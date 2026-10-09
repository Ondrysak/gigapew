extends PanelContainer

## Framed square badge around a crisp pixel icon (nearest filter, integer
## scale of the 16 px art). Menu cards built in code use it; the scene-built
## cards (class_card, meta_card, ability_option) mirror the same frame.

var icon_rect: TextureRect

var _style: StyleBoxFlat

func _init(texture: Texture2D = null, pixels := 48, border := Color(0.1, 0.4, 0.45)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.01, 0.025, 0.04, 0.95)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(4)
	_style.set_content_margin_all(4)
	_style.border_color = border
	add_theme_stylebox_override(&"panel", _style)
	icon_rect = GameIcons.rect(texture, pixels)
	add_child(icon_rect)

func show_icon(texture: Texture2D, border: Color) -> void:
	icon_rect.texture = texture
	_style.border_color = border
