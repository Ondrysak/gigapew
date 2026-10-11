extends Node

## Boot cinematic: a drifting Žižkov courtyard and a worn party poster.
## Any key or click skips.

@export_file("*.tscn") var next_scene := "res://scenes/ui/main_menu.tscn"
@export var backdrop: StageBackdrop
@export var logo: MenuLogo
@export var fade: ColorRect
@export var skip_hint: Control
@export var duration := 6.2

var _leaving := false
var _timeline: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(&"menu")
	logo.reveal = 0.0
	logo.underline_ratio = 0.0
	logo.subtitle_label.modulate.a = 0.0
	skip_hint.modulate.a = 0.0
	fade.color.a = 1.0

	# Stay above the tenement walls while drifting toward the septic courtyard.
	var camera_move := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_move.tween_property(backdrop, ^"orbit_radius", 8.0, duration).from(11.0)
	camera_move.tween_property(backdrop, ^"orbit_height", 6.5, duration).from(8.0)
	camera_move.tween_property(backdrop, ^"look_height", 1.4, duration).from(1.0)

	_timeline = create_tween()
	_timeline.tween_property(fade, ^"color:a", 0.0, 1.3)
	_timeline.parallel().tween_property(skip_hint, ^"modulate:a", 0.7, 1.0).set_delay(0.8)
	_timeline.tween_property(logo, ^"reveal", 1.0, 1.1).set_trans(Tween.TRANS_QUAD)
	_timeline.tween_property(logo, ^"underline_ratio", 1.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(logo.subtitle_label, ^"modulate:a", 1.0, 0.7)
	_timeline.tween_interval(maxf(duration - 3.6, 0.5))
	_timeline.tween_callback(_leave)
	StreetWear.apply_tree(self)

func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) \
			and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		_leave()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if _timeline != null:
		_timeline.kill()
	var out := create_tween()
	out.tween_property(fade, ^"color:a", 1.0, 0.45)
	out.tween_callback(get_tree().change_scene_to_file.bind(next_scene))
