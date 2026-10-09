extends Node

## Persistent player profile (autoload `Profile`): currencies, class unlocks,
## ability unlocks and loadouts, permanent upgrade levels, records and
## settings. Stored as JSON in user://profile.json and saved after every
## mutation. A missing, corrupt or incompatible file resets to defaults (a
## corrupt file is kept as .bak); keys missing from older saves keep defaults.

signal currency_changed(id: StringName, amount: int)
## Emitted after any saved change (currency, unlock, upgrade, record, setting).
signal changed

const SAVE_PATH := "user://profile.json"
const BACKUP_PATH := "user://profile.json.bak"
const VERSION := 1
const ROSTER_PATH := "res://data/classes/roster.tres"
const META_POOL_PATH := "res://data/meta/pool.tres"
const DEFAULT_SETTINGS := {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"mouse_sensitivity": 1.0,
	"fullscreen": false,
}
const DEFAULT_RECORDS := {
	"best_time": 0.0,
	"best_kills": 0,
	"best_level": 0,
	"runs": 0,
	"victories": 0,
	"total_kills": 0,
	"deepest_stage": 0,
}
const SENSITIVITY_RANGE := Vector2(0.3, 2.5)
const VOLUME_BUSES := {
	"master_volume": &"Master",
	"music_volume": &"Music",
	"sfx_volume": &"SFX",
}

## Class chosen in the menu; the game reads it at run start. Persisted.
var selected_class_id: StringName:
	set(value):
		if selected_class_id == value:
			return
		selected_class_id = value
		_mutated()
var roster: ClassRoster
var meta_pool: MetaPool
## best_time, best_kills, best_level, runs, victories, total_kills,
## deepest_stage, and last_run (the latest record_run summary, JSON-safe).
var records: Dictionary = {}
## master_volume, music_volume, sfx_volume (0..1), mouse_sensitivity
## (multiplier), fullscreen (bool). Change through set_setting().
var settings: Dictionary = {}

var _currencies: Dictionary = {}
var _unlocked_classes: Dictionary = {}
var _meta_levels: Dictionary = {}
# "class_id/ability_key" -> true for bought alternate abilities.
var _unlocked_abilities: Dictionary = {}
# class_id -> ability_key of the equipped ability (missing = class default).
var _equipped_abilities: Dictionary = {}
var _crafted_ranks: Dictionary = {}
var _equipped_armor: StringName = &""
var _equipped_weapons: Dictionary = {}
var _equipped_gadgets: Dictionary = {}
var _loading := false
# False in the visual test lab: the player's save is neither read nor written.
var _persistent := true

func _ready() -> void:
	if ResourceLoader.exists(ROSTER_PATH):
		roster = load(ROSTER_PATH) as ClassRoster
	if ResourceLoader.exists(META_POOL_PATH):
		meta_pool = load(META_POOL_PATH) as MetaPool
	if roster == null:
		push_error("Profile: missing class roster at %s" % ROSTER_PATH)
		roster = ClassRoster.new()
	if meta_pool == null:
		push_error("Profile: missing meta pool at %s" % META_POOL_PATH)
		meta_pool = MetaPool.new()
	load_profile()
	apply_settings()

## Detaches from user://profile.json for the rest of the process and starts
## from defaults, so lab scenarios are deterministic and never touch the save.
func enter_sandbox() -> void:
	_persistent = false
	_loading = true
	_reset()
	_loading = false

func is_sandboxed() -> bool:
	return not _persistent

# --- currencies -------------------------------------------------------------

func currency(id: StringName) -> int:
	return int(_currencies.get(String(id), 0))

func add_currency(id: StringName, amount: int) -> void:
	if amount == 0:
		return
	var total := maxi(currency(id) + amount, 0)
	_currencies[String(id)] = total
	currency_changed.emit(id, total)
	_mutated()

## Deducts `amount` if affordable; returns whether it did.
func spend(id: StringName, amount: int) -> bool:
	if amount < 0 or currency(id) < amount:
		return false
	if amount == 0:
		return true
	add_currency(id, -amount)
	return true

## All entries are validated before any debit; one save covers the transaction.
func can_pay(costs: Dictionary) -> bool:
	return _validated_payment(costs) != null

func pay(costs: Dictionary) -> bool:
	var payment: Variant = _validated_payment(costs)
	if payment == null:
		return false
	if payment.is_empty():
		return true
	_debit_payment(payment)
	_mutated()
	_emit_payment(payment)
	return true

