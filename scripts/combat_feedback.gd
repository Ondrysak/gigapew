class_name CombatFeedback
extends Control

const CROSS_DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const HIT_DIRECTIONS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

@export var reticle_color := Color(0.9, 0.84, 0.69, 0.95)
@export var kill_color := Color(0.86, 0.62, 0.32)
@export var damage_color := Color(0.86, 0.2, 0.16)
@export var confirmation_text := "ROZPRÁŠENO"
@export var combo_color := Color(0.84, 0.68, 0.38)

var aiming := true
var terminal := false
var _shot := 0.0
var _hit := 0.0
var _damage := 0.0
var _kill := 0.0
var _lethal_hit := false
var _combo_hits := 0
var _combo_time := 0.0
var _chain_pulse := 0.0
var _combo_text := ""
var _bloom := 0.0
var _hit_punch := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func reset() -> void:
	terminal = false
	aiming = true
	_shot = 0.0
	_hit = 0.0
	_damage = 0.0
	_kill = 0.0
	_lethal_hit = false
	_combo_hits = 0
	_combo_time = 0.0
	_bloom = 0.0
	_hit_punch = 0.0
	_chain_pulse = 0.0
	_combo_text = ""

func show_shot() -> void:
	_shot = 1.0

func show_hit(killed: bool) -> void:
	_hit = 0.32 if killed else 0.16
	_hit_punch = 1.0
	_lethal_hit = killed
	if killed:
		_kill = 0.8

func show_damage() -> void:
	_damage = 1.0

func show_combo(hits: int, bonus: float) -> void:
	_combo_hits = hits
	_combo_text = "SÉRIE %d   +%d%% DALŠÍ RÁNA" % [hits, roundi(bonus * 100.0)] if bonus > 0.0 else "SÉRIE %d" % hits
	_combo_time = 2.5 if hits > 0 else 0.0
	if hits == 3 or hits == 6 or hits == 10:
		_chain_pulse = 1.0

func _process(delta: float) -> void:
	_shot = move_toward(_shot, 0.0, delta * 8.0)
	_hit_punch = move_toward(_hit_punch, 0.0, delta * 9.0)
	# Opens fast with the shooter's bloom, settles back smoothly.
	var bloom := _aim_bloom()
	_bloom = bloom if bloom > _bloom else lerpf(_bloom, bloom, 1.0 - exp(-14.0 * delta))
	_hit = maxf(0.0, _hit - delta)
	_damage = move_toward(_damage, 0.0, delta * 2.8)
	_kill = maxf(0.0, _kill - delta)
	_combo_time = maxf(0.0, _combo_time - delta)
	_chain_pulse = maxf(0.0, _chain_pulse - delta * 3.0)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	if _damage > 0.0:
		for i in 10:
			var inset := float(i * 8)
			var tint := Color(damage_color, _damage * 0.12 * (1.0 - float(i) / 10.0))
			draw_rect(Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), tint, false, 16.0)
	if not terminal and aiming:
		var gap := 6.0 + _bloom * 18.0 + _shot * 3.0
		var arm := 5.0 + _bloom * 3.0
		var ink := reticle_color
		for direction in CROSS_DIRECTIONS:
			draw_line(center + direction * gap, center + direction * (gap + arm), Color(0.01, 0.02, 0.03, 0.7), 4.0)
			draw_line(center + direction * gap, center + direction * (gap + arm), ink, 2.0)
		draw_circle(center, 1.5, Color.WHITE)
	if _hit > 0.0 and not terminal:
		var color := kill_color if _lethal_hit else Color.WHITE
		color.a = minf(1.0, _hit * 12.0)
		# Markers snap out wide and thick, then settle onto the reticle.
		var punch := _hit_punch * _hit_punch * (1.6 if _lethal_hit else 1.0)
		var inner := 7.0 + _bloom * 10.0 + punch * 6.0
		var width := 2.0 + punch * 1.5
		for direction in HIT_DIRECTIONS:
			draw_line(center + direction * inner, center + direction * (inner + 5.0 + punch * 4.0), color, width, true)
	if _kill > 0.0 and not terminal:
		var color := Color(kill_color, minf(1.0, _kill * 3.0))
		_centered_text(confirmation_text, center.y + 52.0, 17, color)
	if _combo_hits > 0 and _combo_time > 0.0 and not terminal:
		var color := combo_color if _combo_hits >= 3 else reticle_color
		_centered_text(_combo_text, center.y + 86.0 - _chain_pulse * 4.0, 17 + int(_chain_pulse * 3.0), color)
		var width := 140.0 * (_combo_time / 2.5)
		draw_line(center + Vector2(-70, 99), center + Vector2(70, 99), Color(0.16, 0.13, 0.09, 0.7), 3.0)
		draw_line(center + Vector2(-70, 99), center + Vector2(-70 + width, 99), color, 3.0)
	if not aiming and not terminal:
		_centered_text("KLIKNI PRO MÍŘENÍ", center.y + 70.0, 17, Color(0.83, 0.76, 0.62))

func _centered_text(text: String, y: float, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## The active camera's ArenaPlayer drives the bloom; none (menus) means a tight reticle.
func _aim_bloom() -> float:
	var camera := get_viewport().get_camera_3d()
	var player := camera.owner as ArenaPlayer if camera != null else null
	return player.aim_bloom if player != null else 0.0
