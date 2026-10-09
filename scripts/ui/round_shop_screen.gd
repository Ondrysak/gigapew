class_name RoundShopScreen
extends Control

## Between-round mineral exchange. Header (round, run summary, banked minerals,
## wallet), three hand loadout cards (click or 1/2/3 selects the hand that
## WEAPON MODS install on), run-wide SUIT SYSTEMS, and a reroll / continue
## footer with a purchase status line. Esc never skips the shop.

signal continue_requested(hand: int)

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const MINERALS: Array[ResourceDefinition] = [preload("res://data/resources/gold.tres"), preload("res://data/resources/crystal.tres"), preload("res://data/resources/shard.tres")]
const GAP := 12
const TEXT := Color(0.83, 0.96, 0.99)
const DIM := Color(0.5, 0.66, 0.72)
const TEAL := Color(0.3, 0.85, 0.88)
const ACCENT := Color(1.0, 0.62, 0.2)
const GOOD := Color(0.5, 1.0, 0.62)
const BAD := Color(1.0, 0.36, 0.3)
const CARD_FILL := Color(0.02, 0.04, 0.06, 0.95)
const SELECTED_FILL := Color(0.1, 0.06, 0.02, 0.97)
## Indexed by RoundShop.Track.
const TRACK_COLORS: Array[Color] = [Color(1.0, 0.42, 0.36), Color(0.3, 0.85, 0.88), Color(0.82, 0.6, 1.0), Color(0.5, 0.95, 0.6)]
const HAND_STATS: Array[String] = ["DMG", "RATE", "PELLETS", "SPLASH", "PIERCE"]
const ELEMENTS := {&"fire": DamageType.Kind.FIRE, &"frost": DamageType.Kind.FROST, &"shock": DamageType.Kind.SHOCK}
## Stock cards in the 3-column grid: two mod columns, then the suit column.
const GRID_ORDER: Array[int] = [0, 1, 4, 2, 3, 5]

## Crisp rank boxes (filled = owned ranks).
class Pips extends Control:
	const BOX := 8.0
	const STEP := 11.0
	var filled := 0
	var total := 0
	var tint := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func show_ranks(value: int, maximum: int, color: Color) -> void:
		filled = value
		total = maximum
		tint = color
		custom_minimum_size = Vector2(maxf(total * STEP - (STEP - BOX), 0.0), BOX)
		queue_redraw()

	func _draw() -> void:
		for index in total:
			var box := Rect2(index * STEP, floorf((size.y - BOX) * 0.5), BOX, BOX)
			if index < filled:
				draw_rect(box, tint)
			else:
				draw_rect(box, Color(tint, 0.1))
				draw_rect(box.grow(-0.5), Color(tint, 0.45), false, 1.0)

var _shop: RoundShop
var _state: RunState
var _selected_hand := 0
var _title: Label
var _summary: Label
var _banked: Label
var _wallet: Dictionary = {}
var _hands: Array[Dictionary] = []
var _mods_target: Label
var _styles: Dictionary = {}
var _suit_stats: Dictionary = {}
var _cards: Array[Dictionary] = []
var _reroll: Button
var _reroll_price: Dictionary = {}
var _status: Label
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
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 22)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	margin.add_child(rows)
	_build_header(rows)
	rows.add_child(_rule())
	var loadout := _row(8)
	loadout.add_child(_label("LOADOUT", 14, TEAL))
	loadout.add_child(_label("Click a hand or press 1 · 2 · 3. Weapon mods install on the selected hand.", 14, DIM))
	rows.add_child(loadout)
	var hands := HBoxContainer.new()
	hands.add_theme_constant_override(&"separation", GAP)
	rows.add_child(hands)
	for index in range(3):
		_build_hand(hands, index)
	_build_section_heads(rows)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	rows.add_child(grid)
	_cards.resize(RoundShop.MOD_SLOTS + RoundShop.SUIT_SLOTS)
	for index in GRID_ORDER:
		_cards[index] = _build_offer(grid, index)
	rows.add_child(_rule())
	_build_footer(rows)
	Profile.currency_changed.connect(_on_wallet_changed)
	hide()

