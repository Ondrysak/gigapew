class_name PickupField
extends Node3D

## XP gems and rare repair kits dropped by horde kills. All pickups are plain
## arrays drawn by one MultiMesh per kind; nothing is allocated per drop.

@export_group("Gems")
@export var gem_mesh: Mesh
## Should honour per-instance color (vertex_color_use_as_albedo).
@export var gem_material: Material
@export var max_gems := 3000
@export var low_value_color := Color(0.2, 0.95, 0.55)
@export var high_value_color := Color(1.0, 0.35, 0.95)
## Gem value reaching the full high_value_color and max scale.
@export var high_value_reference := 25
@export var max_gem_scale := 2.2
@export var gem_height := 0.35

@export_group("Repair")
@export var repair_mesh: Mesh
@export var repair_material: Material
@export var repair_color := Color(1.0, 0.25, 0.3)
@export_range(0.0, 1.0) var repair_chance := 0.01
@export var repair_heal := 15
@export var max_repairs := 64
@export var repair_height := 0.45

@export_group("Collection")
@export var collect_distance := 0.6
@export var initial_attract_speed := 3.0
@export var attract_acceleration := 45.0
@export var max_attract_speed := 30.0

var _player: ArenaPlayer
var _run_state: RunState
var _rng := RandomNumberGenerator.new()
var _gems := PickupSet.new()
var _repairs := PickupSet.new()

func setup(horde: Horde, player: ArenaPlayer, run_state: RunState) -> void:
	_player = player
	_run_state = run_state
	_gems.build(self, gem_mesh, gem_material, max_gems)
	_repairs.build(self, repair_mesh, repair_material, max_repairs)
	horde.enemy_killed.connect(_on_enemy_killed)

func _on_enemy_killed(definition: HordeEnemyDefinition, at: Vector3) -> void:
	if _rng.randf() < repair_chance:
		var kit := _repairs.add(Vector3(at.x, repair_height, at.z), 1)
		if kit >= 0:
			_repairs.write(kit, 1.0, repair_color)
	var value := maxi(1, definition.xp_value)
	var gem := _gems.add(Vector3(at.x, gem_height, at.z), value)
	if gem < 0:
		gem = _gems.nearest(at)
		_gems.merge(gem, value)
	_style_gem(gem)

func _style_gem(index: int) -> void:
	var weight := clampf(float(_gems.values[index] - 1) / float(maxi(1, high_value_reference - 1)), 0.0, 1.0)
	_gems.write(index, lerpf(1.0, max_gem_scale, sqrt(weight)), low_value_color.lerp(high_value_color, weight))

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.active:
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
	index = 0
	var healed := 0
	while index < _repairs.count:
		if _repairs.step(index, target, radius_squared, delta, self):
			healed += repair_heal
			_repairs.remove(index)
			if index < _repairs.count:
				_repairs.write(index, 1.0, repair_color)
		else:
			index += 1
	_gems.flush()
	_repairs.flush()
	if healed > 0:
		_player.heal(healed)
	if collected_xp > 0:
		_run_state.add_xp(collected_xp * _run_state.xp_multiplier)

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
			if distance < best_distance and speeds[index] == 0.0:
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
