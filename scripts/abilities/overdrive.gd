class_name Overdrive
extends ActiveAbility

## Overclocks every auto weapon: RunState.cooldown_boost drops to `boost` for
## `duration` seconds, then returns to 1.

@export var duration := 6.0
## Auto-weapon recharge factor while active (lower recharges faster).
@export var boost := 0.45
## Aura visuals parented under this ability (follows the player).
@export var aura: Node3D
## Children of the aura that orbit around the player.
@export var orbit: Node3D
@export var orbit_speed := 5.0
@export_group("Sound")
@export var end_sound: AudioStream
@export var synth_end: StringName = &"overdrive_end"

var _remaining := 0.0
var _flare := 0.0
var _end_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_end_audio = make_audio(end_sound, synth_end, -8.0)
	if aura != null:
		aura.hide()

func is_overdriven() -> bool:
	return _remaining > 0.0

## Seconds of overdrive left (0 when inactive).
func remaining() -> float:
	return maxf(0.0, _remaining)

func _activate() -> bool:
	_remaining = duration
	_flare = 1.0
	if run_state != null:
		run_state.cooldown_boost = boost
	player.add_shake(0.2)
	player.camera.fov += 6.0
	if aura != null:
		aura.show()
	return true

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0 or not player.active:
		_finish()
		if _end_audio.stream != null:
			_end_audio.play()

func _finish() -> void:
	_remaining = 0.0
	if run_state != null:
		run_state.cooldown_boost = 1.0
	if aura != null:
		aura.hide()

func _exit_tree() -> void:
	# The RunState outlives the stage; never leave it boosted.
	if _remaining > 0.0:
		_finish()

func _process(delta: float) -> void:
	if _remaining <= 0.0 or aura == null:
		return
	_flare = maxf(0.0, _flare - delta * 3.0)
	var fade := minf(1.0, _remaining / 0.6)
	aura.scale = Vector3.ONE * (fade + _flare * 0.6)
	if orbit != null:
		orbit.rotation.y = fmod(orbit.rotation.y + orbit_speed * delta, TAU)
	# Flicker through the final second as a warning.
	aura.visible = _remaining >= 1.0 or fmod(_remaining, 0.2) >= 0.08
