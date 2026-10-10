class_name BattleFrenzy
extends ActiveAbility

## Frenzies the main gun for `duration` seconds: a temporary StatModifier adds
## fire_rate_gain x the current fire rate and pierce_bonus pierce, removed again
## when the frenzy ends.

@export var duration := 5.0
## Fraction of the current total fire rate added while active (1 = double).
@export var fire_rate_gain := 1.0
@export var pierce_bonus := 99
## Aura visuals parented under this ability (follows the player).
@export var aura: Node3D
## Children of the aura spinning around the player's feet.
@export var spinner: Node3D
@export var spin_speed := 7.0
## Children of the aura counter-rotating slower (ring glyphs).
@export var glyphs: Node3D
@export var glyph_speed := -2.5
@export_group("Sound")
@export var end_sound: AudioStream
@export var synth_end: StringName = &"overdrive_end"

var _modifier: StatModifier
var _remaining := 0.0
var _flare := 0.0
var _end_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_modifier = StatModifier.new()
	_end_audio = make_audio(end_sound, synth_end, -8.0)
	if aura != null:
		aura.hide()

func is_ready() -> bool:
	return super() and _remaining <= 0.0

## Seconds of frenzy left (0 when inactive).
func remaining() -> float:
	return maxf(0.0, _remaining)

func _activate() -> bool:
	if run_state == null:
		return false
	_modifier.fire_rate_multiplier = run_state.fire_rate_multiplier * fire_rate_gain * ability_damage_scale(rank())
	_modifier.pierce_bonus = pierce_bonus
	run_state.add_temporary_modifier(_modifier)
	_remaining = duration * duration_scale()
	_flare = 1.0
	player.add_shake(0.2)
	player.camera.fov += 5.0
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
		run_state.remove_temporary_modifier(_modifier)
	if aura != null:
		aura.hide()

func _exit_tree() -> void:
	# The RunState outlives the stage; never leave it boosted.
	if _remaining > 0.0:
		_finish()

func _cancel_effects() -> void:
	_finish()

func _process(delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	if _remaining <= 0.0 or aura == null:
		return
	_flare = maxf(0.0, _flare - delta * 3.0)
	var fade := minf(1.0, _remaining / 0.4)
	aura.scale = Vector3.ONE * (fade + _flare * 0.5)
	if spinner != null:
		spinner.rotation.y = fmod(spinner.rotation.y + spin_speed * delta, TAU)
	if glyphs != null:
		glyphs.rotation.y = fmod(glyphs.rotation.y + glyph_speed * delta, TAU)
	# Flicker through the final second as a warning.
	aura.visible = _remaining >= 1.0 or fmod(_remaining, 0.2) >= 0.08
