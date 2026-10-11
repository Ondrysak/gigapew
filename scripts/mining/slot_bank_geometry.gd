class_name SlotBankGeometry
extends RefCounted

## A bank of three upright fruit machines modelled on a Czech pub cabinet: a
## backlit top glass over three reels, a slanted lower glass with the small risk
## game, a chrome button deck and a lower cabinet with the cash-box door.
## Pryable doors take the natural slots in SLOTS order; every door's rendered
## triangles are its exact collider and its chrome key lock is the weak spot.
## Reels, lights, LEDs, mechanism and the plinth are visual only (no colliders).
## Shaders: slot_cabinet (housing + doors), slot_reels, slot_lights (+ halo),
## all driven by slot_machine.gdshaderinc. Art: tools/automat_art.py.

const TOP_ASPECT := 1.15
const LOW_ASPECT := 3.6
## Panel layouts (u right, v down), mirrored from tools/automat_art.py.
const TOP_REELS: Array[Vector4] = [Vector4(0.245, 0.485, 0.115, 0.22), Vector4(0.375, 0.485, 0.115, 0.22), Vector4(0.505, 0.485, 0.115, 0.22)]
const LOW_REELS: Array[Vector4] = [Vector4(0.19, 0.24, 0.075, 0.46), Vector4(0.275, 0.24, 0.075, 0.46), Vector4(0.36, 0.24, 0.075, 0.46)]
## LED windows as (u0, v0, u1, v1): credit, bet, bonus; then the coin acceptor.
const TOP_LEDS: Array[Vector4] = [Vector4(0.30, 0.835, 0.66, 0.955), Vector4(0.045, 0.86, 0.215, 0.94), Vector4(0.745, 0.86, 0.945, 0.94)]
const TOP_COIN := Vector4(0.80, 0.035, 0.955, 0.10)
## Theme atlas regions (glass_<theme>.png).
const TOP_UV := Rect2(0.0, 0.0005, 1.0, 0.499)
const LOW_UV := Rect2(0.0, 0.5005, 1.0, 0.249)
const BADGE_UV := Rect2(0.0, 0.8125, 0.375, 0.0625)
const STICKER_UV := Rect2(0.375, 0.8125, 0.25, 0.125)
const PLATE_UV := Rect2(0.625, 0.8125, 0.375, 0.046875)
## Door slots in prying order as (part, cabinet): top glass, lower glass, cash door.
const SLOTS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 0), Vector2i(2, 2)]
const TILT := 0.244 # lower glass leans back 14 degrees
const STOPS := 16.0 # symbols around a reel

## UV2.x of slot_cabinet.gdshader surfaces.
enum Surface { PAINT, CHROME, TOP_GLASS, LOW_GLASS, DECAL, MATTE, TUBE }
## UV2.x of slot_lights.gdshader surfaces.
enum Light { BULB, BUTTON, LED, COIN }

const BLACK := Color(0.035, 0.035, 0.04)
const INTERIOR := Color(0.03, 0.03, 0.032)
const GOLD := Color(1.0, 0.78, 0.38)
const BUTTON_COLORS: Array[Color] = [Color(1.0, 0.16, 0.1), Color(1.0, 0.16, 0.1), Color(1.0, 0.97, 0.9), Color(1.0, 0.97, 0.9), Color(1.0, 0.97, 0.9), Color(0.25, 0.5, 1.0), Color(1.0, 0.97, 0.9), Color(0.25, 0.5, 1.0)]

