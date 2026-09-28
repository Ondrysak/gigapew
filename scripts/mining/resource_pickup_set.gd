class_name ResourcePickupSet
extends RefCounted

## Struct-of-arrays nuggets of one resource drawn by a single MultiMesh.
## Nuggets pop out ballistically, rest on the floor, then home in on the
## player. Nothing is allocated per drop or per frame.

const STRIDE := 16
const TILT := 0.45
const SPIN := 2.4

var definition: ResourceDefinition
var count := 0
var capacity := 0
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var values := PackedInt32Array()
var ages := PackedFloat32Array()
## Zero until attracted; then current homing speed.
var speeds := PackedFloat32Array()
var phases := PackedFloat32Array()
var buffer := PackedFloat32Array()
var multimesh: MultiMesh
var scale := 1.0
var _dirty := false

func build(owner: Node3D, p_definition: ResourceDefinition, mesh: Mesh, material: Material, p_capacity: int, p_scale: float) -> void:
	definition = p_definition
	capacity = p_capacity
	scale = p_scale
	positions.resize(capacity)
	velocities.resize(capacity)
	values.resize(capacity)
	ages.resize(capacity)
	speeds.resize(capacity)
	phases.resize(capacity)
	buffer.resize(capacity * STRIDE)
	# Every instance shares the resource color; write it once.
	for index in capacity:
		var base := index * STRIDE
		buffer[base + 12] = definition.color.r
		buffer[base + 13] = definition.color.g
		buffer[base + 14] = definition.color.b
		buffer[base + 15] = definition.color.a
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 100.0, 2000.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "%sPickups" % String(definition.id).capitalize()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner.add_child(instance)
	instance.top_level = true

## Returns the new index, or -1 when the pool is full.
func add(at: Vector3, velocity: Vector3, value: int, phase: float) -> int:
	if count >= capacity:
		return -1
	var index := count
	count += 1
	positions[index] = at
	velocities[index] = velocity
	values[index] = value
	ages[index] = 0.0
	speeds[index] = 0.0
	phases[index] = phase
	_write(index)
	return index

## Removes every nugget and returns their combined value.
func take_all() -> int:
	var total := 0
	for index in count:
		total += values[index]
	count = 0
	_dirty = true
	return total

## Advances every nugget; returns the value that reached the player.
func step(delta: float, target: Vector3, attract_radius_squared: float, can_collect: bool, field: DepositField, bounds: Rect2) -> int:
	var collected := 0
	var index := 0
	while index < count:
		var position := positions[index]
		var age := ages[index] + delta
		ages[index] = age
		var speed := speeds[index]
		if can_collect and speed == 0.0 and age >= field.magnet_delay:
			var offset := target - position
			if offset.x * offset.x + offset.z * offset.z <= attract_radius_squared or age >= field.always_attract_after:
				speed = field.initial_attract_speed
		if can_collect and speed > 0.0:
			speed = minf(speed + field.attract_acceleration * delta, field.max_attract_speed)
			speeds[index] = speed
			var offset := target - position
			var distance := offset.length()
			if distance <= field.collect_distance + speed * delta:
				collected += values[index]
				_remove(index)
				continue
			position += offset * (speed * delta / distance)
		else:
			var velocity := velocities[index]
			velocity.y -= field.pickup_gravity * delta
			position += velocity * delta
			if position.y <= field.pickup_rest_height:
				position.y = field.pickup_rest_height
				velocity.y = -velocity.y * 0.35 if velocity.y < -1.5 else 0.0
				var friction := maxf(0.0, 1.0 - 5.0 * delta)
				velocity.x *= friction
				velocity.z *= friction
			position.x = clampf(position.x, bounds.position.x, bounds.end.x)
			position.z = clampf(position.z, bounds.position.y, bounds.end.y)
			velocities[index] = velocity
		positions[index] = position
		_write(index)
		index += 1
	return collected

func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	multimesh.buffer = buffer
	multimesh.visible_instance_count = count

func _remove(index: int) -> void:
	count -= 1
	if index != count:
		positions[index] = positions[count]
		velocities[index] = velocities[count]
		values[index] = values[count]
		ages[index] = ages[count]
		speeds[index] = speeds[count]
		phases[index] = phases[count]
	_dirty = true

func _write(index: int) -> void:
	var age := ages[index]
	# Pop in from small, then spin slowly so nuggets glint.
	var size := scale * minf(1.0, 0.4 + age * 4.0)
	var basis := (Basis(Vector3.UP, phases[index] + age * SPIN) * Basis(Vector3.RIGHT, TILT)).scaled(Vector3(size, size, size))
	var position := positions[index]
	var base := index * STRIDE
	buffer[base] = basis.x.x
	buffer[base + 1] = basis.y.x
	buffer[base + 2] = basis.z.x
	buffer[base + 3] = position.x
	buffer[base + 4] = basis.x.y
	buffer[base + 5] = basis.y.y
	buffer[base + 6] = basis.z.y
	buffer[base + 7] = position.y
	buffer[base + 8] = basis.x.z
	buffer[base + 9] = basis.y.z
	buffer[base + 10] = basis.z.z
	buffer[base + 11] = position.z
	_dirty = true
