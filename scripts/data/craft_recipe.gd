class_name CraftRecipe
extends StatModifier

## Workshop recipe and its gameplay payload; price increases with owned rank.
@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var category: StringName
@export var costs: Dictionary = {}
@export var max_rank := 1
@export var weapon: WeaponDefinition
@export var hand_upgrade: StringName
@export var upgrade: UpgradeDefinition
