extends Node3D

const CombatFeedback := preload("res://scripts/combat_feedback.gd")

@onready var player: ArenaPlayer = $Player
@onready var enemies: Node3D = $Enemies
@onready var health_label: Label = $CanvasLayer/Health
@onready var hostiles_label: Label = $CanvasLayer/Hostiles
@onready var crosshair: Label = $CanvasLayer/Crosshair
@onready var message: Label = $CanvasLayer/Message

var remaining_hostiles := 0
var _terminal := false
var _last_health := 100
var _feedback: CombatFeedback

func _ready() -> void:
	_feedback = CombatFeedback.new()
	$CanvasLayer.add_child(_feedback)
	crosshair.text = ""
	player.shot_fired.connect(_feedback.show_shot)
	player.hit_confirmed.connect(_feedback.show_hit)
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	for child in enemies.get_children():
		var enemy := child as ArenaEnemy
		enemy.target = player
		enemy.died.connect(_on_enemy_died)
		remaining_hostiles += 1
	_on_health_changed(player.health, 100)
	_update_hostiles()

func _process(_delta: float) -> void:
	_feedback.aiming = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _terminal and event.is_action_pressed("restart") and not event.is_echo():
		get_tree().reload_current_scene()

func _on_health_changed(current: int, _maximum: int) -> void:
	health_label.text = "HEALTH %d" % current
	if current < _last_health:
		_feedback.show_damage()
	_last_health = current
	health_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.4) if current <= 30 else Color(0.86, 0.98, 1.0))

func _on_enemy_died() -> void:
	remaining_hostiles -= 1
	_update_hostiles()
	if remaining_hostiles == 0 and not _terminal:
		_terminal = true
		_feedback.terminal = true
		player.sound.play_cue(&"victory")
		player.active = false
		player.velocity = Vector3.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		crosshair.hide()
		message.text = "ARENA CLEAR\nPRESS R TO RESTART"
		message.show()

func _on_player_died() -> void:
	_terminal = true
	_feedback.terminal = true
	player.sound.play_cue(&"death")
	crosshair.hide()
	message.text = "YOU DIED\nPRESS R TO RESTART"
	message.show()

func _update_hostiles() -> void:
	hostiles_label.text = "HOSTILES %d" % remaining_hostiles
