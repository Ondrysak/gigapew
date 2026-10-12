class_name PickupField
extends Node3D

## Pooled, grounded survival loot. All drops share per-kind MultiMesh buffers.
signal collected(kind: StringName, amount: int)

const Geometry = preload("res://scripts/progression/pickup_geometry.gd")
const MAX_TIMED_SUPPLIES := 2
const SUPPLY_SEARCH_ATTEMPTS := 24
const SUPPLY_FALLBACK_ATTEMPTS := 12
const SUPPLY_FALLBACK_DISTANCE := 2.0
const SUPPLY_PATH_STEP := 0.25
const SUPPLY_CLEARANCE := 0.4
const SUPPLY_SEPARATION_SQUARED := 1.44

@export_group("Gems")
@export var gem_mesh: Mesh
## Should honour per-instance color (vertex_color_use_as_albedo).
@export var gem_material: Material
@export_range(1, 10000) var max_gems := 3000
## Only the admitted victim's XP is earned; skipped kills are not banked.
@export_range(1, 1000) var xp_kill_interval := 3
@export var low_value_color := Color(0.2, 0.95, 0.55)
@export var high_value_color := Color(1.0, 0.35, 0.95)
## Gem value reaching the full high_value_color and max scale.
@export var high_value_reference := 25
@export var max_gem_scale := 2.2
@export var gem_height := 0.35

@export_group("Repair")
@export var repair_mesh: Mesh
@export var repair_material: Material
@export var repair_color := Color.WHITE
@export_range(0.0, 1.0) var repair_chance := 0.004
@export var repair_heal := 15
@export var max_repairs := 64
@export var repair_height := 0.45

@export_group("Magnets")
@export var magnet_mesh: Mesh
@export var magnet_material: Material
@export var magnet_color := Color.WHITE
@export var max_magnets := 32
@export var magnet_height := 0.4
@export_range(1, 1000) var magnet_kill_interval := 120

@export_group("Timed Supply")
@export_range(0.1, 300.0) var supply_interval := 50.0
@export_range(0.1, 30.0) var supply_retry_interval := 2.0
@export var supply_min_distance := 5.0
@export var supply_max_distance := 7.0

@export_group("Collection")
@export var collect_distance := 0.6
@export var initial_attract_speed := 3.0
@export var attract_acceleration := 45.0
@export var max_attract_speed := 30.0

var _horde: Horde
var _player: ArenaPlayer
var _run_state: RunState
var _rng := RandomNumberGenerator.new()
var _gems := PickupSet.new()
var _repairs := PickupSet.new()
var _magnets := PickupSet.new()
## Separate pool: ordinary kill drops cannot consume timed supply slots.
var _supplies := PickupSet.new()
var _nonboss_kills := 0
var _supply_elapsed := 0.0

func setup(horde: Horde, player: ArenaPlayer, run_state: RunState) -> void:
	_horde = horde
	_player = player
	_run_state = run_state
	if repair_mesh == null:
		repair_mesh = Geometry.repair()
	if magnet_mesh == null:
		magnet_mesh = Geometry.magnet()
	_gems.build(self, gem_mesh, gem_material, maxi(1, max_gems))
	_repairs.build(self, repair_mesh, repair_material, maxi(0, max_repairs))
	_magnets.build(self, magnet_mesh, magnet_material, maxi(0, max_magnets))
	_supplies.build(self, repair_mesh, repair_material, MAX_TIMED_SUPPLIES)
	horde.enemy_killed.connect(_on_enemy_killed)

func spawn_magnet(at: Vector3) -> bool:
	if _horde == null:
		return false
	return _spawn(_magnets, at, magnet_height, 1, magnet_color)

func spawn_repair(at: Vector3) -> bool:
	if _horde == null:
		return false
	return _spawn(_repairs, at, repair_height, 1, repair_color)

## Snapshot the current pool; later spawns start with zero attraction speed.
func magnetize_xp() -> int:
	var attracted := 0
	for index in range(_gems.count):
		if _gems.speeds[index] == 0.0:
			_gems.speeds[index] = maxf(0.001, initial_attract_speed)
			attracted += 1
	return attracted

func _spawn(pickups: PickupSet, at: Vector3, height: float, value: int, color: Color) -> bool:
	var index := pickups.add(_grounded(at, height), value)
	if index < 0:
		return false
	pickups.write(index, 1.0, color)
	return true

func _grounded(at: Vector3, height: float) -> Vector3:
	return Vector3(at.x, _horde.ground_height(Vector2(at.x, at.z)) + height, at.z)

