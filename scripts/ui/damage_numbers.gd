class_name DamageNumbers
extends CanvasLayer

## A fixed display pool: no nodes or tweens are created while fighting.
const POOL_SIZE := 64
const LIFETIME := 0.78
const MERGE_WINDOW := 0.12
const MERGE_DISTANCE_SQUARED := 0.64

var _camera: Camera3D
var _horde: Horde
var _surface: Control
var _labels: Array[Label] = []
var _world := PackedVector3Array()
var _life := PackedFloat32Array()
var _age := PackedFloat32Array()
var _amount := PackedFloat32Array()
var _kind := PackedInt32Array()
var _critical := PackedByteArray()
var _killed := PackedByteArray()

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
	# Noninteractive foreground labels; reserved regions keep HUD text clear.
	layer = 1
	_surface = Control.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)
	_world.resize(POOL_SIZE)
	_life.resize(POOL_SIZE)
	_age.resize(POOL_SIZE)
	_amount.resize(POOL_SIZE)
	_kind.resize(POOL_SIZE)
	_critical.resize(POOL_SIZE)
	_killed.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(180.0, 44.0)
		label.add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.035, 0.95))
		label.add_theme_constant_override("outline_size", 4)
		label.hide()
		_surface.add_child(label)
		_labels.append(label)

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
		if _age[i] <= MERGE_WINDOW and _kind[i] == damage_type and bool(_critical[i]) == critical and bool(_killed[i]) == killed and _world[i].distance_squared_to(at) <= MERGE_DISTANCE_SQUARED:
			_amount[i] += amount
			_update_label(i)
			return
		# Preserve fresh finishers/criticals over low-priority crowd ticks.
		if (critical or killed or (_critical[i] == 0 and _killed[i] == 0)) and _life[i] < oldest:
			oldest = _life[i]
			replace = i
	if slot < 0:
		slot = replace
	if slot < 0:
		return
	_world[slot] = at
	_life[slot] = LIFETIME
	_age[slot] = 0.0
	_amount[slot] = amount
	_kind[slot] = damage_type
	_critical[slot] = 1 if critical else 0
	_killed[slot] = 1 if killed else 0
	_update_label(slot)
	_place_label(slot, viewport_size)

func _update_label(slot: int) -> void:
	var number := "%.1f" % _amount[slot] if _amount[slot] < 1.0 else str(roundi(_amount[slot]))
	var prefix := ""
	if _critical[slot] != 0:
		prefix = "CRIT "
	if _killed[slot] != 0:
		prefix += "DOWN "
	var label := _labels[slot]
	label.text = prefix + number
	label.add_theme_color_override("font_color", DamageType.color(_kind[slot]))
	label.add_theme_font_size_override("font_size", 27 if _critical[slot] != 0 else (25 if _killed[slot] != 0 else 21))

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
	point += Vector2(float(slot % 3 - 1) * 18.0, -28.0 - _age[slot] * 48.0)
	var center := viewport_size * 0.5
	# Leave the aiming cross and hit/combo confirmations unobstructed.
	if absf(point.x - center.x) < 115.0 and point.y > center.y - 45.0 and point.y < center.y + 125.0:
		point.x = center.x + (145.0 if point.x >= center.x else -145.0)
	# HUD headers, bottom weapons/ability, and lower corner status/radar panels.
	var safe := point.x >= 95.0 and point.x <= viewport_size.x - 95.0 and point.y >= 190.0 and point.y <= viewport_size.y - 115.0
	if point.y > viewport_size.y - 250.0 and (point.x < 365.0 or point.x > viewport_size.x - 360.0):
		safe = false
	label.visible = safe
	if not safe:
		return
	label.position = point - Vector2(90.0, 22.0)
	label.modulate.a = minf(1.0, _life[slot] / 0.22)

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
		if _life[i] <= 0.0:
			_labels[i].hide()
		else:
			_place_label(i, viewport_size)
