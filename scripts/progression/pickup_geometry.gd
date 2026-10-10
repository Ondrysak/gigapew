class_name PickupGeometry
extends RefCounted

## Built once per field: block silhouettes remain readable without textures.
static func magnet() -> ArrayMesh:
	var tool := _begin()
	var red := Color(1.0, 0.12, 0.2)
	_box(tool, Vector3(-0.21, 0.02, 0.0), Vector3(0.14, 0.38, 0.18), red)
	_box(tool, Vector3(0.21, 0.02, 0.0), Vector3(0.14, 0.38, 0.18), red)
	_box(tool, Vector3(0.0, -0.19, 0.0), Vector3(0.42, 0.14, 0.18), red)
	_box(tool, Vector3(-0.21, 0.25, 0.0), Vector3(0.14, 0.12, 0.18), Color(0.83, 0.96, 1.0))
	_box(tool, Vector3(0.21, 0.25, 0.0), Vector3(0.14, 0.12, 0.18), Color(0.83, 0.96, 1.0))
	# Crossed profiles preserve the horseshoe silhouette from either stage axis.
	_box(tool, Vector3(0.0, 0.02, -0.21), Vector3(0.18, 0.38, 0.14), red)
	_box(tool, Vector3(0.0, 0.02, 0.21), Vector3(0.18, 0.38, 0.14), red)
	_box(tool, Vector3(0.0, -0.19, 0.0), Vector3(0.18, 0.14, 0.42), red)
	_box(tool, Vector3(0.0, 0.25, -0.21), Vector3(0.18, 0.12, 0.14), Color(0.83, 0.96, 1.0))
	_box(tool, Vector3(0.0, 0.25, 0.21), Vector3(0.18, 0.12, 0.14), Color(0.83, 0.96, 1.0))
	return tool.commit()

static func repair() -> ArrayMesh:
	var tool := _begin()
	var red := Color(1.0, 0.2, 0.27)
	_box(tool, Vector3.ZERO, Vector3(0.56, 0.18, 0.18), red)
	_box(tool, Vector3.ZERO, Vector3(0.18, 0.18, 0.56), red)
	_box(tool, Vector3(0.0, 0.18, 0.0), Vector3(0.18, 0.18, 0.18), red)
	_box(tool, Vector3(0.0, -0.18, 0.0), Vector3(0.18, 0.18, 0.18), red)
	return tool.commit()

static func _begin() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool

static func _box(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		tool.set_color(color)
		tool.set_normal(normals[index])
		tool.add_vertex(vertices[index] + center)
