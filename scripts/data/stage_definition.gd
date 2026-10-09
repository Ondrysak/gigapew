class_name StageDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var subtitle: String
## Static world: geometry, lights, PlayerSpawn marker, Obstacles node.
@export var world_scene: PackedScene
## Walkable floor rectangle on XZ (position = min corner), matching the
## inner faces of the perimeter walls.
@export var play_area := Rect2(-32, -32, 64, 64)
@export var schedule: SpawnSchedule
## Optional stage encounters; stages without them retain ordinary horde behavior.
@export var mining_encounter_scene: PackedScene
@export var boss_fight_scene: PackedScene