# ------------------------------------------------------------ building

func _build_header(parent: Container) -> void:
	var header := _row(16)
	parent.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title_row := _row(14)
	titles.add_child(title_row)
	_title = _label("ROUND CLEARED", 30, Color(0.88, 0.98, 1.0))
	title_row.add_child(_title)
	title_row.add_child(_chip("MINERAL EXCHANGE", TEAL))
	var run := _row(18)
	titles.add_child(run)
	_summary = _label("", 14, DIM)
	run.add_child(_summary)
	_banked = _label("", 14, Color(1.0, 0.84, 0.5))
	run.add_child(_banked)
	var wallet := _row(8)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wallet)
	for mineral in MINERALS:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override(&"panel", _box(Color(0.03, 0.07, 0.09, 0.95), Color(mineral.color, 0.55), 1, 6, Vector2(10, 6)))
		wallet.add_child(chip)
		var body := _row(8)
		chip.add_child(body)
		body.add_child(GameIcons.rect(mineral.icon, 32))
		var text := VBoxContainer.new()
		text.add_theme_constant_override(&"separation", -2)
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		body.add_child(text)
		var amount := _label("0", 20, mineral.color.lightened(0.25))
		text.add_child(amount)
		text.add_child(_label(mineral.display_name.to_upper(), 11, DIM))
		_wallet[mineral.id] = amount

