class_name MusicLayers
extends Control

## Source-audio meters, not an animation inferred from combat intensity.
const TEXT := Color(0.87, 0.81, 0.67)
const DIM := Color(0.65, 0.60, 0.49)
const KICK := Color(0.91, 0.52, 0.29)
const SYNTH := Color(0.77, 0.68, 0.40)
const VOICE := Color(0.48, 0.72, 0.65)
const TECHNO_PARTS := [
	[&"kick", "TECHNO KICK", KICK], [&"clap", "CLAP", KICK],
	[&"hat", "HATS", KICK], [&"groove", "NO-KICK GROOVE", KICK],
	[&"bass", "BASS LOOP", KICK], [&"synth", "SYNTH PHRASE", SYNTH],
	[&"arp", "ARP PHRASE", SYNTH], [&"ambient", "ATMOSPHERE", SYNTH],
	[&"accent", "LIVE ACCENT", VOICE],
]
const HARDTEK_PARTS := [
	[&"drums", "KICK / SNARE", KICK], [&"boss_drive", "ROLLING ACID", KICK],
	[&"boss_pad", "BOSS PAD", SYNTH], [&"perc", "HATS / PERC", KICK],
	[&"breaks", "BREAK CHOPS", KICK], [&"rave", "303 / FX", KICK],
	[&"tension", "TENSION", SYNTH], [&"vocals", "VOCAL CHOPS", VOICE],
	[&"accent", "LIVE ACCENT", VOICE],
]
const ACCENT_LABELS := {&"salvage": "SALVAGE", &"combo": "COMBO", &"danger": "DANGER", &"drop": "DROP"}
const STINGER_LABELS := {&"level_up": "LEVEL UP", &"stage_clear": "CLEAR", &"death": "DEATH", &"run_complete": "FINALE"}

var _meter = Music.MixMeter.new()
var _indexes: Array[int] = []
var _parts: Array = TECHNO_PARTS
var _track: StringName = &""
var _bars: Array[float] = []
var _font: Font
var _panel := StyleBoxFlat.new()
var _last_ticks := 0
var _next_poll := 0
var _compact := false
var _status := ""
var _timing := ""
var _cue := ""
var _voice := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = StreetWear.BODY_FONT
	_panel.bg_color = Color(0.075, 0.063, 0.05, 0.92)
	_panel.border_color = Color(0.48, 0.39, 0.26, 0.85)
	_panel.set_border_width_all(1)
	_panel.border_width_left = 3
	_panel.set_corner_radius_all(3)
	_bars.resize(_parts.size())
	for part: Array in _parts:
		_indexes.append(MusicScore.TRACK_STEMS[&"stage"].find(part[0]))
	_bars.fill(0.0)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var view := get_viewport_rect().size
	_compact = view.y < 660.0
	size = Vector2(300, 170 if _compact else 214)
	position = Vector2(view.x - size.x - 24, 286 if _compact else 300)
	queue_redraw()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if now < _next_poll or not is_visible_in_tree():
		return
	var elapsed := clampf(float(now - _last_ticks) / 1000000.0, 0.0, 0.1) if _last_ticks > 0 else 0.05
	_last_ticks = now
	_next_poll = now + 50000
	Music.sample_mix(_meter)
	if _track != _meter.track:
		_track = _meter.track
		_parts = HARDTEK_PARTS if _meter.genre == &"hardtek" else TECHNO_PARTS
		_indexes.clear()
		for part: Array in _parts:
			_indexes.append(_meter.stems.find(part[0]))
		_bars.resize(_parts.size())
		_bars.fill(0.0)
	for i in _parts.size():
		var rms: float = _meter.rms[_indexes[i]] if _indexes[i] >= 0 else _meter.accent_rms
		var target := clampf((linear_to_db(rms) + 60.0) / 60.0, 0.0, 1.0) if rms > 0.001 else 0.0
		_bars[i] = 0.0 if _meter.muted else maxf(target, _bars[i] - elapsed * 3.0)
	_status = "LIVE"
	if _meter.rendered < _meter.gains.size():
		_status = "GENERATING %d/%d" % [_meter.rendered, _meter.gains.size()]
	elif not _meter.playing:
		_status = "STOPPED"
	elif _meter.muted:
		_status = "MUTED"
	elif get_tree().paused:
		_status = "PAUSE · MUSIC LIVE"
	elif _meter.voice != &"":
		_status = "VOICE · VOX OFF" if _meter.genre == &"hardtek" else "VOICE · MUSIC LIVE"
	_timing = "%s minor · %d BPM · %02d/%02d" % [_meter.tonic, _meter.bpm, floori(_meter.position / _meter.bar_seconds) + 1, _meter.bars] if _meter.playing else ("NEW MIX · %d BPM" % _meter.bpm if _meter.bpm > 0 else "WAITING FOR NEW MIX")
	_cue = ""
	if _meter.accent != &"" and not _meter.muted:
		_cue = "ACCENT: " + String(ACCENT_LABELS[_meter.accent])
	for stinger: StringName in _meter.stingers:
		_cue += (" + " if not _cue.is_empty() else "STINGER: ") + String(STINGER_LABELS[stinger])
	_voice = "HLAS: " + String(_meter.voice).to_upper() if _meter.voice != &"" else ""
	queue_redraw()

