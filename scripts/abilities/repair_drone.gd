class_name RepairDrone
extends ActiveAbility

## Deploys a drone that circles the player's head: an instant short shield,
## steady healing over the duration, and a zap at the nearest enemy.

@export var duration := 8.0
## Total HP restored over the whole duration.
@export var heal_total := 40.0
@export var shield_time := 2.5
@export var zap_range := 9.0
@export var zap_interval := 0.5
@export var zap_damage := 18.0
@export var zap_knockback := 3.0
## Drone visuals parented under this ability (follows the player).
@export var drone: Node3D
## Spun rotor ring under the drone.
@export var rotor: Node3D
@export var orbit_radius := 0.95
@export var orbit_height := 0.75
@export var orbit_speed := 2.2
## Shield bubble parented under this ability; its material alpha fades out.
@export var bubble: MeshInstance3D
## Hidden zap beam authored as a unit-length beam along -Z, pooled.
@export var beam_template: Node3D
@export var beam_lifetime := 0.12
## Hidden flat ring authored at radius 1, rising around the player per heal.
@export var pulse_template: Node3D
@export var pulse_interval := 1.0
@export var pulse_lifetime := 0.8
@export var pulse_radius := 1.2
@export_group("Sound")
@export var end_sound: AudioStream
@export var synth_end: StringName = &"overdrive_end"
@export var zap_sound: AudioStream
@export var synth_zap: StringName = &"blink"

var _remaining := 0.0
var _shield := 0.0
var _heal_accum := 0.0
var _zap_timer := 0.0
var _pulse_timer := 0.0
var _orbit := 0.0
var _pop := 0.0
var _bubble_material: StandardMaterial3D
var _bubble_alpha := 0.3
var _beams: Array[Node3D] = []
var _beam_age := PackedFloat32Array()
var _beam_to := PackedVector3Array()
var _next_beam := 0
var _pulses: Array[Node3D] = []
var _pulse_age := PackedFloat32Array()
var _next_pulse := 0
var _end_audio: AudioStreamPlayer
var _zap_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_end_audio = make_audio(end_sound, synth_end, -10.0)
	_zap_audio = make_audio(zap_sound, synth_zap, -18.0)
	_beams = make_pool(beam_template, 3)
	_beam_age.resize(_beams.size())
	_beam_age.fill(-1.0)
	_beam_to.resize(_beams.size())
	_pulses = make_pool(pulse_template, 3)
	_pulse_age.resize(_pulses.size())
	_pulse_age.fill(-1.0)
	for pulse in _pulses:
		# Heal rings rise around the player, so they follow it.
		pulse.top_level = false
	if drone != null:
		drone.hide()
	if bubble != null:
		bubble.hide()
		# Private copy so fading never touches the shared scene resource.
		var source := bubble.material_override as StandardMaterial3D
		if source != null:
			_bubble_material = source.duplicate() as StandardMaterial3D
			_bubble_alpha = source.albedo_color.a
			bubble.material_override = _bubble_material

func is_deployed() -> bool:
	return _remaining > 0.0

func _activate() -> bool:
	_remaining = duration
	_shield = shield_time
	_heal_accum = 0.0
	_zap_timer = zap_interval * 0.5
	_pulse_timer = 0.0
	_pop = 1.0
	player.grant_invulnerability(shield_time)
	player.add_shake(0.12)
	if drone != null:
		drone.show()
	if bubble != null:
		bubble.show()
	return true

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	if not player.active:
		_finish()
		return
	_remaining -= delta
	_shield = maxf(0.0, _shield - delta)
	_heal_accum += heal_total / duration * delta
	if _heal_accum >= 1.0:
		var amount := int(_heal_accum)
		player.heal(amount)
		_heal_accum -= float(amount)
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer += pulse_interval
		_emit_pulse()
	_zap_timer -= delta
	if _zap_timer <= 0.0:
		_zap_timer += zap_interval
		_zap()
	if _remaining <= 0.0:
		_finish()
		if _end_audio.stream != null:
			_end_audio.play()

