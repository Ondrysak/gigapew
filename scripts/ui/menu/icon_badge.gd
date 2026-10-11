extends PanelContainer

## Framed square badge around a crisp pixel icon (nearest filter, integer
## scale of the 16 px art). Menu cards built in code use it; the scene-built
## cards (class_card, meta_card, ability_option) mirror the same frame.

var icon_rect: TextureRect

var _style: StyleBoxFlat

func _init(texture: Texture2D = null, pixels := 48, border := Color(0.46, 0.38, 0.26)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.07, 0.06, 0.045, 0.98)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(0)
	_style.set_content_margin_all(4)
	_style.border_color = border.lerp(Color(0.46, 0.38, 0.26), 0.65)
	add_theme_stylebox_override(&"panel", _style)
	icon_rect = GameIcons.rect(texture, pixels)
	add_child(icon_rect)

func _ready() -> void:
	StreetWear.apply(self)

func show_icon(texture: Texture2D, border: Color) -> void:
	icon_rect.texture = texture
	_style.border_color = border.lerp(Color(0.46, 0.38, 0.26), 0.65)