## Triangle soup with the attributes the slot shaders read; `solid` triangles
## also become collision faces. Points pass through `xform` as they are added.
class Part:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var faces := PackedVector3Array()
	var xform := Transform3D.IDENTITY
	var kind := 0
	var code := 0.0
	var color := Color.BLACK
	var solid := false

	func paint(p_kind: int, p_color: Color, p_solid: bool) -> void:
		kind = p_kind
		color = p_color
		solid = p_solid

	## Front face is clockwise as seen from the outside (Godot's convention).
	func tri(a: Vector3, b: Vector3, c: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		a = xform * a
		b = xform * b
		c = xform * c
		var normal := (c - a).cross(b - a).normalized()
		var attributes := Vector2(kind, code)
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		uvs.append(ua)
		uvs.append(ub)
		uvs.append(uc)
		for corner in 3:
			normals.append(normal)
			colors.append(color)
			uv2s.append(attributes)
		if solid:
			faces.append(a)
			faces.append(b)
			faces.append(c)

	## a bottom-left, b top-left, c top-right, d bottom-right as seen from the front.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv := Rect2(0, 0, 1, 1)) -> void:
		tri(a, b, c, Vector2(uv.position.x, uv.end.y), uv.position, Vector2(uv.end.x, uv.position.y))
		tri(a, c, d, Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.end)

	## Two-sided-safe triangle: flips the winding so its normal faces `outward`.
	func tri_facing(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		if (c - a).cross(b - a).dot(outward) < 0.0:
			tri(a, c, b, ua, uc, ub)
		else:
			tri(a, b, c, ua, ub, uc)

	func box(center: Vector3, size: Vector3, uv := Rect2(0, 0, 1, 1)) -> void:
		var h := size * 0.5
		var lbf := center + Vector3(-h.x, -h.y, h.z)
		var ltf := center + Vector3(-h.x, h.y, h.z)
		var rtf := center + Vector3(h.x, h.y, h.z)
		var rbf := center + Vector3(h.x, -h.y, h.z)
		var lbb := center + Vector3(-h.x, -h.y, -h.z)
		var ltb := center + Vector3(-h.x, h.y, -h.z)
		var rtb := center + Vector3(h.x, h.y, -h.z)
		var rbb := center + Vector3(h.x, -h.y, -h.z)
		quad(lbf, ltf, rtf, rbf, uv)
		quad(rbb, rtb, ltb, lbb, uv)
		quad(rbf, rtf, rtb, rbb, uv)
		quad(lbb, ltb, ltf, lbf, uv)
		quad(ltf, ltb, rtb, rtf, uv)
		quad(lbb, lbf, rbf, rbb, uv)

	## Box spanning two corners (any order).
	func span(a: Vector3, b: Vector3) -> void:
		box((a + b) * 0.5, (b - a).abs())

	## Extrudes a simple (z, y) profile polygon from x0 to x1.
	func prism_x(x0: float, x1: float, profile: PackedVector2Array) -> void:
		var area := 0.0
		for i in profile.size():
			var p := profile[i]
			var q := profile[(i + 1) % profile.size()]
			area += p.x * q.y - q.x * p.y
		var winding := 1.0 if area > 0.0 else -1.0
		var cap := Geometry2D.triangulate_polygon(profile)
		for i in range(0, cap.size(), 3):
			var a := profile[cap[i]]
			var b := profile[cap[i + 1]]
			var c := profile[cap[i + 2]]
			tri_facing(Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x1, c.y, c.x), Vector3.RIGHT)
			tri_facing(Vector3(x0, a.y, a.x), Vector3(x0, b.y, b.x), Vector3(x0, c.y, c.x), Vector3.LEFT)
		for i in profile.size():
			var p := profile[i]
			var q := profile[(i + 1) % profile.size()]
			var edge := q - p
			var outward := Vector3(0.0, -edge.x, edge.y) * winding
			var a := Vector3(x0, p.y, p.x)
			var b := Vector3(x1, p.y, p.x)
			var c := Vector3(x1, q.y, q.x)
			var d := Vector3(x0, q.y, q.x)
			tri_facing(a, b, c, outward)
			tri_facing(a, c, d, outward)

	## Closed n-gon cylinder along `axis`; the front cap (at +axis) maps `uv` as a disc.
	func cylinder(center: Vector3, axis: Vector3, radius: float, length: float, sides: int, uv := Rect2(0, 0, 1, 1)) -> void:
		var w := axis.normalized()
		var u := (Vector3.UP if absf(w.y) < 0.9 else Vector3.RIGHT).cross(w).normalized()
		var v := w.cross(u)
		var front := center + w * length * 0.5
		var back := center - w * length * 0.5
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var r0 := (u * cos(a0) + v * sin(a0)) * radius
			var r1 := (u * cos(a1) + v * sin(a1)) * radius
			var mid := (r0 + r1).normalized()
			var c := uv.get_center()
			var half := uv.size * 0.5
			tri_facing(back + r0, front + r0, front + r1, mid, c, c, c)
			tri_facing(back + r0, front + r1, back + r1, mid, c, c, c)
			tri_facing(front, front + r0, front + r1, w, c, c + Vector2(cos(a0), -sin(a0)) * half, c + Vector2(cos(a1), -sin(a1)) * half)
			tri_facing(back, back + r1, back + r0, -w, c, c, c)

	func commit(mesh: ArrayMesh = null) -> ArrayMesh:
		if mesh == null:
			mesh = ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

	func shape() -> ConcavePolygonShape3D:
		var result := ConcavePolygonShape3D.new()
		result.set_faces(faces)
		return result

## Builds the bank. `count` doors take SLOTS in order; one rng draw per door
## (same order and count as every other machine) tints its paint.
## Returns {"doors": Array[Dictionary], "housing": {"mesh", "shape"}, "reels": ArrayMesh, "lights": ArrayMesh}.
## Each door: mesh, shape, weak_position, weak_radius, hinge, swing, pull, cabinet.
static func build(rng: RandomNumberGenerator, count: int, bounds: Vector3) -> Dictionary:
	var lay := _layout(bounds)
	var doors: Array[Dictionary] = []
	var cash := [false, false, false]
	for index in count:
		var slot := SLOTS[index]
		var tint := rng.randf_range(0.0, 0.07)
		var part := Part.new()
		part.code = float(slot.y + 4 * (index + 1))
		var door: Dictionary
		match slot.x:
			0:
				door = _top_door(part, lay, slot.y, tint)
			1:
				door = _low_door(part, lay, slot.y, tint)
			_:
				door = _cash_door(part, lay, slot.y, tint)
				cash[slot.y] = true
		door["mesh"] = part.commit()
		door["shape"] = part.shape()
		door["cabinet"] = slot.y
		door["weak_radius"] = bounds.y * 0.04
		doors.append(door)
	var housing := Part.new()
	var reels := Part.new()
	var lights := Part.new()
	var halos := Part.new()
	for cabinet in 3:
		housing.code = float(cabinet)
		_housing(housing, lay, cabinet, cash[cabinet])
		_reels(reels, lay, cabinet)
		_lights(lights, halos, lay, cabinet)
	var light_mesh := lights.commit()
	halos.commit(light_mesh)
	return {"doors": doors, "housing": {"mesh": housing.commit(), "shape": housing.shape()}, "reels": reels.commit(), "lights": light_mesh}

static func _layout(bounds: Vector3) -> Dictionary:
	var lay := {}
	var s := clampf(bounds.y / 2.6, 0.7, 1.15)
	var pitch := bounds.x / 3.0
	var wc := pitch - clampf(bounds.x * 0.006, 0.012, 0.03)
	var h := bounds.y
	var y0 := -h * 0.5
	lay["s"] = s
	lay["pitch"] = pitch
	lay["wc"] = wc
	lay["st"] = 0.024 * s
	lay["zf"] = bounds.z * 0.5
	lay["y0"] = y0
	lay["deck_bottom"] = y0 + h * 0.29
	lay["deck_top"] = y0 + h * 0.34
	lay["box_bottom"] = y0 + h * 0.49
	lay["box_top"] = y0 + h * 0.94
	lay["cap"] = 0.022 * s
	var df := clampf(wc * 0.03, 0.02, 0.045)
	var ls := df * 2.2
	var margin := 0.02 * s
	lay["df"] = df
	lay["ls"] = ls
	lay["dt"] = 0.03 * s
	lay["margin"] = margin
	var inner := wc - 2.0 * float(lay["st"]) - 0.024
	# Top glass keeps its art aspect; spare height becomes black header above it.
	var gw_max := inner - df - ls
	var gh_max := float(lay["box_top"]) - float(lay["cap"]) - float(lay["box_bottom"]) - 2.0 * margin - 2.0 * df
	var gw := minf(gw_max, gh_max * TOP_ASPECT)
	var gh := gw / TOP_ASPECT
	var door_w := gw + df + ls
	var gx0 := -door_w * 0.5 + df
	var gy0 := float(lay["box_bottom"]) + margin + df
	lay["glass"] = Rect2(gx0, gy0, gw, gh)
	# Lower glass in panel space: x across, y down the slope from its top edge (negative).
	var slope := (float(lay["box_bottom"]) - float(lay["deck_top"])) / cos(TILT)
	lay["slope"] = slope
	var lgh_max := slope - 2.0 * margin - 2.0 * df
	var lgw := minf(gw_max, lgh_max * LOW_ASPECT)
	var lgh := lgw / LOW_ASPECT
	var low_w := lgw + df + ls
	lay["low_glass"] = Rect2(-low_w * 0.5 + df, -slope * 0.5 - lgh * 0.5, lgw, lgh)
	lay["z_low"] = float(lay["zf"]) + slope * sin(TILT)
	lay["z_deck"] = float(lay["z_low"]) + 0.12 * s
	# Cash door below the maker badge.
	var cw := minf(wc * 0.74, inner - 0.04)
	lay["cash"] = Rect2(-cw * 0.5, y0 + h * 0.03, cw, float(lay["deck_bottom"]) - h * 0.085 - (y0 + h * 0.03))
	lay["cdt"] = 0.025 * s
	return lay

static func _center(lay: Dictionary, cabinet: int) -> float:
	return (float(cabinet) - 1.0) * float(lay["pitch"])

## Transform of the slanted lower panel: origin at its top edge centre, +y up the slope.
static func _low_xform(lay: Dictionary, cabinet: int) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -TILT), Vector3(_center(lay, cabinet), float(lay["box_bottom"]), float(lay["zf"])))

