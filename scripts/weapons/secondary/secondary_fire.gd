class_name SecondaryFire
extends Node3D

## Alternate fire mode of one main gun. Instanced from
## WeaponDefinition.secondary_scene once per hand holding that gun, added under
## the player's camera, and driven by ArenaPlayer:
##   - RMB pressed while this hand is focused, no deposit is in drill reach and
##     the hand's secondary meter holds at least `charge_cost` -> press().
##   - RMB released -> release(); swap, death or stage end -> cancel().
##   - The player deducts `charge_cost` from the hand's meter when `fired` is
##     emitted, so hold-to-charge modes only pay when they actually release.
## Implementations own their visuals (pooled, no per-shot allocation) and deal
## damage through the Horde API. They never move the player's aim.

signal fired

@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## Meter units (0-100 per hand) consumed per use.
@export_range(1.0, 100.0) var charge_cost := 100.0
## Seconds after a release before press() is accepted again.
@export var cooldown := 0.6

var player: ArenaPlayer
var horde: Horde
var run_state: RunState
var hand := 0
var view: WeaponView
## The hand's effective (upgraded) definition; re-sent after shop/level-up changes.
var definition: WeaponDefinition

var _cooldown_left := 0.0

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState, p_hand: int, p_view: WeaponView, p_definition: WeaponDefinition) -> void:
	player = p_player
	horde = p_horde
	run_state = p_run_state
	hand = p_hand
	view = p_view
	definition = p_definition

func configure(p_definition: WeaponDefinition) -> void:
	definition = p_definition

func is_ready() -> bool:
	return _cooldown_left <= 0.0

## True while charging, bursting or sustaining. Primary is blocked except for
## Overspin's rate boost; swapping cancels the held effect.
func is_active() -> bool:
	return false

func primary_rate_multiplier() -> float:
	return 1.0

func primary_spread_multiplier() -> float:
	return 1.0

func charge_progress() -> float:
	return 0.0

## Returns true when the press was accepted (instant modes emit `fired` here).
func press() -> bool:
	return false

func release() -> void:
	pass

func cancel() -> void:
	pass

## Implementations call this when the shot actually leaves the gun.
func _release_shot() -> void:
	_cooldown_left = cooldown
	fired.emit()

func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
