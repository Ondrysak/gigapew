class_name ActiveAbility
extends Node3D

## Class ability fired with the `ability` action. The player instances the
## scene as its child and calls setup(). Subclasses override _activate()
## (return false to refuse) and _ability_physics(); world-space visuals are
## pooled scene nodes switched to top_level, never created while playing.

signal activated

@export var display_name := ""
@export_multiline var description := ""
@export var base_cooldown := 10.0
@export var accent_color := Color(0.1, 0.85, 0.9)
@export var icon: Texture2D

@export_group("Sound")
## Played on activation; empty uses synth_activate (see SynthCue).
@export var activate_sound: AudioStream
@export var synth_activate: StringName
@export var activate_volume_db := -6.0

var player: ArenaPlayer
var horde: Horde
var run_state: RunState
var _cooldown := 0.0
var _activate_audio: AudioStreamPlayer

func _ready() -> void:
	_activate_audio = make_audio(activate_sound, synth_activate, activate_volume_db)

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	player = p_player
	horde = p_horde
	run_state = p_run_state

func is_ready() -> bool:
	return _cooldown <= 0.0 and player != null and player.active

## Fires the ability if ready; returns true when it went off.
func activate() -> bool:
	if not is_ready() or not _activate():
		return false
	_cooldown = cooldown_total()
	if _activate_audio.stream != null:
		_activate_audio.play()
	activated.emit()
	return true

func cooldown_remaining() -> float:
	return maxf(0.0, _cooldown)

func cooldown_total() -> float:
	return base_cooldown * (run_state.ability_cooldown_multiplier if run_state != null else 1.0)

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	_ability_physics(delta)

## Returns false to refuse activation (no cooldown is spent).
func _activate() -> bool:
	return true

func _ability_physics(_delta: float) -> void:
	pass

func damage_scale() -> float:
	return run_state.damage_multiplier if run_state != null else 1.0

## Child AudioStreamPlayer on the SFX bus from an override or a SynthCue name.
func make_audio(stream: AudioStream, synth: StringName, volume_db: float) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream if stream != null else SynthCue.make(synth)
	audio.volume_db = volume_db
	audio.max_polyphony = 2
	audio.bus = &"SFX"
	add_child(audio)
	return audio

## Duplicates a hidden template `count` times as top-level world visuals.
func make_pool(template: Node3D, count: int) -> Array[Node3D]:
	var pool: Array[Node3D] = []
	if template == null:
		return pool
	template.hide()
	for index in range(count):
		var visual := template.duplicate() as Node3D
		add_child(visual)
		visual.top_level = true
		visual.hide()
		pool.append(visual)
	return pool