func _draw() -> void:
	if _font == null:
		return
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	var heading_y := 16.0 if _compact else 20.0
	var genre := String(_meter.genre).to_upper()
	draw_string(_font, Vector2(10, heading_y), genre + " #" + _meter.identity if not _meter.identity.is_empty() else genre + " / LAYERS", HORIZONTAL_ALIGNMENT_LEFT, 142, 12, TEXT)
	draw_string(_font, Vector2(152, heading_y), _status, HORIZONTAL_ALIGNMENT_RIGHT, 138, 10, VOICE if _status == "LIVE" else DIM)
	var clock_y := 29.0 if _compact else 37.0
	draw_string(_font, Vector2(10, clock_y), _timing, HORIZONTAL_ALIGNMENT_LEFT, 198, 10, DIM)
	var beat_seconds: float = _meter.bar_seconds * 0.25
	var phase: float = fposmod(_meter.position, beat_seconds) / beat_seconds if beat_seconds > 0.0 else 0.0
	var beat := floori(_meter.position / beat_seconds) % 4 if beat_seconds > 0.0 else 0
	for i in 4:
		var color := KICK if i == beat and _meter.playing and not _meter.muted else DIM.darkened(0.6)
		if i == beat and _meter.playing and not _meter.muted:
			color.a = lerpf(1.0, 0.3, phase)
		draw_rect(Rect2(247 + i * 11, clock_y - 7, 7, 5), color)
	var first_y := 43.0 if _compact else 55.0
	var row_height := 16.0 if _compact else 20.0
	var rows := ceili(_parts.size() / 2.0)
	for i in _parts.size():
		var x := 10.0 if i < rows else 158.0
		var y := first_y + (i % rows) * row_height
		var gain: float = _meter.gains[_indexes[i]] if _indexes[i] >= 0 else _meter.accent_gain
		var enabled := gain > 0.0001
		var color: Color = _parts[i][2]
		draw_circle(Vector2(x + 2, y - 4), 2, color if enabled else DIM.darkened(0.65))
		draw_string(_font, Vector2(x + 8, y), _parts[i][1], HORIZONTAL_ALIGNMENT_LEFT, 88, 10, TEXT if enabled else DIM.darkened(0.2))
		draw_rect(Rect2(x + 99, y - 9, 31, 7), Color(0.17, 0.15, 0.11))
		if _bars[i] > 0.0:
			draw_rect(Rect2(x + 99, y - 9, 31 * _bars[i], 7), color)
		for tick in [1, 2, 3]:
			draw_line(Vector2(x + 99 + tick * 7.75, y - 9), Vector2(x + 99 + tick * 7.75, y - 2), Color(0.075, 0.063, 0.05, 0.5))
	var footer_y := size.y - 18.0
	var cue := _cue
	if not _voice.is_empty():
		cue += (" · " if not cue.is_empty() else "") + _voice
	draw_string(_font, Vector2(10, footer_y), cue, HORIZONTAL_ALIGNMENT_LEFT, 280, 10, VOICE)
	draw_string(_font, Vector2(10, size.y - 5), "DOT: IN MIX   /   BAR: SOURCE RMS, PRE-FX", HORIZONTAL_ALIGNMENT_LEFT, 280, 9, DIM)
