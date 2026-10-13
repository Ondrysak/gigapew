class_name WeaponDraftScreen
extends CanvasLayer

## Two-gun loadout picker shown at run start and during breaks. Both slots are
## previewed with the run's shared ranks. The consumer owns pause, mouse capture
## and RunState.equip_pair; this layer only selects and emits a distinct pair.
signal confirmed(first: WeaponDefinition, second: WeaponDefinition)
signal cancelled

const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const TEXT := Color(0.87, 0.81, 0.67)
const DIM := Color(0.65, 0.60, 0.49)
const AMBER := Color(0.72, 0.55, 0.32)
const GOOD := Color(0.66, 0.69, 0.46)
const BAD := Color(0.78, 0.43, 0.34)
## Comparison rows: label, RoundShop.weapon_stats key ("" = sustained output).
const ROWS: Array[Array] = [["RÁNA", "DMG"], ["TEMPO", "RATE"], ["KUSŮ", "PELLETS"], ["VÝBUCH", "SPLASH"], ["PRŮRAZ", "PIERCE"], ["ŽIVEL", "TYPE"], ["ZA SEKUNDU", ""]]
const SLOT_NAMES: Array[String] = ["A · V RUCE", "B · DRUHÁ (Q)"]

var pending_first: WeaponDefinition
var pending_second: WeaponDefinition
## 0 edits slot A (active), 1 slot B (partner).
var editing_slot := 0
var allow_cancel := false
var source_buttons: Array[Button] = []
var slot_buttons: Array[Button] = []
var confirm_button: Button
var cancel_button: Button
var input_delay := 0.25
var _state: RunState
var _sources: Array[WeaponDefinition] = []
var _was_first: WeaponDefinition
var _was_second: WeaponDefinition
var _title: Label
var _hint: Label
var _grid: GridContainer
var _slots: Array[Dictionary] = []
var _cells: Array[Array] = []
var _open := false
var _arming := 0.0

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()

func is_open() -> bool:
	return _open

## Prefills the current pair (or the loadout plus the first distinct source);
## never equips. `allow_cancel` is for optional break replacements only.
func open(run_state: RunState, p_allow_cancel: bool = false) -> void:
	_state = run_state
	allow_cancel = p_allow_cancel
	_sources.clear()
	for source in run_state.available_weapons:
		if source != null and not _sources.has(source):
			_sources.append(source)
	_was_first = run_state.primary.source if run_state.primary != null else null
	_was_second = run_state.secondary_primary_source
	pending_first = _was_first if _sources.has(_was_first) else null
	pending_second = _was_second if _sources.has(_was_second) and _was_second != pending_first else null
	for source in _sources:
		if pending_first == null and source != pending_second:
			pending_first = source
		elif pending_second == null and source != pending_first:
			pending_second = source
	editing_slot = 0 if allow_cancel else 1
	_title.text = "VÝMĚNA ZBRANÍ · ZDARMA" if allow_cancel else "VYBER SI DVĚ ZBRANĚ"
	_rebuild_sources()
	_open = true
	_arming = input_delay
	show()
	_refresh()
	var focus := source_buttons[_sources.find(pending_second)] if not source_buttons.is_empty() and _sources.has(pending_second) else confirm_button
	focus.grab_focus()

func close() -> void:
	_open = false
	hide()
	for slot in range(1, 6):
		var action := StringName("ability_%d" % slot)
		if InputMap.has_action(action):
			Input.action_release(action)

func select_slot(slot: int) -> void:
	if not _open or slot < 0 or slot > 1:
		return
	editing_slot = slot
	_refresh()

## Puts `source` into the edited slot; picking the other slot's gun swaps them,
## so the pending pair can never hold a duplicate.
func choose(source: WeaponDefinition) -> bool:
	if not _open or source == null or not _sources.has(source):
		return false
	var other := pending_second if editing_slot == 0 else pending_first
	var current := pending_first if editing_slot == 0 else pending_second
	if source == other:
		other = current
	if editing_slot == 0:
		pending_first = source
		pending_second = other
		editing_slot = 1
	else:
		pending_second = source
		pending_first = other
	_refresh()
	return true

## Replaces the whole pending pair at once; refuses invalid pairs unchanged.
func select_pair(first: WeaponDefinition, second: WeaponDefinition) -> bool:
	if not _open or not _state.can_equip_pair(first, second) or not _sources.has(first) or not _sources.has(second):
		return false
	pending_first = first
	pending_second = second
	_refresh()
	return true

func can_confirm() -> bool:
	return _open and _state != null and _state.can_equip_pair(pending_first, pending_second)

