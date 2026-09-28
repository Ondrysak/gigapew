class_name ClassRoster
extends Resource

## All playable classes in menu order. File: res://data/classes/roster.tres.
@export var classes: Array[ClassDefinition] = []

func find(id: StringName) -> ClassDefinition:
	for definition in classes:
		if definition.id == id:
			return definition
	return classes[0] if not classes.is_empty() else null
