class_name HallucinationVision
extends CanvasLayer

## One world-only screen pass below HUD layer 1. This controller alone writes
## the combo intensity, escalation and audible-beat globals used by native FX.
## Paused menus freeze their drive; their layers stay crisp.
@onready var _game: ArenaGame = get_parent() as ArenaGame

var _enabled := false
var _last_state := -1
var _combo_drive := 0.0
var _escalation_drive := 0.0
var _escalation := -1.0
var _beat := -1.0
var _ceiling := 0.65
var _effective := -1.0
var _mode := -1

var effective_intensity: float:
	get:
		return _effective

func _ready() -> void:
	Profile.changed.connect(_on_profile_changed)
	_on_profile_changed()
	_set_beat(0.0)

func _process(delta: float) -> void:
	if _game == null:
		return
	if _last_state != _game.round_state:
		_last_state = _game.round_state
		_refresh_visibility()
	if _game.round_state == ArenaGame.RoundState.PLAYING and is_instance_valid(_game.player):
		var next := move_toward(_combo_drive, _game.player.combo_intensity, delta / 0.5)
		if next != _combo_drive:
			_combo_drive = next
			_apply_intensity()
		var hits := _game.player.combo_hits
		var target := 0.0
		if hits >= 100:
			target = lerpf(0.35, 0.70, clampf(float(hits - 100) / 100.0, 0.0, 1.0))
			target += 0.30 * clampf(float(hits - 200) / 100.0, 0.0, 1.0)
		# Approximately half a second to settle, independent of frame rate.
		_escalation_drive = lerpf(_escalation_drive, target, 1.0 - exp(-delta / 0.17))
		if absf(_escalation_drive - target) < 0.0001:
			_escalation_drive = target
		_apply_escalation()
		var phase := Music.beat_phase() if _enabled else -1.0
		# A smooth geometric breath, not a brightness flash or synthetic clock.
		_set_beat(0.5 + 0.5 * cos(phase * TAU) if phase >= 0.0 else 0.0)

func _on_profile_changed() -> void:
	_ceiling = clampf(float(Profile.settings.get("hallucination_intensity", 0.65)), 0.0, 1.0)
	_enabled = _ceiling > 0.0
	var next_mode := int(Profile.settings.get("hallucination_mode", Profile.HallucinationMode.MIX))
	if next_mode != _mode:
		_mode = next_mode
		RenderingServer.global_shader_parameter_set("hallucination_mode", _mode)
	_apply_intensity()
	_apply_escalation()
	if not _enabled:
		_set_beat(0.0)
	_refresh_visibility()

func _apply_intensity() -> void:
	var next := _ceiling * lerpf(0.28, 1.0, _combo_drive)
	if next != _effective:
		_effective = next
		RenderingServer.global_shader_parameter_set("hallucination_intensity", _effective)

func _apply_escalation() -> void:
	var next := _ceiling * _escalation_drive
	if next != _escalation:
		_escalation = next
		RenderingServer.global_shader_parameter_set("hallucination_escalation", _escalation)

func _set_beat(next: float) -> void:
	if next != _beat:
		_beat = next
		RenderingServer.global_shader_parameter_set("hallucination_beat", _beat)

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("hallucination_intensity", 0.0)
	RenderingServer.global_shader_parameter_set("hallucination_escalation", 0.0)
	RenderingServer.global_shader_parameter_set("hallucination_beat", 0.0)
	RenderingServer.global_shader_parameter_set("hallucination_mode", Profile.HallucinationMode.FEEDBACK)

func _refresh_visibility() -> void:
	var show_world := false
	if _enabled and _mode != Profile.HallucinationMode.HEADS and _game != null:
		match _game.round_state:
			ArenaGame.RoundState.PLAYING, ArenaGame.RoundState.PAUSED, ArenaGame.RoundState.LEVEL_UP, ArenaGame.RoundState.ENCOUNTER_REWARD, ArenaGame.RoundState.GEAR:
				show_world = true
	# Hiding the layer (rather than setting transparent shader output) removes
	# the screen-reading draw and its automatic screen copy at intensity zero.
	if visible != show_world:
		visible = show_world