## Chrome key lock: escutcheon, cylinder and keyhole. Returns the weak spot.
static func _lock(part: Part, at: Vector3, s: float, width: float) -> Vector3:
	var color := part.color
	part.paint(Surface.CHROME, Color.WHITE, true)
	part.box(at + Vector3(0.0, 0.0, 0.004), Vector3(width, 0.085 * s, 0.008))
	part.cylinder(at + Vector3(0.0, 0.0, 0.016), Vector3.BACK, 0.017 * s, 0.016, 12)
	part.paint(Surface.MATTE, Color(0.01, 0.01, 0.01), true)
	part.box(at + Vector3(0.0, -0.002 * s, 0.0245), Vector3(0.0045 * s, 0.017 * s, 0.002))
	part.color = color
	return at + Vector3(0.0, 0.0, 0.025)

## Black door frame around a glass panel in the part's current transform.
static func _glass_door(part: Part, glass: Rect2, df: float, ls: float, dt: float, z: float, kind: int, uv: Rect2, paint: Color) -> void:
	var x0 := glass.position.x - df
	var x1 := glass.end.x + ls
	var y0 := glass.position.y - df
	var y1 := glass.end.y + df
	part.paint(Surface.PAINT, paint, true)
	part.span(Vector3(x0, y0, z), Vector3(glass.position.x, y1, z + dt))
	part.span(Vector3(glass.end.x, y0, z), Vector3(x1, y1, z + dt))
	part.span(Vector3(glass.position.x, y0, z), Vector3(glass.end.x, glass.position.y, z + dt))
	part.span(Vector3(glass.position.x, glass.end.y, z), Vector3(glass.end.x, y1, z + dt))
	# Gold bead around the glass, as on the real cabinet.
	var bead := df * 0.22
	part.paint(Surface.CHROME, GOLD, true)
	part.span(Vector3(glass.position.x - bead, glass.position.y - bead, z + dt), Vector3(glass.end.x + bead, glass.position.y, z + dt + 0.003))
	part.span(Vector3(glass.position.x - bead, glass.end.y, z + dt), Vector3(glass.end.x + bead, glass.end.y + bead, z + dt + 0.003))
	part.span(Vector3(glass.position.x - bead, glass.position.y, z + dt), Vector3(glass.position.x, glass.end.y, z + dt + 0.003))
	part.span(Vector3(glass.end.x, glass.position.y, z + dt), Vector3(glass.end.x + bead, glass.end.y, z + dt + 0.003))
	part.paint(kind, Color.WHITE, true)
	var gz := z + dt - 0.005
	part.quad(Vector3(glass.position.x, glass.position.y, gz), Vector3(glass.position.x, glass.end.y, gz), Vector3(glass.end.x, glass.end.y, gz), Vector3(glass.end.x, glass.position.y, gz), uv)

