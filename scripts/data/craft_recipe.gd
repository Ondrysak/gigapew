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
@export var weapon_upgrade: StringName
@export var upgrade: UpgradeDefinition

## Weapon, perk and gadget recipes show their payload's icon; armor and
## talents use assets/icons/crafting/<id>.png.
func display_icon() -> Texture2D:
	if weapon != null and weapon.icon != null:
		return weapon.icon
	if upgrade != null and upgrade.icon != null:
		return upgrade.icon
	if not weapon_upgrade.is_empty():
		return GameIcons.lookup(&"shop", weapon_upgrade)
	return GameIcons.lookup(&"crafting", id)
