class_name BaseScreen
extends MenuScreen

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const ARMORY := preload("res://scenes/ui/menu/armory_screen.tscn")
const BACKDROP := preload("res://scripts/ui/menu/base_backdrop.gd")
const CATEGORIES: Array[StringName] = [&"armor", &"weapon", &"gadget", &"perk", &"talent"]
const MINERALS: Array[ResourceDefinition] = [preload("res://data/resources/gold.tres"), preload("res://data/resources/crystal.tres"), preload("res://data/resources/shard.tres")]

var _tabs: TabBar
var _workshop: HBoxContainer
var _legacy: MenuScreen
var _cards: Array[Dictionary] = []
var _hand_selector: OptionButton
var _hand_labels: Array[Label] = []
var _hand_buttons: Array[Button] = []
var _armor_label: Label
var _status: Label
var _currency: CurrencyBar
var _selected_hand := 0

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
	var title := _label("BASE WORKSHOP", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_currency = CurrencyBar.new()
	_currency.currencies = MINERALS
	_currency.font_size = 17
	_currency.add_theme_constant_override(&"separation", 18)
	header.add_child(_currency)
	rows.add_child(_label("Craft permanent equipment with banked minerals. Select a hand before equipping guns or gadgets.", 16))
	# Keep a clear strip of the actual workshop visible above its station tabs.
	var panorama := Control.new()
	panorama.custom_minimum_size.y = 84
	panorama.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(panorama)
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_ALL
	for title_text in ["ARMOR", "WEAPONS", "GADGETS", "PERKS", "TALENTS", "ARMORY"]:
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
	_legacy.back_requested.connect(back_requested.emit)
	_legacy.hide()
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 18)
	rows.add_child(footer)
	back_button = Button.new()
	back_button.text = "BACK  [ESC]"
	footer.add_child(back_button)
	_status = _label("Crafted gear and talent ranks persist between runs.", 16)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	default_focus = _tabs
	super()
	Profile.currency_changed.connect(_on_wallet_changed)
	refresh()

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
	shade.color = Color(0.01, 0.02, 0.035, 0.56)
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
	rows.add_child(_label("THREE-HAND LOADOUT", 20))
	_hand_selector = OptionButton.new()
	for index in range(3):
		_hand_selector.add_item("EQUIP TO HAND %d" % (index + 1))
	_hand_selector.item_selected.connect(_select_hand)
	rows.add_child(_hand_selector)
	_armor_label = _label("", 16)
	_armor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_armor_label)
	for index in range(3):
		var select := Button.new()
		select.add_theme_font_size_override(&"font_size", 16)
		select.pressed.connect(_select_hand.bind(index))
		rows.add_child(select)
		_hand_buttons.append(select)
		var details := _label("", 15)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(details)
		_hand_labels.append(details)
		var actions := HBoxContainer.new()
		rows.add_child(actions)
		for category in [&"weapon", &"gadget"]:
			var clear := Button.new()
			clear.text = "RESET GUN" if category == &"weapon" else "REMOVE GADGET"
			clear.add_theme_font_size_override(&"font_size", 12)
			clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			clear.pressed.connect(_unequip.bind(category, index))
			actions.add_child(clear)
		rows.add_child(HSeparator.new())
	rows.add_child(_label("Perks and talents apply automatically.\nArmory upgrades still apply to every run.", 14))

func _add_recipe(parent: Container, recipe: CraftRecipe) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	panel.add_child(rows)
	var title := _label(recipe.display_name, 21)
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
	_cards.append({"recipe": recipe, "panel": panel, "state": state, "buy": buy, "equip": equip})

