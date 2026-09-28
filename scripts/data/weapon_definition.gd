class_name WeaponDefinition
extends Resource

@export var display_name := "Pulse"
@export var description := "Rapid precision fire"
@export var damage := 25
@export var fire_interval := 0.16
@export var range_meters := 40.0
@export_range(1, 32, 1) var pellet_count := 1
@export_range(0.0, 30.0) var spread_degrees := 0.0
@export var knockback := 6.5
## Extra enemies a single ray passes through (0 = stops at the first).
@export var pierce := 0
@export var view_scene: PackedScene
