class_name AbilityOption
extends Button

## A class kit skill tile. Clicking changes only the mechanics preview.

@export var accent_bar: ColorRect
@export var icon_rect: TextureRect
@export var name_label: Label
@export var status_label: Label

var scene: PackedScene

var _normal: StyleBoxFlat
var _hover: StyleBoxFlat

func _ready() -> void:
	# Own copies so each tile carries its ability accent.
	_normal = get_theme_stylebox(&"normal").duplicate() as StyleBoxFlat
	_hover = get_theme_stylebox(&"hover").duplicate() as StyleBoxFlat
	add_theme_stylebox_override(&"normal", _normal)
	add_theme_stylebox_override(&"hover", _hover)
	add_theme_stylebox_override(&"pressed", _hover)

func show_option(ability_scene: PackedScene, ability_name: String, icon: Texture2D, accent: Color, previewed: bool, status: String) -> void:
	scene = ability_scene
	accent_bar.color = accent
	icon_rect.texture = icon
	icon_rect.visible = icon != null
	name_label.text = ability_name
	name_label.add_theme_color_override(&"font_color", accent.lightened(0.35))
	status_label.text = status
	status_label.add_theme_color_override(&"font_color", Color(0.5, 0.66, 0.72))
	_normal.border_color = accent if previewed else accent.darkened(0.35)
	_normal.set_border_width_all(3 if previewed else 2)
	_hover.border_color = accent.lightened(0.3)
