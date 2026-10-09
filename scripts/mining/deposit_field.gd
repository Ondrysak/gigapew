class_name DepositField
extends Node3D

## Mineral deposits embedded in the stage's perimeter walls and obstacles,
## plus the resource nuggets they (and boss drops) spill. Placement probes the
## real colliders with rays, so any world scene with a PlayerSpawn marker,
## an Obstacles node of StaticBody3Ds and walls on the play_area edges works.

signal deposit_broken(definition: DepositDefinition, position: Vector3)

@export_group("Deposits")
@export var deposit_types: Array[DepositDefinition] = []
## Deposit cap per stage = play area x density, clamped to min/max.
@export var deposits_per_square_meter := 0.004
@export var min_deposits := 16
@export var max_deposits := 26
@export var respawn_interval_min := 20.0
@export var respawn_interval_max := 30.0
## No deposit spawns this close to the PlayerSpawn marker.
@export var spawn_clearance := 8.0
## Respawns never pop in this close to the player.
@export var respawn_player_clearance := 8.0
@export var min_spacing := 5.5
## Share of placements on perimeter walls (the rest go on obstacles).
@export_range(0.0, 1.0) var wall_share := 0.6

@export_group("Effects")
## Chips and break bursts; the material should use vertex color as albedo.
@export var chip_mesh: Mesh
@export var chip_material: Material
@export var chip_emitters := 6
@export var burst_emitters := 4
## Floating "+N Name" popups on break.
@export var show_popups := true
@export var popup_font_size := 64
@export var break_sound: AudioStream
@export var collect_sound: AudioStream
@export var sound_bus: StringName = &"SFX"

@export_group("Pickups")
## Used for resources without a DepositDefinition pickup_mesh (boss drops).
@export var default_pickup_mesh: Mesh
## Should honour per-instance color (vertex_color_use_as_albedo).
@export var pickup_material: Material
@export var max_pickups_per_resource := 160
@export var max_nuggets_per_drop := 10
@export var pickup_rest_height := 0.28
@export var pickup_gravity := 18.0
@export var magnet_delay := 0.45
## Nuggets attract within run_state.pickup_radius + this.
@export var magnet_bonus_radius := 1.5
## Stray nuggets fly to the player regardless of distance after this long.
@export var always_attract_after := 30.0
@export var collect_distance := 0.7
@export var initial_attract_speed := 4.0
@export var attract_acceleration := 50.0
@export var max_attract_speed := 32.0

const PROBE_OUT := 1.6
const PROBE_IN := 0.5
const POPUP_TIME := 1.1

var _world: Node3D
var _area := Rect2()
var _player: ArenaPlayer
var _run_state: RunState
var _rng := RandomNumberGenerator.new()
var _query: PhysicsRayQueryParameters3D
var _clearance_box := BoxShape3D.new()
var _clearance_query := PhysicsShapeQueryParameters3D.new()
var _populate_delay := 2
var _cap := 0
var _respawn_timer := 0.0
var _spawn_point := Vector3.ZERO
var _alive: Array[MineralDeposit] = []
var _placed: Dictionary = {}
# Authored encounter formations do not consume random caps or respawn budgets.
var _reserved_centers := PackedVector3Array()
var _reserved_radii := PackedFloat32Array()

# Obstacle footprints (world X/Z), read like Horde does.
var _obstacle_body: Array[StaticBody3D] = []
var _obstacle_center := PackedVector2Array()
var _obstacle_half := PackedVector2Array()
var _obstacle_circle := PackedByteArray()
var _obstacle_bottom := PackedFloat32Array()
var _obstacle_top := PackedFloat32Array()

# Result of the last successful probe.
var _probe_from := Vector3.ZERO
var _probe_to := Vector3.ZERO
var _probe_normal := Vector3.ZERO
var _probe_body: Object

var _sets: Dictionary = {}
var _set_list: Array[ResourcePickupSet] = []
var _pickup_style: Dictionary = {}

var _chips: Array[CPUParticles3D] = []
var _bursts: Array[CPUParticles3D] = []
var _next_chip := 0
var _next_burst := 0
var _chip_cooldown := 0.0
var _popups: Array[Label3D] = []
var _popup_age := PackedFloat32Array()
var _popup_origin := PackedVector3Array()
var _next_popup := 0
var _break_voice: AudioStreamPlayer3D
var _collect_voice: AudioStreamPlayer
var _collect_cooldown := 0.0

