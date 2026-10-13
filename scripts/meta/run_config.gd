class_name RunConfig
extends RefCounted

## One run's chosen level and tuning. A run plays the selected level; clearing
## it opens the shop, which can start another round on any level, optionally a
## difficulty tier harder. Presets are starting points; editing any value turns
## the configuration into CUSTOM.

## Every selectable level, in menu order. The single catalogue for game and menus.
const LEVEL_PATHS: Array[String] = [
	"res://data/stages/yard.tres",
	"res://data/stages/foundry.tres",
	"res://data/stages/reactor.tres",
]

const CUSTOM := &"custom"
## Tunable multipliers: [min, max, step]. 1.0 is the authored level.
const RANGES := {
	"density": [0.25, 3.0, 0.05],
	"crowd": [0.5, 2.0, 0.05],
	"health": [0.5, 3.0, 0.05],
	"damage": [0.25, 3.0, 0.05],
	"pace": [0.5, 2.0, 0.05],
}
const FIGHTS_RANGE := Vector2i(1, 8)
const MAX_DIFFICULTY := 10
## Each difficulty tier stacks on top of the tuning below.
const TIER_HEALTH := 0.15
const TIER_DAMAGE := 0.10
const TIER_DENSITY := 0.08
## Clear rewards grow with the tier so pushing harder pays.
const TIER_REWARD := 0.25
## Represented-life ceiling regardless of crowd tuning.
const CROWD_LIMIT := Vector2i(8, 200)
## Specialist roles a "no specialists" run leaves out; core crowd roles stay.
const SPECIALISTS: Array[int] = [
	HordeEnemyDefinition.Behavior.THROWER, HordeEnemyDefinition.Behavior.BOUNCER,
	HordeEnemyDefinition.Behavior.HYPE, HordeEnemyDefinition.Behavior.BOMBER,
	HordeEnemyDefinition.Behavior.AMBUSHER, HordeEnemyDefinition.Behavior.SPRAYER,
]
## "fights" -1 keeps the level's own fight count.
const PRESETS := {
	&"pohoda": {"name": "Pohodička", "blurb": "Dvě krátké bitky, řídký dav, měkké rány. Na rozkoukání.",
		"fights": 2, "density": 0.6, "crowd": 0.75, "health": 0.7, "damage": 0.5, "pace": 0.8, "specialists": false},
	&"klasika": {"name": "Klasika", "blurb": "Level přesně tak, jak je postavený.",
		"fights": -1, "density": 1.0, "crowd": 1.0, "health": 1.0, "damage": 1.0, "pace": 1.0, "specialists": true},
	&"rychlovka": {"name": "Rychlovka", "blurb": "Jedna bitka, rychlejší nástup. Na pauzu od práce.",
		"fights": 1, "density": 1.0, "crowd": 1.0, "health": 1.0, "damage": 1.0, "pace": 1.4, "specialists": true},
	&"horda": {"name": "Horda", "blurb": "Dvojnásobný dav z papíru. Hodně těl, málo zdraví.",
		"fights": -1, "density": 2.5, "crowd": 1.8, "health": 0.6, "damage": 0.8, "pace": 1.5, "specialists": true},
	&"peklo": {"name": "Hardtek peklo", "blurb": "Tlustší, hustší a zlejší. Pro vybuildované.",
		"fights": -1, "density": 1.6, "crowd": 1.4, "health": 1.6, "damage": 1.6, "pace": 1.3, "specialists": true},
}
const DEFAULT_PRESET := &"klasika"

var level: StringName = &"yard"
var preset: StringName = DEFAULT_PRESET
var fights := 3
var density := 1.0
var crowd := 1.0
var health := 1.0
var damage := 1.0
var pace := 1.0
var specialists := true
var difficulty := 0

static func levels() -> Array[StageDefinition]:
	var result: Array[StageDefinition] = []
	for path in LEVEL_PATHS:
		result.append(load(path) as StageDefinition)
	return result

## Index of the chosen level in `catalogue`, falling back to the first.
func level_index(catalogue: Array[StageDefinition]) -> int:
	for index in catalogue.size():
		if catalogue[index].id == level:
			return index
	return 0

## Selects a level; a preset that keeps the level's fight count follows it.
func select_level(stage: StageDefinition) -> void:
	level = stage.id
	if PRESETS.has(preset) and int(PRESETS[preset].fights) < 0:
		fights = stage.arena_encounters

