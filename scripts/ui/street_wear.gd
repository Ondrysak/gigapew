class_name StreetWear
extends Control

## Shared poster typography, worn ink, chipped edges and grime; no input changes.
const DIRT := Color(0.008, 0.007, 0.009, 0.8)
const FADED_INK := Color(0.58, 0.49, 0.35, 0.13)
const SCUFF := Color(0.64, 0.56, 0.43, 0.09)
const DISPLAY_FONT: Font = preload("res://assets/fonts/rave_display.tres")
const BODY_FONT: Font = preload("res://assets/fonts/rave_body.tres")

var _surface: Control
var _heavy := false
var _chips: Array[Rect2] = []
var _scuffs: Array[Rect2] = []
var _seams: Array[PackedVector2Array] = []

static func apply(surface: Control, heavy := false) -> void:
	_apply_typography(surface)
	# TabContainer treats even internal Controls as pages. Decorate its bar,
	# never add a page-shaped overlay to the container itself.
	if surface is TabContainer:
		apply(surface.get_tab_bar(), heavy)
		return
	if surface.has_meta(&"street_wear"):
		return
	surface.set_meta(&"street_wear", true)
	var wear := StreetWear.new()
	wear._surface = surface
	wear._heavy = heavy
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Internal children are excluded from container layout and normal tree walks.
	# Paint above the native surface, but below its labels and other content.
	surface.add_child(wear, false, Node.INTERNAL_MODE_FRONT)
	wear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wear.resized.connect(wear._rebuild)
	wear._rebuild()

static func apply_tree(root: Node) -> void:
	if root is Control:
		_apply_typography(root as Control)
	if root is PanelContainer or root is Button or root is TabContainer:
		apply(root as Control)
	for child in root.get_children():
		apply_tree(child)

static func _apply_typography(surface: Control) -> void:
	# The project/theme supplies compact body text, including controls created
	# after this pass. Large unclassified labels/actions get the poster face.
	# Explicit fonts and body/section variants remain authoritative.
	if surface.has_theme_font_override(&"font"):
		return
	if surface.theme_type_variation in [&"BodyLabel", &"DimLabel", &"SectionLabel"]:
		return
	if surface is Label or (surface is Button and not surface is OptionButton and not surface is CheckButton):
		if surface.theme_type_variation in [&"HeaderLabel", &"DisplayLabel", &"AccentButton"] or surface.get_theme_font_size(&"font_size") >= 24:
			surface.add_theme_font_override(&"font", DISPLAY_FONT)

func _rebuild() -> void:
	_chips.clear()
	_scuffs.clear()
	_seams.clear()
	var size := _surface.size
	if size.x < 12.0 or size.y < 12.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_surface.name)
	var amount := 32 if _heavy else 18
	for index in amount:
		var width := rng.randf_range(3.0, minf(24.0, size.x * 0.15))
		var x := rng.randf_range(0.0, size.x - width)
		var y := rng.randf_range(1.0, size.y - 2.0)
		_scuffs.append(Rect2(floorf(x), floorf(y), floorf(width), 1.0 if index % 3 else 2.0))
	for fraction in [0.0, 0.17, 0.43, 0.79, 0.98]:
		var x := minf(size.x - 5.0, size.x * fraction)
		_chips.append(Rect2(x, 0.0, rng.randf_range(4.0, 12.0), rng.randf_range(2.0, 5.0)))
		_chips.append(Rect2(size.x - x - 8.0, size.y - 3.0, 8.0, 3.0))
	_chips.append(Rect2(0.0, size.y * 0.36, 4.0, 11.0))
	_chips.append(Rect2(size.x - 3.0, size.y * 0.7, 3.0, 8.0))
	_seams.append(PackedVector2Array([
		Vector2(5.0, 4.0), Vector2(size.x * 0.24, 3.0),
		Vector2(size.x * 0.24 + 4.0, 5.0), Vector2(size.x * 0.56, 4.0),
	]))
	_seams.append(PackedVector2Array([
		Vector2(size.x * 0.62, size.y - 5.0), Vector2(size.x * 0.82, size.y - 4.0),
		Vector2(size.x * 0.83, size.y - 6.0), Vector2(size.x - 7.0, size.y - 5.0),
	]))
	queue_redraw()

func _draw() -> void:
	for scuff in _scuffs:
		draw_rect(scuff, SCUFF)
	for seam in _seams:
		draw_polyline(seam, FADED_INK, 1.0)
	for chip in _chips:
		draw_rect(chip, DIRT)