func _validated_payment(costs: Dictionary) -> Variant:
	var payment := {}
	for key in costs:
		if not (key is String or key is StringName) or str(key).is_empty():
			return null
		var value: Variant = costs[key]
		if not (value is int or value is float):
			return null
		var amount := float(value)
		if not is_finite(amount) or amount < 0.0 or amount != floor(amount) or amount > 2147483647.0:
			return null
		var id := str(key)
		payment[id] = int(payment.get(id, 0)) + int(amount)
	for id in payment:
		if currency(StringName(id)) < int(payment[id]):
			return null
	return payment

func _debit_payment(payment: Dictionary) -> void:
	for id in payment:
		_currencies[id] = currency(StringName(id)) - int(payment[id])

func _emit_payment(payment: Dictionary) -> void:
	for id in payment:
		if int(payment[id]) > 0:
			currency_changed.emit(StringName(id), currency(StringName(id)))

# --- workshop crafting -------------------------------------------------------

func craft_rank(id: StringName) -> int:
	var recipe := CraftingCatalog.find(id)
	if recipe == null:
		return 0
	return clampi(int(_crafted_ranks.get(String(id), 0)), 0, recipe.max_rank)

func craft_cost(id: StringName) -> Dictionary:
	var recipe := CraftingCatalog.find(id)
	if recipe == null or craft_rank(id) >= recipe.max_rank:
		return {}
	var costs := {}
	for mineral in recipe.costs:
		costs[mineral] = int(recipe.costs[mineral]) * (craft_rank(id) + 1)
	return costs

func craft(id: StringName) -> bool:
	var recipe := CraftingCatalog.find(id)
	if recipe == null or craft_rank(id) >= recipe.max_rank:
		return false
	var payment: Variant = _validated_payment(craft_cost(id))
	if payment == null:
		return false
	_debit_payment(payment)
	_crafted_ranks[String(id)] = craft_rank(id) + 1
	_mutated()
	_emit_payment(payment)
	return true

func equip_craft(id: StringName, hand: int = 0) -> bool:
	if hand < 0 or hand >= 3 or craft_rank(id) <= 0:
		return false
	var recipe := CraftingCatalog.find(id)
	match recipe.category:
		&"armor":
			_equipped_armor = id
		&"weapon":
			if recipe.weapon == null:
				return false
			_equipped_weapons[str(hand)] = String(id)
		&"gadget":
			if recipe.hand_upgrade == &"":
				return false
			_equipped_gadgets[str(hand)] = String(id)
		_:
			return false
	_mutated()
	return true

func unequip_craft(category: StringName, hand: int = 0) -> bool:
	if hand < 0 or hand >= 3:
		return false
	match category:
		&"armor":
			_equipped_armor = &""
		&"weapon":
			_equipped_weapons.erase(str(hand))
		&"gadget":
			_equipped_gadgets.erase(str(hand))
		_:
			return false
	_mutated()
	return true

func is_craft_equipped(id: StringName, hand: int = 0) -> bool:
	if hand < 0 or hand >= 3 or craft_rank(id) <= 0:
		return false
	var recipe := CraftingCatalog.find(id)
	match recipe.category:
		&"armor":
			return _equipped_armor == id
		&"weapon":
			return _equipped_weapons.get(str(hand), "") == String(id)
		&"gadget":
			return _equipped_gadgets.get(str(hand), "") == String(id)
		&"perk", &"talent":
			return true
	return false

func hand_loadout(class_definition: ClassDefinition) -> Array[WeaponDefinition]:
	var fallback := load("res://data/weapons/pulse.tres") as WeaponDefinition
	var result: Array[WeaponDefinition] = []
	for slot in 3:
		var gun := fallback
		if class_definition != null and slot < class_definition.starting_weapons.size() \
				and class_definition.starting_weapons[slot] != null:
			gun = class_definition.starting_weapons[slot]
		result.append(gun)
	for hand in range(3):
		var id := StringName(str(_equipped_weapons.get(str(hand), "")))
		var recipe := CraftingCatalog.find(id)
		if recipe != null and recipe.category == &"weapon" and recipe.weapon != null and craft_rank(id) > 0:
			result[hand] = recipe.weapon
	return result