func _on_enemy_killed(definition: HordeEnemyDefinition, at: Vector3) -> void:
	if _rng.randf() < repair_chance:
		spawn_repair(at)
	if definition.is_boss:
		spawn_magnet(at)
	else:
		_nonboss_kills += 1
		if _nonboss_kills % maxi(1, magnet_kill_interval) == 0:
			spawn_magnet(at)
		if _nonboss_kills % maxi(1, xp_kill_interval) != 0:
			return
	var value := maxi(1, definition.xp_value)
	var gem := _gems.add(_grounded(at, gem_height), value)
	if gem < 0:
		# A saturated pool merges even into homing gems rather than losing XP.
		gem = _gems.nearest(at)
		_gems.merge(gem, value)
	_style_gem(gem)

func _style_gem(index: int) -> void:
	var weight := clampf(float(_gems.values[index] - 1) / float(maxi(1, high_value_reference - 1)), 0.0, 1.0)
	_gems.write(index, lerpf(1.0, max_gem_scale, sqrt(weight)), low_value_color.lerp(high_value_color, weight))

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.active or get_tree().paused:
		return
	var target := _player.global_position
	var radius_squared := _run_state.pickup_radius * _run_state.pickup_radius
	var collected_xp := 0
	var index := 0
	while index < _gems.count:
		if _gems.step(index, target, radius_squared, delta, self):
			collected_xp += _gems.values[index]
			_gems.remove(index)
			if index < _gems.count:
				_style_gem(index)
		else:
			index += 1
	_collect_repairs(_repairs, target)
	_collect_repairs(_supplies, target)
	index = 0
	while index < _magnets.count:
		if _within_reach(_magnets.positions[index], target):
			var attracted := magnetize_xp()
			_remove_styled(_magnets, index, magnet_color)
			collected.emit(&"magnet", attracted)
		else:
			index += 1
	_tick_supply(delta)
	_gems.flush()
	_repairs.flush()
	_magnets.flush()
	_supplies.flush()
	if collected_xp > 0:
		_run_state.add_xp(collected_xp * _run_state.xp_multiplier)

func _within_reach(at: Vector3, target: Vector3) -> bool:
	var offset := target - at
	return offset.x * offset.x + offset.z * offset.z <= collect_distance * collect_distance \
			and absf(offset.y) <= Horde.LEVEL_GAP

func _remove_styled(pickups: PickupSet, index: int, color: Color) -> void:
	pickups.remove(index)
	if index < pickups.count:
		pickups.write(index, 1.0, color)

func _collect_repairs(pickups: PickupSet, target: Vector3) -> void:
	var index := 0
	while index < pickups.count:
		if _within_reach(pickups.positions[index], target) and _player.health < _player.max_health:
			var previous_health := _player.health
			_player.heal(repair_heal)
			var healed := _player.health - previous_health
			if healed > 0:
				_remove_styled(pickups, index, repair_color)
				collected.emit(&"repair", healed)
				continue
		index += 1

func _tick_supply(delta: float) -> void:
	var interval := maxf(0.1, supply_interval)
	_supply_elapsed = minf(interval, _supply_elapsed + delta)
	if _supply_elapsed < interval or _supplies.count >= MAX_TIMED_SUPPLIES:
		return
	if _try_supply():
		_supply_elapsed = 0.0
		collected.emit(&"supply", 1)
	else:
		# Never claim a supply landed when walls or cliffs reject every candidate.
		_supply_elapsed = maxf(0.0, interval - maxf(0.1, supply_retry_interval))

func _try_supply() -> bool:
	var origin := Vector2(_player.global_position.x, _player.global_position.z)
	var area := _horde.play_area.grow(-SUPPLY_CLEARANCE)
	var start_height := _horde.ground_height(origin)
	# Wait until the player is on the modeled surface, not beneath a deck.
	if absf(_player.global_position.y - start_height - 0.9) > Horde.LEVEL_GAP:
		return false
	var phase := _rng.randf() * TAU
	var near := maxf(collect_distance + SUPPLY_CLEARANCE, supply_min_distance)
	var far := maxf(near, supply_max_distance)
	for attempt in range(SUPPLY_SEARCH_ATTEMPTS + SUPPLY_FALLBACK_ATTEMPTS):
		var angle: float
		var distance: float
		if attempt < SUPPLY_SEARCH_ATTEMPTS:
			angle = phase + TAU * float(attempt) / float(SUPPLY_SEARCH_ATTEMPTS)
			distance = lerpf(near, far, float(attempt % 3) * 0.5)
		else:
			# A small raised deck may have no reachable point on the outer ring.
			angle = phase + TAU * float(attempt - SUPPLY_SEARCH_ATTEMPTS) / float(SUPPLY_FALLBACK_ATTEMPTS)
			distance = maxf(collect_distance + SUPPLY_CLEARANCE, minf(near, SUPPLY_FALLBACK_DISTANCE))
		var candidate := origin + Vector2(cos(angle), sin(angle)) * distance
		if not area.has_point(candidate) or _horde.is_blocked(candidate, SUPPLY_CLEARANCE):
			continue
		if _horde.is_roofed(candidate):
			continue
		# Two waiting repair packs must not stack into one pickup.
		var occupied := false
		for index in _supplies.count:
			var at := _supplies.positions[index]
			if candidate.distance_squared_to(Vector2(at.x, at.z)) < SUPPLY_SEPARATION_SQUARED:
				occupied = true
				break
		if occupied:
			continue
		if not _supply_path_clear(origin, candidate, start_height):
			continue
		return _spawn(_supplies, Vector3(candidate.x, 0.0, candidate.y), repair_height, 1, repair_color)
	return false

