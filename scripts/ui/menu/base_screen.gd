class_name BaseScreen
extends MenuScreen

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const ARMORY := preload("res://scenes/ui/menu/armory_screen.tscn")
const BACKDROP := preload("res://scripts/ui/menu/base_backdrop.gd")
const ICON_BADGE := preload("res://scripts/ui/menu/icon_badge.gd")
const BADGE_IDLE := Color(0.38, 0.32, 0.24)
const BADGE_LIVE := Color(0.72, 0.55, 0.32)
const CATEGORIES: Array[StringName] = [&"armor", &"weapon", &"gadget", &"perk", &"talent"]
const MINERALS: Array[ResourceDefinition] = [preload("res://data/resources/gold.tres"), preload("res://data/resources/crystal.tres"), preload("res://data/resources/shard.tres")]

var _tabs: TabBar
var _workshop: HBoxContainer
var _legacy: MenuScreen
var _cards: Array[Dictionary] = []
var _primary: Dictionary = {}
var _armor_badge: ICON_BADGE
var _armor_label: Label
var _status: Label
var _currency: CurrencyBar

func _ready() -> void:
	theme = MENU_THEME
	_build_backdrop()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"left", &"top", &"right", &"bottom"]:
		margin.add_theme_constant_override(StringName("margin_" + String(side)), 28)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 12)
	margin.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := _label("BAZAR POSLEDNÍHO SETU", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_currency = CurrencyBar.new()
	_currency.currencies = MINERALS
	_currency.font_size = 17
	_currency.add_theme_constant_override(&"separation", 18)
	header.add_child(_currency)
	var introduction := _label("Za uloženou kořist pořídíš trvalou výbavu. Vyber jednu hlavní zbraň a jednu kompatibilní vychytávku.", 16)
	introduction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(introduction)
	# Keep a clear strip of the actual workshop visible above its station tabs.
	var panorama := Control.new()
	panorama.custom_minimum_size.y = 84
	panorama.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(panorama)
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_ALL
	for title_text in ["HADRY", "ZBRANĚ", "VYCHYTÁVKY", "FINTY", "TRÉNINK", "TRVALÉ BONUSY"]:
		_tabs.add_tab(title_text)
	_tabs.tab_changed.connect(_on_category_changed)
	rows.add_child(_tabs)
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.y = 240
	rows.add_child(content)
	_workshop = HBoxContainer.new()
	_workshop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workshop.add_theme_constant_override(&"separation", 18)
	content.add_child(_workshop)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_workshop.add_child(scroll)
	var recipes := VBoxContainer.new()
	recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipes.add_theme_constant_override(&"separation", 12)
	scroll.add_child(recipes)
	for recipe in CraftingCatalog.recipes():
		_add_recipe(recipes, recipe)
	_build_loadout()
	_legacy = ARMORY.instantiate() as MenuScreen
	content.add_child(_legacy)
	_legacy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_legacy.back_button.hide()
	# The legacy cards are 270px wide: three columns leave safe room at 1280px.
	var legacy_grid := _legacy.get_node("Margin/Rows/Scroll/Center/Grid") as GridContainer
	legacy_grid.columns = 3
	var legacy_margin := _legacy.get_node("Margin") as MarginContainer
	for side in [&"left", &"top", &"right", &"bottom"]:
		legacy_margin.add_theme_constant_override(StringName("margin_" + String(side)), 4)
	# The workshop header already carries the title tab and the balances.
	_legacy.get_node("Margin/Rows/Header").hide()
	_legacy.get_node("Margin/Rows/Separator").hide()
	_legacy.back_requested.connect(back_requested.emit)
	_legacy.hide()
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 18)
	rows.add_child(footer)
	back_button = Button.new()
	back_button.text = "ZPĚT  [ESC]"
	footer.add_child(back_button)
	_status = _label("Výbava a stupně tréninku zůstávají i mezi běhy.", 16)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	default_focus = _tabs
	super()
	Profile.currency_changed.connect(_on_wallet_changed)
	refresh()
	StreetWear.apply_tree(self)

