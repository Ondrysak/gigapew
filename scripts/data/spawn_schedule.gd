class_name SpawnSchedule
extends Resource

## Minimum musical breathing room; these are never combat completion deadlines.
@export var build_duration := 16.0
@export var peak_duration := 14.0
@export var recovery_duration := 5.0
## At most one small group per cadence; unused admissions remain finite allocations.
@export var build_interval := 0.85
@export var peak_interval := 0.55
## Represented lives, including fused members, not just visible render bodies.
@export var max_alive := 48
@export var waves: Array[SpawnWave] = []
@export var boss: HordeEnemyDefinition
@export var boss_health_multiplier := 1.0
## Preferred approach ring. A bounded whole-arena search handles blocked rings.
@export var spawn_distance_min := 18.0
@export var spawn_distance_max := 30.0
