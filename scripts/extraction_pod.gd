class_name ExtractionPod
extends Node3D

## The contract is done: a drop pod descends into a distant room and hovers in
## a beam visible over every wall. Standing inside the floor ring for
## `hold_time` seconds extracts; progress is kept while the player steps out to
## fight. The director surges for the whole extraction. Nothing here collides,
## so the pod never blocks the horde's navigation.
signal departed

enum State { LANDING, WAITING, DEPARTED }

const COLOR := Color(0.35, 1.0, 0.6)

@export var hold_time := 10.0
@export var zone_radius := 4.5
@export var landing_time := 3.0
@export var hover_height := 4.2
## Director spawn-rate multiplier while extracting.
@export var surge_multiplier := 2.0

var state := State.LANDING
## Seconds already held inside the ring.
var progress := 0.0
var _player: ArenaPlayer
var _age := 0.0
var _depart_age := 0.0
var _pod: Node3D
var _beam_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _light: OmniLight3D

func setup(player: ArenaPlayer) -> void:
	_player = player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ring_material = _glow(COLOR, 1.0)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = zone_radius - 0.25
	torus.outer_radius = zone_radius
	ring.mesh = torus
	ring.material_override = _ring_material
	ring.scale = Vector3(1.0, 0.08, 1.0)
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_beam_material = _glow(Color(COLOR, 0.16), 0.8)
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var beam := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 1.2
	column.bottom_radius = 1.2
	column.height = 60.0
	beam.mesh = column
	beam.material_override = _beam_material
	beam.position.y = 30.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_pod = Node3D.new()
	add_child(_pod)
	var hull := _steel()
	_part(CylinderMesh.new(), hull, Vector3(0, 0, 0), Vector3(1.3, 2.4, 1.3), 1.0, 1.0)
	_part(CylinderMesh.new(), hull, Vector3(0, 1.8, 0), Vector3(1.3, 1.2, 1.3), 0.0, 1.0)
	_part(CylinderMesh.new(), _ring_material, Vector3(0, 0.6, 0), Vector3(1.32, 0.12, 1.32), 1.0, 1.0)
	_part(CylinderMesh.new(), _ring_material, Vector3(0, -1.25, 0), Vector3(0.9, 0.1, 0.9), 1.0, 1.0)
	for index in 4:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 1.6, 0.9)
		fin.mesh = box
		fin.material_override = hull
		var angle := index * PI * 0.5
		fin.position = Vector3(cos(angle) * 1.35, -0.6, sin(angle) * 1.35)
		fin.rotation.y = -angle
		_pod.add_child(fin)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 2.5
	_light.omni_range = 12.0
	_light.position.y = 3.0
	add_child(_light)
	_pod.position.y = 45.0

func _physics_process(delta: float) -> void:
	if get_tree().paused or state == State.DEPARTED:
		return
	_age += delta
	if state == State.LANDING:
		if _age >= landing_time:
			state = State.WAITING
		return
	if player_inside():
		progress = minf(hold_time, progress + delta)
	if progress >= hold_time:
		state = State.DEPARTED
		departed.emit()

func player_inside() -> bool:
	if not is_instance_valid(_player) or not _player.active or state != State.WAITING:
		return false
	var offset := _player.global_position - global_position
	return Vector2(offset.x, offset.z).length() <= zone_radius and absf(offset.y) < 3.0

func fraction() -> float:
	return progress / hold_time

func distance_to(at: Vector3) -> float:
	return Vector2(at.x - global_position.x, at.z - global_position.z).length()

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	match state:
		State.LANDING:
			var t := clampf(_age / landing_time, 0.0, 1.0)
			_pod.position.y = lerpf(45.0, hover_height, 1.0 - pow(1.0 - t, 3.0))
		State.WAITING:
			_pod.position.y = hover_height + sin(_age * 2.0) * 0.15
			_pod.rotation.y += delta * 0.4
		State.DEPARTED:
			_depart_age += delta
			_pod.position.y = hover_height + _depart_age * _depart_age * 12.0
	var inside := player_inside()
	_beam_material.albedo_color.a = (0.3 if inside else 0.16) + sin(_age * 6.0) * 0.04
	_light.light_energy = 3.5 if inside else 2.5

func _part(mesh: CylinderMesh, material: Material, at: Vector3, size: Vector3, top: float, bottom: float) -> void:
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.scale = size
	_pod.add_child(part)

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = energy
	return material

func _steel() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.36, 0.4)
	material.metallic = 0.7
	material.roughness = 0.35
	return material
