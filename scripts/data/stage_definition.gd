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
## Optional salvage outcrops, never required to finish the arena.
@export_range(0, 6, 1) var outcrop_count := 2
## Finite BUILD / PEAK encounters, each followed by a real survivor cleanup.
@export_range(1, 8, 1) var arena_encounters := 4
## Seconds of calm on arrival before the director starts spawning.
@export_range(0.0, 30.0, 0.5) var spawn_grace := 0.0
@export var schedule: SpawnSchedule
## Explicit authored encounter fixtures; procedural campaign does not launch them.
@export var mining_encounter_scene: PackedScene
@export var boss_fight_scene: PackedScene
