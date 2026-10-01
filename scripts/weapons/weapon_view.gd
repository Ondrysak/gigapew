class_name WeaponView
extends Node3D

# Scene-assigned references keep the actor independent of model hierarchy.
@export var muzzle: Node3D
@export var flash: GeometryInstance3D
@export var flash_light: Light3D
## Tracer line material; leave empty to draw no tracers (e.g. flame weapons).
@export var trace_material: Material
@export var impact_material: Material
@export var target_impact_material: Material
@export var shot_cue: StringName = &"shot"
@export var hit_cue: StringName = &"hit"
@export var kill_cue: StringName = &"kill"
@export var shot_sound: AudioStream
@export var hit_sound: AudioStream
@export var kill_sound: AudioStream
## Built-in SynthCue used when shot_sound is empty; empty falls back to shot_cue.
@export var synth_shot: StringName
@export var shot_volume_db := -10.0
@export var recoil_distance := 0.11
@export var recoil_angle := 0.09
@export var trace_width := 0.014
@export var trace_duration := 0.045
@export var flash_duration := 0.045

@export_group("Spin")
## Optional node spun about its local Z axis while the gun spins up.
@export var spinner: Node3D
## Radians per second at full spin.
@export var spin_speed := 38.0
## Looping sound whose pitch and volume follow the spin.
@export var spin_sound: AudioStream
@export var synth_spin: StringName
@export var spin_volume_db := -15.0

@export_group("Flame")
## Material for puffs launched along each ray; empty disables puffs.
@export var puff_material: Material
@export var puff_pool_size := 48
@export var puff_lifetime := 0.3
@export var puff_start_size := 0.06
@export var puff_end_size := 0.8
## Puffs shrink so their surface stays at least this far from the camera.
@export var puff_camera_clearance := 0.45

@export_group("Blast")
## Hidden node authored at radius 1; pooled for explosive shots.
@export var blast_template: Node3D
@export var blast_pool_size := 6
@export var blast_duration := 0.26
## Visual radius as a fraction of the damage radius.
@export var blast_visual_scale := 0.75
## Blasts whose flash would reach within this distance of the camera skip the
## flash (damage still applies), so point-blank shots never white out the view.
@export var min_view_clearance := 1.0

var _rest: Vector3
var _rest_rotation := Vector3.ZERO
var _mining_offset := Vector3.ZERO
var _kick_strength := 1.0
var _damage_type := -1
var _flash_material: StandardMaterial3D
var _critical_material: StandardMaterial3D
var _blast_material: StandardMaterial3D
var _recoil := 0.0
var _landing_dip := 0.0
var _stride := 0.0
var _sway := Vector2.ZERO
var _flash_time := 0.0
var _trace_time := 0.0
var _impact_time := 0.0
var _traces: Array[MeshInstance3D] = []
var _impacts: Array[MeshInstance3D] = []
var _sparks: Array[MeshInstance3D] = []
var _shot_audio: AudioStreamPlayer
var _hit_audio: AudioStreamPlayer
var _kill_audio: AudioStreamPlayer
var _spin_audio: AudioStreamPlayer
var _spin := 0.0
var _camera: Camera3D
var _puffs: Array[MeshInstance3D] = []
var _puff_from := PackedVector3Array()
var _puff_to := PackedVector3Array()
var _puff_age := PackedFloat32Array()
var _puff_next := 0
var _blasts: Array[Node3D] = []
var _blast_times := PackedFloat32Array()
var _blast_radii := PackedFloat32Array()

func _ready() -> void:
	_rest = position
	_rest_rotation = rotation
	_shot_audio = _make_audio(shot_sound if shot_sound != null else SynthCue.make(synth_shot))
	_shot_audio.volume_db = shot_volume_db
	_hit_audio = _make_audio(hit_sound)
	_kill_audio = _make_audio(kill_sound)
	var hum := spin_sound if spin_sound != null else SynthCue.make(synth_spin)
	if hum != null:
		_spin_audio = _make_audio(hum)
		_spin_audio.max_polyphony = 1

