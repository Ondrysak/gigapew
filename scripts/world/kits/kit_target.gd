class_name KitTarget
extends RefCounted
## Sink the world fills in before calling `PragueKits.build`.
##
## Use ONE KitTarget for every site of a world, then call `flush(parent)` once
## after the last `PragueKits.build`. Kit builders never touch the scene tree
## or the world RNG; they only go through this object.
##
## Callables the world fills in:
## - `solid(center: Vector3, size: Vector3, yaw: float, material: Material) -> void`
##   One Obstacles StaticBody3D + BoxShape3D (size = full extents, rotated by
##   `yaw` radians about +Y around `center`) plus a matching batched visual box.
##   Kits pass `material = null`: collider only, the visual is a palette box.
## - `visual(kind: StringName, xform: Transform3D, material: Material) -> void`
##   Visual-only primitive; `kind` is `&"box"`, `&"cylinder"` or `&"sphere"`.
##   Unit meshes (box 1×1×1, cylinder radius 0.5 height 1, sphere radius 0.5);
##   `xform` carries the scale. Batched by mesh+material. Kits only send their
##   few theme surfaces (metro walls, terrazzo, WC tiles and cashier glass) here.
## - `label(text: String, xform: Transform3D, font_size: int, color: Color) -> void`
##   Fixed (non-billboard) Label3D facing the basis +Z axis.
## - `light(position: Vector3, color: Color, energy: float, range: float) -> bool`
##   OmniLight3D; returns false once the world's kit light budget is spent.
##
## Everything else (furniture, fixtures, goods, signs) is collected here as
## palette instances and drawn by `flush` in at most five MultiMesh batches
## (palette box/cylinder/sphere/hollow ring + the sign atlas), whatever the colours.
## Venue floors add one shared batch, with finish/variant in instance channels.

const PAINT_SHADER = preload("res://shaders/kits/kit_paint.gdshader")
const SIGN_SHADER = preload("res://shaders/kits/kit_sign.gdshader")
const FLOOR_SHADER = preload("res://shaders/kits/venue_floor.gdshader")
const SIGN_ATLAS = preload("res://assets/kits/sign_atlas.png")
## Sign atlas grid (cells per row and per column).
const SIGN_GRID := Vector2i(8, 8)

## Surface finish of a palette instance (stored in the custom data alpha).
enum Finish { MATTE, SATIN, METAL, GLOSS, MIRROR, GRIME }

var solid: Callable
var visual: Callable
var label: Callable
var light: Callable

## Counters kept by the helpers below so builders and labs can audit budgets.
var solids_added := 0
var labels_added := 0
var lights_added := 0

static var _meshes: Dictionary = {}
static var _paint_material: ShaderMaterial
static var _sign_material: ShaderMaterial
static var _floor_material: ShaderMaterial

## kind -> {"xforms": Array[Transform3D], "custom": PackedColorArray}
var _paint: Dictionary = {}
var _signs: Array[Transform3D] = []
var _sign_cells: PackedColorArray = []
var _floors: Array[Transform3D] = []
var _floor_styles := PackedColorArray()


func add_solid(center: Vector3, size: Vector3, yaw: float, material: Material) -> void:
	solids_added += 1
	if solid.is_valid():
		solid.call(center, size, yaw, material)


func add_visual(kind: StringName, xform: Transform3D, material: Material) -> void:
	if visual.is_valid():
		visual.call(kind, xform, material)


func add_label(text: String, xform: Transform3D, font_size: int, color: Color) -> void:
	labels_added += 1
	if label.is_valid():
		label.call(text, xform, font_size, color)


func add_light(position: Vector3, color: Color, energy: float, range: float) -> bool:
	if not light.is_valid():
		return false
	var placed: bool = light.call(position, color, energy, range)
	if placed:
		lights_added += 1
	return placed


