class_name RoundShopScreen
extends Control

signal continue_requested(hand: int)

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const MINERALS: Array[ResourceDefinition] = [preload("res://data/resources/gold.tres"), preload("res://data/resources/crystal.tres"), preload("res://data/resources/shard.tres")]

var _shop: RoundShop
var _state: RunState
var _selected_hand := 0
var _title: Label
var _summary: Label
var _currency: CurrencyBar
var _hand_buttons: Array[Button] = []
var _hand_details: Array[Label] = []
var _cards: Array[Dictionary] = []
var _status: Label
var _run_bonuses: Label
var _reroll: Button
var _continue: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MENU_THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.025, 0.04, 0.96)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"left", &"top", &"right", &"bottom"]:
		margin.add_theme_constant_override(StringName("margin_" + String(side)), 24)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 10)
	margin.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	_title = _label("ROUND CLEARED", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_currency = CurrencyBar.new()
	_currency.currencies = MINERALS
	_currency.font_size = 17
	_currency.add_theme_constant_override(&"separation", 18)
	header.add_child(_currency)
	_summary = _label("", 15)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.max_lines_visible = 2
	rows.add_child(_summary)
	rows.add_child(_label("SELECT A HAND  ·  Weapon upgrades affect only that hand. Shop bonuses last for this run.", 16))
	var hands := HBoxContainer.new()
	hands.add_theme_constant_override(&"separation", 12)
	rows.add_child(hands)
	for index in range(3):
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"CardPanel"
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hands.add_child(panel)
		var hand_rows := VBoxContainer.new()
		hand_rows.add_theme_constant_override(&"separation", 5)
		panel.add_child(hand_rows)
		var select := Button.new()
		select.add_theme_font_size_override(&"font_size", 16)
		select.pressed.connect(_select_hand.bind(index))
		hand_rows.add_child(select)
		_hand_buttons.append(select)
		var details := _label("", 14)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hand_rows.add_child(details)
		_hand_details.append(details)
	_run_bonuses = _label("", 14)
	_run_bonuses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_run_bonuses)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	rows.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	scroll.add_child(grid)
	for index in range(4):
		_build_offer(grid, index)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 16)
	rows.add_child(footer)
	_reroll = Button.new()
	_reroll.add_theme_font_size_override(&"font_size", 17)
	_reroll.pressed.connect(_on_reroll)
	footer.add_child(_reroll)
	_continue = Button.new()
	_continue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue.theme_type_variation = &"AccentButton"
	_continue.pressed.connect(_on_continue)
	footer.add_child(_continue)
	_status = _label("", 15)
	_status.custom_minimum_size.y = 36
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_status)
	Profile.currency_changed.connect(_on_wallet_changed)
	hide()

func _build_offer(parent: Container, index: int) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	panel.add_child(rows)
	var title := _label("", 20)
	rows.add_child(title)
	var description := _label("", 15)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(description)
	var availability := _label("", 14)
	rows.add_child(availability)
	var buy := Button.new()
	buy.add_theme_font_size_override(&"font_size", 16)
	buy.pressed.connect(_on_buy.bind(index))
	rows.add_child(buy)
	_cards.append({"title": title, "description": description, "availability": availability, "buy": buy})

func open(state: RunState, stage: int, final_stage: bool, summary: String, focused_hand: int) -> void:
	_state = state
	_selected_hand = clampi(focused_hand, 0, state.hands.size() - 1)
	_shop = RoundShop.new()
	_shop.setup(state, stage, randi())
	_title.text = "ROUND %d CLEARED  //  MINERAL EXCHANGE" % (stage + 1)
	_summary.text = summary
	_continue.text = "RETURN TO BASE" if final_stage else "CONTINUE TO ROUND %d" % (stage + 2)
	_status.text = "Your minerals are banked. Choose a hand, buy upgrades, or save your wallet for base crafting."
	show()
	_refresh()
	_hand_buttons[_selected_hand].grab_focus.call_deferred()

