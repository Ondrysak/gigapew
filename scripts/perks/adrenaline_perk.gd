class_name AdrenalinePerk
extends PerkEffect

## The main gun fires faster the more health is missing: the fire-rate bonus
## scales linearly from 0 at full health to the level's maximum at 0 HP. It
## lives in one temporary RunState modifier, refreshed only on real changes.

## Fire-rate bonus at 0 HP per level (0.8 = +80%).
@export var max_bonuses := PackedFloat32Array([0.4, 0.6, 0.8])
## Smallest bonus change worth recomputing run stats for.
@export var min_step := 0.02

var _modifier: StatModifier
var _max_bonus := 0.0

func _setup() -> void:
	_modifier = StatModifier.new()
	run_state.add_temporary_modifier(_modifier)
	player.health_changed.connect(_on_health_changed)

func _refresh() -> void:
	_max_bonus = per_level(max_bonuses)
	_update(true)

func _on_health_changed(_current: int, _maximum: int) -> void:
	_update(false)

func _update(force: bool) -> void:
	if _modifier == null or not is_instance_valid(player):
		return
	var missing := 1.0 - clampf(float(player.health) / float(maxi(1, player.max_health)), 0.0, 1.0)
	var value := _max_bonus * missing
	var current := _modifier.fire_rate_multiplier
	if value == current:
		return
	# Small drifts are skipped, but returning to exactly 0 always applies.
	if not force and value != 0.0 and absf(value - current) < min_step:
		return
	_modifier.fire_rate_multiplier = value
	run_state.refresh_modifiers()

func _exit_tree() -> void:
	# The RunState outlives the stage; never leave it boosted.
	if _modifier != null and run_state != null:
		run_state.remove_temporary_modifier(_modifier)
