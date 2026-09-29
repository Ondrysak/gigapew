class_name ClassSelectScreen
extends MenuScreen

## Operator select: roster cards plus a detail panel (loadout, ability picker,
## stat profile) and one action button that deploys or unlocks the selection.
## The picker previews the class's abilities; an unlocked one is equipped by
## pressing its tile, a locked one is bought with the ability action button.

signal deploy_requested(definition: ClassDefinition)

@export var card_scene: PackedScene
@export var card_row: Container
@export var currency_bar: CurrencyBar
@export var accent_bar: ColorRect
@export var name_label: Label
@export var tagline_label: Label
@export var description_label: Label
@export var weapons_label: Label
@export var ability_option_scene: PackedScene
@export var ability_option_row: Container
@export var ability_name_label: Label
@export var ability_description_label: Label
@export var ability_action_button: Button
@export var stats_label: RichTextLabel
@export var action_button: Button
@export var status_label: Label
@export var good_color := Color(0.4, 1, 0.7)
@export var bad_color := Color(1, 0.45, 0.4)

var _cards: Array[ClassCard] = []
var _options: Array[AbilityOption] = []
var _selected: ClassDefinition
## Ability shown in the detail panel (defaults to the equipped one).
var _preview: PackedScene
## PackedScene -> {name, description, cooldown, accent}; read once per scene.
var _abilities: Dictionary = {}

func _ready() -> void:
	super()
	var most_options := 0
	for definition in Profile.roster.classes:
		var card := card_scene.instantiate() as ClassCard
		card_row.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(definition))
		card.focus_entered.connect(_select.bind(definition))
		_cards.append(card)
		most_options = maxi(most_options, definition.ability_options().size())
	for index in range(most_options):
		var option := ability_option_scene.instantiate() as AbilityOption
		ability_option_row.add_child(option)
		option.pressed.connect(_on_option_pressed.bind(index))
		option.focus_entered.connect(_on_option_focused.bind(index))
		_options.append(option)
	action_button.pressed.connect(_on_action_pressed)
	ability_action_button.pressed.connect(_on_ability_action_pressed)

func refresh() -> void:
	if _selected == null:
		_selected = Profile.selected_class()
		_preview = Profile.equipped_ability_scene(_selected)
	status_label.text = ""
	_redraw()
	var index := Profile.roster.classes.find(_selected)
	default_focus = _cards[index] if index >= 0 and index < _cards.size() else action_button

func _on_card_pressed(definition: ClassDefinition) -> void:
	_select(definition)
	action_button.grab_focus()

func _select(definition: ClassDefinition) -> void:
	if _selected == definition:
		return
	_selected = definition
	_preview = Profile.equipped_ability_scene(definition)
	status_label.text = ""
	if Profile.is_class_unlocked(definition):
		Profile.selected_class_id = definition.id
	_redraw()

func _on_option_focused(index: int) -> void:
	if _selected == null:
		return
	var options := _selected.ability_options()
	if index >= options.size() or _preview == options[index]:
		return
	_preview = options[index]
	status_label.text = ""
	_redraw()

func _on_option_pressed(index: int) -> void:
	if _selected == null:
		return
	var options := _selected.ability_options()
	if index >= options.size():
		return
	_preview = options[index]
	status_label.text = ""
	if Profile.is_class_unlocked(_selected) and Profile.is_ability_unlocked(_selected, _preview):
		Profile.equip_ability(_selected, _preview)
	elif not Profile.is_ability_unlocked(_selected, _preview):
		ability_action_button.grab_focus()
	_redraw()

func _on_ability_action_pressed() -> void:
	if _selected == null or _preview == null:
		return
	var info := _ability_info(_preview)
	if Profile.is_ability_unlocked(_selected, _preview):
		if Profile.equip_ability(_selected, _preview):
			status_label.text = "%s equipped." % info.name
	elif Profile.unlock_ability(_selected, _preview):
		Profile.equip_ability(_selected, _preview)
		status_label.text = "%s unlocked and equipped." % info.name
	else:
		var missing := _selected.ability_cost(_preview) - Profile.currency(_selected.ability_unlock_currency)
		status_label.text = "Need %d more %s." % [missing, currency_bar.label_for(_selected.ability_unlock_currency).to_lower()]
	_redraw()

func _on_action_pressed() -> void:
	if _selected == null:
		return
	if Profile.is_class_unlocked(_selected):
		Profile.selected_class_id = _selected.id
		deploy_requested.emit(_selected)
		return
	if Profile.unlock_class(_selected):
		Profile.selected_class_id = _selected.id
		status_label.text = "%s unlocked." % _selected.display_name
	else:
		var missing := _selected.unlock_cost - Profile.currency(_selected.unlock_currency)
		status_label.text = "Need %d more %s." % [missing, currency_bar.label_for(_selected.unlock_currency).to_lower()]
	_redraw()