## Palette primitive: `color` is sRGB albedo, `glow` 0..3.5 multiplies it as emission.
func add_paint(kind: StringName, xform: Transform3D, color: Color, finish: int = Finish.MATTE, glow: float = 0.0) -> void:
	if not _paint.has(kind):
		_paint[kind] = {"xforms": [] as Array[Transform3D], "custom": PackedColorArray()}
	var entry: Dictionary = _paint[kind]
	(entry.xforms as Array[Transform3D]).append(xform)
	# Quantised so half-float or 8-bit instance storage keeps the code exact.
	var level := clampi(roundi(glow * 2.0), 0, 7)
	var code := float(finish) + float(level) / 8.0
	var custom: PackedColorArray = entry.custom
	custom.append(Color(color.r, color.g, color.b, code / 8.0))
	entry.custom = custom


## Unit box printed with atlas cells `cell`..`cell + span - 1` (one row) on its
## +Z face; edges and back are a dark board. `glow` 0..1 backlights the print.
func add_sign(xform: Transform3D, cell: int, span: int = 1, glow: float = 0.0) -> void:
	_signs.append(xform)
	var column := cell % SIGN_GRID.x
	var row := cell / SIGN_GRID.x
	_sign_cells.append(Color(float(column) / SIGN_GRID.x, float(row) / SIGN_GRID.y, clampf(glow, 0.0, 1.0), float(span) / SIGN_GRID.x))


## Normalized style channels survive both float and 8-bit instance storage.
## Every venue finish/variant shares one floor draw batch.
func add_floor(xform: Transform3D, venue_kind: int, variant: int) -> void:
	_floors.append(xform)
	_floor_styles.append(Color(float(venue_kind) / 3.0, float(variant) / 2.0, 0.0, 0.0))


## Adds palette, sign and venue-floor batches; returns the batch count.
func flush(parent: Node3D) -> int:
	var added := 0
	for kind: StringName in _paint:
		var entry: Dictionary = _paint[kind]
		parent.add_child(_batch(_mesh(kind), _paint_shared(), entry.xforms, entry.custom))
		added += 1
	if not _signs.is_empty():
		parent.add_child(_batch(_mesh(&"box"), _sign_shared(), _signs, _sign_cells))
		added += 1
	if not _floors.is_empty():
		parent.add_child(_batch(_mesh(&"box"), _floor_shared(), _floors, _floor_styles))
		added += 1
	_floors.clear()
	_floor_styles = PackedColorArray()
	_paint.clear()
	_signs = []
	_sign_cells = PackedColorArray()
	return added


func _batch(mesh: Mesh, material: Material, xforms: Array[Transform3D], custom: PackedColorArray) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = not custom.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = xforms.size()
	for index in xforms.size():
		multimesh.set_instance_transform(index, xforms[index])
		if multimesh.use_custom_data:
			multimesh.set_instance_custom_data(index, custom[index])
	var batch := MultiMeshInstance3D.new()
	batch.name = "KitBatch"
	batch.multimesh = multimesh
	batch.material_override = material
	return batch


static func _mesh(kind: StringName) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: PrimitiveMesh
	match kind:
		&"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 12
			cylinder.rings = 1
			mesh = cylinder
		&"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
		&"ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.38
			ring.outer_radius = 0.5
			ring.rings = 24
			ring.ring_segments = 6
			mesh = ring
		_:
			mesh = BoxMesh.new()
	_meshes[kind] = mesh
	return mesh


static func _paint_shared() -> ShaderMaterial:
	if _paint_material == null:
		_paint_material = ShaderMaterial.new()
		_paint_material.shader = PAINT_SHADER
	return _paint_material


static func _sign_shared() -> ShaderMaterial:
	if _sign_material == null:
		_sign_material = ShaderMaterial.new()
		_sign_material.shader = SIGN_SHADER
		_sign_material.set_shader_parameter("atlas", SIGN_ATLAS)
		_sign_material.set_shader_parameter("grid", Vector2(SIGN_GRID))
	return _sign_material


static func _floor_shared() -> ShaderMaterial:
	if _floor_material == null:
		_floor_material = ShaderMaterial.new()
		_floor_material.shader = FLOOR_SHADER
	return _floor_material
