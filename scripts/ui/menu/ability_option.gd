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
	StreetWear.apply_tree(self)

func show_option(ability_scene: PackedScene, ability_name: String, icon: Texture2D, accent: Color, previewed: bool, status: String) -> void:
	scene = ability_scene
	accent = accent.lerp(Color(0.52, 0.43, 0.3), 0.7)
	accent_bar.color = accent
	icon_rect.texture = icon
	icon_rect.visible = icon != null
	name_label.text = ability_name
	name_label.add_theme_color_override(&"font_color", Color(0.88, 0.82, 0.68))
	status_label.text = status
	status_label.add_theme_color_override(&"font_color", Color(0.67, 0.61, 0.5))
	_normal.border_color = accent if previewed else Color(0.28, 0.25, 0.2)
	_normal.set_border_width_all(2 if previewed else 1)
	_hover.border_color = Color(0.65, 0.54, 0.36)
