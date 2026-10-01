class_name MiningFeedback
extends CanvasLayer

## Two persistent, alternating canvases. Only the destination is rendered;
## the disabled source keeps its completed texture and has no sampler bound.
const HISTORY_SHADER := preload("res://shaders/mining_history.gdshader")
const HISTORY_SIZE := Vector2i(384, 216)
const TAIL_SECONDS := 0.55

var strength := 0.65
var telemetry_visible := false
var _player: ArenaPlayer
var _camera: Camera3D
var _views: Array[SubViewport] = []
var _materials: Array[ShaderMaterial] = []
var _display: TextureRect
var _readout_layer: CanvasLayer
var _panel: VBoxContainer
var _name: Label
var _status: Label
var _bar: ProgressBar
var _hint: Label
var _seam: Label
var _data: Dictionary = {}
var _resonance := 0.0
var _drilling := false
var _tail := 0.0
var _fracture := 0.0
var _phase := 0.0
var _last := -1
var _pending := -1
var _generation := 0
var _pending_generation := 0
var _dirty := false

func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 2:
		var viewport := SubViewport.new()
		viewport.name = "MiningHistory%d" % index
		viewport.size = HISTORY_SIZE
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.gui_disable_input = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(viewport)
		var material := ShaderMaterial.new()
		material.shader = HISTORY_SHADER
		var canvas := ColorRect.new()
		canvas.size = Vector2(HISTORY_SIZE)
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.material = material
		viewport.add_child(canvas)
		_views.append(viewport)
		_materials.append(material)
	_display = TextureRect.new()
	_display.name = "MiningEchoes"
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.hide()
	add_child(_display)
	_readout_layer = CanvasLayer.new()
	_readout_layer.name = "MiningTelemetry"
	_readout_layer.layer = 2
	add_child(_readout_layer)
	_panel = VBoxContainer.new()
	_panel.name = "TargetReadout"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_constant_override("separation", 3)
	_readout_layer.add_child(_panel)
	_name = _label(18)
	_status = _label(14)
	_bar = ProgressBar.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size = Vector2(250.0, 5.0)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_panel.add_child(_bar)
	_hint = _label(13)
	_seam = Label.new()
	_seam.text = "◇"
	_seam.add_theme_font_size_override("font_size", 27)
	_seam.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.9))
	_seam.add_theme_constant_override("outline_size", 5)
	_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_layer.add_child(_seam)
	_panel.hide()
	_seam.hide()
	RenderingServer.frame_post_draw.connect(_after_draw)

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.03, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	_panel.add_child(label)
	return label

func setup(player: ArenaPlayer) -> void:
	_player = player
	_camera = player.camera

func set_target(data: Dictionary, drilling: bool, resonance: float) -> void:
	_data = data
	_drilling = drilling and not data.is_empty()
	_resonance = resonance
	if _drilling:
		_tail = TAIL_SECONDS
	_dirty = _dirty or _drilling

func fragment_beat() -> void:
	_fracture = 1.0
	_tail = TAIL_SECONDS
	_dirty = true

## Invalidates stale render callbacks as well as hiding old textures. A reset
## history starts without a source sample, so old stage/pause frames cannot leak.
func reset() -> void:
	if not _dirty and _data.is_empty() and _last == -1 and _pending == -1:
		return
	_generation += 1
	_data = {}
	_drilling = false
	_resonance = 0.0
	_tail = 0.0
	_fracture = 0.0
	_last = -1
	_pending = -1
	_dirty = false
	telemetry_visible = false
	_panel.hide()
	_seam.hide()
	_display.hide()
	_display.texture = null
	for index in _views.size():
		_views[index].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_materials[index].set_shader_parameter("history", null)
		_materials[index].set_shader_parameter("history_valid", false)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.active \
			or get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		reset()
		return
	_update_telemetry()
	if not _drilling:
		_tail = maxf(0.0, _tail - delta)
	_fracture = move_toward(_fracture, 0.0, delta * 4.5)
	if strength <= 0.0 or _tail <= 0.0:
		_stop_history()
		return
	if _pending != -1:
		return
	_phase += delta
	var destination := 0 if _last != 0 else 1
	var source := 1 - destination
	# Unbind the inactive canvas before assigning the active canvas. Even
	# though disabled, leaving a reverse sampler bound creates a render cycle.
	_materials[source].set_shader_parameter("history", null)
	_views[source].render_target_update_mode = SubViewport.UPDATE_DISABLED
	var material := _materials[destination]
	material.set_shader_parameter("history_valid", _last != -1)
	material.set_shader_parameter("history", _views[source].get_texture() if _last != -1 else null)
	material.set_shader_parameter("step_seconds", minf(delta, 0.05))
	material.set_shader_parameter("aspect", get_viewport().get_visible_rect().size.aspect())
	material.set_shader_parameter("phase", _phase)
	material.set_shader_parameter("contact", 1.0 if _drilling else 0.0)
	material.set_shader_parameter("fracture", _fracture)
	material.set_shader_parameter("resonance", _resonance)
	material.set_shader_parameter("progress", float(_data.get("progress", 0.0)))
	if not _data.is_empty():
		material.set_shader_parameter("mineral_color", _data["color"])
	_pending = destination
	_pending_generation = _generation
	_views[destination].render_target_update_mode = SubViewport.UPDATE_ONCE

func _after_draw() -> void:
	if _pending == -1 or _pending_generation != _generation:
		return
	_last = _pending
	_pending = -1
	_display.texture = _views[_last].get_texture()
	_display.modulate.a = clampf(strength, 0.0, 1.0) * clampf(_tail / 0.18, 0.0, 1.0)
	_display.show()

func _stop_history() -> void:
	if _last == -1 and _pending == -1:
		return
	_generation += 1
	_last = -1
	_pending = -1
	_display.hide()
	_display.texture = null
	for index in _views.size():
		_views[index].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_materials[index].set_shader_parameter("history", null)
		_materials[index].set_shader_parameter("history_valid", false)

func _update_telemetry() -> void:
	telemetry_visible = not _data.is_empty()
	_panel.visible = telemetry_visible
	_seam.hide()
	if not telemetry_visible:
		return
	var screen_size := get_viewport().get_visible_rect().size
	_panel.position = screen_size * 0.5 + Vector2(-145.0, 52.0)
	_panel.size.x = 290.0
	var progress := clampf(float(_data["progress"]), 0.0, 1.0)
	var weak := bool(_data["weak"])
	_name.text = str(_data["name"]).to_upper()
	_name.modulate = _data["color"]
	_status.text = "FRACTURE %d%%  ·  %d / %d SECTIONS" % [roundi(progress * 100.0), int(_data["remaining"]), int(_data["total"])]
	_bar.value = progress
	_hint.text = "WEAK SEAM ×1.75  ·  RESONANCE +%d%%" % roundi(_resonance * 35.0) if weak \
			else "Hold RMB · Aim for ◇ seam · Resonance +%d%%" % roundi(_resonance * 35.0)
	_hint.modulate = Color(0.6, 1.0, 0.85) if weak else Color(0.8, 0.87, 0.95)
	var point: Vector3 = _data["weak_position"]
	if _camera == null or _camera.is_position_behind(point):
		return
	var projected := _camera.unproject_position(point)
	if not Rect2(Vector2(16.0, 16.0), screen_size - Vector2(32.0, 32.0)).has_point(projected):
		return
	_seam.position = projected - Vector2(14.0, 20.0)
	_seam.modulate = Color(0.6, 1.0, 0.85, 0.85) if weak else Color(1.0, 0.85, 0.5, 0.65)
	_seam.show()

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
