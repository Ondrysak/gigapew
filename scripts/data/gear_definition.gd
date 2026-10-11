class_name GearDefinition
extends Resource

## Passive run equipment; discovery is persistent, ownership is not.
@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export_multiline var quote := ""
@export var icon: Texture2D
@export var accent_color := Color.WHITE
@export var cursed := false
