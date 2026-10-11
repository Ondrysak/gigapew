class_name DepositGeometry
extends RefCounted

## Wall cabinets: every removable door has its exact rendered triangle collider.
## The frame, empty trays and backing are separate and survive the last payout.
static func build(rng: RandomNumberGenerator, count: int, bounds: Vector3, resource_id: StringName) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var rows := ceili(float(count) / 3.0)
	var cell := Vector2(bounds.x * 0.9 / 3.0, bounds.y * 0.72 / float(rows))
	var front := bounds.z * 0.53
	var enamel := Color(0.28, 0.12, 0.09) if resource_id == &"gold" else (Color(0.25, 0.3, 0.25) if resource_id == &"crystal" else Color(0.16, 0.12, 0.24))
	for index in count:
		var center := Vector3((float(index % 3) - 1.0) * cell.x, bounds.y * 0.25 - (floorf(float(index) / 3.0) + 0.5) * cell.y, front)
		var triangles := PackedVector3Array()
		var colors := PackedColorArray()
		var shade := enamel.lightened(rng.randf_range(0.0, 0.07))
		_box(triangles, colors, center, Vector3(cell.x * 0.91, cell.y * 0.88, 0.08), shade)
		var lock := center + Vector3(cell.x * 0.34, -cell.y * 0.24, 0.057)
		_box(triangles, colors, lock, Vector3(cell.x * 0.16, cell.y * 0.2, 0.034), Color(0.7, 0.62, 0.42))
		_box(triangles, colors, lock + Vector3(0.0, 0.0, 0.018), Vector3(0.016, cell.y * 0.11, 0.009), Color(0.025, 0.025, 0.025))
		if resource_id == &"crystal":
			# White cigarettes with brown filters, visible through the vending door.
			_box(triangles, colors, center + Vector3(-cell.x * 0.05, cell.y * 0.12, 0.047), Vector3(cell.x * 0.71, cell.y * 0.4, 0.028), Color(0.025, 0.035, 0.025))
			for cigarette in 6:
				var at := center + Vector3((float(cigarette) - 3.0) * cell.x * 0.1, cell.y * 0.13, 0.076)
				_box(triangles, colors, at, Vector3(cell.x * 0.053, cell.y * 0.25, 0.04), Color(0.84, 0.81, 0.65))
				_box(triangles, colors, at - Vector3(0.0, cell.y * 0.15, 0.0), Vector3(cell.x * 0.053, cell.y * 0.07, 0.04), Color(0.62, 0.29, 0.1))
		else:
			_box(triangles, colors, center + Vector3(-cell.x * 0.04, cell.y * 0.1, 0.05), Vector3(cell.x * 0.74, cell.y * 0.38, 0.025), Color(0.025, 0.025, 0.028))
			for reel in 3:
				_box(triangles, colors, center + Vector3((float(reel) - 1.0) * cell.x * 0.23 - cell.x * 0.04, cell.y * 0.1, 0.075), Vector3(cell.x * 0.2, cell.y * 0.32, 0.035), Color(0.84, 0.78, 0.56))
		# Coin slot and payout aperture belong to the door, not the empty tray.
		_box(triangles, colors, center + Vector3(-cell.x * 0.2, -cell.y * 0.25, 0.05), Vector3(cell.x * 0.25, 0.025, 0.026), Color(0.02, 0.02, 0.02))
		var geometry := _surface(triangles, colors)
		geometry["weak_position"] = lock + Vector3(0.0, 0.0, 0.023)
		geometry["weak_radius"] = minf(cell.x, cell.y) * 0.17
		geometry["center"] = center
		geometry["cell"] = cell
		sections.append(geometry)
	return sections

static func housing(bounds: Vector3, count: int) -> Dictionary:
	var triangles := PackedVector3Array()
	var colors := PackedColorArray()
	var dark := Color(0.055, 0.06, 0.055)
	var steel := Color(0.22, 0.24, 0.23)
	var depth := bounds.z * 0.52
	var rows := ceili(float(count) / 3.0)
	var cell := Vector2(bounds.x * 0.9 / 3.0, bounds.y * 0.72 / float(rows))
	_box(triangles, colors, Vector3(0.0, 0.0, 0.04), Vector3(bounds.x, bounds.y, 0.08), dark)
	for side in [-1.0, 1.0]:
		_box(triangles, colors, Vector3(side * bounds.x * 0.48, 0.0, depth * 0.5), Vector3(bounds.x * 0.04, bounds.y, depth), steel)
	_box(triangles, colors, Vector3(0.0, bounds.y * 0.39, depth * 0.5), Vector3(bounds.x * 0.94, bounds.y * 0.22, depth), steel)
	_box(triangles, colors, Vector3(0.0, -bounds.y * 0.47, depth * 0.5), Vector3(bounds.x * 0.94, bounds.y * 0.06, depth), steel)
	for divider in [-0.5, 0.5]:
		_box(triangles, colors, Vector3(divider * cell.x, -bounds.y * 0.11, depth * 0.5), Vector3(0.035, bounds.y * 0.72, depth), steel)
	for row in range(rows + 1):
		_box(triangles, colors, Vector3(0.0, bounds.y * 0.25 - float(row) * cell.y, depth * 0.5), Vector3(bounds.x * 0.92, 0.035, depth), steel)
	return _surface(triangles, colors)

static func _surface(triangles: PackedVector3Array, colors: PackedColorArray) -> Dictionary:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in range(0, triangles.size(), 3):
		var normal := (triangles[triangle + 2] - triangles[triangle]).cross(triangles[triangle + 1] - triangles[triangle]).normalized()
		for corner in 3:
			tool.set_normal(normal)
			tool.set_color(colors[triangle + corner])
			tool.add_vertex(triangles[triangle + corner])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(triangles)
	return {"mesh": tool.commit(), "shape": shape}

static func _box(triangles: PackedVector3Array, colors: PackedColorArray, center: Vector3, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	var points := PackedVector3Array([
		center + Vector3(-half.x, -half.y, -half.z), center + Vector3(half.x, -half.y, -half.z),
		center + Vector3(half.x, half.y, -half.z), center + Vector3(-half.x, half.y, -half.z),
		center + Vector3(-half.x, -half.y, half.z), center + Vector3(half.x, -half.y, half.z),
		center + Vector3(half.x, half.y, half.z), center + Vector3(-half.x, half.y, half.z)])
	for face in [[4, 7, 6, 5], [1, 2, 3, 0], [0, 3, 7, 4], [5, 6, 2, 1], [7, 3, 2, 6], [0, 4, 5, 1]]:
		for index in [face[0], face[1], face[2], face[0], face[2], face[3]]:
			triangles.append(points[index])
			colors.append(color)
