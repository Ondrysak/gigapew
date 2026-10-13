class_name MiningFeedback
extends CanvasLayer

## Nearby optional loot readout: press once, take the compartment's real stock.
var telemetry_visible := false
var _player: ArenaPlayer
var _camera: Camera3D
var _panel: VBoxContainer
var _backing: Panel
var _name: Label
var _status: Label
var _hint: Label
var _seam: Label
var _data: Dictionary = {}

func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backing = Panel.new()
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.09, 0.072, 0.052, 0.95)
	paper.border_color = Color(0.56, 0.43, 0.25)
	paper.set_border_width_all(1)
	_backing.add_theme_stylebox_override(&"panel", paper)
	add_child(_backing)
	_panel = VBoxContainer.new()
	_panel.name = "TargetReadout"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_constant_override("separation", 3)
	add_child(_panel)
	_name = _label(18)
	_status = _label(14)
	_hint = _label(13)
	_seam = Label.new()
	_seam.text = "+"
	_seam.add_theme_font_size_override("font_size", 25)
	_seam.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.9))
	_seam.add_theme_constant_override("outline_size", 4)
	_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seam)
	StreetWear.apply(_backing)
	_backing.hide()
	_panel.hide()
	_seam.hide()

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.02, 0.015, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_color", Color(0.86, 0.8, 0.67))
	_panel.add_child(label)
	return label

func setup(player: ArenaPlayer) -> void:
	_player = player
	_camera = player.camera

func set_target(data: Dictionary) -> void:
	_data = data

func reset() -> void:
	_data = {}
	telemetry_visible = false
	_panel.hide()
	_backing.hide()
	_seam.hide()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.active \
			or get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		reset()
		return
	telemetry_visible = not _data.is_empty()
	_panel.visible = telemetry_visible
	_backing.visible = telemetry_visible
	_seam.hide()
	if not telemetry_visible:
		return
	var screen_size := get_viewport().get_visible_rect().size
	_panel.position = screen_size * 0.5 + Vector2(-175.0, 52.0)
	_panel.size.x = 350.0
	_backing.position = _panel.position - Vector2(10, 6)
	_backing.size = _panel.size + Vector2(20, 12)
	var weak := bool(_data["weak"])
	_name.text = str(_data["name"]).to_upper()
	var tint: Color = _data["color"]
	_name.modulate = tint.lerp(Color(0.84, 0.73, 0.51), 0.6)
	_status.text = "ZBÝVÁ %d / %d PŘIHRÁDEK · %d KOŘISTI" % [int(_data["remaining"]), int(_data["total"]), int(_data["yield_remaining"])]
	_hint.text = "Stiskni F · Rozbij přihrádku · Volitelná kořist"
	_hint.modulate = Color(0.91, 0.73, 0.39) if weak else Color(0.84, 0.78, 0.65)
	var point: Vector3 = _data["weak_position"]
	if _camera == null or _camera.is_position_behind(point):
		return
	var projected := _camera.unproject_position(point)
	if not Rect2(Vector2(16.0, 16.0), screen_size - Vector2(32.0, 32.0)).has_point(projected):
		return
	_seam.position = projected - Vector2(10.0, 18.0)
	_seam.modulate = Color(0.92, 0.72, 0.34, 0.85) if weak else Color(0.86, 0.79, 0.62, 0.65)
	_seam.show()
