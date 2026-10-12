class_name PragueKits
extends RefCounted
## Deterministic Prague dressing in a room-local, cardinal-facing basis.
## Substantial furniture collides; every mouth joins the shared clear aisle.
const METRO = preload("res://shaders/kits/metro_wall.gdshader")
const TERRAZZO = preload("res://shaders/kits/terrazzo.gdshader")
const TILE = preload("res://shaders/kits/wc_tile.gdshader")
const RADIO = preload("res://assets/third_party/kenney_furniture/radio.glb")
const PLANT = preload("res://assets/third_party/kenney_furniture/plantSmall3.glb")
const WHITE := Color(0.82, 0.83, 0.77)
const STEEL := Color(0.52, 0.56, 0.58)
const WOOD := Color(0.29, 0.16, 0.075)
const BLUE := Color(0.08, 0.28, 0.62)
const DARK := Color(0.06, 0.075, 0.08)
static var _surfaces: Dictionary = {}
const QUOTE_SALT := 0x514F5445
const QUOTE_PIXEL_SIZE := 0.005
const QUOTE_OUTLINE_PIXELS := 20.0
static var _quote_lines := PackedStringArray()
static var _quotes_loaded := false
static var _quote_font: Font
var target: KitTarget
var site: Dictionary
var center: Vector3
var right: Vector3
var front: Vector3
var yaw: float
var half: Vector2
var height: float
const AISLE_HALF := 1.05
const OUTDOOR_MARGIN := 0.75
## Leave a full 2 m navigation cell plus two 0.4 m enemy radii between assemblies.
const FURNITURE_GAP := 2.8
var mouths: Array[Vector2] = []
var mouth_widths: Array[float] = []
var clear_paths: Array[Rect2] = []
var stair_bounds: Array[Rect2] = []
var furniture_bounds: Array[Rect2] = []
var outdoor := false
var rng := RandomNumberGenerator.new()
var quote_rng := RandomNumberGenerator.new()
var count := 0


static func build(sink: KitTarget, description: Dictionary) -> void:
	var kit := PragueKits.new()
	kit.target = sink
	kit.site = description
	var rect: Rect2 = description.get("rect", Rect2(-4, -4, 8, 8))
	var facing: Vector2 = description.get("facing", Vector2(0, 1))
	if facing.length_squared() < 0.01:
		facing = Vector2(0, 1)
	facing = facing.normalized()
	kit.front = Vector3(facing.x, 0, facing.y)
	kit.right = Vector3(facing.y, 0, -facing.x)
	kit.yaw = atan2(facing.x, facing.y)
	kit.center = Vector3(rect.get_center().x, float(description.get("floor_y", 0.0)), rect.get_center().y)
	kit.half = Vector2(absf(kit.right.x) * rect.size.x + absf(kit.right.z) * rect.size.y, absf(facing.x) * rect.size.x + absf(facing.y) * rect.size.y) * 0.5
	kit.height = maxf(2.1, float(description.get("ceiling_y", kit.center.y + 3.0)) - kit.center.y)
	kit.outdoor = StringName(description.get("kind", &"wc")) in [&"construction", &"park"]
	kit._reserve_routes()
	kit.rng.seed = int(description.get("seed", 0))
	kit.quote_rng.seed = int(description.get("seed", 0)) ^ QUOTE_SALT
	description["quote_signs"] = [] as Array[Dictionary]
	match StringName(description.get("kind", &"wc")):
		&"metro": kit._metro()
		&"wc": kit._wc()
		&"toitoi": kit._portable()
		&"hospoda": kit._pub(false)
		&"nonstop", &"snack", &"snack_room": kit._pub(true)
		&"herna": kit._herna()
		&"vecerka": kit._shop()
		&"construction": kit._construction()
		&"park": kit._park()
	kit._quote_signage()


func _point(p: Vector3) -> Vector3:
	return center + right * p.x + Vector3.UP * p.y + front * p.z


func _transform(p: Vector3, size: Vector3, turn: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw + turn) * Basis.from_scale(size), _point(p))


static func _load_quotes() -> void:
	if _quotes_loaded:
		return
	_quotes_loaded = true
	_quote_font = ThemeDB.fallback_font
	var source := FileAccess.open("res://hlasky.txt", FileAccess.READ)
	if source == null:
		push_error("Quote signage cannot read res://hlasky.txt")
		return
	for line in source.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			_quote_lines.append(trimmed)


static func _wrap_quote(text: String, font_size: int, width: float) -> String:
	var lines := PackedStringArray()
	var current := ""
	for word in text.replace("\t", " ").split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if _quote_font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			current = candidate
			continue
		if not current.is_empty():
			lines.append(current)
		# Leave long words whole; the fitting pass reduces the font until
		# they fit too, preserving normalized whitespace and every character.
		current = word
	if not current.is_empty():
		lines.append(current)
	return "\n".join(lines)


func _quote_board(xform: Transform3D, size: Vector2, outside: bool, style: int) -> void:
	_load_quotes()
	if _quote_lines.is_empty():
		return
	var text := _quote_lines[quote_rng.randi_range(0, _quote_lines.size() - 1)]
	# Label3D ignores transform scale: fit actual font metrics in pixel space.
	# Keep the full ten-pixel outline on each side inside a generous border.
	var pixels := (size - Vector2(0.18, 0.18)) / QUOTE_PIXEL_SIZE - Vector2.ONE * QUOTE_OUTLINE_PIXELS
	var rendered := ""
	var font_size := 48
	while font_size > 0:
		rendered = _wrap_quote(text, font_size, pixels.x)
		var extent := _quote_font.get_multiline_string_size(rendered, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		if extent.x <= pixels.x and extent.y <= pixels.y:
			break
		font_size -= 1
	# Every source line can be selected, including the longest ones.
	# The supplied boards have ample room even at the smallest font size.
	font_size = maxi(1, font_size)
	var frame: Color = [WOOD, BLUE, Color(0.72, 0.40, 0.065)][style % 3]
	var ink: Color = [Color(0.98, 0.92, 0.72), WHITE, Color(1.0, 0.88, 0.55)][style % 3]
	target.add_paint(&"box", xform * Transform3D(Basis.from_scale(Vector3(size.x, size.y, 0.065)), Vector3.ZERO), frame, KitTarget.Finish.SATIN)
	target.add_paint(&"box", xform * Transform3D(Basis.from_scale(Vector3(size.x - 0.08, size.y - 0.08, 0.012)), Vector3(0, 0, 0.04)), DARK)
	var label_xform := xform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.06))
	target.add_label(rendered, label_xform, font_size, ink)
	var signs: Array[Dictionary] = site["quote_signs"]
	signs.append({
		"text": text, "rendered_text": rendered, "position": label_xform.origin,
		"normal": label_xform.basis.z.normalized(), "size": size,
		"font_size": font_size, "outdoor": outside,
	})


func _hanging_quotes() -> void:
	var size := Vector2(minf(1.9, half.x * 2.0 - 0.3), 0.86)
	var y := minf(2.72, height - size.y * 0.5 - 0.12)
	# The clear central spine stays visible below the notices. Wall banks
	# reach the ceiling, so hanging in the aisle avoids hiding the print.
	for index in 2:
		var p := Vector3(0, y, half.y * (0.35 if index == 0 else -0.35))
		var turn := 0.0 if index == 0 else PI
		_quote_board(_transform(p, Vector3.ONE, turn), size, false, quote_rng.randi_range(0, 2))
		var rod_length := maxf(0.02, height - y - size.y * 0.5)
		for x in [-size.x * 0.38, size.x * 0.38]:
			_box(p + Vector3(x, size.y * 0.5 + rod_length * 0.5, 0), Vector3(0.025, rod_length, 0.025), STEEL)


func _entrance_quote() -> void:
	var door: Vector3 = site.get("door", _point(Vector3(0, 0, half.y)))
	var local := _local(door)
	var side_wall := absf(absf(local.x) - half.x) < absf(absf(local.y) - half.y)
	var normal := Vector3(signf(local.x), 0, 0) if side_wall else Vector3(0, 0, signf(local.y))
	var turn := atan2(normal.x, normal.z)
	var size := Vector2(2.2, 1.2)
	# The wall ring is solid beside the mouth. Mount above the actual open
	# entrance instead of burying a notice inside that two-metre facade.
	var p := Vector3(local.x, height + size.y * 0.5 + 0.08, local.y) + normal * 0.18
	_quote_board(_transform(p, Vector3.ONE, turn), size, true, quote_rng.randi_range(0, 2))


func _quote_signage() -> void:
	match StringName(site.get("kind", &"wc")):
		&"herna", &"hospoda", &"nonstop", &"snack", &"snack_room", &"vecerka", &"wc":
			_hanging_quotes()
			if site.kind != &"wc":
				_entrance_quote()
		&"metro":
			_hanging_quotes()
			var entries: Array = site.get("entrances", [])
			var entry: Dictionary = entries[0] if not entries.is_empty() else {}
			var top: Vector3 = entry.get("top", site.get("door", center))
			var direction: Vector3 = entry.get("direction", front)
			direction = Vector3(direction.x, 0, direction.z).normalized()
			var basis := Basis(Vector3.UP, atan2(-direction.x, -direction.z))
			# Face arriving street traffic over the clear stair approach.
			var p := top + basis.z * 0.45 + Vector3.UP * 2.65
			_quote_board(Transform3D(basis, p), Vector2(2.0, 1.1), true, 1)
		&"park", &"construction":
			for side in [-1.0, 1.0]:
				# Construction notices frame the front gate, away from the
				# side fence and the equipment occupying its inner corners.
				var p := Vector3(side * (half.x - 0.85), 1.9, half.y - 0.18) if site.kind == &"construction" else Vector3(side * (half.x - 0.18), 1.9, side * half.y * 0.35)
				var turn: float = 0.0 if site.kind == &"construction" else -side * PI * 0.5
				_quote_board(_transform(p, Vector3.ONE, turn), Vector2(1.7, 1.2), true, 0 if site.kind == &"park" else 2)
				_box(Vector3(p.x, 0.65, p.z), Vector3(0.055, 1.3, 0.055), WOOD if site.kind == &"park" else STEEL)


