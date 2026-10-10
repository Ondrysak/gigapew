class_name SuppressionBarrage
extends ActiveAbility

## Calls in rings of shells around the spot the player stood on at activation:
## one wave per wave_radii entry (wave_counts blasts each), blasts sweeping
## around the ring blast_stagger apart, waves wave_interval apart.

@export var wave_radii := PackedFloat32Array([4.0, 7.0, 10.0])
## Blasts per wave (paired with wave_radii by index).
@export var wave_counts := PackedInt32Array([8, 10, 12])
@export var blast_stagger := 0.06
@export var wave_interval := 0.25
## Random scatter of each blast center (m).
@export var jitter := 0.6
@export var blast_radius := 2.6
@export var blast_damage := 55.0
@export var blast_knockback := 14.0
@export var wave_shake := 0.16
## Hidden flash authored at radius 1 (core fireball and pillar).
@export var flash_template: Node3D
@export var flash_radius := 1.5
@export var flash_duration := 0.45
## Hidden flat ring authored at radius 1, expanded to blast_radius as a scorch.
@export var scorch_template: Node3D
@export var scorch_duration := 0.8
## Flashes that would reach within this distance of the camera are skipped.
@export var min_view_clearance := 1.0
@export_group("Sound")
@export var wave_sound: AudioStream
@export var synth_wave: StringName = &"seismic_boom"

## Scheduled detonation time per blast (-1 once fired).
var _blast_time := PackedFloat32Array()
var _blast_at := PackedVector3Array()
## 1 for the first blast of each wave (shake and sound cue).
var _blast_leads := PackedByteArray()
var _blast_total := 0
var _pending := 0
var _elapsed := 0.0
var _flashes: Array[Node3D] = []
var _flash_age := PackedFloat32Array()
var _next_flash := 0
var _scorches: Array[Node3D] = []
var _scorch_age := PackedFloat32Array()
var _next_scorch := 0
var _rng := RandomNumberGenerator.new()
var _wave_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_rng.randomize()
	_wave_audio = make_audio(wave_sound, synth_wave, -9.0)
	for wave in mini(wave_radii.size(), wave_counts.size()):
		_blast_total += maxi(0, wave_counts[wave])
	_blast_time.resize(_blast_total)
	_blast_time.fill(-1.0)
	_blast_at.resize(_blast_total)
	_blast_leads.resize(_blast_total)
	_flashes = make_pool(flash_template, _blast_total)
	_flash_age.resize(_flashes.size())
	_flash_age.fill(-1.0)
	_scorches = make_pool(scorch_template, _blast_total)
	_scorch_age.resize(_scorches.size())
	_scorch_age.fill(-1.0)

func is_ready() -> bool:
	return super() and _pending == 0 and _blast_total > 0

func _activate() -> bool:
	var center := player.global_position
	var floor_y := center.y - 0.85
	var n := 0
	for wave in mini(wave_radii.size(), wave_counts.size()):
		var count := maxi(0, wave_counts[wave])
		var radius := wave_radii[wave]
		var offset := _rng.randf() * TAU
		for i in count:
			var angle := offset + TAU * float(i) / float(count)
			var at := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
			at += Vector3(_rng.randf_range(-jitter, jitter), 0.0, _rng.randf_range(-jitter, jitter))
			if horde != null:
				var area := horde.play_area
				at.x = clampf(at.x, area.position.x, area.end.x)
				at.z = clampf(at.z, area.position.y, area.end.y)
			at.y = floor_y
			_blast_at[n] = at
			_blast_time[n] = wave * wave_interval + i * blast_stagger
			_blast_leads[n] = 1 if i == 0 else 0
			n += 1
	_pending = n
	_elapsed = 0.0
	player.add_shake(0.1)
	return true

func _ability_physics(delta: float) -> void:
	if _pending == 0:
		return
	if not player.active:
		_pending = 0
		_blast_time.fill(-1.0)
		return
	_elapsed += delta
	for n in _blast_total:
		var time := _blast_time[n]
		if time < 0.0 or time > _elapsed:
			continue
		_blast_time[n] = -1.0
		_pending -= 1
		_blast(_blast_at[n], _blast_leads[n] == 1)

func _blast(at: Vector3, lead: bool) -> void:
	if horde != null:
		blast(at, blast_radius, blast_damage * damage_scale(), blast_knockback)
	if lead:
		player.add_shake(wave_shake)
		if _wave_audio.stream != null:
			_wave_audio.play()
	if not _flashes.is_empty():
		var flash := _flashes[_next_flash]
		# Skip flashes that would engulf the camera; the scorch still marks the hit.
		if player.camera.global_position.distance_to(at) >= flash_radius + min_view_clearance:
			_flash_age[_next_flash] = 0.0
			flash.global_position = at
			flash.scale = Vector3.ONE * 0.05
			flash.show()
			_next_flash = (_next_flash + 1) % _flashes.size()
	if not _scorches.is_empty():
		var scorch := _scorches[_next_scorch]
		_scorch_age[_next_scorch] = 0.0
		scorch.global_position = at + Vector3.UP * 0.05
		scorch.scale = Vector3.ONE * 0.3
		scorch.show()
		_next_scorch = (_next_scorch + 1) % _scorches.size()

func _cancel_effects() -> void:
	_pending = 0
	_blast_time.fill(-1.0)
	_flash_age.fill(-1.0)
	_scorch_age.fill(-1.0)

func _process(delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	for index in range(_flashes.size()):
		var age := _flash_age[index]
		if age < 0.0:
			continue
		age += delta
		var flash := _flashes[index]
		if age >= flash_duration:
			_flash_age[index] = -1.0
			flash.hide()
			continue
		_flash_age[index] = age
		var p := age / flash_duration
		var size := sin(minf(p * 2.2, 1.0) * PI * 0.5) * (1.0 - p * p * 0.85)
		flash.scale = Vector3.ONE * maxf(size, 0.02) * flash_radius
	for index in range(_scorches.size()):
		var age := _scorch_age[index]
		if age < 0.0:
			continue
		age += delta
		var scorch := _scorches[index]
		if age >= scorch_duration:
			_scorch_age[index] = -1.0
			scorch.hide()
			continue
		_scorch_age[index] = age
		var t := age / scorch_duration
		var radius := lerpf(0.3, blast_radius, 1.0 - pow(1.0 - minf(t * 1.8, 1.0), 3.0))
		scorch.scale = Vector3(radius, maxf(0.05, 1.0 - t), radius)
