class_name RoundShop
extends RefCounted

## Stage-clear stock, paid from banked minerals. CATALOG is the single table of
## every shop upgrade: WEAPON MODS (FIREPOWER, PAYLOAD, ELEMENT tracks) are
## applied to the primary by WeaponBuild; SUIT SYSTEMS last the run through
## RunState. Stock is rolled per section and every purchase validates the full
## price before anything is applied or charged.

enum Track { FIREPOWER, PAYLOAD, ELEMENT, SUIT }
enum Section { MODS, SUIT }

const TRACK_NAMES: Array[String] = ["FIREPOWER", "PAYLOAD", "ELEMENT", "SUIT"]
const MOD_SLOTS := 4
const SUIT_SLOTS := 2
## Every price adds the stage's gold: BASE_GOLD + GOLD_PER_STAGE per cleared
## stage (stage index capped at GOLD_STAGE_CAP); `price` holds the gold offset
## and flat crystal/shard amounts.
const BASE_GOLD := 6
const GOLD_PER_STAGE := 2
const GOLD_STAGE_CAP := 5
## `stat` names the primary/run stat the preview compares. ELEMENT conversions
## are mutually exclusive: each conversion replaces the primary's damage type.
const CATALOG := {
	&"damage": {"name": "Hardened Output", "effect": "+20% base damage per rank", "track": Track.FIREPOWER, "stat": "DMG", "max_rank": 5, "price": {&"gold": 0, &"crystal": 2}},
	&"cadence": {"name": "Accelerated Cycling", "effect": "+15% attack rate per rank", "track": Track.FIREPOWER, "stat": "RATE", "max_rank": 5, "price": {&"gold": 0, &"crystal": 2}},
	&"projectiles": {"name": "Projectile Splitter", "effect": "+2 pellets per shot", "track": Track.PAYLOAD, "stat": "PELLETS", "max_rank": 6, "price": {&"gold": 0, &"crystal": 5}},
	&"splash": {"name": "Blast Chamber", "effect": "+1.1 m blast on every hit", "track": Track.PAYLOAD, "stat": "SPLASH", "max_rank": 4, "price": {&"gold": 0, &"crystal": 5}},
	&"pierce": {"name": "Penetrator", "effect": "Shots pierce +1 enemy", "track": Track.PAYLOAD, "stat": "PIERCE", "max_rank": 4, "price": {&"gold": 0, &"shard": 1}},
	&"fire": {"name": "Cinder Conversion", "effect": "Fire damage: ignites targets", "track": Track.ELEMENT, "stat": "TYPE", "max_rank": 1, "price": {&"gold": -2, &"crystal": 7}},
	&"frost": {"name": "Cryo Conversion", "effect": "Frost damage: slows targets", "track": Track.ELEMENT, "stat": "TYPE", "max_rank": 1, "price": {&"gold": -2, &"crystal": 3, &"shard": 1}},
	&"shock": {"name": "Arc Conversion", "effect": "Shock damage: chains to others", "track": Track.ELEMENT, "stat": "TYPE", "max_rank": 1, "price": {&"gold": -2, &"crystal": 3, &"shard": 1}},
	&"armor": {"name": "Field Plating", "effect": "+1 armor against every hit", "track": Track.SUIT, "stat": "ARMOR", "max_rank": 5, "price": {&"gold": 0, &"crystal": 3}},
	&"health": {"name": "Reinforced Suit", "effect": "+15 maximum health", "track": Track.SUIT, "stat": "HEALTH", "max_rank": 5, "price": {&"gold": -1, &"crystal": 2}},
	&"power": {"name": "Combat Calibration", "effect": "+10% damage, every weapon", "track": Track.SUIT, "stat": "POWER", "max_rank": 5, "price": {&"gold": 0, &"crystal": 2}},
}

## Offers 0..MOD_SLOTS-1 are weapon mods, the rest suit systems:
## {id, section, cost, sold}.
var offers: Array[Dictionary] = []
var _state: RunState
var _stage := 0
var _rerolls := 0
var _rng := RandomNumberGenerator.new()

# ------------------------------------------------------------ catalog

static func track(id: StringName) -> int:
	return int(CATALOG[id].track) if CATALOG.has(id) else -1

static func is_weapon_mod(id: StringName) -> bool:
	return CATALOG.has(id) and int(CATALOG[id].track) != Track.SUIT

static func max_rank(id: StringName) -> int:
	return int(CATALOG[id].max_rank) if CATALOG.has(id) else 0

static func icon(id: StringName) -> Texture2D:
	return GameIcons.lookup(&"shop", id)