func _shape(kind: StringName, p: Vector3, size: Vector3, color: Color, block: bool = false, finish: int = KitTarget.Finish.MATTE, glow: float = 0.0, turn: float = 0.0) -> void:
	# Reject an entire blocking primitive, never paint a collision-free substitute.
	var footprint := _footprint(p, size, turn)
	if not Rect2(-half, half * 2.0).encloses(footprint):
		return
	if block and (count >= 40 or not _clear(p, size, turn)):
		return
	target.add_paint(kind, _transform(p, size, turn), color, finish, glow)
	if block:
		target.add_solid(_point(p), size, yaw + turn, null)
		furniture_bounds.append(footprint)
		count += 1


func _box(p: Vector3, size: Vector3, color: Color, block: bool = false, finish: int = KitTarget.Finish.MATTE, glow: float = 0.0, turn: float = 0.0) -> void:
	_shape(&"box", p, size, color, block, finish, glow, turn)


func _local(p: Vector3) -> Vector2:
	var delta := p - center
	return Vector2(delta.dot(right), delta.dot(front))


func _local_rect(rect: Rect2) -> Rect2:
	var middle := _local(Vector3(rect.get_center().x, center.y, rect.get_center().y))
	var size := Vector2(absf(right.x) * rect.size.x + absf(right.z) * rect.size.y, absf(front.x) * rect.size.x + absf(front.z) * rect.size.y)
	return Rect2(middle - size * 0.5, size)


func _footprint(p: Vector3, size: Vector3, turn: float = 0.0) -> Rect2:
	var c := absf(cos(turn))
	var s := absf(sin(turn))
	var extent := Vector2(size.x * c + size.z * s, size.x * s + size.z * c) * 0.5
	return Rect2(Vector2(p.x, p.z) - extent, extent * 2.0)


func _reserve_segment(a: Vector2, b: Vector2) -> void:
	clear_paths.append(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x - b.x), absf(a.y - b.y))).grow(AISLE_HALF))


func _reserve_endpoint(p: Vector2) -> void:
	# Side mouths go straight to the spine. End mouths first enter two metres,
	# then turn across it, keeping the whole L connected rather than two islands.
	var on_side := absf(absf(p.x) - half.x) < absf(absf(p.y) - half.y)
	var inner := p
	if not on_side and absf(p.y) > half.y - 2.0:
		inner.y = signf(p.y) * maxf(0.0, half.y - 2.0)
		_reserve_segment(p, inner)
	_reserve_segment(inner, Vector2(0, inner.y))


func _reserve_routes() -> void:
	clear_paths.append(Rect2(Vector2(-AISLE_HALF, -half.y), Vector2(AISLE_HALF * 2.0, half.y * 2.0)))
	var openings: Array = site.get("openings", []).duplicate()
	var widths: Array = site.get("opening_widths", [])
	var door: Vector3 = site.get("door", _point(Vector3(0, 0, half.y)))
	if not openings.has(door):
		openings.append(door)
	for index in openings.size():
		var p := _local(openings[index])
		var width := maxf(AISLE_HALF * 2.0, float(widths[index]) if index < widths.size() else AISLE_HALF * 2.0)
		mouths.append(p)
		mouth_widths.append(width)
		_reserve_endpoint(p)
		# Keep the entire carved opening usable, not just its centre cell.
		if absf(absf(p.x) - half.x) < 0.6:
			var x := half.x - 2.0 if p.x > 0.0 else -half.x
			clear_paths.append(Rect2(Vector2(x, p.y - width * 0.5), Vector2(2.0, width)))
		elif absf(absf(p.y) - half.y) < 0.6:
			var z := half.y - 2.0 if p.y > 0.0 else -half.y
			clear_paths.append(Rect2(Vector2(p.x - width * 0.5, z), Vector2(width, 2.0)))
	for standing: Vector3 in site.get("standing_points", []):
		_reserve_endpoint(_local(standing))
	for zone: Rect2 in site.get("machine_zones", []):
		clear_paths.append(_local_rect(zone))
	for entry: Dictionary in site.get("entrances", []):
		var foot: Vector3 = entry.get("foot", entry.get("position", center))
		var p := _local(foot)
		mouths.append(p)
		mouth_widths.append(6.0)
		_reserve_endpoint(p)
		if entry.has("rect"):
			var bounds := _local_rect(entry.rect)
			stair_bounds.append(bounds)
			clear_paths.append(bounds.grow(0.1))
			var direction: Vector3 = entry.get("direction", front)
			var landing := foot + direction * 1.0
			var width := Vector2(absf(direction.z), absf(direction.x)) * 6.0 + Vector2(absf(direction.x), absf(direction.z)) * 2.0
			clear_paths.append(_local_rect(Rect2(Vector2(landing.x, landing.z) - width * 0.5, width)))


func _clear(p: Vector3, size: Vector3, turn: float = 0.0) -> bool:
	var footprint := _footprint(p, size, turn)
	var bounds := Rect2(-half, half * 2.0)
	if outdoor:
		bounds = bounds.grow(-OUTDOOR_MARGIN)
	if not bounds.encloses(footprint):
		return false
	for path: Rect2 in clear_paths:
		if footprint.intersects(path):
			return false
	return true


func _furniture_spot(preferred: Vector3, size: Vector3, turn: float = 0.0) -> Vector3:
	# Move whole assemblies when a newly supplied mouth occupies their old slot.
	# Claim envelopes so relocated shelves/counters do not pile up on each other.
	if _available(preferred, size, turn):
		furniture_bounds.append(_footprint(preferred, size, turn))
		return preferred
	var extent := _footprint(Vector3.ZERO, size, turn).size * 0.5
	var margin := OUTDOOR_MARGIN if outdoor else 0.12
	var x := minf(absf(preferred.x), half.x - margin - extent.x)
	var last_z := half.y - margin - extent.y
	for side in 2:
		var direction := signf(preferred.x) if side == 0 else -signf(preferred.x)
		for step in maxi(0, int((last_z * 2.0) / 0.5) + 1):
			var p := Vector3(direction * x, preferred.y, -last_z + float(step) * 0.5)
			if _available(p, size, turn):
				furniture_bounds.append(_footprint(p, size, turn))
				return p
	if not outdoor:
		var last_x := half.x - margin - extent.x
		for column in maxi(0, int(last_x * 4.0) + 1):
			for row in maxi(0, int(last_z * 4.0) + 1):
				var p := Vector3(-last_x + column * 0.5, preferred.y, -last_z + row * 0.5)
				if _available(p, size, turn):
					furniture_bounds.append(_footprint(p, size, turn))
					return p
	return Vector3(INF, INF, INF)


func _available(p: Vector3, size: Vector3, turn: float) -> bool:
	if not _clear(p, size, turn):
		return false
	var footprint := _footprint(p, size, turn)
	if not outdoor and site.kind != &"toitoi":
		# Flush to a wall, or leave a usable passage; never create a narrow
		# pocket that looks walkable but has no route around the furniture.
		for gap in [footprint.position.x + half.x, half.x - footprint.end.x, footprint.position.y + half.y, half.y - footprint.end.y]:
			if gap > 0.2 and gap < FURNITURE_GAP:
				return false
	footprint = footprint.grow(1.25 if outdoor or site.kind == &"toitoi" else FURNITURE_GAP)
	for occupied: Rect2 in furniture_bounds:
		if footprint.intersects(occupied):
			return false
	return true


func _sign(cell: int, p: Vector3, size: Vector2, turn: float = 0.0, glow: float = 0.0) -> void:
	if absf(p.x) + size.x * 0.5 <= half.x and absf(p.z) + 0.04 <= half.y:
		target.add_sign(_transform(p, Vector3(size.x, size.y, 0.06), turn), cell, 1, glow)


func _surface(shader: Shader, key: String, parameters: Dictionary) -> Material:
	if not _surfaces.has(key):
		var material := ShaderMaterial.new()
		material.shader = shader
		for parameter: String in parameters:
			material.set_shader_parameter(parameter, parameters[parameter])
		_surfaces[key] = material
	return _surfaces[key]


func _entrance_sign(cell: int) -> void:
	var position := (site.door as Vector3) + Vector3.UP * 2.55 + front * 0.16
	target.add_sign(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(3.0, 0.55, 0.035)), position), cell, 1, 0.35)


func _lining(wall: Material, floor_material: Material) -> void:
	target.add_visual(&"box", _transform(Vector3(0, 0.012, 0), Vector3(half.x * 2 - 0.08, 0.018, half.y * 2 - 0.08)), floor_material)
	_wall_segments(_wall_strip.bind(wall))


## All wall materials share the same portal and stair clipping contract.
func _wall_segments(draw: Callable) -> void:
	# Use the same mouths as collision routing, including full stair footprints.
	for face in 4:
		var side_axis := face < 2
		var direction := -1.0 if face % 2 == 0 else 1.0
		var extent := half.y if side_axis else half.x
		var edge := direction * (half.x if side_axis else half.y)
		var gaps: Array[Vector2] = []
		for index in mouths.size():
			var opening := mouths[index]
			if absf((opening.x if side_axis else opening.y) - edge) < 0.6:
				var middle := opening.y if side_axis else opening.x
				var radius := mouth_widths[index] * 0.5
				gaps.append(Vector2(maxf(-extent, middle - radius), minf(extent, middle + radius)))
		for bounds: Rect2 in stair_bounds:
			var low := bounds.position.x if side_axis else bounds.position.y
			var high := bounds.end.x if side_axis else bounds.end.y
			if edge >= low - 0.1 and edge <= high + 0.1:
				gaps.append(Vector2(maxf(-extent, (bounds.position.y if side_axis else bounds.position.x) - 0.1), minf(extent, (bounds.end.y if side_axis else bounds.end.x) + 0.1)))
		gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cursor := -extent + 0.04
		for gap: Vector2 in gaps:
			draw.call(side_axis, edge, cursor, gap.x)
			cursor = maxf(cursor, gap.y)
		draw.call(side_axis, edge, cursor, extent - 0.04)


