class_name WeaponView
extends Node3D

# Scene-assigned references keep the actor independent of model hierarchy.
@export var muzzle: Node3D
@export var flash: GeometryInstance3D
@export var flash_light: Light3D
@export var trace_material: Material
@export var impact_material: Material
@export var target_impact_material: Material
@export var shot_cue: StringName = &"shot"
@export var hit_cue: StringName = &"hit"
@export var kill_cue: StringName = &"kill"
@export var shot_sound: AudioStream
@export var hit_sound: AudioStream
@export var kill_sound: AudioStream
@export var recoil_distance := 0.11
@export var recoil_angle := 0.09
@export var trace_width := 0.014
@export var trace_duration := 0.045
@export var flash_duration := 0.045

var _rest: Vector3
var _recoil := 0.0
var _landing_dip := 0.0
var _stride := 0.0
var _sway := Vector2.ZERO
var _flash_time := 0.0
var _trace_time := 0.0
var _impact_time := 0.0
var _traces: Array[MeshInstance3D] = []
var _impacts: Array[MeshInstance3D] = []
var _shot_audio: AudioStreamPlayer
var _hit_audio: AudioStreamPlayer
var _kill_audio: AudioStreamPlayer

func _ready() -> void:
	_rest = position
	_shot_audio = _make_audio(shot_sound)
	_hit_audio = _make_audio(hit_sound)
	_kill_audio = _make_audio(kill_sound)

func _make_audio(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.max_polyphony = 4
	add_child(player)
	return player

func prepare(pellet_count: int) -> void:
	# Allocate once for this definition's maximum rays, never during firing.
	var trace_mesh := BoxMesh.new()
	trace_mesh.size = Vector3(trace_width, trace_width, 1.0)
	var impact_mesh := SphereMesh.new()
	impact_mesh.radius = 1.0
	impact_mesh.height = 2.0
	impact_mesh.radial_segments = 8
	impact_mesh.rings = 4
	for index in range(pellet_count):
		var trace := MeshInstance3D.new()
		trace.mesh = trace_mesh
		trace.material_override = trace_material
		trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trace)
		trace.top_level = true
		trace.hide()
		_traces.append(trace)
		var impact := MeshInstance3D.new()
		impact.mesh = impact_mesh
		impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(impact)
		impact.top_level = true
		impact.hide()
		_impacts.append(impact)

func aim(relative: Vector2) -> void:
	_sway += relative * 0.00012
	_sway = _sway.clamp(Vector2(-0.025, -0.02), Vector2(0.025, 0.02))

func land(falling_speed: float) -> void:
	_landing_dip = minf(-falling_speed * 0.006, 0.055)

func animate_motion(delta: float, speed_ratio: float, lateral_speed: float, grounded: bool, active: bool) -> void:
	var blend := 1.0 - exp(-18.0 * delta)
	_recoil = lerpf(_recoil, 0.0, blend)
	_landing_dip = lerpf(_landing_dip, 0.0, 1.0 - exp(-12.0 * delta))
	_sway = _sway.lerp(Vector2.ZERO, blend)
	if active and grounded:
		_stride += delta * 12.0 * speed_ratio
	var bob := Vector3(sin(_stride) * 0.012, absf(cos(_stride)) * 0.009, 0.0) * speed_ratio
	position = _rest + bob + Vector3(-_sway.x, _sway.y - _landing_dip, _recoil * recoil_distance)
	rotation.x = _recoil * recoil_angle
	rotation.z = -lateral_speed * 0.002
	if not active:
		_flash_time = 0.0

func _process(delta: float) -> void:
	_flash_time = maxf(0.0, _flash_time - delta)
	flash.visible = _flash_time > 0.0
	flash_light.visible = flash.visible
	_trace_time = maxf(0.0, _trace_time - delta)
	_impact_time = maxf(0.0, _impact_time - delta)
	for trace in _traces:
		if _trace_time == 0.0:
			trace.hide()
	for impact in _impacts:
		if _impact_time == 0.0:
			impact.hide()
		elif impact.visible:
			impact.scale = Vector3.ONE * maxf(0.001, _impact_time * 0.9)

func begin_shot(sound: CombatAudio) -> void:
	_play(_shot_audio, sound, shot_cue)
	_recoil = 1.0
	_flash_time = flash_duration
	_trace_time = trace_duration
	_impact_time = 0.13
	for trace in _traces:
		trace.hide()
	for impact in _impacts:
		impact.hide()

func show_ray(index: int, end: Vector3, normal: Vector3, hit_surface: bool, hit_enemy: bool) -> void:
	var start := muzzle.global_position
	if start.distance_squared_to(end) > 0.01:
		var trace := _traces[index]
		trace.global_position = (start + end) * 0.5
		trace.global_basis = Basis.looking_at(end - start)
		trace.scale = Vector3(1.0, 1.0, start.distance_to(end))
		trace.show()
	if hit_surface:
		var impact := _impacts[index]
		impact.global_position = end + normal * 0.035
		impact.material_override = target_impact_material if hit_enemy else impact_material
		impact.scale = Vector3.ONE * 0.117
		impact.show()

func confirm_hit(killed: bool, sound: CombatAudio) -> void:
	_play(_kill_audio if killed else _hit_audio, sound, kill_cue if killed else hit_cue)

func _play(player: AudioStreamPlayer, fallback: CombatAudio, cue: StringName) -> void:
	if player.stream != null:
		player.play()
	else:
		fallback.play_cue(cue)
