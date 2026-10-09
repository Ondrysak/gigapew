class_name CraftingCatalog
extends RefCounted

static var _recipes: Array[CraftRecipe] = []

static func recipes() -> Array[CraftRecipe]:
	if not _recipes.is_empty():
		return _recipes
	var scout := _recipe(&"scout_suit", "Scout Suit", &"armor", "Equip: +20 maximum health, +1 armor, +5% movement speed.", {&"gold": 18, &"crystal": 8})
	scout.max_health_bonus = 20
	scout.armor = 1.0
	scout.move_speed_multiplier = 0.05
	var bulwark := _recipe(&"bulwark_plate", "Bulwark Plate", &"armor", "Equip: +45 maximum health and +3 armor; -5% movement speed.", {&"gold": 28, &"crystal": 12, &"shard": 3})
	bulwark.max_health_bonus = 45
	bulwark.armor = 3.0
	bulwark.move_speed_multiplier = -0.05
	_weapon(&"weapon_pulse", "Pulse Blueprint", preload("res://data/weapons/pulse.tres"), {&"gold": 12, &"crystal": 5})
	_weapon(&"weapon_scatter", "Scatter Blueprint", preload("res://data/weapons/scatter.tres"), {&"gold": 16, &"crystal": 7})
	_weapon(&"weapon_rail", "Rail Blueprint", preload("res://data/weapons/rail.tres"), {&"gold": 18, &"shard": 3})
	_weapon(&"weapon_minigun", "Minigun Blueprint", preload("res://data/weapons/minigun.tres"), {&"gold": 24, &"crystal": 10})
	_weapon(&"weapon_autocannon", "Autocannon Blueprint", preload("res://data/weapons/autocannon.tres"), {&"gold": 24, &"crystal": 12, &"shard": 3})
	_weapon(&"weapon_flamethrower", "Flamethrower Blueprint", preload("res://data/weapons/flamethrower.tres"), {&"gold": 18, &"crystal": 14})
	_weapon(&"weapon_baton", "Shock Baton Blueprint", preload("res://data/weapons/baton.tres"), {})
	_weapon(&"weapon_cleaver", "Cleaver Blueprint", preload("res://data/weapons/cleaver.tres"), {&"gold": 6, &"crystal": 2})
	_gadget(&"splitter", "Projectile Splitter", &"projectiles", "Equip on one hand: +2 projectiles per shot, with a modest spread.", {&"gold": 15, &"crystal": 10})
	_gadget(&"blast_chamber", "Blast Chamber", &"splash", "Equip on one hand: +1.1 m splash radius; blasts deal at least 60% shot damage.", {&"gold": 15, &"crystal": 12, &"shard": 2})
	_gadget(&"fire_converter", "Cinder Converter", &"fire", "Equip on one hand: fire damage ignites enemies.", {&"gold": 10, &"crystal": 15})
	_gadget(&"frost_converter", "Cryo Converter", &"frost", "Equip on one hand: frost damage slows enemies.", {&"gold": 12, &"crystal": 6, &"shard": 3})
	_gadget(&"shock_converter", "Arc Converter", &"shock", "Equip on one hand: shock chains 40% hit damage to up to three nearby enemies.", {&"gold": 12, &"crystal": 8, &"shard": 4})
	var scavenger := _recipe(&"perk_scavenger", "Salvage License", &"perk", "Unlocks Scavenger: kills can rarely salvage Cinder Crystals (2% / 3.5% / 5%); bosses yield 2.", {&"gold": 20, &"crystal": 8, &"shard": 3})
	scavenger.upgrade = preload("res://data/upgrades/perk_scavenger.tres")
	var vampiric := _recipe(&"perk_vampiric", "Vampiric Implant", &"perk", "Start every run with Vampiric Rounds: every 25 kills restores 2 health.", {&"gold": 20, &"crystal": 10, &"shard": 4})
	vampiric.upgrade = preload("res://data/upgrades/perk_vampiric_rounds.tres")
	var mining := _recipe(&"talent_prospector", "Prospector Training", &"talent", "Each rank: +15% mining damage and +5% mineral yield. Applies to every run.", {&"gold": 10, &"crystal": 5})
	mining.max_rank = 5
	mining.mining_multiplier = 0.15
	mining.resource_multiplier = 0.05
	var combat := _recipe(&"talent_marksman", "Marksman Training", &"talent", "Each rank: +5% damage and +2% critical chance. Applies to every run.", {&"gold": 12, &"crystal": 4, &"shard": 1})
	combat.max_rank = 5
	combat.damage_multiplier = 0.05
	combat.crit_chance = 0.02
	var engineer := _recipe(&"talent_engineer", "Field Engineering", &"talent", "Each rank: abilities recharge 4% faster and +0.1 health regeneration per second.", {&"gold": 10, &"crystal": 6, &"shard": 1})
	engineer.max_rank = 5
	engineer.ability_cooldown_multiplier = -0.04
	engineer.regen_per_second = 0.1
	return _recipes

static func find(id: StringName) -> CraftRecipe:
	for recipe in recipes():
		if recipe.id == id:
			return recipe
	return null

static func _recipe(id: StringName, title: String, category: StringName, description: String, costs: Dictionary) -> CraftRecipe:
	var recipe := CraftRecipe.new()
	recipe.id = id
	recipe.display_name = title
	recipe.category = category
	recipe.description = description
	recipe.costs = costs
	_recipes.append(recipe)
	return recipe

static func _weapon(id: StringName, title: String, weapon: WeaponDefinition, costs: Dictionary) -> void:
	var details := weapon.description
	if weapon.kind == WeaponDefinition.Kind.MELEE:
		details += ". %d damage, %.0f-degree arc, %.1f m reach, %.2f s swing cadence; no ammunition or reload" % [weapon.damage, weapon.melee_arc_degrees, weapon.range_meters, weapon.fire_interval]
	var recipe := _recipe(id, title, &"weapon", "Unlock %s for any hand. %s. Selected-class starting weapons remain free." % [weapon.display_name, details], costs)
	recipe.weapon = weapon

static func _gadget(id: StringName, title: String, kind: StringName, description: String, costs: Dictionary) -> void:
	var recipe := _recipe(id, title, &"gadget", description, costs)
	recipe.hand_upgrade = kind