static func _top_door(part: Part, lay: Dictionary, cabinet: int, tint: float) -> Dictionary:
	var s := float(lay["s"])
	var glass: Rect2 = lay["glass"]
	glass.position.x += _center(lay, cabinet)
	var z := float(lay["zf"])
	var dt := float(lay["dt"])
	var df := float(lay["df"])
	var ls := float(lay["ls"])
	_glass_door(part, glass, df, ls, dt, z, Surface.TOP_GLASS, TOP_UV, BLACK.lightened(tint))
	var lock := Vector3(glass.end.x + ls * 0.5, glass.position.y + glass.size.y * 0.42, z + dt)
	var weak := _lock(part, lock, s, minf(ls * 0.75, 0.05 * s))
	# Hinged on the left: the latch side swings out.
	return {"weak_position": weak, "hinge": Vector3(glass.position.x - df, glass.get_center().y, z), "swing": -0.12, "pull": 0.03}

static func _low_door(part: Part, lay: Dictionary, cabinet: int, tint: float) -> Dictionary:
	var s := float(lay["s"])
	var glass: Rect2 = lay["low_glass"]
	var dt := float(lay["dt"])
	var df := float(lay["df"])
	var ls := float(lay["ls"])
	part.xform = _low_xform(lay, cabinet)
	_glass_door(part, glass, df, ls, dt, 0.0, Surface.LOW_GLASS, LOW_UV, BLACK.lightened(tint))
	var lock := Vector3(glass.end.x + ls * 0.5, glass.get_center().y, dt)
	var weak: Vector3 = part.xform * _lock(part, lock, s * 0.8, minf(ls * 0.75, 0.05 * s))
	var hinge: Vector3 = part.xform * Vector3(glass.position.x - df, glass.get_center().y, 0.0)
	part.xform = Transform3D.IDENTITY
	return {"weak_position": weak, "hinge": hinge, "swing": -0.12, "pull": 0.03}

static func _cash_door(part: Part, lay: Dictionary, cabinet: int, tint: float) -> Dictionary:
	var s := float(lay["s"])
	var rect: Rect2 = lay["cash"]
	rect.position.x += _center(lay, cabinet)
	var z := float(lay["zf"])
	var t := float(lay["cdt"])
	var paint := BLACK.lightened(tint)
	part.paint(Surface.PAINT, paint, true)
	part.span(Vector3(rect.position.x, rect.position.y, z), Vector3(rect.end.x, rect.end.y, z + t))
	# Raised inner panel with a chrome pin-stripe.
	var inset := rect.grow(-0.045 * s)
	part.paint(Surface.PAINT, paint.lightened(0.04), true)
	part.span(Vector3(inset.position.x, inset.position.y, z + t), Vector3(inset.end.x, inset.end.y, z + t + 0.006))
	part.paint(Surface.CHROME, Color.WHITE, true)
	var stripe := 0.005 * s
	var zs := z + t + 0.006
	part.span(Vector3(inset.position.x, inset.end.y - stripe, zs), Vector3(inset.end.x, inset.end.y, zs + 0.002))
	part.span(Vector3(inset.position.x, inset.position.y, zs), Vector3(inset.end.x, inset.position.y + stripe, zs + 0.002))
	part.span(Vector3(inset.position.x, inset.position.y, zs), Vector3(inset.position.x + stripe, inset.end.y, zs + 0.002))
	part.span(Vector3(inset.end.x - stripe, inset.position.y, zs), Vector3(inset.end.x, inset.end.y, zs + 0.002))
	# POKLADNA plate, the prying sticker and a recessed pull.
	var front := zs + 0.0025
	var plate := Vector2(minf(inset.size.x * 0.5, 0.42 * s), 0.0)
	plate.y = plate.x * PLATE_UV.size.y * 2.0 / PLATE_UV.size.x
	var plate_at := Vector2(inset.get_center().x, inset.end.y - 0.05 * s - plate.y * 0.5)
	part.paint(Surface.DECAL, Color.WHITE, true)
	part.quad(Vector3(plate_at.x - plate.x * 0.5, plate_at.y - plate.y * 0.5, front), Vector3(plate_at.x - plate.x * 0.5, plate_at.y + plate.y * 0.5, front), Vector3(plate_at.x + plate.x * 0.5, plate_at.y + plate.y * 0.5, front), Vector3(plate_at.x + plate.x * 0.5, plate_at.y - plate.y * 0.5, front), PLATE_UV)
	var sticker := minf(inset.size.y * 0.42, 0.2 * s)
	var sticker_at := Vector2(inset.end.x - 0.04 * s - sticker * 0.5, inset.position.y + 0.04 * s + sticker * 0.5)
	part.quad(Vector3(sticker_at.x - sticker * 0.5, sticker_at.y - sticker * 0.5, front), Vector3(sticker_at.x - sticker * 0.5, sticker_at.y + sticker * 0.5, front), Vector3(sticker_at.x + sticker * 0.5, sticker_at.y + sticker * 0.5, front), Vector3(sticker_at.x + sticker * 0.5, sticker_at.y - sticker * 0.5, front), STICKER_UV)
	part.paint(Surface.CHROME, Color.WHITE, true)
	var pull := Vector3(inset.get_center().x, inset.get_center().y - 0.02 * s, zs)
	part.span(pull + Vector3(-0.12 * s, -0.012 * s, 0.0), pull + Vector3(0.12 * s, 0.012 * s, 0.018))
	var lock := Vector3(rect.position.x + 0.075 * s, rect.end.y - 0.07 * s, zs)
	var weak := _lock(part, lock, s, 0.05 * s)
	# Hinged on the right: the lock side swings out.
	return {"weak_position": weak, "hinge": Vector3(rect.end.x, rect.get_center().y, z), "swing": 0.12, "pull": 0.025}