func _build_backdrop() -> void:
	var viewport_container := SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	viewport_container.add_child(viewport)
	viewport.add_child(BACKDROP.new())
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.035, 0.025, 0.018, 0.64)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _build_loadout() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 350
	panel.theme_type_variation = &"CardPanel"
	_workshop.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 10)
	scroll.add_child(rows)
	rows.add_child(_label("VÝBAVA NA POSLEDNÍ SET", 20))
	var armor := HBoxContainer.new()
	armor.add_theme_constant_override(&"separation", 10)
	rows.add_child(armor)
	_armor_badge = ICON_BADGE.new(null, 32)
	armor.add_child(_armor_badge)
	_armor_label = _label("", 16)
	_armor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_armor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	armor.add_child(_armor_label)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	rows.add_child(header)
	var badge := ICON_BADGE.new(null, 48)
	header.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var weapon_name := _label("", 17)
	weapon_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_name.add_theme_color_override(&"font_color", Color(0.87, 0.81, 0.67))
	titles.add_child(weapon_name)
	var gadget_row := HBoxContainer.new()
	gadget_row.add_theme_constant_override(&"separation", 6)
	rows.add_child(gadget_row)
	var gadget_icon := GameIcons.rect(null, 16)
	gadget_row.add_child(gadget_icon)
	var gadget := _label("", 14)
	gadget.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gadget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gadget_row.add_child(gadget)
	var stats := _label("", 14)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(stats)
	_primary = {"badge": badge, "name": weapon_name, "gadget_icon": gadget_icon, "gadget": gadget, "stats": stats}
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	for category in [&"weapon", &"gadget"]:
		var clear := Button.new()
		clear.text = "VÝCHOZÍ ZBRAŇ" if category == &"weapon" else "SUNDAT VYCHYTÁVKU"
		clear.add_theme_font_size_override(&"font_size", 12)
		clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clear.pressed.connect(_unequip.bind(category))
		actions.add_child(clear)
	rows.add_child(HSeparator.new())
	rows.add_child(_label("Finty a trénink se použijí automaticky.\nTrvalé bonusy platí v každém běhu.", 14))

func _add_recipe(parent: Container, recipe: CraftRecipe) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	parent.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 16)
	panel.add_child(columns)
	var badge := ICON_BADGE.new(recipe.display_icon(), 48)
	columns.add_child(badge)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 8)
	columns.add_child(rows)
	var title := _label(recipe.display_name, 21)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(title)
	var description := _label(recipe.description, 16)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(description)
	var state := _label("", 15)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(state)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 10)
	rows.add_child(actions)
	var buy := Button.new()
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.add_theme_font_size_override(&"font_size", 16)
	buy.pressed.connect(_craft.bind(recipe.id))
	actions.add_child(buy)
	var equip := Button.new()
	equip.add_theme_font_size_override(&"font_size", 16)
	equip.pressed.connect(_equip.bind(recipe.id))
	actions.add_child(equip)
	_cards.append({"recipe": recipe, "panel": panel, "badge": badge, "state": state, "buy": buy, "equip": equip})

func refresh() -> void:
	if _currency == null:
		return
	_currency.refresh()
	for card in _cards:
		var recipe: CraftRecipe = card.recipe
		var rank := Profile.craft_rank(recipe.id)
		var maxed := rank >= recipe.max_rank
		var equipped := Profile.is_craft_equipped(recipe.id)
		var cost := Profile.craft_cost(recipe.id)
		var panel: PanelContainer = card.panel
		panel.visible = _tabs.current_tab < CATEGORIES.size() and recipe.category == CATEGORIES[mini(_tabs.current_tab, CATEGORIES.size() - 1)]
		var state: Label = card.state
		state.text = "VLASTNÍŠ %d / %d%s" % [rank, recipe.max_rank, "  ·  NASAZENO" if equipped else ""]
		card.badge.show_icon(recipe.display_icon(), BADGE_LIVE if equipped else (BADGE_IDLE.lightened(0.15) if rank > 0 else BADGE_IDLE))
		if recipe.category in [&"perk", &"talent"] and rank > 0:
			state.text += "  ·  AUTOMATICKY PŘI STARTU"
		var compatible := recipe.category != &"gadget" or Profile.can_equip_gadget(recipe.id)
		if not compatible:
			state.text += "  ·  PRO TUTO ZBRAŇ NEAKTIVNÍ"
		var buy: Button = card.buy
		buy.text = "MAXIMUM" if maxed else "%s  ·  %s" % ["POŘÍDIT" if rank == 0 else "VYLEPŠIT", _price(cost)]
		buy.disabled = maxed or not Profile.can_pay(cost)
		var equip: Button = card.equip
		equip.visible = recipe.category in [&"armor", &"weapon", &"gadget"]
		equip.disabled = rank == 0 or (not equipped and not compatible)
		equip.text = "SUNDAT" if equipped else ("OBLÉCT" if recipe.category == &"armor" else ("VYBRAT ZBRAŇ" if recipe.category == &"weapon" else "NASADIT"))
	_workshop.visible = _tabs.current_tab != 5
	_legacy.visible = _tabs.current_tab == 5
	if _legacy.visible:
		_legacy.refresh()
	_refresh_loadout()

