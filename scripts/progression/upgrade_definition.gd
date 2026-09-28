class_name UpgradeDefinition
extends Resource

## One level-up choice. STAT upgrades add their modifier fields to RunState
## once per owned level; WEAPON upgrades grant and level an AutoWeapon scene.

enum Kind { STAT, WEAPON }

@export var id: StringName
@export var display_name := ""
## Fallback text for every level.
@export_multiline var description := ""
## Optional text per level reached: entry 0 describes level 1, entry 1 level 2...
@export var level_descriptions: PackedStringArray = PackedStringArray()
@export var kind := Kind.STAT
@export var max_level := 5
## Repeatable entries are only offered when too few regular upgrades remain,
## never max out and are not counted towards weapon slots.
@export var repeatable := false
## Relative chance to be rolled among eligible upgrades.
@export var weight := 1.0
## Health restored immediately by the consumer when chosen.
@export var instant_heal := 0

@export_group("Presentation")
@export var accent_color := Color(0.1, 0.85, 0.9)
@export var icon: Texture2D

@export_group("Stat Modifiers Per Level")
@export var damage_multiplier := 0.0
@export var fire_rate_multiplier := 0.0
@export var move_speed_multiplier := 0.0
@export var max_health_bonus := 0
@export var regen_per_second := 0.0
@export var pickup_radius := 0.0
@export var pierce_bonus := 0
@export var area_multiplier := 0.0
## Added to RunState.cooldown_multiplier; negative values fire faster.
@export var cooldown_multiplier := 0.0
@export var armor := 0.0
@export var xp_multiplier := 0.0
@export var projectile_bonus := 0

@export_group("Weapon")
## Root must be an AutoWeapon.
@export var weapon_scene: PackedScene

## Text for the level reached after taking this upgrade (1-based).
func describe(level: int) -> String:
	var index := level - 1
	if index >= 0 and index < level_descriptions.size() and not level_descriptions[index].is_empty():
		return level_descriptions[index]
	return description