func _redraw() -> void:
	for index in range(_cards.size()):
		var entry := Profile.roster.classes[index]
		var entry_unlocked := Profile.is_class_unlocked(entry)
		_cards[index].show_class(entry, entry_unlocked, entry == _selected and entry_unlocked, _cost_text(entry))
	if _selected == null:
		return
	var accent := _selected.accent_color
	var unlocked := Profile.is_class_unlocked(_selected)
	accent_bar.color = accent
	name_label.text = _selected.display_name.to_upper()
	name_label.add_theme_color_override(&"font_color", accent.lightened(0.35))
	tagline_label.text = _selected.tagline.to_upper()
	tagline_label.add_theme_color_override(&"font_color", accent)
	description_label.text = _selected.description
	weapons_label.text = _loadout_text(_selected)
	_redraw_abilities(unlocked)
	var stats := StatText.bbcode(_selected, good_color, bad_color)
	stats_label.text = stats if not stats.is_empty() else "Standard-issue baseline."
	if unlocked:
		action_button.text = "DEPLOY AS %s" % _selected.display_name.to_upper()
		action_button.disabled = false
	else:
		action_button.text = "UNLOCK  ·  %s" % _cost_text(_selected)
		action_button.disabled = not Profile.can_afford_class(_selected)
		if action_button.disabled and status_label.text.is_empty():
			status_label.text = "Mine rare %s deposits and destroy bosses to earn more." \
					% currency_bar.label_for(_selected.unlock_currency).to_lower()

func _redraw_abilities(class_unlocked: bool) -> void:
	var options := _selected.ability_options()
	var equipped := Profile.equipped_ability_scene(_selected)
	if _preview == null or not options.has(_preview):
		_preview = equipped
	for index in range(_options.size()):
		var tile := _options[index]
		tile.visible = index < options.size()
		if not tile.visible:
			continue
		var scene := options[index]
		var info := _ability_info(scene)
		var owned := Profile.is_ability_unlocked(_selected, scene)
		var state := "EQUIPPED" if scene == equipped else "OWNED"
		if not owned:
			var currency := currency_bar.label_for(_selected.ability_unlock_currency).trim_prefix("VOID ")
			state = "LOCKED · %d %s" % [_selected.ability_cost(scene), currency]
		tile.show_option(scene, info.name, info.accent, owned, scene == equipped, scene == _preview, state)
	ability_option_row.visible = options.size() > 1
	var shown := _ability_info(_preview)
	ability_name_label.text = String(shown.name).to_upper()
	ability_name_label.add_theme_color_override(&"font_color", Color(shown.accent).lightened(0.35))
	if float(shown.cooldown) > 0.0:
		ability_description_label.text = "%d s recharge  ·  %s" % [roundi(shown.cooldown), shown.description]
	else:
		ability_description_label.text = shown.description
	var preview_owned := _preview != null and Profile.is_ability_unlocked(_selected, _preview)
	ability_action_button.visible = options.size() > 1
	if _preview == equipped:
		ability_action_button.text = "EQUIPPED"
		ability_action_button.disabled = true
	elif preview_owned:
		ability_action_button.text = "EQUIP"
		ability_action_button.disabled = not class_unlocked
	else:
		ability_action_button.text = "UNLOCK  ·  %s" % _ability_cost_text(_preview)
		ability_action_button.disabled = not class_unlocked or not Profile.can_afford_ability(_selected, _preview)

func _cost_text(definition: ClassDefinition) -> String:
	return "%d %s" % [definition.unlock_cost, currency_bar.label_for(definition.unlock_currency)]

func _ability_cost_text(scene: PackedScene) -> String:
	return "%d %s" % [_selected.ability_cost(scene), currency_bar.label_for(_selected.ability_unlock_currency)]

func _loadout_text(definition: ClassDefinition) -> String:
	var names := PackedStringArray()
	for weapon in definition.starting_weapons:
		if weapon != null:
			names.append(weapon.display_name)
	var text := "  ·  ".join(names) if not names.is_empty() else "No main guns"
	var extras := PackedStringArray()
	for upgrade in definition.starting_upgrades:
		if upgrade != null:
			extras.append(upgrade.display_name)
	if not extras.is_empty():
		text += "\n+ " + "  ·  ".join(extras)
	return text

func _ability_info(scene: PackedScene) -> Dictionary:
	if _abilities.has(scene):
		return _abilities[scene]
	var info := {"name": "No ability", "description": "This operator has no active ability.", "cooldown": 0.0, "accent": Color(0.6, 1, 1)}
	if scene != null:
		var node := scene.instantiate()
		var ability := node as ActiveAbility
		if ability != null:
			info = {"name": ability.display_name, "description": ability.description, "cooldown": ability.base_cooldown, "accent": ability.accent_color}
		node.free()
	_abilities[scene] = info
	return info
