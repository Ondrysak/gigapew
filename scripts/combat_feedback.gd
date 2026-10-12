class_name CombatFeedback
extends Control

const CROSS_DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const HIT_DIRECTIONS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
const DISPLAY_FONT := preload("res://assets/fonts/rave_display.tres")
const BODY_FONT := preload("res://assets/fonts/rave_body.tres")

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
var _combo_fraction := 0.0
var _chain_pulse := 0.0
var _combo_text := ""
var _combo_bonus_text := ""
var _combo_width := 0.0
var _bonus_width := 0.0
var _combo_font_size := 42
var _combo_heat := 0.0
var _ink_time := 0.0
var _bloom := 0.0
var _hit_punch := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_measure_combo)
	_measure_combo()

func reset() -> void:
	terminal = false
	aiming = true
	_shot = 0.0
	_hit = 0.0
	_damage = 0.0
	_kill = 0.0
	_lethal_hit = false
	_combo_hits = 0
	_combo_fraction = 0.0
	_bloom = 0.0
	_hit_punch = 0.0
	_chain_pulse = 0.0
	_combo_text = ""
	_combo_bonus_text = ""
	_combo_heat = 0.0
	_ink_time = 0.0

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
	if hits > _combo_hits:
		_chain_pulse = maxf(_chain_pulse, 1.0 if hits == 3 or hits == 6 or hits == 10 or hits % 25 == 0 else 0.3)
	_combo_hits = hits
	_combo_heat = clampf(float(hits) / float(ArenaPlayer.COMBO_PRESSURE_FULL), 0.0, 1.0)
	_combo_text = "SÉRIE %d" % hits
	_combo_bonus_text = "+%d%% DALŠÍ RÁNA" % roundi(bonus * 100.0) if bonus > 0.0 else "DRŽ RYTMUS"
	_measure_combo()

func _process(delta: float) -> void:
	if not get_tree().paused:
		_ink_time += delta
	_shot = move_toward(_shot, 0.0, delta * 8.0)
	_hit_punch = move_toward(_hit_punch, 0.0, delta * 9.0)
	# Opens fast with the shooter's bloom, settles back smoothly.
	var player := _aim_player()
	var bloom := player.aim_bloom if player != null else 0.0
	_bloom = bloom if bloom > _bloom else lerpf(_bloom, bloom, 1.0 - exp(-14.0 * delta))
	_hit = maxf(0.0, _hit - delta)
	_damage = move_toward(_damage, 0.0, delta * 2.8)
	_kill = maxf(0.0, _kill - delta)
	_combo_fraction = player.combo_fraction if player != null and _combo_hits > 0 else 0.0
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
		_centered_text(confirmation_text, center.y + 46.0, 22, color, DISPLAY_FONT)
	if _combo_hits > 0 and _combo_fraction > 0.0 and not terminal:
		_draw_combo(center)
	if not aiming and not terminal:
		_centered_text("KLIKNI PRO MÍŘENÍ", center.y + 70.0, 17, Color(0.83, 0.76, 0.62))

func _measure_combo() -> void:
	_combo_font_size = 28 if size.y < 540.0 else (34 if size.y < 660.0 else 42)
	_combo_width = DISPLAY_FONT.get_string_size(_combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size).x
	_bonus_width = BODY_FONT.get_string_size(_combo_bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

func _draw_combo(center: Vector2) -> void:
	var baseline := center.y + minf(108.0, maxf(65.0, size.y * 0.5 - 190.0))
	var scale := (1.0 + _chain_pulse * 0.09) * minf(1.0, (size.x - 48.0) / maxf(1.0, _combo_width))
	var lean := sin(_ink_time * 0.8) * _combo_heat * 0.025
	var tear := (1.0 + _combo_heat * 2.2) * (0.65 + _chain_pulse * 0.35)
	var ink := combo_color.lerp(Color(1.0, 0.29, 0.58), _combo_heat * 0.65) if _combo_hits >= 3 else reticle_color
	draw_set_transform(Vector2(center.x, baseline - _chain_pulse * 3.0), lean, Vector2.ONE * scale)
	var origin := Vector2(-_combo_width * 0.5, 0.0)
	# Displaced print plates, not rapidly flashing or scrambled unreadable digits.
	draw_string_outline(DISPLAY_FONT, origin, _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, 5, Color(0.025, 0.015, 0.025, 0.95))
	draw_string(DISPLAY_FONT, origin + Vector2(-tear, -0.7), _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, Color(0.2, 0.95, 0.94, 0.55))
	draw_string(DISPLAY_FONT, origin + Vector2(tear, 0.7), _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, Color(1.0, 0.22, 0.6, 0.55))
	draw_string(DISPLAY_FONT, origin, _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, ink)
	draw_set_transform(Vector2.ZERO)
	var bonus_at := Vector2(center.x - _bonus_width * 0.5, baseline + 23.0)
	draw_string_outline(BODY_FONT, bonus_at, _combo_bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0.02, 0.015, 0.02, 0.95))
	draw_string(BODY_FONT, bonus_at, _combo_bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.65))
	var y := baseline + 35.0
	draw_line(Vector2(center.x - 88.0, y), Vector2(center.x + 88.0, y), Color(0.08, 0.035, 0.07, 0.9), 5.0)
	draw_line(Vector2(center.x - 88.0, y), Vector2(center.x - 88.0 + 176.0 * _combo_fraction, y), ink, 3.0)

func _centered_text(text: String, y: float, font_size: int, color: Color, font: Font = BODY_FONT) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2((size.x - width) * 0.5, y)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.02, 0.015, 0.02, color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## The active player's gameplay timer drives the counter, including pause and decay.
func _aim_player() -> ArenaPlayer:
	var camera := get_viewport().get_camera_3d()
	return camera.owner as ArenaPlayer if camera != null else null