## Cabinet shell (solid) plus visual-only interior, trims, badge and plinth.
static func _housing(part: Part, lay: Dictionary, cabinet: int, cash_door: bool) -> void:
	var s := float(lay["s"])
	var xc := _center(lay, cabinet)
	var wc := float(lay["wc"])
	var st := float(lay["st"])
	var zf := float(lay["zf"])
	var y0 := float(lay["y0"])
	var deck_bottom := float(lay["deck_bottom"])
	var deck_top := float(lay["deck_top"])
	var box_bottom := float(lay["box_bottom"])
	var box_top := float(lay["box_top"])
	var cap := float(lay["cap"])
	var z_low := float(lay["z_low"])
	var z_deck := float(lay["z_deck"])
	var x0 := xc - wc * 0.5
	var x1 := xc + wc * 0.5
	var ix0 := x0 + st
	var ix1 := x1 - st
	var back := 0.03
	part.paint(Surface.PAINT, BLACK, true)
	# Shell: back, sides following the cabinet silhouette, top cap.
	part.span(Vector3(x0, y0, 0.0), Vector3(x1, box_top, back))
	var profile := PackedVector2Array([Vector2(back, y0), Vector2(zf, y0), Vector2(zf, deck_bottom), Vector2(z_deck, deck_bottom),
		Vector2(z_deck, deck_top - 0.035 * s), Vector2(z_low, deck_top), Vector2(zf, box_bottom), Vector2(zf, box_top), Vector2(back, box_top)])
	part.prism_x(x0, ix0, profile)
	part.prism_x(ix1, x1, profile)
	part.span(Vector3(x0, box_top - cap, back), Vector3(x1, box_top, zf + 0.012))
	# Top box front frame around the glass opening, and the dark reel bay behind it.
	var glass: Rect2 = lay["glass"]
	glass.position.x += xc
	var bay := 0.0
	for reel in TOP_REELS:
		bay = maxf(bay, _reel_radius(reel.w * glass.size.y, 2.6) * 1.05 + 0.06)
	_framed_bay(part, Rect2(ix0, box_bottom, ix1 - ix0, box_top - cap - box_bottom), glass, zf, bay, s, true)
	# Display boards and the coin mech behind their glass windows.
	part.paint(Surface.MATTE, Color(0.012, 0.01, 0.01), false)
	var windows: Array[Vector4] = TOP_LEDS.duplicate()
	windows.append(TOP_COIN)
	for window in windows:
		var a := Vector2(glass.position.x + window.x * glass.size.x, glass.end.y - window.w * glass.size.y)
		var b := Vector2(glass.position.x + window.z * glass.size.x, glass.end.y - window.y * glass.size.y)
		part.span(Vector3(a.x - 0.02 * s, a.y - 0.02 * s, zf - 0.03), Vector3(b.x + 0.02 * s, b.y + 0.02 * s, zf + 0.001))
	# Button deck: a chrome-fronted ledge with a slanted top.
	part.paint(Surface.PAINT, BLACK, true)
	part.prism_x(ix0, ix1, PackedVector2Array([Vector2(zf, deck_bottom), Vector2(z_deck, deck_bottom), Vector2(z_deck, deck_top - 0.035 * s),
		Vector2(z_low, deck_top), Vector2(zf, deck_top)]))
	part.paint(Surface.CHROME, Color.WHITE, true)
	part.span(Vector3(ix0, deck_bottom + 0.004, z_deck), Vector3(ix1, deck_top - 0.035 * s - 0.004, z_deck + 0.008))
	part.span(Vector3(ix0, deck_bottom - 0.006 * s, zf), Vector3(ix1, deck_bottom, z_deck + 0.008))
	part.paint(Surface.CHROME, Color.WHITE, false)
	for index in 8:
		var at := _button_at(lay, cabinet, index)
		part.cylinder(at.origin, at.basis.z, _button_radius(lay) * 1.25, 0.012, 16)
	# Lower slanted panel: frame around its glass and the small reel bay behind.
	part.xform = _low_xform(lay, cabinet)
	var slope := float(lay["slope"])
	var low: Rect2 = lay["low_glass"]
	var low_bay := 0.0
	for reel in LOW_REELS:
		low_bay = maxf(low_bay, _reel_radius(reel.w * low.size.y, 2.4) * 1.05 + 0.05)
	_framed_bay(part, Rect2(ix0 - xc, -slope, ix1 - ix0, slope), low, 0.0, low_bay, s, true)
	part.xform = Transform3D.IDENTITY
	# Lower cabinet front around the cash door (or a blank panel), badge above.
	var cash: Rect2 = lay["cash"]
	cash.position.x += xc
	part.paint(Surface.PAINT, BLACK, true)
	if cash_door:
		_framed_bay(part, Rect2(ix0, y0, ix1 - ix0, deck_bottom - y0), cash, zf, 0.3 * s, s, false)
		# Empty steel cash box on the bay floor.
		part.paint(Surface.PAINT, Color(0.32, 0.33, 0.35), false)
		var box := Vector3(cash.size.x * 0.7, cash.size.y * 0.42, minf(0.24 * s, zf - 0.12))
		var floor_y := cash.position.y
		var zb := zf - 0.04 - box.z
		var bx := cash.get_center().x
		var wall := 0.008
		part.span(Vector3(bx - box.x * 0.5, floor_y, zb), Vector3(bx + box.x * 0.5, floor_y + wall, zb + box.z))
		part.span(Vector3(bx - box.x * 0.5, floor_y, zb), Vector3(bx - box.x * 0.5 + wall, floor_y + box.y, zb + box.z))
		part.span(Vector3(bx + box.x * 0.5 - wall, floor_y, zb), Vector3(bx + box.x * 0.5, floor_y + box.y, zb + box.z))
		part.span(Vector3(bx - box.x * 0.5, floor_y, zb), Vector3(bx + box.x * 0.5, floor_y + box.y, zb + wall))
		part.span(Vector3(bx - box.x * 0.5, floor_y, zb + box.z - wall), Vector3(bx + box.x * 0.5, floor_y + box.y * 0.8, zb + box.z))
	else:
		part.span(Vector3(ix0, y0, zf - 0.025), Vector3(ix1, deck_bottom, zf))
		# A screwed-shut service panel where no cash door is fitted.
		part.paint(Surface.MATTE, Color(0.01, 0.01, 0.01), false)
		var seam := cash.grow(0.004)
		part.span(Vector3(seam.position.x, seam.position.y, zf), Vector3(seam.end.x, seam.position.y + 0.004, zf + 0.002))
		part.span(Vector3(seam.position.x, seam.end.y - 0.004, zf), Vector3(seam.end.x, seam.end.y, zf + 0.002))
		part.span(Vector3(seam.position.x, seam.position.y, zf), Vector3(seam.position.x + 0.004, seam.end.y, zf + 0.002))
		part.span(Vector3(seam.end.x - 0.004, seam.position.y, zf), Vector3(seam.end.x, seam.end.y, zf + 0.002))
	part.paint(Surface.DECAL, Color.WHITE, false)
	var badge_w := minf(wc * 0.3, 0.3 * s)
	var badge_h := badge_w * BADGE_UV.size.y * 2.0 / BADGE_UV.size.x
	var badge_y := (cash.end.y + deck_bottom) * 0.5
	part.quad(Vector3(xc - badge_w * 0.5, badge_y - badge_h * 0.5, zf + 0.003), Vector3(xc - badge_w * 0.5, badge_y + badge_h * 0.5, zf + 0.003),
		Vector3(xc + badge_w * 0.5, badge_y + badge_h * 0.5, zf + 0.003), Vector3(xc + badge_w * 0.5, badge_y - badge_h * 0.5, zf + 0.003), BADGE_UV)
	# Chrome side trims on the straight front edges.
	part.paint(Surface.CHROME, Color.WHITE, false)
	for x in [x0, ix1]:
		part.span(Vector3(x - 0.001, box_bottom, zf - 0.006), Vector3(x + st + 0.001, box_top, zf + 0.008))
		part.span(Vector3(x - 0.001, y0, zf - 0.006), Vector3(x + st + 0.001, deck_bottom, zf + 0.008))
	part.span(Vector3(x0, box_top - cap, zf + 0.004), Vector3(x1, box_top - cap + 0.008 * s, zf + 0.016))
	# Two-tier service candle seat on the top box.
	var candle := _candle_at(lay, cabinet)
	var r := 0.036 * s
	part.cylinder(candle + Vector3(0.0, 0.006 * s, 0.0), Vector3.UP, r * 1.15, 0.012 * s, 12)
	part.cylinder(candle + Vector3(0.0, 0.07 * s, 0.0), Vector3.UP, r * 1.05, 0.008 * s, 12)
	part.cylinder(candle + Vector3(0.0, 0.133 * s, 0.0), Vector3.UP, r * 0.9, 0.012 * s, 12)
	# Plinth down to the floor (visual only; whatever is below the floor is hidden).
	part.paint(Surface.MATTE, Color(0.015, 0.015, 0.017), false)
	part.span(Vector3(x0 + 0.01, y0 - 0.6, back), Vector3(x1 - 0.01, y0, zf - 0.02))
	part.paint(Surface.CHROME, Color(0.55, 0.55, 0.58), false)
	part.span(Vector3(x0 + 0.01, y0 - 0.006, zf - 0.02), Vector3(x1 - 0.01, y0, zf + 0.002))

