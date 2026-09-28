class_name LevelUpCard
extends Button

## One offer on the level-up screen. Layout lives in level_up_card.tscn; the
## script only writes text/colors into the referenced controls.

@export var accent_bar: ColorRect
@export var key_label: Label
@export var kind_label: Label
@export var name_label: Label
@export var level_label: Label
@export var description_label: Label
@export var icon_rect: TextureRect

var _normal: StyleBoxFlat
var _hover: StyleBoxFlat

func _ready() -> void:
	# Own copies so each card can carry its offer's accent border.
	_normal = get_theme_stylebox(&"normal").duplicate() as StyleBoxFlat
	_hover = get_theme_stylebox(&"hover").duplicate() as StyleBoxFlat
	add_theme_stylebox_override(&"normal", _normal)
	add_theme_stylebox_override(&"hover", _hover)
	add_theme_stylebox_override(&"pressed", _hover)

func show_offer(upgrade: UpgradeDefinition, current_level: int, key: int) -> void:
	var accent := upgrade.accent_color
	accent_bar.color = accent
	_normal.border_color = accent.darkened(0.35)
	_hover.border_color = accent.lightened(0.3)
	key_label.text = "[%d]" % key
	if upgrade.kind == UpgradeDefinition.Kind.WEAPON:
		kind_label.text = "AUTO WEAPON"
	elif upgrade.repeatable:
		kind_label.text = "SUPPLY"
	else:
		kind_label.text = "SYSTEM"
	kind_label.add_theme_color_override(&"font_color", accent)
	name_label.text = upgrade.display_name.to_upper()
	name_label.add_theme_color_override(&"font_color", accent.lightened(0.35))
	if upgrade.repeatable:
		level_label.text = "INSTANT"
	elif current_level == 0:
		level_label.text = "NEW   LV 1 / %d" % upgrade.max_level
	else:
		level_label.text = "LV %d  →  %d / %d" % [current_level, current_level + 1, upgrade.max_level]
	description_label.text = upgrade.describe(current_level + 1)
	icon_rect.texture = upgrade.icon
	icon_rect.visible = upgrade.icon != null
