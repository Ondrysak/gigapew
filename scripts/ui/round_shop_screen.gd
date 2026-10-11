class_name RoundShopScreen
extends Control

## One-primary exchange: persistent weapon comparison, five skill upgrades,
## and scrollable mod/suit stock. All transactions belong to RoundShop.
signal continue_requested()

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const MINERALS: Array[ResourceDefinition] = [preload("res://data/resources/gold.tres"), preload("res://data/resources/crystal.tres"), preload("res://data/resources/shard.tres")]
const STAT_LABELS := {"DMG": "RÁNA", "RATE": "TEMPO", "PELLETS": "KUSŮ", "SPLASH": "VÝBUCH", "PIERCE": "PRŮRAZ", "TYPE": "ŽIVEL", "ARMOR": "OCHRANA", "HEALTH": "ZDRAVÍ", "POWER": "SÍLA"}
const TEXT := Color(0.87, 0.81, 0.67)
const DIM := Color(0.65, 0.60, 0.49)
const AMBER := Color(0.72, 0.55, 0.32)
const GOOD := Color(0.66, 0.69, 0.46)
const BAD := Color(0.78, 0.43, 0.34)

var _shop: RoundShop
var _state: RunState
var _title: Label
var _summary: Label
var _wallet: Dictionary = {}
var _primary_name: Label
var _primary_icon: TextureRect
var _primary_stats: Label
var _selector: OptionButton
var _comparison: Label
var _swap: Button
var _abilities: Array[Dictionary] = []
var _offers: Array[Dictionary] = []
var _reroll: Button
var _status: Label
var _continue: Button
var _candidate := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MENU_THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.045, 0.035, 0.025, 0.98)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 22)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	margin.add_child(rows)
	var header := _row()
	rows.add_child(header)
	_title = _label("SEKTOR HOTOVÝ", 26, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	for mineral in MINERALS:
		header.add_child(GameIcons.rect(mineral.icon, 24))
		var value := _label("0", 18, TEXT)
		header.add_child(value)
		_wallet[mineral.id] = value
	_summary = _label("", 13, DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_summary)
	_build_primary(rows)
	rows.add_child(_label("PĚT DOVEDNOSTÍ · SAMOSTATNÁ VYLEPŠENÍ · KLÁVESY 1–5", 16, AMBER))
	var skills := _row()
	rows.add_child(skills)
	for slot in range(5):
		_build_ability(skills, slot)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(tabs)
	_offers.resize(RoundShop.MOD_SLOTS + RoundShop.SUIT_SLOTS)
	for section in range(2):
		var scroll := ScrollContainer.new()
		scroll.name = "ÚPRAVY ZBRANĚ" if section == 0 else "HADRY A SÍLA"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		tabs.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override(&"h_separation", 10)
		grid.add_theme_constant_override(&"v_separation", 8)
		scroll.add_child(grid)
		var start := 0 if section == 0 else RoundShop.MOD_SLOTS
		var end := RoundShop.MOD_SLOTS if section == 0 else _offers.size()
		for index in range(start, end):
			_offers[index] = _build_offer(grid, index)
	var footer := _row()
	rows.add_child(footer)
	_reroll = _button("JINÁ NABÍDKA", _on_reroll)
	footer.add_child(_reroll)
	_status = _label("", 13, TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	_continue = _button("POKRAČOVAT", _on_continue)
	footer.add_child(_continue)
	Profile.currency_changed.connect(_on_wallet_changed)
	StreetWear.apply_tree(self)
	hide()

func _build_primary(parent: Container) -> void:
	var panel := _panel()
	parent.add_child(panel)
	var columns := _row()
	panel.add_child(columns)
	_primary_icon = GameIcons.rect(null, 48)
	columns.add_child(_primary_icon)
	var current := VBoxContainer.new()
	current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(current)
	_primary_name = _label("HLAVNÍ ZBRAŇ", 18, AMBER)
	_primary_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	current.add_child(_primary_name)
	_primary_stats = _label("", 13, TEXT)
	_primary_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	current.add_child(_primary_stats)
	var candidate := VBoxContainer.new()
	candidate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(candidate)
	_selector = OptionButton.new()
	_selector.add_theme_font_size_override(&"font_size", 15)
	_selector.item_selected.connect(_select_candidate)
	candidate.add_child(_selector)
	_comparison = _label("", 13, DIM)
	_comparison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	candidate.add_child(_comparison)
	_swap = _button("VYMĚNIT ZDARMA", _on_swap)
	columns.add_child(_swap)
	_swap.tooltip_text = "Vymění hlavní zbraň. Koupené stupně úprav zůstávají."

func _build_ability(parent: Container, slot: int) -> void:
	var panel := _panel()
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	panel.add_child(rows)
	var header := _row()
	rows.add_child(header)
	header.add_child(_label(str(slot + 1), 17, AMBER))
	var icon := GameIcons.rect(null, 24)
	header.add_child(icon)
	var rank := _label("S0 / 3", 13, DIM)
	header.add_child(rank)
	var title := _label("", 15, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.y = 36
	rows.add_child(title)
	var stats := _label("", 12, DIM)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(stats)
	var price := _label("", 12, GOOD)
	price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(price)
	var buy := _button("VYLEPŠIT", _on_buy_ability.bind(slot))
	rows.add_child(buy)
	_abilities.append({"panel": panel, "icon": icon, "rank": rank, "title": title, "stats": stats, "price": price, "buy": buy})

func _build_offer(parent: Container, index: int) -> Dictionary:
	var panel := _panel()
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	panel.add_child(rows)
	var header := _row()
	rows.add_child(header)
	var icon := GameIcons.rect(null, 24)
	header.add_child(icon)
	var title := _label("", 16, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var rank := _label("", 12, DIM)
	header.add_child(rank)
	var effect := _label("", 13, DIM)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(effect)
	var bottom := _row()
	rows.add_child(bottom)
	var comparison := _label("", 14, GOOD)
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(comparison)
	var buy := _button("KOUPIT", _on_buy.bind(index))
	bottom.add_child(buy)
	return {"panel": panel, "icon": icon, "title": title, "rank": rank, "effect": effect, "comparison": comparison, "buy": buy}

func open(state: RunState, stage: int, final_stage: bool, summary: String) -> void:
	_state = state
	_shop = RoundShop.new()
	_shop.setup(state, stage, randi())
	_title.text = "SEKTOR %d HOTOVÝ · BAZAR" % (stage + 1)
	_summary.text = summary.replace("\n", "   ")
	_continue.text = "ZPÁTKY DO BAZARU" if final_stage else "DO SEKTORU %d" % (stage + 2)
	_selector.clear()
	_candidate = 0
	for index in state.available_weapons.size():
		var source := state.available_weapons[index]
		_selector.add_item(source.display_name)
		if source == state.primary.source:
			_candidate = index
	_selector.select(_candidate)
	_status.text = "Výměna zdarma, úpravy zůstávají. Vylepši dovednosti, hlavní zbraň nebo hadry."
	show()
	_refresh()
	_continue.grab_focus.call_deferred()

func _refresh() -> void:
	if _shop == null:
		return
	for id: StringName in _wallet:
		_wallet[id].text = str(Profile.currency(id))
	_primary_name.text = "HLAVNÍ · " + _state.primary.definition.display_name.to_upper()
	_primary_icon.texture = _state.primary.definition.icon
	_primary_stats.text = _weapon_text(_state.primary.definition)
	_refresh_comparison()
	for slot in _abilities.size():
		var card: Dictionary = _abilities[slot]
		var preview := _shop.ability_preview(slot)
		card.icon.texture = preview.icon
		card.title.text = preview.name
		card.rank.text = "S%d / %d" % [preview.rank, preview.max_rank]
		if not _state.is_ability_unlocked(slot):
			var level := _state.ability_unlock_level(slot)
			card.stats.text = "Odemkne se na úrovni %d" % level
			card.panel.tooltip_text = "%s\n%s" % [preview.name, preview.description]
			card.price.text = "ZAMČENO"
			card.price.add_theme_color_override(&"font_color", BAD)
			card.buy.disabled = true
			card.buy.text = "ÚR %d" % level
			continue
		var maxed := not _state.can_upgrade_ability(slot)
		card.stats.text = "TEĎ " + String(preview.from)
		if not maxed:
			card.stats.text += "\nPAK " + String(preview.to)
		card.panel.tooltip_text = "%s\n%s\n%s" % [preview.name, preview.description, preview.effect]
		card.price.text = "MAXIMUM" if maxed else _price(_shop.ability_cost(slot))
		var can_buy := _shop.can_buy_ability(slot)
		card.price.add_theme_color_override(&"font_color", GOOD if can_buy or maxed else BAD)
		card.buy.disabled = not can_buy
		card.buy.text = "MAXIMUM" if maxed else ("VYLEPŠIT" if can_buy else "CHYBÍ KOŘIST")
	for index in _offers.size():
		var card: Dictionary = _offers[index]
		var offer := _shop.offers[index]
		var id := StringName(offer.id)
		var entry: Dictionary = RoundShop.CATALOG[id]
		var preview := _shop.preview(id)
		card.icon.texture = RoundShop.icon(id)
		card.title.text = entry.name
		card.rank.text = "S%d / %d" % [_shop.rank(id), RoundShop.max_rank(id)]
		card.effect.text = "%s · %s" % [RoundShop.TRACK_NAMES[RoundShop.track(id)], entry.effect]
		card.comparison.text = "%s  %s → %s" % [STAT_LABELS.get(preview.stat, "BONUS"), preview.from, preview.to if not String(preview.to).is_empty() else "MAXIMUM"]
		var can_buy := _shop.can_buy(index)
		card.buy.disabled = not can_buy
		card.buy.text = "PRODÁNO" if offer.sold else ("MAXIMUM" if _shop.is_maxed(id) else "KOUPIT · " + _price(offer.cost))
		card.buy.tooltip_text = "Chybí kořist" if not can_buy and not offer.sold and not _shop.is_maxed(id) else ""
	_reroll.text = "JINÁ NABÍDKA · " + _price(_shop.reroll_cost())
	_reroll.disabled = not _shop.can_reroll()
	var focused := get_viewport().gui_get_focus_owner() as Button
	if focused != null and focused.disabled and is_ancestor_of(focused):
		_continue.grab_focus.call_deferred()

func _weapon_text(definition: WeaponDefinition) -> String:
	var stats := RoundShop.weapon_stats(definition, _state.projectile_bonus)
	return "RÁNA %s · TEMPO %s · ×%s\nVÝBUCH %s · PRŮRAZ %s · %s" % [stats.DMG, stats.RATE, stats.PELLETS, stats.SPLASH, stats.PIERCE, stats.TYPE]

func _refresh_comparison() -> void:
	if _candidate < 0 or _candidate >= _state.available_weapons.size():
		_swap.disabled = true
		return
	var source := _state.available_weapons[_candidate]
	var preview := WeaponBuild.new()
	preview.upgrade_levels = _state.primary.upgrade_levels
	preview.swap(source)
	_comparison.text = _weapon_text(preview.definition)
	var current := source == _state.primary.source
	_swap.disabled = current
	_swap.text = "NASAZENO" if current else "VYMĚNIT ZDARMA"

func _select_candidate(index: int) -> void:
	_candidate = index
	_refresh_comparison()

func _on_swap() -> void:
	if _candidate >= 0 and _candidate < _state.available_weapons.size() and _state.swap_primary(_state.available_weapons[_candidate]):
		_status.text = "Hlavní zbraň vyměněna. Koupené stupně úprav zůstávají."
	_refresh()

func _on_buy_ability(slot: int) -> void:
	var success := _shop.buy_ability(slot)
	_status.text = "Dovednost %d: stupeň %d." % [slot + 1, _state.ability_rank(slot)] if success else "Nákup odmítnut. Nic se nestrhlo."
	_refresh()

func _on_buy(index: int) -> void:
	_status.text = "Vylepšení nasazeno." if _shop.buy(index) else "Nelze koupit: prodáno, maximum nebo chybí kořist. Nic se nestrhlo."
	_refresh()

func _on_reroll() -> void:
	_status.text = "Neprodaná nabídka vyměněna." if _shop.reroll() else "Nabídku nelze vyměnit. Peněženka beze změny."
	_refresh()

func _on_continue() -> void:
	for slot in range(5):
		Input.action_release(StringName("ability_%d" % (slot + 1)))
	hide()
	continue_requested.emit()

func _on_wallet_changed(_id: StringName, _amount: int) -> void:
	if is_visible_in_tree():
		_refresh.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_continue.grab_focus()

func _price(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for mineral in MINERALS:
		var amount := int(cost.get(mineral.id, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, mineral.display_name])
	return "ZDARMA" if parts.is_empty() else " + ".join(parts)

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.075, 0.055, 0.98)
	style.border_color = Color(0.35, 0.29, 0.21)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override(&"panel", style)
	return panel

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	return row

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", 14)
	for state in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style := MENU_THEME.get_stylebox(state, &"Button").duplicate() as StyleBox
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
