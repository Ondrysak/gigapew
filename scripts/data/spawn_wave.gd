class_name SpawnWave
extends Resource

## A finite species allocation in each selected encounter, not an endless rate.
@export var enemy: HordeEnemyDefinition
@export_range(1, 8, 1) var encounter_start := 1
@export_range(1, 8, 1) var encounter_end := 8
## BUILD brings the crowd; PEAK introduces a second, deliberately different mix.
@export var peak := false
@export_range(1, 200, 1) var count := 16
@export_range(0, 40, 1) var count_growth := 4
## Small groups share a safe approach without filling a blocked ring backlog.
@export_range(1, 8, 1) var group_size := 4
@export var health_multiplier := 1.0