## Front frame around `opening` inside `face`, plus a dark recess `depth` deep
## (with dead backlight tubes and a loom when `fittings`).
static func _framed_bay(part: Part, face: Rect2, opening: Rect2, z: float, depth: float, s: float, fittings: bool) -> void:
	var t := 0.025
	part.paint(Surface.PAINT, BLACK, true)
	part.span(Vector3(face.position.x, face.position.y, z - t), Vector3(opening.position.x, face.end.y, z))
	part.span(Vector3(opening.end.x, face.position.y, z - t), Vector3(face.end.x, face.end.y, z))
	part.span(Vector3(opening.position.x, face.position.y, z - t), Vector3(opening.end.x, opening.position.y, z))
	part.span(Vector3(opening.position.x, opening.end.y, z - t), Vector3(opening.end.x, face.end.y, z))
	part.paint(Surface.MATTE, INTERIOR, true)
	var inner := z - t
	var rear := z - depth
	part.span(Vector3(opening.position.x - 0.01, opening.position.y - 0.01, rear - 0.02), Vector3(opening.end.x + 0.01, opening.end.y + 0.01, rear))
	part.span(Vector3(opening.position.x - 0.01, opening.position.y, rear), Vector3(opening.position.x, opening.end.y, inner))
	part.span(Vector3(opening.end.x, opening.position.y, rear), Vector3(opening.end.x + 0.01, opening.end.y, inner))
	part.span(Vector3(opening.position.x, opening.position.y - 0.01, rear), Vector3(opening.end.x, opening.position.y, inner))
	part.span(Vector3(opening.position.x, opening.end.y, rear), Vector3(opening.end.x, opening.end.y + 0.01, inner))
	if fittings:
		part.paint(Surface.TUBE, Color(0.78, 0.8, 0.76), false)
		var tube := 0.012 * s
		part.cylinder(Vector3(opening.get_center().x, opening.end.y - tube * 2.0, rear + tube * 2.5), Vector3.RIGHT, tube, opening.size.x * 0.85, 8)
		part.cylinder(Vector3(opening.get_center().x, opening.position.y + tube * 2.0, rear + tube * 2.5), Vector3.RIGHT, tube, opening.size.x * 0.85, 8)
		part.paint(Surface.MATTE, Color(0.04, 0.16, 0.06), false)
		part.span(Vector3(opening.position.x + opening.size.x * 0.06, opening.position.y + opening.size.y * 0.3, rear), Vector3(opening.position.x + opening.size.x * 0.3, opening.position.y + opening.size.y * 0.7, rear + 0.006))
		part.paint(Surface.MATTE, Color(0.35, 0.05, 0.03), false)
		part.span(Vector3(opening.position.x + 0.02, opening.position.y + opening.size.y * 0.5, rear + 0.006), Vector3(opening.end.x - 0.02, opening.position.y + opening.size.y * 0.5 + 0.008 * s, rear + 0.016))
	part.paint(Surface.PAINT, BLACK, true)

