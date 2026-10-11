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
## A hero skill slot became usable (guided start reveals them by level).
signal ability_unlocked(slot: int)
signal gear_changed

const MAX_WEAPONS := 4
const MAX_GEAR := 4
const BASE_CRIT_MULTIPLIER := 2.0
## Precision adds one base-damage unit; never stacks a second random multiplier.
const WEAK_SPOT_CRIT_BONUS := 1.0
## Guided start: player level at which each skill slot (1–5) unlocks, and the
## levels at which perk and gun-mod cards join the level-up pool.
const ABILITY_UNLOCK_LEVELS: Array[int] = [1, 2, 3, 5, 7]
const PERK_UNLOCK_LEVEL := 3
const GUN_MOD_UNLOCK_LEVEL := 5

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
## Four passive slots, retained only for this run.
var gear: Array[GearDefinition] = []
var gear_health_multiplier := 1.0

## Effective primary and ordered hero skills retained across stage loads.
var primary: WeaponBuild
var available_weapons: Array[WeaponDefinition] = []
var ability_scenes: Array[PackedScene] = []
const MAX_ABILITY_RANK := 3
var ability_ranks := PackedInt32Array([0, 0, 0, 0, 0])
## Guided runs reveal skills and upgrade kinds gradually; otherwise all at once.
var guided := false
var unlocked_abilities := 5
var _ability_offers: Dictionary = {}
var _ability_metadata: Dictionary = {}
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
## Chance (0..1) that a hit is critical.
var crit_chance := 0.0
## Damage factor of a critical hit.
var crit_multiplier := BASE_CRIT_MULTIPLIER

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
# Independent exposure zones: overlapping skills use the strongest bonus.
var _exposure_zones: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	xp_required = required_for(level)
	_rng.randomize()

func has_gear(id: StringName) -> bool:
	for item in gear:
		if item.id == id:
			return true
	return false

## Replacement is always explicit; never discard an item to make room.
func equip_gear(item: GearDefinition, replace_slot: int = -1) -> bool:
	if item == null or GearCatalog.find(item.id) == null or has_gear(item.id):
		return false
	if replace_slot < -1 or replace_slot >= gear.size():
		return false
	if replace_slot == -1:
		if gear.size() >= MAX_GEAR:
			return false
		gear.append(item)
	else:
		gear[replace_slot] = item
	_recompute()
	gear_changed.emit()
	return true

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
	if gained > 0:
		_refresh_unlocks()
	xp_changed.emit(xp, xp_required, level)
	for _index in range(gained):
		level_up_ready.emit()

func consume_level_up() -> bool:
	if pending_level_ups <= 0:
		return false
	pending_level_ups -= 1
	return true

## Call once at run start. A guided run begins with only the first skill.
func start_guided(enabled: bool) -> void:
	guided = enabled
	unlocked_abilities = _unlocks_for(level) if enabled else 5

func is_ability_unlocked(slot: int) -> bool:
	return slot >= 0 and slot < unlocked_abilities

func ability_unlock_level(slot: int) -> int:
	return ABILITY_UNLOCK_LEVELS[clampi(slot, 0, 4)] if guided else 1

func _unlocks_for(p_level: int) -> int:
	var count := 0
	for required in ABILITY_UNLOCK_LEVELS:
		if p_level >= required:
			count += 1
	return count

func _refresh_unlocks() -> void:
	var reached := _unlocks_for(level) if guided else 5
	while unlocked_abilities < reached:
		unlocked_abilities += 1
		ability_unlocked.emit(unlocked_abilities - 1)

func initialize_primary(source: WeaponDefinition) -> void:
	primary = WeaponBuild.new()
	primary.setup(source if source != null else load("res://data/weapons/pulse.tres") as WeaponDefinition)
	if not available_weapons.has(primary.source):
		available_weapons.append(primary.source)

func swap_primary(source: WeaponDefinition) -> bool:
	if primary == null or source == null or not available_weapons.has(source):
		return false
	primary.swap(source)
	return true

func ability_rank(slot: int) -> int:
	return ability_ranks[slot] if slot >= 0 and slot < ability_ranks.size() else 0

func can_upgrade_ability(slot: int) -> bool:
	return is_ability_unlocked(slot) and slot < ability_scenes.size() \
			and ability_scenes[slot] != null and ability_rank(slot) < MAX_ABILITY_RANK

func upgrade_ability(slot: int) -> bool:
	if not can_upgrade_ability(slot):
		return false
	ability_ranks[slot] += 1
	return true

