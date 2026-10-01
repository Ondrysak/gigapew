class_name RunState
extends RefCounted

## Run-wide progression: experience, player level, chosen upgrades, collected
## resources and the supply meter. Survives stage changes. Derived stats are
## rebuilt from every StatModifier source: class, meta upgrades, run upgrades.

signal xp_changed(xp: int, required: int, level: int)
## Emitted once for every level gained (also for full supply meters).
signal level_up_ready
## Unbanked amount of a resource collected so far.
signal resources_changed(id: StringName, amount: int)
signal supply_changed(value: int, required: int)

const MAX_WEAPONS := 4

var level := 1
var xp := 0
var xp_required := 0
## Levels gained whose upgrade has not been chosen yet.
var pending_level_ups := 0
## Upgrade id -> owned level.
var upgrade_levels: Dictionary = {}
## WEAPON upgrades in pick order (limited to MAX_WEAPONS).
var owned_weapons: Array[UpgradeDefinition] = []
## PERK upgrades in pick order; they never use weapon slots.
var owned_perks: Array[UpgradeDefinition] = []

## Three effective hand resources retained across stage loads.
var hands: Array[WeaponHand] = []
var shop_levels: Dictionary = {}
var _shop_modifiers: Array[StatModifier] = []

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
var mining_multiplier := 1.0
## Lower recharges the class ability faster.
var ability_cooldown_multiplier := 1.0
var resource_multiplier := 1.0
## Temporary auto-weapon recharge factor set by abilities (1 = none).
var cooldown_boost := 1.0
## Chance (0..1) that a hit is critical.
var crit_chance := 0.0
## Damage factor of a critical hit.
var crit_multiplier := 1.5

## Resource id -> amount collected and not yet banked.
var resources: Dictionary = {}
var supply := 0
var supply_required := 60

var _permanent: Array[StatModifier] = []
var _permanent_stacks := PackedInt32Array()
var _resource_remainder: Dictionary = {}

var _definitions: Dictionary = {}
var _xp_remainder := 0.0
# Short-lived modifiers (abilities, conditional perks), each counted once.
var _temporary: Array[StatModifier] = []
# One exposure zone at a time (e.g. Recon Flare): hits inside deal extra damage.
var _exposure_center := Vector2.ZERO
var _exposure_radius := 0.0
var _exposure_bonus := 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	xp_required = required_for(level)
	_rng.randomize()

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


func initialize_hands(definitions: Array[WeaponDefinition]) -> void:
	hands.clear()
	var fallback: WeaponDefinition = preload("res://data/weapons/pulse.tres")
	for index in range(3):
		var source := definitions[index] if index < definitions.size() else fallback
		var hand := WeaponHand.new()
		hand.setup(source if source != null else fallback)
		hands.append(hand)

func hand_definitions() -> Array[WeaponDefinition]:
	var definitions: Array[WeaponDefinition] = []
	for hand in hands:
		definitions.append(hand.definition)
	return definitions

## Round-shop boosts are run-local and survive stage changes.
func can_buy_shop_stat(id: StringName) -> bool:
	return id in [&"armor", &"health", &"power"] and int(shop_levels.get(id, 0)) < 5

func buy_shop_stat(id: StringName) -> bool:
	if not can_buy_shop_stat(id):
		return false
	var modifier := StatModifier.new()
	match id:
		&"armor":
			modifier.armor = 1.0
		&"health":
			modifier.max_health_bonus = 15
		&"power":
			modifier.damage_multiplier = 0.1
	shop_levels[id] = int(shop_levels.get(id, 0)) + 1
	_shop_modifiers.append(modifier)
	_recompute()
	return true
## Sets the modifiers that last the whole run: the class (x1) and each
## purchased meta upgrade (x its level). Call once before play.
func set_permanent_modifiers(class_definition: ClassDefinition, meta_levels: Dictionary) -> void:
	_permanent.clear()
	_permanent_stacks.clear()
	if class_definition != null:
		_permanent.append(class_definition)
		_permanent_stacks.append(1)
	for meta: StatModifier in meta_levels:
		if int(meta_levels[meta]) > 0:
			_permanent.append(meta)
			_permanent_stacks.append(int(meta_levels[meta]))
	_recompute()

