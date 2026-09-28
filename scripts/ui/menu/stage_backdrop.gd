class_name StageBackdrop
extends Node3D

## Decorative 3D backdrop for menus: a camera orbiting a stage world while a
## loop of enemy models marches through it. Every Node3D child of `crowd`
## marches along +Z inside `march_range` and bobs; the models themselves are
## plain replaceable scenes.

@export var camera: Camera3D
@export var crowd: Node3D
@export var orbit_center := Vector3.ZERO
@export var orbit_radius := 20.0
@export var orbit_height := 5.0
## Radians per second.
@export var orbit_speed := 0.06
@export var orbit_angle := 0.4
@export var look_height := 1.4
@export var march_speed := 1.4
## Z range crowd members walk through before wrapping to the start.
@export var march_range := Vector2(-22.0, 22.0)
@export var bob_height := 0.08
@export var bob_rate := 7.0

var _phases: PackedFloat32Array = PackedFloat32Array()
var _base_heights: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	if crowd != null:
		for child in crowd.get_children():
			var member := child as Node3D
			if member == null:
				continue
			member.look_at(member.global_position + Vector3.BACK, Vector3.UP)
			_phases.append(randf() * TAU)
			_base_heights.append(member.position.y)
	_place_camera()

func _process(delta: float) -> void:
	orbit_angle = wrapf(orbit_angle + orbit_speed * delta, 0.0, TAU)
	_place_camera()
	if crowd == null:
		return
	var span := march_range.y - march_range.x
	var index := 0
	for child in crowd.get_children():
		var member := child as Node3D
		if member == null:
			continue
		var spot := member.position
		spot.z += march_speed * delta
		if spot.z > march_range.y:
			spot.z -= span
		_phases[index] += bob_rate * delta
		spot.y = _base_heights[index] + absf(sin(_phases[index])) * bob_height
		member.position = spot
		index += 1

func _place_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(sin(orbit_angle), 0.0, cos(orbit_angle)) * orbit_radius
	camera.position = orbit_center + offset + Vector3.UP * orbit_height
	camera.look_at(orbit_center + Vector3.UP * look_height, Vector3.UP)
