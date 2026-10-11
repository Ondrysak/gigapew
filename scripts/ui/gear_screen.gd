class_name GearScreen
extends CanvasLayer

## The consumer owns pause, mouse capture and equipping. This layer only picks.
signal chosen(item: GearDefinition, replace_slot: int)
signal declined

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const TEXT := Color(0.87, 0.81, 0.67)
const DIM := Color(0.65, 0.60, 0.49)
const AMBER := Color(0.72, 0.55, 0.32)
const BAD := Color(0.78, 0.43, 0.34)

var offer_buttons: Array[Button] = []
var replacement_buttons: Array[Button] = []
var leave_button: Button
var back_button: Button
var input_delay := 0.25
var _root: Control
var _title: Label
var _hint: Label
var _comparison: Label
var _grid: GridContainer
var _state: RunState
var _offers: Array[GearDefinition] = []
var _selected: GearDefinition
var _mode := "offers"
var _open := false
var _arming := 0.0
var _generation := 0

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()

func _build() -> void:
	_root = Control.new()
	_root.theme = MENU_THEME
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.045, 0.035, 0.025, 0.98)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 36)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	_root.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 12)
	margin.add_child(rows)
	_title = _label("VÝBAVA", 28, AMBER)
	rows.add_child(_title)
	_hint = _label("", 15, TEXT)
	rows.add_child(_hint)
	_comparison = _label("", 14, TEXT)
	rows.add_child(_comparison)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	rows.add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 12)
	_grid.add_theme_constant_override(&"v_separation", 12)
	scroll.add_child(_grid)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 16)
	rows.add_child(footer)
	back_button = Button.new()
	back_button.text = "ZPĚT K NABÍDCE"
	back_button.pressed.connect(_back)
	footer.add_child(back_button)
	var help := _label("1–4 výběr · šipky / Tab pohyb · Enter potvrzení · Esc odejít", 14, DIM)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	leave_button = Button.new()
	leave_button.text = "NECHAT BÝT · ESC"
	leave_button.pressed.connect(_decline)
	footer.add_child(leave_button)
	StreetWear.apply_tree(_root)

func present(offers: Array[GearDefinition], state: RunState, title: String) -> void:
	_state = state
	_offers.clear()
	for item in offers:
		if item != null and _offers.size() < 3:
			_offers.append(item)
	_selected = null
	_mode = "offers"
	_title.text = title
	_open = true
	show()
	_render()

func present_inventory(state: RunState) -> void:
	_state = state
	_selected = null
	_mode = "inventory"
	_title.text = "VÝBAVA TOHLEHO BĚHU"
	_open = true
	show()
	_render()

func close() -> void:
	_open = false
	_generation += 1
	hide()
	for slot in range(1, 6):
		var action := StringName("ability_%d" % slot)
		if InputMap.has_action(action):
			Input.action_release(action)

func _process(delta: float) -> void:
	if _open:
		_arming = maxf(0.0, _arming - delta)

func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_decline()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_4:
		get_viewport().set_input_as_handled()
		var index := int(key.keycode - KEY_1)
		if _mode == "offers":
			_choose_offer(index, _generation)
		elif _mode == "replace":
			_replace(index, _generation)
		elif index < offer_buttons.size():
			offer_buttons[index].grab_focus()