static func _reel_radius(window_height: float, visible_symbols: float) -> float:
	return STOPS * window_height / visible_symbols / TAU

## Local payline point of top reel `reel` (0-2) in `cabinet` of a bank with `bounds`.
static func reel_center(bounds: Vector3, cabinet: int, reel: int) -> Vector3:
	return _reel_center(_layout(bounds), cabinet, reel)

static func _reel_center(lay: Dictionary, cabinet: int, reel: int) -> Vector3:
	var glass: Rect2 = lay["glass"]
	var w := TOP_REELS[reel]
	return Vector3(_center(lay, cabinet) + glass.position.x + w.x * glass.size.x, glass.end.y - (w.y + w.w * 0.5) * glass.size.y, float(lay["zf"]) - 0.006)

## Reel drums behind the windows: top reels 0-2, lower reels 3-5.
## UV.x across the strip, UV.y = symbols above the payline; UV2 = (reel, cabinet).
static func _reels(part: Part, lay: Dictionary, cabinet: int) -> void:
	var glass: Rect2 = lay["glass"]
	for reel in 3:
		var w := TOP_REELS[reel]
		_drum(part, _reel_center(lay, cabinet, reel), w.z * glass.size.x * 1.1, w.w * glass.size.y, 2.6, reel, cabinet)
	part.xform = _low_xform(lay, cabinet)
	var low: Rect2 = lay["low_glass"]
	for reel in 3:
		var w := LOW_REELS[reel]
		var center := Vector3(low.position.x + w.x * low.size.x, low.end.y - (w.y + w.w * 0.5) * low.size.y, -0.006)
		_drum(part, center, w.z * low.size.x * 1.1, w.w * low.size.y, 2.4, reel + 3, cabinet)
	part.xform = Transform3D.IDENTITY

## `front` is the drum's nearest point (on the payline).
static func _drum(part: Part, front: Vector3, width: float, window: float, visible: float, reel: int, cabinet: int) -> void:
	var symbol := window / visible
	var radius := STOPS * symbol / TAU
	var axis := front - Vector3(0.0, 0.0, radius)
	# Strip cells are 2 symbols wide in texture space.
	var u := width / symbol * 0.25
	part.code = float(cabinet)
	part.kind = reel
	part.solid = false
	var steps := 22
	var reach := deg_to_rad(80.0)
	for i in steps:
		var a0 := lerpf(-reach, reach, float(i) / float(steps))
		var a1 := lerpf(-reach, reach, float(i + 1) / float(steps))
		var p0 := axis + Vector3(0.0, sin(a0), cos(a0)) * radius
		var p1 := axis + Vector3(0.0, sin(a1), cos(a1)) * radius
		var s0 := a0 / TAU * STOPS
		var s1 := a1 / TAU * STOPS
		part.color = Color(1, 1, 1, 1)
		part.tri(p0 + Vector3(-width * 0.5, 0, 0), p1 + Vector3(-width * 0.5, 0, 0), p1 + Vector3(width * 0.5, 0, 0), Vector2(0.5 - u, s0), Vector2(0.5 - u, s1), Vector2(0.5 + u, s1))
		part.tri(p0 + Vector3(-width * 0.5, 0, 0), p1 + Vector3(width * 0.5, 0, 0), p0 + Vector3(width * 0.5, 0, 0), Vector2(0.5 - u, s0), Vector2(0.5 + u, s1), Vector2(0.5 + u, s0))
		# Dark plastic reel rims either side of the strip.
		part.color = Color(0.06, 0.06, 0.07, 0.0)
		for side in [-1.0, 1.0]:
			var x := Vector3(side * width * 0.5, 0.0, 0.0)
			var inner0 := axis + x + Vector3(0.0, sin(a0), cos(a0)) * radius * 0.82
			var inner1 := axis + x + Vector3(0.0, sin(a1), cos(a1)) * radius * 0.82
			part.tri_facing(p0 + x, p1 + x, inner1, Vector3(side, 0.0, 0.0))
			part.tri_facing(p0 + x, inner1, inner0, Vector3(side, 0.0, 0.0))