func _wall_strip(side_axis: bool, edge: float, start: float, end: float, material: Material) -> void:
	if end - start < 0.04: return
	var middle := (start + end) * 0.5
	var inset := edge - signf(edge) * 0.025
	var p := Vector3(inset, height * 0.5, middle) if side_axis else Vector3(middle, height * 0.5, inset)
	var size := Vector3(0.025, height - 0.04, end - start) if side_axis else Vector3(end - start, height - 0.04, 0.025)
	target.add_visual(&"box", _transform(p, size), material)
	# The visible lining can border another underground room, where the outer
	# terrain hull has no wall. Use the identical portal-cut strip for physics.
	target.add_solid(_point(p), size, yaw, null)
	count += 1


func _tubes() -> void:
	# Four paired fittings; only metro spends two of the four world kit lights.
	for z in [-half.y * 0.5, half.y * 0.5]:
		for x in [-half.x * 0.5, half.x * 0.5]:
			_box(Vector3(x, height - 0.10, z), Vector3(0.25, 0.07, 1.42), STEEL, false, KitTarget.Finish.METAL)
			for offset in [-0.065, 0.065]:
				_box(Vector3(x + offset, height - 0.15, z), Vector3(0.038, 0.035, 1.28), WHITE, false, KitTarget.Finish.GLOSS, 2.5)
		if StringName(site.get("kind", &"wc")) == &"metro":
			target.add_light(_point(Vector3(0, height - 0.3, z)), Color(0.82, 0.89, 1.0), 0.55, maxf(4.0, half.x * 1.25))
	for side in [-1.0, 1.0]:
		var x: float = side * (half.x - 0.28)
		_box(Vector3(x, height - 0.09, 0), Vector3(0.16, 0.08, half.y * 2.0 - 0.4), DARK)
		for offset in [-0.055, 0.055]:
			_box(Vector3(x + offset, height - 0.15, 0), Vector3(0.035, 0.035, half.y * 2.0 - 0.5), STEEL, false, KitTarget.Finish.METAL)
		for n in maxi(1, int(half.y)):
			_box(Vector3(x, height - 0.19, -half.y + 0.6 + n * 1.8), Vector3(0.22, 0.035, 0.07), DARK)
	var duct_z := -half.y * 0.65
	_box(Vector3(0, height - 0.12, duct_z), Vector3(half.x * 2.0 - 0.45, 0.15, 0.34), STEEL, false, KitTarget.Finish.METAL)
	for side in [-1.0, 1.0]:
		var x: float = side * half.x * 0.65
		_box(Vector3(x, height - 0.205, duct_z), Vector3(0.8, 0.018, 0.25), DARK)
		for n in 7:
			_box(Vector3(x - 0.33 + n * 0.11, height - 0.218, duct_z), Vector3(0.024, 0.012, 0.24), STEEL, false, KitTarget.Finish.METAL)


func _bench(x: float, z: float, color: Color = WOOD, turn: float = 0.0) -> void:
	var size := Vector3(1.55, 0.9, 0.6)
	if count >= 40: return
	var p := _furniture_spot(Vector3(x, 0.45, z), size, turn)
	if not p.is_finite(): return
	var rotation := Basis(Vector3.UP, turn)
	_box(p, Vector3(1.55, 0.12, 0.55), color, false, KitTarget.Finish.MATTE, 0.0, turn)
	_box(p + rotation * Vector3(0, 0.34, -0.24), Vector3(1.55, 0.55, 0.08), color, false, KitTarget.Finish.MATTE, 0.0, turn)
	for dx in [-0.55, 0.55]:
		_box(p + rotation * Vector3(dx, -0.22, 0), Vector3(0.08, 0.46, 0.48), DARK, false, KitTarget.Finish.MATTE, 0.0, turn)
	target.add_solid(_point(p), size, yaw + turn, null)
	count += 1


func _metro() -> void:
	var theme := StringName(site.get("theme", &"yard"))
	var line := 0 if theme == &"yard" else (1 if theme == &"foundry" else 2)
	var color: Color = [Color(0.03, 0.57, 0.28), Color(0.85, 0.67, 0.04), Color(0.8, 0.08, 0.1)][line]
	var wall := _surface(METRO, "metro%d:%s" % [line, center.y], {"mode": line, "line_color": color, "base_y": center.y})
	_lining(wall, _surface(TERRAZZO, "terrazzo", {}))
	_tubes()
	# A/B/C: golden cups, pearl glass/marble, cream ceramics; coloured inlays
	# mark the central circulation while safe wall bays define fixture zones.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 1.14, 0.027, 0), Vector3(0.055, 0.009, half.y * 2.0 - 0.12), color)
		for n in maxi(1, int(half.y / 1.8)):
			var z := -half.y + 1.0 + n * 3.0
			var p := Vector3(side * (half.x - 0.095), 1.48, z)
			if not _clear(p, Vector3(0.13, 2.0, 0.9)): continue
			_box(p, Vector3(0.08, 2.25, 0.84), STEEL if line == 0 else WHITE, false, KitTarget.Finish.METAL if line == 0 else KitTarget.Finish.SATIN)
			_box(p + Vector3(-side * 0.045, -0.48, 0), Vector3(0.02, 1.2, 0.76), DARK if line == 1 else color)
			_box(p + Vector3(-side * 0.045, -1.35, 0), Vector3(0.02, 0.14, 0.84), DARK)
	_sign(line, Vector3(0, minf(2.35, height - 0.38), -half.y + 0.07), Vector2(minf(5.0, half.x * 1.8), 0.62), 0, 0.3)
	_sign(31, Vector3(0, height - 0.38, half.y - 0.12), Vector2(2.0, 0.44), PI, 0.35)
	var variant := rng.randi_range(0, 2)
	var machine_side := -1.0 if variant == 1 else 1.0
	var turn := -machine_side * PI * 0.5
	for n in (2 if line == 1 else 1):
		var p := _room_assembly(Vector3(machine_side * (half.x - 0.62), 1.0, half.y - 1.5 - n * 1.0), Vector3(0.7, 2.0, 0.8), turn)
		if not p.is_finite(): continue
		_room_piece(p, Vector3.ZERO, Vector3(0.68, 1.96, 0.62), Color(0.87, 0.34, 0.055), turn, KitTarget.Finish.SATIN)
		_room_sign(12, p, Vector3(0, 0.65, 0.33), Vector2(0.56, 0.35), turn)
		_room_piece(p, Vector3(-0.09, 0.16, 0.33), Vector3(0.34, 0.32, 0.03), Color(0.12, 0.26, 0.29), turn, KitTarget.Finish.GLOSS, 0.4)
		_room_piece(p, Vector3(0.22, 0.2, 0.34), Vector3(0.07, 0.035, 0.035), STEEL, turn)
		_room_piece(p, Vector3(0, -0.4, 0.34), Vector3(0.4, 0.12, 0.04), DARK, turn)
		_room_piece(p, Vector3(0, -0.85, 0.34), Vector3(0.5, 0.08, 0.035), STEEL, turn)
	for side in [-1.0, 1.0]:
		var p := _room_assembly(Vector3(side * (half.x - 1.1), 0.78, half.y - 2.5), Vector3(0.36, 1.56, 0.36))
		if not p.is_finite(): continue
		_box(p + Vector3(0, -0.15, 0), Vector3(0.09, 1.22, 0.09), STEEL, false, KitTarget.Finish.METAL)
		_box(p + Vector3(0, -0.72, 0), Vector3(0.28, 0.1, 0.28), STEEL)
		_box(p + Vector3(0, 0.56, 0), Vector3(0.34, 0.36, 0.3), Color(0.9, 0.69, 0.04))
		_box(p + Vector3(0, 0.56, 0.157), Vector3(0.22, 0.025, 0.015), DARK)
		_sign(13, p + Vector3(0, 0.64, 0.17), Vector2(0.28, 0.14))
	for n in (3 if variant == 2 else 2):
		_bench(-machine_side * (half.x - 0.6), -half.y + 1.7 + n * 2.1, Color(0.56, 0.29, 0.08) if line == 0 else STEEL, machine_side * PI * 0.5)
	var bin := _room_assembly(Vector3(machine_side * (half.x - 0.5), 0.43, -half.y + 1.0), Vector3(0.52, 0.86, 0.52))
	if bin.is_finite():
		_shape(&"cylinder", bin, Vector3(0.48, 0.82, 0.48), STEEL, false, KitTarget.Finish.METAL)
		_shape(&"cylinder", bin + Vector3(0, 0.41, 0), Vector3(0.43, 0.025, 0.43), DARK)
		_box(bin + Vector3(0.28, -0.41, 0.1), Vector3(0.16, 0.015, 0.12), WHITE, false, KitTarget.Finish.GRIME, 0.0, 0.35)
	_room_notice(-machine_side, -half.y * 0.35, 14, color, variant)
	_room_notice(machine_side, half.y * 0.1, 3, color, (variant + 1) % 3)
	var entrances: Array = site.get("entrances", [])
	if entrances.is_empty():
		entrances = [{"position": site.get("door", _point(Vector3(0, 0, half.y)))}]
	for entry: Dictionary in entrances:
		var top: Vector3 = entry.get("top", entry.get("position", center))
		# Preserve the surface pylon beside, never inside, the full stair mouth.
		var direction: Vector3 = entry.get("direction", front)
		var p := top + Vector3(direction.z, 0, -direction.x) * 3.45
		target.add_paint(&"box", Transform3D(Basis().scaled(Vector3(0.12, 2.5, 0.12)), p + Vector3.UP * 1.25), STEEL, KitTarget.Finish.METAL)
		target.add_sign(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.8, 0.8, 0.16)), p + Vector3.UP * 2.6), 4, 1, 0.3)