## Call once after the world scene is in the tree. Deposits appear after the
## first physics frames, once the world colliders are queryable.
func setup(world: Node3D, play_area: Rect2, player: ArenaPlayer, run_state: RunState) -> void:
	_world = world
	_area = play_area
	_player = player
	_run_state = run_state
	_rng.randomize()
	_cap = clampi(roundi(play_area.get_area() * deposits_per_square_meter), min_deposits, max_deposits)
	_respawn_timer = _rng.randf_range(respawn_interval_min, respawn_interval_max)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1, [player.get_rid()])
	_clearance_query.shape = _clearance_box
	_clearance_query.collision_mask = 1
	for definition in deposit_types:
		if definition == null or definition.resource == null:
			continue
		_placed[definition] = 0
		if definition.pickup_mesh != null and not _pickup_style.has(definition.resource):
			_pickup_style[definition.resource] = definition
		_set_for(definition.resource)
	_build_effects()

## Spills `amount` of a resource as nuggets at a world position (boss drops).
func drop(definition: ResourceDefinition, amount: int, at: Vector3) -> void:
	_spill(definition, amount, at, Vector3.ZERO)

## Credits every nugget still on the floor at once (e.g. on stage clear).
func collect_all() -> void:
	for pickups in _set_list:
		var total := pickups.take_all()
		pickups.flush()
		if total > 0 and _run_state != null:
			_run_state.add_resource(pickups.definition, total)

## Live deposits (for HUD or debugging).
func deposit_count() -> int:
	return _alive.size()

## Reserve before the delayed random population; the reservation survives depletion.
func reserve_authored_space(center: Vector3, radius: float) -> void:
	_reserved_centers.append(center)
	_reserved_radii.append(maxf(0.0, radius))

## A real, permanent formation on an authored collider face, with normal conserved loot.
## Returns null until physics can prove its support and floor/walk-up clearance.
func create_authored_deposit(definition: DepositDefinition, point: Vector3, normal: Vector3, support: StaticBody3D, seed: int) -> MineralDeposit:
	if _world == null or definition == null or definition.resource == null or support == null:
		return null
	normal.y = 0.0
	if normal.length_squared() < 0.5:
		return null
	normal = normal.normalized()
	var space := get_world_3d().direct_space_state
	if not _formation_clear(space, point, normal, definition.formation_size, support):
		return null
	var deposit := MineralDeposit.new()
	deposit.name = "AuthoredDefenseVein"
	deposit.configure(definition, seed, 1.0)
	add_child(deposit)
	deposit.global_transform = Transform3D(Basis(Vector3.UP.cross(normal), Vector3.UP, normal), point)
	deposit.struck.connect(_on_deposit_struck)
	deposit.fragment_mined.connect(_on_fragment_mined)
	deposit.depleted.connect(_on_authored_depleted)
	return deposit

func _on_authored_depleted(deposit: MineralDeposit) -> void:
	# Keep the depleted object for encounter progress; no random respawn or second payout.
	deposit_broken.emit(deposit.definition, deposit.last_hit_position)

func _physics_process(delta: float) -> void:
	if _world == null:
		return
	if _populate_delay > 0:
		_populate_delay -= 1
		if _populate_delay == 0:
			_populate()
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = _rng.randf_range(respawn_interval_min, respawn_interval_max)
		if _alive.size() < _cap:
			var definition := _pick_type()
			if definition != null:
				_try_place(definition, 16, true)
	_chip_cooldown = maxf(0.0, _chip_cooldown - delta)
	_collect_cooldown = maxf(0.0, _collect_cooldown - delta)
	_step_pickups(delta)

func _process(delta: float) -> void:
	for index in _popups.size():
		var label := _popups[index]
		if not label.visible:
			continue
		var age := _popup_age[index] + delta
		_popup_age[index] = age
		if age >= POPUP_TIME:
			label.hide()
			continue
		label.global_position = _popup_origin[index] + Vector3.UP * (0.4 + age * 1.1)
		label.modulate.a = clampf((POPUP_TIME - age) * 3.0, 0.0, 1.0)
		label.outline_modulate.a = label.modulate.a

# ---------------------------------------------------------------- pickups

