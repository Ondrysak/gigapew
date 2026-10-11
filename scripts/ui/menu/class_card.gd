class_name ClassCard
extends Button

## Compact roster tile for one class. Layout lives in class_card.tscn; the
## script writes text/colors, the framed class icon and the selected/locked
## look (dimmed icon plus a lock glyph beside the unlock price).

@export var accent_bar: ColorRect
@export var badge: PanelContainer
@export var icon_rect: TextureRect
@export var lock_icon: TextureRect
@export var name_label: Label
@export var tagline_label: Label
@export var status_label: Label

var definition: ClassDefinition

var _normal: StyleBoxFlat
var _hover: StyleBoxFlat
var _badge: StyleBoxFlat

func _ready() -> void:
	# Own copies so each card carries its class accent.
	_normal = get_theme_stylebox(&"normal").duplicate() as StyleBoxFlat
	_hover = get_theme_stylebox(&"hover").duplicate() as StyleBoxFlat
	add_theme_stylebox_override(&"normal", _normal)
	add_theme_stylebox_override(&"hover", _hover)
	add_theme_stylebox_override(&"pressed", _hover)
	_badge = badge.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	badge.add_theme_stylebox_override(&"panel", _badge)
	StreetWear.apply_tree(self)

func show_class(class_definition: ClassDefinition, unlocked: bool, selected: bool, cost_text: String) -> void:
	definition = class_definition
	var accent := class_definition.accent_color
	var shown := accent if unlocked else accent.darkened(0.55)
	accent_bar.color = shown
	icon_rect.texture = class_definition.icon
	badge.visible = class_definition.icon != null
	icon_rect.modulate = Color.WHITE if unlocked else Color(0.45, 0.41, 0.34)
	_badge.border_color = accent if selected else shown.darkened(0.2)
	lock_icon.visible = not unlocked
	name_label.text = class_definition.display_name.to_upper()
	name_label.add_theme_color_override(&"font_color", Color(0.88, 0.82, 0.68) if unlocked else Color(0.6, 0.56, 0.48))
	tagline_label.text = class_definition.tagline
	if unlocked:
		status_label.text = "VYBRÁNO" if selected else "V PARTĚ"
		status_label.add_theme_color_override(&"font_color", Color(0.75, 0.69, 0.52))
	else:
		status_label.text = "MIMO PARTU  ·  %s" % cost_text
		status_label.add_theme_color_override(&"font_color", Color(0.78, 0.62, 0.4))
	_normal.border_color = accent if selected else shown.darkened(0.35)
	_normal.set_border_width_all(2 if selected else 1)
	_normal.shadow_color = Color.TRANSPARENT
	_normal.shadow_size = 0
	_hover.border_color = Color(0.65, 0.54, 0.36)