func _wc_piece(kind: StringName, origin: Vector3, offset: Vector3, size: Vector3, color: Color, turn: float, block: bool = false, finish: int = KitTarget.Finish.MATTE, extra_turn: float = 0.0) -> void:
	_shape(kind, origin + Basis(Vector3.UP, turn) * offset, size, color, block, finish, 0.0, turn + extra_turn)


func _wc_ring(origin: Vector3, y: float, radii: Vector2, depth: float, color: Color, turn: float, finish: int = KitTarget.Finish.GLOSS) -> void:
	# One continuous hollow oval, not a row of disconnected porcelain blocks.
	# The shared torus has centreline radius .44 and tube diameter .12.
	var scale := Vector3(radii.x / 0.44, depth / 0.12, radii.y / 0.44)
	var p := origin + Basis(Vector3.UP, turn) * Vector3(0, y, 0)
	target.add_paint(&"ring", _transform(p, scale, turn), color, finish)


func _toilet(x: float, z: float, turn: float = 0.0, block: bool = true) -> void:
	var p := Vector3(x, 0, z)
	# Only the actual fixture is blocked, never the surrounding stall.
	if block:
		if count >= 40 or not _clear(p + Vector3.UP * 0.51, Vector3(0.52, 1.02, 0.83), turn):
			return
		target.add_solid(_point(p + Vector3.UP * 0.51), Vector3(0.52, 1.02, 0.83), yaw + turn, null)
		count += 1
	_wc_piece(&"cylinder", p, Vector3(0, 0.07, -0.045), Vector3(0.31, 0.12, 0.38), WHITE, turn, false, KitTarget.Finish.GLOSS)
	_wc_piece(&"cylinder", p, Vector3(0, 0.19, -0.07), Vector3(0.23, 0.16, 0.28), WHITE, turn, false, KitTarget.Finish.GLOSS)
	_wc_piece(&"cylinder", p, Vector3(0, 0.29, 0.025), Vector3(0.32, 0.035, 0.42), Color(0.25, 0.29, 0.27), turn)
	_wc_ring(p, 0.315, Vector2(0.16, 0.205), 0.09, WHITE, turn)
	_wc_ring(p, 0.375, Vector2(0.195, 0.245), 0.09, WHITE, turn)
	_wc_ring(p, 0.435, Vector2(0.22, 0.28), 0.045, WHITE, turn)
	_wc_ring(p, 0.478, Vector2(0.217, 0.274), 0.035, Color(0.9, 0.9, 0.83), turn)
	_wc_piece(&"cylinder", p, Vector3(0, 0.315, 0.04), Vector3(0.235, 0.012, 0.30), Color(0.18, 0.34, 0.36), turn, false, KitTarget.Finish.GLOSS)
	_wc_piece(&"cylinder", p, Vector3(0, 0.323, 0.025), Vector3(0.075, 0.006, 0.085), DARK, turn)
	# A closed cistern, distinct lid, dual flush buttons and seat hinges.
	_wc_piece(&"box", p, Vector3(0, 0.745, -0.285), Vector3(0.39, 0.40, 0.16), WHITE, turn, false, KitTarget.Finish.GLOSS)
	_wc_piece(&"box", p, Vector3(0, 0.956, -0.285), Vector3(0.42, 0.025, 0.18), WHITE, turn, false, KitTarget.Finish.GLOSS)
	for dx in [-0.035, 0.035]:
		_wc_piece(&"cylinder", p, Vector3(dx, 0.974, -0.28), Vector3(0.045, 0.009, 0.055), STEEL, turn, false, KitTarget.Finish.METAL)
	for dx in [-0.11, 0.11]:
		_wc_piece(&"box", p, Vector3(dx, 0.487, -0.215), Vector3(0.045, 0.035, 0.085), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0, 0.46, -0.25), Vector3(0.30, 0.10, 0.19), WHITE, turn, false, KitTarget.Finish.GLOSS)
	_wc_piece(&"cylinder", p, Vector3(0.18, 0.39, -0.31), Vector3(0.025, 0.29, 0.025), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0.18, 0.28, -0.36), Vector3(0.065, 0.04, 0.035), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0, 0.16, -0.29), Vector3(0.12, 0.12, 0.22), WHITE, turn)


func _wc_stall(preferred: Vector3, turn: float, panel: Color, ladies: bool, wear: float) -> void:
	if count + 6 > 40: return
	var p := _furniture_spot(preferred, Vector3(1.72, 2.12, 1.90), turn)
	if not p.is_finite(): return
	turn = -PI * 0.5 if p.x > 0.0 else PI * 0.5
	for side in [-1.0, 1.0]:
		_wc_piece(&"box", p, Vector3(side * 0.80, 1.05, 0), Vector3(0.055, 2.10, 1.78), panel, turn, true, KitTarget.Finish.SATIN)
		_wc_piece(&"box", p, Vector3(side * 0.767, 0.17, 0), Vector3(0.014, 0.24, 1.68), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0, 1.05, -0.855), Vector3(1.60, 2.10, 0.055), panel, turn, true, KitTarget.Finish.SATIN)
	_wc_piece(&"box", p, Vector3(0.72, 1.05, 0.855), Vector3(0.16, 2.10, 0.055), panel, turn, true, KitTarget.Finish.SATIN)
	_wc_piece(&"box", p, Vector3(0, 2.07, 0.855), Vector3(1.65, 0.055, 0.07), STEEL, turn, false, KitTarget.Finish.METAL)
	# A real hinged leaf tucked inside the left partition leaves over one
	# metre of usable front opening, rather than a solid envelope collider.
	var ajar := rng.randf_range(1.02, 1.22)
	var hinge := Vector3(-0.765, 1.01, 0.82)
	var door := hinge + Basis(Vector3.UP, ajar) * Vector3(0.34, 0, 0)
	_wc_piece(&"box", p, door, Vector3(0.68, 1.83, 0.048), panel.lightened(0.12), turn, true, KitTarget.Finish.SATIN, ajar)
	var handle := hinge + Basis(Vector3.UP, ajar) * Vector3(0.55, -0.05, 0.04)
	_wc_piece(&"box", p, handle, Vector3(0.12, 0.025, 0.055), STEEL, turn, false, KitTarget.Finish.METAL, ajar)
	for y in [0.35, 1.66]:
		_wc_piece(&"cylinder", p, Vector3(-0.765, y, 0.82), Vector3(0.035, 0.13, 0.035), STEEL, turn, false, KitTarget.Finish.METAL)
	var fixture := p + Basis(Vector3.UP, turn) * Vector3(0, 0, -0.39)
	_toilet(fixture.x, fixture.z, turn)
	var points: Array[Vector3] = site.get("toilet_points", [] as Array[Vector3])
	if points.is_empty():
		site["toilet_facing"] = right * sin(turn) + front * cos(turn)
	points.append(_point(fixture + Vector3.UP * 0.47))
	site["toilet_points"] = points
	_sign(9 if ladies else 8, p + Basis(Vector3.UP, turn) * Vector3(0.57, 1.65, 0.895), Vector2(0.27, 0.21), turn)
	# Roll axle lies across the wall: horizontal cylinder, not a soap cube.
	var holder := p + Basis(Vector3.UP, turn) * Vector3(0.72, 0.68, -0.20)
	_wc_piece(&"box", p, Vector3(0.752, 0.68, -0.20), Vector3(0.025, 0.17, 0.22), STEEL, turn, false, KitTarget.Finish.METAL)
	target.add_paint(&"cylinder", _transform(holder, Vector3.ONE, turn) * Transform3D(Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(0.12, 0.14, 0.12)), Vector3.ZERO), WHITE)
	_wc_piece(&"box", p, Vector3(0.70, 0.58, -0.14), Vector3(0.075, 0.14, 0.012), WHITE, turn)
	var stain_z := rng.randf_range(-0.55, 0.30)
	_wc_piece(&"box", p, Vector3(-0.766, 0.27, stain_z), Vector3(0.008, 0.19 + wear * 0.2, 0.16), Color(0.29, 0.25, 0.16), turn, false, KitTarget.Finish.GRIME)


func _wc_urinal(preferred: Vector3, turn: float, panel: Color) -> void:
	if count + 2 > 40: return
	var p := _furniture_spot(preferred, Vector3(0.83, 1.80, 0.82), turn)
	if not p.is_finite(): return
	turn = PI * 0.5 if p.x < 0.0 else -PI * 0.5
	# Include the projecting trough, not merely its flat ceramic back.
	target.add_solid(_point(p + Basis(Vector3.UP, turn) * Vector3(0, 0.96, -0.05)), Vector3(0.49, 0.82, 0.55), yaw + turn, null)
	count += 1
	_wc_piece(&"box", p, Vector3(0, 0.96, -0.19), Vector3(0.49, 0.82, 0.27), WHITE, turn, false, KitTarget.Finish.GLOSS)
	# Recessed back, porcelain cheeks and a projecting open drain trough.
	_wc_piece(&"box", p, Vector3(0, 0.98, -0.046), Vector3(0.34, 0.50, 0.018), Color(0.39, 0.48, 0.44), turn, false, KitTarget.Finish.GLOSS)
	for side in [-1.0, 1.0]:
		_wc_piece(&"box", p, Vector3(side * 0.205, 0.93, 0.015), Vector3(0.07, 0.62, 0.18), WHITE, turn, false, KitTarget.Finish.GLOSS)
	_wc_ring(p, 0.66, Vector2(0.20, 0.16), 0.07, WHITE, turn)
	_wc_piece(&"cylinder", p, Vector3(0, 0.638, 0.015), Vector3(0.27, 0.012, 0.21), Color(0.28, 0.38, 0.37), turn, false, KitTarget.Finish.GLOSS)
	_wc_piece(&"cylinder", p, Vector3(0, 0.65, 0.025), Vector3(0.05, 0.009, 0.05), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"cylinder", p, Vector3(0, 1.43, -0.25), Vector3(0.027, 0.30, 0.027), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0, 1.61, -0.24), Vector3(0.10, 0.09, 0.08), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0.37, 0.99, -0.035), Vector3(0.04, 1.30, 0.65), panel, turn, true, KitTarget.Finish.SATIN)


