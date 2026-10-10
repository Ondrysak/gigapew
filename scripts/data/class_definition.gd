class_name ClassDefinition
extends StatModifier

## A playable class: one primary firearm, five active skills and a permanent
## stat profile. Inherited stat fields apply once for the whole run.

@export var id: StringName
@export var display_name := ""
@export var tagline := ""
@export_multiline var description := ""
@export var accent_color := Color(0.1, 0.85, 0.9)
@export var icon: Texture2D
@export var primary_weapon: WeaponDefinition
## Level-up upgrades granted at run start (e.g. an auto weapon).
@export var starting_upgrades: Array[UpgradeDefinition] = []
## Five unlocked ActiveAbility scenes, in key 1–5 order.
@export var ability_scenes: Array[PackedScene] = []
## Cost in `unlock_currency`; 0 means unlocked from the start.
@export var unlock_cost := 0
@export var unlock_currency: StringName = &"shard"

