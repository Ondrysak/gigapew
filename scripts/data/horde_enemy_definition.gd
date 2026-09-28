class_name HordeEnemyDefinition
extends Resource

## Gameplay data for one horde enemy type. Enemies are simulated in bulk by
## Horde; `model_scene` is baked once into a shared mesh for batched drawing.

enum Behavior { SWARM, RANGED, CHARGER }

@export var display_name := "Grunt"
@export var behavior := Behavior.SWARM
@export var max_health := 20.0
@export var speed := 4.0
## Horizontal body radius for crowding and hits.
@export var radius := 0.4
## Vertical hit extent above the floor.
@export var height := 1.4
## Knockback is divided by mass.
@export var mass := 1.0
## Damage contributed per contact tick while touching the player.
@export var contact_damage := 2.0
@export var xp_value := 1
@export var is_boss := false

@export_group("Ranged")
@export var preferred_range := 12.0
@export var attack_range := 22.0
@export var attack_cooldown := 3.0
@export var telegraph_duration := 0.6
@export var projectile_damage := 4.0
@export var projectile_speed := 9.0

@export_group("Charger")
@export var charge_range := 10.0
@export var charge_speed := 14.0
@export var charge_duration := 0.6

@export_group("Presentation")
## Node3D whose MeshInstance3D descendants use StandardMaterial3D overrides.
## Faces -Z; floor at y=0. Baked into one multi-surface mesh at stage start.
@export var model_scene: PackedScene
@export var model_scale := 1.0
@export var bob_amplitude := 0.05
@export var bob_speed := 6.0
@export var flash_color := Color(1.0, 0.92, 0.8)
@export var telegraph_color := Color(1.0, 0.3, 0.05)
