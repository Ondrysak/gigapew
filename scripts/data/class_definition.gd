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
## Default ability, always available. Root must be an ActiveAbility.
@export var ability_scene: PackedScene
## Optional abilities bought in class select; roots must be ActiveAbility.
@export var alternate_abilities: Array[PackedScene] = []
## Unlock price of each alternate ability (same order), in ability_unlock_currency.
@export var alternate_ability_costs: PackedInt32Array = PackedInt32Array()
@export var ability_unlock_currency: StringName = &"shard"
## Cost in `unlock_currency`; 0 means unlocked from the start.
@export var unlock_cost := 0
@export var unlock_currency: StringName = &"shard"

## The default ability followed by every alternate, in picker order.
func ability_options() -> Array[PackedScene]:
	var options: Array[PackedScene] = []
	if ability_scene != null:
		options.append(ability_scene)
	for scene in alternate_abilities:
		if scene != null and not options.has(scene):
			options.append(scene)
	return options

## Unlock price of an ability option; 0 for the default or unknown scenes.
func ability_cost(scene: PackedScene) -> int:
	if scene == null or scene == ability_scene:
		return 0
	var index := alternate_abilities.find(scene)
	if index < 0 or index >= alternate_ability_costs.size():
		return 0
	return maxi(0, alternate_ability_costs[index])

## Stable save key of an ability scene (its file name without extension).
static func ability_key(scene: PackedScene) -> StringName:
	if scene == null:
		return &""
	return StringName(scene.resource_path.get_file().get_basename())
