class_name StageBackdrop
extends Node3D

## Decorative 3D backdrop: the stage world and a few VAT-driven monster
## previews orbit beneath the menu. Crowd roots are markers; their actual
## meshes/materials come from the same definitions and baker as the horde.

@export var camera: Camera3D
@export var crowd: Node3D
@export var sentinel: Node3D
@export var monster_definitions: Array[HordeEnemyDefinition]
@export var vat_shader: Shader
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
var _previews: Array[MeshInstance3D] = []
var _preview_frames := PackedFloat32Array()
var _preview_counts := PackedFloat32Array()
var _preview_fps := PackedFloat32Array()
var _meshes: Array[ArrayMesh] = []

func _ready() -> void:
	_meshes.resize(monster_definitions.size())
	if sentinel != null:
		_add_preview(sentinel, 4)
	if crowd != null:
		for child in crowd.get_children():
			var member := child as Node3D
			if member == null:
				continue
			member.look_at(member.global_position + Vector3.BACK, Vector3.UP)
			var type := 0
			if member.name.begins_with("Runner"):
				type = 1
			elif member.name.begins_with("Spitter"):
				type = 2
			elif member.name.begins_with("Tank"):
				type = 3
			_add_preview(member, type)
			_phases.append(randf() * TAU)
			_base_heights.append(member.position.y)
	_place_camera()

func _add_preview(member: Node3D, type: int) -> void:
	if type >= monster_definitions.size():
		return
	var definition := monster_definitions[type]
	if definition == null or definition.vertex_animation == null:
		return
	if _meshes[type] == null:
		_meshes[type] = HordeMeshBaker.bake(definition, vat_shader, vat_shader)
	# The scene marker may already instance the rest glb for editor previews.
	for child in member.get_children():
		child.queue_free()
	var visual := MeshInstance3D.new()
	visual.mesh = _meshes[type]
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	member.add_child(visual)
	var animation := definition.vertex_animation
	var index := animation.find_clip(definition.move_clip)
	if index < 0:
		index = 0
	var clip := animation.clips[index]
	visual.set_instance_shader_parameter("preview_start", float(clip.start_frame))
	visual.set_instance_shader_parameter("preview_count", float(clip.frame_count))
	var frame := randf() * clip.frame_count
	visual.set_instance_shader_parameter("preview_frame", frame)
	_previews.append(visual)
	_preview_frames.append(frame)
	_preview_counts.append(float(clip.frame_count))
	_preview_fps.append(clip.fps)
func _process(delta: float) -> void:
	orbit_angle = wrapf(orbit_angle + orbit_speed * delta, 0.0, TAU)
	for index in _previews.size():
		var frame := fposmod(_preview_frames[index] + delta * _preview_fps[index], _preview_counts[index])
		_preview_frames[index] = frame
		_previews[index].set_instance_shader_parameter("preview_frame", frame)
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
