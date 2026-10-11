class_name DepositGeometry
extends RefCounted

## Cigarette vending machine: every removable door has its exact rendered triangle
## collider. The frame, empty trays and backing are separate and survive the last
## payout. (Fruit-machine banks are SlotBankGeometry.)
static func build(rng: RandomNumberGenerator, count: int, bounds: Vector3) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var rows := ceili(float(count) / 3.0)
	var cell := Vector2(bounds.x * 0.9 / 3.0, bounds.y * 0.72 / float(rows))
	var front := bounds.z * 0.53
	var enamel := Color(0.25, 0.3, 0.25)
	for index in count:
		var center := Vector3((float(index % 3) - 1.0) * cell.x, bounds.y * 0.25 - (floorf(float(index) / 3.0) + 0.5) * cell.y, front)
		var triangles := PackedVector3Array()
		var colors := PackedColorArray()
		var shade := enamel.lightened(rng.randf_range(0.0, 0.07))
		_box(triangles, colors, center, Vector3(cell.x * 0.91, cell.y * 0.88, 0.08), shade)
		var lock := center + Vector3(cell.x * 0.34, -cell.y * 0.24, 0.057)
		_box(triangles, colors, lock, Vector3(cell.x * 0.16, cell.y * 0.2, 0.034), Color(0.7, 0.62, 0.42))
		_box(triangles, colors, lock + Vector3(0.0, 0.0, 0.018), Vector3(0.016, cell.y * 0.11, 0.009), Color(0.025, 0.025, 0.025))
		# White cigarettes with brown filters, visible through the vending door.
		_box(triangles, colors, center + Vector3(-cell.x * 0.05, cell.y * 0.12, 0.047), Vector3(cell.x * 0.71, cell.y * 0.4, 0.028), Color(0.025, 0.035, 0.025))
		for cigarette in 6:
			var at := center + Vector3((float(cigarette) - 3.0) * cell.x * 0.1, cell.y * 0.13, 0.076)
			_box(triangles, colors, at, Vector3(cell.x * 0.053, cell.y * 0.25, 0.04), Color(0.84, 0.81, 0.65))
			_box(triangles, colors, at - Vector3(0.0, cell.y * 0.15, 0.0), Vector3(cell.x * 0.053, cell.y * 0.07, 0.04), Color(0.62, 0.29, 0.1))
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
	# Coloured marquee backing behind the lit name sign.
	_box(triangles, colors, Vector3(0.0, bounds.y * 0.39, depth + 0.002), Vector3(bounds.x * 0.86, bounds.y * 0.17, 0.004), PALETTE[0].darkened(0.78))
	return _surface(triangles, colors)