func _render() -> void:
	_generation += 1
	_arming = input_delay
	offer_buttons.clear()
	replacement_buttons.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	back_button.visible = _mode == "replace"
	leave_button.text = "ZAVŘÍT · ESC" if _mode == "inventory" else "NECHAT BÝT · ESC"
	_comparison.visible = _mode == "replace"
	if _mode == "offers":
		_grid.columns = maxi(1, _offers.size())
		_hint.text = "Vyber jednu věc · %d / 4 míst obsazeno · výbava vydrží do konce běhu" % _state.gear.size()
		for index in range(_offers.size()):
			var item := _offers[index]
			var discovery := "NOVÝ OBJEV · odemčeno pro budoucí běžné dropy" if bool(item.get_meta(&"newly_discovered", false)) else "OBJEVENO · dostupné v budoucích běžných dropech"
			var button := _card(item, index + 1, discovery)
			button.pressed.connect(_choose_offer.bind(index, _generation))
			offer_buttons.append(button)
	elif _mode == "replace":
		_grid.columns = 2
		_hint.text = "Všechna čtyři místa jsou plná. Výslovně vyber věc, kterou zahodíš."
		_comparison.text = "BEREŠ: %s%s\n%s\n„%s“" % [_selected.display_name, " · PROKLETÉ" if _selected.cursed else "", _selected.description, _selected.quote]
		for index in range(_state.gear.size()):
			var button := _card(_state.gear[index], index + 1, "ZAHODIT TUTO VĚC → vzít %s" % _selected.display_name)
			button.pressed.connect(_replace.bind(index, _generation))
			replacement_buttons.append(button)
	else:
		_grid.columns = 2
		_hint.text = "Pouze prohlížení · %d / 4 míst · další běh začíná bez výbavy" % _state.gear.size()
		for index in range(4):
			if index < _state.gear.size():
				offer_buttons.append(_card(_state.gear[index], index + 1, "VYBAVENO · plný účinek a hláška"))
			else:
				var empty := Button.new()
				empty.text = "%d · VOLNÉ MÍSTO\nNajdi skrýš nebo poraz elitu." % (index + 1)
				empty.custom_minimum_size.y = 210
				empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_grid.add_child(empty)
				offer_buttons.append(empty)
	StreetWear.apply_tree(_grid)
	var buttons: Array[Button] = replacement_buttons if _mode == "replace" else offer_buttons
	for index in range(buttons.size()):
		var button := buttons[index]
		button.focus_neighbor_left = button.get_path_to(buttons[maxi(0, index - 1)])
		button.focus_neighbor_right = button.get_path_to(buttons[mini(buttons.size() - 1, index + 1)])
		button.focus_neighbor_top = button.get_path_to(buttons[maxi(0, index - _grid.columns)])
		button.focus_neighbor_bottom = button.get_path_to(buttons[index + _grid.columns]) if index + _grid.columns < buttons.size() else button.get_path_to(leave_button)
	if not buttons.is_empty():
		buttons[0].grab_focus()
	else:
		leave_button.grab_focus()

func _card(item: GearDefinition, number: int, caption: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 210)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(button)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	button.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 7)
	margin.add_child(rows)
	var heading := HBoxContainer.new()
	rows.add_child(heading)
	heading.add_child(GameIcons.rect(item.icon, 40))
	var name_label := _label("%d · %s" % [number, item.display_name], 19, item.accent_color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	if item.cursed:
		rows.add_child(_label("PROKLETÉ · bonus za cenu postihu", 14, BAD))
	rows.add_child(_label(item.description, 16, TEXT))
	var quote := _label("„%s“" % item.quote, 14, DIM)
	quote.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(quote)
	rows.add_child(_label(caption, 13, AMBER))
	_ignore_mouse(margin)
	rows.minimum_size_changed.connect(_fit_card.bind(button, rows))
	_fit_card(button, rows)
	return button

func _fit_card(button: Button, rows: VBoxContainer) -> void:
	# Wrapped descriptions must grow the grid, never paint over another card.
	button.custom_minimum_size.y = maxf(210.0, rows.get_combined_minimum_size().y + 24.0)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label

func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_mouse(child)

func _choose_offer(index: int, generation: int) -> void:
	if not _open or _arming > 0.0 or generation != _generation or _mode != "offers" or index < 0 or index >= _offers.size():
		return
	_selected = _offers[index]
	if _state.gear.size() < RunState.MAX_GEAR:
		var item := _selected
		close()
		chosen.emit(item, -1)
	else:
		_mode = "replace"
		_render()

func _replace(index: int, generation: int) -> void:
	if not _open or _arming > 0.0 or generation != _generation or _mode != "replace" or index < 0 or index >= _state.gear.size():
		return
	var item := _selected
	close()
	chosen.emit(item, index)

func _back() -> void:
	if not _open or _arming > 0.0 or _mode != "replace":
		return
	_mode = "offers"
	_selected = null
	_render()

func _decline() -> void:
	if not _open or _arming > 0.0:
		return
	close()
	declined.emit()