func _wc_basins(preferred: Vector3, turn: float) -> void:
	if count + 4 > 40: return
	var p := _furniture_spot(preferred, Vector3(1.76, 2.24, 0.98), turn)
	if not p.is_finite(): return
	turn = PI * 0.5 if p.x < 0.0 else -PI * 0.5
	_wc_piece(&"box", p, Vector3(0, 0.39, 0), Vector3(1.48, 0.72, 0.61), WHITE, turn, true, KitTarget.Finish.SATIN)
	for dx in [-0.38, 0.38]:
		var bowl := p + Basis(Vector3.UP, turn) * Vector3(dx, 0, 0.035)
		_wc_piece(&"cylinder", bowl, Vector3(0, 0.756, 0), Vector3(0.31, 0.018, 0.24), Color(0.40, 0.48, 0.44), turn, false, KitTarget.Finish.GLOSS)
		_wc_ring(bowl, 0.782, Vector2(0.20, 0.155), 0.055, WHITE, turn)
		_wc_ring(bowl, 0.836, Vector2(0.24, 0.19), 0.035, WHITE, turn)
		_wc_piece(&"cylinder", bowl, Vector3(0, 0.768, 0.02), Vector3(0.045, 0.007, 0.045), STEEL, turn, false, KitTarget.Finish.METAL)
		_wc_piece(&"cylinder", p, Vector3(dx, 0.993, -0.225), Vector3(0.033, 0.30, 0.033), STEEL, turn, false, KitTarget.Finish.METAL)
		_wc_piece(&"box", p, Vector3(dx, 1.133, -0.14), Vector3(0.035, 0.035, 0.18), STEEL, turn, false, KitTarget.Finish.METAL)
		_wc_piece(&"box", p, Vector3(dx, 1.175, -0.225), Vector3(0.085, 0.015, 0.05), STEEL, turn, false, KitTarget.Finish.METAL)
		_wc_piece(&"box", p, Vector3(dx, 0.41, 0.313), Vector3(0.045, 0.16, 0.015), STEEL, turn, false, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0, 1.58, -0.405), Vector3(1.47, 0.93, 0.045), DARK, turn, true)
	_wc_piece(&"box", p, Vector3(0, 1.58, -0.374), Vector3(1.37, 0.83, 0.018), Color(0.66, 0.77, 0.79), turn, false, KitTarget.Finish.MIRROR)
	_wc_piece(&"box", p, Vector3(-0.69, 1.08, -0.30), Vector3(0.17, 0.28, 0.16), WHITE, turn, true)
	_wc_piece(&"box", p, Vector3(-0.69, 1.005, -0.21), Vector3(0.075, 0.025, 0.035), DARK, turn)
	_wc_piece(&"box", p, Vector3(0.73, 1.20, -0.27), Vector3(0.25, 0.34, 0.20), STEEL, turn, true, KitTarget.Finish.METAL)
	_wc_piece(&"box", p, Vector3(0.73, 0.98, -0.155), Vector3(0.17, 0.18, 0.014), WHITE, turn)
	_sign(28, p + Basis(Vector3.UP, turn) * Vector3(0, 2.12, -0.37), Vector2(1.25, 0.18), turn)
	_wc_piece(&"box", p, Vector3(0, 0.027, 0.37), Vector3(0.19, 0.006, 0.19), STEEL, turn, false, KitTarget.Finish.METAL)
	for dx in [-0.065, -0.022, 0.022, 0.065]:
		_wc_piece(&"box", p, Vector3(dx, 0.031, 0.37), Vector3(0.012, 0.003, 0.14), DARK, turn)
	site["basin_points"] = [_point(p + Vector3.UP * 0.84)]


func _wc() -> void:
	_entrance_sign(5)
	var theme := StringName(site.get("theme", &"yard"))
	var variant := 0 if theme == &"yard" else (1 if theme == &"foundry" else 2)
	var panel: Color = [Color(0.29, 0.46, 0.40), Color(0.39, 0.43, 0.53), Color(0.47, 0.34, 0.26)][variant]
	var wear := rng.randf_range(0.35, 0.70) + float(variant) * 0.12
	var key := "%s:%s" % [theme, center.y]
	# Cache only sector-wide tile finishes; seed-dependent wear is painted on
	# the stall panels so rebuilding a seed cannot inherit another room's wear.
	var texture_seed := float(variant * 37)
	var surface_wear := 0.46 + float(variant) * 0.16
	_lining(_surface(TILE, "wcwall:" + key, {"base_y": center.y, "band_color": panel, "wear": surface_wear, "wear_seed": texture_seed}), _surface(TILE, "wcfloor:" + key, {"is_floor": true, "wear": surface_wear, "wear_seed": texture_seed}))
	# Two protected lamps keep the sanitary fittings readable, with one
	# local-light request only; hardware remains in the shared paint batches.
	for z in [-half.y * 0.48, half.y * 0.38]:
		_box(Vector3(0, height - 0.13, z), Vector3(0.40, 0.08, 1.20), STEEL)
		_box(Vector3(0, height - 0.185, z), Vector3(0.31, 0.035, 1.10), WHITE, false, KitTarget.Finish.GLOSS, 2.5)
	target.add_light(_point(Vector3(0.65, minf(height - 0.45, 2.75), -0.55)), Color(0.88, 0.94, 1.0), 1.8, 7.0)
	_sign(6 if variant == 2 else 5, Vector3(0, 2.30, half.y - 0.08), Vector2(1.6, 0.52), PI)
	_sign(7, Vector3(0, 2.26, -half.y + 0.08), Vector2(1.8, 0.36))
	site["toilet_points"] = [] as Array[Vector3]
	var sx := half.x - 1.03
	if sx < AISLE_HALF + 0.96: return
	var stalls := mini(3, maxi(1, int((half.y * 2.0 - 1.8) / 1.85)))
	var stagger := rng.randf_range(0.0, 0.14)
	for n in stalls:
		_wc_stall(Vector3(sx, 0, -half.y + 1.02 + n * 1.85 + stagger), -PI * 0.5, panel, n > 0 or variant == 2, wear)
	for n in (1 if variant == 2 else 2):
		_wc_urinal(Vector3(-half.x + 0.49, 0, -half.y + 0.85 + n * 1.08), PI * 0.5, panel)
	_wc_basins(Vector3(-half.x + 0.61, 0, 0.72 if variant == 2 else 0.55), PI * 0.5)
	# The Czech attendant desk is a whole reserved assembly, including chair;
	# no turnstile arm or payment furniture crosses the shared public aisle.
	var desk := _furniture_spot(Vector3(sx, 0, half.y - 0.73), Vector3(1.38, 1.42, 1.18))
	if desk.is_finite() and count + 2 <= 40:
		_box(desk + Vector3(0, 0.44, 0.20), Vector3(1.18, 0.84, 0.58), WOOD, true)
		_box(desk + Vector3(0, 0.885, 0.20), Vector3(1.28, 0.055, 0.66), WOOD.lightened(0.13))
		_box(desk + Vector3(0, 0.47, -0.39), Vector3(0.43, 0.90, 0.38), DARK, true)
		_shape(&"cylinder", desk + Vector3(-0.27, 0.925, 0.29), Vector3(0.21, 0.025, 0.21), WHITE)
		for n in 6:
			_shape(&"cylinder", desk + Vector3(-0.27 + rng.randf_range(-0.055, 0.055), 0.946, 0.29 + rng.randf_range(-0.055, 0.055)), Vector3(0.029, 0.006, 0.029), Color(0.70, 0.62, 0.39), false, KitTarget.Finish.METAL)
		_box(desk + Vector3(0.32, 1.02, 0.13), Vector3(0.31, 0.22, 0.22), DARK)
		_box(desk + Vector3(0.32, 1.139, 0.13), Vector3(0.24, 0.018, 0.15), STEEL)
		_sign(19, desk + Vector3(0, 0.63, 0.515), Vector2(0.78, 0.23))
		_sign(27, desk + Vector3(0, 1.31, 0.12), Vector2(0.90, 0.23))


