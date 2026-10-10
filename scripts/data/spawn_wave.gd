class_name SpawnWave
extends Resource

## Sustained population: ramps from rate_start to rate_end over the configured
## pressure window, then holds the final rate until the level contract is done.
@export var enemy: HordeEnemyDefinition
@export var start_time := 0.0
@export var end_time := 300.0
@export var rate_start := 1.0
@export var rate_end := 4.0
## Enemies arrive in clusters of this size at one spawn point.
@export var group_size := 4
@export var health_multiplier := 1.0
