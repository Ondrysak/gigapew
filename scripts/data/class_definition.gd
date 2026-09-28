class_name ClassDefinition
extends StatModifier

## A playable class: starting loadout, permanent stat profile and active
## ability. Inherited stat fields apply once for the whole run.

@export var id: StringName
@export var display_name := ""
@export var tagline := ""
@export_multiline var description := ""
@export var accent_color := Color(0.1, 0.85, 0.9)
@export var icon: Texture2D
## Main guns in slot order (keys 1/2/3).
@export var starting_weapons: Array[WeaponDefinition] = []
## Level-up upgrades granted at run start (e.g. an auto weapon).
@export var starting_upgrades: Array[UpgradeDefinition] = []
## Root must be an ActiveAbility.
@export var ability_scene: PackedScene
## Cost in `unlock_currency`; 0 means unlocked from the start.
@export var unlock_cost := 0
@export var unlock_currency: StringName = &"shard"