func _portable() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * (half.x - 0.8)
		# Retain two complete real cabins, relocating each whole assembly around
		# the machine approaches. Only these external props use an envelope.
		var p := _furniture_spot(Vector3(x, 1.15, -half.y + 0.85), Vector3(1.3, 2.3, 1.4))
		if not p.is_finite(): continue
		target.add_solid(_point(p), Vector3(1.3, 2.3, 1.4), yaw, null)
		count += 1
		var cabin_color := BLUE if side < 0.0 else BLUE.lightened(0.08)
		for dx in [-0.59, 0.59]:
			_box(p + Vector3(dx, 0, 0), Vector3(0.08, 2.2, 1.25), cabin_color)
			for dz in [-0.43, -0.17, 0.10, 0.37]:
				_box(p + Vector3(dx + signf(dx) * 0.044, -0.05, dz), Vector3(0.018, 1.86, 0.055), cabin_color.lightened(0.10))
		_box(p + Vector3(0, 0, -0.59), Vector3(1.25, 2.2, 0.08), cabin_color)
		_box(p + Vector3(0, 1.12, 0), Vector3(1.3, 0.14, 1.3), WHITE)
		# The base panel is above the street, never an invisible below-floor slab.
		_box(p + Vector3(0, -1.09, 0), Vector3(1.20, 0.08, 1.20), DARK)
		for dx in [-0.3, 0, 0.3]:
			_box(p + Vector3(dx, 1.2, -0.35), Vector3(0.18, 0.03, 0.3), DARK)
		var door_turn := 1.16
		var hinge := p + Vector3(-0.55, 0, 0.59)
		var door := hinge + Basis(Vector3.UP, door_turn) * Vector3(0.42, 0, 0)
		_box(door, Vector3(0.84, 2.03, 0.06), cabin_color, false, KitTarget.Finish.SATIN, 0, door_turn)
		_sign(25, door + Basis(Vector3.UP, door_turn) * Vector3(0, 0.53, 0.04), Vector2(0.48, 0.32), door_turn)
		_sign(10, door + Basis(Vector3.UP, door_turn) * Vector3(0, 0.0, 0.04), Vector2(0.25, 0.12), door_turn)
		_box(hinge + Basis(Vector3.UP, door_turn) * Vector3(0.68, 0, 0.05), Vector3(0.035, 0.14, 0.045), STEEL, false, KitTarget.Finish.METAL, 0, door_turn)
		_toilet(p.x + 0.07, p.z - 0.18, 0.0, false)
		_box(p + Vector3(0.47, -0.43, -0.19), Vector3(0.13, 0.17, 0.16), WHITE)
		_box(p + Vector3(0.44, -0.10, -0.38), Vector3(0.15, 0.28, 0.12), WHITE)
		# A roof-height notice faces the open approach without covering the
		# cabin's door badges or introducing another collision envelope.
		_quote_board(_transform(p + Vector3(0, 1.54, 0.62), Vector3.ONE), Vector2(1.25, 0.62), true, 1)


func _glass(x: float, z: float, y: float) -> void:
	_shape(&"cylinder", Vector3(x, y, z), Vector3(0.11, 0.19, 0.11), Color(0.83, 0.55, 0.08), false, KitTarget.Finish.GLOSS)
	_shape(&"cylinder", Vector3(x, y + 0.105, z), Vector3(0.11, 0.035, 0.11), WHITE)
	_box(Vector3(x + 0.075, y, z), Vector3(0.045, 0.12, 0.035), STEEL)


func _pub(snack: bool) -> void:
	_entrance_sign(23 if snack else 15)
	var variant := rng.randi_range(0, 2)
	var side := -1.0 if variant == 1 else 1.0
	var turn := -side * PI * 0.5
	_room_shell(Color(0.76, 0.72, 0.58) if not snack else Color(0.81, 0.82, 0.75), WOOD if not snack else Color(0.2, 0.32, 0.33))
	_tubes()
	target.add_light(_point(Vector3(0, height - 0.4, 0)), Color(0.8, 0.88, 1.0), 0.7, maxf(5.0, half.length()))
	var length := minf(3.4, half.y * 1.1)
	var bar := _room_assembly(Vector3(side * (half.x - 1.0), 1.1, -half.y * 0.22), Vector3(length, 2.2, 1.75), turn)
	if bar.is_finite():
		side = signf(bar.x)
		turn = -side * PI * 0.5
		_room_piece(bar, Vector3(0, -0.56, 0.28), Vector3(length - 0.1, 1.08, 0.85), WOOD if not snack else WHITE, turn)
		_room_piece(bar, Vector3(0, 0.04, 0.28), Vector3(length, 0.12, 1.02), DARK, turn, KitTarget.Finish.SATIN)
		_room_piece(bar, Vector3(0, -0.9, 0.79), Vector3(length - 0.2, 0.05, 0.05), STEEL, turn, KitTarget.Finish.METAL)
		for n in 6:
			_room_piece(bar, Vector3(-length * 0.42 + n * length * 0.168, -0.48, 0.72), Vector3(0.045, 0.85, 0.025), Color(0.44, 0.27, 0.13), turn)
		_room_piece(bar, Vector3(0, 0.32, -0.71), Vector3(length - 0.12, 1.42, 0.08), DARK, turn)
		for row in 3:
			_room_piece(bar, Vector3(0, -0.16 + row * 0.46, -0.49), Vector3(length - 0.16, 0.055, 0.4), WOOD if not snack else STEEL, turn)
			for n in 7:
				var offset := Vector3(-length * 0.38 + n * length * 0.125, row * 0.46, -0.47)
				_room_bottle(bar, offset, turn, Color(0.13, 0.33, 0.16) if (n + row) % 2 == 0 else Color(0.42, 0.23, 0.08), 0.24)
		if snack:
			# Nonstop: hot-food display, espresso machine and refrigerated base.
			_room_piece(bar, Vector3(-0.65, 0.31, 0.32), Vector3(0.9, 0.45, 0.68), STEEL, turn, KitTarget.Finish.METAL)
			_room_piece(bar, Vector3(-0.65, 0.35, 0.67), Vector3(0.78, 0.26, 0.018), Color(0.17, 0.28, 0.3), turn, KitTarget.Finish.GLOSS)
			for n in 4:
				_room_piece(bar, Vector3(-0.94 + n * 0.19, 0.31, 0.69), Vector3(0.16, 0.06, 0.06), Color(0.77, 0.49, 0.18), turn)
			_room_piece(bar, Vector3(0.58, 0.3, 0.23), Vector3(0.65, 0.42, 0.46), DARK, turn, KitTarget.Finish.METAL)
			_room_piece(bar, Vector3(0.58, 0.34, 0.47), Vector3(0.49, 0.13, 0.04), STEEL, turn)
			_room_piece(bar, Vector3(0.58, 0.57, 0.23), Vector3(0.25, 0.12, 0.25), Color(0.25, 0.12, 0.055), turn)
			_room_sign(23, bar, Vector3(0, 0.88, -0.42), Vector2(1.4, 0.3), turn, 0.5)
		else:
			# Hospoda: two chrome beer taps with wooden handles, drip tray, mugs.
			for dx in [-0.26, 0.26]:
				_shape(&"cylinder", bar + Basis(Vector3.UP, turn) * Vector3(dx, 0.3, 0.22), Vector3(0.065, 0.43, 0.065), STEEL, false, KitTarget.Finish.METAL)
				_room_piece(bar, Vector3(dx, 0.47, 0.37), Vector3(0.05, 0.04, 0.3), STEEL, turn)
				_room_piece(bar, Vector3(dx, 0.57, 0.33), Vector3(0.04, 0.19, 0.04), WOOD, turn)
			_room_piece(bar, Vector3(0, 0.11, 0.47), Vector3(0.9, 0.025, 0.32), STEEL, turn, KitTarget.Finish.METAL)
			for dx in [-0.65, 0.66]:
				var mug := bar + Basis(Vector3.UP, turn) * Vector3(dx, 0.22, 0.52)
				_glass(mug.x, mug.z, mug.y)
			_room_sign(29, bar, Vector3(0, 0.88, -0.42), Vector2(1.2, 0.3), turn)
		# Countertop props sit within the already reserved bar envelope.
		var radio := bar + Basis(Vector3.UP, turn) * Vector3(-length * 0.41, 0.105, -0.21)
		target.add_model(RADIO, _transform(radio, Vector3.ONE * 1.35, turn))
		var plant := bar + Basis(Vector3.UP, turn) * Vector3(length * 0.38, 0.105, 0.12)
		target.add_model(PLANT, _transform(plant, Vector3.ONE * 2.1, turn))
		site["countertop_point"] = _point(bar + Basis(Vector3.UP, turn) * Vector3(0, 0.105, 0.05))
		site["countertop_facing"] = Basis(Vector3.UP, yaw + turn) * Vector3.BACK
	var table_count := 2 if snack else 3
	for n in table_count:
		_room_table(Vector3(-side * (half.x - 1.05), 0.55, -half.y + 1.55 + n * 2.8), variant, snack)
	_sign(23 if snack else 15, Vector3(0, minf(2.35, height - 0.35), -half.y + 0.09), Vector2(2.1, 0.6), 0, 0.7)
	_room_notice(-side, half.y * 0.25, 17, WOOD, variant)
	_room_notice(side, half.y * 0.45, 30 if snack else 16, Color(0.51, 0.24, 0.09), variant)
	if not snack:
		var dart := Vector3(-side * (half.x - 0.09), 1.7, 0)
		if _clear(dart, Vector3(0.12, 0.65, 0.65)):
			_box(dart, Vector3(0.05, 0.62, 0.62), Color(0.6, 0.15, 0.1))
			_box(dart + Vector3(side * 0.035, 0, 0), Vector3(0.02, 0.4, 0.4), DARK)
			_box(dart + Vector3(side * 0.05, 0, 0), Vector3(0.02, 0.08, 0.08), Color(0.2, 0.5, 0.2))
	for lx in [-half.x * 0.5, half.x * 0.5]:
		_box(Vector3(lx, height - 0.18, 0), Vector3(0.035, 0.3, 0.035), DARK)
		_shape(&"sphere", Vector3(lx, height - 0.35, 0), Vector3(0.45, 0.25, 0.45), Color(0.85, 0.62, 0.25), false, KitTarget.Finish.GLOSS, 1.5)