## Read scene presentation once without putting an effect in the live tree.
func ability_metadata(slot: int) -> Dictionary:
	if slot < 0 or slot >= 5 or slot >= ability_scenes.size() or ability_scenes[slot] == null:
		return {}
	var scene := ability_scenes[slot]
	if not _ability_metadata.has(scene):
		var ability := scene.instantiate() as ActiveAbility
		if ability == null:
			return {}
		var strength_label := "RÁNA"
		var duration_label := "ČAS"
		var mastery_effect := "Za stupeň: poškození +25 % základu · prodleva -12 % základu · trvání +15 %."
		if ability is BattleFrenzy:
			strength_label = "TEMPO+"
			mastery_effect = "Za stupeň: bonus rychlosti střelby +25 % základu · prodleva -12 % základu · trvání +15 %."
		elif ability is Overdrive:
			strength_label = ""
			mastery_effect = "Za stupeň: prodleva -12 % základu · trvání +15 %. Síla zrychlení autozbraní se nemění."
		elif ability is SeismicCharge or ability is SuppressionBarrage:
			duration_label = ""
			mastery_effect = "Za stupeň: poškození +25 % základu · prodleva -12 % základu. Dosah a počet ran se nemění."
		elif ability is BlinkDash or ability is DrillDash or ability is GrappleVault:
			duration_label = "ŠTÍT"
			mastery_effect = "Za stupeň: poškození +25 % základu · prodleva -12 % základu · nezranitelnost +15 %. Délka přesunu se nemění."
		elif ability is ReconFlare:
			mastery_effect = "Za stupeň: poškození i bonus označení +25 % základu · prodleva -12 % základu · trvání +15 %."
		elif ability is RepairDrone:
			mastery_effect = "Za stupeň: poškození +25 % základu · prodleva -12 % základu · trvání, štít i celkové léčení +15 %."
		_ability_metadata[scene] = {
			"name": ability.display_name, "description": ability.description,
			"icon": ability.icon, "color": ability.accent_color,
			"cooldown": ability.base_cooldown,
			"mastery_effect": mastery_effect, "strength_label": strength_label,
			"duration_label": duration_label, "strength_uses_damage": not (ability is BattleFrenzy),
		}
		ability.free()
	return _ability_metadata[scene]

func ability_upgrade_offer(slot: int) -> UpgradeDefinition:
	var metadata := ability_metadata(slot)
	if metadata.is_empty():
		return null
	if not _ability_offers.has(slot):
		var offer := UpgradeDefinition.new()
		offer.id = StringName("ability_slot_%d" % slot)
		offer.kind = UpgradeDefinition.Kind.ABILITY
		offer.ability_slot = slot
		offer.max_level = MAX_ABILITY_RANK
		_ability_offers[slot] = offer
	var offer: UpgradeDefinition = _ability_offers[slot]
	offer.display_name = "%s · mistrovství" % metadata.name
	offer.icon = metadata.icon
	offer.accent_color = metadata.color
	offer.description = "%s\n%s" % [metadata.description, metadata.mastery_effect]
	return offer

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
	if upgrade.kind == UpgradeDefinition.Kind.ABILITY:
		return ability_rank(upgrade.ability_slot)
	return int(upgrade_levels.get(upgrade.id, 0))

func apply_upgrade(upgrade: UpgradeDefinition) -> void:
	if upgrade == null:
		return
	if upgrade.kind == UpgradeDefinition.Kind.ABILITY:
		upgrade_ability(upgrade.ability_slot)
		return
	if not upgrade.repeatable and not _is_eligible(upgrade):
		return
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
	for slot in range(5):
		var ability_offer := ability_upgrade_offer(slot)
		if ability_offer != null and can_upgrade_ability(slot):
			candidates.append(ability_offer)
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

## Each skill owns its zone, so cancelling one never clears another.
func add_exposure_zone(source: ActiveAbility, center: Vector3, radius: float, bonus: float) -> void:
	_exposure_zones[source] = {"center": Vector2(center.x, center.z), "radius_squared": radius * radius, "bonus": bonus}

func remove_exposure_zone(source: ActiveAbility) -> void:
	_exposure_zones.erase(source)

func exposure_scale(at: Vector3) -> float:
	var point := Vector2(at.x, at.z)
	var strongest := 0.0
	for source in _exposure_zones:
		var zone: Dictionary = _exposure_zones[source]
		if point.distance_squared_to(zone.center) <= float(zone.radius_squared):
			strongest = maxf(strongest, float(zone.bonus))
	return 1.0 + strongest

## Rolls crit_chance once.
func roll_critical() -> bool:
	return crit_chance > 0.0 and _rng.randf() < crit_chance

## Per-hit damage factor for weapons: exposure zone times a crit roll.
func hit_scale(at: Vector3) -> float:
	var scale := exposure_scale(at)
	return scale * crit_multiplier if roll_critical() else scale

func _is_eligible(upgrade: UpgradeDefinition) -> bool:
	if upgrade.kind == UpgradeDefinition.Kind.ABILITY:
		return can_upgrade_ability(upgrade.ability_slot)
	if level_of(upgrade) >= upgrade.max_level:
		return false
	if guided and upgrade.kind == UpgradeDefinition.Kind.PERK and level < PERK_UNLOCK_LEVEL:
		return false
	if guided and upgrade.kind == UpgradeDefinition.Kind.GUN_MOD and level < GUN_MOD_UNLOCK_LEVEL:
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
	crit_multiplier = BASE_CRIT_MULTIPLIER
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
	gear_health_multiplier = 0.65 if has_gear(&"glass") else 1.0
	if has_gear(&"glass"):
		damage_multiplier *= 1.5

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