func _step_pickups(delta: float) -> void:
	var can_collect := _player != null and is_instance_valid(_player) and _player.active
	var target := _player.global_position if can_collect else Vector3.ZERO
	var radius := (_run_state.pickup_radius if _run_state != null else 3.0) + magnet_bonus_radius
	var bounds := _area.grow(-0.3)
	for pickups in _set_list:
		if pickups.count == 0:
			pickups.flush()
			continue
		var collected := pickups.step(delta, target, radius * radius, can_collect, self, bounds)
		pickups.flush()
		if collected > 0:
			if _run_state != null:
				_run_state.add_resource(pickups.definition, collected)
			if _collect_cooldown == 0.0:
				_collect_cooldown = 0.05
				_collect_voice.pitch_scale = _rng.randf_range(0.92, 1.12)
				_collect_voice.play()

func _set_for(definition: ResourceDefinition) -> ResourcePickupSet:
	var pickups: ResourcePickupSet = _sets.get(definition)
	if pickups != null:
		return pickups
	var mesh := default_pickup_mesh
	var size := 1.0
	var style: DepositDefinition = _pickup_style.get(definition)
	if style != null:
		mesh = style.pickup_mesh
		size = style.pickup_scale
	pickups = ResourcePickupSet.new()
	pickups.build(self, definition, mesh, pickup_material, max_pickups_per_resource, size)
	_sets[definition] = pickups
	_set_list.append(pickups)
	return pickups

func _spill(definition: ResourceDefinition, amount: int, at: Vector3, normal: Vector3) -> void:
	if definition == null or amount <= 0:
		return
	var pickups := _set_for(definition)
	var nuggets := clampi(amount, 1, maxi(1, max_nuggets_per_drop))
	var share := floori(float(amount) / float(nuggets))
	var extra := amount % nuggets
	var overflow := 0
	for nugget in nuggets:
		var value := share + (1 if nugget < extra else 0)
		var angle := _rng.randf() * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		if normal != Vector3.ZERO:
			direction = (Vector3(normal.x, 0.0, normal.z).normalized() + direction * 0.75).normalized()
		var velocity := direction * _rng.randf_range(1.6, 3.8) + Vector3.UP * _rng.randf_range(3.5, 6.0)
		if pickups.add(at, velocity, value, _rng.randf() * TAU) < 0:
			overflow += value
	# A full pool never loses resources.
	if overflow > 0 and _run_state != null:
		_run_state.add_resource(definition, overflow)

# ---------------------------------------------------------------- placement

func _populate() -> void:
	var spawn := _world.get_node_or_null("PlayerSpawn") as Node3D
	_spawn_point = spawn.global_position if spawn != null else Vector3(_area.get_center().x, 0.0, _area.get_center().y)
	_read_obstacles(_world.get_node_or_null("Obstacles"))
	for definition in deposit_types:
		if definition == null or definition.resource == null:
			continue
		for _index in definition.guaranteed:
			_try_place(definition, 160, false, true)
	var attempts := _cap * 3
	while _alive.size() < _cap and attempts > 0:
		attempts -= 1
		var definition := _pick_type()
		if definition == null:
			break
		_try_place(definition, 24, false)

func _read_obstacles(root: Node) -> void:
	if root == null:
		return
	for body in root.get_children():
		if not body is StaticBody3D:
			continue
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider == null or collider.shape == null:
				continue
			var world := (body as Node3D).global_transform * collider.transform
			var half_height := 0.0
			var half := Vector2.ZERO
			var circle := 0
			if collider.shape is CylinderShape3D:
				var cylinder := collider.shape as CylinderShape3D
				var radius := cylinder.radius * world.basis.get_scale().x
				half = Vector2(radius, radius)
				half_height = cylinder.height * 0.5 * world.basis.get_scale().y
				circle = 1
			elif collider.shape is BoxShape3D:
				# Yaw is a multiple of 90 degrees: project the box extents onto X/Z.
				var extents := (collider.shape as BoxShape3D).size * 0.5
				var x_axis := world.basis.x * extents.x
				var z_axis := world.basis.z * extents.z
				half = Vector2(absf(x_axis.x) + absf(z_axis.x), absf(x_axis.z) + absf(z_axis.z))
				half_height = absf((world.basis.y * extents.y).y)
			else:
				continue
			_obstacle_body.append(body)
			_obstacle_center.append(Vector2(world.origin.x, world.origin.z))
			_obstacle_half.append(half)
			_obstacle_circle.append(circle)
			_obstacle_bottom.append(world.origin.y - half_height)
			_obstacle_top.append(world.origin.y + half_height)