func _make_audio(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.max_polyphony = 4
	player.bus = &"SFX"
	add_child(player)
	return player

func prepare(pellet_count: int) -> void:
	# Allocate once for this definition's maximum rays, never during firing.
	if not _impacts.is_empty():
		return
	# All materials mutated by type upgrades belong to this view, not its scene.
	trace_material = _local_material(trace_material) if trace_material != null else null
	impact_material = _local_material(impact_material)
	target_impact_material = _local_material(target_impact_material)
	puff_material = _local_material(puff_material) if puff_material != null else null
	_critical_material = _local_material(target_impact_material)
	_blast_material = _local_material(null)
	_blast_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if flash is MeshInstance3D:
		var mesh_flash := flash as MeshInstance3D
		_flash_material = _local_material(mesh_flash.get_active_material(0))
		mesh_flash.material_override = _flash_material
	var trace_mesh := BoxMesh.new()
	trace_mesh.size = Vector3(trace_width, trace_width, 1.0)
	var impact_mesh := _sphere_mesh(8, 4)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.018, 0.16, 0.018)
	for index in range(pellet_count):
		if trace_material != null:
			var trace := MeshInstance3D.new()
			trace.mesh = trace_mesh
			trace.material_override = trace_material
			_add_world_visual(trace)
			_traces.append(trace)
		var impact := MeshInstance3D.new()
		impact.mesh = impact_mesh
		_add_world_visual(impact)
		_impacts.append(impact)
		# Two short crossed streaks at the actual contact point, reused per ray.
		for arm in 2:
			var spark := MeshInstance3D.new()
			spark.mesh = spark_mesh
			_add_world_visual(spark)
			_sparks.append(spark)
	if puff_material != null:
		var puff_mesh := _sphere_mesh(10, 5)
		for index in range(puff_pool_size):
			var puff := MeshInstance3D.new()
			puff.mesh = puff_mesh
			puff.material_override = puff_material
			_add_world_visual(puff)
			_puffs.append(puff)
		_puff_from.resize(puff_pool_size)
		_puff_to.resize(puff_pool_size)
		_puff_age.resize(puff_pool_size)
		_puff_age.fill(-1.0)
	var blast_count := maxi(pellet_count, blast_pool_size)
	var blast_mesh := _sphere_mesh(12, 6)
	if blast_template != null:
		blast_template.hide()
	for index in range(blast_count):
		var blast: Node3D
		if blast_template != null:
			blast = blast_template.duplicate() as Node3D
		else:
			var sphere := MeshInstance3D.new()
			sphere.mesh = blast_mesh
			sphere.material_override = _blast_material
			sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			blast = sphere
		add_child(blast)
		blast.top_level = true
		blast.hide()
		_blasts.append(blast)
	_blast_times.resize(blast_count)
	_blast_times.fill(0.0)
	_blast_radii.resize(blast_count)

func _local_material(source: Material) -> StandardMaterial3D:
	if source is StandardMaterial3D:
		return source.duplicate() as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

## Called when effective hand upgrades change, never from the shot path.
func configure(definition: WeaponDefinition) -> void:
	_kick_strength = lerpf(0.7, 1.35, inverse_lerp(0.15, 0.6, clampf(definition.recoil_degrees, 0.15, 0.6)))
	if _damage_type == definition.damage_type:
		return
	_damage_type = definition.damage_type
	var color := DamageType.color(_damage_type)
	_tint(trace_material as StandardMaterial3D, color)
	_tint(impact_material as StandardMaterial3D, color.lerp(Color.WHITE, 0.25))
	_tint(target_impact_material as StandardMaterial3D, color)
	_tint(puff_material as StandardMaterial3D, color)
	_tint(_flash_material, color.lerp(Color.WHITE, 0.35))
	_tint(_critical_material, color.lerp(Color.WHITE, 0.7))
	_tint(_blast_material, Color(color.r, color.g, color.b, 0.25))
	if flash_light != null:
		flash_light.light_color = color
	for blast in _blasts:
		_tint_blast(blast, color)

func _tint(material: StandardMaterial3D, color: Color) -> void:
	if material == null:
		return
	material.albedo_color = color
	if material.emission_enabled:
		material.emission = Color(color.r, color.g, color.b)

