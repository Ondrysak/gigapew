class_name LastStandPerk
extends PerkEffect

## Cheats death a limited number of times per stage: a lethal hit leaves the
## player at 1 HP, grants a few seconds of invulnerability inside a red-gold
## bubble, heals a little once the hit has resolved and shoves the crowd away.

## Saves per stage, per level.
@export var charges := PackedFloat32Array([1.0, 1.0, 2.0])
## Invulnerability seconds per level.
@export var invulnerabilities := PackedFloat32Array([3.0, 4.0, 4.0])
## Health restored on top of the 1 HP left, per level.
@export var heal_bonuses := PackedFloat32Array([0.0, 10.0, 20.0])
@export var shove_radius := 6.0
@export var shove_damage := 1.0
@export var shove_knockback := 30.0
@export var shake := 0.6
## Bubble visuals parented under this perk (follows the player while shown).
@export var bubble: Node3D
@export_group("Sound")
@export var trigger_sound: AudioStream
@export var synth_trigger: StringName = &"bulwark"

var _guard: Callable
var _used := 0
var _bubble_left := 0.0
var _pop := 0.0
var _pending_heal := 0
var _audio: AudioStreamPlayer

func _ready() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.stream = trigger_sound if trigger_sound != null else SynthCue.make(synth_trigger)
	_audio.volume_db = -4.0
	_audio.bus = &"SFX"
	add_child(_audio)
	if bubble != null:
		bubble.hide()

func _setup() -> void:
	_guard = _on_lethal_hit
	player.add_death_guard(_guard)

## Saves left this stage.
func charges_left() -> int:
	return maxi(0, int(per_level(charges)) - _used)

# Called by the player inside take_damage: only bookkeeping here; the heal and
# shove run deferred once the hit has resolved.
func _on_lethal_hit() -> bool:
	if charges_left() <= 0:
		return false
	_used += 1
	var seconds := per_level(invulnerabilities)
	player.grant_invulnerability(seconds)
	_pending_heal = int(per_level(heal_bonuses))
	_bubble_left = seconds
	_pop = 1.0
	player.add_shake(shake)
	if _audio.stream != null:
		_audio.play()
	_resolve.call_deferred()
	return true

func _resolve() -> void:
	if not is_instance_valid(player) or not player.active:
		return
	if _pending_heal > 0:
		player.heal(_pending_heal)
		_pending_heal = 0
	if is_instance_valid(horde):
		horde.damage_radius(player.global_position, shove_radius, shove_damage, shove_knockback)

func _process(delta: float) -> void:
	if bubble == null or _bubble_left <= 0.0:
		return
	_bubble_left -= delta
	if _bubble_left <= 0.0 or not is_instance_valid(player) or not player.active:
		_bubble_left = 0.0
		bubble.hide()
		return
	# The perk root rides with the player so the bubble surrounds it.
	global_position = player.global_position
	_pop = maxf(0.0, _pop - delta * 4.0)
	var time := Time.get_ticks_msec() * 0.001
	bubble.scale = Vector3.ONE * (1.0 + sin(time * 6.0) * 0.03 + _pop * 0.35)
	bubble.rotation.y = fmod(bubble.rotation.y + delta * 1.6, TAU)
	# Flicker through the final second as a warning.
	bubble.visible = _bubble_left >= 1.0 or fmod(_bubble_left, 0.2) >= 0.08

func _exit_tree() -> void:
	if not _guard.is_null() and is_instance_valid(player):
		player.remove_death_guard(_guard)