func _herna() -> void:
	_entrance_sign(18)
	var variant := rng.randi_range(0, 2)
	var accent: Color = [Color(0.4, 0.08, 0.24), Color(0.08, 0.25, 0.38), Color(0.38, 0.24, 0.08)][variant]
	_room_shell(Color(0.25, 0.23, 0.26), accent)
	_tubes()
	target.add_light(_point(Vector3(0, height - 0.4, 0)), Color(0.78, 0.85, 1.0), 0.65, maxf(5.0, half.length()))
	_sign(18, Vector3(0, minf(2.3, height - 0.4), -half.y + 0.12), Vector2(2.5, 0.7), 0, 0.8)
	var desk := _room_assembly(Vector3(half.x - 1.0, 1.0, half.y - 1.3), Vector3(1.6, 2.0, 0.95), -PI * 0.5)
	if desk.is_finite():
		_room_piece(desk, Vector3(0, -0.46, 0), Vector3(1.55, 1.08, 0.85), accent, -PI * 0.5)
		_room_piece(desk, Vector3(0, 0.15, 0), Vector3(1.6, 0.12, 0.95), DARK, -PI * 0.5)
		_room_piece(desk, Vector3(0, 0.53, 0.15), Vector3(1.5, 0.66, 0.035), Color(0.19, 0.26, 0.29), -PI * 0.5, KitTarget.Finish.GLOSS)
		for dx in [-0.7, 0.7]:
			_room_piece(desk, Vector3(dx, 0.54, 0.19), Vector3(0.04, 0.72, 0.04), STEEL, -PI * 0.5)
		_room_sign(19, desk, Vector3(0, 0.88, 0.22), Vector2(1.3, 0.22), -PI * 0.5)
	_room_notice(-1.0, half.y * 0.55, 21, accent, variant)
	_room_notice(1.0, half.y * 0.1, 18, accent, (variant + 1) % 3)


func _shop() -> void:
	_entrance_sign(20)
	var variant := rng.randi_range(0, 2)
	var side := -1.0 if variant == 1 else 1.0
	_room_shell(Color(0.8, 0.81, 0.71), Color(0.33, 0.46, 0.29))
	_tubes()
	target.add_light(_point(Vector3(0, height - 0.35, 0)), Color(0.85, 0.94, 1.0), 0.75, maxf(5.0, half.length()))
	_sign(20, Vector3(0, minf(2.35, height - 0.35), -half.y + 0.07), Vector2(2.3, 0.6))
	for n in (3 if variant == 2 else 2):
		var turn := side * PI * 0.5
		var p := _room_assembly(Vector3(-side * (half.x - 0.52), 1.0, -half.y + 1.3 + n * 2.25), Vector3(1.9, 2.0, 0.72), turn)
		if not p.is_finite(): continue
		_room_piece(p, Vector3(0, 0, -0.28), Vector3(1.88, 1.95, 0.06), Color(0.46, 0.51, 0.41), turn)
		for dx in [-0.9, 0.9]:
			_room_piece(p, Vector3(dx, 0, 0), Vector3(0.05, 2.0, 0.63), STEEL, turn)
		for row in 4:
			var y := -0.75 + row * 0.43
			_room_piece(p, Vector3(0, y, 0), Vector3(1.85, 0.045, 0.65), WHITE, turn)
			_shop_goods(p, y + 0.17, turn, (row + variant) % 3)
			for price in 4:
				_room_piece(p, Vector3(-0.67 + price * 0.44, y - 0.02, 0.335), Vector3(0.13, 0.055, 0.015), Color(0.9, 0.78, 0.34), turn)
	var turn := -side * PI * 0.5
	var fridge := _room_assembly(Vector3(side * (half.x - 0.62), 1.1, -half.y + 1.2), Vector3(1.15, 2.2, 1.05), turn)
	if fridge.is_finite():
		_room_piece(fridge, Vector3.ZERO, Vector3(1.1, 2.16, 0.8), WHITE, turn)
		_room_piece(fridge, Vector3(0, -0.03, 0.41), Vector3(0.94, 1.67, 0.03), Color(0.09, 0.18, 0.21), turn, KitTarget.Finish.GLOSS)
		for row in 3:
			_room_piece(fridge, Vector3(0, -0.67 + row * 0.5, 0.43), Vector3(0.91, 0.025, 0.06), STEEL, turn)
			for n in 5:
				_room_bottle(fridge, Vector3(-0.36 + n * 0.18, -0.51 + row * 0.5, 0.43), turn, Color(0.17, 0.43, 0.2) if row % 2 == 0 else Color(0.53, 0.27, 0.08), 0.27)
		_room_piece(fridge, Vector3(0.43, -0.03, 0.46), Vector3(0.035, 1.6, 0.035), WHITE, turn, KitTarget.Finish.GLOSS, 0.7)
		_room_sign(30, fridge, Vector3(0, 0.92, 0.43), Vector2(0.92, 0.2), turn, 0.3)
	var till := _room_assembly(Vector3(side * (half.x - 0.85), 0.8, half.y - 1.3), Vector3(1.75, 1.6, 1.1), turn)
	if till.is_finite():
		_room_piece(till, Vector3(0, -0.3, 0), Vector3(1.65, 1.0, 0.92), WOOD, turn)
		_room_piece(till, Vector3(0, 0.25, 0), Vector3(1.75, 0.1, 1.03), DARK, turn)
		_room_piece(till, Vector3(0.35, 0.4, 0.07), Vector3(0.38, 0.22, 0.34), STEEL, turn)
		_room_piece(till, Vector3(0.35, 0.58, -0.05), Vector3(0.33, 0.22, 0.055), Color(0.14, 0.28, 0.23), turn, KitTarget.Finish.GLOSS, 0.3)
		_room_sign(19, till, Vector3(-0.38, 0.53, 0.15), Vector2(0.65, 0.23), turn)
		for n in 4:
			_room_piece(till, Vector3(-0.57 + n * 0.22, 0.4, 0.43), Vector3(0.17, 0.19, 0.12), Color(0.73, 0.21 + n * 0.1, 0.1), turn)
	_room_notice(side, half.y * 0.1, 22, Color(0.33, 0.46, 0.29), variant)
	_room_notice(-side, half.y * 0.48, 21, Color(0.8, 0.62, 0.16), variant)
	var crates := _room_assembly(Vector3(-side * (half.x - 0.7), 0.48, half.y - 1.0), Vector3(1.1, 0.96, 0.95), side * PI * 0.5)
	if crates.is_finite():
		for row in 2:
			_room_piece(crates, Vector3(0, -0.24 + row * 0.44, 0), Vector3(1.05, 0.4, 0.8), Color(0.19, 0.35, 0.17), side * PI * 0.5)
			for n in 5:
				_room_piece(crates, Vector3(-0.4 + n * 0.2, -0.21 + row * 0.44, 0.41), Vector3(0.11, 0.21, 0.015), DARK, side * PI * 0.5)


func _room_assembly(preferred: Vector3, size: Vector3, turn: float = 0.0) -> Vector3:
	# One collider and one reserved envelope per detailed furniture assembly.
	# Do not emit the visible parts when the whole assembly cannot be placed.
	if count >= 40: return Vector3(INF, INF, INF)
	var p := _furniture_spot(preferred, size, turn)
	if not p.is_finite(): return p
	target.add_solid(_point(p), size, yaw + turn, null)
	count += 1
	return p


func _room_piece(p: Vector3, offset: Vector3, size: Vector3, color: Color, turn: float = 0.0, finish: int = KitTarget.Finish.MATTE, glow: float = 0.0) -> void:
	_box(p + Basis(Vector3.UP, turn) * offset, size, color, false, finish, glow, turn)


func _room_sign(cell: int, p: Vector3, offset: Vector3, size: Vector2, turn: float = 0.0, glow: float = 0.0) -> void:
	var position := p + Basis(Vector3.UP, turn) * offset
	var scale := Vector3(size.x, size.y, 0.025)
	if Rect2(-half, half * 2.0).encloses(_footprint(position, scale, turn)):
		target.add_sign(_transform(position, scale, turn), cell, 1, glow)


func _room_shell(plaster: Color, dado: Color) -> void:
	# Reuse the shared terrazzo batch; plaster/wainscot use the world palette.
	# Wall spans come from the same portal cuts as the station and WC lining.
	target.add_visual(&"box", _transform(Vector3(0, 0.012, 0), Vector3(half.x * 2 - 0.08, 0.018, half.y * 2 - 0.08)), _surface(TERRAZZO, "terrazzo", {}))
	_wall_segments(_room_wall_segment.bind(plaster, dado))


func _room_wall_segment(side_axis: bool, edge: float, start: float, end: float, plaster: Color, dado: Color) -> void:
	if end - start < 0.04: return
	var middle := (start + end) * 0.5
	var inset := edge - signf(edge) * 0.025
	var p := Vector3(inset, height * 0.5, middle) if side_axis else Vector3(middle, height * 0.5, inset)
	var size := Vector3(0.025, height - 0.04, end - start) if side_axis else Vector3(end - start, height - 0.04, 0.025)
	_box(p, size, plaster)
	target.add_solid(_point(p), size, yaw, null)
	count += 1
	# All wall trims are cut to the identical span, never bridged across a door.
	var inner := edge - signf(edge) * 0.052
	for band in 3:
		var y: float = [0.58, 1.18, 0.1][band]
		var h: float = [1.06, 0.055, 0.16][band]
		var trim_p := Vector3(inner, y, middle) if side_axis else Vector3(middle, y, inner)
		var trim_size := Vector3(0.028, h, end - start) if side_axis else Vector3(end - start, h, 0.028)
		_box(trim_p, trim_size, dado if band == 0 else DARK, false, KitTarget.Finish.SATIN if band == 1 else KitTarget.Finish.MATTE)
	for n in int((end - start) / 0.6):
		var along := start + 0.3 + n * 0.6
		var seam_p := Vector3(inner - signf(edge) * 0.016, 0.57, along) if side_axis else Vector3(along, 0.57, inner - signf(edge) * 0.016)
		_box(seam_p, Vector3(0.009, 0.97, 0.012) if side_axis else Vector3(0.012, 0.97, 0.009), dado.darkened(0.25))


