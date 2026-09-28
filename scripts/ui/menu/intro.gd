extends Node

## Boot cinematic: fade in on a drifting shot of the horde, glitch-reveal the
## logo, then hand over to the main menu. Any key or click skips.

@export_file("*.tscn") var next_scene := "res://scenes/ui/main_menu.tscn"
@export var backdrop: StageBackdrop
@export var logo: MenuLogo
@export var fade: ColorRect
@export var crt: ColorRect
@export var skip_hint: Control
@export var duration := 6.2

var _leaving := false
var _timeline: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(&"menu")
	logo.reveal = 0.0
	logo.underline_ratio = 0.0
	logo.glitch = 1.0
	logo.subtitle_label.modulate.a = 0.0
	skip_hint.modulate.a = 0.0
	fade.color.a = 1.0
	var crt_material := crt.material as ShaderMaterial

	# Camera push: low and wide, rising toward the crowd. The start radius stays
	# inside the yard's obstacle ring (crates ~21 m, pillars ~22.6 m out).
	var camera_move := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_move.tween_property(backdrop, ^"orbit_radius", 12.0, duration).from(19.0)
	camera_move.tween_property(backdrop, ^"orbit_height", 4.2, duration).from(1.1)
	camera_move.tween_property(backdrop, ^"look_height", 2.2, duration).from(1.0)

	_timeline = create_tween()
	_timeline.tween_property(fade, ^"color:a", 0.0, 1.3)
	_timeline.parallel().tween_property(skip_hint, ^"modulate:a", 0.7, 1.0).set_delay(0.8)
	_timeline.tween_property(logo, ^"reveal", 1.0, 1.1).set_trans(Tween.TRANS_QUAD)
	_timeline.parallel().tween_method(_set_glitch.bind(crt_material), 1.0, 0.05, 1.8).set_ease(Tween.EASE_OUT)
	_timeline.tween_property(logo, ^"underline_ratio", 1.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(logo.subtitle_label, ^"modulate:a", 1.0, 0.7)
	_timeline.tween_interval(maxf(duration - 4.5, 0.5))
	_timeline.tween_callback(_leave)

func _set_glitch(value: float, crt_material: ShaderMaterial) -> void:
	logo.glitch = value
	if crt_material != null:
		crt_material.set_shader_parameter(&"glitch", value * 0.8)

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