func _pick_type() -> DepositDefinition:
	var total := 0.0
	for definition in deposit_types:
		if _can_place_more(definition):
			total += maxf(0.0, definition.weight)
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for definition in deposit_types:
		if not _can_place_more(definition):
			continue
		roll -= maxf(0.0, definition.weight)
		if roll < 0.0:
			return definition
	return null

func _can_place_more(definition: DepositDefinition) -> bool:
	if definition == null or definition.resource == null or not _placed.has(definition):
		return false
	return definition.max_per_stage <= 0 or int(_placed[definition]) < definition.max_per_stage

func _try_place(definition: DepositDefinition, attempts: int, respawn: bool, wall_only: bool = false) -> bool:
	if not _can_place_more(definition) or _alive.size() >= _cap:
		return false
	var space := get_world_3d().direct_space_state
	for _attempt in attempts:
		var size_scale := _rng.randf_range(0.95, 1.08)
		var bounds := definition.formation_size * size_scale
		var on_wall := wall_only or _obstacle_body.is_empty() or _rng.randf() < wall_share
		if not (_wall_probe(definition, bounds) if on_wall else _obstacle_probe(definition, bounds)):
			continue
		if _is_inside_obstacle(Vector2(_probe_from.x, _probe_from.z)):
			continue
		_query.from = _probe_from
		_query.to = _probe_to
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		if collider is MineralDeposit or not collider is StaticBody3D:
			continue
		if _probe_body != null and collider != _probe_body:
			continue
		var normal: Vector3 = hit["normal"]
		normal.y = 0.0
		if normal.length_squared() < 0.5 or normal.normalized().dot(_probe_normal) < 0.7:
			continue
		normal = normal.normalized()
		var point: Vector3 = hit["position"]
		if not _is_clear(point, bounds, respawn):
			continue
		if not _formation_clear(space, point, normal, bounds, collider as StaticBody3D):
			continue
		_spawn_deposit(definition, point, normal, size_scale)
		return true
	return false

func _wall_probe(definition: DepositDefinition, bounds: Vector3) -> bool:
	var width := _area.size.x
	var depth := _area.size.y
	var along := _rng.randf() * (width + depth) * 2.0
	var y := _rng.randf_range(maxf(definition.min_height, bounds.y * 0.5 + 0.15), maxf(definition.max_height, bounds.y * 0.5 + 0.15))
	var margin := bounds.x * 0.5 + bounds.z + 0.5
	if width <= margin * 2.0 or depth <= margin * 2.0:
		return false
	var surface: Vector3
	if along < width * 2.0:
		var x := _area.position.x + clampf(fmod(along, width), margin, width - margin)
		var north := along < width
		surface = Vector3(x, y, _area.position.y if north else _area.end.y)
		_probe_normal = Vector3.BACK if north else Vector3.FORWARD
	else:
		along -= width * 2.0
		var z := _area.position.y + clampf(fmod(along, depth), margin, depth - margin)
		var west := along < depth
		surface = Vector3(_area.position.x if west else _area.end.x, y, z)
		_probe_normal = Vector3.RIGHT if west else Vector3.LEFT
	_probe_from = surface + _probe_normal * PROBE_OUT
	_probe_to = surface - _probe_normal * PROBE_IN
	_probe_body = null
	return true

func _obstacle_probe(definition: DepositDefinition, bounds: Vector3) -> bool:
	var index := _rng.randi_range(0, _obstacle_body.size() - 1)
	var low := maxf(definition.min_height, _obstacle_bottom[index] + bounds.y * 0.5 + 0.15)
	var high := minf(definition.max_height, _obstacle_top[index] - bounds.y * 0.5 - 0.15)
	if high < low:
		return false
	var center := _obstacle_center[index]
	var half := _obstacle_half[index]
	var surface := Vector2.ZERO
	# Broad flat faces only: pillars and narrow cover are not formation anchors.
	if _obstacle_circle[index] == 1:
		return false
	var margin := bounds.x * 0.5 + 0.4
	var x_face := half.x >= margin
	var z_face := half.y >= margin
	if not x_face and not z_face:
		return false
	if x_face and (not z_face or _rng.randf() < half.x / (half.x + half.y)):
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		surface = Vector2(center.x + _rng.randf_range(-half.x + margin, half.x - margin), center.y + half.y * side)
		_probe_normal = Vector3(0.0, 0.0, side)
	else:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		surface = Vector2(center.x + half.x * side, center.y + _rng.randf_range(-half.y + margin, half.y - margin))
		_probe_normal = Vector3(side, 0.0, 0.0)
	var y := _rng.randf_range(low, high)
	var point := Vector3(surface.x, y, surface.y)
	_probe_from = point + _probe_normal * PROBE_OUT
	_probe_to = Vector3(center.x, y, center.y)
	_probe_body = _obstacle_body[index]
	return true