func _tint_blast(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.material_override = _blast_material
	elif node is Light3D:
		(node as Light3D).light_color = color
	for child in node.get_children():
		_tint_blast(child, color)

func _sphere_mesh(segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh

func _add_world_visual(visual: MeshInstance3D) -> void:
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	visual.top_level = true
	visual.hide()

func aim(relative: Vector2) -> void:
	_sway += relative * 0.00012
	_sway = _sway.clamp(Vector2(-0.025, -0.02), Vector2(0.025, 0.02))

func land(falling_speed: float) -> void:
	_landing_dip = minf(-falling_speed * 0.006, 0.055)

## Spin-up progress 0..1 of a spinning gun (drives the spinner and its hum).
func set_spin(ratio: float) -> void:
	_spin = ratio
	if _spin_audio == null:
		return
	if ratio <= 0.02:
		if _spin_audio.playing:
			_spin_audio.stop()
		return
	_spin_audio.pitch_scale = lerpf(0.45, 1.25, ratio)
	_spin_audio.volume_db = spin_volume_db + linear_to_db(clampf(ratio * 1.5, 0.05, 1.0))
	if not _spin_audio.playing:
		_spin_audio.play()

func animate_motion(delta: float, speed_ratio: float, lateral_speed: float, grounded: bool, active: bool, mining: bool = false) -> void:
	var blend := 1.0 - exp(-18.0 * delta)
	_recoil = lerpf(_recoil, 0.0, blend)
	_landing_dip = lerpf(_landing_dip, 0.0, 1.0 - exp(-12.0 * delta))
	_sway = _sway.lerp(Vector2.ZERO, blend)
	if active and grounded:
		_stride += delta * 12.0 * speed_ratio
	var bob := Vector3(sin(_stride) * 0.012, absf(cos(_stride)) * 0.009, 0.0) * speed_ratio
	# A spinning gun hums with a slight shake.
	var buzz := Vector3(sin(_stride * 31.0 + _spin * 7.0), cos(_stride * 27.0 + _spin * 5.0), 0.0) * _spin * 0.0025
	# The drill raises on the left; yield space without hiding a weapon/hand.
	_mining_offset = _mining_offset.lerp(Vector3(-0.16, -0.12, 0.0) if mining else Vector3.ZERO, blend)
	position = _rest + bob + buzz + _mining_offset + Vector3(-_sway.x, _sway.y - _landing_dip, _recoil * recoil_distance)
	rotation = _rest_rotation + Vector3(_recoil * recoil_angle, 0.0, -lateral_speed * 0.002)
	if not active:
		_flash_time = 0.0

func _process(delta: float) -> void:
	_flash_time = maxf(0.0, _flash_time - delta)
	if flash != null:
		flash.visible = _flash_time > 0.0
	if flash_light != null:
		flash_light.visible = _flash_time > 0.0
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
	if spinner != null and _spin > 0.0:
		spinner.rotation.z = fmod(spinner.rotation.z + spin_speed * _spin * delta, TAU)
	for spark in _sparks:
		if _impact_time == 0.0:
			spark.hide()
		elif spark.visible:
			spark.scale = Vector3.ONE * maxf(0.001, _impact_time * 7.7)
	if not _puffs.is_empty():
		_update_puffs(delta)
	if not _blasts.is_empty():
		_update_blasts(delta)

func begin_shot(sound: CombatAudio) -> void:
	_play(_shot_audio, sound, shot_cue)
	_recoil = _kick_strength
	_flash_time = flash_duration
	_trace_time = trace_duration
	_impact_time = 0.13
	for trace in _traces:
		trace.hide()
	for impact in _impacts:
		impact.hide()
	for spark in _sparks:
		spark.hide()

func show_ray(index: int, end: Vector3, normal: Vector3, hit_surface: bool, hit_enemy: bool, critical: bool = false) -> void:
	var start := muzzle.global_position
	var ray := end - start
	var orientation := muzzle.global_basis
	if ray.length_squared() > 0.0001:
		orientation = Basis.looking_at(ray, Vector3.RIGHT if absf(ray.normalized().y) > 0.98 else Vector3.UP)
	if index < _traces.size() and ray.length_squared() > 0.01:
		var trace := _traces[index]
		trace.global_position = (start + end) * 0.5
		trace.global_basis = orientation
		trace.scale = Vector3(1.0, 1.0, ray.length())
		trace.show()
	if not _puffs.is_empty():
		_launch_puff(start, end)
	if hit_surface:
		var impact := _impacts[index]
		var surface_normal := orientation.z if hit_enemy else normal
		impact.global_position = end + surface_normal * (0.09 if hit_enemy else 0.035)
		impact.material_override = _critical_material if hit_enemy and critical else target_impact_material if hit_enemy else impact_material
		impact.scale = Vector3.ONE * (0.15 if hit_enemy and critical else 0.117)
		impact.show()
		for arm in 2:
			var spark := _sparks[index * 2 + arm]
			spark.global_position = end + surface_normal * 0.07
			spark.global_basis = orientation.rotated(orientation.z, PI * (0.25 if arm == 0 else -0.25))
			spark.material_override = impact.material_override
			spark.scale = Vector3.ONE
			spark.show()

## Explosion flash at `at` for a blast of damage radius `radius`.
func show_blast(at: Vector3, radius: float) -> void:
	if _blasts.is_empty():
		return
	var visual_radius := radius * blast_visual_scale
	if _view_camera() != null and _camera.global_position.distance_to(at) < visual_radius + min_view_clearance:
		return
	var slot := 0
	for index in range(_blasts.size()):
		if _blast_times[index] <= 0.0:
			slot = index
			break
		if _blast_times[index] < _blast_times[slot]:
			slot = index
	var blast := _blasts[slot]
	blast.global_position = at
	blast.scale = Vector3.ONE * visual_radius * 0.3
	blast.show()
	_blast_times[slot] = blast_duration
	_blast_radii[slot] = visual_radius

func confirm_hit(killed: bool, sound: CombatAudio, chain: int, critical: bool = false) -> void:
	var pitch := 1.0 + 0.045 * float(mini(chain, 7)) + (0.18 if critical and not killed else 0.0)
	_play(_kill_audio if killed else _hit_audio, sound, kill_cue if killed else hit_cue, pitch)
	if killed or critical:
		_impact_time = maxf(_impact_time, 0.18 if killed else 0.15)
		for impact in _impacts:
			if impact.visible and impact.material_override == target_impact_material:
				impact.material_override = _critical_material
		for spark in _sparks:
			if spark.visible and spark.material_override == target_impact_material:
				spark.material_override = _critical_material

func _play(player: AudioStreamPlayer, fallback: CombatAudio, cue: StringName, pitch: float = 1.0) -> void:
	if player.stream != null:
		player.pitch_scale = pitch
		player.play()
	else:
		fallback.play_cue(cue, pitch)

func _view_camera() -> Camera3D:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	return _camera

func _launch_puff(start: Vector3, end: Vector3) -> void:
	var slot := _puff_next
	_puff_next = (_puff_next + 1) % _puffs.size()
	_puff_from[slot] = start
	_puff_to[slot] = end
	_puff_age[slot] = 0.0

func _update_puffs(delta: float) -> void:
	var camera := _view_camera()
	for index in range(_puffs.size()):
		var age := _puff_age[index]
		if age < 0.0:
			continue
		var puff := _puffs[index]
		age += delta
		if age >= puff_lifetime:
			_puff_age[index] = -1.0
			puff.hide()
			continue
		_puff_age[index] = age
		var t := age / puff_lifetime
		# Fast out of the nozzle, lingering and rising at the far end.
		var travel := 1.0 - (1.0 - t) * (1.0 - t)
		var at := _puff_from[index].lerp(_puff_to[index], travel) + Vector3.UP * (t * t * 0.7)
		var size := lerpf(puff_start_size, puff_end_size, sqrt(t)) * (1.0 - t * t * t * t)
		if camera != null:
			size = minf(size, maxf(0.0, camera.global_position.distance_to(at) - puff_camera_clearance) * 0.7)
		if size < 0.01:
			puff.hide()
			continue
		puff.global_position = at
		puff.scale = Vector3.ONE * size
		puff.show()

func _update_blasts(delta: float) -> void:
	for index in range(_blasts.size()):
		if _blast_times[index] <= 0.0:
			continue
		_blast_times[index] -= delta
		var blast := _blasts[index]
		if _blast_times[index] <= 0.0:
			blast.hide()
			continue
		var progress := 1.0 - _blast_times[index] / blast_duration
		# Snap out to full radius, then collapse as the flash fades.
		var size := sin(minf(progress * 1.6, 1.0) * PI * 0.5) * (1.0 - progress * progress * 0.7)
		blast.scale = Vector3.ONE * maxf(size, 0.02) * _blast_radii[index]
