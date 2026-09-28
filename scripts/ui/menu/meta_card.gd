class_name MetaCard
extends PanelContainer

## One permanent upgrade in the Armory: level pips, current/next effect and
## a buy button. Layout lives in meta_card.tscn.

signal purchase_requested(definition: MetaUpgradeDefinition)

@export var accent_bar: ColorRect
@export var icon_rect: TextureRect
@export var name_label: Label
@export var level_label: Label
@export var pips: HBoxContainer
@export var description_label: Label
@export var effect_label: Label
@export var buy_button: Button
@export var pip_size := Vector2(26, 8)
@export var pip_empty_color := Color(0.08, 0.16, 0.19, 1)

var definition: MetaUpgradeDefinition

func _ready() -> void:
	buy_button.pressed.connect(func() -> void: purchase_requested.emit(definition))

## Redraws for `level` owned; `price_text` is empty when maxed.
func show_upgrade(upgrade: MetaUpgradeDefinition, level: int, price_text: String, affordable: bool) -> void:
	definition = upgrade
	var accent := upgrade.accent_color
	var maximum := upgrade.max_level()
	accent_bar.color = accent
	icon_rect.texture = upgrade.icon
	icon_rect.visible = upgrade.icon != null
	name_label.text = upgrade.display_name.to_upper()
	name_label.add_theme_color_override(&"font_color", accent.lightened(0.3))
	level_label.text = "LV %d / %d" % [level, maximum]
	description_label.text = upgrade.description
	while pips.get_child_count() < maximum:
		var pip := ColorRect.new()
		pip.custom_minimum_size = pip_size
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	for index in range(pips.get_child_count()):
		var pip := pips.get_child(index) as ColorRect
		pip.visible = index < maximum
		pip.color = accent if index < level else pip_empty_color
	var now := StatText.summary(upgrade, level) if level > 0 else "—"
	if level >= maximum:
		effect_label.text = "NOW  %s" % now
		buy_button.text = "MAXED"
		buy_button.disabled = true
	else:
		effect_label.text = "NOW  %s\nNEXT  %s" % [now, StatText.summary(upgrade, level + 1)]
		buy_button.text = "UPGRADE  ·  %s" % price_text
		buy_button.disabled = not affordable