## Visual-only lamps in one mesh: surface 0 opaque bulbs, surface 1 additive
## halos. UV.x is the chase ordinal or phase; UV.y = pattern + 8 * (door + 1),
## with door -1 for the cabinet itself. Halo UV2 spans -1..1 for the falloff.
## Lamps have no colliders, so prying and precision rays are unchanged.
static func lamps(bounds: Vector3, doors: Array[Dictionary]) -> ArrayMesh:
	var cores := SurfaceTool.new()
	cores.begin(Mesh.PRIMITIVE_TRIANGLES)
	var halos := SurfaceTool.new()
	halos.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palette := PALETTE
	var depth := bounds.z * 0.52
	var bulb := minf(bounds.x, bounds.y) * 0.028
	var front := depth + bulb * 0.5 + 0.004
	# Marquee: bulbs chase clockwise around the name sign.
	var left := -bounds.x * 0.45
	var top := bounds.y * 0.485
	var bottom := bounds.y * 0.285
	var ring := PackedVector3Array()
	for n in 13:
		ring.append(Vector3(lerpf(left, -left, float(n) / 12.0), top, front))
	for n in 3:
		ring.append(Vector3(-left, lerpf(top, bottom, float(n + 1) / 4.0), front))
	for n in 13:
		ring.append(Vector3(lerpf(-left, left, float(n) / 12.0), bottom, front))
	for n in 3:
		ring.append(Vector3(left, lerpf(bottom, top, float(n + 1) / 4.0), front))
	for n in ring.size():
		_lamp(cores, halos, ring[n], Vector3.ONE * bulb, palette[2] if n % 2 == 0 else palette[0], n, Lamp.MARQUEE, -1, 2.6)
	# Side rails: pairs of bulbs run up both edges of the cabinet.
	for side in [-1.0, 1.0]:
		for n in 9:
			var at := Vector3(side * bounds.x * 0.48, lerpf(-bounds.y * 0.44, bounds.y * 0.26, float(n) / 8.0), front)
			_lamp(cores, halos, at, Vector3.ONE * bulb, palette[1] if n % 2 == 0 else palette[0], n, Lamp.RAIL, -1, 2.4)
	# Two-tier service candle on the top corner, as on real cabinets.
	var candle := Vector3(bounds.x * 0.07, bounds.y * 0.07, bounds.x * 0.07)
	for tier in 2:
		var at := Vector3(bounds.x * 0.36, bounds.y * 0.5 + candle.y * (0.5 + float(tier)), depth * 0.6)
		_lamp(cores, halos, at, candle, palette[0] if tier == 0 else palette[2], tier, Lamp.CANDLE, -1, 2.2)
	# Neon strip under the sign.
	_lamp(cores, halos, Vector3(0.0, bounds.y * 0.255, front), Vector3(bounds.x * 0.9, bounds.y * 0.012, bulb * 0.5), palette[1], 0, Lamp.STRIP, -1, 1.25)
	for door in doors.size():
		var center: Vector3 = doors[door]["center"]
		var cell: Vector2 = doors[door]["cell"]
		var phase := float(door) / float(maxi(doors.size(), 1))
		# Selection bar under the packs.
		_lamp(cores, null, center + Vector3(-cell.x * 0.04, -cell.y * 0.1, 0.095), Vector3(cell.x * 0.74, cell.y * 0.012, 0.004), palette[0], phase, Lamp.PAYLINE, door, 0.0)
		for side in [-1.0, 1.0]:
			var at := center + Vector3(side * cell.x * 0.3, cell.y * 0.37, 0.04 + bulb * 0.5)
			_lamp(cores, halos, at, Vector3.ONE * bulb, palette[2] if side < 0.0 else palette[0], phase + (0.5 if side > 0.0 else 0.0), Lamp.WIN, door, 2.4)
	var mesh := cores.commit()
	halos.commit(mesh)
	return mesh

enum Lamp { MARQUEE, RAIL, CANDLE, STRIP, PAYLINE, WIN }

const PALETTE: Array[Color] = [Color(0.35, 1.0, 0.5), Color(0.95, 1.0, 0.85), Color(1.0, 0.6, 0.18)]

static func _lamp(cores: SurfaceTool, halos: SurfaceTool, center: Vector3, size: Vector3, color: Color, phase: float, pattern: int, door: int, halo: float) -> void:
	var code := Vector2(phase, float(pattern + 8 * (door + 1)))
	var triangles := PackedVector3Array()
	var colors := PackedColorArray()
	_box(triangles, colors, center, size, color)
	for triangle in range(0, triangles.size(), 3):
		var normal := (triangles[triangle + 2] - triangles[triangle]).cross(triangles[triangle + 1] - triangles[triangle]).normalized()
		for corner in 3:
			cores.set_normal(normal)
			cores.set_color(color)
			cores.set_uv(code)
			cores.add_vertex(triangles[triangle + corner])
	if halos == null or halo <= 0.0:
		return
	var half := Vector2(size.x, size.y) * halo * 0.5 + Vector2.ONE * minf(size.x, size.y) * halo * 0.5
	var z := center.z + size.z * 0.5 + 0.002
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for corner: Vector2 in corners:
		halos.set_normal(Vector3.BACK)
		halos.set_color(color)
		halos.set_uv(code)
		halos.set_uv2(corner)
		halos.add_vertex(Vector3(center.x + corner.x * half.x, center.y + corner.y * half.y, z))

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
