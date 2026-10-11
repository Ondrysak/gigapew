class_name ClassSelectScreen
extends MenuScreen

## Operator select: one primary firearm and a five-skill kit.
## Skill tiles preview their mechanics; the entire kit unlocks with the class.

signal deploy_requested(definition: ClassDefinition)

const ICON_BADGE := preload("res://scripts/ui/menu/icon_badge.gd")

@export var card_scene: PackedScene
@export var card_row: Container
@export var currency_bar: CurrencyBar
@export var accent_bar: ColorRect
@export var class_badge: PanelContainer
@export var class_icon: TextureRect
@export var name_label: Label
@export var tagline_label: Label
@export var description_label: Label
## Shows the current primary firearm.
@export var loadout_row: HBoxContainer
@export var extras_label: Label
@export var ability_option_scene: PackedScene
@export var ability_option_row: Container
@export var ability_icon: TextureRect
@export var ability_name_label: Label
@export var ability_description_label: Label
@export var stats_label: RichTextLabel
@export var action_button: Button
@export var status_label: Label
@export var good_color := Color(0.66, 0.7, 0.44)
@export var bad_color := Color(0.8, 0.46, 0.36)

var _cards: Array[ClassCard] = []
var _options: Array[AbilityOption] = []
var _selected: ClassDefinition
## Ability shown in the detail panel.
var _preview: PackedScene
## PackedScene -> {name, description, cooldown, accent, icon}; read once per scene.
var _abilities: Dictionary = {}
var _class_badge_style: StyleBoxFlat

func _ready() -> void:
	super()
	var most_options := 0
	for definition in Profile.roster.classes:
		var card := card_scene.instantiate() as ClassCard
		card_row.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(definition))
		card.focus_entered.connect(_select.bind(definition))
		_cards.append(card)
		most_options = maxi(most_options, definition.ability_scenes.size())
	for index in range(most_options):
		var option := ability_option_scene.instantiate() as AbilityOption
		ability_option_row.add_child(option)
		option.pressed.connect(_on_option_pressed.bind(index))
		option.focus_entered.connect(_on_option_focused.bind(index))
		_options.append(option)
	action_button.pressed.connect(_on_action_pressed)
	StreetWear.apply_tree(self)

func refresh() -> void:
	if _selected == null:
		_selected = Profile.selected_class()
		_preview = _selected.ability_scenes[0]
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
	_preview = definition.ability_scenes[0]
	status_label.text = ""
	if Profile.is_class_unlocked(definition):
		Profile.selected_class_id = definition.id
	_redraw()

func _on_option_focused(index: int) -> void:
	if _selected == null:
		return
	var options := _selected.ability_scenes
	if index >= options.size() or _preview == options[index]:
		return
	_preview = options[index]
	status_label.text = ""
	_redraw()

func _on_option_pressed(index: int) -> void:
	_on_option_focused(index)

func _on_action_pressed() -> void:
	if _selected == null:
		return
	if Profile.is_class_unlocked(_selected):
		Profile.selected_class_id = _selected.id
		deploy_requested.emit(_selected)
		return
	if Profile.unlock_class(_selected):
		Profile.selected_class_id = _selected.id
		status_label.text = "%s je v partě." % _selected.display_name
	else:
		var missing := _selected.unlock_cost - Profile.currency(_selected.unlock_currency)
		status_label.text = "Ještě chybí %d %s." % [missing, currency_bar.label_for(_selected.unlock_currency).to_lower()]
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
	class_icon.texture = _selected.icon
	class_badge.visible = _selected.icon != null
	class_icon.modulate = Color.WHITE if unlocked else Color(0.45, 0.41, 0.34)
	if _class_badge_style == null:
		_class_badge_style = class_badge.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
		class_badge.add_theme_stylebox_override(&"panel", _class_badge_style)
	_class_badge_style.border_color = accent if unlocked else accent.darkened(0.45)
	name_label.text = _selected.display_name.to_upper()
	name_label.add_theme_color_override(&"font_color", Color(0.88, 0.82, 0.68))
	tagline_label.text = _selected.tagline.to_upper()
	tagline_label.add_theme_color_override(&"font_color", Color(0.75, 0.68, 0.53))
	description_label.text = _selected.description
	_redraw_loadout(_selected)
	_redraw_abilities()
	var stats := StatText.bbcode(_selected, good_color, bad_color)
	stats_label.text = stats if not stats.is_empty() else "Základní parametry beze změn."
	if unlocked:
		action_button.text = "VYRAZIT DO ULIC"
		action_button.disabled = false
	else:
		action_button.text = "PŘIBRAT DO PARTY  ·  %s" % _cost_text(_selected)
		action_button.disabled = not Profile.can_afford_class(_selected)
		if action_button.disabled and status_label.text.is_empty():
			status_label.text = "Páč přihrádky automatů a plň kontrakty pro další kořist (%s)." \
					% currency_bar.label_for(_selected.unlock_currency)

