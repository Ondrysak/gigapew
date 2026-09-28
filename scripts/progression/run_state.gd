class_name RunState
extends RefCounted

## Run-wide progression: experience, player level and chosen upgrades.
## Survives stage changes; derived stats are rebuilt from upgrade levels.

signal xp_changed(xp: int, required: int, level: int)
## Emitted once for every level gained.
signal level_up_ready

const MAX_WEAPONS := 4

var level := 1
var xp := 0
var xp_required := 0
## Levels gained whose upgrade has not been chosen yet.
var pending_level_ups := 0
## Upgrade id -> owned level.
var upgrade_levels: Dictionary = {}
var owned_weapons: Array[UpgradeDefinition] = []

var damage_multiplier := 1.0
## Higher fires the main gun faster.
var fire_rate_multiplier := 1.0
var move_speed_multiplier := 1.0
var max_health_bonus := 0
var regen_per_second := 0.0
var pickup_radius := 3.0
var pierce_bonus := 0
var area_multiplier := 1.0
## Lower recharges auto weapons faster.
var cooldown_multiplier := 1.0
## Flat reduction per incoming hit.
var armor := 0.0
var xp_multiplier := 1.0
var projectile_bonus := 0

var _definitions: Dictionary = {}
var _xp_remainder := 0.0

func _init() -> void:
	xp_required = required_for(level)

static func required_for(p_level: int) -> int:
	return 5 + p_level * 4 + roundi(pow(float(p_level), 1.4))

func add_xp(amount: float) -> void:
	_xp_remainder += amount
	var whole := floori(_xp_remainder)
	if whole <= 0:
		return
	_xp_remainder -= whole
	xp += whole
	var gained := 0
	while xp >= xp_required:
		xp -= xp_required
		level += 1
		xp_required = required_for(level)
		gained += 1
	pending_level_ups += gained
	xp_changed.emit(xp, xp_required, level)
	for _index in range(gained):
		level_up_ready.emit()

func consume_level_up() -> bool:
	if pending_level_ups <= 0:
		return false
	pending_level_ups -= 1
	return true

func level_of(upgrade: UpgradeDefinition) -> int:
	return int(upgrade_levels.get(upgrade.id, 0))

func apply_upgrade(upgrade: UpgradeDefinition) -> void:
	_definitions[upgrade.id] = upgrade
	upgrade_levels[upgrade.id] = level_of(upgrade) + 1
	if upgrade.kind == UpgradeDefinition.Kind.WEAPON and not owned_weapons.has(upgrade):
		owned_weapons.append(upgrade)
	_recompute()

func roll_offers(pool: UpgradePool, count: int, rng: RandomNumberGenerator) -> Array[UpgradeDefinition]:
	var offers: Array[UpgradeDefinition] = []
	var candidates: Array[UpgradeDefinition] = []
	var fallbacks: Array[UpgradeDefinition] = []
	for upgrade in pool.upgrades:
		if upgrade == null:
			continue
		if upgrade.repeatable:
			fallbacks.append(upgrade)
		elif _is_eligible(upgrade):
			candidates.append(upgrade)
	_draw_weighted(candidates, offers, count, rng)
	_draw_weighted(fallbacks, offers, count, rng)
	return offers

func _is_eligible(upgrade: UpgradeDefinition) -> bool:
	if level_of(upgrade) >= upgrade.max_level:
		return false
	if upgrade.kind == UpgradeDefinition.Kind.WEAPON:
		if upgrade.weapon_scene == null:
			return false
		if not owned_weapons.has(upgrade) and owned_weapons.size() >= MAX_WEAPONS:
			return false
	return true

# Weighted sampling without replacement, appending until `offers` holds `count`.
func _draw_weighted(source: Array[UpgradeDefinition], offers: Array[UpgradeDefinition], count: int, rng: RandomNumberGenerator) -> void:
	var remaining := source.duplicate()
	while offers.size() < count and not remaining.is_empty():
		var total := 0.0
		for upgrade in remaining:
			total += maxf(upgrade.weight, 0.0)
		var pick := remaining.size() - 1
		if total > 0.0:
			var roll := rng.randf() * total
			for index in range(remaining.size()):
				roll -= maxf(remaining[index].weight, 0.0)
				if roll < 0.0:
					pick = index
					break
		else:
			pick = rng.randi_range(0, remaining.size() - 1)
		offers.append(remaining[pick])
		remaining.remove_at(pick)

func _recompute() -> void:
	damage_multiplier = 1.0
	fire_rate_multiplier = 1.0
	move_speed_multiplier = 1.0
	max_health_bonus = 0
	regen_per_second = 0.0
	pickup_radius = 3.0
	pierce_bonus = 0
	area_multiplier = 1.0
	cooldown_multiplier = 1.0
	armor = 0.0
	xp_multiplier = 1.0
	projectile_bonus = 0
	for id in upgrade_levels:
		var upgrade: UpgradeDefinition = _definitions[id]
		var stacks := int(upgrade_levels[id])
		damage_multiplier += upgrade.damage_multiplier * stacks
		fire_rate_multiplier += upgrade.fire_rate_multiplier * stacks
		move_speed_multiplier += upgrade.move_speed_multiplier * stacks
		max_health_bonus += upgrade.max_health_bonus * stacks
		regen_per_second += upgrade.regen_per_second * stacks
		pickup_radius += upgrade.pickup_radius * stacks
		pierce_bonus += upgrade.pierce_bonus * stacks
		area_multiplier += upgrade.area_multiplier * stacks
		cooldown_multiplier += upgrade.cooldown_multiplier * stacks
		armor += upgrade.armor * stacks
		xp_multiplier += upgrade.xp_multiplier * stacks
		projectile_bonus += upgrade.projectile_bonus * stacks
	damage_multiplier = maxf(damage_multiplier, 0.1)
	fire_rate_multiplier = maxf(fire_rate_multiplier, 0.1)
	move_speed_multiplier = maxf(move_speed_multiplier, 0.1)
	area_multiplier = maxf(area_multiplier, 0.1)
	cooldown_multiplier = maxf(cooldown_multiplier, 0.25)
	xp_multiplier = maxf(xp_multiplier, 0.0)
