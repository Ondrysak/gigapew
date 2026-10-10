class_name RoundShopScreen
extends Control

## One-primary exchange: persistent weapon comparison, five skill upgrades,
## and scrollable mod/suit stock. All transactions belong to RoundShop.
signal continue_requested()

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const MINERALS: Array[ResourceDefinition] = [preload("res://data/resources/gold.tres"), preload("res://data/resources/crystal.tres"), preload("res://data/resources/shard.tres")]
const TEXT := Color(0.83, 0.96, 0.99)
const DIM := Color(0.5, 0.66, 0.72)
const TEAL := Color(0.3, 0.85, 0.88)
const GOOD := Color(0.5, 1.0, 0.62)
const BAD := Color(1.0, 0.36, 0.3)

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
	shade.color = Color(0.01, 0.025, 0.04, 0.97)
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
	_title = _label("ROUND CLEARED", 26, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	for mineral in MINERALS:
		header.add_child(GameIcons.rect(mineral.icon, 24))
		var value := _label("0", 18, mineral.color.lightened(0.2))
		header.add_child(value)
		_wallet[mineral.id] = value
	_summary = _label("", 13, DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_summary)
	_build_primary(rows)
	rows.add_child(_label("FIVE ABILITIES · INDEPENDENT UPGRADES · KEYS 1–5", 16, TEAL))
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
		scroll.name = "PRIMARY MODS" if section == 0 else "SUIT SYSTEMS"
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
	_reroll = _button("REROLL STOCK", _on_reroll)
	footer.add_child(_reroll)
	_status = _label("", 13, TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	_continue = _button("CONTINUE", _on_continue)
	footer.add_child(_continue)
	Profile.currency_changed.connect(_on_wallet_changed)
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
	_primary_name = _label("PRIMARY", 18, TEAL)
	current.add_child(_primary_name)
	_primary_stats = _label("", 13, TEXT)
	current.add_child(_primary_stats)
	var candidate := VBoxContainer.new()
	candidate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(candidate)
	_selector = OptionButton.new()
	_selector.add_theme_font_size_override(&"font_size", 15)
	_selector.item_selected.connect(_select_candidate)
	candidate.add_child(_selector)
	_comparison = _label("", 13, DIM)
	candidate.add_child(_comparison)
	_swap = _button("SWAP FREE", _on_swap)
	columns.add_child(_swap)
	_swap.tooltip_text = "Change the single primary firearm. Purchased mod ranks stay installed."

func _build_ability(parent: Container, slot: int) -> void:
	var panel := _panel()
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	panel.add_child(rows)
	var header := _row()
	rows.add_child(header)
	header.add_child(_label(str(slot + 1), 17, TEAL))
	var icon := GameIcons.rect(null, 24)
	header.add_child(icon)
	var rank := _label("R0 / 3", 13, DIM)
	header.add_child(rank)
	var title := _label("", 15, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(title)
	var stats := _label("", 12, DIM)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(stats)
	var price := _label("", 12, GOOD)
	price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(price)
	var buy := _button("UPGRADE", _on_buy_ability.bind(slot))
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
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var rank := _label("", 12, DIM)
	header.add_child(rank)
	var effect := _label("", 13, DIM)
	rows.add_child(effect)
	var bottom := _row()
	rows.add_child(bottom)
	var comparison := _label("", 14, GOOD)
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(comparison)
	var buy := _button("BUY", _on_buy.bind(index))
	bottom.add_child(buy)
	return {"panel": panel, "icon": icon, "title": title, "rank": rank, "effect": effect, "comparison": comparison, "buy": buy}

func open(state: RunState, stage: int, final_stage: bool, summary: String) -> void:
	_state = state
	_shop = RoundShop.new()
	_shop.setup(state, stage, randi())
	_title.text = "ROUND %d CLEARED · MINERAL EXCHANGE" % (stage + 1)
	_summary.text = summary.replace("\n", "   ")
	_continue.text = "RETURN TO BASE" if final_stage else "CONTINUE TO ROUND %d" % (stage + 2)
	_selector.clear()
	_candidate = 0
	for index in state.available_weapons.size():
		var source := state.available_weapons[index]
		_selector.add_item(source.display_name)
		if source == state.primary.source:
			_candidate = index
	_selector.select(_candidate)
	_status.text = "Swap freely; mods persist. Buy individual skills, primary mods or suit systems."
	show()
	_refresh()
	_continue.grab_focus.call_deferred()

func _refresh() -> void:
	if _shop == null:
		return
	for id: StringName in _wallet:
		_wallet[id].text = str(Profile.currency(id))
	_primary_name.text = "PRIMARY · " + _state.primary.definition.display_name.to_upper()
	_primary_icon.texture = _state.primary.definition.icon
	_primary_stats.text = _weapon_text(_state.primary.definition)
	_refresh_comparison()
	for slot in _abilities.size():
		var card: Dictionary = _abilities[slot]
		var preview := _shop.ability_preview(slot)
		card.icon.texture = preview.icon
		card.title.text = preview.name
		card.rank.text = "R%d / %d" % [preview.rank, preview.max_rank]
		var maxed := not _state.can_upgrade_ability(slot)
		card.stats.text = "NOW " + String(preview.from)
		if not maxed:
			card.stats.text += "\nNEXT " + String(preview.to)
		card.panel.tooltip_text = String(preview.description) + "\n" + String(preview.effect)
		card.price.text = "MAX RANK" if maxed else _price(_shop.ability_cost(slot))
		var can_buy := _shop.can_buy_ability(slot)
		card.price.modulate = GOOD if can_buy or maxed else BAD
		card.buy.disabled = not can_buy
		card.buy.text = "MAX RANK" if maxed else ("UPGRADE" if can_buy else "NEED MINERALS")
	for index in _offers.size():
		var card: Dictionary = _offers[index]
		var offer := _shop.offers[index]
		var id := StringName(offer.id)
		var entry: Dictionary = RoundShop.CATALOG[id]
		var preview := _shop.preview(id)
		card.icon.texture = RoundShop.icon(id)
		card.title.text = entry.name
		card.rank.text = "R%d / %d" % [_shop.rank(id), RoundShop.max_rank(id)]
		card.effect.text = "%s · %s" % [RoundShop.TRACK_NAMES[RoundShop.track(id)], entry.effect]
		card.comparison.text = "%s  %s → %s" % [preview.stat, preview.from, preview.to if not String(preview.to).is_empty() else "MAX"]
		var can_buy := _shop.can_buy(index)
		card.buy.disabled = not can_buy
		card.buy.text = "SOLD" if offer.sold else ("MAXED" if _shop.is_maxed(id) else "BUY · " + _price(offer.cost))
		card.buy.tooltip_text = "Not enough minerals" if not can_buy and not offer.sold and not _shop.is_maxed(id) else ""
	_reroll.text = "REROLL · " + _price(_shop.reroll_cost())
	_reroll.disabled = not _shop.can_reroll()
	var focused := get_viewport().gui_get_focus_owner() as Button
	if focused != null and focused.disabled and is_ancestor_of(focused):
		_continue.grab_focus.call_deferred()

func _weapon_text(definition: WeaponDefinition) -> String:
	var stats := RoundShop.weapon_stats(definition, _state.projectile_bonus)
	return "DMG %s · RATE %s · ×%s\nSPLASH %s · PIERCE %s · %s" % [stats.DMG, stats.RATE, stats.PELLETS, stats.SPLASH, stats.PIERCE, stats.TYPE]

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
	_swap.text = "EQUIPPED" if current else "SWAP FREE"

func _select_candidate(index: int) -> void:
	_candidate = index
	_refresh_comparison()

func _on_swap() -> void:
	if _candidate >= 0 and _candidate < _state.available_weapons.size() and _state.swap_primary(_state.available_weapons[_candidate]):
		_status.text = "Primary swapped. All purchased mod ranks retained."
	_refresh()

func _on_buy_ability(slot: int) -> void:
	var success := _shop.buy_ability(slot)
	_status.text = "Ability %d upgraded to rank %d." % [slot + 1, _state.ability_rank(slot)] if success else "Purchase refused. Nothing charged."
	_refresh()

func _on_buy(index: int) -> void:
	_status.text = "Upgrade installed." if _shop.buy(index) else "Purchase refused: sold, maxed or not enough minerals. Nothing charged."
	_refresh()

func _on_reroll() -> void:
	_status.text = "Unsold stock replaced." if _shop.reroll() else "Reroll unavailable. Wallet unchanged."
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
			parts.append("%d %s" % [amount, "Cinder" if mineral.id == &"crystal" else mineral.display_name])
	return "FREE" if parts.is_empty() else " + ".join(parts)

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.06, 0.95)
	style.border_color = Color(0.1, 0.4, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
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