func _is_inside_obstacle(xz: Vector2) -> bool:
	if not _area.grow(-0.2).has_point(xz):
		return true
	for index in _obstacle_center.size():
		var delta := xz - _obstacle_center[index]
		var half := _obstacle_half[index]
		if _obstacle_circle[index] == 1:
			if delta.length() < half.x + 0.2:
				return true
		elif absf(delta.x) < half.x + 0.2 and absf(delta.y) < half.y + 0.2:
			return true
	return false

func _is_clear(point: Vector3, bounds: Vector3, respawn: bool) -> bool:
	var xz := Vector2(point.x, point.z)
	var radius := Vector2(bounds.x * 0.5, bounds.z).length()
	if xz.distance_to(Vector2(_spawn_point.x, _spawn_point.z)) < spawn_clearance + radius:
		return false
	if respawn and _player != null and is_instance_valid(_player):
		var player := _player.global_position
		if xz.distance_to(Vector2(player.x, player.z)) < respawn_player_clearance + radius:
			return false
	for index in _reserved_centers.size():
		if point.distance_to(_reserved_centers[index]) < radius + _reserved_radii[index]:
			return false
	for deposit in _alive:
		var other_radius := Vector2(deposit.formation_size.x * 0.5, deposit.formation_size.z).length()
		if deposit.global_position.distance_to(point) < maxf(min_spacing, radius + other_radius + 0.4):
			return false
	return true

func _formation_clear(space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3, bounds: Vector3, support: StaticBody3D) -> bool:
	var right := Vector3.UP.cross(normal)
	# The entire width and height must sit against the same broad wall face.
	for x in [-0.48, 0.0, 0.48]:
		for y in [-0.46, 0.46]:
			var sample: Vector3 = point + right * bounds.x * x + Vector3.UP * bounds.y * y
			_query.from = sample + normal * PROBE_OUT
			_query.to = sample - normal * PROBE_IN
			var hit := space.intersect_ray(_query)
			if hit.is_empty() or hit["collider"] != support:
				return false
			var face_normal: Vector3 = hit["normal"]
			var face_point: Vector3 = hit["position"]
			if face_normal.dot(normal) < 0.95 or absf((face_point - point).dot(normal)) > 0.15:
				return false
	# Check floor clearance under all three columns, including outward tips.
	for x in [-0.45, 0.0, 0.45]:
		var bottom: Vector3 = point + right * bounds.x * x + normal * bounds.z * 0.6 - Vector3.UP * bounds.y * 0.5
		_query.from = bottom + Vector3.UP * 0.25
		_query.to = bottom - Vector3.UP * 4.0
		var floor_hit := space.intersect_ray(_query)
		if floor_hit.is_empty():
			return false
		var floor_point: Vector3 = floor_hit["position"]
		if floor_point.y > bottom.y - 0.06:
			return false
	# Reserve real walkable room beyond the whole deposit, not just its origin.
	_clearance_box.size = Vector3(bounds.x + 0.3, bounds.y - 0.12, bounds.z + 1.25)
	_clearance_query.transform = Transform3D(Basis(right, Vector3.UP, normal), point + normal * (0.18 + _clearance_box.size.z * 0.5))
	_clearance_query.exclude = [_player.get_rid(), support.get_rid()]
	return space.intersect_shape(_clearance_query, 1).is_empty()

func _spawn_deposit(definition: DepositDefinition, point: Vector3, normal: Vector3, size_scale: float) -> void:
	var deposit := MineralDeposit.new()
	deposit.name = "%sDeposit" % String(definition.resource.id).capitalize()
	deposit.configure(definition, _rng.randi(), size_scale)
	add_child(deposit)
	# Procedural geometry protrudes along +Z, out of the surface.
	var up := Vector3.UP
	deposit.global_transform = Transform3D(Basis(up.cross(normal), up, normal), point)
	deposit.struck.connect(_on_deposit_struck)
	deposit.fragment_mined.connect(_on_fragment_mined)
	deposit.depleted.connect(_on_deposit_depleted)
	_alive.append(deposit)
	_placed[definition] = int(_placed[definition]) + 1

