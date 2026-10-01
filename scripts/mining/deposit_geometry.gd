class_name DepositGeometry
extends RefCounted

## Each section is a merged seven-crystal tree (1 + 2 + 4). Its concave
## collider uses the exact triangles, including the spaces between branches.
const SIDES := 6
const BRANCH_DEPTH := 2

static func build(rng: RandomNumberGenerator, count: int, bounds: Vector3) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var phase := rng.randf_range(-0.12, 0.12)
	var layout := rng.randi_range(0, 2)
	for index in count:
		var centre: Vector3
		var direction: Vector3
		if layout == 0:
			# Hollow geode crown, with uneven radial growth.
			var angle := TAU * float(index) / float(count) + phase
			var spread := rng.randf_range(0.88, 1.05)
			centre = Vector3(cos(angle) * 0.34 * bounds.x * spread, sin(angle) * 0.25 * bounds.y * spread, 0.12)
			direction = Vector3(cos(angle) * 0.28, sin(angle) * 0.25, 1.0).normalized()
		elif layout == 1:
			# A winding seam makes the player follow the vein across the wall.
			var along := float(index) / float(count - 1) - 0.5
			var rise := sin(along * TAU * 1.2 + phase)
			centre = Vector3(along * bounds.x * 0.72, rise * bounds.y * 0.21, 0.12)
			direction = Vector3(along * 0.5, rise * 0.22, 1.0).normalized()
		else:
			# Two diverging branches expose a fork rather than another ring.
			var branch := float(index % 2) * 2.0 - 1.0
			var along := floorf(float(index) * 0.5) / maxf(1.0, floorf(float(count - 1) * 0.5))
			centre = Vector3((along - 0.5) * bounds.x * 0.64, branch * (0.16 + 0.12 * along) * bounds.y, 0.12)
			direction = Vector3((along - 0.5) * 0.38, branch * 0.32, 1.0).normalized()
		centre += Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06), 0.0)
		var length := bounds.z * rng.randf_range(0.66, 0.82)
		var radius := minf(bounds.x * 0.12, bounds.y * 0.22) * rng.randf_range(0.86, 1.0)
		var triangles := PackedVector3Array()
		_branch(triangles, rng, centre, direction, length, radius, BRANCH_DEPTH, bounds)
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle in range(0, triangles.size(), 3):
			# Godot's front faces wind clockwise when viewed from outside.
			var normal := (triangles[triangle + 2] - triangles[triangle]).cross(triangles[triangle + 1] - triangles[triangle]).normalized()
			for corner in 3:
				tool.set_normal(normal)
				tool.add_vertex(triangles[triangle + corner])
		var mesh := tool.commit()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(triangles)
		sections.append({"mesh": mesh, "shape": shape, "weak_position": _bounded(centre + direction * length, bounds), "weak_radius": radius * 0.58})
	return sections

static func _branch(triangles: PackedVector3Array, rng: RandomNumberGenerator, start: Vector3, direction: Vector3, length: float, radius: float, depth: int, bounds: Vector3) -> void:
	var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var right := reference.cross(direction).normalized()
	var up := direction.cross(right).normalized()
	var roll := rng.randf() * TAU
	var base := PackedVector3Array()
	var shoulder := PackedVector3Array()
	for side in SIDES:
		var angle := TAU * float(side) / float(SIDES) + roll
		var radial := (right * cos(angle) + up * sin(angle)) * radius
		base.append(_bounded(start + radial * 0.68, bounds))
		shoulder.append(_bounded(start + direction * length * 0.6 + radial, bounds))
	var tip := _bounded(start + direction * length, bounds)
	var back := _bounded(start - direction * length * 0.1, bounds)
	for side in SIDES:
		var next := (side + 1) % SIDES
		_triangle(triangles, base[side], shoulder[side], shoulder[next])
		_triangle(triangles, base[side], shoulder[next], base[next])
		_triangle(triangles, shoulder[side], tip, shoulder[next])
		_triangle(triangles, base[next], back, base[side])
	if depth <= 0:
		return
	for child in 2:
		var angle := roll + float(child) * PI + rng.randf_range(-0.4, 0.4)
		var radial := right * cos(angle) + up * sin(angle)
		var child_start := start + direction * length * 0.45 + radial * radius * 0.5
		var child_direction := (direction * 0.72 + radial * 0.68).normalized()
		_branch(triangles, rng, child_start, child_direction, length * 0.48, radius * 0.43, depth - 1, bounds)

static func _bounded(point: Vector3, bounds: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -bounds.x * 0.5, bounds.x * 0.5), clampf(point.y, -bounds.y * 0.5, bounds.y * 0.5), clampf(point.z, -0.12, bounds.z))

static func _triangle(triangles: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 0.0000001:
		return
	triangles.append(a)
	triangles.append(b)
	triangles.append(c)
