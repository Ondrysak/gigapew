class_name StageDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var subtitle: String
## ProceduralWorld scene, configured with this stage and a seed before mounting.
@export var world_scene: PackedScene
## Walkable floor rectangle on XZ (position = min corner), matching the
## inner faces of the perimeter walls.
@export var play_area := Rect2(-32, -32, 64, 64)
## Controls the procedural architecture palette and landmark silhouettes.
@export var layout_theme: StringName = &"yard"
## Requested number of separated cover islands; clear lanes take precedence.
@export_range(4, 32, 1) var cover_count := 16
## Raised decks, each reached by one ramp: high ground the horde must funnel up.
@export_range(0, 4, 1) var overlook_count := 1
## Interior ore rocks whose long faces host contract ore before the perimeter.
@export_range(0, 6, 1) var outcrop_count := 2
## Mining and kill contract difficulty relative to the first campaign stage.
@export_range(0.1, 5.0, 0.05) var quest_scale := 1.0
@export var schedule: SpawnSchedule
## Explicit authored encounter fixtures; procedural campaign does not launch them.
@export var mining_encounter_scene: PackedScene
@export var boss_fight_scene: PackedScene
