class_name AbilityOption
extends Button

## One tile of the class-select ability picker. Layout lives in
## ability_option.tscn; the script writes text/colors and the equipped,
## previewed and locked looks.

@export var accent_bar: ColorRect
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

## `status` is the short state line (EQUIPPED / OWNED / cost).
func show_option(ability_scene: PackedScene, ability_name: String, accent: Color, unlocked: bool, equipped: bool, previewed: bool, status: String) -> void:
	scene = ability_scene
	var shown := accent if unlocked else accent.darkened(0.55)
	accent_bar.color = shown
	name_label.text = ability_name
	name_label.add_theme_color_override(&"font_color", accent.lightened(0.35) if unlocked else Color(0.5, 0.56, 0.6))
	status_label.text = status
	if equipped:
		status_label.add_theme_color_override(&"font_color", accent.lightened(0.2))
	elif unlocked:
		status_label.add_theme_color_override(&"font_color", Color(0.5, 0.66, 0.72))
	else:
		status_label.add_theme_color_override(&"font_color", Color(1, 0.62, 0.3))
	_normal.border_color = accent if previewed else shown.darkened(0.35)
	_normal.set_border_width_all(3 if previewed else 2)
	_normal.shadow_color = Color(accent, 0.28 if equipped else 0.0)
	_normal.shadow_size = 10 if equipped else 0
	_hover.border_color = accent.lightened(0.3)