func refresh() -> void:
	if _currency == null:
		return
	_currency.refresh()
	for card in _cards:
		var recipe: CraftRecipe = card.recipe
		var rank := Profile.craft_rank(recipe.id)
		var maxed := rank >= recipe.max_rank
		var equipped := Profile.is_craft_equipped(recipe.id, _selected_hand)
		var cost := Profile.craft_cost(recipe.id)
		var panel: PanelContainer = card.panel
		panel.visible = _tabs.current_tab < CATEGORIES.size() and recipe.category == CATEGORIES[mini(_tabs.current_tab, CATEGORIES.size() - 1)]
		var state: Label = card.state
		state.text = "OWNED %d / %d%s" % [rank, recipe.max_rank, "  ·  EQUIPPED" if equipped else ""]
		if recipe.category in [&"perk", &"talent"] and rank > 0:
			state.text += "  ·  AUTOMATIC AT DEPLOYMENT"
		var buy: Button = card.buy
		buy.text = "MAX RANK" if maxed else "%s  ·  %s" % ["CRAFT" if rank == 0 else "UPGRADE", _price(cost)]
		buy.disabled = maxed or not Profile.can_pay(cost)
		var equip: Button = card.equip
		equip.visible = recipe.category in [&"armor", &"weapon", &"gadget"]
		equip.disabled = rank == 0
		equip.text = "UNEQUIP" if equipped else ("EQUIP ARMOR" if recipe.category == &"armor" else "EQUIP H%d" % (_selected_hand + 1))
	_workshop.visible = _tabs.current_tab != 5
	_legacy.visible = _tabs.current_tab == 5
	if _legacy.visible:
		_legacy.refresh()
	_refresh_loadout()

func _refresh_loadout() -> void:
	var preview := RunState.new()
	preview.initialize_hands(Profile.hand_loadout(Profile.selected_class()))
	Profile.apply_hand_gadgets(preview.hands)
	var definitions := preview.hand_definitions()
	_armor_label.text = "ARMOR  ·  " + _equipped_name(&"armor", 0, "Operator standard")
	for index in range(3):
		_hand_buttons[index].text = "HAND %d%s" % [index + 1, "  ·  SELECTED" if index == _selected_hand else "  ·  SELECT"]
		var weapon := definitions[index]
		_hand_labels[index].text = "%s\n%d dmg · %d projectiles · %.2fs cadence\nSplash %.1fm · %s\nGadget: %s" % [weapon.display_name, weapon.damage, weapon.pellet_count, weapon.fire_interval, weapon.explosion_radius, DamageType.label(weapon.damage_type), _equipped_name(&"gadget", index, "None")]

func _equipped_name(category: StringName, hand: int, fallback: String) -> String:
	for recipe in CraftingCatalog.recipes():
		if recipe.category == category and Profile.is_craft_equipped(recipe.id, hand):
			return recipe.display_name
	return fallback

func _on_category_changed(_tab: int) -> void:
	refresh()

func _select_hand(hand: int) -> void:
	_selected_hand = hand
	_hand_selector.select(hand)
	refresh()

func _craft(id: StringName) -> void:
	var recipe := CraftingCatalog.find(id)
	if Profile.craft(id):
		_status.text = "%s crafted to rank %d. %s" % [recipe.display_name, Profile.craft_rank(id), "Equip it to use it." if recipe.category in [&"armor", &"weapon", &"gadget"] else "Applies at your next deployment."]
	else:
		_status.text = "Cannot craft %s: insufficient minerals or maximum rank reached." % recipe.display_name
	refresh()

func _equip(id: StringName) -> void:
	var recipe := CraftingCatalog.find(id)
	if Profile.is_craft_equipped(id, _selected_hand):
		_unequip(recipe.category, _selected_hand)
		return
	if Profile.equip_craft(id, _selected_hand):
		_status.text = "%s equipped%s. Saved for your next run." % [recipe.display_name, "" if recipe.category == &"armor" else " to hand %d" % (_selected_hand + 1)]
	else:
		_status.text = "Craft this item before equipping it."
	refresh()

func _unequip(category: StringName, hand: int) -> void:
	if Profile.unequip_craft(category, hand):
		_status.text = "%s removed%s. Default equipment restored." % [String(category).capitalize(), "" if category == &"armor" else " from hand %d" % (hand + 1)]
	else:
		_status.text = "No crafted %s equipped in this slot." % category
	refresh()

func _on_wallet_changed(_id: StringName, _amount: int) -> void:
	if is_visible_in_tree():
		refresh.call_deferred()

func _price(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for mineral in MINERALS:
		if cost.has(mineral.id):
			parts.append("%d %s" % [int(cost[mineral.id]), "Cinder" if mineral.id == &"crystal" else mineral.display_name])
	return " + ".join(parts)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	return label
