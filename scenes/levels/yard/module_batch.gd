@tool
extends Node3D

## Draws every copy of a modular art piece listed in `transforms` through one
## MultiMeshInstance3D per source mesh, so a kit module repeated along a wall
## costs one draw call per material instead of one per copy. The batches are
## generated when the node enters the tree (also in the editor) and are never
## saved with the scene; edit `transforms` to move copies.

## Art scene whose MeshInstance3D descendants are batched. Ignored when `mesh` is set.
@export var source: PackedScene
## A single mesh to batch instead of a scene (its own material is used).
@export var mesh: Mesh
## Placement of each copy, relative to this node.
@export var transforms: Array[Transform3D] = []
## Multiplies the albedo of every source material; white keeps the art unchanged.
@export var tint := Color(1, 1, 1, 1)
@export var cast_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# Tinted copies shared by every batch (and every world load) using the same art.
static var _tinted_meshes: Dictionary = {}
static var _tinted_materials: Dictionary = {}

func _ready() -> void:
	if transforms.is_empty():
		return
	if mesh != null:
		_add_batch(mesh, Transform3D.IDENTITY)
		return
	if source == null:
		return
	var art := source.instantiate()
	_collect(art, Transform3D.IDENTITY)
	art.free()

func _collect(node: Node, parent_transform: Transform3D) -> void:
	var local := parent_transform
	var spatial := node as Node3D
	if spatial != null:
		local = parent_transform * spatial.transform
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		_add_batch(instance.mesh, local)
	for child in node.get_children():
		_collect(child, local)

func _add_batch(source_mesh: Mesh, offset: Transform3D) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _tinted_mesh(source_mesh)
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index] * offset)
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multimesh
	batch.cast_shadow = cast_shadow
	add_child(batch)

func _tinted_mesh(source_mesh: Mesh) -> Mesh:
	var array_mesh := source_mesh as ArrayMesh
	if tint == Color(1, 1, 1, 1) or array_mesh == null:
		return source_mesh
	var key := "%d/%s" % [array_mesh.get_instance_id(), tint.to_html()]
	var cached: Mesh = _tinted_meshes.get(key)
	if cached != null:
		return cached
	var copy := array_mesh.duplicate() as ArrayMesh
	for surface in copy.get_surface_count():
		copy.surface_set_material(surface, _tinted_material(copy.surface_get_material(surface)))
	_tinted_meshes[key] = copy
	return copy

func _tinted_material(material: Material) -> Material:
	var base := material as BaseMaterial3D
	if base == null:
		return material
	var key := "%d/%s" % [base.get_instance_id(), tint.to_html()]
	var cached: Material = _tinted_materials.get(key)
	if cached != null:
		return cached
	var copy := base.duplicate() as BaseMaterial3D
	copy.albedo_color = copy.albedo_color * tint
	_tinted_materials[key] = copy
	return copy
