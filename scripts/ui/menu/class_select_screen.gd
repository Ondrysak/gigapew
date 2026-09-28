class_name ClassSelectScreen
extends MenuScreen

## Operator select: roster cards plus a detail panel (loadout, ability, stat
## profile) and one action button that deploys or unlocks the selection.

signal deploy_requested(definition: ClassDefinition)

@export var card_scene: PackedScene
@export var card_row: Container
@export var currency_bar: CurrencyBar
@export var accent_bar: ColorRect
@export var name_label: Label
@export var tagline_label: Label
@export var description_label: Label
@export var weapons_label: Label
@export var ability_name_label: Label
@export var ability_description_label: Label
@export var stats_label: RichTextLabel
@export var action_button: Button
@export var status_label: Label
@export var good_color := Color(0.4, 1, 0.7)
@export var bad_color := Color(1, 0.45, 0.4)

var _cards: Array[ClassCard] = []
var _selected: ClassDefinition
## ClassDefinition -> {name, description, cooldown}; read once per class.
var _abilities: Dictionary = {}

func _ready() -> void:
	super()
	for definition in Profile.roster.classes:
		var card := card_scene.instantiate() as ClassCard
		card_row.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(definition))
		card.focus_entered.connect(_select.bind(definition))
		_cards.append(card)
	action_button.pressed.connect(_on_action_pressed)

func refresh() -> void:
	if _selected == null:
		_selected = Profile.selected_class()
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
	status_label.text = ""
	if Profile.is_class_unlocked(definition):
		Profile.selected_class_id = definition.id
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
	var ability := _ability_info(_selected)
	if float(ability.cooldown) > 0.0:
		ability_name_label.text = "%s  ·  %d s RECHARGE" % [String(ability.name).to_upper(), roundi(ability.cooldown)]
	else:
		ability_name_label.text = String(ability.name).to_upper()
	ability_description_label.text = ability.description
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

func _cost_text(definition: ClassDefinition) -> String:
	return "%d %s" % [definition.unlock_cost, currency_bar.label_for(definition.unlock_currency)]

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

func _ability_info(definition: ClassDefinition) -> Dictionary:
	if _abilities.has(definition):
		return _abilities[definition]
	var info := {"name": "No ability", "description": "This operator has no active ability.", "cooldown": 0.0}
	if definition.ability_scene != null:
		var node := definition.ability_scene.instantiate()
		var ability := node as ActiveAbility
		if ability != null:
			info = {"name": ability.display_name, "description": ability.description, "cooldown": ability.base_cooldown}
		node.free()
	_abilities[definition] = info
	return info