func _build_hand(parent: Container, index: int) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	var top := _row(12)
	content.add_child(top)
	var icon := GameIcons.rect(null, 48)
	top.add_child(icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var title_row := _row(8)
	info.add_child(title_row)
	var title := _label("", 19, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title_row.add_child(title)
	var slot := _chip("HAND %d" % (index + 1), DIM)
	title_row.add_child(slot)
	var type_row := _row(6)
	info.add_child(type_row)
	var type_icon := GameIcons.rect(null, 16)
	type_row.add_child(type_icon)
	var type_label := _label("", 13, TEXT)
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_label)
	var tag := _label("SELECTED", 12, ACCENT)
	type_row.add_child(tag)
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override(&"panel", _box(Color(0.03, 0.08, 0.1, 0.9), Color(0, 0, 0, 0), 0, 4, Vector2(6, 4)))
	content.add_child(strip)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override(&"separation", 4)
	strip.add_child(stats_row)
	var stats := {}
	var captions := {}
	for stat in HAND_STATS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override(&"separation", -2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_row.add_child(column)
		var caption := _label(stat, 11, DIM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		var value := _label("", 17, TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(value)
		stats[stat] = value
		captions[stat] = caption
	var tracks := VBoxContainer.new()
	tracks.add_theme_constant_override(&"separation", 3)
	content.add_child(tracks)
	var pips := {}
	var elements := {}
	for track: int in [RoundShop.Track.FIREPOWER, RoundShop.Track.PAYLOAD, RoundShop.Track.ELEMENT]:
		var line := _row(10)
		tracks.add_child(line)
		var name_label := _label(RoundShop.TRACK_NAMES[track], 11, TRACK_COLORS[track])
		name_label.custom_minimum_size.x = 70
		line.add_child(name_label)
		for id in RoundShop.ids_in_track(track):
			var group := _row(4)
			line.add_child(group)
			var mod_icon := GameIcons.rect(RoundShop.icon(id), 16)
			group.add_child(mod_icon)
			if track == RoundShop.Track.ELEMENT:
				elements[id] = mod_icon
			else:
				var boxes := Pips.new()
				group.add_child(boxes)
				pips[id] = boxes
	var button := _content_button(content, Vector2(14, 10))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_select_hand.bind(index))
	parent.add_child(button)
	_hands.append({"button": button, "icon": icon, "slot": slot, "tag": tag, "title": title, "type_icon": type_icon, "type_label": type_label, "stats": stats, "captions": captions, "pips": pips, "elements": elements})

func _build_section_heads(parent: Container) -> void:
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override(&"separation", GAP)
	parent.add_child(heads)
	var mods := _row(8)
	mods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mods.size_flags_stretch_ratio = 2.0
	heads.add_child(mods)
	mods.add_child(_label("WEAPON MODS", 14, TEAL))
	_mods_target = _label("", 14, ACCENT)
	mods.add_child(_mods_target)
	var suit := _row(8)
	suit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_child(suit)
	var suit_title := _label("SUIT SYSTEMS", 14, TEAL)
	suit_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	suit.add_child(suit_title)
	for id: StringName in [&"armor", &"health", &"power"]:
		var stat := _row(4)
		suit.add_child(stat)
		stat.add_child(GameIcons.rect(RoundShop.icon(id), 16))
		var value := _label("", 13, TEXT)
		stat.add_child(value)
		_suit_stats[id] = value
	# Keep the mods heading exactly as wide as two stock columns.
	heads.resized.connect(func() -> void:
		mods.size_flags_stretch_ratio = 2.0 + 3.0 * GAP / maxf(heads.size.x - 2.0 * GAP, 1.0))

func _build_offer(parent: Container, index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	panel.add_child(rows)
	var top := _row(12)
	rows.add_child(top)
	var icon := GameIcons.rect(null, 48)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var title_row := _row(8)
	info.add_child(title_row)
	var title := _label("", 17, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title_row.add_child(title)
	var track := _chip("", TEAL)
	title_row.add_child(track)
	var effect := _label("", 13, DIM)
	effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effect.clip_text = true
	info.add_child(effect)
	var preview := _row(6)
	info.add_child(preview)
	var stat := _label("", 12, DIM)
	preview.add_child(stat)
	var from := _label("", 15, TEXT)
	preview.add_child(from)
	var arrow := _label("→", 15, DIM)
	preview.add_child(arrow)
	var to := _label("", 15, GOOD)
	to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_child(to)
	var pips := Pips.new()
	preview.add_child(pips)
	var bottom := _row(10)
	rows.add_child(bottom)
	var price := _price_row(bottom)
	var buy := Button.new()
	buy.custom_minimum_size.x = 120
	buy.add_theme_font_size_override(&"font_size", 16)
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		buy.add_theme_stylebox_override(state, _compact_style(state))
	buy.pressed.connect(_on_buy.bind(index))
	bottom.add_child(buy)
	return {"panel": panel, "icon": icon, "title": title, "track": track, "effect": effect, "stat": stat, "from": from, "arrow": arrow, "to": to, "pips": pips, "price": price, "buy": buy}

func _build_footer(parent: Container) -> void:
	var footer := _row(16)
	parent.add_child(footer)
	var content := _row(10)
	content.add_child(GameIcons.rect(RoundShop.icon(&"reroll"), 32))
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 0)
	content.add_child(text)
	text.add_child(_label("REROLL STOCK", 15, TEXT))
	_reroll_price = _price_row(text)
	_reroll = _content_button(content, Vector2(16, 6))
	_reroll.custom_minimum_size.x = maxf(_reroll.custom_minimum_size.x, 210.0)
	_reroll.pressed.connect(_on_reroll)
	footer.add_child(_reroll)
	_status = _label("", 14, TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_status)
	_continue = Button.new()
	_continue.theme_type_variation = &"AccentButton"
	_continue.custom_minimum_size.x = 340
	_continue.add_theme_font_size_override(&"font_size", 21)
	_continue.pressed.connect(_on_continue)
	footer.add_child(_continue)

## One chip (icon + amount) per mineral; hidden when a price omits it.
func _price_row(parent: Container) -> Dictionary:
	var row := _row(10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(row)
	var chips := {}
	for mineral in MINERALS:
		var chip := _row(4)
		row.add_child(chip)
		chip.add_child(GameIcons.rect(mineral.icon, 16))
		var amount := _label("", 15, TEXT)
		chip.add_child(amount)
		chips[mineral.id] = {"chip": chip, "amount": amount, "color": mineral.color.lightened(0.3)}
	return chips

# ------------------------------------------------------------ flow

func open(state: RunState, stage: int, final_stage: bool, summary: String, focused_hand: int) -> void:
	_state = state
	_selected_hand = clampi(focused_hand, 0, state.hands.size() - 1)
	_shop = RoundShop.new()
	_shop.setup(state, stage, randi())
	_title.text = "ROUND %d CLEARED" % (stage + 1)
	var lines := summary.split("\n", false, 1)
	_summary.text = lines[0] if lines.size() > 0 else ""
	_banked.text = lines[1].replace("\n", "   ") if lines.size() > 1 else ""
	_continue.text = "RETURN TO BASE" if final_stage else "CONTINUE TO ROUND %d" % (stage + 2)
	_set_status("Minerals banked. Buy mods for the selected hand or suit systems for the run, or save them for base crafting.", TEXT)
	show()
	_refresh()
	_hands[_selected_hand].button.grab_focus.call_deferred()

func _refresh() -> void:
	if _shop == null:
		return
	for id: StringName in _wallet:
		_wallet[id].text = str(Profile.currency(id))
	for index in range(_hands.size()):
		_refresh_hand(index)
	var selected := _state.hands[_selected_hand].definition
	_mods_target.text = "→  HAND %d · %s" % [_selected_hand + 1, selected.display_name.to_upper()]
	_suit_stats[&"armor"].text = RoundShop.number(_state.armor)
	_suit_stats[&"health"].text = "+%d" % _state.max_health_bonus
	_suit_stats[&"power"].text = "×%.2f" % _state.damage_multiplier
	for index in range(_cards.size()):
		_refresh_offer(index)
	_show_price(_reroll_price, _shop.reroll_cost(), false)
	_reroll.disabled = not _shop.can_reroll()
	_reroll.get_child(0).modulate = Color(1, 1, 1, 0.45) if _reroll.disabled else Color.WHITE
	# A button that just became unusable (sold, maxed, broke) hands keyboard focus to continue.
	var focused := get_viewport().gui_get_focus_owner() as Button
	if focused != null and focused.disabled and is_ancestor_of(focused):
		_continue.grab_focus.call_deferred()

func _refresh_hand(index: int) -> void:
	var card := _hands[index]
	var hand := _state.hands[index]
	var definition := hand.definition
	var selected := index == _selected_hand
	card.icon.texture = definition.icon if definition.icon != null else GameIcons.lookup(&"hud", &"hand")
	card.title.text = definition.display_name.to_upper()
	_set_chip(card.slot, "HAND %d" % (index + 1), ACCENT if selected else DIM)
	card.tag.visible = selected
	var kind := definition.damage_type
	card.type_icon.texture = GameIcons.damage_type(kind)
	card.type_label.text = DamageType.label(kind).to_upper()
	card.type_label.add_theme_color_override(&"font_color", DamageType.color(kind))
	var stats := RoundShop.hand_stats(definition, _state.projectile_bonus)
	for stat: String in card.stats:
		var readout := stat
		if definition.kind == WeaponDefinition.Kind.MELEE:
			if stat == "PELLETS":
				readout = "ARC"
			elif stat == "PIERCE":
				readout = "REACH"
		card.captions[stat].text = readout
		card.stats[stat].text = stats[readout]
	for id: StringName in card.pips:
		card.pips[id].show_ranks(hand.rank(id), RoundShop.max_rank(id), TRACK_COLORS[RoundShop.track(id)])
		card.pips[id].modulate.a = 1.0 if hand.supports(id) else 0.25
	for id: StringName in card.elements:
		card.elements[id].modulate = Color.WHITE if kind == ELEMENTS[id] else Color(1, 1, 1, 0.2)
	var button: Button = card.button
	var border := ACCENT if selected else Color(0.1, 0.4, 0.45)
	var fill := SELECTED_FILL if selected else CARD_FILL
	var width := 3 if selected else 2
	button.add_theme_stylebox_override(&"normal", _box(fill, border, width, 8, Vector2.ZERO))
	button.add_theme_stylebox_override(&"hover", _box(fill.lightened(0.04), ACCENT.lightened(0.25) if selected else TEAL, width, 8, Vector2.ZERO))
	button.add_theme_stylebox_override(&"pressed", _box(fill.lightened(0.06), ACCENT.lightened(0.35), width, 8, Vector2.ZERO))
	button.add_theme_stylebox_override(&"focus", _box(Color(0, 0, 0, 0), Color(0.75, 1.0, 1.0, 0.9), 2, 10, Vector2.ZERO, 4.0))

func _refresh_offer(index: int) -> void:
	var card := _cards[index]
	var offer: Dictionary = _shop.offers[index]
	var id := StringName(offer.id)
	var entry: Dictionary = RoundShop.CATALOG[id]
	var track := RoundShop.track(id)
	var color := TRACK_COLORS[track]
	var sold := bool(offer.sold)
	var buyable := _shop.can_buy(index, _selected_hand)
	var maxed := _shop.is_maxed(id, _selected_hand)
	var unsupported := RoundShop.is_hand_mod(id) and not _state.hands[_selected_hand].supports(id)
	card.icon.texture = RoundShop.icon(id)
	card.title.text = String(entry.name)
	_set_chip(card.track, RoundShop.TRACK_NAMES[track], color)
	card.effect.text = String(entry.effect)
	var preview := _shop.preview(id, _selected_hand)
	card.stat.text = String(preview.stat)
	card.from.text = String(preview.from)
	var to := String(preview.to)
	card.arrow.visible = not to.is_empty()
	card.to.text = to if not to.is_empty() else ("N/A" if unsupported else ("MAX" if maxed or track != RoundShop.Track.ELEMENT else "ACTIVE"))
	card.to.add_theme_color_override(&"font_color", GOOD if not to.is_empty() else DIM)
	card.pips.show_ranks(_shop.rank(id, _selected_hand), RoundShop.max_rank(id), color)
	_show_price(card.price, offer.cost, sold)
	var buy: Button = card.buy
	buy.disabled = not buyable
	if sold:
		buy.text = "SOLD"
	elif unsupported:
		buy.text = "FIREARMS ONLY"
	elif not to.is_empty():
		buy.text = "BUY"
	elif track == RoundShop.Track.ELEMENT and not maxed:
		buy.text = "ACTIVE"
	else:
		buy.text = "MAXED"
	var panel: PanelContainer = card.panel
	var live := not sold and not to.is_empty()
	panel.add_theme_stylebox_override(&"panel", _box(CARD_FILL, Color(color, 0.7) if live else Color(0.12, 0.2, 0.23), 2, 8, Vector2(14, 12)))
	panel.modulate = Color(1, 1, 1, 0.5) if sold else Color.WHITE
	card.icon.modulate = Color.WHITE if live else Color(1, 1, 1, 0.55)

## Fills price chips; amounts the wallet cannot cover turn red.
func _show_price(chips: Dictionary, cost: Dictionary, muted: bool) -> void:
	for id: StringName in chips:
		var chip: Dictionary = chips[id]
		var amount := int(cost.get(id, 0))
		chip.chip.visible = cost.has(id)
		chip.amount.text = str(amount)
		var short := Profile.currency(id) < amount
		chip.amount.add_theme_color_override(&"font_color", DIM if muted else (BAD if short else chip.color))

func _select_hand(hand: int) -> void:
	if _state == null or hand < 0 or hand >= _state.hands.size():
		return
	_selected_hand = hand
	_refresh()

func _on_buy(index: int) -> void:
	var id := StringName(_shop.offers[index].id)
	var name_text := String(RoundShop.CATALOG[id].name)
	var hand_mod := RoundShop.is_hand_mod(id)
	if _shop.buy(index, _selected_hand):
		var target := "HAND %d · %s" % [_selected_hand + 1, _state.hands[_selected_hand].definition.display_name.to_upper()] if hand_mod else "your suit for the rest of the run"
		_set_status("%s installed on %s." % [name_text, target], GOOD)
	else:
		_set_status("Purchase refused: sold, maxed or not enough minerals. Nothing was charged.", ACCENT)
	_refresh()
	_focus_next_offer(index)

func _on_reroll() -> void:
	if _shop.reroll():
		_set_status("Unsold stock replaced. Each reroll costs more than the last.", GOOD)
	else:
		_set_status("Reroll unavailable: not enough minerals or nothing left to roll. Wallet and stock unchanged.", ACCENT)
	_refresh()

func _on_continue() -> void:
	hide()
	continue_requested.emit(_selected_hand)

func _on_wallet_changed(_id: StringName, _amount: int) -> void:
	if is_visible_in_tree():
		_refresh.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Escape cannot bypass the between-round transaction/continuation flow.
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_continue.grab_focus()
		return
	for hand in range(3):
		if event.is_action_pressed(StringName("weapon_%d" % (hand + 1))):
			get_viewport().set_input_as_handled()
			var hand_focused := false
			for card in _hands:
				hand_focused = hand_focused or card.button.has_focus()
			_select_hand(hand)
			if hand_focused:
				_hands[hand].button.grab_focus()
			return

## Keeps keyboard flow on the stock: the next buyable card, else continue.
func _focus_next_offer(index: int) -> void:
	var start := GRID_ORDER.find(index)
	for step in range(GRID_ORDER.size()):
		var buy: Button = _cards[GRID_ORDER[(start + step) % GRID_ORDER.size()]].buy
		if not buy.disabled:
			buy.grab_focus.call_deferred()
			return
	_continue.grab_focus.call_deferred()

func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)

# ------------------------------------------------------------ widgets

## A Button whose face is an arbitrary layout: `content` fills it inside
## `padding` and drives its minimum size; children never take the mouse.
func _content_button(content: Control, padding: Vector2) -> Button:
	var button := Button.new()
	button.add_child(content)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = padding.x
	content.offset_top = padding.y
	content.offset_right = -padding.x
	content.offset_bottom = -padding.y
	var fit := func() -> void:
		button.custom_minimum_size.y = content.get_combined_minimum_size().y + padding.y * 2.0
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, content.get_combined_minimum_size().x + padding.x * 2.0)
	content.minimum_size_changed.connect(fit)
	fit.call()
	_ignore_mouse(content)
	return button

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(_label(text, 11, color))
	_set_chip(chip, text, color)
	return chip

func _set_chip(chip: PanelContainer, text: String, color: Color) -> void:
	chip.add_theme_stylebox_override(&"panel", _box(Color(color, 0.14), Color(color, 0.6), 1, 3, Vector2(6, 1)))
	var label := chip.get_child(0) as Label
	label.text = text
	label.add_theme_color_override(&"font_color", color)

## Shared, memoized flat styles (refreshes reuse them instead of allocating).
## A transparent fill draws only the border; `expand` grows it outward.
func _box(fill: Color, border: Color, width: int, radius: int, padding: Vector2, expand := 0.0) -> StyleBoxFlat:
	var key := [fill, border, width, radius, padding, expand]
	if _styles.has(key):
		return _styles[key]
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = fill.a > 0.0
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_expand_margin_all(expand)
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	_styles[key] = style
	return style

## The theme's button look with a shorter face for in-card BUY buttons.
func _compact_style(state: StringName) -> StyleBox:
	var key := [&"compact", state]
	if not _styles.has(key):
		var style := MENU_THEME.get_stylebox(state, &"Button").duplicate() as StyleBox
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		_styles[key] = style
	return _styles[key]

func _rule() -> HSeparator:
	var rule := HSeparator.new()
	rule.add_theme_constant_override(&"separation", 4)
	return rule

func _row(separation: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", separation)
	return row

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
