extends Node

## Title menu over a live stage backdrop. Home buttons open MenuScreen pages;
## class select's deploy starts res://scenes/game.tscn with
## Profile.selected_class_id set.

@export_file("*.tscn") var game_scene := "res://scenes/game.tscn"
@export var home: Control
@export var play_button: Button
@export var base_button: Button
@export var records_button: Button
@export var settings_button: Button
@export var quit_button: Button
@export var operator_label: Label
@export var class_select: ClassSelectScreen
@export var base: MenuScreen
@export var records: MenuScreen
@export var settings: MenuScreen
## Darkens the backdrop while a page is open.
@export var screen_dim: CanvasItem
@export var fade: ColorRect

var _return_focus: Control
var _leaving := false

func _ready() -> void:
	# A run abandoned from the pause menu arrives with the tree still paused.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(&"menu")
	play_button.pressed.connect(_open.bind(class_select, play_button))
	base_button.pressed.connect(_open.bind(base, base_button))
	records_button.pressed.connect(_open.bind(records, records_button))
	settings_button.pressed.connect(_open.bind(settings, settings_button))
	quit_button.pressed.connect(get_tree().quit)
	quit_button.visible = OS.get_name() != "Web"
	for screen: MenuScreen in _screens():
		screen.hide()
		screen.back_requested.connect(_show_home)
	class_select.deploy_requested.connect(_deploy)
	_return_focus = play_button
	_show_home()
	fade.color.a = 1.0
	create_tween().tween_property(fade, ^"color:a", 0.0, 0.6)
	if get_tree().get_meta(&"open_base", false):
		get_tree().remove_meta(&"open_base")
		_open.call_deferred(base, base_button)
	StreetWear.apply_tree(self)

func _screens() -> Array[MenuScreen]:
	return [class_select, base, records, settings]

func _open(screen: MenuScreen, from: Control) -> void:
	if _leaving:
		return
	_return_focus = from
	home.hide()
	screen_dim.show()
	for other in _screens():
		if other != screen:
			other.hide()
	screen.open()

func _show_home() -> void:
	for screen in _screens():
		screen.hide()
	screen_dim.hide()
	home.show()
	_refresh_operator()
	_return_focus.grab_focus.call_deferred()

func _refresh_operator() -> void:
	var parts := PackedStringArray()
	var definition := Profile.selected_class()
	if definition != null:
		parts.append("PARTA  %s" % definition.display_name.to_upper())
	var records_data := Profile.records
	parts.append("VÝPRAVY  %d" % int(records_data.runs))
	parts.append("v%s" % ProjectSettings.get_setting("application/config/version"))
	if float(records_data.best_time) > 0.0:
		var seconds := int(records_data.best_time)
		parts.append("REKORD  %d:%02d" % [floori(seconds / 60.0), seconds % 60])
	operator_label.text = "   ·   ".join(parts)

func _deploy(definition: ClassDefinition) -> void:
	if _leaving:
		return
	_leaving = true
	Profile.selected_class_id = definition.id
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var out := create_tween()
	out.tween_property(fade, ^"color:a", 1.0, 0.5)
	out.tween_callback(get_tree().change_scene_to_file.bind(game_scene))
