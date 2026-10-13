class_name RouteChoiceScreen
extends CanvasLayer

## Pausing and committing a route belong to ArenaGame. Choices use source ids.
signal chosen(id: StringName)
signal weapons_requested

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
var choice_buttons: Array[Button] = []
var loadout_button: Button
var _root: Control
var _title: Label
var _choices: VBoxContainer
var _open := false
var _arming := 0.0
var _generation := 0
var _ids: Array[StringName] = []

func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = MENU_THEME
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.03, 0.025, 0.93)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(edge, 40)
	for edge in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(edge, 28)
	_root.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 12)
	margin.add_child(rows)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 28)
	rows.add_child(_title)
	var hint := Label.new()
	hint.text = "Vyber trasu. Dojdi na místo a rozjeď další fight."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	rows.add_child(scroll)
	_choices = VBoxContainer.new()
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.add_theme_constant_override(&"separation", 12)
	scroll.add_child(_choices)
	loadout_button = Button.new()
	loadout_button.text = "ZMĚNIT DVOJICI ZBRANÍ"
	loadout_button.pressed.connect(_edit_pair)
	rows.add_child(loadout_button)
	var footer := Label.new()
	footer.text = "1–3 trasa · šipky / Tab výběr · Enter potvrzení"
	rows.add_child(footer)
	StreetWear.apply_tree(_root)
	hide()

func present(choices: Array[Dictionary], origin: Vector3, next_set: int, total_sets: int) -> void:
	close()
	_title.text = "KAM DÁL? · FIGHT %d / %d" % [next_set, total_sets]
	for child in _choices.get_children():
		child.free()
	choice_buttons.clear()
	_ids.clear()
	_generation += 1
	for choice in choices:
		var index := _ids.size()
		_ids.append(choice.id)
		var button := Button.new()
		button.custom_minimum_size.y = 88.0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%d · %s · %dm\n%s" % [index + 1, choice.name.to_upper(), roundi(origin.distance_to(choice.position)), _tactic(choice.kind)]
		button.pressed.connect(_choose.bind(index, _generation))
		_choices.add_child(button)
		choice_buttons.append(button)
	StreetWear.apply_tree(_choices)
	_open = true
	_arming = 0.25
	show()
	if not choice_buttons.is_empty():
		choice_buttons[0].grab_focus()

func _tactic(kind: StringName) -> String:
	match kind:
		&"hospoda": return "Oběhni výčep · sudy do davu · hlídej oba vchody"
		&"herna": return "Automaty lámou lajny · střídej zbraně · kryt není bezpečí"
		&"nonstop": return "Z ulice přes pult · krátké lajny · drž si únikovou trasu"
		&"station", &"metro": return "Sloupy a nástupiště · odrážej střely · měň výšku"
	return "Dva vstupy · drž pohyb · poslední živý ukončí fight"

func close() -> void:
	_open = false
	_generation += 1
	hide()

func _process(delta: float) -> void:
	if _open:
		_arming = maxf(0.0, _arming - delta)

func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code >= KEY_1 and code <= KEY_3:
		get_viewport().set_input_as_handled()
		_choose(code - KEY_1, _generation)

func _choose(index: int, generation: int) -> void:
	if not _open or _arming > 0.0 or generation != _generation or index < 0 or index >= _ids.size():
		return
	chosen.emit(_ids[index])

func _edit_pair() -> void:
	if _open and _arming <= 0.0:
		weapons_requested.emit()
