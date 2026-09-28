class_name MenuScreen
extends Control

## A full-screen menu page. Owners call open()/hide(); `ui_cancel` (Esc) or a
## Back button emits back_requested. Subclasses override refresh() to redraw
## from Profile and set `default_focus`.

signal back_requested

## Focused when the screen opens (keyboard/controller navigation).
@export var default_focus: Control
@export var back_button: BaseButton

func _ready() -> void:
	if back_button != null:
		back_button.pressed.connect(back_requested.emit)

func open() -> void:
	show()
	refresh()
	if default_focus != null and default_focus.is_visible_in_tree():
		default_focus.grab_focus.call_deferred()

## Redraws from current data. Called by open().
func refresh() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