func _supply_path_clear(origin: Vector2, destination: Vector2, start_height: float) -> bool:
	var steps := maxi(1, ceili(origin.distance_to(destination) / SUPPLY_PATH_STEP))
	var stride := origin.distance_to(destination) / float(steps)
	var previous_height := start_height
	for step in range(1, steps + 1):
		var point := origin.lerp(destination, float(step) / float(steps))
		if _horde.is_blocked(point, SUPPLY_CLEARANCE):
			return false
		var height := _horde.ground_height(point)
		# Both directions must be walkable: no pack atop or below a sheer ledge.
		if absf(height - previous_height) > Horde.CLIMB + stride * Horde.CLIMB_SLOPE:
			return false
		previous_height = height
	return true

## Struct-of-arrays storage for one pickup kind plus its MultiMesh buffer.
class PickupSet:
	const STRIDE := 16

	var count := 0
	var capacity := 0
	var positions := PackedVector3Array()
	var values := PackedInt32Array()
	## Zero until attracted; then current homing speed.
	var speeds := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var buffer := PackedFloat32Array()
	var multimesh: MultiMesh
	var dirty := false

	func build(owner: Node3D, mesh: Mesh, material: Material, p_capacity: int) -> void:
		capacity = p_capacity
		positions.resize(capacity)
		values.resize(capacity)
		speeds.resize(capacity)
		scales.resize(capacity)
		buffer.resize(capacity * STRIDE)
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = capacity
		multimesh.visible_instance_count = 0
		# Pickups spread over the whole stage; skip per-frame AABB rebuilds.
		multimesh.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 100.0, 2000.0))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		owner.add_child(instance)
		instance.top_level = true

	func add(at: Vector3, value: int) -> int:
		if count >= capacity:
			return -1
		var index := count
		count += 1
		positions[index] = at
		values[index] = value
		speeds[index] = 0.0
		return index

	func merge(index: int, value: int) -> void:
		values[index] += value

	func nearest(at: Vector3) -> int:
		var best := 0
		var best_distance := INF
		for index in range(count):
			var offset := positions[index] - at
			var distance := offset.x * offset.x + offset.z * offset.z
			if distance < best_distance:
				best_distance = distance
				best = index
		return best

	## Writes scale and color, and the position, for one instance.
	func write(index: int, scale: float, color: Color) -> void:
		scales[index] = scale
		var base := index * STRIDE
		var position := positions[index]
		buffer[base] = scale
		buffer[base + 1] = 0.0
		buffer[base + 2] = 0.0
		buffer[base + 3] = position.x
		buffer[base + 4] = 0.0
		buffer[base + 5] = scale
		buffer[base + 6] = 0.0
		buffer[base + 7] = position.y
		buffer[base + 8] = 0.0
		buffer[base + 9] = 0.0
		buffer[base + 10] = scale
		buffer[base + 11] = position.z
		buffer[base + 12] = color.r
		buffer[base + 13] = color.g
		buffer[base + 14] = color.b
		buffer[base + 15] = color.a
		dirty = true

	## Moves an attracted pickup; returns true when it reached the player.
	func step(index: int, target: Vector3, radius_squared: float, delta: float, field: PickupField) -> bool:
		var position := positions[index]
		var offset := target - position
		var speed := speeds[index]
		if speed == 0.0:
			if offset.x * offset.x + offset.z * offset.z > radius_squared:
				return false
			speed = field.initial_attract_speed
		speed = minf(speed + field.attract_acceleration * delta, field.max_attract_speed)
		speeds[index] = speed
		var distance := offset.length()
		if distance <= field.collect_distance + speed * delta:
			return true
		position += offset * (speed * delta / distance)
		positions[index] = position
		var base := index * STRIDE
		buffer[base + 3] = position.x
		buffer[base + 7] = position.y
		buffer[base + 11] = position.z
		dirty = true
		return false

	## Swap-removes; caller restyles the moved entry at `index`.
	func remove(index: int) -> void:
		count -= 1
		if index != count:
			positions[index] = positions[count]
			values[index] = values[count]
			speeds[index] = speeds[count]
			scales[index] = scales[count]
		dirty = true

	func flush() -> void:
		if not dirty:
			return
		dirty = false
		multimesh.buffer = buffer
		multimesh.visible_instance_count = count