func crafting_modifiers() -> Dictionary:
	var modifiers := {}
	for recipe in CraftingCatalog.recipes():
		var rank := craft_rank(recipe.id)
		if rank <= 0:
			continue
		if recipe.category == &"talent":
			modifiers[recipe] = rank
		elif recipe.category == &"armor" and _equipped_armor == recipe.id:
			modifiers[recipe] = 1
	return modifiers

func apply_hand_gadgets(hands: Array[WeaponHand]) -> void:
	for hand in mini(3, hands.size()):
		var id := StringName(str(_equipped_gadgets.get(str(hand), "")))
		var recipe := CraftingCatalog.find(id)
		if recipe != null and recipe.category == &"gadget" and craft_rank(id) > 0:
			hands[hand].upgrade(recipe.hand_upgrade)

## The normal run perk machinery instantiates these effects once at deployment.
func starting_craft_upgrades() -> Array[UpgradeDefinition]:
	var upgrades: Array[UpgradeDefinition] = []
	for recipe in CraftingCatalog.recipes():
		if recipe.category == &"perk" and craft_rank(recipe.id) > 0 and recipe.upgrade != null:
			upgrades.append(recipe.upgrade)
	return upgrades

# --- classes ----------------------------------------------------------------

func is_class_unlocked(definition: ClassDefinition) -> bool:
	if definition == null:
		return false
	return definition.unlock_cost <= 0 or _unlocked_classes.has(String(definition.id))

func can_afford_class(definition: ClassDefinition) -> bool:
	return definition != null and currency(definition.unlock_currency) >= definition.unlock_cost

## Spends the unlock cost; returns true when the class is (now) unlocked.
func unlock_class(definition: ClassDefinition) -> bool:
	if definition == null:
		return false
	if is_class_unlocked(definition):
		return true
	if currency(definition.unlock_currency) < definition.unlock_cost:
		return false
	_unlocked_classes[String(definition.id)] = true
	# spend() saves, so the unlock is written together with the payment.
	spend(definition.unlock_currency, definition.unlock_cost)
	return true

## The selected class, falling back to the first unlocked one.
func selected_class() -> ClassDefinition:
	for definition in roster.classes:
		if definition.id == selected_class_id and is_class_unlocked(definition):
			return definition
	for definition in roster.classes:
		if is_class_unlocked(definition):
			return definition
	return roster.find(selected_class_id)

# --- class abilities ----------------------------------------------------------

## True for the class default and for bought alternates.
func is_ability_unlocked(definition: ClassDefinition, scene: PackedScene) -> bool:
	if definition == null or scene == null or not definition.ability_options().has(scene):
		return false
	return definition.ability_cost(scene) <= 0 or _unlocked_abilities.has(_ability_slot(definition, scene))

func can_afford_ability(definition: ClassDefinition, scene: PackedScene) -> bool:
	return definition != null and currency(definition.ability_unlock_currency) >= definition.ability_cost(scene)

## Spends the ability's cost (class must be unlocked); returns true when the
## ability is (now) unlocked.
func unlock_ability(definition: ClassDefinition, scene: PackedScene) -> bool:
	if definition == null or scene == null or not definition.ability_options().has(scene):
		return false
	if is_ability_unlocked(definition, scene):
		return true
	if not is_class_unlocked(definition) or not can_afford_ability(definition, scene):
		return false
	_unlocked_abilities[_ability_slot(definition, scene)] = true
	# spend() saves, so the unlock is written together with the payment.
	spend(definition.ability_unlock_currency, definition.ability_cost(scene))
	return true

## Makes an unlocked ability the one the class deploys with.
func equip_ability(definition: ClassDefinition, scene: PackedScene) -> bool:
	if not is_ability_unlocked(definition, scene):
		return false
	var key := String(ClassDefinition.ability_key(scene))
	if _equipped_abilities.get(String(definition.id), "") != key:
		_equipped_abilities[String(definition.id)] = key
		_mutated()
	return true

## The class's equipped ability; falls back to definition.ability_scene when
## nothing (or something no longer available) is equipped.
func equipped_ability_scene(definition: ClassDefinition) -> PackedScene:
	if definition == null:
		return null
	var key := StringName(str(_equipped_abilities.get(String(definition.id), "")))
	if key != &"":
		for scene in definition.ability_options():
			if ClassDefinition.ability_key(scene) == key and is_ability_unlocked(definition, scene):
				return scene
	return definition.ability_scene

