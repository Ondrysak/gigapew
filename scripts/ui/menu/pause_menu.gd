class_name PauseMenu
extends CanvasLayer

## In-run pause overlay. The owner pauses the tree and calls open(); this
## layer processes while paused. Resume (button or Esc) hides the menu,
## recaptures the mouse and emits resume_requested (owner unpauses). Abandon
## asks for confirmation, then emits abandon_requested without closing.

signal resume_requested
signal abandon_requested

@export var main_panel: Control
@export var resume_button: Button
@export var settings_button: Button
@export var abandon_button: Button
@export var confirm_box: Control
@export var confirm_abandon_button: Button
@export var cancel_abandon_button: Button
@export var settings: MenuScreen

var _open := false
var _opened_frame := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_show_settings)
	abandon_button.pressed.connect(_set_confirming.bind(true))
	cancel_abandon_button.pressed.connect(_set_confirming.bind(false))
	confirm_abandon_button.pressed.connect(_abandon)
	settings.back_requested.connect(_show_main.bind(settings_button))

func open() -> void:
	_open = true
	_opened_frame = Engine.get_process_frames()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main(resume_button)

func close() -> void:
	_open = false
	hide()

func is_open() -> bool:
	return _open

func _unhandled_input(event: InputEvent) -> void:
	if not _open or settings.visible:
		return
	if not (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		return
	get_viewport().set_input_as_handled()
	# The key press that opened the menu must not immediately close it.
	if Engine.get_process_frames() == _opened_frame:
		return
	if confirm_box.visible:
		_set_confirming(false)
	else:
		_resume()

func _show_main(focus: Control) -> void:
	settings.hide()
	main_panel.show()
	confirm_box.hide()
	abandon_button.show()
	focus.grab_focus.call_deferred()

func _show_settings() -> void:
	main_panel.hide()
	settings.open()

func _set_confirming(confirming: bool) -> void:
	confirm_box.visible = confirming
	abandon_button.visible = not confirming
	var focus := cancel_abandon_button if confirming else abandon_button
	focus.grab_focus.call_deferred()

func _resume() -> void:
	if not _open:
		return
	close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resume_requested.emit()

func _abandon() -> void:
	if not _open:
		return
	abandon_requested.emit()
