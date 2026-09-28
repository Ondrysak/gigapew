extends Control

const CROSS_DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const HIT_DIRECTIONS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

var aiming := true
var terminal := false
var _shot := 0.0
var _hit := 0.0
var _damage := 0.0
var _kill := 0.0
var _lethal_hit := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_shot() -> void:
	_shot = 1.0

func show_hit(killed: bool) -> void:
	_hit = 0.32 if killed else 0.16
	_lethal_hit = killed
	if killed:
		_kill = 0.8

func show_damage() -> void:
	_damage = 1.0

func _process(delta: float) -> void:
	_shot = move_toward(_shot, 0.0, delta * 8.0)
	_hit = maxf(0.0, _hit - delta)
	_damage = move_toward(_damage, 0.0, delta * 2.8)
	_kill = maxf(0.0, _kill - delta)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	if _damage > 0.0:
		for i in 10:
			var inset := float(i * 8)
			var tint := Color(1.0, 0.13, 0.25, _damage * 0.12 * (1.0 - float(i) / 10.0))
			draw_rect(Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), tint, false, 16.0)
	if not terminal and aiming:
		var gap := 6.0 + _shot * 4.0
		var ink := Color(0.58, 1.0, 0.95, 0.9)
		for direction in CROSS_DIRECTIONS:
			draw_line(center + direction * gap, center + direction * (gap + 5.0), Color(0.01, 0.02, 0.03, 0.7), 4.0)
			draw_line(center + direction * gap, center + direction * (gap + 5.0), ink, 2.0)
		draw_circle(center, 1.5, Color.WHITE)
	if _hit > 0.0 and not terminal:
		var color := Color(1.0, 0.68, 0.25) if _lethal_hit else Color.WHITE
		color.a = minf(1.0, _hit * 12.0)
		for direction in HIT_DIRECTIONS:
			draw_line(center + direction * 7.0, center + direction * 12.0, color, 2.0, true)
	if _kill > 0.0 and not terminal:
		var color := Color(1.0, 0.68, 0.25, minf(1.0, _kill * 3.0))
		_centered_text("TARGET DOWN", center.y + 52.0, 17, color)
	if not aiming and not terminal:
		_centered_text("CLICK TO CAPTURE AIM", center.y + 70.0, 17, Color(0.65, 0.85, 0.9))

func _centered_text(text: String, y: float, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
