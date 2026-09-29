class_name ScavengerPerk
extends PerkEffect

## Kills may salvage a crystal straight into the run's resources; bosses
## always yield a handful. A small orange sparkle marks each find.

@export var crystal: ResourceDefinition
## Chance per kill to salvage one crystal, per level.
@export var chances := PackedFloat32Array([0.06, 0.1, 0.15])
## Crystals salvaged from every boss kill.
@export var boss_amount := 10
## Hidden sparkle authored at unit size.
@export var sparkle_template: Node3D
@export var sparkle_count := 6
@export var sparkle_size := 0.5
@export var sparkle_duration := 0.35
## Minimum seconds between sparkles.
@export var sparkle_interval := 0.08

var _chance := 0.0
var _next_msec := 0
var _sparkles: AutoFxPool
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if sparkle_template != null:
		sparkle_template.hide()
		_sparkles = AutoFxPool.new(self, sparkle_template, AutoFxPool.Style.SPARK)
		_sparkles.reserve(sparkle_count)

func _setup() -> void:
	horde.enemy_killed.connect(_on_enemy_killed)

func _refresh() -> void:
	_chance = per_level(chances)

func _on_enemy_killed(definition: HordeEnemyDefinition, at: Vector3) -> void:
	if crystal == null:
		return
	if definition != null and definition.is_boss:
		run_state.add_resource(crystal, boss_amount)
	elif _rng.randf() < _chance:
		run_state.add_resource(crystal, 1)
	else:
		return
	var now := Time.get_ticks_msec()
	if _sparkles == null or now < _next_msec:
		return
	_next_msec = now + int(sparkle_interval * 1000.0)
	_sparkles.spawn(at, sparkle_size, sparkle_duration, _rng.randf() * TAU)

func _process(delta: float) -> void:
	if _sparkles != null:
		_sparkles.update(delta)
