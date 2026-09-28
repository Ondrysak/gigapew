class_name ResourceDefinition
extends Resource

## A collectible material. Banked resources become persistent currency
## (Profile) when a stage is cleared; supply resources fill the in-run
## supply meter, which grants a free upgrade pick when full.

@export var id: StringName
@export var display_name := ""
@export var color := Color(1.0, 0.8, 0.2)
@export var icon: Texture2D
@export var banked := true
## Supply meter points per unit collected (0 = none).
@export var supply_value := 0
