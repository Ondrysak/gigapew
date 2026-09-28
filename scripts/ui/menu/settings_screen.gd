extends MenuScreen

## Audio, mouse and display options. Every change applies and saves through
## Profile.set_setting(). Works while the tree is paused (pause menu).

@export var master_slider: Range
@export var music_slider: Range
@export var sfx_slider: Range
@export var sensitivity_slider: Range
@export var master_value: Label
@export var music_value: Label
@export var sfx_value: Label
@export var sensitivity_value: Label
@export var fullscreen_toggle: BaseButton

func _ready() -> void:
	super()
	sensitivity_slider.min_value = Profile.SENSITIVITY_RANGE.x
	sensitivity_slider.max_value = Profile.SENSITIVITY_RANGE.y
	master_slider.value_changed.connect(_on_volume_changed.bind("master_volume", master_value))
	music_slider.value_changed.connect(_on_volume_changed.bind("music_volume", music_value))
	sfx_slider.value_changed.connect(_on_volume_changed.bind("sfx_volume", sfx_value))
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

func refresh() -> void:
	var settings := Profile.settings
	master_slider.set_value_no_signal(settings.master_volume)
	music_slider.set_value_no_signal(settings.music_volume)
	sfx_slider.set_value_no_signal(settings.sfx_volume)
	sensitivity_slider.set_value_no_signal(settings.mouse_sensitivity)
	fullscreen_toggle.set_pressed_no_signal(settings.fullscreen)
	_show_volume(master_value, settings.master_volume)
	_show_volume(music_value, settings.music_volume)
	_show_volume(sfx_value, settings.sfx_volume)
	_show_sensitivity(settings.mouse_sensitivity)

func _on_volume_changed(value: float, key: String, label: Label) -> void:
	Profile.set_setting(key, value)
	_show_volume(label, value)

func _on_sensitivity_changed(value: float) -> void:
	Profile.set_setting("mouse_sensitivity", value)
	_show_sensitivity(value)

func _on_fullscreen_toggled(pressed: bool) -> void:
	Profile.set_setting("fullscreen", pressed)

func _show_volume(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value * 100.0)

func _show_sensitivity(value: float) -> void:
	sensitivity_value.text = "%.2f×" % value
