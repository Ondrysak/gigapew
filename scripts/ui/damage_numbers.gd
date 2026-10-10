class_name DamageNumbers
extends CanvasLayer

## A fixed display pool: no nodes or tweens are created while fighting.
## Hits of one damage type landing close together within MERGE_WINDOW add up
## into one number; new numbers that would overlap a live one stack above it.
const POOL_SIZE := 64
const LIFETIME := 0.78
const MERGE_WINDOW := 0.2
const MERGE_DISTANCE_SQUARED := 0.81
const LABEL_SIZE := Vector2(180.0, 44.0)
const RISE_SPEED := 56.0
## Screen-space footprint used to keep numbers apart.
const STACK_WIDTH := 70.0
const STACK_HEIGHT := 28.0
const STACK_LIMIT := 5
const POP_TIME := 0.14
const CRIT_ICON_SIZE := 16.0

var _camera: Camera3D
var _horde: Horde
var _surface: Control
var _labels: Array[Label] = []
var _icons: Array[TextureRect] = []
var _world := PackedVector3Array()
var _offset := PackedVector2Array()
var _life := PackedFloat32Array()
var _age := PackedFloat32Array()
var _pop := PackedFloat32Array()
var _amount := PackedFloat32Array()
var _kind := PackedInt32Array()
var _critical := PackedByteArray()
var _killed := PackedByteArray()
## Set by _spawn_offset: label blocking every stack row, or -1.
var _crowded := -1

func setup(camera: Camera3D, horde: Horde) -> void:
	_disconnect_horde()
	_camera = camera
	_horde = horde
	_ensure_pool()
	_reset_pool()
	if is_instance_valid(_horde):
		_horde.damage_reported.connect(_on_damage)

func _ensure_pool() -> void:
	if _surface != null:
		return
	# Noninteractive foreground labels; reserved regions keep HUD readouts clear.
	layer = 1
	_surface = Control.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)
	_life.resize(POOL_SIZE)
	_age.resize(POOL_SIZE)
	_pop.resize(POOL_SIZE)
	_amount.resize(POOL_SIZE)
	_world.resize(POOL_SIZE)
	_offset.resize(POOL_SIZE)
	_kind.resize(POOL_SIZE)
	_critical.resize(POOL_SIZE)
	_killed.resize(POOL_SIZE)
	var crit_icon := GameIcons.lookup(&"hud", &"crit")
	for i in POOL_SIZE:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = LABEL_SIZE
		label.pivot_offset = LABEL_SIZE * 0.5
		label.add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.035, 0.95))
		label.add_theme_constant_override("outline_size", 5)
		label.hide()
		var icon := GameIcons.rect(crit_icon, CRIT_ICON_SIZE)
		icon.size = Vector2(CRIT_ICON_SIZE, CRIT_ICON_SIZE)
		icon.hide()
		label.add_child(icon)
		_surface.add_child(label)
		_labels.append(label)
		_icons.append(icon)

func _disconnect_horde() -> void:
	if is_instance_valid(_horde) and _horde.damage_reported.is_connected(_on_damage):
		_horde.damage_reported.disconnect(_on_damage)
	_horde = null

func _exit_tree() -> void:
	_disconnect_horde()
	_camera = null

func _reset_pool() -> void:
	_life.fill(0.0)
	for label in _labels:
		label.hide()

func _on_damage(at: Vector3, amount: float, damage_type: int, critical: bool, killed: bool) -> void:
	if amount <= 0.0 or not is_instance_valid(_camera) or _camera.is_position_behind(at):
		return
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var projected := _camera.unproject_position(at)
	if not Rect2(Vector2.ZERO, viewport_size).has_point(projected):
		return
	var slot := -1
	var replace := -1
	var oldest := INF
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			if slot < 0:
				slot = i
			continue
		# Rapid hits on one spot read as one growing number; a crit or kill
		# landing in the window upgrades it instead of spawning a second label.
		if _age[i] <= MERGE_WINDOW and _kind[i] == damage_type and _world[i].distance_squared_to(at) <= MERGE_DISTANCE_SQUARED:
			_merge(i, amount, critical, killed)
			return
		# Preserve fresh finishers/criticals over low-priority crowd ticks.
		if (critical or killed or (_critical[i] == 0 and _killed[i] == 0)) and _life[i] < oldest:
			oldest = _life[i]
			replace = i
	if slot < 0:
		slot = replace
	if slot < 0:
		return
	var offset := _spawn_offset(projected, slot, viewport_size)
	# No free row nearby: fold the hit into the crowding number rather than
	# drawing over it, as long as it is the same damage type.
	if _crowded >= 0 and _kind[_crowded] == damage_type:
		_merge(_crowded, amount, critical, killed)
		return
	_life[slot] = 0.0
	_labels[slot].hide()
	_world[slot] = at
	_life[slot] = LIFETIME
	_age[slot] = 0.0
	_pop[slot] = POP_TIME
	_amount[slot] = amount
	_kind[slot] = damage_type
	_critical[slot] = 1 if critical else 0
	_killed[slot] = 1 if killed else 0
	_offset[slot] = offset
	_update_label(slot)
	_place_label(slot, viewport_size)