func _on_deposit_struck(deposit: MineralDeposit) -> void:
	if _chip_cooldown > 0.0 or _chips.is_empty():
		return
	_chip_cooldown = 0.06
	var emitter := _chips[_next_chip]
	_next_chip = (_next_chip + 1) % _chips.size()
	_fire_emitter(emitter, deposit.last_hit_position, deposit.global_basis.z, deposit.definition.resource.color)

func _on_fragment_mined(deposit: MineralDeposit, amount: int, center: Vector3) -> void:
	var definition := deposit.definition
	var normal := deposit.global_basis.z
	_spill(definition.resource, amount, center, normal)
	if not _bursts.is_empty():
		_fire_emitter(_bursts[_next_burst], center, normal, definition.resource.color)
		_next_burst = (_next_burst + 1) % _bursts.size()
	_break_voice.global_position = center
	_break_voice.pitch_scale = _rng.randf_range(0.9, 1.1)
	_break_voice.play()
	if amount > 0 and show_popups and not _popups.is_empty():
		_show_popup(center, "+%d %s" % [floori(amount * (_run_state.resource_multiplier if _run_state != null else 1.0)), definition.resource.display_name], definition.resource.color)

func _on_deposit_depleted(deposit: MineralDeposit) -> void:
	var definition := deposit.definition
	var center := deposit.last_hit_position
	_alive.erase(deposit)
	deposit.queue_free()
	deposit_broken.emit(definition, center)

# ---------------------------------------------------------------- effects

func _build_effects() -> void:
	for _index in chip_emitters:
		_chips.append(_make_emitter(7, 0.45, 2.0, 4.5, 55.0, 0.7))
	for _index in burst_emitters:
		_bursts.append(_make_emitter(30, 0.8, 3.0, 7.5, 70.0, 1.3))
	if show_popups:
		for _index in 4:
			var label := Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.font_size = popup_font_size
			label.outline_size = 12
			label.outline_modulate = Color(0.02, 0.02, 0.03, 1.0)
			label.pixel_size = 0.006
			add_child(label)
			label.top_level = true
			label.hide()
			_popups.append(label)
		_popup_age.resize(_popups.size())
		_popup_origin.resize(_popups.size())
	_break_voice = AudioStreamPlayer3D.new()
	_break_voice.stream = break_sound if break_sound != null else MiningSynth.cue(&"crunch")
	_break_voice.bus = sound_bus
	_break_voice.max_polyphony = 3
	_break_voice.unit_size = 12.0
	add_child(_break_voice)
	_collect_voice = AudioStreamPlayer.new()
	_collect_voice.stream = collect_sound if collect_sound != null else MiningSynth.cue(&"tink")
	_collect_voice.bus = sound_bus
	_collect_voice.volume_db = -12.0
	_collect_voice.max_polyphony = 4
	add_child(_collect_voice)

func _make_emitter(amount: int, lifetime: float, speed_min: float, speed_max: float, spread: float, size: float) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.one_shot = true
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.explosiveness = 1.0
	emitter.local_coords = false
	emitter.mesh = chip_mesh
	emitter.material_override = chip_material
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.direction = Vector3(0.0, 0.0, 1.0)
	emitter.spread = spread
	emitter.initial_velocity_min = speed_min
	emitter.initial_velocity_max = speed_max
	emitter.gravity = Vector3(0.0, -14.0, 0.0)
	emitter.angular_velocity_min = -360.0
	emitter.angular_velocity_max = 360.0
	emitter.scale_amount_min = size * 0.6
	emitter.scale_amount_max = size
	add_child(emitter)
	emitter.top_level = true
	return emitter

func _fire_emitter(emitter: CPUParticles3D, at: Vector3, normal: Vector3, color: Color) -> void:
	var up := Vector3.RIGHT if absf(normal.y) > 0.9 else Vector3.UP
	emitter.global_transform = Transform3D(Basis.looking_at(-normal, up), at)
	emitter.color = color
	emitter.restart()

func _show_popup(at: Vector3, text: String, color: Color) -> void:
	var index := _next_popup
	_next_popup = (_next_popup + 1) % _popups.size()
	var label := _popups[index]
	label.text = text
	label.modulate = color
	label.outline_modulate.a = 1.0
	_popup_age[index] = 0.0
	_popup_origin[index] = at
	label.global_position = at + Vector3.UP * 0.4
	label.show()