func add_resource(definition: ResourceDefinition, amount: int) -> void:
	if amount <= 0:
		return
	var scaled: float = amount * resource_multiplier + float(_resource_remainder.get(definition.id, 0.0))
	var whole := floori(scaled)
	_resource_remainder[definition.id] = scaled - whole
	if whole <= 0:
		return
	resources[definition.id] = int(resources.get(definition.id, 0)) + whole
	resources_changed.emit(definition.id, resources[definition.id])
	if definition.supply_value > 0:
		supply += whole * definition.supply_value
		# A full supply meter is worth one free upgrade pick.
		while supply >= supply_required:
			supply -= supply_required
			pending_level_ups += 1
			level_up_ready.emit()
		supply_changed.emit(supply, supply_required)

## Spends collected (unbanked) resources, e.g. crystals for a console.
## Returns false and spends nothing when the run holds too few.
func spend_resource(id: StringName, amount: int) -> bool:
	var held := int(resources.get(id, 0))
	if amount < 0 or held < amount:
		return false
	resources[id] = held - amount
	resources_changed.emit(id, resources[id])
	return true

## Removes and returns the banked-type resources collected so far,
## scaled by `fraction` (rounded down), e.g. 0.5 on death.
func take_bankable(banked_ids: Array[StringName], fraction: float) -> Dictionary:
	var taken := {}
	for id in banked_ids:
		var amount := int(resources.get(id, 0))
		if amount <= 0:
			continue
		taken[id] = floori(amount * fraction)
		resources[id] = 0
		resources_changed.emit(id, 0)
	return taken

func level_of(upgrade: UpgradeDefinition) -> int:
	return int(upgrade_levels.get(upgrade.id, 0))

func apply_upgrade(upgrade: UpgradeDefinition) -> void:
	_definitions[upgrade.id] = upgrade
	upgrade_levels[upgrade.id] = level_of(upgrade) + 1
	if upgrade.kind == UpgradeDefinition.Kind.WEAPON and not owned_weapons.has(upgrade):
		owned_weapons.append(upgrade)
	elif upgrade.kind == UpgradeDefinition.Kind.PERK and not owned_perks.has(upgrade):
		owned_perks.append(upgrade)
	_recompute()

func roll_offers(pool: UpgradePool, count: int, rng: RandomNumberGenerator) -> Array[UpgradeDefinition]:
	var offers: Array[UpgradeDefinition] = []
	var candidates: Array[UpgradeDefinition] = []
	var overclocks: Array[UpgradeDefinition] = []
	var fallbacks: Array[UpgradeDefinition] = []
	for upgrade in pool.upgrades:
		if upgrade == null:
			continue
		if upgrade.repeatable:
			fallbacks.append(upgrade)
		elif _is_eligible(upgrade):
			if upgrade.kind == UpgradeDefinition.Kind.OVERCLOCK:
				overclocks.append(upgrade)
			else:
				candidates.append(upgrade)
	# A ready overclock is always offered; any others compete normally.
	var featured: Array[UpgradeDefinition] = []
	_draw_weighted(overclocks, featured, mini(1, count), rng)
	for upgrade in overclocks:
		if not featured.has(upgrade):
			candidates.append(upgrade)
	_draw_weighted(candidates, offers, count - featured.size(), rng)
	_draw_weighted(fallbacks, offers, count - featured.size(), rng)
	for upgrade in featured:
		offers.insert(rng.randi_range(0, offers.size()), upgrade)
	return offers

## True once an OVERCLOCK upgrade targeting this weapon upgrade was taken.
func is_overclocked(target: UpgradeDefinition) -> bool:
	for id in upgrade_levels:
		var upgrade: UpgradeDefinition = _definitions[id]
		if upgrade.kind == UpgradeDefinition.Kind.OVERCLOCK and upgrade.overclock_target != null and upgrade.overclock_target.id == target.id:
			return true
	return false

## Adds a modifier counted once until removed (ability boosts, conditional
## perks). max_health_bonus in temporary modifiers is ignored by the player.
func add_temporary_modifier(modifier: StatModifier) -> void:
	if modifier != null and not _temporary.has(modifier):
		_temporary.append(modifier)
		_recompute()

func remove_temporary_modifier(modifier: StatModifier) -> void:
	if _temporary.has(modifier):
		_temporary.erase(modifier)
		_recompute()