func _refresh() -> void:
	if _shop == null:
		return
	_currency.refresh()
	for index in range(3):
		var hand := _state.hands[index]
		var definition := hand.definition
		_hand_buttons[index].text = "HAND %d%s  ·  %s" % [index + 1, " [SELECTED]" if index == _selected_hand else "", definition.display_name]
		# Avoid a long authored name forcing the three columns off screen.
		_hand_buttons[index].text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_hand_buttons[index].clip_text = true
		var pellets := clampi(definition.pellet_count + _state.projectile_bonus, 1, WeaponHand.MAX_PROJECTILES)
		_hand_details[index].text = "%d base damage · %d projectiles · %s\n%.2fs cadence · %.1fm splash · %d pierce\n%s" % [definition.damage, pellets, DamageType.label(definition.damage_type), definition.fire_interval, definition.explosion_radius, definition.pierce, _levels(hand.upgrade_levels)]
	_run_bonuses.text = "RUN BONUSES  ·  Damage ×%.2f  ·  Fire rate ×%.2f  ·  Armor %.1f  ·  Health +%d  ·  Extra projectiles +%d" % [_state.damage_multiplier, _state.fire_rate_multiplier, _state.armor, _state.max_health_bonus, _state.projectile_bonus]
	for index in range(_cards.size()):
		var offer: Dictionary = _shop.offers[index]
		var card := _cards[index]
		var title: Label = card.title
		title.text = String(offer.name)
		var description: Label = card.description
		description.text = String(offer.description)
		var buy: Button = card.buy
		buy.disabled = not _shop.can_buy(index, _selected_hand)
		buy.text = "SOLD" if bool(offer.sold) else "BUY  ·  " + _price(offer.cost)
		var availability: Label = card.availability
		if bool(offer.sold):
			availability.text = "Purchased. Reroll for fresh stock."
		elif not Profile.can_pay(offer.cost):
			availability.text = "Insufficient banked minerals."
		elif buy.disabled:
			availability.text = "Unavailable / maximum rank reached."
		else:
			availability.text = "Ready to purchase · selected hand %d" % (_selected_hand + 1)
	var reroll_cost := _shop.reroll_cost()
	_reroll.text = "REROLL  ·  " + _price(reroll_cost)
	_reroll.disabled = not _shop.can_reroll()

func _select_hand(hand: int) -> void:
	_selected_hand = hand
	_refresh()

func _on_buy(index: int) -> void:
	var name_text := String(_shop.offers[index].name)
	if _shop.buy(index, _selected_hand):
		_status.text = "%s purchased for this run. Hand %d and run bonuses are updated above." % [name_text, _selected_hand + 1]
	else:
		_status.text = "Purchase refused: sold, maximum rank, or insufficient minerals. Nothing was charged."
	_refresh()
	_hand_buttons[_selected_hand].grab_focus.call_deferred()

func _on_reroll() -> void:
	if _shop.reroll():
		_status.text = "New stock delivered. Reroll prices increase after each paid refresh."
	else:
		_status.text = "Reroll unavailable: insufficient minerals or all effects capped. Wallet and stock are unchanged."
	_refresh()
	if _reroll.disabled:
		_continue.grab_focus.call_deferred()

func _on_continue() -> void:
	hide()
	continue_requested.emit(_selected_hand)

func _on_wallet_changed(_id: StringName, _amount: int) -> void:
	if is_visible_in_tree():
		_refresh.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	# Escape cannot bypass the between-round transaction/continuation flow.
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_continue.grab_focus()

func _levels(levels: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in [&"projectiles", &"splash", &"fire", &"frost", &"shock", &"damage", &"cadence", &"pierce"]:
		var rank := int(levels.get(kind, 0))
		if rank > 0:
			parts.append("%s %d" % [String(kind).capitalize(), rank])
	return "UPGRADES: " + (" · ".join(parts) if not parts.is_empty() else "None")

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
