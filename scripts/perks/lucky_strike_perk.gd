class_name LuckyStrikePerk
extends PerkEffect

## Critical-hit feedback: a gold spark burst where the main gun lands a
## critical hit. The crit chance and damage come from the upgrade's stat
## fields; this scene only draws them.

## Hidden spark burst authored at unit size.
@export var spark_template: Node3D
@export var spark_count := 6
@export var spark_size := 0.6
@export var spark_duration := 0.22
## Minimum seconds between bursts.
@export var spark_interval := 0.05
## Bursts closer than this to the camera are skipped.
@export var min_view_clearance := 0.8

var _sparks: AutoFxPool
var _next_msec := 0

func _ready() -> void:
	if spark_template != null:
		spark_template.hide()
		_sparks = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
		_sparks.reserve(spark_count)

func _setup() -> void:
	player.critical_hit.connect(_on_critical_hit)

func _on_critical_hit(at: Vector3) -> void:
	if _sparks == null:
		return
	var now := Time.get_ticks_msec()
	if now < _next_msec:
		return
	if player.camera.global_position.distance_to(at) < spark_size + min_view_clearance:
		return
	_next_msec = now + int(spark_interval * 1000.0)
	_sparks.spawn(at, spark_size, spark_duration, randf() * TAU)

func _process(delta: float) -> void:
	if _sparks != null:
		_sparks.update(delta)