## Re-derives stats after a registered temporary modifier's fields changed.
func refresh_modifiers() -> void:
	_recompute()

## Marks a floor zone: hits on enemies inside deal (1 + bonus) damage.
func set_exposure_zone(center: Vector3, radius: float, bonus: float) -> void:
	_exposure_center = Vector2(center.x, center.z)
	_exposure_radius = maxf(0.0, radius)
	_exposure_bonus = bonus

func clear_exposure_zone() -> void:
	_exposure_radius = 0.0
	_exposure_bonus = 0.0

## Damage factor from the exposure zone for a hit at `at` (1 outside).
func exposure_scale(at: Vector3) -> float:
	if _exposure_radius <= 0.0:
		return 1.0
	var offset := Vector2(at.x, at.z) - _exposure_center
	return 1.0 + _exposure_bonus if offset.length_squared() <= _exposure_radius * _exposure_radius else 1.0

## Rolls crit_chance once.
func roll_critical() -> bool:
	return crit_chance > 0.0 and _rng.randf() < crit_chance

## Per-hit damage factor for weapons: exposure zone times a crit roll.
func hit_scale(at: Vector3) -> float:
	var scale := exposure_scale(at)
	return scale * crit_multiplier if roll_critical() else scale

func _is_eligible(upgrade: UpgradeDefinition) -> bool:
	if level_of(upgrade) >= upgrade.max_level:
		return false
	if upgrade.kind == UpgradeDefinition.Kind.WEAPON:
		if upgrade.weapon_scene == null:
			return false
		if not owned_weapons.has(upgrade) and owned_weapons.size() >= MAX_WEAPONS:
			return false
	elif upgrade.kind == UpgradeDefinition.Kind.OVERCLOCK:
		var target := upgrade.overclock_target
		if target == null or level_of(target) < target.max_level:
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
	mining_multiplier = 1.0
	ability_cooldown_multiplier = 1.0
	resource_multiplier = 1.0
	crit_chance = 0.0
	crit_multiplier = 1.5
	for index in _permanent.size():
		_add_modifier(_permanent[index], _permanent_stacks[index])
	for id in upgrade_levels:
		_add_modifier(_definitions[id], int(upgrade_levels[id]))
	for modifier in _shop_modifiers:
		_add_modifier(modifier, 1)
	for modifier in _temporary:
		_add_modifier(modifier, 1)
	damage_multiplier = maxf(damage_multiplier, 0.1)
	fire_rate_multiplier = maxf(fire_rate_multiplier, 0.1)
	move_speed_multiplier = maxf(move_speed_multiplier, 0.1)
	area_multiplier = maxf(area_multiplier, 0.1)
	cooldown_multiplier = maxf(cooldown_multiplier, 0.25)
	xp_multiplier = maxf(xp_multiplier, 0.0)
	mining_multiplier = maxf(mining_multiplier, 0.1)
	ability_cooldown_multiplier = maxf(ability_cooldown_multiplier, 0.25)
	resource_multiplier = maxf(resource_multiplier, 0.0)
	crit_chance = clampf(crit_chance, 0.0, 1.0)
	crit_multiplier = maxf(crit_multiplier, 1.0)

func _add_modifier(modifier: StatModifier, stacks: int) -> void:
	damage_multiplier += modifier.damage_multiplier * stacks
	fire_rate_multiplier += modifier.fire_rate_multiplier * stacks
	move_speed_multiplier += modifier.move_speed_multiplier * stacks
	max_health_bonus += modifier.max_health_bonus * stacks
	regen_per_second += modifier.regen_per_second * stacks
	pickup_radius += modifier.pickup_radius * stacks
	pierce_bonus += modifier.pierce_bonus * stacks
	area_multiplier += modifier.area_multiplier * stacks
	cooldown_multiplier += modifier.cooldown_multiplier * stacks
	armor += modifier.armor * stacks
	xp_multiplier += modifier.xp_multiplier * stacks
	projectile_bonus += modifier.projectile_bonus * stacks
	mining_multiplier += modifier.mining_multiplier * stacks
	ability_cooldown_multiplier += modifier.ability_cooldown_multiplier * stacks
	resource_multiplier += modifier.resource_multiplier * stacks
	crit_chance += modifier.crit_chance * stacks
	crit_multiplier += modifier.crit_multiplier * stacks
