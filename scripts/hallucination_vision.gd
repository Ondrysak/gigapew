class_name HallucinationVision
extends CanvasLayer

## One world-only screen pass below HUD layer 1. This controller alone writes
## the combo-driven global used by both vision and native phantom anatomy.
## Paused menus freeze its drive and gameplay clock; their layers stay crisp.
@onready var _game: ArenaGame = get_parent() as ArenaGame

var _enabled := false
var _last_state := -1
var _combo_drive := 0.0
var _ceiling := 0.65
var _effective := -1.0

var effective_intensity: float:
	get:
		return _effective

func _ready() -> void:
	Profile.changed.connect(_on_profile_changed)
	_on_profile_changed()

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

func _on_profile_changed() -> void:
	_ceiling = clampf(float(Profile.settings.get("hallucination_intensity", 0.65)), 0.0, 1.0)
	_enabled = _ceiling > 0.0
	_apply_intensity()
	_refresh_visibility()

func _apply_intensity() -> void:
	var next := _ceiling * lerpf(0.28, 1.0, _combo_drive)
	if next != _effective:
		_effective = next
		RenderingServer.global_shader_parameter_set("hallucination_intensity", _effective)

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("hallucination_intensity", 0.0)

func _refresh_visibility() -> void:
	var show_world := false
	if _enabled and _game != null:
		match _game.round_state:
			ArenaGame.RoundState.PLAYING, ArenaGame.RoundState.PAUSED, ArenaGame.RoundState.LEVEL_UP, ArenaGame.RoundState.ENCOUNTER_REWARD, ArenaGame.RoundState.GEAR:
				show_world = true
	# Hiding the layer (rather than setting transparent shader output) removes
	# the screen-reading draw and its automatic screen copy at intensity zero.
	if visible != show_world:
		visible = show_world
