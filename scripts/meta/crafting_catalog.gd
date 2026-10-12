class_name CraftingCatalog
extends RefCounted

static var _recipes: Array[CraftRecipe] = []

static func recipes() -> Array[CraftRecipe]:
	if not _recipes.is_empty():
		return _recipes
	var scout := _recipe(&"scout_suit", "Bunda na noční tramvaj", &"armor", "Po nasazení: +20 maximálního zdraví, +1 ochrany, +5 % rychlosti pohybu.", {&"gold": 18, &"crystal": 8})
	scout.max_health_bonus = 20
	scout.armor = 1.0
	scout.move_speed_multiplier = 0.05
	var bulwark := _recipe(&"bulwark_plate", "Kabát vyhazovače", &"armor", "Po nasazení: +45 maximálního zdraví, +3 ochrany; -5 % rychlosti pohybu.", {&"gold": 28, &"crystal": 12, &"shard": 3})
	bulwark.max_health_bonus = 45
	bulwark.armor = 3.0
	bulwark.move_speed_multiplier = -0.05
	_weapon(&"weapon_pulse", "Lahve na zálohu", preload("res://data/weapons/pulse.tres"), {&"gold": 12, &"crystal": 5})
	_weapon(&"weapon_scatter", "Bazarový rozptyl", preload("res://data/weapons/scatter.tres"), {&"gold": 16, &"crystal": 7})
	_weapon(&"weapon_rail", "Bazarový průraz", preload("res://data/weapons/rail.tres"), {&"gold": 18, &"shard": 3})
	_weapon(&"weapon_minigun", "Bazarová kadence", preload("res://data/weapons/minigun.tres"), {&"gold": 24, &"crystal": 10})
	_weapon(&"weapon_autocannon", "Bazarové výbuchy", preload("res://data/weapons/autocannon.tres"), {&"gold": 24, &"crystal": 12, &"shard": 3})
	_weapon(&"weapon_flamethrower", "Bazarový plamen", preload("res://data/weapons/flamethrower.tres"), {&"gold": 18, &"crystal": 14})
	_weapon(&"weapon_maschine", "Bedna na hard set", preload("res://data/weapons/maschine.tres"), {&"gold": 22, &"crystal": 12, &"shard": 2})
	_weapon(&"weapon_cihlomet", "Cihly ze stavby", preload("res://data/weapons/cihlomet.tres"), {&"gold": 20, &"crystal": 8, &"shard": 3})
	_weapon(&"weapon_tvarohomet", "Tvaroh pod tlakem", preload("res://data/weapons/tvarohomet.tres"), {&"gold": 20, &"crystal": 14, &"shard": 2})
	_gadget(&"splitter", "Dvojitej panák", &"projectiles", "Na hlavní zbrani: +2 projektily na výstřel s mírným rozptylem.", {&"gold": 15, &"crystal": 10})
	_gadget(&"blast_chamber", "Rána jak z výčepu", &"splash", "Na hlavní zbrani: +1,1 m poloměru výbuchu; výbuch má nejméně 60 % poškození střely.", {&"gold": 15, &"crystal": 12, &"shard": 2})
	_gadget(&"fire_converter", "Rum a zapalovač", &"fire", "Na hlavní zbrani: ohnivé poškození zapaluje nepřátele.", {&"gold": 10, &"crystal": 15})
	_gadget(&"frost_converter", "Fernet z mrazáku", &"frost", "Na hlavní zbrani: mrazivé poškození zpomaluje nepřátele.", {&"gold": 12, &"crystal": 6, &"shard": 3})
	_gadget(&"shock_converter", "Zkrat v zásuvce", &"shock", "Na hlavní zbrani: blesk přenese 40 % poškození zásahu až na 3 blízké nepřátele.", {&"gold": 12, &"crystal": 8, &"shard": 4})
	var scavenger := _recipe(&"perk_scavenger", "Průkaz šacovače", &"perk", "Odemkne Šacování kapes: zabití může přidat Cigára (2 % / 3,5 % / 5 %); boss dá 2.", {&"gold": 20, &"crystal": 8, &"shard": 3})
	scavenger.upgrade = preload("res://data/upgrades/perk_scavenger.tres")
	var vampiric := _recipe(&"perk_vampiric", "Panák na sekeru", &"perk", "Každý běh začne s bonusem Panák za účet: každých 25 zabití obnoví 2 zdraví.", {&"gold": 20, &"crystal": 10, &"shard": 4})
	vampiric.upgrade = preload("res://data/upgrades/perk_vampiric_rounds.tres")
	var mining := _recipe(&"talent_prospector", "Kurz páčení automatů", &"talent", "Za stupeň: +15 % rychlosti páčení a +5 % kořisti. Platí pro každý běh.", {&"gold": 10, &"crystal": 5})
	mining.max_rank = 5
	mining.mining_multiplier = 0.15
	mining.resource_multiplier = 0.05
	var combat := _recipe(&"talent_marksman", "Kurz disrespectu", &"talent", "Za stupeň: +5 % poškození a +2 % šance na kritický zásah. Platí pro každý běh.", {&"gold": 12, &"crystal": 4, &"shard": 1})
	combat.max_rank = 5
	combat.damage_multiplier = 0.05
	combat.crit_chance = 0.02
	var engineer := _recipe(&"talent_engineer", "Servis posledního setu", &"talent", "Za stupeň: -4 % prodlevy skillů a obnova +0,1 zdraví/s. Platí pro každý běh.", {&"gold": 10, &"crystal": 6, &"shard": 1})
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
	var recipe := _recipe(id, title, &"weapon", "Nastaví výchozí hlavní zbraň: %s. Všechny základní zbraně můžeš během běhu zdarma měnit; výroba uloží výchozí blueprint." % weapon.display_name, costs)
	recipe.weapon = weapon

static func _gadget(id: StringName, title: String, kind: StringName, description: String, costs: Dictionary) -> void:
	var recipe := _recipe(id, title, &"gadget", description, costs)
	recipe.weapon_upgrade = kind