static func _button_radius(lay: Dictionary) -> float:
	return minf(float(lay["wc"]) * 0.82 / 8.0 * 0.32, 0.05 * float(lay["s"]))

## Button frame on the slanted deck top: origin on the surface, +z its normal.
static func _button_at(lay: Dictionary, cabinet: int, index: int) -> Transform3D:
	var s := float(lay["s"])
	var z_low := float(lay["z_low"])
	var z_deck := float(lay["z_deck"])
	var top := float(lay["deck_top"])
	var a := Vector2(z_low, top)
	var b := Vector2(z_deck, top - 0.035 * s)
	var mid := a.lerp(b, 0.5)
	var slope := (b - a).normalized()
	var normal := Vector3(0.0, slope.x, -slope.y).normalized()
	if normal.y < 0.0:
		normal = -normal
	var span := float(lay["wc"]) * 0.82
	var x := _center(lay, cabinet) + (float(index) - 3.5) / 8.0 * span
	var z_axis := normal
	var x_axis := Vector3.RIGHT
	var y_axis := z_axis.cross(x_axis)
	return Transform3D(Basis(x_axis, y_axis, z_axis), Vector3(x, mid.y, mid.x))

static func _candle_at(lay: Dictionary, cabinet: int) -> Vector3:
	return Vector3(_center(lay, cabinet) + float(lay["wc"]) * 0.33, float(lay["box_top"]), float(lay["zf"]) - 0.14 * float(lay["s"]))

## Candle tiers, button caps, LED displays and coin window behind the glass.
## UV2 = (Light kind, cabinet + 4 * sub). Halos: UV spans -1..1 for the falloff.
static func _lights(cores: Part, halos: Part, lay: Dictionary, cabinet: int) -> void:
	var s := float(lay["s"])
	var candle := _candle_at(lay, cabinet)
	var r := 0.036 * s
	for tier in 2:
		cores.code = float(cabinet + 4 * tier)
		cores.paint(Light.BULB, Color(1.0, 0.72, 0.2) if tier == 0 else Color(1.0, 0.96, 0.88), false)
		var at := candle + Vector3(0.0, (0.038 + 0.063 * float(tier)) * s, 0.0)
		cores.cylinder(at, Vector3.UP, r, 0.055 * s, 12)
		_halo(halos, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.0, r + 0.004)), Vector2(r * 2.6, 0.06 * s), Light.BULB, cabinet + 4 * tier, cores.color)
	var radius := _button_radius(lay)
	for index in 8:
		var at := _button_at(lay, cabinet, index)
		cores.code = float(cabinet + 4 * index)
		cores.paint(Light.BUTTON, BUTTON_COLORS[index], false)
		cores.cylinder(at.origin + at.basis.z * 0.014, at.basis.z, radius, 0.016, 16, Rect2(0.125 * float(index), 0.75, 0.125, 0.0625))
		_halo(halos, Transform3D(at.basis, at.origin + at.basis.z * 0.024), Vector2.ONE * radius * 3.2, Light.BUTTON, cabinet + 4 * index, BUTTON_COLORS[index])
	var glass: Rect2 = lay["glass"]
	var x0 := _center(lay, cabinet) + glass.position.x
	var z := float(lay["zf"]) + 0.004
	for display in 3:
		cores.code = float(cabinet + 4 * display)
		cores.paint(Light.LED, Color(1.0, 0.08, 0.03), false)
		_panel_quad(cores, x0, glass, TOP_LEDS[display], z)
	cores.code = float(cabinet)
	cores.paint(Light.COIN, Color(1.0, 0.2, 0.1), false)
	_panel_quad(cores, x0, glass, TOP_COIN, z)

## Quad over a (u0, v0, u1, v1) window of the top glass; UV 0..1 with v down.
static func _panel_quad(part: Part, x0: float, glass: Rect2, window: Vector4, z: float) -> void:
	var a := Vector2(x0 + window.x * glass.size.x, glass.end.y - window.w * glass.size.y)
	var b := Vector2(x0 + window.z * glass.size.x, glass.end.y - window.y * glass.size.y)
	part.quad(Vector3(a.x, a.y, z), Vector3(a.x, b.y, z), Vector3(b.x, b.y, z), Vector3(b.x, a.y, z))

static func _halo(halos: Part, at: Transform3D, size: Vector2, kind: int, code: int, color: Color) -> void:
	halos.code = float(code)
	halos.paint(kind, color, false)
	var h := size * 0.5
	halos.quad(at * Vector3(-h.x, -h.y, 0.0), at * Vector3(-h.x, h.y, 0.0), at * Vector3(h.x, h.y, 0.0), at * Vector3(h.x, -h.y, 0.0), Rect2(-1, -1, 2, 2))
