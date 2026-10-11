class_name GearHUD
extends Control

signal inspect_requested

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const TEXT := Color(0.87, 0.81, 0.67)
const DIM := Color(0.65, 0.60, 0.49)

var slot_buttons: Array[Button] = []
var _icons: Array[TextureRect] = []
var _names: Array[Label] = []
var _status: Label
var _state: RunState
var _player: ArenaPlayer

func _ready() -> void:
	theme = MENU_THEME
	custom_minimum_size = Vector2(420, 66)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	add_child(rows)
	var slots := HBoxContainer.new()
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_theme_constant_override(&"separation", 4)
	rows.add_child(slots)
	for index in range(4):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_inspect)
		slots.add_child(button)
		slot_buttons.append(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override(&"margin_left", 4)
		margin.add_theme_constant_override(&"margin_right", 4)
		button.add_child(margin)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 4)
		margin.add_child(row)
		var icon := GameIcons.rect(null, 24)
		row.add_child(icon)
		_icons.append(icon)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		label.add_theme_font_size_override(&"font_size", 12)
		label.add_theme_color_override(&"font_color", TEXT)
		row.add_child(label)
		_names.append(label)
	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override(&"font_size", 12)
	_status.add_theme_color_override(&"font_color", DIM)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.clip_text = true
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_status)
	StreetWear.apply_tree(self)
	_refresh()

func setup(state: RunState) -> void:
	if _state != null and _state.gear_changed.is_connected(_refresh):
		_state.gear_changed.disconnect(_refresh)
	_state = state
	if _state != null:
		_state.gear_changed.connect(_refresh)
	if is_node_ready():
		_refresh()

func bind_player(player: ArenaPlayer) -> void:
	_player = player

func _process(_delta: float) -> void:
	if _status == null:
		return
	var feedback := ""
	if is_instance_valid(_player):
		var effects := _player.gear_effects
		if is_instance_valid(effects):
			feedback = effects.status_text()
	var next := "G · výbava" if feedback.is_empty() else "G · výbava  |  %s" % feedback
	if _status.text != next:
		_status.text = next
		_status.tooltip_text = next

func _refresh() -> void:
	if not is_node_ready():
		return
	for index in range(4):
		var item: GearDefinition = _state.gear[index] if _state != null and index < _state.gear.size() else null
		_icons[index].texture = item.icon if item != null else null
		_names[index].text = item.display_name if item != null else "%d · —" % (index + 1)
		_names[index].add_theme_color_override(&"font_color", item.accent_color if item != null else DIM)
		slot_buttons[index].tooltip_text = "%s%s\n%s\n„%s“\nG · prohlédnout celou výbavu" % [item.display_name, " · PROKLETÉ" if item.cursed else "", item.description, item.quote] if item != null else "Volné místo %d / 4\nNajdi skrýš nebo poraz elitu.\nG · prohlédnout výbavu" % (index + 1)

func _inspect() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		inspect_requested.emit()
