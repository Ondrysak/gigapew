class_name CombatFeedback
extends Control

const CROSS_DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const HIT_DIRECTIONS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
const DISPLAY_FONT := preload("res://assets/fonts/rave_display.tres")
const BODY_FONT := preload("res://assets/fonts/rave_body.tres")
const PRINT_SHARDS := ["S", "T", "Y", "L", "E", "×"]
const AIM_HINT := "KLIKNI PRO MÍŘENÍ"

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
var _measured_combo_text := ""
var _measured_bonus_text := ""
var _measured_font_size := 0
var _combo_bonus_percent := -1
var _combo_tier := 0
var _tier_burst := 0.0
var _beat_phase := -1.0
var _beat_travel := 0.0
var _dance_strength := 0.65
var _rhythm_eligible := false
var _rhythm_confirmation := 0.0
var _rhythm_punch := 0.0
var _rhythm_shot_percent := -1
var _rhythm_shot_max := false
var _rhythm_shot_text := ""
var _rhythm_shot_width := 0.0
var _rhythm_prompt_text := ""
var _rhythm_ready_text := ""
var _rhythm_prompt_width := 0.0
var _rhythm_ready_width := 0.0
var _kill_width := 0.0
var _aim_hint_width := 0.0
var _combo_ascent := 0.0
var _combo_descent := 0.0
var _shard_widths := PackedFloat32Array()
var _bloom := 0.0
var _hit_punch := 0.0
var _drop_charge := 0.0
var _drop_ready := false
var _drop_percent := -1

var _action_left := 0.0
var _action_text := ""
var _action_width := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_measure_combo)
	Profile.changed.connect(_on_profile_changed)
	_on_profile_changed()
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
	_combo_bonus_percent = -1
	_combo_tier = 0
	_tier_burst = 0.0
	_beat_phase = -1.0
	_beat_travel = 0.0
	_rhythm_eligible = false
	_rhythm_confirmation = 0.0
	_rhythm_punch = 0.0
	_rhythm_shot_text = ""
	_rhythm_shot_percent = -1
	_rhythm_shot_max = false
	_drop_charge = 0.0
	_drop_ready = false
	_drop_percent = -1
	_action_left = 0.0
	_action_text = ""