func confirm() -> bool:
	if not can_confirm():
		return false
	var first := pending_first
	var second := pending_second
	close()
	confirmed.emit(first, second)
	return true

func cancel() -> bool:
	if not _open or not allow_cancel:
		return false
	close()
	cancelled.emit()
	return true

func _process(delta: float) -> void:
	if _open:
		_arming = maxf(0.0, _arming - delta)

func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if code == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if allow_cancel:
			_on_cancel()
		else:
			confirm_button.grab_focus()
	elif code >= KEY_1 and code <= KEY_9:
		get_viewport().set_input_as_handled()
		_on_source(int(code - KEY_1))
	elif code == KEY_A or code == KEY_B:
		get_viewport().set_input_as_handled()
		_on_slot(0 if code == KEY_A else 1)

func _on_source(index: int) -> void:
	if not _open:
		return
	if _arming > 0.0 or index < 0 or index >= _sources.size() or not choose(_sources[index]):
		_refresh()

func _on_slot(slot: int) -> void:
	if not _open:
		return
	if _arming <= 0.0:
		select_slot(slot)
	else:
		_refresh()

func _on_confirm() -> void:
	if _arming <= 0.0:
		confirm()

func _on_cancel() -> void:
	if _arming <= 0.0:
		cancel()

func _refresh() -> void:
	var first := _state.preview_weapon(pending_first)
	var second := _state.preview_weapon(pending_second)
	var previews: Array[WeaponDefinition] = [first, second]
	var picks: Array[WeaponDefinition] = [pending_first, pending_second]
	var was: Array[WeaponDefinition] = [_was_first, _was_second]
	for slot in 2:
		var card: Dictionary = _slots[slot]
		var effective := previews[slot]
		var editing := slot == editing_slot
		slot_buttons[slot].set_pressed_no_signal(editing)
		card.heading.text = SLOT_NAMES[slot] + ("  ◀ VYBÍRÁŠ" if editing else "")
		card.heading.add_theme_color_override(&"font_color", AMBER if editing else DIM)
		card.icon.texture = effective.icon if effective != null else null
		card.name.text = effective.display_name.to_upper() if effective != null else "—"
		card.description.text = effective.description if effective != null else "Vyber zbraň klávesou 1–%d." % _sources.size()
		var changed := allow_cancel and was[slot] != null and picks[slot] != was[slot]
		card.change.text = "MÍSTO: %s" % was[slot].display_name if changed else ("BEZE ZMĚNY" if allow_cancel else "")
		card.change.add_theme_color_override(&"font_color", AMBER if changed else DIM)
	var stats: Array[Dictionary] = [RoundShop.weapon_stats(first, _state.projectile_bonus), RoundShop.weapon_stats(second, _state.projectile_bonus)]
	for row in ROWS.size():
		var key := String(ROWS[row][1])
		var values := PackedFloat32Array([_value(first, key), _value(second, key)])
		for slot in 2:
			var cell: Label = _cells[row][slot]
			if previews[slot] == null:
				cell.text = "—"
			elif key.is_empty():
				cell.text = "%d" % roundi(values[slot])
			else:
				cell.text = String(stats[slot].get(key, "—"))
			var compared := key != "TYPE" and previews[0] != null and previews[1] != null
			var better := compared and values[slot] > values[1 - slot] + 0.001
			var worse := compared and values[slot] + 0.001 < values[1 - slot]
			cell.add_theme_color_override(&"font_color", GOOD if better else (BAD if worse else TEXT))
	for index in source_buttons.size():
		var source := _sources[index]
		var button := source_buttons[index]
		var tag := " [A]" if source == pending_first else (" [B]" if source == pending_second else "")
		var effective := _state.preview_weapon(source)
		button.text = "%d · %s%s\n%s · %d/s" % [index + 1, source.display_name, tag, DamageType.label(effective.damage_type).to_upper(), roundi(_value(effective, ""))]
		button.set_pressed_no_signal(not tag.is_empty())
	_hint.text = "Úpravy jsou sdílené: obě zbraně ukazují stejné stupně %s. Výměna je zdarma." % _ranks_text() if allow_cancel \
			else "Dvě různé zbraně do ruky. Q přepíná. Obě ukazují sdílené stupně %s." % _ranks_text()
	cancel_button.visible = allow_cancel
	var unchanged := pending_first == _was_first and pending_second == _was_second
	confirm_button.disabled = not can_confirm()
	confirm_button.text = ("NECHAT · ENTER" if unchanged and allow_cancel else "VZÍT TYHLE DVĚ · ENTER")

