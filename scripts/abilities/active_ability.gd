class_name ActiveAbility
extends Node3D

## One independently cooled-down hero skill. The player sets slot before setup.
## Subclasses override _activate(), _ability_physics() and _cancel_effects().
## World-space visuals are pooled scene nodes, never created while playing.

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
var slot := 0
var _cooldown := 0.0
var _activate_audio: AudioStreamPlayer
var _effects_cancelled := false
var _visual_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_activate_audio = make_audio(activate_sound, synth_activate, activate_volume_db)

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	player = p_player
	horde = p_horde
	run_state = p_run_state

func is_ready() -> bool:
	return not get_tree().paused and _cooldown <= 0.0 and effects_allowed()

## Fires the ability if ready; returns true when it went off.
func activate() -> bool:
	if not is_ready() or not _activate():
		return false
	_cooldown = cooldown_total()
	_effects_cancelled = false
	if _activate_audio.stream != null:
		_activate_audio.play()
	activated.emit()
	return true

func cooldown_remaining() -> float:
	return maxf(0.0, _cooldown)

static func ability_damage_scale(upgrade_rank: int) -> float:
	return 1.0 + 0.25 * clampi(upgrade_rank, 0, RunState.MAX_ABILITY_RANK)

static func ability_cooldown_scale(upgrade_rank: int) -> float:
	return 1.0 - 0.12 * clampi(upgrade_rank, 0, RunState.MAX_ABILITY_RANK)

static func ability_duration_scale(upgrade_rank: int) -> float:
	return 1.0 + 0.15 * clampi(upgrade_rank, 0, RunState.MAX_ABILITY_RANK)

func rank() -> int:
	return run_state.ability_rank(slot) if run_state != null else 0

func duration_scale() -> float:
	return ability_duration_scale(rank())

func cooldown_total() -> float:
	return base_cooldown * ability_cooldown_scale(rank()) * (run_state.ability_cooldown_multiplier if run_state != null else 1.0)

func effects_allowed() -> bool:
	return is_instance_valid(player) and player.active and player.health > 0

func effect_time() -> float:
	return _visual_time

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if not effects_allowed():
		cancel()
		return
	_visual_time += delta
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	_ability_physics(delta)

## Death/inactive cleanup, not menu or mining cancellation.
func cancel() -> void:
	if _effects_cancelled:
		return
	_effects_cancelled = true
	_cancel_effects()
	for child in get_children():
		if child is Node3D:
			child.hide()
		elif child is AudioStreamPlayer:
			child.stop()

func _cancel_effects() -> void:
	pass

func _exit_tree() -> void:
	cancel()

## Returns false to refuse activation (no cooldown is spent).
func _activate() -> bool:
	return true

func _ability_physics(_delta: float) -> void:
	pass

func damage_scale() -> float:
	return ability_damage_scale(rank()) * (run_state.damage_multiplier if run_state != null else 1.0)

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