func show_shot() -> void:
	_shot = 1.0
	var player := _aim_player()
	var bonus := player.last_rhythm_bonus if player != null else 0.0
	_rhythm_confirmation = 0.0
	_rhythm_punch = 0.0
	if bonus > 0.0:
		var percent := roundi(bonus * 100.0)
		var full := is_equal_approx(bonus, ArenaPlayer.RHYTHM_MAX_BONUS)
		var payoff := "DROP! ×10 • " + player.drop_effect_label()
		if percent != _rhythm_shot_percent or full != _rhythm_shot_max or payoff != _rhythm_shot_text:
			_rhythm_shot_percent = percent
			_rhythm_shot_max = full
			_rhythm_shot_text = payoff
			_rhythm_shot_width = DISPLAY_FONT.get_string_size(_rhythm_shot_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_rhythm_confirmation = 1.0
		_rhythm_punch = bonus / ArenaPlayer.RHYTHM_MAX_BONUS

func show_action(label: String) -> void:
	if terminal or label.is_empty():
		return
	if label != _action_text:
		_action_text = label
		_action_width = DISPLAY_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_action_left = 1.1

func show_hit(killed: bool) -> void:
	_hit = 0.32 if killed else 0.16
	_hit_punch = 1.0
	_lethal_hit = killed
	if killed:
		_kill = 0.8

func show_damage() -> void:
	_damage = 1.0

func show_combo(hits: int, bonus: float) -> void:
	var next_tier := mini(3, floori(float(maxi(0, hits)) / 100.0))
	if hits >= 100 and hits > _combo_hits and floori(float(hits) / 100.0) > floori(float(_combo_hits) / 100.0):
		_tier_burst = 1.0
	_combo_tier = next_tier
	if hits > _combo_hits:
		_chain_pulse = maxf(_chain_pulse, 1.0 if hits == 3 or hits == 6 or hits == 10 or hits % 25 == 0 else 0.3)
	var text_changed := hits != _combo_hits
	if text_changed:
		_combo_text = "STYLE %d" % hits if hits > 0 else ""
	var bonus_percent := roundi(bonus * 100.0)
	if bonus_percent != _combo_bonus_percent:
		_combo_bonus_percent = bonus_percent
		_combo_bonus_text = "+%d%% DAMAGE • KILLY + STYLE" % bonus_percent if bonus > 0.0 else "KILLY + STYLE"
		text_changed = true
	_combo_hits = hits
	_combo_heat = clampf(float(hits) / float(ArenaPlayer.COMBO_PRESSURE_FULL), 0.0, 1.0)
	if hits <= 0:
		_combo_fraction = 0.0
		_chain_pulse = 0.0
		_tier_burst = 0.0
		_beat_travel = 0.0
	if text_changed:
		_measure_combo()

func _process(delta: float) -> void:
	# Music can continue underneath pause menus; this HUD must not follow it.
	if get_tree().paused:
		return
	_shot = move_toward(_shot, 0.0, delta * 8.0)
	_hit_punch = move_toward(_hit_punch, 0.0, delta * 9.0)
	# Opens fast with the shooter's bloom, settles back smoothly.
	var player := _aim_player()
	_update_beat()
	_rhythm_eligible = player != null and player.active and player.rhythm_eligible() and _beat_phase >= 0.0
	_drop_charge = player.drop_charge if player != null else 0.0
	_drop_ready = player != null and player.drop_ready
	var percent := floori(_drop_charge * 100.0)
	var prompt := "DROP %d%% • KILLY + STYLE" % percent
	if _drop_ready:
		prompt = "DROP NABITÝ • KLIK NA BEAT" if _rhythm_eligible else "DROP NABITÝ • TĚŽKÁ ZBRAŇ + HUDBA"
	if prompt != _rhythm_prompt_text:
		_drop_percent = percent
		_rhythm_prompt_text = prompt
		_rhythm_ready_text = "TEĎ! KLIK → DROP ×10" if _drop_ready and _rhythm_eligible else prompt
		_rhythm_prompt_width = BODY_FONT.get_string_size(_rhythm_prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_rhythm_ready_width = BODY_FONT.get_string_size(_rhythm_ready_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var bloom := player.aim_bloom if player != null else 0.0
	_bloom = bloom if bloom > _bloom else lerpf(_bloom, bloom, 1.0 - exp(-14.0 * delta))
	_hit = maxf(0.0, _hit - delta)
	_damage = move_toward(_damage, 0.0, delta * 2.8)
	_kill = maxf(0.0, _kill - delta)
	_combo_fraction = player.combo_fraction if player != null and _combo_hits > 0 else 0.0
	_chain_pulse = maxf(0.0, _chain_pulse - delta * 3.0)
	_tier_burst = maxf(0.0, _tier_burst - delta * 1.8)
	_rhythm_confirmation = maxf(0.0, _rhythm_confirmation - delta)
	_action_left = maxf(0.0, _action_left - delta)
	_rhythm_punch = maxf(0.0, _rhythm_punch - delta * 5.0)
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
		if _rhythm_punch > 0.0 and _dance_strength > 0.0:
			var radius := 18.0 + (1.0 - _rhythm_punch) * 22.0
			var power_ink := Color(0.2, 0.95, 0.94, _rhythm_punch * _dance_strength * 0.8)
			for direction in HIT_DIRECTIONS:
				draw_line(center + direction * radius, center + direction * (radius + 8.0 * _rhythm_punch), power_ink, 2.0, true)
	if _hit > 0.0 and not terminal:
		var color := kill_color if _lethal_hit else Color.WHITE
		color.a = minf(1.0, _hit * 12.0)
		# Markers snap out wide and thick, then settle onto the reticle.
		var punch := _hit_punch * _hit_punch * (1.6 if _lethal_hit else 1.0)
		var inner := 7.0 + _bloom * 10.0 + punch * 6.0
		var width := 2.0 + punch * 1.5
		for direction in HIT_DIRECTIONS:
			draw_line(center + direction * inner, center + direction * (inner + 5.0 + punch * 4.0), color, width, true)
	if _kill > 0.0 and not terminal and _action_left <= 0.0:
		var color := Color(kill_color, minf(1.0, _kill * 3.0))
		_draw_cached_text(confirmation_text, _kill_width, center.y + 46.0, 22, color, DISPLAY_FONT)
	if _action_left > 0.0 and not terminal:
		_draw_cached_text(_action_text, _action_width, center.y + 46.0, 22, Color(0.2, 0.95, 0.94, minf(1.0, _action_left * 4.0)), DISPLAY_FONT)
	if _combo_hits > 0 and _combo_fraction > 0.0 and not terminal:
		_draw_combo(center)
	if not terminal and aiming:
		_draw_rhythm(center)
	if not aiming and not terminal:
		_draw_cached_text(AIM_HINT, _aim_hint_width, center.y + 70.0, 17, Color(0.83, 0.76, 0.62))

func _measure_combo() -> void:
	_combo_font_size = 26 if size.y < 540.0 else (30 if size.y < 660.0 else 42)
	var font_changed := _combo_font_size != _measured_font_size
	if font_changed or _combo_text != _measured_combo_text:
		_combo_width = DISPLAY_FONT.get_string_size(_combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size).x
		_measured_combo_text = _combo_text
	if font_changed:
		_combo_ascent = DISPLAY_FONT.get_ascent(_combo_font_size)
		_combo_descent = DISPLAY_FONT.get_descent(_combo_font_size)
		_measured_font_size = _combo_font_size
	if _combo_bonus_text != _measured_bonus_text:
		_bonus_width = BODY_FONT.get_string_size(_combo_bonus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_measured_bonus_text = _combo_bonus_text
	if _shard_widths.is_empty():
		_kill_width = DISPLAY_FONT.get_string_size(confirmation_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_aim_hint_width = BODY_FONT.get_string_size(AIM_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		_rhythm_prompt_text = "DROP 0% • KILLY + STYLE"
		_rhythm_ready_text = _rhythm_prompt_text
		_rhythm_prompt_width = BODY_FONT.get_string_size(_rhythm_prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_rhythm_ready_width = _rhythm_prompt_width
		_shard_widths.resize(PRINT_SHARDS.size())
		for i in PRINT_SHARDS.size():
			_shard_widths[i] = DISPLAY_FONT.get_string_size(PRINT_SHARDS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x

func _on_profile_changed() -> void:
	_dance_strength = clampf(float(Profile.settings.get("hallucination_intensity", 0.65)), 0.0, 1.0)

func _update_beat() -> void:
	var phase := Music.beat_phase()
	if phase < 0.0:
		_beat_phase = -1.0
		_beat_travel = 0.0
		return
	if _beat_phase < 0.0:
		_beat_travel = phase
	else:
		# Unwrap measured audio phase, never integrate a made-up BPM clock.
		_beat_travel += maxf(0.0, wrapf(phase - _beat_phase, -0.5, 0.5))
		_beat_travel = fmod(_beat_travel, 16.0)
	_beat_phase = phase

func _combo_baseline(center: Vector2) -> float:
	# Bottom HUD begins at height - 142; leave the fixed rhythm row above it.
	return minf(center.y + 108.0, size.y - 197.0)

func _draw_combo(center: Vector2) -> void:
	var baseline := _combo_baseline(center)
	var musical := _beat_phase >= 0.0
	var drive := _dance_strength if musical else 0.0
	var tier := float(_combo_tier)
	var angle := _beat_phase * TAU if musical else 0.0
	var kick := pow(1.0 - _beat_phase, 3.0) if musical else 0.0
	var bounce := (2.0 + tier * 3.0) * kick * drive
	var lean := sin(angle) * (0.025 + tier * 0.035) * drive
	var shake := Vector2.ZERO
	if _combo_tier >= 2:
		shake = Vector2(sin(angle * 3.0), sin(angle * 2.0)) * (tier - 1.0) * kick * 2.0 * drive
	var scale := 1.0 + (_chain_pulse * 0.06 + kick * (0.025 + tier * 0.02)) * drive
	scale = minf(scale, minf(360.0, size.x - 64.0) / maxf(1.0, _combo_width))
	var label_height := _combo_ascent + _combo_descent
	var lane_top := center.y + 62.0
	var lane_bottom := baseline + 2.0
	var rotated_height := absf(sin(lean)) * _combo_width + absf(cos(lean)) * label_height
	scale = minf(scale, maxf(1.0, lane_bottom - lane_top) / maxf(1.0, rotated_height))
	var half_height := rotated_height * scale * 0.5
	var pivot_y := clampf(baseline - (_combo_ascent - _combo_descent) * 0.5 - bounce + shake.y, lane_top + half_height, lane_bottom - half_height)
	var pivot := Vector2(center.x + shake.x, pivot_y)
	var tear := (1.0 + _combo_heat * 2.2 + tier) * (0.65 + _chain_pulse * 0.35) * _dance_strength
	var ink := combo_color.lerp(Color(1.0, 0.29, 0.58), minf(0.9, _combo_heat * 0.65 + tier * 0.08)) if _combo_hits >= 3 else reticle_color
	if _combo_tier > 0 and drive > 0.0:
		_draw_combo_prints(center, baseline, ink, kick, drive)
	draw_set_transform(pivot, lean, Vector2.ONE * scale)
	var origin := Vector2(-_combo_width * 0.5, (_combo_ascent - _combo_descent) * 0.5)
	# Only the counter rolls. Bonus, decay, rhythm target and reticle stay fixed.
	draw_string_outline(DISPLAY_FONT, origin, _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, 5, Color(0.025, 0.015, 0.025, 0.95))
	draw_string(DISPLAY_FONT, origin + Vector2(-tear, -0.7), _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, Color(0.2, 0.95, 0.94, 0.55))
	draw_string(DISPLAY_FONT, origin + Vector2(tear, 0.7), _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, Color(1.0, 0.22, 0.6, 0.55))
	draw_string(DISPLAY_FONT, origin, _combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _combo_font_size, ink)
	draw_set_transform(Vector2.ZERO)
	_draw_cached_text(_combo_bonus_text, _bonus_width, baseline + 23.0, 14, Color(1.0, 0.9, 0.65))
	var y := baseline + 35.0
	draw_line(Vector2(center.x - 88.0, y), Vector2(center.x + 88.0, y), Color(0.08, 0.035, 0.07, 0.9), 5.0)
	draw_line(Vector2(center.x - 88.0, y), Vector2(center.x - 88.0 + 176.0 * _combo_fraction, y), ink, 3.0)

func _draw_combo_prints(center: Vector2, baseline: float, ink: Color, kick: float, drive: float) -> void:
	var tier := float(_combo_tier)
	var top := center.y + 58.0
	var bottom := baseline + 3.0
	var middle := (top + bottom) * 0.5
	var radius := minf(190.0, _combo_width * 0.5 + 24.0 + tier * 10.0)
	var orbit := _beat_travel * TAU * (0.25 + tier * 0.125)
	var vertical := maxf(2.0, (bottom - top) * 0.5 - 8.0)
	# Elliptical print halos are confined to the counter lane, not the world.
	for ring in _combo_tier:
		var ring_radius := radius + float(ring) * 8.0 + _tier_burst * 12.0
		var start := orbit * (-1.0 if ring % 2 == 1 else 1.0) + float(ring)
		draw_set_transform(Vector2(center.x, middle), 0.0, Vector2(1.0, vertical / ring_radius))
		draw_arc(Vector2.ZERO, ring_radius, start, start + PI * 1.25, 40, Color(ink if ring % 2 == 0 else Color(0.2, 0.95, 0.94), (0.22 + kick * 0.15) * drive), 1.5, true)
	draw_set_transform(Vector2.ZERO)
	var count := 4 + _combo_tier * 2
	for i in count:
		var spiral := orbit + float(i) * TAU / float(count)
		var spread := 1.0 + _tier_burst * 0.15
		var at := Vector2(center.x + cos(spiral) * radius * spread, middle + sin(spiral) * vertical)
		# Shards can spin a full turn; the actual numeric counter never flips.
		var index := i % PRINT_SHARDS.size()
		draw_set_transform(at, spiral + PI * 0.5, Vector2.ONE * (0.65 + tier * 0.1))
		draw_string_outline(DISPLAY_FONT, Vector2(-_shard_widths[index] * 0.5, 5.0), PRINT_SHARDS[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 2, Color(0.02, 0.015, 0.025, drive * 0.8))
		draw_string(DISPLAY_FONT, Vector2(-_shard_widths[index] * 0.5, 5.0), PRINT_SHARDS[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ink if i % 2 == 0 else Color(0.2, 0.95, 0.94), drive * (0.4 + kick * 0.25)))
	draw_set_transform(Vector2.ZERO)
	if _tier_burst > 0.0:
		var burst_radius := radius + (1.0 - _tier_burst) * 26.0
		for i in 12:
			var a := float(i) * TAU / 12.0
			var at := Vector2(center.x + cos(a) * burst_radius, middle + sin(a) * vertical)
			draw_line(at, at + Vector2(cos(a) * 9.0, sin(a) * 3.0), Color(ink, _tier_burst * drive * 0.8), 2.0, true)

func _draw_rhythm(center: Vector2) -> void:
	var y := _combo_baseline(center) + 50.0
	var signed_phase := _beat_phase if _beat_phase <= 0.5 else _beat_phase - 1.0
	var ready := _drop_ready and _rhythm_eligible and absf(signed_phase) <= ArenaPlayer.RHYTHM_PERFECT_WINDOW
	var color := Color(0.2, 0.95, 0.94) if ready else Color(0.86, 0.81, 0.68)
	var text := _rhythm_ready_text if ready else _rhythm_prompt_text
	var width := _rhythm_ready_width if ready else _rhythm_prompt_width
	var font: Font = BODY_FONT
	var font_size := 14
	if _rhythm_confirmation > 0.0:
		text = _rhythm_shot_text
		width = _rhythm_shot_width
		color = Color(1.0, 0.72, 0.38)
		font = DISPLAY_FONT
		font_size = 22
		if _rhythm_shot_max:
			color = Color(0.2, 0.95, 0.94)
	var at := Vector2(center.x - 24.0 - width, y)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.02, 0.015, 0.02, 0.95))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	var target := Vector2(center.x + 55.0, y - 4.0)
	draw_line(target - Vector2(40.0, 0.0), target + Vector2(40.0, 0.0), Color(0.04, 0.025, 0.04, 0.95), 5.0)
	if _drop_ready and _rhythm_eligible:
		draw_line(target - Vector2(16.0, 0.0), target + Vector2(16.0, 0.0), Color(color, 0.55), 4.0)
		draw_line(target - Vector2(0.0, 5.0), target + Vector2(0.0, 5.0), color, 1.5)
		var marker := target + Vector2(clampf(signed_phase / 0.25, -1.0, 1.0) * 40.0, 0.0)
		draw_circle(marker, 3.0, color)
	else:
		draw_line(target - Vector2(40.0, 0.0), target + Vector2(-40.0 + 80.0 * _drop_charge, 0.0), Color(0.2, 0.95, 0.94), 3.0)

func _draw_cached_text(text: String, width: float, y: float, font_size: int, color: Color, font: Font = BODY_FONT) -> void:
	var at := Vector2((size.x - width) * 0.5, y)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.02, 0.015, 0.02, color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## The active player's gameplay timer drives the counter, including pause and decay.
func _aim_player() -> ArenaPlayer:
	var camera := get_viewport().get_camera_3d()
	return camera.owner as ArenaPlayer if camera != null else null
