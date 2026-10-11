class_name HallucinationVision
extends CanvasLayer

## One world-only screen pass below HUD layer 1. The global gameplay clock
## freezes its drift in pause/reward menus; their higher layers stay crisp.
@onready var _game: ArenaGame = get_parent() as ArenaGame

var _enabled := false
var _last_state := -1

func _ready() -> void:
	Profile.changed.connect(_on_profile_changed)
	_on_profile_changed()

func _process(_delta: float) -> void:
	if _game == null:
		return
	if _last_state != _game.round_state:
		_last_state = _game.round_state
		_refresh_visibility()

func _on_profile_changed() -> void:
	_enabled = float(Profile.settings.get("hallucination_intensity", 0.65)) > 0.0
	_refresh_visibility()

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