func _ranks_text() -> String:
	if _state.primary == null or _state.primary.upgrade_levels.is_empty():
		return "(zatím žádné)"
	var parts := PackedStringArray()
	for id: StringName in _state.primary.upgrade_levels:
		if RoundShop.CATALOG.has(id):
			parts.append("%s S%d" % [RoundShopScreen.STAT_LABELS.get(String(RoundShop.CATALOG[id].stat), String(id)), int(_state.primary.upgrade_levels[id])])
	return "(%s)" % ", ".join(parts)

func _value(definition: WeaponDefinition, key: String) -> float:
	if definition == null:
		return 0.0
	var pellets := float(clampi(definition.pellet_count + _state.projectile_bonus, 1, WeaponBuild.MAX_PROJECTILES))
	var rate := 1.0 / maxf(definition.fire_interval, 0.001)
	match key:
		"DMG":
			return float(definition.damage)
		"RATE":
			return rate
		"PELLETS":
			return pellets
		"SPLASH":
			return definition.explosion_radius
		"PIERCE":
			return float(definition.pierce)
		"TYPE":
			return 0.0
	return definition.damage * pellets * rate

func _build() -> void:
	var root := Control.new()
	root.theme = MENU_THEME
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.045, 0.035, 0.025, 0.98)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 22)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	root.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	margin.add_child(rows)
	_title = _label("VYBER SI DVĚ ZBRANĚ", 26, AMBER)
	rows.add_child(_title)
	_hint = _label("", 13, DIM)
	rows.add_child(_hint)
	var compare := HBoxContainer.new()
	compare.add_theme_constant_override(&"separation", 10)
	rows.add_child(compare)
	compare.add_child(_slot_card(0))
	compare.add_child(_table())
	compare.add_child(_slot_card(1))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	rows.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(_grid)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 12)
	rows.add_child(footer)
	var help := _label("1–9 zbraň do slotu · A/B slot · šipky/Tab pohyb · Enter potvrdit · Esc zpět", 13, DIM)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	cancel_button = _button("ZPĚT · ESC")
	cancel_button.pressed.connect(_on_cancel)
	footer.add_child(cancel_button)
	confirm_button = _button("VZÍT TYHLE DVĚ · ENTER")
	confirm_button.pressed.connect(_on_confirm)
	footer.add_child(confirm_button)
	StreetWear.apply_tree(root)

func _slot_card(slot: int) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_slot.bind(slot))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	button.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	margin.add_child(rows)
	var heading := _label("", 14, AMBER)
	rows.add_child(heading)
	var title := HBoxContainer.new()
	rows.add_child(title)
	var icon := GameIcons.rect(null, 36)
	title.add_child(icon)
	var name_label := _label("", 18, TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	var description := _label("", 12, DIM)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(description)
	var change := _label("", 12, DIM)
	rows.add_child(change)
	_ignore_mouse(margin)
	rows.minimum_size_changed.connect(_fit_card.bind(button, rows))
	_fit_card(button, rows)
	slot_buttons.append(button)
	_slots.append({"heading": heading, "icon": icon, "name": name_label, "description": description, "change": change})
	return button

func _fit_card(button: Button, rows: VBoxContainer) -> void:
	# Wrapped descriptions grow the card instead of painting past its border.
	button.custom_minimum_size.y = maxf(150.0, rows.get_combined_minimum_size().y + 20.0)

func _table() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 250
	var table := GridContainer.new()
	table.columns = 3
	table.add_theme_constant_override(&"h_separation", 14)
	table.add_theme_constant_override(&"v_separation", 1)
	panel.add_child(table)
	for text in ["", "A", "B"]:
		var header := _label(text, 13, AMBER)
		header.autowrap_mode = TextServer.AUTOWRAP_OFF
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		table.add_child(header)
	for row in ROWS:
		var name_label := _label(String(row[0]), 13, DIM)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		table.add_child(name_label)
		var cells: Array[Label] = []
		for slot in 2:
			var cell := _label("—", 13, TEXT)
			cell.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			table.add_child(cell)
			cells.append(cell)
		_cells.append(cells)
	return panel

func _rebuild_sources() -> void:
	source_buttons.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for index in _sources.size():
		var button := _button("")
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		button.icon = _sources[index].icon
		button.expand_icon = false
		button.add_theme_constant_override(&"icon_max_width", 24)
		button.tooltip_text = _sources[index].description
		button.pressed.connect(_on_source.bind(index))
		_grid.add_child(button)
		source_buttons.append(button)
	StreetWear.apply_tree(_grid)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", 13)
	return button

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
