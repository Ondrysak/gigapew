class_name RunSetupScreen
extends MenuScreen

## Run setup after operator select: level, preset, tuning and difficulty tier.
## Every change is saved to Profile so the next visit opens where you left it.

signal start_requested

const TEXT := Color(0.87, 0.81, 0.67)
const DIM := Color(0.65, 0.60, 0.49)
const AMBER := Color(0.72, 0.55, 0.32)
## key, label, hint. Multipliers use RunConfig.RANGES.
const SLIDERS: Array[Array] = [
	["fights", "BITKY", "Kolik bitek musíš vyčistit."],
	["density", "HUSTOTA", "Počet nepřátel v každé bitce."],
	["crowd", "STROP DAVU", "Kolik těl smí být naživu naráz."],
	["health", "ZDRAVÍ NEPŘÁTEL", "Kolik toho snesou."],
	["damage", "PŘÍCHOZÍ POŠKOZENÍ", "Všechno, co schytáš."],
	["pace", "TEMPO NÁSTUPU", "Jak rychle dorážejí další skupiny."],
	["difficulty", "OBTÍŽNOST", "Stupeň: +15 % zdraví, +10 % ran, +8 % hustoty, +25 % odměn."],
]

var config: RunConfig
var _levels: Array[StageDefinition] = RunConfig.levels()
var _level_buttons: Array[Button] = []
var _preset_buttons: Dictionary = {}
var _sliders: Dictionary = {}
var _specialists: CheckButton
var _blurb: Label
var _summary: Label
var _start: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 48.0
	scroll.offset_top = 30.0
	scroll.offset_right = -48.0
	scroll.offset_bottom = -28.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 7)
	scroll.add_child(rows)
	var title := _label("NASTAVENÍ VÝPRAVY", 28, TEXT)
	title.theme_type_variation = &"HeaderLabel"
	rows.add_child(title)
	rows.add_child(_label("KAM", 16, AMBER))
	var level_row := _row()
	rows.add_child(level_row)
	var level_group := ButtonGroup.new()
	for index in _levels.size():
		var stage := _levels[index]
		var button := _toggle("%s\n%s" % [stage.display_name.to_upper(), stage.subtitle], level_group)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_level.bind(index))
		level_row.add_child(button)
		_level_buttons.append(button)
	rows.add_child(_label("PŘEDVOLBY", 16, AMBER))
	var preset_row := _row()
	rows.add_child(preset_row)
	var preset_group := ButtonGroup.new()
	for id: StringName in RunConfig.PRESETS:
		var button := _toggle(String(RunConfig.PRESETS[id].name).to_upper(), preset_group)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_preset.bind(id))
		preset_row.add_child(button)
		_preset_buttons[id] = button
	_blurb = _label("", 14, DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_blurb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 28)
	grid.add_theme_constant_override(&"v_separation", 2)
	rows.add_child(grid)
	for entry in SLIDERS:
		grid.add_child(_slider_row(String(entry[0]), String(entry[1]), String(entry[2])))
	_specialists = CheckButton.new()
	_specialists.text = "SPECIALISTÉ (bombař, Tarzan, polejvač, flaškař, vyhazovač, hecíř)"
	_specialists.toggled.connect(_on_specialists)
	rows.add_child(_specialists)
	_summary = _label("", 15, TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_summary)
	var footer := _row()
	rows.add_child(footer)
	var back := Button.new()
	back.text = "ZPĚT"
	footer.add_child(back)
	back_button = back
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_start = Button.new()
	_start.text = "VYRAZIT DO ULIC"
	_start.pressed.connect(_on_start)
	footer.add_child(_start)
	default_focus = _start
	super()

func refresh() -> void:
	config = Profile.load_run_config()
	_sync()

func _slider_row(key: String, caption: String, hint: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 0)
	var head := _row()
	box.add_child(head)
	var name_label := _label(caption, 15, TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value := _label("", 15, AMBER)
	head.add_child(value)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(320, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match key:
		"fights":
			slider.min_value = RunConfig.FIGHTS_RANGE.x
			slider.max_value = RunConfig.FIGHTS_RANGE.y
			slider.step = 1.0
		"difficulty":
			slider.min_value = 0
			slider.max_value = RunConfig.MAX_DIFFICULTY
			slider.step = 1.0
		_:
			var bounds: Array = RunConfig.RANGES[key]
			slider.min_value = float(bounds[0])
			slider.max_value = float(bounds[1])
			slider.step = float(bounds[2])
	slider.value_changed.connect(_on_slider.bind(key))
	slider.tooltip_text = hint
	box.add_child(slider)
	box.add_child(_label(hint, 11, DIM))
	_sliders[key] = {"slider": slider, "value": value}
	return box

func _on_level(index: int) -> void:
	config.select_level(_levels[index])
	_commit()

func _on_preset(id: StringName) -> void:
	config.apply_preset(id, _levels[config.level_index(_levels)])
	_commit()

func _on_slider(value: float, key: String) -> void:
	config.set_value(key, value)
	_commit()

func _on_specialists(enabled: bool) -> void:
	config.set_value("specialists", enabled)
	_commit()

func _on_start() -> void:
	Profile.set_run_config(config)
	start_requested.emit()

func _commit() -> void:
	Profile.set_run_config(config)
	_sync()

func _sync() -> void:
	var stage := _levels[config.level_index(_levels)]
	for index in _level_buttons.size():
		_level_buttons[index].set_pressed_no_signal(_levels[index] == stage)
	for id: StringName in _preset_buttons:
		(_preset_buttons[id] as Button).set_pressed_no_signal(id == config.preset)
	_blurb.text = String(RunConfig.PRESETS[config.preset].blurb) if RunConfig.PRESETS.has(config.preset) \
			else "Vlastní nastavení. Předvolba ho celé přepíše."
	for key: String in _sliders:
		var entry: Dictionary = _sliders[key]
		var value: Variant = config.get(key)
		(entry.slider as Range).set_value_no_signal(float(value))
		(entry.value as Label).text = _format(key, value)
	_specialists.set_pressed_no_signal(config.specialists)
	var built := config.build_stage(stage)
	_summary.text = "%s · %s\nZhruba %d těl v %d bitkách · naráz nejvýš %d · odměny ×%.2f · trvalé nákupy z bazaru: %d stupňů" % [
		stage.display_name.to_upper(), config.label(), config.estimated_enemies(stage), built.arena_encounters,
		built.schedule.max_alive, config.reward_scale(), Profile.shop_build_ranks()]

func _format(key: String, value: Variant) -> String:
	match key:
		"fights":
			return str(int(value))
		"difficulty":
			return "%d" % int(value)
	return "×%.2f" % float(value)

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	return row

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label

func _toggle(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	return button