func _merge(slot: int, amount: float, critical: bool, killed: bool) -> void:
	_amount[slot] += amount
	_critical[slot] = 1 if critical or _critical[slot] != 0 else 0
	_killed[slot] = 1 if killed or _killed[slot] != 0 else 0
	_pop[slot] = POP_TIME
	_update_label(slot)

## Screen offset fixed at spawn: steps aside from the crosshair and lifts a
## new number above live numbers it would overlap. Sets _crowded to the
## blocking label when every row up to STACK_LIMIT is taken, else -1.
func _spawn_offset(projected: Vector2, slot: int, viewport_size: Vector2) -> Vector2:
	var offset := Vector2.ZERO
	_crowded = -1
	for attempt in STACK_LIMIT:
		var point := projected + offset + Vector2(0.0, -28.0)
		offset.x = _avoid_crosshair(point, viewport_size).x - projected.x
		point.x = projected.x + offset.x
		_crowded = -1
		for j in POOL_SIZE:
			if j == slot or _life[j] <= 0.0 or not _labels[j].visible:
				continue
			var center := _labels[j].position + LABEL_SIZE * 0.5
			if absf(center.x - point.x) < STACK_WIDTH and absf(center.y - point.y) < STACK_HEIGHT:
				_crowded = j
				break
		if _crowded < 0:
			break
		if attempt < STACK_LIMIT - 1:
			offset.y -= STACK_HEIGHT
	return offset

## Leave the aiming cross and hit/combo confirmations unobstructed.
func _avoid_crosshair(point: Vector2, viewport_size: Vector2) -> Vector2:
	var center := viewport_size * 0.5
	if absf(point.x - center.x) < 115.0 and point.y > center.y - 45.0 and point.y < center.y + 125.0:
		point.x = center.x + (145.0 if point.x >= center.x else -145.0)
	return point

func _update_label(slot: int) -> void:
	var number := "%.1f" % _amount[slot] if _amount[slot] < 1.0 else str(roundi(_amount[slot]))
	var critical := _critical[slot] != 0
	var font_size := 27 if critical else (25 if _killed[slot] != 0 else 21)
	var label := _labels[slot]
	label.text = number
	label.add_theme_color_override("font_color", DamageType.color(_kind[slot]))
	label.add_theme_font_size_override("font_size", font_size)
	var icon := _icons[slot]
	icon.visible = critical
	if critical:
		var width := label.get_theme_font("font").get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		icon.position = Vector2((LABEL_SIZE.x - width) * 0.5 - CRIT_ICON_SIZE - 3.0, (LABEL_SIZE.y - CRIT_ICON_SIZE) * 0.5)

func _place_label(slot: int, viewport_size: Vector2) -> void:
	var label := _labels[slot]
	var at := _world[slot]
	if _camera.is_position_behind(at):
		label.hide()
		return
	var point := _camera.unproject_position(at)
	# Cull at the original contact point, not at a clamped fake screen target.
	if not Rect2(Vector2.ZERO, viewport_size).has_point(point):
		label.hide()
		return
	point = _avoid_crosshair(point + _offset[slot] + Vector2(0.0, -28.0 - _age[slot] * RISE_SPEED), viewport_size)
	var safe := _clear_of_hud(point, viewport_size)
	label.visible = safe
	if not safe:
		return
	label.position = point - LABEL_SIZE * 0.5
	label.modulate.a = minf(1.0, _life[slot] / 0.22)
	label.scale = Vector2.ONE * (1.0 + 0.35 * maxf(0.0, _pop[slot]) / POP_TIME)

## False inside the HUD's panels (see hud.tscn): top bar, stage/threat/radar
## corners, vitals, ability slot, hand slots and the controls line.
func _clear_of_hud(point: Vector2, viewport_size: Vector2) -> bool:
	if point.x < 40.0 or point.x > viewport_size.x - 40.0 or point.y < 104.0 or point.y > viewport_size.y - 60.0:
		return false
	if point.y < 150.0 and point.x < 440.0:
		return false
	if point.y >= 148.0 and point.y < 402.0 and point.x < 340.0:
		return false
	if point.y < 300.0 and point.x > viewport_size.x - 230.0:
		return false
	if point.y > viewport_size.y - 160.0 and point.x < 390.0:
		return false
	if point.y > viewport_size.y - 225.0 and point.x > viewport_size.x - 470.0:
		return false
	return not (point.y > viewport_size.y - 140.0 and absf(point.x - viewport_size.x * 0.5) < 90.0)

func _process(delta: float) -> void:
	if _surface == null:
		return
	if not is_instance_valid(_camera) or not is_instance_valid(_horde):
		_reset_pool()
		return
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		_life[i] = maxf(0.0, _life[i] - delta)
		_age[i] += delta
		_pop[i] = maxf(0.0, _pop[i] - delta)
		if _life[i] <= 0.0:
			_labels[i].hide()
		else:
			_place_label(i, viewport_size)
