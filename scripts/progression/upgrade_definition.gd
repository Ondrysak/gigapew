class_name UpgradeDefinition
extends StatModifier

## One level-up choice. STAT upgrades add their inherited modifier fields to
## RunState once per owned level; WEAPON upgrades grant and level an AutoWeapon;
## OVERCLOCK upgrades change how their target weapon behaves once it is maxed;
## PERK upgrades grant and level a PerkEffect (plus optional inherited stats);
## GUN_MOD upgrades alter player-fired shots without an auto-weapon slot;
## ABILITY upgrades raise one independent hero skill's run rank.

enum Kind { STAT, WEAPON, OVERCLOCK, PERK, GUN_MOD, ABILITY }

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
## Zero-based hero ability slot; ABILITY upgrades never occupy auto-weapon slots.
@export_range(0, 4) var ability_slot := 0

@export_group("Presentation")
@export var accent_color := Color(0.1, 0.85, 0.9)
@export var icon: Texture2D

@export_group("Weapon")
## Root must be an AutoWeapon.
@export var weapon_scene: PackedScene

@export_group("Overclock")
## WEAPON upgrade this overclock modifies; offered once that weapon is maxed.
@export var overclock_target: UpgradeDefinition

@export_group("Perk")
## Root must be a PerkEffect; optional for stat-only perks.
@export var perk_scene: PackedScene

## Text for the level reached after taking this upgrade (1-based).
func describe(level: int) -> String:
	var index := level - 1
	if index >= 0 and index < level_descriptions.size() and not level_descriptions[index].is_empty():
		return level_descriptions[index]
	return description