func _redraw_abilities() -> void:
	var options := _selected.ability_scenes
	if _preview == null or not options.has(_preview):
		_preview = options[0]
	for index in range(_options.size()):
		var tile := _options[index]
		tile.visible = index < options.size()
		if not tile.visible:
			continue
		var scene := options[index]
		var info := _ability_info(scene)
		tile.show_option(scene, info.name, info.icon, info.accent, scene == _preview, "KLÁVESA %d · SKILL" % (index + 1))
		tile.tooltip_text = "%s\n%s" % [info.name, info.description]
	ability_option_row.show()
	var shown := _ability_info(_preview)
	ability_name_label.text = String(shown.name).to_upper()
	ability_icon.texture = shown.icon
	ability_icon.visible = shown.icon != null
	ability_name_label.add_theme_color_override(&"font_color", Color(0.88, 0.82, 0.68))
	ability_description_label.text = "%.1fs prodleva · %s\nKaždý trik vylepšuješ zvlášť. S radami do začátku se další triky odemykají podle úrovně; bez rad máš všech pět hned." % [shown.cooldown, shown.description]

func _cost_text(definition: ClassDefinition) -> String:
	return "%d %s" % [definition.unlock_cost, currency_bar.label_for(definition.unlock_currency)]


## One primary chip plus starting upgrades.
func _redraw_loadout(definition: ClassDefinition) -> void:
	if loadout_row.get_child_count() == 0:
		loadout_row.add_child(_loadout_chip())
	var weapon := Profile.primary_loadout(definition)
	var chip := loadout_row.get_child(0)
	var badge = chip.get_child(0)
	badge.visible = weapon != null and weapon.icon != null
	if badge.visible:
		badge.show_icon(weapon.icon, definition.accent_color.darkened(0.3))
	(chip.get_child(1) as Label).text = weapon.display_name if weapon != null else "Bez hlavní zbraně"
	var extras := PackedStringArray()
	for upgrade in definition.starting_upgrades:
		if upgrade != null:
			extras.append(upgrade.display_name)
	for upgrade in Profile.starting_craft_upgrades():
		extras.append(upgrade.display_name)
	extras_label.visible = not extras.is_empty()
	extras_label.text = "+ " + "  ·  ".join(extras)

func _loadout_chip() -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override(&"separation", 8)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(ICON_BADGE.new(null, 32))
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(1, 0.8, 0.5))
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(label)
	return chip

func _ability_info(scene: PackedScene) -> Dictionary:
	if _abilities.has(scene):
		return _abilities[scene]
	var info := {"name": "Bez skillu", "description": "Tahle postava nemá aktivní skill.", "cooldown": 0.0, "accent": Color(0.65, 0.5, 0.29), "icon": GameIcons.lookup(&"hud", &"ability")}
	if scene != null:
		var node := scene.instantiate()
		var ability := node as ActiveAbility
		if ability != null:
			info = {"name": ability.display_name, "description": ability.description, "cooldown": ability.base_cooldown, "accent": ability.accent_color, "icon": ability.icon if ability.icon != null else info.icon}
		node.free()
	_abilities[scene] = info
	return info
