class_name MetaUpgradeDefinition
extends StatModifier

## Permanent upgrade bought between runs. Inherited stat fields apply once per
## purchased level at the start of every run.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var accent_color := Color(1.0, 0.75, 0.25)
@export var icon: Texture2D
## Price of each level: costs[0] buys level 1. Size defines the max level.
@export var costs := PackedInt32Array([50, 100, 180, 300, 450])
@export var currency: StringName = &"gold"

func max_level() -> int:
	return costs.size()