func _ability_slot(definition: ClassDefinition, scene: PackedScene) -> String:
	return "%s/%s" % [definition.id, ClassDefinition.ability_key(scene)]

# --- permanent upgrades ------------------------------------------------------

func meta_level(definition: MetaUpgradeDefinition) -> int:
	if definition == null:
		return 0
	return clampi(int(_meta_levels.get(String(definition.id), 0)), 0, definition.max_level())

## Price of the next level, or -1 when maxed.
func next_meta_cost(definition: MetaUpgradeDefinition) -> int:
	var level := meta_level(definition)
	if definition == null or level >= definition.max_level():
		return -1
	return definition.costs[level]

func buy_meta(definition: MetaUpgradeDefinition) -> bool:
	var cost := next_meta_cost(definition)
	if cost < 0 or currency(definition.currency) < cost:
		return false
	_meta_levels[String(definition.id)] = meta_level(definition) + 1
	spend(definition.currency, cost)
	return true

## Purchased levels keyed by definition (levels > 0 only), for RunState.
func meta_levels() -> Dictionary:
	var levels := {}
	for definition in meta_pool.upgrades:
		var level := meta_level(definition)
		if level > 0:
			levels[definition] = level
	return levels

# --- records ----------------------------------------------------------------

## Folds a finished run into the records. Keys: class_id, kills, time, level,
## stages_cleared, victory, banked (id -> amount). `banked` is informational:
## the game adds currency itself via add_currency() when it banks.
func record_run(summary: Dictionary) -> void:
	var kills := int(summary.get("kills", 0))
	var time := float(summary.get("time", 0.0))
	var level := int(summary.get("level", 0))
	var stages := int(summary.get("stages_cleared", 0))
	var victory := bool(summary.get("victory", false))
	records.runs = int(records.runs) + 1
	records.total_kills = int(records.total_kills) + kills
	if victory:
		records.victories = int(records.victories) + 1
	records.best_time = maxf(float(records.best_time), time)
	records.best_kills = maxi(int(records.best_kills), kills)
	records.best_level = maxi(int(records.best_level), level)
	records.deepest_stage = maxi(int(records.deepest_stage), stages)
	var banked := {}
	var banked_source: Variant = summary.get("banked", {})
	if banked_source is Dictionary:
		for key in banked_source:
			banked[String(key)] = int(banked_source[key])
	records.last_run = {
		"class_id": String(summary.get("class_id", &"")),
		"kills": kills,
		"time": time,
		"level": level,
		"stages_cleared": stages,
		"victory": victory,
		"banked": banked,
	}
	_mutated()

# --- settings ---------------------------------------------------------------

## Validates, stores, applies and saves one setting.
func set_setting(key: String, value: Variant) -> void:
	if not DEFAULT_SETTINGS.has(key):
		push_warning("Profile: unknown setting %s" % key)
		return
	settings[key] = _sanitize_setting(key, value)
	apply_settings()
	_mutated()

func apply_settings() -> void:
	for key: String in VOLUME_BUSES:
		var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if bus < 0:
			continue
		var volume := float(settings.get(key, DEFAULT_SETTINGS[key]))
		AudioServer.set_bus_mute(bus, volume <= 0.001)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	var fullscreen := bool(settings.get("fullscreen", false))
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# --- persistence ------------------------------------------------------------

func save() -> void:
	if not _persistent:
		return
	var data := {
		"version": VERSION,
		"selected_class_id": String(selected_class_id),
		"currencies": _currencies,
		"unlocked_classes": _unlocked_classes.keys(),
		"meta_levels": _meta_levels,
		"unlocked_abilities": _unlocked_abilities.keys(),
		"equipped_abilities": _equipped_abilities,
		"crafted_ranks": _crafted_ranks,
		"equipped_armor": String(_equipped_armor),
		"equipped_weapons": _equipped_weapons,
		"equipped_gadgets": _equipped_gadgets,
		"records": records,
		"settings": settings,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Profile: cannot write %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func load_profile() -> void:
	_loading = true
	_reset()
	var data := _read_file()
	if not data.is_empty():
		_apply_data(data)
	var chosen := _find_class(selected_class_id)
	if chosen == null or not is_class_unlocked(chosen):
		var fallback := selected_class()
		selected_class_id = fallback.id if fallback != null else &""
	_loading = false
	save()

func _read_file() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and int(_number(parsed.get("version", -1))) == VERSION:
		return parsed
	push_warning("Profile: %s is corrupt or incompatible; resetting (backup: %s)" % [SAVE_PATH, BACKUP_PATH])
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BACKUP_PATH))
	return {}