static func ids_in_track(value: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in CATALOG:
		if int(CATALOG[id].track) == value:
			ids.append(id)
	return ids

static func weapon_stats(definition: WeaponDefinition, projectile_bonus: int) -> Dictionary:
	if definition == null:
		return {}
	var rate := 1.0 / maxf(definition.fire_interval, 0.001)
	return {
		"DMG": str(definition.damage),
		"RATE": "%.1f/s" % rate if rate < 100.0 else "%d/s" % roundi(rate),
		"PELLETS": str(clampi(definition.pellet_count + projectile_bonus, 1, WeaponBuild.MAX_PROJECTILES)),
		"SPLASH": "%.1fm" % definition.explosion_radius if definition.explosion_radius > 0.0 else "—",
		"PIERCE": str(definition.pierce),
		"TYPE": DamageType.label(definition.damage_type).to_upper(),
	}

## Whole numbers without decimals, otherwise one decimal.
static func number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value

# ------------------------------------------------------------ stock

func setup(state: RunState, stage: int, seed: int) -> void:
	_state = state
	_stage = maxi(stage, 0)
	_rerolls = 0
	_rng.seed = seed ^ ((_stage + 1) * 104729)
	offers.clear()
	_restock()

func section_of(index: int) -> int:
	return Section.MODS if index < MOD_SLOTS else Section.SUIT

func rank(id: StringName) -> int:
	if _state == null:
		return 0
	if is_weapon_mod(id):
		return _state.primary.rank(id) if _state.primary != null else 0
	return int(_state.shop_levels.get(id, 0))

func is_maxed(id: StringName) -> bool:
	return CATALOG.has(id) and rank(id) >= max_rank(id)

func can_buy(index: int) -> bool:
	if _state == null or index < 0 or index >= offers.size():
		return false
	var offer := offers[index]
	if bool(offer.sold) or not _effect_available(StringName(offer.id)):
		return false
	return Profile.can_pay(offer.cost)

func buy(index: int) -> bool:
	if not can_buy(index):
		return false
	var offer := offers[index]
	var id := StringName(offer.id)
	# Neither build nor suit mutations emit signals. Pay after the effect,
	# so currency observers see a complete purchase; validation cannot drift.
	var applied := _state.primary.upgrade(id) if is_weapon_mod(id) else _state.buy_shop_stat(id)
	if not applied:
		return false
	offer.sold = true
	return Profile.pay(offer.cost)

func preview(id: StringName) -> Dictionary:
	if _state == null or not CATALOG.has(id):
		return {}
	var stat := String(CATALOG[id].stat)
	if is_weapon_mod(id):
		var weapon := _state.primary
		if weapon == null or not weapon.supports(id):
			return {"stat": stat, "from": "—", "to": ""}
		var now := weapon_stats(weapon.definition, _state.projectile_bonus)
		var next := weapon.preview(id)
		return {"stat": stat, "from": now[stat], "to": weapon_stats(next, _state.projectile_bonus)[stat] if next != null else ""}
	var available := _effect_available(id)
	match id:
		&"armor":
			return {"stat": stat, "from": number(_state.armor), "to": number(_state.armor + 1.0) if available else ""}
		&"health":
			return {"stat": stat, "from": "+%d" % _state.max_health_bonus, "to": "+%d" % (_state.max_health_bonus + 15) if available else ""}
	return {"stat": stat, "from": "×%.2f" % _state.damage_multiplier, "to": "×%.2f" % (_state.damage_multiplier + 0.1) if available else ""}

func ability_cost(slot: int) -> Dictionary:
	if _state == null or not _state.can_upgrade_ability(slot):
		return {}
	var next := _state.ability_rank(slot) + 1
	return {&"gold": BASE_GOLD + mini(_stage, GOLD_STAGE_CAP) * GOLD_PER_STAGE + 3 * next,
		&"crystal": 2 * next, &"shard": next - 1}

func can_buy_ability(slot: int) -> bool:
	return _state != null and _state.can_upgrade_ability(slot) and Profile.can_pay(ability_cost(slot))

func buy_ability(slot: int) -> bool:
	if not can_buy_ability(slot):
		return false
	var cost := ability_cost(slot)
	if not _state.upgrade_ability(slot):
		return false
	return Profile.pay(cost)

func ability_preview(slot: int) -> Dictionary:
	if _state == null:
		return {}
	var metadata := _state.ability_metadata(slot)
	if metadata.is_empty():
		return {}
	var current := _state.ability_rank(slot)
	return {"name": metadata.name, "icon": metadata.icon, "description": metadata.description,
		"rank": current, "max_rank": RunState.MAX_ABILITY_RANK, "stat": "ABILITY",
		"effect": "+25% base damage · -12% base cooldown · +15% duration per rank",
		"from": _ability_stats(slot, current),
		"to": _ability_stats(slot, current + 1) if _state.can_upgrade_ability(slot) else ""}

func _ability_stats(slot: int, ability_rank: int) -> String:
	var metadata := _state.ability_metadata(slot)
	var cooldown: float = metadata.cooldown * ActiveAbility.ability_cooldown_scale(ability_rank) * _state.ability_cooldown_multiplier
	return "DMG %d%% · CD %.1fs · TIME %d%%" % [
		roundi(100.0 * ActiveAbility.ability_damage_scale(ability_rank) * _state.damage_multiplier),
		cooldown, roundi(100.0 * ActiveAbility.ability_duration_scale(ability_rank))]

func reroll_cost() -> Dictionary:
	return {&"gold": 3 + _rerolls * 3, &"crystal": 1 + _rerolls}

## A reroll needs an unsold card and at least one effect left to roll.
func can_reroll() -> bool:
	if _state == null or not Profile.can_pay(reroll_cost()):
		return false
	var unsold := false
	for offer in offers:
		unsold = unsold or not bool(offer.sold)
	if not unsold:
		return false
	for id: StringName in CATALOG:
		if _effect_available(id):
			return true
	return false

## Replaces every unsold card in both sections; sold cards stay sold.
func reroll() -> bool:
	if not can_reroll():
		return false
	if not Profile.pay(reroll_cost()):
		return false
	_rerolls += 1
	_restock()
	return true

func _effect_available(id: StringName) -> bool:
	if _state == null or not CATALOG.has(id):
		return false
	if is_weapon_mod(id):
		return _state.primary != null and _state.primary.can_upgrade(id)
	return rank(id) < max_rank(id) and _state.can_buy_shop_stat(id)

func _restock() -> void:
	var previous := offers.duplicate()
	offers.resize(MOD_SLOTS + SUIT_SLOTS)
	var mod_ids: Array[StringName] = []
	for value in [Track.FIREPOWER, Track.PAYLOAD, Track.ELEMENT]:
		mod_ids.append_array(ids_in_track(value))
	_restock_section(Section.MODS, 0, MOD_SLOTS, mod_ids, previous)
	_restock_section(Section.SUIT, MOD_SLOTS, SUIT_SLOTS, ids_in_track(Track.SUIT), previous)

## Unsold slots draw distinct ids: effects not on display first, then the ones
## being replaced, and capped effects only when nothing else is left (can_buy
## refuses those, so they never charge). One ELEMENT conversion per roll unless
## the pool runs dry.
func _restock_section(section: int, first: int, count: int, ids: Array[StringName], previous: Array) -> void:
	var kept: Array[StringName] = []
	var shown: Array[StringName] = []
	for index in range(first, mini(first + count, previous.size())):
		var offer: Dictionary = previous[index]
		if bool(offer.sold):
			kept.append(StringName(offer.id))
		else:
			shown.append(StringName(offer.id))
	var fresh: Array[StringName] = []
	var repeat: Array[StringName] = []
	var exhausted: Array[StringName] = []
	for id in ids:
		if id in kept:
			continue
		if not _effect_available(id):
			exhausted.append(id)
		elif id in shown:
			repeat.append(id)
		else:
			fresh.append(id)
	var elements := kept.filter(func(id: StringName) -> bool: return track(id) == Track.ELEMENT).size()
	for index in range(first, first + count):
		if index < previous.size() and bool(previous[index].sold):
			offers[index] = previous[index]
			continue
		var id := _draw([fresh, repeat, exhausted], elements > 0)
		elements += 1 if track(id) == Track.ELEMENT else 0
		offers[index] = {"id": id, "section": section, "cost": _price(id), "sold": false}

func _draw(pools: Array, avoid_element: bool) -> StringName:
	for strict in ([true, false] if avoid_element else [false]):
		for pool: Array[StringName] in pools:
			var options := pool.filter(func(id: StringName) -> bool: return not strict or track(id) != Track.ELEMENT)
			if options.is_empty():
				continue
			var id: StringName = options[_rng.randi_range(0, options.size() - 1)]
			pool.erase(id)
			return id
	return &""

func _price(id: StringName) -> Dictionary:
	var gold := BASE_GOLD + mini(_stage, GOLD_STAGE_CAP) * GOLD_PER_STAGE
	var cost := {}
	var price: Dictionary = CATALOG[id].price
	for mineral: StringName in price:
		cost[mineral] = int(price[mineral]) + (gold if mineral == &"gold" else 0)
	return cost
