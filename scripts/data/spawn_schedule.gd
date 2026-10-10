class_name SpawnSchedule
extends Resource

## Ordinary spawn pressure stops increasing at this horizon; the level has no timer.
@export var ramp_duration := 240.0
## Regular spawning pauses while this many enemies are alive.
@export var max_alive := 1200
@export var waves: Array[SpawnWave] = []
@export var boss: HordeEnemyDefinition
@export var boss_health_multiplier := 1.0
## Spawn ring around the player, clamped into the play area.
@export var spawn_distance_min := 22.0
@export var spawn_distance_max := 34.0