func _refresh_loadout() -> void:
	var preview := RunState.new()
	preview.initialize_primary(Profile.primary_loadout(Profile.selected_class()))
	Profile.apply_primary_gadget(preview.primary)
	var weapon := preview.primary.definition
	var armor := _equipped_recipe(&"armor")
	_armor_badge.show_icon(armor.display_icon() if armor != null else GameIcons.lookup(&"hud", &"armor"), BADGE_LIVE if armor != null else BADGE_IDLE)
	_armor_label.text = "HADRY  ·  " + (armor.display_name if armor != null else "Co bylo po ruce")
	_primary.badge.show_icon(weapon.icon, BADGE_LIVE)
	_primary.name.text = weapon.display_name
	var gadget := _equipped_recipe(&"gadget")
	var gadget_active := gadget != null and preview.primary.rank(gadget.weapon_upgrade) > 0
	_primary.gadget_icon.texture = gadget.display_icon() if gadget != null else null
	_primary.gadget_icon.visible = gadget != null
	_primary.gadget_icon.modulate = Color.WHITE if gadget_active else Color(0.5, 0.5, 0.5)
	_primary.gadget.text = "Vychytávka: %s%s" % [gadget.display_name if gadget != null else "žádná", " (neaktivní)" if gadget != null and not gadget_active else ""]
	_primary.stats.text = "%d poškození · %d projektilů · %.2fs prodleva\nVýbuch %.1fm · průraz %d · %s\nPět dovedností na klávesách 1–5.\nZamiř zblízka na přihrádku automatu;\ndrž F a páč." % [weapon.damage, weapon.pellet_count, weapon.fire_interval, weapon.explosion_radius, weapon.pierce, DamageType.label(weapon.damage_type)]

func _equipped_recipe(category: StringName) -> CraftRecipe:
	for recipe in CraftingCatalog.recipes():
		if recipe.category == category and Profile.is_craft_equipped(recipe.id):
			return recipe
	return null

func _on_category_changed(_tab: int) -> void:
	refresh()


func _craft(id: StringName) -> void:
	var recipe := CraftingCatalog.find(id)
	if Profile.craft(id):
		_status.text = "%s: stupeň %d. %s" % [recipe.display_name, Profile.craft_rank(id), "Nasaď a používej." if recipe.category in [&"armor", &"weapon", &"gadget"] else "Platí od příštího běhu."]
	else:
		_status.text = "%s nelze pořídit: chybí kořist nebo už máš maximum." % recipe.display_name
	refresh()

func _equip(id: StringName) -> void:
	var recipe := CraftingCatalog.find(id)
	if Profile.is_craft_equipped(id):
		_unequip(recipe.category)
		return
	if Profile.equip_craft(id):
		_status.text = "%s nasazeno. Uloženo pro příští běh." % recipe.display_name
	else:
		_status.text = "Tahle vychytávka nesedí na hlavní zbraň." if recipe.category == &"gadget" and not Profile.can_equip_gadget(id) else "Nejdřív tuhle výbavu pořiď."
	refresh()

func _unequip(category: StringName) -> void:
	if Profile.unequip_craft(category):
		_status.text = "Výbava sundána. Obnovena výchozí výbava."
	else:
		_status.text = "V této kategorii nemáš nic nasazeno."
	refresh()

func _on_wallet_changed(_id: StringName, _amount: int) -> void:
	if is_visible_in_tree():
		refresh.call_deferred()

func _price(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for mineral in MINERALS:
		if cost.has(mineral.id):
			parts.append("%d %s" % [int(cost[mineral.id]), mineral.display_name])
	return "ZDARMA" if parts.is_empty() else " + ".join(parts)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	return label