func apply_preset(id: StringName, stage: StageDefinition) -> void:
	if not PRESETS.has(id):
		return
	var values: Dictionary = PRESETS[id]
	preset = id
	var authored := int(values.fights)
	fights = authored if authored > 0 else (stage.arena_encounters if stage != null else 3)
	for key: String in RANGES:
		set(key, float(values[key]))
	specialists = bool(values.specialists)

## Any manual edit leaves the preset.
func set_value(key: String, value: Variant) -> void:
	match key:
		"fights":
			fights = clampi(int(value), FIGHTS_RANGE.x, FIGHTS_RANGE.y)
		"specialists":
			specialists = bool(value)
		"difficulty":
			difficulty = clampi(int(value), 0, MAX_DIFFICULTY)
			return
		_:
			if not RANGES.has(key):
				return
			var bounds: Array = RANGES[key]
			set(key, clampf(snappedf(float(value), float(bounds[2])), float(bounds[0]), float(bounds[1])))
	preset = CUSTOM

func preset_name() -> String:
	return String(PRESETS[preset].name) if PRESETS.has(preset) else "Vlastní"

func health_scale() -> float:
	return health * (1.0 + TIER_HEALTH * difficulty)

func damage_scale() -> float:
	return damage * (1.0 + TIER_DAMAGE * difficulty)

func density_scale() -> float:
	return density * (1.0 + TIER_DENSITY * difficulty)

func reward_scale() -> float:
	return 1.0 + TIER_REWARD * difficulty

## Short HUD/shop line: preset and tier.
func label() -> String:
	return "%s · OBTÍŽNOST %d" % [preset_name().to_upper(), difficulty]

## Effective copy of `stage`: the authored resources are never mutated.
func build_stage(stage: StageDefinition) -> StageDefinition:
	var result := stage.duplicate(false) as StageDefinition
	result.arena_encounters = fights
	var schedule := stage.schedule.duplicate(false) as SpawnSchedule
	var waves: Array[SpawnWave] = []
	for authored in stage.schedule.waves:
		if authored == null or authored.enemy == null:
			continue
		if not specialists and authored.enemy.behavior in SPECIALISTS:
			continue
		var wave := authored.duplicate(false) as SpawnWave
		wave.count = maxi(1, roundi(authored.count * density_scale()))
		wave.count_growth = maxi(0, roundi(authored.count_growth * density_scale()))
		wave.health_multiplier = authored.health_multiplier * health_scale()
		waves.append(wave)
	schedule.waves = waves
	schedule.boss_health_multiplier = stage.schedule.boss_health_multiplier * health_scale()
	schedule.max_alive = clampi(roundi(stage.schedule.max_alive * crowd), CROWD_LIMIT.x, CROWD_LIMIT.y)
	schedule.build_interval = stage.schedule.build_interval / pace
	schedule.peak_interval = stage.schedule.peak_interval / pace
	result.schedule = schedule
	return result

## Represented bodies the director will admit across every fight.
func estimated_enemies(stage: StageDefinition) -> int:
	var total := 0
	var built := build_stage(stage)
	for wave in built.schedule.waves:
		for encounter in range(1, built.arena_encounters + 1):
			if encounter >= wave.encounter_start and encounter <= wave.encounter_end:
				total += wave.count + wave.count_growth * (encounter - wave.encounter_start)
	return total

func to_dict() -> Dictionary:
	return {"level": String(level), "preset": String(preset), "fights": fights,
		"density": density, "crowd": crowd, "health": health, "damage": damage,
		"pace": pace, "specialists": specialists, "difficulty": difficulty}

## Sanitized; unknown or missing keys keep defaults.
static func from_dict(data: Dictionary) -> RunConfig:
	var config := RunConfig.new()
	config.level = StringName(str(data.get("level", config.level)))
	for key: String in RANGES:
		var bounds: Array = RANGES[key]
		var value: Variant = data.get(key, 1.0)
		config.set(key, clampf(float(value) if (value is float or value is int) else 1.0, float(bounds[0]), float(bounds[1])))
	var fights_value: Variant = data.get("fights", config.fights)
	config.fights = clampi(int(fights_value) if (fights_value is float or fights_value is int) else config.fights, FIGHTS_RANGE.x, FIGHTS_RANGE.y)
	var tier: Variant = data.get("difficulty", 0)
	config.difficulty = clampi(int(tier) if (tier is float or tier is int) else 0, 0, MAX_DIFFICULTY)
	var flag: Variant = data.get("specialists", true)
	config.specialists = flag if flag is bool else true
	var id := StringName(str(data.get("preset", DEFAULT_PRESET)))
	config.preset = id if PRESETS.has(id) or id == CUSTOM else DEFAULT_PRESET
	return config
