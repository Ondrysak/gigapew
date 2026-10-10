class_name Bulwark
extends ActiveAbility

## Raises an invulnerable shield bubble and blasts the crowd away with a
## damaging shockwave; while it holds, the bubble keeps shoving enemies off.

@export var duration := 4.0
@export var pulse_radius := 6.0
@export var pulse_damage := 45.0
@export var pulse_knockback := 28.0
## Weaker repelling shove every aura_interval seconds while the bubble holds.
@export var aura_interval := 0.5
@export var aura_radius := 2.6
@export var aura_damage := 4.0
@export var aura_knockback := 12.0
## Bubble visuals parented under this ability (follows the player).
@export var bubble: Node3D
## Hidden flat ring authored at radius 1, expanded to pulse_radius.
@export var shock_template: Node3D
@export var shock_duration := 0.5
@export_group("Sound")
@export var end_sound: AudioStream
@export var synth_end: StringName = &"bulwark_end"

var _remaining := 0.0
var _aura_timer := 0.0
var _pop := 0.0
var _shocks: Array[Node3D] = []
var _shock_age := PackedFloat32Array()
var _next_shock := 0
var _end_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_end_audio = make_audio(end_sound, synth_end, -8.0)
	_shocks = make_pool(shock_template, 2)
	_shock_age.resize(_shocks.size())
	_shock_age.fill(-1.0)
	if bubble != null:
		bubble.hide()

func is_shielded() -> bool:
	return _remaining > 0.0

func _activate() -> bool:
	player.set_ability_protection(self, true)
	_remaining = duration * duration_scale()
	_aura_timer = aura_interval
	_pop = 1.0
	var center := player.global_position
	if horde != null:
		horde.damage_radius(center, pulse_radius, pulse_damage * damage_scale(), pulse_knockback)
	player.add_shake(0.4)
	player.camera.fov += 8.0
	_emit_shock(center)
	if bubble != null:
		bubble.show()
	return true

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0 or not player.active:
		_finish()
		if _end_audio.stream != null:
			_end_audio.play()
		return
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer += aura_interval
		if horde != null:
			horde.damage_radius(player.global_position, aura_radius, aura_damage * damage_scale(), aura_knockback)

func _emit_shock(center: Vector3) -> void:
	if _shocks.is_empty():
		return
	var shock := _shocks[_next_shock]
	_shock_age[_next_shock] = 0.0
	_next_shock = (_next_shock + 1) % _shocks.size()
	shock.global_position = Vector3(center.x, center.y - 0.8, center.z)
	shock.scale = Vector3.ONE * 0.5
	shock.show()

func _finish() -> void:
	_remaining = 0.0
	if is_instance_valid(player):
		player.set_ability_protection(self, false)
	if bubble != null:
		bubble.hide()

func _cancel_effects() -> void:
	_finish()
	_shock_age.fill(-1.0)

func _exit_tree() -> void:
	_finish()

func _process(delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	if bubble != null and _remaining > 0.0:
		_pop = maxf(0.0, _pop - delta * 4.0)
		var time := effect_time()
		var breathe := 1.0 + sin(time * 6.0) * 0.03 + _pop * 0.35
		bubble.scale = Vector3.ONE * breathe
		bubble.rotation.y = fmod(bubble.rotation.y + delta * 1.6, TAU)
		# Flicker through the final second as a warning.
		bubble.visible = _remaining >= 1.0 or fmod(_remaining, 0.2) >= 0.08
	for index in range(_shocks.size()):
		var age := _shock_age[index]
		if age < 0.0:
			continue
		age += delta
		var shock := _shocks[index]
		if age >= shock_duration:
			_shock_age[index] = -1.0
			shock.hide()
			continue
		_shock_age[index] = age
		var t := age / shock_duration
		var radius := lerpf(0.5, pulse_radius, 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t))
		shock.scale = Vector3(radius, maxf(0.05, 1.0 - t), radius)