func _zap() -> void:
	if horde == null or drone == null:
		return
	var origin := drone.global_position
	var index := horde.nearest(origin, zap_range)
	if index < 0:
		return
	var target := horde.enemy_position(index)
	var push := Vector3(target.x - origin.x, 0.0, target.z - origin.z).normalized() * zap_knockback
	horde.damage_direct(index, zap_damage * damage_scale(), origin, push)
	if _zap_audio.stream != null:
		_zap_audio.play()
	if _beams.is_empty():
		return
	var slot := _next_beam
	_next_beam = (_next_beam + 1) % _beams.size()
	_beam_age[slot] = 0.0
	_beam_to[slot] = target
	_place_beam(_beams[slot], origin, target, 1.0)

func _emit_pulse() -> void:
	if _pulses.is_empty():
		return
	var pulse := _pulses[_next_pulse]
	_pulse_age[_next_pulse] = 0.0
	_next_pulse = (_next_pulse + 1) % _pulses.size()
	pulse.position = Vector3(0.0, -0.85, 0.0)
	pulse.scale = Vector3.ONE * pulse_radius
	pulse.show()

## Places a template authored as a unit-length beam along -Z between points.
static func _place_beam(beam: Node3D, from: Vector3, to: Vector3, width_scale: float) -> void:
	var offset := to - from
	var length := offset.length()
	if length < 0.001 or width_scale <= 0.0:
		beam.hide()
		return
	var direction := offset / length
	var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	var frame := Basis.looking_at(direction, up)
	beam.global_transform = Transform3D(Basis(frame.x * width_scale, frame.y * width_scale, frame.z * length), (from + to) * 0.5)
	beam.show()

func _finish() -> void:
	_remaining = 0.0
	_shield = 0.0
	if drone != null:
		drone.hide()
	if bubble != null:
		bubble.hide()

func _exit_tree() -> void:
	_finish()

func _process(delta: float) -> void:
	if _remaining > 0.0:
		_animate_drone(delta)
	for index in range(_beams.size()):
		var age := _beam_age[index]
		if age < 0.0:
			continue
		age += delta
		if age >= beam_lifetime or drone == null:
			_beam_age[index] = -1.0
			_beams[index].hide()
			continue
		_beam_age[index] = age
		# The beam stays anchored to the moving drone while it fades.
		_place_beam(_beams[index], drone.global_position, _beam_to[index], 1.0 - age / beam_lifetime)
	for index in range(_pulses.size()):
		var age := _pulse_age[index]
		if age < 0.0:
			continue
		age += delta
		var pulse := _pulses[index]
		if age >= pulse_lifetime:
			_pulse_age[index] = -1.0
			pulse.hide()
			continue
		_pulse_age[index] = age
		var t := age / pulse_lifetime
		var radius := pulse_radius * (1.0 - t * 0.35)
		pulse.position = Vector3(0.0, -0.85 + t * 1.9, 0.0)
		pulse.scale = Vector3(radius, maxf(0.05, 1.0 - t), radius)

func _animate_drone(delta: float) -> void:
	_pop = maxf(0.0, _pop - delta * 3.0)
	if drone != null:
		_orbit = fmod(_orbit + orbit_speed * delta, TAU)
		var bob := sin(_orbit * 3.0) * 0.08
		drone.position = Vector3(cos(_orbit) * orbit_radius, orbit_height + bob, sin(_orbit) * orbit_radius)
		# Nose along the orbit tangent.
		drone.rotation.y = PI - _orbit
		drone.scale = Vector3.ONE * (1.0 - _pop * 0.6)
		# Flicker through the final second as a warning.
		drone.visible = _remaining >= 1.0 or fmod(_remaining, 0.2) >= 0.08
		if rotor != null:
			rotor.rotation.y = fmod(rotor.rotation.y + delta * 30.0, TAU)
	if bubble == null:
		return
	if _shield <= 0.0:
		bubble.hide()
		return
	var fade := minf(1.0, _shield / (shield_time * 0.6))
	bubble.scale = Vector3.ONE * (1.0 + _pop * 0.3 + (1.0 - fade) * 0.15)
	if _bubble_material != null:
		var color := _bubble_material.albedo_color
		color.a = _bubble_alpha * fade
		_bubble_material.albedo_color = color