func _apply_data(data: Dictionary) -> void:
	selected_class_id = StringName(str(data.get("selected_class_id", "")))
	var currencies: Variant = data.get("currencies", {})
	if currencies is Dictionary:
		for key in currencies:
			_currencies[str(key)] = maxi(int(_number(currencies[key])), 0)
	var unlocked: Variant = data.get("unlocked_classes", [])
	if unlocked is Array:
		for id in unlocked:
			_unlocked_classes[str(id)] = true
	var levels: Variant = data.get("meta_levels", {})
	# Saves from before ability loadouts lack these keys: defaults stay.
	var abilities: Variant = data.get("unlocked_abilities", [])
	if abilities is Array:
		for slot in abilities:
			_unlocked_abilities[str(slot)] = true
	var equipped: Variant = data.get("equipped_abilities", {})
	if equipped is Dictionary:
		for key in equipped:
			_equipped_abilities[str(key)] = str(equipped[key])
	if levels is Dictionary:
		for key in levels:
			_meta_levels[str(key)] = maxi(int(_number(levels[key])), 0)
	var crafted: Variant = data.get("crafted_ranks", {})
	if crafted is Dictionary:
		for key in crafted:
			var recipe := CraftingCatalog.find(StringName(str(key)))
			if recipe != null:
				var rank := clampi(int(_number(crafted[key])), 0, recipe.max_rank)
				if rank > 0:
					_crafted_ranks[String(recipe.id)] = rank
	var armor_id := StringName(str(data.get("equipped_armor", "")))
	var armor_recipe := CraftingCatalog.find(armor_id)
	if armor_recipe != null and armor_recipe.category == &"armor" and craft_rank(armor_id) > 0:
		_equipped_armor = armor_id
	_load_craft_slots(data.get("equipped_weapons", {}), &"weapon", _equipped_weapons)
	_load_craft_slots(data.get("equipped_gadgets", {}), &"gadget", _equipped_gadgets)
	var saved_records: Variant = data.get("records", {})
	if saved_records is Dictionary:
		for key in DEFAULT_RECORDS:
			if saved_records.has(key):
				var value := maxf(_number(saved_records[key]), 0.0)
				if key == "best_time":
					records[key] = value
				else:
					records[key] = int(value)
		if saved_records.get("last_run") is Dictionary:
			records.last_run = saved_records.last_run
	var saved_settings: Variant = data.get("settings", {})
	if saved_settings is Dictionary:
		for key in DEFAULT_SETTINGS:
			if saved_settings.has(key):
				settings[key] = _sanitize_setting(key, saved_settings[key])

func _reset() -> void:
	selected_class_id = &""
	_currencies.clear()
	_unlocked_classes.clear()
	_meta_levels.clear()
	_unlocked_abilities.clear()
	_equipped_abilities.clear()
	_crafted_ranks.clear()
	_equipped_armor = &""
	_equipped_weapons.clear()
	_equipped_gadgets.clear()
	records = DEFAULT_RECORDS.duplicate()
	settings = DEFAULT_SETTINGS.duplicate()

func _load_craft_slots(saved: Variant, category: StringName, slots: Dictionary) -> void:
	if not saved is Dictionary:
		return
	for hand in range(3):
		var id := StringName(str(saved.get(str(hand), "")))
		var recipe := CraftingCatalog.find(id)
		if recipe != null and recipe.category == category and craft_rank(id) > 0:
			slots[str(hand)] = String(id)

func _sanitize_setting(key: String, value: Variant) -> Variant:
	match key:
		"fullscreen":
			return value if value is bool else _number(value) != 0.0
		"mouse_sensitivity":
			return clampf(_number(value, 1.0), SENSITIVITY_RANGE.x, SENSITIVITY_RANGE.y)
		_:
			return clampf(_number(value, 1.0), 0.0, 1.0)

func _number(value: Variant, fallback := 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback

func _find_class(id: StringName) -> ClassDefinition:
	for definition in roster.classes:
		if definition.id == id:
			return definition
	return null

func _mutated() -> void:
	if _loading:
		return
	save()
	changed.emit()