func _room_notice(side: float, z: float, cell: int, accent: Color, variant: int) -> void:
	var p := Vector3(side * (half.x - 0.09), 1.75, z)
	var turn := -side * PI * 0.5
	if not _clear(p, Vector3(1.6, 1.3, 0.13), turn): return
	_room_piece(p, Vector3.ZERO, Vector3(1.55, 1.23, 0.065), STEEL, turn, KitTarget.Finish.METAL)
	_room_piece(p, Vector3(0, 0, 0.04), Vector3(1.45, 1.13, 0.012), Color(0.75, 0.72, 0.61), turn)
	_room_sign(cell, p, Vector3(0, 0.38, 0.055), Vector2(1.38, 0.27), turn, 0.1)
	if variant == 0:
		# Diagram with distinct route colours, station dots and legend bars.
		for row in 3:
			var color: Color = [Color(0.07, 0.48, 0.23), Color(0.75, 0.57, 0.05), Color(0.75, 0.09, 0.1)][row]
			_room_piece(p, Vector3(0, 0.1 - row * 0.18, 0.057), Vector3(1.14, 0.026, 0.009), color, turn)
			for n in 6:
				_room_piece(p, Vector3(-0.51 + n * 0.2, 0.1 - row * 0.18, 0.064), Vector3(0.055, 0.055, 0.007), WHITE, turn)
	else:
		# Concert/menu flyers and public notices, with visible paper margins.
		for n in 4:
			var x := -0.5 + n * 0.33
			_room_piece(p, Vector3(x, -0.12, 0.057), Vector3(0.28, 0.63, 0.009), WHITE if n % 2 == 0 else accent.lightened(0.4), turn)
			_room_piece(p, Vector3(x, 0.06, 0.065), Vector3(0.21, 0.15, 0.006), accent, turn)
			for row in 4:
				_room_piece(p, Vector3(x, -0.07 - row * 0.072, 0.065), Vector3(0.19, 0.014, 0.006), DARK, turn)


func _room_bottle(p: Vector3, offset: Vector3, turn: float, color: Color, h: float) -> void:
	var rotation := Basis(Vector3.UP, turn)
	_shape(&"cylinder", p + rotation * offset, Vector3(0.095, h * 0.72, 0.095), color, false, KitTarget.Finish.GLOSS)
	_shape(&"cylinder", p + rotation * (offset + Vector3(0, h * 0.43, 0)), Vector3(0.045, h * 0.28, 0.045), color, false, KitTarget.Finish.GLOSS)
	_room_piece(p, offset + Vector3(0, -0.005, 0.049), Vector3(0.073, h * 0.3, 0.012), WHITE, turn)


func _room_table(preferred: Vector3, variant: int, snack: bool) -> void:
	var p := _room_assembly(preferred, Vector3(1.65, 1.1, 2.35))
	if not p.is_finite(): return
	_box(p + Vector3(0, 0.21, 0), Vector3(1.5, 0.11, 0.8), WOOD if not snack else WHITE)
	for dx in [-0.55, 0.55]:
		_box(p + Vector3(dx, -0.14, 0), Vector3(0.09, 0.72, 0.59), DARK)
	for side in [-1.0, 1.0]:
		_box(p + Vector3(0, -0.09, side * 0.84), Vector3(1.45, 0.11, 0.47), WOOD if variant != 1 else Color(0.42, 0.1, 0.09))
		_box(p + Vector3(0, 0.19, side * 1.09), Vector3(1.45, 0.55, 0.075), WOOD)
		for dx in [-0.53, 0.53]:
			_box(p + Vector3(dx, -0.33, side * 0.84), Vector3(0.07, 0.42, 0.43), DARK)
	if not snack:
		_glass(p.x - 0.3, p.z, p.y + 0.36)
		_glass(p.x + 0.3, p.z + 0.12, p.y + 0.36)
	else:
		_box(p + Vector3(0.2, 0.34, 0.1), Vector3(0.22, 0.15, 0.16), Color(0.8, 0.2, 0.07))
	_box(p + Vector3(-0.48, 0.34, -0.16), Vector3(0.16, 0.16, 0.08), WHITE)
	_box(p + Vector3(-0.48, 0.43, -0.16), Vector3(0.11, 0.025, 0.09), WHITE)


func _shop_goods(p: Vector3, y: float, turn: float, kind: int) -> void:
	var colors: Array[Color] = [Color(0.74, 0.18, 0.08), Color(0.82, 0.68, 0.24), Color(0.12, 0.4, 0.23), Color(0.16, 0.33, 0.62)]
	for n in 8:
		var x := -0.77 + n * 0.22
		var color := colors[(n + kind) % colors.size()]
		if kind == 0:
			_room_bottle(p, Vector3(x, y, 0.17), turn, color, 0.26)
		elif kind == 1:
			_room_piece(p, Vector3(x, y, 0.12), Vector3(0.17, 0.29, 0.26), color, turn)
			_room_piece(p, Vector3(x, y + 0.04, 0.255), Vector3(0.11, 0.1, 0.012), WHITE, turn)
		else:
			_shape(&"cylinder", p + Basis(Vector3.UP, turn) * Vector3(x, y - 0.04, 0.15), Vector3(0.15, 0.2, 0.15), color, false, KitTarget.Finish.SATIN)
			_room_piece(p, Vector3(x, y - 0.04, 0.23), Vector3(0.1, 0.08, 0.01), WHITE, turn)


func _construction() -> void:
	# Inset fence fragments leave a perimeter route and a two-metre cross gate.
	var fence_length := half.y - OUTDOOR_MARGIN - AISLE_HALF
	for side in [-1.0, 1.0]:
		var x: float = side * (half.x - OUTDOOR_MARGIN - 0.1)
		for end in [-1.0, 1.0]:
			var z: float = end * (AISLE_HALF + fence_length * 0.5)
			var p := Vector3(x, 1.0, z)
			var size := Vector3(0.12, 2.1, fence_length)
			if fence_length < 0.3 or not _clear(p, size): continue
			_box(p, Vector3(0.08, 2, fence_length), STEEL, true)
			for dz in [-fence_length * 0.5 + 0.05, fence_length * 0.5 - 0.05]:
				_box(Vector3(x, 1, z + dz), Vector3(0.12, 2.1, 0.1), DARK)
	_sign(24, Vector3(0, 1.8, -half.y + 0.12), Vector2(minf(4.0, half.x * 1.7), 0.9))
	# Narrow real site equipment fits beside the spine even in a six-metre lot.
	var x := (AISLE_HALF + half.x - OUTDOOR_MARGIN) * 0.5
	var width := minf(1.1, half.x - OUTDOOR_MARGIN - AISLE_HALF - 0.1)
	var z := -half.y + OUTDOOR_MARGIN + 0.95
	var dumpster := Vector3(x, 0.6, z)
	if width > 0.6 and _clear(dumpster, Vector3(width, 1.2, 1.8)):
		_box(dumpster, Vector3(width, 1.2, 1.8), Color(0.62, 0.3, 0.07), true)
		_box(dumpster + Vector3.UP * 0.62, Vector3(width - 0.08, 0.03, 1.7), DARK)
	var cabin := Vector3(-x, 1.15, z)
	if width > 0.6 and _clear(cabin, Vector3(width, 2.3, 1.8)):
		_box(cabin, Vector3(width, 2.3, 1.8), Color(0.22, 0.34, 0.39), true)
		_sign(26, cabin + Vector3(0, 0.35, 0.93), Vector2(width - 0.1, 0.6))
	var rack := Vector3(x, 1.5, 0.0)
	if width > 0.6 and _clear(rack, Vector3(width, 3.0, 0.6)):
		for y in [0.1, 1.6, 2.9]:
			_box(Vector3(x, y, 0), Vector3(width, 0.06, 0.6), WOOD)
		for dx in [-width * 0.45, width * 0.45]:
			_box(Vector3(x + dx, 1.5, 0), Vector3(0.06, 3, 0.06), STEEL, true)
	_shape(&"sphere", Vector3(-x, 0.15, 0), Vector3(width, 0.7, 0.8), Color(0.57, 0.46, 0.29))
	for side in [-1.0, 1.0]:
		for n in 3:
			var p := Vector3(side * (half.x - 0.8), 0.25, -0.7 + n * 0.8)
			_box(p - Vector3(0, 0.2, 0), Vector3(0.35, 0.07, 0.35), DARK)
			_shape(&"cylinder", p, Vector3(0.2, 0.43, 0.2), Color(0.95, 0.29, 0.04))
			_shape(&"cylinder", p + Vector3(0, 0.06, 0), Vector3(0.21, 0.07, 0.21), WHITE)


func _park() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * (half.x - 1.4)
		for z in [-half.y + 1.8, half.y - 1.8]:
			var p := Vector3(x, 1.5, z)
			if not _clear(p, Vector3(0.55, 3, 0.55)): continue
			_shape(&"cylinder", p, Vector3(0.45, 3, 0.45), WOOD, true)
			_shape(&"sphere", p + Vector3(0, 2, 0), Vector3(2.5, 2.7, 2.5), Color(0.12, 0.26 + rng.randf() * 0.08, 0.08))
		_bench(side * (half.x - OUTDOOR_MARGIN - 0.4), 0, WOOD, PI * 0.5)
		_shape(&"cylinder", Vector3(x, 0.4, 1.4), Vector3(0.4, 0.8, 0.4), DARK, true)
		_box(Vector3(x, 1.8, -1.5), Vector3(0.08, 3.6, 0.08), DARK, true)
		_shape(&"sphere", Vector3(x, 3.7, -1.5), Vector3(0.35, 0.4, 0.35), Color(0.92, 0.75, 0.41), false, KitTarget.Finish.GLOSS, 1)
		_shape(&"sphere", Vector3(x, 0.18, -0.85), Vector3(0.6, 0.32, 1.7), Color(0.22, 0.27, 0.3))
