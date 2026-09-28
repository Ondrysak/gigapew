class_name StatModifier
extends Resource

## Additive run-stat modifiers shared by classes, permanent (meta) upgrades and
## level-up upgrades. RunState sums every source: class x1, meta upgrade x its
## purchased level, level-up upgrade x its stacks.

@export_group("Stat Modifiers")
@export var damage_multiplier := 0.0
## Main gun fire rate; positive fires faster.
@export var fire_rate_multiplier := 0.0
@export var move_speed_multiplier := 0.0
@export var max_health_bonus := 0
@export var regen_per_second := 0.0
@export var pickup_radius := 0.0
@export var pierce_bonus := 0
@export var area_multiplier := 0.0
## Auto weapon recharge; negative recharges faster.
@export var cooldown_multiplier := 0.0
@export var armor := 0.0
@export var xp_multiplier := 0.0
@export var projectile_bonus := 0
## Mining damage dealt to mineral deposits.
@export var mining_multiplier := 0.0
## Class ability recharge; negative recharges faster.
@export var ability_cooldown_multiplier := 0.0
## Extra yield from every mined or dropped resource.
@export var resource_multiplier := 0.0
