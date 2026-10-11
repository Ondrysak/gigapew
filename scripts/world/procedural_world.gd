class_name ProceduralWorld
extends Node3D

## Built synchronously in _ready, before the game configures horde navigation.
## A CELL_SIZE grid, identical to the horde grid, starts as solid rock. A themed
## plan carves irregular rooms; corridors of varying width (a spanning tree plus
## extra loops) join them and dead-end alcoves break their outlines. Unreachable
## pockets are refilled, and the remaining rock merges into exact axis-aligned
## blocks that physics, the horde and ore placement all read.
const CELL_SIZE := 2.0
const WALL_THICKNESS := 0.8
## Open floor kept around set pieces, cover islands and pillars (metres).
const PIECE_MARGIN := 4.0
## Ramp pitch matches the authored Yard ramps; walkable for player and horde.
const RAMP_ANGLE := 0.29
const RAMP_WIDTH := 4.2
const RAMP_THICKNESS := 0.6
## Outward normals of block faces: north, south, west, east.
const FACE_NORMALS: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
const ModuleBatch = preload("res://scenes/levels/yard/module_batch.gd")
const ZIZKOV_FLOOR = preload("res://shaders/zizkov_floor.gdshader")
const ZIZKOV_WALL = preload("res://shaders/zizkov_wall.gdshader")
const FOUNDRY_FLOOR = preload("res://shaders/foundry_floor.gdshader")
const REACTOR_FLOOR = preload("res://shaders/reactor_floor.gdshader")
const FLAT_WALL_ART = preload("res://assets/third_party/quaternius_megakit/WallAstra_Straight_Flat.gltf")
const REACTOR_WALL_ART = preload("res://assets/third_party/quaternius_megakit/WallAstra_Straight_Divided.gltf")
const FOUNDRY_STEEL = preload("res://scenes/levels/foundry/materials/foundry_steel.tres")
const FOUNDRY_WALL = preload("res://scenes/levels/foundry/materials/foundry_wall.tres")
const FOUNDRY_DARK = preload("res://scenes/levels/foundry/materials/foundry_dark.tres")
const VENUE_FRONT = preload("res://shaders/venue_front.gdshader")

## Storefront kit (visual only), see `_dress_storefront`.
const STORE_MIN_GAP := 3.4
## The shopfront is a plaster slab standing this far off the wall (covering the
## tenement's own ground-floor windows); every part sits in front of it.
const STORE_BASE := 0.18
const STORE_WALL := Color(0.4, 0.36, 0.29)
const STORE_SPACING := 9.0
const STORE_SALT := 0x53544F52
const STORE_FILLS := 4
const STORE_COUNT := {&"yard": 10, &"foundry": 6, &"reactor": 6}
const STORE_PLASTER := Color(0.5, 0.45, 0.36)
const STORE_DARK := Color(0.055, 0.048, 0.042)
const STORE_IRON := Color(0.055, 0.055, 0.06)
const STORE_WOOD := Color(0.24, 0.13, 0.07)
const STORE_PAPER := Color(0.82, 0.8, 0.7)
const STORE_INK := Color(0.09, 0.07, 0.1)
const STORE_CARD := Color(0.45, 0.33, 0.2)
const STORE_STEEL := Color(0.55, 0.56, 0.57)
const STORE_BLUE := Color(0.1, 0.17, 0.32)
const STORE_MUSTARD := Color(0.85, 0.64, 0.12)
const STORE_CONCRETE := Color(0.34, 0.33, 0.3)
const STORE_STONE := Color(0.6, 0.57, 0.5)

var level_seed: int
var mining_sites: Array[Dictionary] = []
## {center (deck top), size, height, foot, direction} per generated overlook.
var overlooks: Array[Dictionary] = []
var outcrops: Array[StaticBody3D] = []
## Walkable cells (1) on the CELL_SIZE grid from `layout_origin`; read by the radar.
var layout_open := PackedByteArray()
var layout_width := 0
var layout_height := 0
var layout_origin := Vector2.ZERO
## {bounds: Rect2i, kind: StringName, arena: bool, anchor: Vector2i, core: Rect2i}
var rooms: Array[Dictionary] = []
var _corridors: Array[Dictionary] = []
var _spawn_room := 0
var _stage: StageDefinition
var _rng := RandomNumberGenerator.new()
var _area: Rect2
var _theme: StringName
var _obstacles: Node3D
var _elevation: Node3D
var _decoration: Node3D
var _occupied: Array[Rect2] = []
var _wall_height: float
var _wall: Material
var _steel: Material
var _dark: Material
var _rock: Material
var _accent: Material
var _secondary: Material
var _accent_color: Color
var _secondary_color: Color
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _sphere := SphereMesh.new()
var _visual_batches: Dictionary = {}
## Batched dressing materials that skip the shadow pass (small facade detail).
var _shadowless: Dictionary = {}
## Žižkov (yard) palette, keyed by role; empty for the other themes.
var _props: Dictionary[StringName, Material] = {}
## Žižkov facade runs, recorded per open block face and dressed once every
## block and ore site exists: {mid, normal, length, height, along_x, key, sites}.
var _facade_runs: Array[Dictionary] = []

## Storefronts are visual dressing only. `storefronts_enabled` (set before the
## world enters the tree) off leaves the bare facades. `venue_override` (ids from
## the venue catalog; static so a lab can set it before a game builds its world)
## replaces the seeded lineup and relaxes the spacing.
var storefronts_enabled := true
static var venue_override: Array[StringName] = []
## {venue, position, normal, tangent, width, labels, reach, key} per storefront.
var venue_sites: Array[Dictionary] = []
var _store_batches: Dictionary = {}
var _venue_fills := 0
var _store_frames := 0
## Herna/Pivo face centres of the yard, kept apart from storefronts.
var _sign_points: Array[Vector3] = []
var _site: Dictionary = {}
## +1/-1: which end of the shopfront carries the door.
var _ds := 1.0

func configure(stage: StageDefinition, seed: int) -> void:
	assert(not is_inside_tree(), "Configure the procedural world before adding it to the tree.")
	_stage = stage
	level_seed = seed

func _ready() -> void:
	assert(_stage != null, "ProceduralWorld requires a stage and seed.")
	_area = _stage.play_area
	_theme = _stage.layout_theme
	_rng.seed = level_seed
	_box.size = Vector3.ONE
	_cylinder.top_radius = 1.0
	_cylinder.bottom_radius = 1.0
	_cylinder.height = 1.0
	_cylinder.radial_segments = 64
	_cylinder.rings = 1
	_sphere.radial_segments = 10
	_sphere.rings = 5
	_obstacles = Node3D.new()
	_obstacles.name = "Obstacles"
	add_child(_obstacles)
	# Decks and ramps: the horde rasterises their top faces into walkable height.
	_elevation = Node3D.new()
	_elevation.name = "Elevation"
	add_child(_elevation)
	_decoration = Node3D.new()
	_decoration.name = "Architecture"
	add_child(_decoration)
	_configure_theme()
	_build_floor()
	_build_perimeter()
	_generate_layout()
	_build_spawn()
	_build_solids()
	# The reactor core claims its floor before anything else is placed near it.
	for room in rooms:
		if room.kind == &"hub":
			_build_reactor_core(room)
	_build_set_pieces()
	_build_room_features()
	if _theme == &"yard":
		_build_zizkov_street()
	_build_guides()
	_build_lighting()
	_flush_visual_batches()
	# Storefronts wait until the game's deposit field has placed its machines (a few
	# physics frames), so they never stand under one; see `_physics_process`.
	set_physics_process(storefronts_enabled)

func _configure_theme() -> void:
	_wall_height = 5.0
	_accent_color = Color(0.12, 0.82, 0.92)
	_secondary_color = Color(1.0, 0.52, 0.15)
	_wall = _material(Color(0.075, 0.105, 0.145), 0.65, 0.45)
	_steel = _material(Color(0.15, 0.2, 0.255), 0.55, 0.5)
	_dark = _material(Color(0.035, 0.05, 0.07), 0.7, 0.5)
	_rock = _material(Color(0.16, 0.19, 0.22), 1.0, 0.05)
	if _theme == &"foundry":
		_wall_height = 6.0
		_wall = FOUNDRY_WALL
		_steel = FOUNDRY_STEEL
		_dark = FOUNDRY_DARK
		_rock = _material(Color(0.23, 0.14, 0.095), 1.0, 0.05)
		_accent_color = Color(1.0, 0.5, 0.12)
		_secondary_color = Color(1.0, 0.78, 0.25)
	elif _theme == &"reactor":
		_wall_height = 8.0
		_wall = _material(Color(0.085, 0.07, 0.15), 0.55, 0.7)
		_steel = _material(Color(0.22, 0.25, 0.28), 0.55, 0.8)
		_rock = _material(Color(0.15, 0.12, 0.23), 0.95, 0.1)
		_accent_color = Color(0.19, 0.92, 0.86)
		_secondary_color = Color(0.65, 0.33, 1.0)
	else:
		_configure_zizkov()
	_accent = _material(_accent_color, 0.4, 0.1, true)
	_secondary = _material(_secondary_color, 0.4, 0.1, true)

## Žižkov: plaster tenements, setts, sodium lamps, road paint and herna neon.
func _configure_zizkov() -> void:
	_accent_color = Color(0.95, 0.68, 0.24)
	_secondary_color = Color(0.95, 0.17, 0.1)
	var wall := ShaderMaterial.new()
	wall.shader = ZIZKOV_WALL
	_wall = wall
	var brick := ShaderMaterial.new()
	brick.shader = ZIZKOV_WALL
	brick.set_shader_parameter("brick_share", 1.0)
	_rock = brick
	var skyline := ShaderMaterial.new()
	skyline.shader = ZIZKOV_WALL
	skyline.set_shader_parameter("windows", true)
	_props[&"skyline"] = skyline
	_steel = _material(Color(0.34, 0.33, 0.31), 0.95, 0.0)
	_dark = _material(Color(0.05, 0.045, 0.04), 0.9, 0.0)
	for entry: Array in [
		[&"cornice", Color(0.6, 0.55, 0.46), 0.9, 0.0, true],
		[&"frame", Color(0.5, 0.45, 0.37), 0.8, 0.0, false],
		[&"glass", Color(0.02, 0.025, 0.035), 0.12, 0.3, false],
		[&"board", Color(0.3, 0.2, 0.12), 0.95, 0.0, false],
		[&"wood", Color(0.24, 0.13, 0.07), 0.7, 0.0, false],
		[&"iron", Color(0.055, 0.055, 0.06), 0.55, 0.6, true],
		[&"pipe", Color(0.32, 0.33, 0.34), 0.5, 0.5, false],
		[&"sign", Color(0.045, 0.035, 0.035), 0.6, 0.2, true],
		[&"bin", Color(0.3, 0.31, 0.3), 0.5, 0.6, true],
		[&"container", Color(0.12, 0.23, 0.15), 0.7, 0.4, true],
		[&"bag", Color(0.018, 0.018, 0.022), 0.3, 0.0, true],
		[&"bag_blue", Color(0.1, 0.17, 0.38), 0.35, 0.0, true],
		[&"paper", Color(0.62, 0.58, 0.5), 0.9, 0.0, false],
		[&"cardboard", Color(0.45, 0.33, 0.2), 0.95, 0.0, true],
		[&"roof", Color(0.2, 0.12, 0.085), 0.8, 0.1, true],
		[&"poster_column", Color(0.3, 0.34, 0.27), 0.8, 0.2, true],
		[&"graffiti_black", Color(0.025, 0.025, 0.03), 0.6, 0.0, false],
		[&"graffiti_red", Color(0.78, 0.12, 0.1), 0.6, 0.0, false],
		[&"graffiti_yellow", Color(0.9, 0.74, 0.15), 0.6, 0.0, false],
		[&"graffiti_green", Color(0.2, 0.58, 0.26), 0.6, 0.0, false],
		[&"graffiti_purple", Color(0.45, 0.2, 0.6), 0.6, 0.0, false],
		[&"graffiti_silver", Color(0.72, 0.74, 0.78), 0.35, 0.6, false],
	]:
		_props[entry[0]] = _material(entry[1], entry[2], entry[3])
		if not entry[4]:
			_shadowless[_props[entry[0]]] = true
	for entry: Array in [
		[&"glass_lit", Color(1.0, 0.64, 0.28), 1.1],
		[&"glass_tv", Color(0.45, 0.6, 1.0), 0.9],
		[&"sodium", Color(1.0, 0.6, 0.24), 3.0],
		[&"neon_red", Color(1.0, 0.1, 0.07), 3.0],
		[&"neon_yellow", Color(1.0, 0.76, 0.22), 2.6],
	]:
		var glow := _material(entry[1], 0.4, 0.0, true)
		glow.emission_energy_multiplier = entry[2]
		_props[entry[0]] = glow
		_shadowless[glow] = true

func _build_floor() -> void:
	var material := ShaderMaterial.new()
	match _theme:
		&"foundry": material.shader = FOUNDRY_FLOOR
		&"reactor": material.shader = REACTOR_FLOOR
		_: material.shader = ZIZKOV_FLOOR
	material.set_shader_parameter("area_center", _area.get_center())
	material.set_shader_parameter("area_half_extents", _area.size * 0.5)
	if _theme == &"foundry":
		material.set_shader_parameter("plate_origin", _area.position)
		material.set_shader_parameter("heat_edge_z", _area.position.y)
	var center := _area.get_center()
	_box_body(self, "Floor", Vector3(center.x, -0.5, center.y), Vector3(_area.size.x + 2.0, 1.0, _area.size.y + 2.0), material)

## Outer bounds only; the generated rock mass forms every visible inner wall.
func _build_perimeter() -> void:
	var center := _area.get_center()
	_box_body(self, "NorthWall", Vector3(center.x, _wall_height * 0.5, _area.position.y - WALL_THICKNESS * 0.5), Vector3(_area.size.x + WALL_THICKNESS * 2.0, _wall_height, WALL_THICKNESS), _wall)
	_box_body(self, "SouthWall", Vector3(center.x, _wall_height * 0.5, _area.end.y + WALL_THICKNESS * 0.5), Vector3(_area.size.x + WALL_THICKNESS * 2.0, _wall_height, WALL_THICKNESS), _wall)
	_box_body(self, "WestWall", Vector3(_area.position.x - WALL_THICKNESS * 0.5, _wall_height * 0.5, center.y), Vector3(WALL_THICKNESS, _wall_height, _area.size.y), _wall)
	_box_body(self, "EastWall", Vector3(_area.end.x + WALL_THICKNESS * 0.5, _wall_height * 0.5, center.y), Vector3(WALL_THICKNESS, _wall_height, _area.size.y), _wall)
	_build_skyline()

# ---------------------------------------------------------------- layout grid

func _generate_layout() -> void:
	layout_origin = _area.position
	layout_width = roundi(_area.size.x / CELL_SIZE)
	layout_height = roundi(_area.size.y / CELL_SIZE)
	layout_open.resize(layout_width * layout_height)
	layout_open.fill(0)
	match _theme:
		&"foundry": _plan_foundry()
		&"reactor": _plan_reactor()
		_: _plan_compound()
	_add_alcoves()
	# Ring cores go back in after corridors, which may have tunnelled through.
	for room in rooms:
		var core: Rect2i = room.core
		if core.has_area():
			_set_cells(core, 0)
	_spawn_room = _pick_spawn_room()
	_prune_unreachable(rooms[_spawn_room].anchor)

## Žižkov (yard): a compound of mixed-shape rooms with looping corridors.
func _plan_compound() -> void:
	for _index in maxi(1, _stage.overlook_count):
		_try_room(Vector2i(15, 11), Vector2i(18, 13), [&"hall"], true)
	for _index in 10 + _rng.randi_range(0, 2):
		_try_room(Vector2i(6, 6), Vector2i(13, 12), [&"l_shape", &"t_shape", &"cross", &"chamfer", &"ring", &"pillars", &"hall", &"disc"], false)
	_connect_rooms(0.4)

## Foundry: long stacked furnace halls, transfer passages and side chambers.
func _plan_foundry() -> void:
	var heights: Array[int] = []
	for index in 3:
		heights.append(10 if index < _stage.overlook_count else 6)
	_shuffle(heights)
	var used := 0
	for height in heights:
		used += height
	var gap := maxi(2, (layout_height - 4 - used) / 2)
	var z := 2
	var halls: Array[int] = []
	for height in heights:
		var length := _rng.randi_range(roundi(layout_width * 0.55), layout_width - 6)
		var x := _rng.randi_range(2, layout_width - 2 - length)
		var arena := height >= 10
		halls.append(_add_room(Rect2i(x, z, length, height), &"hall" if arena else &"pillars", arena))
		z += height + gap
	for _index in 4:
		_try_room(Vector2i(6, 6), Vector2i(9, 8), [&"chamfer", &"l_shape", &"hall", &"disc"], false)
	_connect_rooms(0.3)
	# Several short vertical transfer passages between neighbouring halls.
	for index in halls.size() - 1:
		var upper: Rect2i = rooms[halls[index]].bounds
		var lower: Rect2i = rooms[halls[index + 1]].bounds
		var from := maxi(upper.position.x, lower.position.x) + 2
		var to := mini(upper.end.x, lower.end.x) - 3
		if to <= from:
			continue
		for _passage in _rng.randi_range(2, 3):
			var x := _rng.randi_range(from, to)
			_carve_path([Vector2i(x, upper.get_center().y), Vector2i(x, lower.get_center().y)], _corridor_width())

## Reactor: a round hub around the core, narrow spokes in and a ring of chords out.
func _plan_reactor() -> void:
	var center := Vector2i(layout_width / 2, layout_height / 2)
	var hub := _add_room(Rect2i(center - Vector2i(8, 8), Vector2i(16, 16)), &"hub", false)
	for _index in maxi(1, _stage.overlook_count):
		_try_room(Vector2i(15, 11), Vector2i(17, 12), [&"hall"], true)
	for _index in 6:
		_try_room(Vector2i(7, 7), Vector2i(11, 10), [&"l_shape", &"chamfer", &"ring", &"pillars", &"disc", &"cross"], false)
	var outer: Array[int] = []
	for index in rooms.size():
		if index != hub:
			outer.append(index)
	var middle := Vector2(center)
	outer.sort_custom(func(a: int, b: int) -> bool:
		var va := Vector2(rooms[a].anchor) - middle
		var vb := Vector2(rooms[b].anchor) - middle
		return atan2(va.y, va.x) < atan2(vb.y, vb.x))
	for index in outer.size():
		var a: Vector2i = rooms[outer[index]].anchor
		var b: Vector2i = rooms[outer[(index + 1) % outer.size()]].anchor
		if a != b:
			_carve_line(Vector2(a) + Vector2(0.5, 0.5), Vector2(b) + Vector2(0.5, 0.5), 1.5)
	for index in outer.size():
		if index % 2 == 0 or outer.size() <= 3:
			_carve_line(middle, Vector2(rooms[outer[index]].anchor) + Vector2(0.5, 0.5), 1.0 + _rng.randf_range(0.0, 0.6))

func _try_room(min_size: Vector2i, max_size: Vector2i, kinds: Array[StringName], arena: bool) -> int:
	var region := Rect2i(2, 2, layout_width - 4, layout_height - 4)
	# Arenas must exist for their overlook, so they search much harder.
	for _attempt in 300 if arena else 80:
		var size := Vector2i(_rng.randi_range(min_size.x, max_size.x), _rng.randi_range(min_size.y, max_size.y))
		if _rng.randf() < 0.5:
			size = Vector2i(size.y, size.x)
		if size.x > region.size.x or size.y > region.size.y:
			continue
		var bounds := Rect2i(Vector2i(_rng.randi_range(region.position.x, region.end.x - size.x), _rng.randi_range(region.position.y, region.end.y - size.y)), size)
		var free := true
		for room in rooms:
			if (room.bounds as Rect2i).grow(2).intersects(bounds):
				free = false
				break
		if free:
			return _add_room(bounds, _pick_kind(kinds, size), arena)
	return -1

func _pick_kind(kinds: Array[StringName], size: Vector2i) -> StringName:
	var smallest := mini(size.x, size.y)
	var allowed: Array[StringName] = []
	for kind in kinds:
		var needed := 1
		match kind:
			&"ring": needed = 10
			&"pillars": needed = 9
			&"disc", &"l_shape", &"t_shape", &"cross": needed = 8
			&"chamfer": needed = 6
		if smallest >= needed:
			allowed.append(kind)
	return allowed[_rng.randi() % allowed.size()] if not allowed.is_empty() else &"hall"

func _add_room(bounds: Rect2i, kind: StringName, arena: bool) -> int:
	var room := {"bounds": bounds, "kind": kind, "arena": arena, "anchor": bounds.get_center(), "core": Rect2i()}
	var arm := Vector2i(maxi(4, roundi(bounds.size.x * 0.45)), maxi(4, roundi(bounds.size.y * 0.45)))
	match kind:
		&"l_shape":
			var band := Rect2i(bounds.position.x, bounds.position.y if _rng.randf() < 0.5 else bounds.end.y - arm.y, bounds.size.x, arm.y)
			var column := Rect2i(bounds.position.x if _rng.randf() < 0.5 else bounds.end.x - arm.x, bounds.position.y, arm.x, bounds.size.y)
			_set_cells(band, 1)
			_set_cells(column, 1)
			room.anchor = band.get_center()
		&"t_shape":
			var band := Rect2i(bounds.position.x, bounds.position.y if _rng.randf() < 0.5 else bounds.end.y - arm.y, bounds.size.x, arm.y)
			var stem := Rect2i(bounds.position.x + (bounds.size.x - arm.x) / 2, bounds.position.y, arm.x, bounds.size.y)
			_set_cells(band, 1)
			_set_cells(stem, 1)
			room.anchor = stem.get_center()
		&"cross":
			_set_cells(Rect2i(bounds.position.x, bounds.position.y + (bounds.size.y - arm.y) / 2, bounds.size.x, arm.y), 1)
			_set_cells(Rect2i(bounds.position.x + (bounds.size.x - arm.x) / 2, bounds.position.y, arm.x, bounds.size.y), 1)
		&"disc", &"hub":
			var middle := Vector2(bounds.position) + Vector2(bounds.size) * 0.5
			var radii := Vector2(bounds.size) * 0.5
			for z in range(bounds.position.y, bounds.end.y):
				for x in range(bounds.position.x, bounds.end.x):
					if ((Vector2(x + 0.5, z + 0.5) - middle) / radii).length_squared() <= 1.0:
						_set_cell(Vector2i(x, z), 1)
		&"ring":
			_set_cells(bounds, 1)
			room.core = bounds.grow(-3)
			room.anchor = Vector2i(bounds.position.x + 1, bounds.position.y + bounds.size.y / 2)
		&"chamfer":
			_set_cells(bounds, 1)
			var cut := maxi(1, mini(bounds.size.x, bounds.size.y) / 4)
			for corner: Vector2i in [bounds.position, Vector2i(bounds.end.x - cut, bounds.position.y), Vector2i(bounds.position.x, bounds.end.y - cut), bounds.end - Vector2i(cut, cut)]:
				_set_cells(Rect2i(corner, Vector2i(cut, cut)), 0)
		_:
			_set_cells(bounds, 1)
	rooms.append(room)
	return rooms.size() - 1

## A spanning tree guarantees one route everywhere; extra links add loops so
## the horde can flank and the player always has a second way out.
func _connect_rooms(loop_chance: float) -> void:
	if rooms.size() < 2:
		return
	var linked: Dictionary = {}
	var joined := PackedByteArray()
	joined.resize(rooms.size())
	joined[0] = 1
	for _step in rooms.size() - 1:
		var best := INF
		var pair := Vector2i(-1, -1)
		for a in rooms.size():
			if joined[a] == 0:
				continue
			for b in rooms.size():
				if joined[b] == 1:
					continue
				var distance := Vector2(rooms[a].anchor).distance_to(Vector2(rooms[b].anchor))
				if distance < best:
					best = distance
					pair = Vector2i(a, b)
		joined[pair.y] = 1
		_link(pair.x, pair.y, linked)
	for a in rooms.size():
		if _rng.randf() >= loop_chance:
			continue
		var best := INF
		var other := -1
		for b in rooms.size():
			if b == a or linked.has(Vector2i(mini(a, b), maxi(a, b))):
				continue
			var distance := Vector2(rooms[a].anchor).distance_to(Vector2(rooms[b].anchor))
			if distance < best:
				best = distance
				other = b
		if other >= 0:
			_link(a, other, linked)

func _link(a: int, b: int, linked: Dictionary) -> void:
	linked[Vector2i(mini(a, b), maxi(a, b))] = true
	var from: Vector2i = rooms[a].anchor
	var to: Vector2i = rooms[b].anchor
	var points: Array[Vector2i] = [from]
	if absi(to.x - from.x) > 8 and absi(to.y - from.y) > 4 and _rng.randf() < 0.45:
		# A dog-leg: across, down, across again.
		var bend := _rng.randi_range(mini(from.x, to.x) + 2, maxi(from.x, to.x) - 2)
		points.append(Vector2i(bend, from.y))
		points.append(Vector2i(bend, to.y))
	elif _rng.randf() < 0.5:
		points.append(Vector2i(to.x, from.y))
	else:
		points.append(Vector2i(from.x, to.y))
	points.append(to)
	_carve_path(points, _corridor_width())

## 4 m chokepoints, 6 m standard passages and occasional 8 m boulevards.
func _corridor_width() -> int:
	var roll := _rng.randf()
	return 2 if roll < 0.25 else (3 if roll < 0.8 else 4)

func _carve_path(points: Array[Vector2i], width: int) -> void:
	var offset := width / 2
	for index in points.size() - 1:
		var a := points[index]
		var b := points[index + 1]
		_set_cells(Rect2i(mini(a.x, b.x) - offset, mini(a.y, b.y) - offset, absi(b.x - a.x) + width, absi(b.y - a.y) + width), 1)
	# Guide line follows the corridor's true centre, in cell units.
	var shift := 0.5 if width % 2 == 1 else 0.0
	var line: Array[Vector2] = []
	for point in points:
		line.append(Vector2(point) + Vector2(shift, shift))
	_corridors.append({"line": line, "width": width})

## Straight (often diagonal) passage between two points in cell units.
func _carve_line(a: Vector2, b: Vector2, half_width: float) -> void:
	var low := Vector2i(floori(minf(a.x, b.x) - half_width), floori(minf(a.y, b.y) - half_width))
	var high := Vector2i(ceili(maxf(a.x, b.x) + half_width), ceili(maxf(a.y, b.y) + half_width))
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var middle := Vector2(x + 0.5, z + 0.5)
			if middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, a, b)) <= half_width:
				_set_cell(Vector2i(x, z), 1)
	var line: Array[Vector2] = [a, b]
	_corridors.append({"line": line, "width": roundi(half_width * 2.0)})

## Shallow dead-end pockets on room edges: cover to fall back into, or a trap.
func _add_alcoves() -> void:
	for _index in _rng.randi_range(3, 6):
		var bounds: Rect2i = rooms[_rng.randi() % rooms.size()].bounds
		var depth := _rng.randi_range(2, 3)
		var length := _rng.randi_range(3, 5)
		var along_x := _rng.randi_range(bounds.position.x, maxi(bounds.position.x, bounds.end.x - length))
		var along_z := _rng.randi_range(bounds.position.y, maxi(bounds.position.y, bounds.end.y - length))
		match _rng.randi_range(0, 3):
			0: _set_cells(Rect2i(along_x, bounds.position.y - depth, length, depth), 1)
			1: _set_cells(Rect2i(along_x, bounds.end.y, length, depth), 1)
			2: _set_cells(Rect2i(bounds.position.x - depth, along_z, depth, length), 1)
			_: _set_cells(Rect2i(bounds.end.x, along_z, depth, length), 1)

func _pick_spawn_room() -> int:
	var candidates: Array[int] = []
	for index in rooms.size():
		if not rooms[index].arena and rooms[index].kind != &"hub" and _open_at(rooms[index].anchor):
			candidates.append(index)
	if candidates.is_empty():
		for index in rooms.size():
			if _open_at(rooms[index].anchor):
				candidates.append(index)
	return candidates[_rng.randi() % candidates.size()] if not candidates.is_empty() else 0

func _prune_unreachable(start: Vector2i) -> void:
	var visited := PackedByteArray()
	visited.resize(layout_open.size())
	var queue: Array[int] = [start.y * layout_width + start.x]
	visited[queue[0]] = 1
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var x := cell % layout_width
		var z := cell / layout_width
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := Vector2i(x, z) + step
			if not _open_at(next):
				continue
			var index := next.y * layout_width + next.x
			if visited[index] == 0:
				visited[index] = 1
				queue.append(index)
	for index in layout_open.size():
		if visited[index] == 0:
			layout_open[index] = 0

## One cell of rock is always kept around the grid edge.
func _set_cell(cell: Vector2i, value: int) -> void:
	if cell.x >= 1 and cell.y >= 1 and cell.x < layout_width - 1 and cell.y < layout_height - 1:
		layout_open[cell.y * layout_width + cell.x] = value

func _set_cells(rect: Rect2i, value: int) -> void:
	for z in range(maxi(rect.position.y, 1), mini(rect.end.y, layout_height - 1)):
		for x in range(maxi(rect.position.x, 1), mini(rect.end.x, layout_width - 1)):
			layout_open[z * layout_width + x] = value

func _open_at(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < layout_width and cell.y < layout_height and layout_open[cell.y * layout_width + cell.x] == 1

func _cell_world(cell: Vector2) -> Vector2:
	return layout_origin + cell * CELL_SIZE

func _room_rect(room: Dictionary) -> Rect2:
	var bounds: Rect2i = room.bounds
	return Rect2(_cell_world(Vector2(bounds.position)), Vector2(bounds.size) * CELL_SIZE)

## Where a drop pod lands: the clear room spot farthest from `from`, so the
## extraction is a run through the level rather than a step to the side.
func extraction_point(from: Vector3) -> Vector3:
	var best: Vector3 = get_node("PlayerSpawn").position
	var best_distance := -1.0
	for room in rooms:
		for cell: Vector2i in [room.anchor, (room.bounds as Rect2i).get_center()]:
			if not _open_at(cell):
				continue
			var at := _cell_world(Vector2(cell) + Vector2(0.5, 0.5))
			if not _area_clear(Rect2(at - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), 1.0):
				continue
			var distance := at.distance_to(Vector2(from.x, from.z))
			if distance > best_distance:
				best_distance = distance
				best = Vector3(at.x, 0.0, at.y)
	return best

## True when the footprint plus margin lies on carved floor clear of other pieces.
func _area_clear(footprint: Rect2, margin: float) -> bool:
	var grown := footprint.grow(margin)
	var low := Vector2i(floori((grown.position.x - layout_origin.x) / CELL_SIZE), floori((grown.position.y - layout_origin.y) / CELL_SIZE))
	var high := Vector2i(ceili((grown.end.x - layout_origin.x) / CELL_SIZE) - 1, ceili((grown.end.y - layout_origin.y) / CELL_SIZE) - 1)
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			if not _open_at(Vector2i(x, z)):
				return false
	for occupied in _occupied:
		if occupied.intersects(grown):
			return false
	return true

func _shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var pick := _rng.randi_range(0, index)
		var swap = values[index]
		values[index] = values[pick]
		values[pick] = swap

# ---------------------------------------------------------------- geometry

func _build_spawn() -> void:
	var anchor: Vector2i = rooms[_spawn_room].anchor
	var at := _cell_world(Vector2(anchor) + Vector2(0.5, 0.5))
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(at.x, 0.05, at.y)
	# Face the level's centre of mass rather than the nearest wall.
	var toward := _area.get_center() - at
	if toward.length_squared() < 1.0:
		toward = Vector2(0.0, -1.0)
	spawn.rotation.y = atan2(-toward.x, -toward.y)
	add_child(spawn)
	_occupied.append(Rect2(at - Vector2(3.0, 3.0), Vector2(6.0, 6.0)))
	# Flush floor markings, never raised props on the landing pad.
	if _theme == &"yard":
		# Luďas wakes up on the yard's septic lid.
		_visual(_cylinder, _steel, Vector3(at.x, 0.005, at.y), Vector3(1.05, 0.01, 1.05))
		_visual(_cylinder, _props[&"iron"], Vector3(at.x, 0.012, at.y), Vector3(0.82, 0.012, 0.82))
		for bar in 5:
			_visual(_box, _dark, Vector3(at.x + (bar - 2) * 0.28, 0.02, at.y), Vector3(0.07, 0.01, 1.3 - absf(bar - 2) * 0.3))
		return
	_visual(_box, _accent, Vector3(at.x, 0.006, at.y - 1.8), Vector3(3.6, 0.01, 0.08))
	_visual(_box, _accent, Vector3(at.x, 0.006, at.y + 1.8), Vector3(3.6, 0.01, 0.08))

## Greedy rectangle merge of the remaining rock into exact blocks.
func _build_solids() -> void:
	var used := PackedByteArray()
	used.resize(layout_open.size())
	var index := 0
	for z in layout_height:
		for x in layout_width:
			var cell := z * layout_width + x
			if layout_open[cell] == 1 or used[cell] == 1:
				continue
			var width := 1
			while x + width < layout_width and layout_open[cell + width] == 0 and used[cell + width] == 0:
				width += 1
			var depth := 1
			while z + depth < layout_height:
				var row_free := true
				for dx in width:
					var other := (z + depth) * layout_width + x + dx
					if layout_open[other] == 1 or used[other] == 1:
						row_free = false
						break
				if not row_free:
					break
				depth += 1
			for dz in depth:
				for dx in width:
					used[(z + dz) * layout_width + x + dx] = 1
			_build_block(Rect2i(x, z, width, depth), index)
			index += 1

func _build_block(rect: Rect2i, index: int) -> void:
	var outer := rect.position.x == 0 or rect.position.y == 0 or rect.end.x == layout_width or rect.end.y == layout_height
	# Large inner masses vary in height for a broken skyline; small steps along
	# diagonal passages stay level, and nothing drops below the ore band.
	var height := _wall_height if outer or rect.get_area() < 6 else maxf(4.2, _wall_height + _rng.randf_range(-0.8, 2.5))
	var origin := _cell_world(Vector2(rect.position))
	var size := Vector2(rect.size) * CELL_SIZE
	var center := origin + size * 0.5
	var body := _box_body(_obstacles, "Rock%d" % index, Vector3(center.x, height * 0.5, center.y), Vector3(size.x, height, size.y), _wall)
	_visual(_box, _dark, Vector3(center.x, height + 0.006, center.y), Vector3(size.x * 0.98, 0.012, size.y * 0.98))
	for face in 4:
		var length := rect.size.x if face < 2 else rect.size.y
		var start := -1
		for step in length + 1:
			var open := step < length and _open_at(_face_cell(rect, face, step, 1))
			if open and start < 0:
				start = step
			elif not open and start >= 0:
				_dress_face(rect, face, start, step - start, body, height)
				start = -1

func _face_cell(rect: Rect2i, face: int, step: int, depth: int) -> Vector2i:
	match face:
		0: return Vector2i(rect.position.x + step, rect.position.y - depth)
		1: return Vector2i(rect.position.x + step, rect.end.y - 1 + depth)
		2: return Vector2i(rect.position.x - depth, rect.position.y + step)
	return Vector2i(rect.end.x - 1 + depth, rect.position.y + step)

## World point on a block face, `along` cells from the face's start.
func _face_point(rect: Rect2i, face: int, along: float) -> Vector3:
	var point: Vector2
	match face:
		0: point = _cell_world(Vector2(rect.position.x + along, rect.position.y))
		1: point = _cell_world(Vector2(rect.position.x + along, rect.end.y))
		2: point = _cell_world(Vector2(rect.position.x, rect.position.y + along))
		_: point = _cell_world(Vector2(rect.end.x, rect.position.y + along))
	return Vector3(point.x, 0.0, point.y)

func _dress_face(rect: Rect2i, face: int, start: int, count: int, body: StaticBody3D, height: float) -> void:
	var normal := FACE_NORMALS[face]
	var mid := _face_point(rect, face, start + count * 0.5)
	var length := count * CELL_SIZE
	var along_x := face < 2
	var run_sites := mining_sites.size()
	# Tenement dressing waits until every machine site and set piece exists.
	_facade_runs.append({"mid": mid, "normal": normal, "length": length, "height": height, "along_x": along_x, "key": hash([rect.position, face, start])})
	if _theme != &"yard":
		# Everything flush on the face: a glowing top trim, a dark mid band above
		# the machine mounting height, and a hazard kick-plate reading the wall line.
		_visual(_box, _accent, mid + normal * 0.02 + Vector3.UP * (height - 0.45), Vector3(length, 0.12, 0.04) if along_x else Vector3(0.04, 0.12, length))
		if count >= 3:
			_visual(_box, _dark, mid + normal * 0.015 + Vector3.UP * minf(height - 1.3, 3.6), Vector3(length - 1.0, 1.1, 0.03) if along_x else Vector3(0.03, 1.1, length - 1.0))
		_visual(_box, _secondary, mid + normal * 0.02 + Vector3.UP * 0.09, Vector3(length, 0.18, 0.04) if along_x else Vector3(0.04, 0.18, length))
	# Contract machine sites need a broad face with two open cells of standing room.
	var deep_start := -1
	for step in range(start, start + count + 1):
		var deep := step < start + count and _open_at(_face_cell(rect, face, step, 2))
		if deep and deep_start < 0:
			deep_start = step
		elif not deep and deep_start >= 0:
			var run := step - deep_start
			if run >= 3:
				var sites := 1 + (run - 3) / 4
				var spacing := float(run) / float(sites)
				for site in sites:
					var point := _face_point(rect, face, deep_start + spacing * (site + 0.5))
					point.y = 1.5
					mining_sites.append({"position": point, "normal": normal, "support": body})
			deep_start = -1
	_facade_runs[-1]["sites"] = mining_sites.size() - run_sites

## Overlooks favour arena rooms; outcrops spread over the others first.
func _build_set_pieces() -> void:
	var arenas: Array[int] = []
	var others: Array[int] = []
	for index in rooms.size():
		if rooms[index].arena:
			arenas.append(index)
		else:
			others.append(index)
	var overlook_order: Array[int] = arenas.duplicate()
	overlook_order.append_array(others)
	var outcrop_order: Array[int] = others.duplicate()
	_shuffle(outcrop_order)
	outcrop_order.append_array(arenas)
	for slot in _stage.overlook_count:
		_place_in_rooms(overlook_order, slot, _try_overlook)
	for slot in _stage.outcrop_count:
		_place_in_rooms(outcrop_order, slot, _try_outcrop)

## Prefers the dealt room, then any other, then anywhere on the open floor;
## a piece that fits nowhere is skipped.
func _place_in_rooms(order: Array[int], slot: int, attempt: Callable) -> void:
	for offset in order.size():
		if attempt.call(_room_rect(rooms[order[(slot + offset) % order.size()]])):
			return
	for _sweep in 12:
		if attempt.call(_area):
			return

func _try_overlook(region: Rect2) -> bool:
	var height := 1.8
	match _theme:
		&"foundry": height = 2.2
		&"reactor": height = 2.6
	height += _rng.randf_range(0.0, 0.3)
	var run := height / tan(RAMP_ANGLE)
	var size := Vector2(_rng.randf_range(7.0, 9.5), _rng.randf_range(7.0, 9.5))
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	_shuffle(directions)
	for direction in directions:
		var along_x := absf(direction.x) > 0.5
		var extent := size + (Vector2(run, 0.0) if along_x else Vector2(0.0, run))
		if extent.x > region.size.x or extent.y > region.size.y:
			continue
		for _attempt in 24:
			var corner := Vector2(_rng.randf_range(region.position.x, region.end.x - extent.x), _rng.randf_range(region.position.y, region.end.y - extent.y))
			var footprint := Rect2(corner, extent)
			if not _area_clear(footprint, PIECE_MARGIN):
				continue
			_occupied.append(footprint)
			# The deck holds the end opposite the ramp's outward direction.
			var deck := Rect2(corner + Vector2(run if direction.x < 0.0 else 0.0, run if direction.y < 0.0 else 0.0), size)
			_build_overlook(deck, height, direction, run)
			return true
	return false

func _build_overlook(deck: Rect2, height: float, direction: Vector2, run: float) -> void:
	var center := deck.get_center()
	var label := "Overlook%d" % overlooks.size()
	_box_body(_elevation, label, Vector3(center.x, height * 0.5, center.y), Vector3(deck.size.x, height, deck.size.y), _steel)
	var outward := Vector3(direction.x, 0.0, direction.y)
	var edge := Vector3(center.x, 0.0, center.y) + outward * (deck.size.x if absf(direction.x) > 0.5 else deck.size.y) * 0.5
	var foot := edge + outward * run
	# Box axes: X across the ramp, Y the surface normal, Z climbing toward the deck.
	var slope := Vector3.UP * sin(RAMP_ANGLE) - outward * cos(RAMP_ANGLE)
	var normal := Vector3.UP * cos(RAMP_ANGLE) + outward * sin(RAMP_ANGLE)
	var basis := Basis(normal.cross(slope), normal, slope)
	var length := run / cos(RAMP_ANGLE)
	var surface_mid := (foot + edge + Vector3.UP * height) * 0.5
	var ramp_size := Vector3(RAMP_WIDTH, RAMP_THICKNESS, length)
	var shape := BoxShape3D.new()
	shape.size = ramp_size
	var ramp := _body(_elevation, label + "Ramp", surface_mid - normal * RAMP_THICKNESS * 0.5, shape)
	ramp.basis = basis
	_visual(_box, _steel, ramp.position, ramp_size, basis)
	var treads := maxi(3, floori(length / 1.6))
	for index in treads:
		var along := (float(index) + 0.5) / float(treads) - 0.5
		_visual(_box, _accent, surface_mid + slope * length * along + normal * 0.012, Vector3(RAMP_WIDTH * 0.86, 0.02, 0.16), basis)
	_visual(_box, _secondary, Vector3(foot.x, 0.006, foot.z) - outward * 0.2, Vector3(RAMP_WIDTH, 0.01, 0.3) if absf(direction.y) > 0.5 else Vector3(0.3, 0.01, RAMP_WIDTH))
	# Flush dressing only: nothing visible may stand where nothing collides.
	var top := Vector3(center.x, height, center.y)
	_visual(_box, _dark, top + Vector3.UP * 0.006, Vector3(deck.size.x * 0.94, 0.012, deck.size.y * 0.94))
	for sign_value in [-1.0, 1.0]:
		_visual(_box, _accent, top + Vector3(0.0, 0.014, sign_value * (deck.size.y * 0.5 - 0.35)), Vector3(deck.size.x - 0.7, 0.012, 0.08))
		_visual(_box, _accent, top + Vector3(sign_value * (deck.size.x * 0.5 - 0.35), 0.014, 0.0), Vector3(0.08, 0.012, deck.size.y - 0.7))
	_visual(_box, _secondary, Vector3(center.x, 0.4, center.y), Vector3(deck.size.x + 0.02, 0.12, deck.size.y + 0.02))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		var at := center + corner * (deck.size * 0.5 - Vector2(0.17, 0.17))
		_visual(_box, _dark, Vector3(at.x, height * 0.5, at.y), Vector3(0.36, height + 0.01, 0.36))
	_add_fill(top + Vector3.UP * 3.0, _accent_color, 1.4, 12.0)
	overlooks.append({"center": top, "size": deck.size, "height": height, "foot": foot, "direction": outward})

func _try_outcrop(region: Rect2) -> bool:
	# Long faces must still exceed a full machine bank (about 4.8 m).
	var length := _rng.randf_range(5.6, 7.0)
	var depth := _rng.randf_range(2.6, 3.4)
	var height := _rng.randf_range(3.4, 4.4)
	var along_x := _rng.randf() < 0.5
	for _orientation in 2:
		var extent := Vector2(length, depth) if along_x else Vector2(depth, length)
		if extent.x <= region.size.x and extent.y <= region.size.y:
			for _attempt in 40:
				var corner := Vector2(_rng.randf_range(region.position.x, region.end.x - extent.x), _rng.randf_range(region.position.y, region.end.y - extent.y))
				var footprint := Rect2(corner, extent)
				# Room for a wall machine and a player in front, and never inside a
				# wall site's standing spot (2.5 m out plus body radius).
				if not _area_clear(footprint, 3.6):
					continue
				_occupied.append(footprint)
				_build_outcrop(footprint, height, along_x)
				return true
		along_x = not along_x
	return false

## Both long faces are real, broad supports for contract ore mid-room.
func _build_outcrop(footprint: Rect2, height: float, along_x: bool) -> void:
	var center := footprint.get_center()
	var position := Vector3(center.x, height * 0.5, center.y)
	var body := _box_body(_obstacles, "OreOutcrop%d" % outcrops.size(), position, Vector3(footprint.size.x, height, footprint.size.y), _rock)
	outcrops.append(body)
	var half_depth := (footprint.size.y if along_x else footprint.size.x) * 0.5
	for sign_value in [-1.0, 1.0]:
		var normal := Vector3(0.0, 0.0, sign_value) if along_x else Vector3(sign_value, 0.0, 0.0)
		mining_sites.append({"position": Vector3(center.x, 1.5, center.y) + normal * half_depth, "normal": normal, "support": body, "interior": true})
	_visual(_box, _dark, position + Vector3.UP * (height * 0.5), Vector3(footprint.size.x * 0.96, 0.012, footprint.size.y * 0.96))
	var end_offset := Vector3(footprint.size.x * 0.5, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, footprint.size.y * 0.5)
	if _theme == &"yard":
		_dress_zizkov_outcrop(position, height, end_offset)
		return
	# Glowing seams on the short ends and a beacon above mark it from range.
	for sign_value in [-1.0, 1.0]:
		var seam := Vector3(0.012, height * 0.7, footprint.size.y * 0.5) if along_x else Vector3(footprint.size.x * 0.5, height * 0.7, 0.012)
		_visual(_box, _secondary, position + end_offset * sign_value, seam)
	_visual(_cylinder, _secondary, position + Vector3.UP * (height * 0.5 + 0.45), Vector3(0.12, 0.9, 0.12))
	_add_fill(position + Vector3.UP * (height * 0.5 + 1.5), _secondary_color, 1.2, 11.0)

func _build_room_features() -> void:
	for room in rooms:
		if room.kind == &"pillars":
			_build_pillars(room)
	_build_cover()

## Colonnades: pillars on cell corners, four cells apart, clear of the walls.
func _build_pillars(room: Dictionary) -> void:
	var bounds: Rect2i = room.bounds
	var radius := 0.75
	for z in range(bounds.position.y + 2, bounds.end.y - 2, 4):
		for x in range(bounds.position.x + 2, bounds.end.x - 2, 4):
			var center := _cell_world(Vector2(x + 1, z + 1))
			var footprint := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			if not _area_clear(footprint, 3.5):
				continue
			_occupied.append(footprint)
			var position := Vector3(center.x, _wall_height * 0.5, center.y)
			_cylinder_body("Pillar%d_%d" % [x, z], position, radius, _wall_height, _steel)
			if _theme == &"yard":
				_dress_zizkov_pillar(position, radius, _wall_height)
			else:
				_dress_column(position, Vector3(radius * 2.0, _wall_height, radius * 2.0), false)

## The reactor itself: a tall glowing landmark visible over every wall.
func _build_reactor_core(room: Dictionary) -> void:
	var center := _room_rect(room).get_center()
	var radius := 3.0
	var height := 15.0
	var position := Vector3(center.x, height * 0.5, center.y)
	_cylinder_body("ReactorCore", position, radius, height, _steel)
	_occupied.append(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0))
	for index in 6:
		var band_y := 1.2 + index * 2.3
		_visual(_cylinder, _accent if index % 2 == 0 else _secondary, Vector3(center.x, band_y, center.y), Vector3(radius + 0.02, 0.22, radius + 0.02))
	_visual(_cylinder, _accent, Vector3(center.x, height + 0.3, center.y), Vector3(radius * 0.6, 0.6, radius * 0.6))
	_add_fill(Vector3(center.x, 9.0, center.y), _accent_color, 3.2, 26.0)

func _build_cover() -> void:
	for index in _stage.cover_count / 2:
		var landmark := index < 2
		var circular := _theme == &"reactor" or index % 3 == 1
		var size := _island_size(landmark, circular)
		for _attempt in 60:
			var region := _room_rect(rooms[_rng.randi() % rooms.size()])
			if region.size.x < size.x + 2.0 * PIECE_MARGIN or region.size.y < size.z + 2.0 * PIECE_MARGIN:
				continue
			var point := Vector2(_rng.randf_range(region.position.x + size.x * 0.5, region.end.x - size.x * 0.5), _rng.randf_range(region.position.y + size.z * 0.5, region.end.y - size.z * 0.5))
			var footprint := Rect2(point - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
			if not _area_clear(footprint, PIECE_MARGIN):
				continue
			_occupied.append(footprint)
			var position := Vector3(point.x, size.y * 0.5, point.y)
			var label := "IndustrialIsland%d" % index
			if _theme == &"yard":
				_build_zizkov_island(label, position, size, landmark, circular)
			elif circular:
				_cylinder_body(label, position, size.x * 0.5, size.y, _steel)
				_dress_column(position, size, landmark)
			else:
				_box_body(_obstacles, label, position, size, _steel)
				_dress_box(position, size, landmark)
			break

## Painted centre lines trace every passage; narrow chokepoints glow in the
## secondary colour. Rooms get a thin floor outline marking their extent.
func _build_guides() -> void:
	for corridor in _corridors:
		var line: Array[Vector2] = corridor.line
		var material := _secondary if int(corridor.width) <= 2 else _accent
		for index in line.size() - 1:
			var a := _cell_world(line[index])
			var b := _cell_world(line[index + 1])
			var span := b - a
			if span.length() < 0.5:
				continue
			var middle := (a + b) * 0.5
			_visual(_box, material, Vector3(middle.x, 0.007, middle.y), Vector3(span.length(), 0.01, 0.07), Basis(Vector3.UP, atan2(-span.y, span.x)))
	for room in rooms:
		var rect := _room_rect(room).grow(-0.5)
		var material := _secondary if room.arena else _accent
		var center := rect.get_center()
		for sign_value in [-1.0, 1.0]:
			_visual(_box, material, Vector3(center.x, 0.006, center.y + sign_value * rect.size.y * 0.5), Vector3(rect.size.x, 0.01, 0.05))
			_visual(_box, material, Vector3(center.x + sign_value * rect.size.x * 0.5, 0.006, center.y), Vector3(0.05, 0.01, rect.size.y))

func _island_size(landmark: bool, circular: bool) -> Vector3:
	if circular:
		var diameter := _rng.randf_range(3.6, 5.6) if landmark else _rng.randf_range(2.2, 3.4)
		var height := _rng.randf_range(6.0, 9.0) if landmark else _rng.randf_range(2.5, 4.5)
		return Vector3(diameter, height, diameter)
	var size := Vector3(_rng.randf_range(4.0, 6.0), _rng.randf_range(3.6, 5.2), _rng.randf_range(5.0, 9.0)) if landmark else Vector3(_rng.randf_range(2.0, 3.6), _rng.randf_range(1.8, 3.0), _rng.randf_range(2.0, 4.5))
	if _rng.randf() < 0.5:
		var width := size.x
		size.x = size.z
		size.z = width
	return size

func _dress_box(position: Vector3, size: Vector3, landmark: bool) -> void:
	# Thin embedded panels keep the visible blocking silhouette equal to the box.
	var panel_height := size.y * 0.55
	for sign_value in [-1.0, 1.0]:
		_visual(_box, _dark, position + Vector3(0.0, 0.0, sign_value * size.z * 0.5), Vector3(size.x * 0.82, panel_height, 0.012))
		_visual(_box, _accent, position + Vector3(0.0, size.y * 0.33, sign_value * size.z * 0.5), Vector3(size.x * 0.85, 0.09, 0.014))
		if _theme == &"foundry" and landmark:
			# Furnace mouths, glowing behind an inset grille.
			_visual(_box, _secondary, position + Vector3(0.0, -0.15, sign_value * size.z * 0.5), Vector3(size.x * 0.55, panel_height * 0.65, 0.014))
			for bar in 5:
				_visual(_box, _dark, position + Vector3((float(bar) - 2.0) * size.x * 0.1, -0.15, sign_value * (size.z * 0.5 + 0.006)), Vector3(0.11, panel_height * 0.7, 0.014))
	_visual(_box, _dark, position + Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x * 0.95, 0.012, size.z * 0.95))

func _dress_column(position: Vector3, size: Vector3, landmark: bool) -> void:
	# Coaxial sleeves share the cylinder footprint; no hidden compound collider.
	for fraction in [-0.36, 0.36]:
		_visual(_cylinder, _accent if fraction > 0.0 else _secondary, position + Vector3(0.0, size.y * fraction, 0.0), Vector3(size.x * 0.5 + 0.005, 0.1, size.z * 0.5 + 0.005))
	_visual(_cylinder, _dark, position + Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x * 0.48, 0.014, size.z * 0.48))
	if landmark:
		_add_fill(position + Vector3(0.0, size.y * 0.5 + 0.4, 0.0), _accent_color, 1.4, 13.0)

func _build_skyline() -> void:
	if _theme == &"yard":
		_build_zizkov_skyline()
		_build_tv_tower()
		return
	# Reuse the authored kit's batched art only OUTSIDE the playable rectangle.
	var batch := ModuleBatch.new()
	batch.name = "ExteriorWallModules"
	batch.source = REACTOR_WALL_ART if _theme == &"reactor" else FLAT_WALL_ART
	batch.tint = Color(0.82, 0.58, 0.38) if _theme == &"foundry" else Color.WHITE
	for side in 4:
		var horizontal := side < 2
		var length := _area.size.x if horizontal else _area.size.y
		var count := floori(length / 4.0)
		for index in count:
			var offset := (float(index) + 0.5) * length / float(count)
			var position: Vector3
			var yaw: float
			match side:
				0:
					position = Vector3(_area.position.x + offset, _wall_height, _area.position.y - 4.0)
					yaw = PI * 0.5
				1:
					position = Vector3(_area.position.x + offset, _wall_height, _area.end.y + 4.0)
					yaw = -PI * 0.5
				2:
					position = Vector3(_area.position.x - 4.0, _wall_height, _area.position.y + offset)
					yaw = 0.0
				_:
					position = Vector3(_area.end.x + 4.0, _wall_height, _area.position.y + offset)
					yaw = PI
			batch.transforms.append(Transform3D(Basis(Vector3.UP, yaw), position))
	_decoration.add_child(batch)

func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.023, 0.048)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.37, 0.51, 0.69)
	environment.ambient_light_energy = 0.8
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if _theme == &"foundry":
		environment.background_color = Color(0.045, 0.018, 0.012)
		environment.ambient_light_color = Color(0.72, 0.47, 0.32)
	elif _theme == &"reactor":
		environment.background_color = Color(0.018, 0.009, 0.042)
		environment.ambient_light_color = Color(0.39, 0.43, 0.75)
	else:
		_zizkov_night(environment)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-1.0, -0.5, 0.0)
	key.light_color = Color(0.82, 0.86, 1.0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 70.0
	if _theme == &"yard":
		# A smoggy moon; the sodium lamps do the real work.
		key.light_color = Color(0.62, 0.68, 0.92)
		key.light_energy = 0.55
		key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(key)
	# One coloured fill per large room, alternating the theme's two hues; in
	# Žižkov every one is a sodium lamp hung on a wire across the yard.
	var lit := 0
	for room in rooms:
		var rect := _room_rect(room)
		if lit >= 8 or rect.size.x * rect.size.y < 140.0 or room.kind == &"hub":
			continue
		var center := rect.get_center()
		if _theme == &"yard":
			_hang_lamp(rect)
			_add_fill(Vector3(center.x, _wall_height - 0.75, center.y), _accent_color, 2.4, maxf(rect.size.x, rect.size.y) * 0.9)
		else:
			_add_fill(Vector3(center.x, _wall_height - 0.5, center.y), _accent_color if lit % 2 == 0 else _secondary_color, 2.0, maxf(rect.size.x, rect.size.y) * 0.9)
		lit += 1

# ---------------------------------------------------------------- Žižkov dressing
# Visual only, after the layout: no colliders, and variety comes from hashes,
# never from the layout RNG, so same-seed collision layouts stay identical.

## Deterministic 0..1 value for a dressing decision.
func _vary(key: int, salt: int) -> float:
	return float(hash([key, salt]) & 0xFFFF) / 65535.0

func _run_tangent(run: Dictionary) -> Vector3:
	return Vector3.RIGHT if run.along_x else Vector3.BACK

## Box on a facade run: `along` from the run middle, `out` of the wall plane;
## `size` is (width along the wall, height, depth out of it).
func _facade_box(run: Dictionary, material: Material, along: float, y: float, out: float, size: Vector3, basis := Basis()) -> void:
	var normal: Vector3 = run.normal
	var mid: Vector3 = run.mid
	var at := mid + _run_tangent(run) * along + Vector3.UP * y + normal * out
	_visual(_box, material, at, size if run.along_x else Vector3(size.z, size.y, size.x), basis)

func _facade_point(run: Dictionary, along: float, y: float, out: float) -> Vector3:
	var normal: Vector3 = run.normal
	var mid: Vector3 = run.mid
	return mid + _run_tangent(run) * along + Vector3.UP * y + normal * out

func _far_from(point: Vector3, taken: Array[Vector3], distance: float) -> bool:
	for other in taken:
		if Vector2(point.x - other.x, point.z - other.z).length() < distance:
			return false
	return true

## Picks the few signs, lamps and bin corners per level, then dresses every face.
func _build_zizkov_street() -> void:
	var order: Array[Dictionary] = _facade_runs.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.key) < int(b.key))
	var signs: Array[Vector3] = []
	var lamps: Array[Vector3] = []
	var bins: Array[Vector3] = []
	var ore: Array[Vector3] = []
	for site: Dictionary in mining_sites:
		ore.append(site.position)
	var herna := 0
	var pivo := 0
	for run in order:
		var mid: Vector3 = run.mid
		var length: float = run.length
		run.feature = &""
		# Signs sit above the ore band; broad mining faces must remain eligible.
		if run.height >= 5.0 and length >= 8.0 and herna < 2 and _far_from(mid, signs, 28.0):
			run.feature = &"herna"
			herna += 1
			signs.append(mid)
		elif length >= 6.0 and pivo < 2 and _far_from(mid, signs, 22.0):
			run.feature = &"pivo"
			pivo += 1
			signs.append(mid)
		run.lamp = length >= 4.0 and lamps.size() < 16 and _far_from(mid, lamps, 12.0)
		if run.lamp:
			lamps.append(mid)
		var corner := _facade_point(run, -length * 0.5 + 1.2, 0.0, 0.0)
		run.bins = length >= 4.0 and bins.size() < 14 and _far_from(corner, bins, 9.0) and _far_from(corner, ore, 3.4)
		if run.bins:
			bins.append(corner)
	_sign_points = signs
	for run in _facade_runs:
		_dress_tenement(run)

func _dress_tenement(run: Dictionary) -> void:
	var length: float = run.length
	var height: float = run.height
	var key: int = run.key
	var feature: StringName = run.feature
	_facade_box(run, _props[&"cornice"], 0.0, height - 0.3, 0.08, Vector3(length, 0.22, 0.16))
	_facade_box(run, _props[&"cornice"], 0.0, height - 0.5, 0.04, Vector3(length, 0.08, 0.08))
	var pavlac := feature == &"" and height >= 6.25 and length >= 6.0 and _vary(key, 1) < 0.7
	if height >= 5.6 and feature == &"" and not pavlac:
		_facade_box(run, _props[&"cornice"], 0.0, 4.1, 0.04, Vector3(length, 0.12, 0.08))
	var windows := floori((length - 0.6) / 2.6)
	if windows > 0:
		var spacing := length / windows
		for index in windows:
			var along := -length * 0.5 + spacing * (index + 0.5)
			if not (feature == &"pivo" and absf(along) < 1.7):
				_add_window(run, along, 3.1, hash([key, index]))
			if height >= 6.25:
				_add_window(run, along, 5.25, hash([key, index, 2]))
	if pavlac:
		_add_pavlac(run)
	if _vary(key, 2) < 0.45:
		_facade_box(run, _props[&"pipe"], -length * 0.5 + 0.3, (height - 0.35) * 0.5, 0.1, Vector3(0.11, height - 0.35, 0.11))
	if feature == &"" and length >= 4.0 and _vary(key, 3) < 0.5:
		_add_graffiti(run, key)
	match feature:
		&"herna": _add_herna(run)
		&"pivo": _add_pivo(run)
	if run.lamp:
		_add_wall_lamp(run, length * 0.5 - 0.55, minf(4.0, height - 0.85))
	if run.bins:
		_add_bins(run, key)

func _add_window(run: Dictionary, along: float, y: float, key: int) -> void:
	var roll := _vary(key, 0)
	_facade_box(run, _props[&"frame"], along, y, 0.02, Vector3(1.04, 1.44, 0.04))
	_facade_box(run, _props[&"cornice"], along, y - 0.75, 0.08, Vector3(1.2, 0.07, 0.16))
	if roll < 0.08:
		# Boarded up after the last landlord left.
		_facade_box(run, _props[&"board"], along, y, 0.03, Vector3(0.9, 1.3, 0.06))
		_facade_box(run, _props[&"wood"], along, y + 0.2, 0.065, Vector3(1.0, 0.16, 0.03), Basis(run.normal, 0.25))
		return
	var glass: Material = _props[&"glass"]
	if roll > 0.9:
		glass = _props[&"glass_tv"]
	elif roll > 0.72:
		glass = _props[&"glass_lit"]
	_facade_box(run, glass, along, y, 0.025, Vector3(0.84, 1.24, 0.05))
	_facade_box(run, _props[&"frame"], along, y, 0.035, Vector3(0.06, 1.24, 0.07))
	_facade_box(run, _props[&"frame"], along, y + 0.22, 0.035, Vector3(0.84, 0.06, 0.07))

## Pavlač: a cantilevered access gallery with a thin iron railing, on brackets.
func _add_pavlac(run: Dictionary) -> void:
	var length: float = run.length
	var normal: Vector3 = run.normal
	var tangent := _run_tangent(run)
	var iron: Material = _props[&"iron"]
	_facade_box(run, _steel, 0.0, 4.2, 0.4, Vector3(length - 0.1, 0.16, 0.8))
	_facade_box(run, iron, 0.0, 5.24, 0.76, Vector3(length - 0.1, 0.045, 0.045))
	_facade_box(run, iron, 0.0, 4.36, 0.76, Vector3(length - 0.1, 0.03, 0.03))
	var posts := floori(length / 0.45)
	for index in posts + 1:
		var along := -length * 0.5 + 0.05 + (length - 0.1) * index / float(posts)
		_facade_box(run, iron, along, 4.76, 0.76, Vector3(0.025, 0.92, 0.025))
	# Brackets lean out from the wall to the slab's outer edge.
	var lean := tangent.cross(Vector3.UP).dot(normal)
	var brace := Basis(tangent, lean * atan2(0.6, 0.62))
	var braces := maxi(2, floori(length / 2.4))
	for index in braces:
		var along := -length * 0.5 + 0.6 + (length - 1.2) * index / float(braces - 1)
		_facade_box(run, iron, along, 3.81, 0.33, Vector3(0.05, 0.88, 0.05), brace)
	# Washing on the line, because somebody still lives here.
	if _vary(run.key, 4) < 0.6:
		var colours: Array[StringName] = [&"paper", &"bag_blue", &"graffiti_red", &"paper"]
		for index in 4:
			var along := -length * 0.25 + index * 0.62 + _vary(run.key, 10 + index) * 0.2
			_facade_box(run, _props[colours[index]], along, 4.92, 0.8, Vector3(0.5, 0.55 + _vary(run.key, 20 + index) * 0.25, 0.012))

## Throw-ups: a black outline block, a colour fill and a few chrome letters.
func _add_graffiti(run: Dictionary, key: int) -> void:
	var length: float = run.length
	var normal: Vector3 = run.normal
	var fills: Array[StringName] = [&"graffiti_red", &"graffiti_yellow", &"graffiti_green", &"graffiti_purple", &"graffiti_silver"]
	var width := minf(length - 1.4, 1.4 + _vary(key, 5) * 1.4)
	var tall := 0.6 + _vary(key, 6) * 0.45
	var along := (_vary(key, 7) - 0.5) * (length - width - 1.0)
	var y := 1.25 + _vary(key, 8) * 0.4
	var tilt := (_vary(key, 9) - 0.5) * 0.12
	_facade_box(run, _props[&"graffiti_black"], along, y, 0.006, Vector3(width + 0.16, tall + 0.16, 0.012), Basis(normal, tilt))
	_facade_box(run, _props[fills[int(_vary(key, 11) * 4.99)]], along, y, 0.013, Vector3(width, tall, 0.012), Basis(normal, tilt))
	var letters := clampi(floori(width / 0.42), 2, 5)
	var letter: Material = _props[fills[int(_vary(key, 12) * 4.99)]]
	for index in letters:
		var offset := along + (index - (letters - 1) * 0.5) * width / letters
		_facade_box(run, letter, offset, y + (_vary(key, 30 + index) - 0.5) * 0.12, 0.02, Vector3(width / letters * 0.62, tall * 0.62, 0.012), Basis(normal, tilt + (_vary(key, 40 + index) - 0.5) * 0.5))

## Herna NONSTOP: neon board under the cornice, blade sign, blacked-out shop.
func _add_herna(run: Dictionary) -> void:
	var normal: Vector3 = run.normal
	var tangent := _run_tangent(run)
	var length: float = run.length
	var red: Material = _props[&"neon_red"]
	var yellow: Material = _props[&"neon_yellow"]
	_facade_box(run, _props[&"sign"], 0.0, 4.25, 0.06, Vector3(3.8, 0.78, 0.12))
	for sign_value: float in [-1.0, 1.0]:
		_facade_box(run, yellow, 0.0, 4.25 + sign_value * 0.41, 0.13, Vector3(3.9, 0.05, 0.05))
		_facade_box(run, yellow, sign_value * 1.95, 4.25, 0.13, Vector3(0.05, 0.87, 0.05))
	_label("HERNA NONSTOP", _facade_point(run, 0.0, 4.25, 0.135), normal, 78, Color(1.0, 0.16, 0.1), Color(0.45, 0.0, 0.0))
	# Keep mining faces clear at ground level; only empty faces get a shopfront.
	if run.sites == 0:
		_facade_box(run, _props[&"glass"], 0.6, 1.45, 0.03, Vector3(2.2, 1.3, 0.06))
		for sign_value: float in [-1.0, 1.0]:
			_facade_box(run, red, 0.6, 1.45 + sign_value * 0.68, 0.07, Vector3(2.3, 0.04, 0.04))
			_facade_box(run, red, 0.6 + sign_value * 1.13, 1.45, 0.07, Vector3(0.04, 1.4, 0.04))
		_label("VÝHERNÍ AUTOMATY", _facade_point(run, 0.6, 1.62, 0.07), normal, 34, Color(1.0, 0.82, 0.25), Color(0.3, 0.1, 0.0))
		_label("777", _facade_point(run, 0.6, 1.2, 0.07), normal, 64, Color(1.0, 0.2, 0.12), Color(0.3, 0.0, 0.0))
		_facade_box(run, _props[&"frame"], -1.3, 1.1, 0.02, Vector3(1.2, 2.2, 0.04))
		_facade_box(run, _props[&"sign"], -1.3, 1.05, 0.04, Vector3(1.0, 2.1, 0.04))
	# Blade sign sticking out over the pavement.
	var blade := minf(length * 0.5 - 0.8, 2.6)
	_facade_box(run, _props[&"sign"], blade, 3.25, 0.52, Vector3(0.12, 1.7, 0.8))
	_facade_box(run, red, blade, 3.25, 0.93, Vector3(0.14, 1.74, 0.04))
	for side_value: float in [-1.0, 1.0]:
		_label("H\nE\nR\nN\nA", _facade_point(run, blade + side_value * 0.065, 3.25, 0.52), tangent * side_value, 52, Color(1.0, 0.82, 0.22), Color(0.45, 0.15, 0.0))
	_add_fill(_facade_point(run, 0.0, 3.9, 1.2), _secondary_color, 1.6, 8.0)

## Hostinec: wooden door, board over it and a lit PIVO blade sign.
func _add_pivo(run: Dictionary) -> void:
	var normal: Vector3 = run.normal
	var tangent := _run_tangent(run)
	if run.sites == 0:
		_facade_box(run, _props[&"frame"], 0.0, 1.15, 0.02, Vector3(1.3, 2.3, 0.04))
		_facade_box(run, _props[&"wood"], 0.0, 1.1, 0.04, Vector3(1.1, 2.2, 0.04))
		_facade_box(run, _props[&"glass_lit"], 0.0, 1.75, 0.065, Vector3(0.7, 0.5, 0.02))
	_facade_box(run, _props[&"sign"], 0.0, 2.75, 0.05, Vector3(2.4, 0.5, 0.1))
	_label("HOSTINEC", _facade_point(run, 0.0, 2.75, 0.105), normal, 56, Color(0.95, 0.85, 0.6), Color(0.15, 0.08, 0.02))
	_facade_box(run, _props[&"iron"], 1.0, 3.62, 0.4, Vector3(0.05, 0.05, 0.8))
	_facade_box(run, _props[&"sign"], 1.0, 3.3, 0.55, Vector3(0.1, 0.62, 0.84))
	for sign_value: float in [-1.0, 1.0]:
		_facade_box(run, _props[&"neon_yellow"], 1.0, 3.3 + sign_value * 0.33, 0.55, Vector3(0.12, 0.04, 0.88))
	for side_value: float in [-1.0, 1.0]:
		_label("PIVO", _facade_point(run, 1.0 + side_value * 0.056, 3.3, 0.55), tangent * side_value, 60, Color(1.0, 0.86, 0.35), Color(0.4, 0.2, 0.0))

func _add_wall_lamp(run: Dictionary, along: float, y: float) -> void:
	var iron: Material = _props[&"iron"]
	_facade_box(run, iron, along, y + 0.28, 0.38, Vector3(0.05, 0.05, 0.76))
	_facade_box(run, iron, along, y + 0.14, 0.72, Vector3(0.025, 0.24, 0.025))
	_facade_box(run, iron, along, y, 0.72, Vector3(0.38, 0.1, 0.38))
	_facade_box(run, _props[&"sodium"], along, y - 0.07, 0.72, Vector3(0.28, 0.05, 0.28))

## Popelnice in a row at one end of the face, lids ajar, bags spilling out.
func _add_bins(run: Dictionary, key: int) -> void:
	var length: float = run.length
	var tangent := _run_tangent(run)
	var count := 2 + int(_vary(key, 13) < 0.5)
	for index in count:
		var along := -length * 0.5 + 0.9 + index * 0.66
		var at := _facade_point(run, along, 0.0, 0.22)
		_visual(_cylinder, _props[&"bin"], at + Vector3.UP * 0.46, Vector3(0.28, 0.92, 0.28))
		_visual(_cylinder, _props[&"iron"], at + Vector3.UP * 0.2, Vector3(0.29, 0.05, 0.29))
		if _vary(key, 50 + index) < 0.55:
			_visual(_cylinder, _props[&"iron"], at + Vector3.UP * 1.0, Vector3(0.3, 0.04, 0.3), Basis(tangent, 0.5))
			_visual(_sphere, _props[&"bag"], at + Vector3.UP * 0.98, Vector3(0.42, 0.3, 0.4))
		else:
			_visual(_cylinder, _props[&"iron"], at + Vector3.UP * 0.94, Vector3(0.3, 0.04, 0.3))
	var spill := _facade_point(run, -length * 0.5 + 0.9 + count * 0.66, 0.0, 0.25)
	_visual(_sphere, _props[&"bag"], spill + Vector3.UP * 0.16, Vector3(0.46, 0.34, 0.4))
	_visual(_sphere, _props[&"bag_blue"], spill + tangent * 0.36 + Vector3.UP * 0.13, Vector3(0.36, 0.28, 0.34))
	_visual(_box, _props[&"cardboard"], spill + tangent * 0.2 + Vector3.UP * 0.03, Vector3(0.5, 0.05, 0.42), Basis(Vector3.UP, _vary(key, 14)))

func _label(text: String, position: Vector3, facing: Vector3, font_size: int, color: Color, outline: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.outline_size = 10
	label.pixel_size = 0.005
	label.modulate = color
	label.outline_modulate = outline
	label.double_sided = false
	label.position = position
	label.basis = Basis.looking_at(-facing, Vector3.UP)
	_decoration.add_child(label)

## ------------------------------------------------------------ storefronts
## Venue shopfronts on tenement faces. Visual only: every part is an instance of
## three shared primitive meshes (one draw call each), none has a collider, and
## the gameplay RNG is never drawn from: venues and faces are picked with a
## private RNG seeded from the level seed, so layout, mining sites and RNG order
## are identical without them. They are built a few physics frames after the
## world, once the game's machines stand, on stretches of wall that are free.

func _physics_process(_delta: float) -> void:
	_store_frames += 1
	var field: DepositField = null
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is DepositField:
				field = sibling
	if _store_frames >= 4 and (field == null or field.deposit_count() > 0 or _store_frames >= 120):
		set_physics_process(false)
		_build_storefronts()

## Runs once the game has placed its machines: finds the free stretches of
## every face and dresses storefronts there, as three batched meshes.
func _build_storefronts() -> void:
	var order: Array[Dictionary] = _facade_runs.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.key) < int(b.key))
	for run in order:
		run.venue = null
	_choose_storefronts(order, _sign_points.duplicate())
	for run in order:
		if run.venue != null:
			_dress_storefront(run)
	_flush_store_batches()

## The widest stretch of a face where nothing solid (machine, cover island, ramp)
## stands within a metre of the wall at storefront height: Vector2(centre along
## the face, length), or ZERO when none fits a shopfront. Wall lamps, pipes and
## bins keep their own corners. Reads the physics world; changes nothing in it.
func _storefront_slot(run: Dictionary) -> Vector2:
	var length: float = run.length
	var low := -length * 0.5 + (3.6 if run.get("bins", false) else 0.45)
	var high := length * 0.5 - (0.85 if run.get("lamp", false) else 0.3)
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 3.0, 1.0) if run.along_x else Vector3(1.0, 3.0, 0.5)
	query.shape = box
	query.collision_mask = 1
	var space := get_world_3d().direct_space_state
	var best := Vector2.ZERO
	var start := low
	var along := low
	while along + 0.5 <= high + 0.001:
		query.transform = Transform3D(Basis(), to_global(_facade_point(run, along + 0.25, 1.6, 0.55)))
		if not space.intersect_shape(query, 1).is_empty():
			if along - start > best.y:
				best = Vector2((start + along) * 0.5, along - start)
			start = along + 0.5
		along += 0.5
	if along - start > best.y:
		best = Vector2((start + along) * 0.5, along - start)
	return best if best.y >= STORE_MIN_GAP else Vector2.ZERO

## Walks a seeded shuffle of the faces with room and gives each the next venue
## of the sector's seeded lineup (the first is the stage-clear shop's).
func _choose_storefronts(order: Array[Dictionary], taken: Array[Vector3]) -> void:
	if not storefronts_enabled:
		return
	var catalog := ShopVenueCatalog.shared()
	var lineup: Array[ShopVenue] = []
	if venue_override.is_empty():
		lineup = catalog.order_for(_theme, level_seed)
		lineup.resize(mini(lineup.size(), int(STORE_COUNT.get(_theme, 6))))
	else:
		for id in venue_override:
			lineup.append(catalog.find(id))
	var pool: Array[Dictionary] = []
	for run in order:
		if run.get("feature", &"") == &"":
			run.slot = _storefront_slot(run)
			if run.slot.y > 0.0:
				pool.append(run)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([level_seed, STORE_SALT])
	for index in range(pool.size() - 1, 0, -1):
		var pick := rng.randi_range(0, index)
		var swap := pool[index]
		pool[index] = pool[pick]
		pool[pick] = swap
	var spacing := STORE_SPACING if venue_override.is_empty() else STORE_SPACING * 0.5
	var next := 0
	for run in pool:
		if next >= lineup.size():
			break
		var slot: Vector2 = run.slot
		var at := _facade_point(run, slot.x, 0.0, 0.0)
		if not _far_from(at, taken, spacing):
			continue
		run.venue = lineup[next]
		run.venue_along = slot.x
		run.venue_width = minf(slot.y - 0.3, 6.0 if lineup[next].facade_style == &"arch" else 5.4)
		taken.append(at)
		next += 1

func _storefront_width(run: Dictionary) -> float:
	return run.venue_width

func _dress_storefront(face: Dictionary) -> void:
	var venue: ShopVenue = face.venue
	var width := _storefront_width(face)
	# Everything below is placed relative to the shopfront's own centre.
	var run := face.duplicate()
	run.mid = _facade_point(face, face.venue_along, 0.0, 0.0)
	_ds = 1.0 if _vary(run.key, 60) < 0.5 else -1.0
	_site = {"venue": venue, "position": run.mid, "normal": run.normal, "tangent": _run_tangent(run), "width": width, "labels": [], "reach": 0.0, "key": run.key}
	venue_sites.append(_site)
	_vbox(run, STORE_CONCRETE if venue.facade_style == &"arch" else STORE_WALL, 0.0, 1.9, -0.01, Vector3(width + 0.1, 3.8, 0.02))
	if venue.facade_style == &"arch":
		_store_arch(run, venue, width)
	else:
		_store_front(run, venue, width)
	_store_sign(run, venue, width)
	if venue.fill_energy > 0.0 and _venue_fills < STORE_FILLS:
		_venue_fills += 1
		_add_fill(_facade_point(run, 0.0, 2.1, 1.5), venue.glow_color, venue.fill_energy, 7.0)

## Queues one storefront part; see `_flush_store_batches` (three draw calls per
## street: one per primitive mesh, all sharing the venue_front shader).
func _store_part(mesh: Mesh, color: Color, energy: float, at: Vector3, size: Vector3, basis: Basis) -> void:
	if not _store_batches.has(mesh):
		_store_batches[mesh] = {"transforms": [], "paint": []}
	var batch: Dictionary = _store_batches[mesh]
	batch.transforms.append(Transform3D(basis * Basis.from_scale(size), at))
	var linear := color.srgb_to_linear()
	batch.paint.append(Color(linear.r, linear.g, linear.b, energy))

func _flush_store_batches() -> void:
	if _store_batches.is_empty():
		return
	var material := ShaderMaterial.new()
	material.shader = VENUE_FRONT
	for mesh: Mesh in _store_batches:
		var batch: Dictionary = _store_batches[mesh]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = batch.transforms.size()
		for index in batch.transforms.size():
			multimesh.set_instance_transform(index, batch.transforms[index])
			multimesh.set_instance_custom_data(index, batch.paint[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Storefronts"
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decoration.add_child(instance)
	_store_batches.clear()

## Box on the shopfront; `u` runs along the shop with the door at +u (mirrored
## per shop), `size` is (along, height, depth out of the wall).
func _vbox(run: Dictionary, color: Color, u: float, y: float, out: float, size: Vector3, energy: float = 0.0, basis := Basis()) -> void:
	_store_part(_box, color, energy, _facade_point(run, _ds * u, y, out + STORE_BASE), size if run.along_x else Vector3(size.z, size.y, size.x), basis)
	_site.reach = maxf(_site.reach, out + STORE_BASE + size.z * 0.5)

## Upright cylinder on the shopfront.
func _vcyl(run: Dictionary, color: Color, u: float, y: float, out: float, radius: float, height: float, energy: float = 0.0) -> void:
	_store_part(_cylinder, color, energy, _facade_point(run, _ds * u, y, out + STORE_BASE), Vector3(radius, height, radius), Basis())
	_site.reach = maxf(_site.reach, out + STORE_BASE + radius)

## Flat disc facing out of the wall.
func _vdisc(run: Dictionary, color: Color, u: float, y: float, out: float, radius: float, energy: float = 0.0) -> void:
	_store_part(_cylinder, color, energy, _facade_point(run, _ds * u, y, out + STORE_BASE), Vector3(radius, 0.03, radius), Basis(_run_tangent(run), PI * 0.5))
	_site.reach = maxf(_site.reach, out + STORE_BASE + 0.015)

func _vball(run: Dictionary, color: Color, u: float, y: float, out: float, size: Vector3) -> void:
	_store_part(_sphere, color, 0.0, _facade_point(run, _ds * u, y, out + STORE_BASE), size, Basis())
	_site.reach = maxf(_site.reach, out + STORE_BASE + size.z * 0.5)

## +1 or -1 so that `Basis(tangent, sign * angle)` lowers an outward bar or
## leans an upright one against the wall.
func _slope_sign(run: Dictionary) -> float:
	return _run_tangent(run).cross(run.normal).dot(Vector3.UP)

func _venue_label(run: Dictionary, text: String, u: float, y: float, out: float, font_size: int, pixel_size: float, color: Color, outline_size: int, tilt: float, wrap_pixels: float, fit: Vector2) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = outline_size
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.double_sided = false
	if wrap_pixels > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = wrap_pixels
	label.position = _facade_point(run, _ds * u, y, out + STORE_BASE)
	var normal: Vector3 = run.normal
	label.basis = Basis.looking_at(-normal, Vector3.UP) * Basis(Vector3.BACK, tilt)
	label.set_meta(&"fit", fit)
	_decoration.add_child(label)
	_site.labels.append(label)
	return label

## Lit sign board with the venue's sign text across the shop.
func _store_sign(run: Dictionary, venue: ShopVenue, width: float) -> void:
	var arch := venue.facade_style == &"arch"
	var board_w := minf(width, 3.7) if arch else width
	var board_h := 0.5 if arch else 0.62
	var y := 3.52 if arch else 3.38
	var tilt := (_vary(run.key, 61) - 0.5) * 0.04 if arch else 0.0
	_vbox(run, venue.sign_color, 0.0, y, 0.07, Vector3(board_w, board_h, 0.14), 0.45, Basis(run.normal, tilt))
	if venue.facade_style == &"neon" or venue.bulbs:
		for side in [-1.0, 1.0]:
			_vbox(run, venue.glow_color, 0.0, y + side * (board_h * 0.5 + 0.02), 0.1, Vector3(board_w + 0.06, 0.05, 0.05), 2.4)
		_vbox(run, venue.glow_color, -board_w * 0.5, y, 0.1, Vector3(0.05, board_h, 0.05), 2.4)
		_vbox(run, venue.glow_color, board_w * 0.5, y, 0.1, Vector3(0.05, board_h, 0.05), 2.4)
	else:
		for side in [-1.0, 1.0]:
			_vbox(run, STORE_PLASTER, 0.0, y + side * (board_h * 0.5 + 0.03), 0.09, Vector3(board_w + 0.14, 0.07, 0.18))
	if venue.bulbs:
		var bulbs := int(board_w / 0.34)
		for index in bulbs:
			var u := -board_w * 0.5 + 0.17 + index * (board_w - 0.34) / (bulbs - 1)
			var lit := STORE_MUSTARD if index % 2 == 0 else venue.glow_color
			for side in [-1.0, 1.0]:
				_vbox(run, lit, u, y + side * (board_h * 0.5 + 0.1), 0.12, Vector3(0.08, 0.08, 0.08), 3.0)
	var fit := board_w - 0.3
	var size := clampi(int(fit / (venue.sign_text.length() * 0.7 * 0.005)), 24, 76)
	var dark_text := venue.text_color.get_luminance() < 0.2
	_venue_label(run, venue.sign_text, 0.0, y, 0.145, size, 0.005, venue.text_color, 0 if dark_text else 8, tilt, 0.0, Vector2(board_w - 0.1, board_h - 0.06))

## Hand-written note with the venue's tagline, taped on the glass or the riser.
func _store_paper(run: Dictionary, venue: ShopVenue, u: float, y: float, out: float, w: float, h: float, font: int) -> void:
	var tilt := (_vary(run.key, 62) - 0.5) * 0.08
	_vbox(run, STORE_PAPER, u, y, out, Vector3(w, h, 0.012), 0.3, Basis(run.normal, tilt))
	for side: float in [-1.0, 1.0]:
		_vbox(run, STORE_MUSTARD, u + side * (w * 0.5 - 0.12), y + h * 0.5, out + 0.007, Vector3(0.14, 0.05, 0.014))
	_venue_label(run, venue.tagline, u, y, out + 0.015, font, 0.004, STORE_INK, 0, tilt, (w - 0.16) / 0.004, Vector2(w - 0.1, h - 0.06))

## Window, door, awning, goods and pavement stock of every non-arch venue.
func _store_front(run: Dictionary, venue: ShopVenue, width: float) -> void:
	var half := width * 0.5
	var neon := venue.facade_style == &"neon"
	var compact := width < 4.6
	var door := 0.86 if compact else 1.0
	var u0 := -half + 0.2
	var u1 := half - door - 0.48
	var ww := u1 - u0
	var uc := (u0 + u1) * 0.5
	var ud := half - 0.28 - door * 0.5
	var back := venue.glow_color.darkened(0.8) if neon else venue.glow_color.lerp(STORE_PAPER, 0.3).darkened(0.3 + (1.0 - minf(venue.window_glow, 1.0)) * 0.4)
	var back_energy := 0.8 * venue.window_glow
	for side: float in [-1.0, 1.0]:
		_vbox(run, STORE_PLASTER, side * (half - 0.1), 1.55, 0.05, Vector3(0.2, 3.1, 0.1))
	_vbox(run, STORE_PLASTER, u1 + 0.06, 1.55, 0.05, Vector3(0.12, 3.1, 0.1))
	# Window: lit back wall, rails, sill.
	_vbox(run, back, uc, 1.38, 0.03, Vector3(ww, 1.7, 0.04), back_energy)
	_vbox(run, STORE_PLASTER, uc, 2.27, 0.07, Vector3(ww + 0.2, 0.1, 0.12))
	_vbox(run, STORE_PLASTER, uc, 0.5, 0.1, Vector3(ww + 0.3, 0.07, 0.2))
	if venue.facade_style == &"tiled":
		for row in 2:
			for index in int(ww / 0.25) + 1:
				var tile := STORE_PAPER if (index + row) % 2 == 0 else venue.awning_color
				_vbox(run, tile, u0 + 0.125 + index * 0.25, 0.12 + row * 0.2, 0.05, Vector3(0.25, 0.2, 0.06))
	else:
		_vbox(run, STORE_DARK, uc, 0.23, 0.05, Vector3(ww + 0.1, 0.46, 0.08))
	if neon:
		for side: float in [-1.0, 1.0]:
			_vbox(run, venue.glow_color, uc, 1.38 + side * 0.88, 0.1, Vector3(ww + 0.1, 0.05, 0.05), 2.8)
			_vbox(run, venue.glow_color, uc + side * (ww * 0.5 + 0.025), 1.38, 0.1, Vector3(0.05, 1.8, 0.05), 2.8)
	# Door.
	_vbox(run, STORE_PLASTER, ud, 1.1, 0.05, Vector3(door + 0.16, 2.2, 0.1))
	_vbox(run, STORE_DARK if neon else STORE_WOOD, ud, 1.05, 0.08, Vector3(door, 2.1, 0.05))
	_vbox(run, back, ud, 1.65, 0.11, Vector3(door * 0.6, 0.62, 0.02), back_energy)
	_vbox(run, STORE_IRON, ud - door * 0.36, 1.0, 0.13, Vector3(0.05, 0.2, 0.05))
	if neon:
		_vbox(run, venue.glow_color, ud, 2.2, 0.09, Vector3(door + 0.16, 0.04, 0.04), 2.8)
		for side: float in [-1.0, 1.0]:
			_vbox(run, venue.glow_color, ud + side * (door + 0.16) * 0.5, 1.1, 0.09, Vector3(0.04, 2.2, 0.04), 2.8)
	else:
		_store_awning(run, venue, width)
	# The note: on the glass, or on the dark riser of the lit-frame venues.
	var paper_w := 0.0
	if neon:
		_store_paper(run, venue, uc, 0.25, 0.1, minf(ww + 0.1, 2.7), 0.4, 22)
	else:
		paper_w = minf(ww - 0.5, 2.3)
		_store_paper(run, venue, uc, 0.95, 0.075, paper_w, 0.62, 24 if compact else 28)
	_store_goods(run, venue, u0, u1, paper_w)
	_store_stock(run, venue, u0)

func _store_awning(run: Dictionary, venue: ShopVenue, width: float) -> void:
	var count := maxi(8, roundi(width / 0.42))
	var stripe := (width + 0.1) / count
	var slope := Basis(_run_tangent(run), -_slope_sign(run) * 0.53)
	for index in count:
		var u := -width * 0.5 - 0.05 + stripe * (index + 0.5)
		var color := venue.awning_color if index % 2 == 0 else venue.awning_alt
		_vbox(run, color, u, 2.65, 0.38, Vector3(stripe, 0.04, 0.79), 0.0, slope)
		_vbox(run, color, u, 2.42, 0.735, Vector3(stripe, 0.2, 0.03))

func _store_goods(run: Dictionary, venue: ShopVenue, u0: float, u1: float, paper_w: float) -> void:
	var shape := venue.goods_shape
	var colors := venue.goods_colors
	var ww := u1 - u0
	var uc := (u0 + u1) * 0.5
	var key: int = run.key
	match shape:
		&"tickets":
			_vbox(run, STORE_DARK, uc, 1.8, 0.045, Vector3(ww - 0.1, 0.8, 0.02))
			var cols := int((ww - 0.3) / 0.18)
			for row in 3:
				for col in cols:
					var u := u0 + 0.15 + col * (ww - 0.3) / (cols - 1)
					_vbox(run, colors[(row + col) % colors.size()], u, 2.02 - row * 0.26, 0.06, Vector3(0.14, 0.2, 0.012), 0.3)
		&"sausages":
			_vbox(run, STORE_IRON, uc, 2.15, 0.1, Vector3(ww - 0.1, 0.03, 0.03))
			var hooks := int((ww - 0.4) / 0.32)
			for index in hooks:
				var u := u0 + 0.2 + index * (ww - 0.4) / (hooks - 1)
				for link in 3:
					_vcyl(run, colors[(index + link) % 2], u, 2.0 - link * 0.21, 0.1, 0.045, 0.2)
				if index % 3 == 1:
					_vball(run, colors[0], u + 0.15, 1.8, 0.1, Vector3(0.16, 0.2, 0.16))
			_vbox(run, STORE_PAPER, uc, 0.56, 0.12, Vector3(ww - 0.3, 0.06, 0.26))
			for index in 2:
				_vball(run, colors[index], u0 + 0.28 + index * (ww - 0.56), 0.68, 0.12, Vector3(0.22, 0.18, 0.2))
		&"machines":
			var count := maxi(2, int(ww / 0.6))
			for index in count:
				_slot_machine(run, venue, u0 + ww / count * (index + 0.5))
		&"coats":
			_vbox(run, STORE_IRON, uc, 2.1, 0.14, Vector3(ww - 0.1, 0.03, 0.03))
			var coats := int((ww - 0.3) / 0.36)
			for index in coats:
				var u := u0 + 0.2 + index * (ww - 0.4) / (coats - 1)
				var tall := 0.62 + _vary(key, 120 + index) * 0.16
				_vbox(run, colors[index % colors.size()], u, 2.08 - tall * 0.5, 0.14, Vector3(0.3, tall, 0.09))
				_vbox(run, STORE_DARK, u, 2.04, 0.15, Vector3(0.12, 0.08, 0.1))
			_goods_zones(run, venue, u0, u1, paper_w, 0.55, 0.27)
		_:
			var neon := venue.facade_style == &"neon"
			var shelves: Array[float] = [1.45]
			if neon:
				shelves = [1.05, 1.6]
			var count := int((ww - 0.4) / 0.27) + 1
			for shelf in shelves:
				_vbox(run, STORE_WOOD, uc, shelf, 0.08, Vector3(ww - 0.1, 0.05, 0.22))
				for index in count:
					_goods_item(run, venue, u0 + 0.2 + index * (ww - 0.4) / (count - 1), shelf + 0.025, index + int(shelf * 10.0))
			if neon:
				for index in count:
					_goods_item(run, venue, u0 + 0.2 + index * (ww - 0.4) / (count - 1), 0.55, index + 3)
			else:
				_goods_zones(run, venue, u0, u1, paper_w, 0.55, 0.27)

## Goods standing on the window floor to both sides of the taped note.
func _goods_zones(run: Dictionary, venue: ShopVenue, u0: float, u1: float, paper_w: float, y: float, pitch: float) -> void:
	var uc := (u0 + u1) * 0.5
	for side: float in [-1.0, 1.0]:
		var from := uc + side * (paper_w * 0.5 + 0.15)
		var span := absf((u1 - 0.2 if side > 0.0 else u0 + 0.2) - from)
		for index in int(span / pitch) + 1:
			_goods_item(run, venue, from + side * index * pitch, y, index + (0 if side > 0.0 else 7))

func _slot_machine(run: Dictionary, venue: ShopVenue, u: float) -> void:
	var colors := venue.goods_colors
	_vbox(run, STORE_DARK, u, 1.15, 0.2, Vector3(0.4, 1.3, 0.28))
	_vbox(run, venue.glow_color, u, 1.9, 0.2, Vector3(0.4, 0.12, 0.3), 2.0)
	_vbox(run, colors[1], u, 1.5, 0.35, Vector3(0.32, 0.26, 0.02), 1.6)
	for reel in 3:
		_vbox(run, venue.glow_color, u + (reel - 1) * 0.1, 1.5, 0.362, Vector3(0.07, 0.17, 0.02), 2.4)
	_vbox(run, STORE_IRON, u, 0.82, 0.36, Vector3(0.26, 0.07, 0.1))

## One window item standing on y.
func _goods_item(run: Dictionary, venue: ShopVenue, u: float, y: float, index: int) -> void:
	var colors := venue.goods_colors
	var tint := colors[index % colors.size()]
	var key: int = run.key
	var roll := _vary(key, 100 + index)
	var lit := 1.6 if venue.facade_style == &"neon" else 0.0
	match venue.goods_shape:
		&"bottles", &"mixed":
			if venue.goods_shape == &"mixed" and index % 3 == 1:
				_vbox(run, tint, u, y + 0.17, 0.12, Vector3(0.2, 0.34, 0.09))
			else:
				var tall := 0.26 + roll * 0.1
				_vcyl(run, tint, u, y + tall * 0.5, 0.12, 0.055, tall, lit)
				_vcyl(run, tint, u, y + tall + 0.07, 0.12, 0.026, 0.14, lit)
		&"shoes", &"coats":
			if index % 2 == 0 or venue.goods_shape == &"coats":
				_vbox(run, tint, u, y + 0.16, 0.12, Vector3(0.12, 0.26, 0.1))
				_vbox(run, tint, u + 0.07, y + 0.05, 0.12, Vector3(0.26, 0.1, 0.1))
			else:
				for tape in 3:
					_vbox(run, STORE_DARK, u, y + 0.015 + tape * 0.03, 0.12, Vector3(0.2, 0.025, 0.13))
				_vbox(run, colors[1], u, y + 0.1, 0.12, Vector3(0.12, 0.01, 0.08))
		&"crates":
			match index % 3:
				0:
					_vball(run, colors[0], u, y + 0.14, 0.12, Vector3(0.18, 0.24, 0.18))
					_vcyl(run, colors[1], u, y + 0.31, 0.12, 0.04, 0.12)
				1:
					_vbox(run, colors[2], u, y + 0.05, 0.12, Vector3(0.22, 0.1, 0.15))
					_vbox(run, colors[0], u, y + 0.15, 0.12, Vector3(0.22, 0.1, 0.15))
				_:
					_vcyl(run, colors[1], u, y + 0.15, 0.12, 0.055, 0.3)
					_vcyl(run, colors[1], u, y + 0.35, 0.12, 0.026, 0.14)
		&"glasses":
			_vcyl(run, colors[0], u, y + 0.1, 0.12, 0.052, 0.2)
			_vcyl(run, colors[1], u, y + 0.225, 0.12, 0.054, 0.05)
		&"tools":
			match index % 4:
				0: _vcyl(run, colors[0], u, y + 0.12, 0.12, 0.13, 0.24)
				1: _vbox(run, STORE_PAPER, u, y + 0.2, 0.12, Vector3(0.28, 0.4, 0.12))
				2: _vball(run, STORE_BLUE, u, y + 0.15, 0.12, Vector3(0.3, 0.3, 0.2))
				_: _vball(run, colors[1], u, y + 0.09, 0.12, Vector3(0.22, 0.18, 0.2))
		&"parcels":
			var w := 0.22 + roll * 0.14
			var h := 0.16 + _vary(key, 140 + index) * 0.14
			_vbox(run, STORE_CARD, u, y + h * 0.5, 0.12, Vector3(w, h, 0.2))
			_vbox(run, colors[1], u, y + h * 0.5, 0.222, Vector3(0.05, h, 0.004))
			if index % 2 == 0:
				_vbox(run, STORE_CARD, u, y + h + 0.07, 0.12, Vector3(w * 0.7, 0.14, 0.16))
		&"loaves":
			if index % 2 == 0:
				_vball(run, tint, u, y + 0.08, 0.12, Vector3(0.32, 0.15, 0.16))
			else:
				for roll_index in 3:
					_vball(run, tint, u + (roll_index - 1) * 0.08, y + 0.05 + (0.07 if roll_index == 1 else 0.0), 0.12, Vector3(0.1, 0.08, 0.1))

## What spills onto the pavement in front of the window (all under 0.6 m deep).
func _store_stock(run: Dictionary, venue: ShopVenue, u0: float) -> void:
	match venue.goods_shape:
		&"crates":
			for index in 2:
				var u := u0 + 0.4 + index * 0.62
				_vbox(run, STORE_CARD, u, 0.15, 0.3, Vector3(0.5, 0.3, 0.34))
				_vball(run, venue.goods_colors[0], u - 0.1, 0.4, 0.3, Vector3(0.2, 0.26, 0.2))
				_vcyl(run, venue.goods_colors[1], u - 0.1, 0.57, 0.3, 0.04, 0.12)
				_vball(run, venue.goods_colors[0], u + 0.12, 0.38, 0.3, Vector3(0.2, 0.26, 0.2))
		&"glasses":
			_vcyl(run, STORE_WOOD, u0 + 0.5, 0.375, 0.4, 0.3, 0.75)
			for band in [0.18, 0.56]:
				_vcyl(run, STORE_IRON, u0 + 0.5, band, 0.4, 0.31, 0.05)
			_vcyl(run, STORE_CARD, u0 + 0.5, 0.76, 0.4, 0.27, 0.03)
		&"tools":
			var lean := _slope_sign(run) * 0.12
			for index in 2:
				var u := u0 + 0.2 + index * 0.3
				var basis := Basis(_run_tangent(run), lean)
				_vbox(run, STORE_WOOD, u, 0.68, 0.1, Vector3(0.04, 1.3, 0.04), 0.0, basis)
				_vbox(run, STORE_STEEL, u, 0.12, 0.11, Vector3(0.2, 0.26, 0.03))
			_vcyl(run, STORE_STEEL, u0 + 0.9, 0.15, 0.3, 0.16, 0.3)
		&"parcels":
			_vbox(run, STORE_CARD, u0 + 0.45, 0.175, 0.32, Vector3(0.52, 0.35, 0.36))
			_vbox(run, STORE_CARD, u0 + 0.5, 0.5, 0.3, Vector3(0.4, 0.3, 0.3))
			_vbox(run, STORE_PAPER, u0 + 0.42, 0.77, 0.3, Vector3(0.34, 0.25, 0.28))
			_vbox(run, STORE_MUSTARD, u0 + 0.5, 0.5, 0.452, Vector3(0.06, 0.3, 0.004))
		&"shoes":
			_vbox(run, STORE_CARD, u0 + 0.5, 0.17, 0.3, Vector3(0.6, 0.34, 0.3))
			for index in 7:
				_vbox(run, STORE_DARK if index % 2 == 0 else venue.goods_colors[1], u0 + 0.28 + index * 0.07, 0.36, 0.3, Vector3(0.012, 0.3, 0.26))

## Žižkovský tunel: a dark mouth in a stone ring, a lamp at the far end, jars of
## memories on a shelf, graveyard soil in sacks and the tagline painted by hand.
func _store_arch(run: Dictionary, venue: ShopVenue, width: float) -> void:
	var colors := venue.goods_colors
	var radius := minf(1.4, (width - 0.9) * 0.5)
	_vdisc(run, STORE_STONE, 0.0, radius, 0.02, radius + 0.24)
	_vbox(run, STORE_STONE, 0.0, radius * 0.5, 0.02, Vector3(radius * 2.0 + 0.48, radius, 0.04))
	_vdisc(run, STORE_DARK, 0.0, radius, 0.05, radius)
	_vbox(run, STORE_DARK, 0.0, radius * 0.5, 0.05, Vector3(radius * 2.0, radius, 0.03))
	_vbox(run, STORE_STONE, 0.0, radius * 2.0 + 0.1, 0.06, Vector3(0.3, 0.3, 0.08))
	_vdisc(run, venue.glow_color.darkened(0.3), 0.0, radius + 0.6, 0.07, 0.24, 1.0)
	for lamp in 3:
		_vbox(run, venue.glow_color, (lamp - 1) * radius * 0.6, radius * 2.0 - 0.25 - absf(lamp - 1) * 0.12, 0.08, Vector3(0.12, 0.05, 0.05), 2.5)
	var tilt := (_vary(run.key, 63) - 0.5) * 0.06
	_venue_label(run, venue.tagline, 0.0, 0.62, 0.075, 28, 0.0042, Color(0.9, 0.88, 0.8), 0, tilt, (radius * 2.0 - 0.3) / 0.0042, Vector2(radius * 2.0 - 0.1, 0.8))
	# Jars of memories on a shelf inside the mouth, graveyard soil on the floor.
	_vbox(run, STORE_WOOD, 0.0, 1.1, 0.1, Vector3(radius * 1.5, 0.04, 0.2))
	for jar in 5:
		var pale := jar % 2 == 0
		_vcyl(run, colors[1] if pale else STORE_DARK, (jar - 2) * radius * 0.3, 1.22, 0.1, 0.06, 0.2, 0.8 if pale else 0.0)
	for sack in 2:
		_vball(run, colors[0], (sack * 2.0 - 1.0) * (radius - 0.3), 0.15, 0.3, Vector3(0.4, 0.3, 0.3))
	_vball(run, STORE_DARK, -radius + 0.3, 0.38, 0.28, Vector3(0.3, 0.2, 0.24))

## Brick shed: posters on the short ends and a lamp on the roof.
func _dress_zizkov_outcrop(position: Vector3, height: float, end_offset: Vector3) -> void:
	var key := hash(position)
	var colours: Array[StringName] = [&"paper", &"graffiti_red", &"graffiti_yellow", &"paper", &"graffiti_green"]
	var along_x := end_offset.x != 0.0
	for sign_value: float in [-1.0, 1.0]:
		var face := position + end_offset * sign_value + end_offset.normalized() * sign_value * 0.008
		for index in 3:
			var lateral := (index - 1) * 0.75 + (_vary(key, index) - 0.5) * 0.3
			var size := Vector3(0.012, 0.95, 0.65) if along_x else Vector3(0.65, 0.95, 0.012)
			var offset := Vector3(0.0, -0.2 + _vary(key, 5 + index) * 0.6, lateral) if along_x else Vector3(lateral, -0.2 + _vary(key, 5 + index) * 0.6, 0.0)
			_visual(_box, _props[colours[int(_vary(key, 9 + index) * 4.99)]], face + offset + end_offset.normalized() * sign_value * 0.004 * index, size, Basis(end_offset.normalized(), (_vary(key, 12 + index) - 0.5) * 0.15))
	var top := position + Vector3.UP * (height * 0.5)
	_visual(_cylinder, _props[&"iron"], top + Vector3.UP * 0.6, Vector3(0.05, 1.2, 0.05))
	_visual(_box, _props[&"iron"], top + Vector3.UP * 1.2, Vector3(0.42, 0.1, 0.42))
	_visual(_box, _props[&"sodium"], top + Vector3.UP * 1.13, Vector3(0.32, 0.05, 0.32))
	_add_fill(top + Vector3.UP * 1.0, _accent_color, 1.4, 11.0)

## Colonnade pillars: rendered concrete with a dark base and an iron capital.
func _dress_zizkov_pillar(position: Vector3, radius: float, height: float) -> void:
	_visual(_cylinder, _dark, position + Vector3.UP * (0.3 - height * 0.5), Vector3(radius + 0.01, 0.6, radius + 0.01))
	_visual(_cylinder, _props[&"iron"], position + Vector3.UP * (height * 0.5 - 0.2), Vector3(radius + 0.01, 0.25, radius + 0.01))
	_visual(_cylinder, _dark, position + Vector3.UP * (height * 0.5), Vector3(radius * 0.96, 0.014, radius * 0.96))
	var key := hash(position)
	if _vary(key, 0) < 0.6:
		_visual(_cylinder, _props[&"paper"], position + Vector3.UP * (1.6 - height * 0.5), Vector3(radius + 0.008, 0.8, radius + 0.008))

## Cover islands: a brick chimney stump, plakátovací sloupy, a garage block
## and overflowing skips. Same bodies as the other themes, new skins.
func _build_zizkov_island(label: String, position: Vector3, size: Vector3, landmark: bool, circular: bool) -> void:
	var key := hash(position)
	var top := position + Vector3.UP * (size.y * 0.5)
	if circular:
		var radius := size.x * 0.5
		_cylinder_body(label, position, radius, size.y, _rock if landmark else _props[&"poster_column"])
		_visual(_cylinder, _dark, top, Vector3(radius * 0.96, 0.014, radius * 0.96))
		if landmark:
			for fraction: float in [-0.2, 0.25]:
				_visual(_cylinder, _props[&"iron"], position + Vector3.UP * size.y * fraction, Vector3(radius + 0.01, 0.14, radius + 0.01))
			_visual(_cylinder, _dark, top - Vector3.UP * 0.4, Vector3(radius + 0.005, 0.8, radius + 0.005))
			_add_fill(top + Vector3.UP * 0.4, _accent_color, 1.4, 13.0)
			return
		_visual(_cylinder, _props[&"poster_column"], top - Vector3.UP * 0.12, Vector3(radius + 0.06, 0.14, radius + 0.06))
		_visual(_cylinder, _props[&"paper"], position + Vector3.UP * (1.7 - size.y * 0.5), Vector3(radius + 0.008, 1.5, radius + 0.008))
		var posters: Array[StringName] = [&"graffiti_red", &"graffiti_yellow", &"graffiti_green", &"graffiti_purple", &"cardboard"]
		for index in 5:
			var angle := TAU * index / 5.0 + _vary(key, index)
			var facing := Vector3(sin(angle), 0.0, cos(angle))
			_visual(_box, _props[posters[index]], position + facing * (radius + 0.02) + Vector3.UP * (1.6 + _vary(key, 10 + index) * 0.3 - size.y * 0.5), Vector3(radius * 0.7, 0.9, 0.012), Basis(Vector3.UP, angle))
		return
	if landmark:
		# Garage block: plaster, a rolled-down green shutter each side.
		_box_body(_obstacles, label, position, size, _wall)
		var shutter := minf(2.4, size.y - 0.8)
		for sign_value: float in [-1.0, 1.0]:
			var face := position + Vector3(0.0, shutter * 0.5 - size.y * 0.5, sign_value * size.z * 0.5)
			_visual(_box, _props[&"container"], face, Vector3(size.x * 0.62, shutter, 0.03))
			for slat in 6:
				_visual(_box, _dark, face + Vector3(0.0, (slat - 2.5) * shutter / 6.0, sign_value * 0.02), Vector3(size.x * 0.62, 0.025, 0.012))
		_visual(_box, _dark, top, Vector3(size.x * 0.97, 0.012, size.z * 0.97))
		return
	# Velkoobjemový kontejner: ribbed green skip with the heap kept flush.
	_box_body(_obstacles, label, position, size, _props[&"container"])
	for sign_value: float in [-1.0, 1.0]:
		var ribs := maxi(2, floori(size.x / 0.55))
		for rib in ribs:
			var x := (rib - (ribs - 1) * 0.5) * size.x / ribs
			_visual(_box, _props[&"iron"], position + Vector3(x, 0.0, sign_value * (size.z * 0.5 + 0.015)), Vector3(0.06, size.y * 0.9, 0.03))
	_visual(_box, _props[&"iron"], top - Vector3.UP * 0.05, Vector3(size.x + 0.04, 0.1, size.z + 0.04))
	_visual(_box, _dark, top + Vector3.UP * 0.006, Vector3(size.x * 0.94, 0.012, size.z * 0.94))
	var heap: Array[StringName] = [&"bag", &"cardboard", &"bag_blue", &"paper", &"bag"]
	for index in 5:
		var spot := Vector3((_vary(key, index) - 0.5) * size.x * 0.6, 0.0, (_vary(key, 10 + index) - 0.5) * size.z * 0.6)
		var bulk := Vector3(0.6, 0.32, 0.5) * (0.7 + _vary(key, 20 + index) * 0.5)
		_visual(_sphere if index % 2 == 0 else _box, _props[heap[index]], top + spot + Vector3.UP * bulk.y * 0.3, bulk, Basis(Vector3.UP, _vary(key, 30 + index) * TAU))

## A sodium lamp hung on a wire across the room's short axis.
func _hang_lamp(rect: Rect2) -> void:
	var center := rect.get_center()
	var across := Vector3.RIGHT if rect.size.x <= rect.size.y else Vector3.BACK
	var half := (rect.size.x if rect.size.x <= rect.size.y else rect.size.y) * 0.5
	var lamp := Vector3(center.x, _wall_height - 0.45, center.y)
	var iron: Material = _props[&"iron"]
	for sign_value: float in [-1.0, 1.0]:
		var anchor: Vector3 = lamp + across * sign_value * half + Vector3.UP * 0.4
		var wire := lamp + Vector3.UP * 0.12 - anchor
		var direction := wire.normalized()
		var side := direction.cross(Vector3.UP).normalized()
		_visual(_box, iron, anchor + wire * 0.5, Vector3(wire.length(), 0.02, 0.02), Basis(direction, side.cross(direction), side))
	_visual(_cylinder, iron, lamp + Vector3.UP * 0.04, Vector3(0.34, 0.12, 0.34))
	_visual(_cylinder, _props[&"sodium"], lamp - Vector3.UP * 0.04, Vector3(0.26, 0.05, 0.26))

## Tenement rows ring the yard outside the walls, with lit windows and roofs.
func _build_zizkov_skyline() -> void:
	var skyline: Material = _props[&"skyline"]
	var roof: Material = _props[&"roof"]
	for row in 2:
		var gap := WALL_THICKNESS + 0.4 + row * 15.0
		for side in 4:
			var along_x := side < 2
			var length := _area.size.x if along_x else _area.size.y
			var cursor := -10.0 - row * 6.0
			var index := 0
			while cursor < length + 10.0:
				var key := hash([row, side, index])
				index += 1
				var width := 6.5 + _vary(key, 0) * 7.0
				var along := cursor + width * 0.5
				cursor += width
				if row == 1 and _vary(key, 1) < 0.3:
					continue
				var storeys := 3 + int(_vary(key, 2) * 2.99) + row
				var height := 1.2 + storeys * 3.1
				var depth := 11.0
				var outward := -1.0 if side % 2 == 0 else 1.0
				var edge := (_area.position.y if side == 0 else _area.end.y) if along_x else (_area.position.x if side == 2 else _area.end.x)
				var across := edge + outward * (gap + depth * 0.5)
				var start := _area.position.x if along_x else _area.position.y
				var center := Vector3(start + along, height * 0.5, across) if along_x else Vector3(across, height * 0.5, start + along)
				var tangent := Vector3.RIGHT if along_x else Vector3.BACK
				var inward := (Vector3(0.0, 0.0, -outward) if along_x else Vector3(-outward, 0.0, 0.0))
				_visual(_box, skyline, center, Vector3(width, height, depth) if along_x else Vector3(depth, height, width))
				var front := center + inward * (depth * 0.5 + 0.15)
				_visual(_box, _props[&"cornice"], front + Vector3.UP * (height * 0.5 - 0.25), Vector3(width, 0.3, 0.3) if along_x else Vector3(0.3, 0.3, width))
				var side_len := depth / sqrt(2.0)
				var pitch := Basis.from_scale(Vector3(1.0, 0.42, 1.0)) * Basis(tangent, PI * 0.25)
				_visual(_box, roof, center + Vector3.UP * (height * 0.5), Vector3(width, side_len, side_len) if along_x else Vector3(side_len, side_len, width), pitch)
				for chimney in 2:
					var spot := (_vary(key, 3 + chimney) - 0.5) * (width - 1.5)
					_visual(_box, _rock, center + tangent * spot + inward * (1.0 + chimney * 1.6) + Vector3.UP * (height * 0.5 + 1.6), Vector3(0.7, 1.8, 0.7))

## Žižkovský vysílač (1985–92): three tubes, two cabins, the antenna. Far
## outside the play area and exempt from fog so it always looms over the roofs.
func _build_tv_tower() -> void:
	var center := _area.get_center()
	var base := Vector3(center.x, 0.0, center.y) + Vector3(-0.55, 0.0, -0.83).normalized() * 165.0
	var concrete := _material(Color(0.6, 0.61, 0.64), 0.55, 0.35)
	var cabin := _material(Color(0.32, 0.33, 0.36), 0.4, 0.5)
	var windows := _material(Color(0.95, 0.8, 0.55), 0.4, 0.0, true)
	windows.emission_energy_multiplier = 1.4
	var beacon := _material(Color(1.0, 0.08, 0.05), 0.4, 0.0, true)
	beacon.emission_energy_multiplier = 4.0
	for material: StandardMaterial3D in [concrete, cabin, windows, beacon]:
		material.disable_fog = true
		_shadowless[material] = true
	# [offset, radius, height]
	for tube: Array in [[Vector2(0.0, -2.6), 3.2, 134.0], [Vector2(-6.2, 3.4), 2.4, 118.0], [Vector2(6.2, 3.4), 2.4, 124.0]]:
		var offset: Vector2 = tube[0]
		var radius: float = tube[1]
		var height: float = tube[2]
		var at := base + Vector3(offset.x, height * 0.5, offset.y)
		_visual(_cylinder, concrete, at, Vector3(radius, height, radius))
		_visual(_sphere, beacon, base + Vector3(offset.x, height + 0.4, offset.y), Vector3(1.4, 1.4, 1.4))
	for level: Array in [[66.0, 8.0], [93.0, 7.0]]:
		var y: float = level[0]
		var tall: float = level[1]
		var pod := base + Vector3(0.0, y, 0.6)
		_visual(_box, cabin, pod, Vector3(19.0, tall, 13.0))
		_visual(_cylinder, cabin, pod + Vector3(-9.5, 0.0, 0.0), Vector3(6.5, tall, 6.5))
		_visual(_cylinder, cabin, pod + Vector3(9.5, 0.0, 0.0), Vector3(6.5, tall, 6.5))
		_visual(_box, windows, pod + Vector3.UP * (tall * 0.12), Vector3(19.1, 1.3, 13.1))
		_visual(_cylinder, windows, pod + Vector3(-9.5, tall * 0.12, 0.0), Vector3(6.55, 1.3, 6.55))
		_visual(_cylinder, windows, pod + Vector3(9.5, tall * 0.12, 0.0), Vector3(6.55, 1.3, 6.55))
	for mast: Array in [[134.0, 160.0, 1.1], [160.0, 192.0, 0.65], [192.0, 216.0, 0.3]]:
		var low: float = mast[0]
		var high: float = mast[1]
		_visual(_cylinder, concrete, base + Vector3(0.0, (low + high) * 0.5, -2.6), Vector3(mast[2], high - low, mast[2]))
		_visual(_sphere, beacon, base + Vector3(0.0, high, -2.6), Vector3(1.2, 1.2, 1.2))

## Warm sodium night under a smog-lit sky, with smoky haze.
func _zizkov_night(environment: Environment) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.012, 0.015, 0.032)
	sky_material.sky_horizon_color = Color(0.21, 0.115, 0.055)
	sky_material.sky_curve = 0.09
	sky_material.ground_horizon_color = Color(0.21, 0.115, 0.055)
	sky_material.ground_bottom_color = Color(0.03, 0.02, 0.015)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_color = Color(0.62, 0.47, 0.34)
	environment.ambient_light_energy = 0.75
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.24, 0.15, 0.085)
	environment.fog_density = 0.014
	environment.fog_sky_affect = 0.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 0.9

func _box_body(parent: Node, label: String, position: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var body := _body(parent, label, position, shape)
	_visual(_box, material, position, size)
	return body

func _cylinder_body(label: String, position: Vector3, radius: float, height: float, material: Material) -> StaticBody3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var body := _body(_obstacles, label, position, shape)
	_visual(_cylinder, material, position, Vector3(radius, height, radius))
	return body

func _body(parent: Node, label: String, position: Vector3, shape: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body

func _visual(mesh: Mesh, material: Material, position: Vector3, size: Vector3, basis := Basis()) -> void:
	if not _visual_batches.has(mesh):
		_visual_batches[mesh] = {}
	var materials: Dictionary = _visual_batches[mesh]
	if not materials.has(material):
		var copy := mesh.duplicate() as PrimitiveMesh
		copy.material = material
		materials[material] = {"mesh": copy, "transforms": []}
	materials[material]["transforms"].append(Transform3D(basis * Basis.from_scale(size), position))

func _flush_visual_batches() -> void:
	for materials: Dictionary in _visual_batches.values():
		for material: Material in materials:
			var entry: Dictionary = materials[material]
			var batch := ModuleBatch.new()
			batch.mesh = entry["mesh"]
			batch.transforms.assign(entry["transforms"])
			if _shadowless.has(material):
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_decoration.add_child(batch)
	_visual_batches.clear()

func _material(color: Color, roughness: float, metallic: float, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
	return material

func _add_fill(position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	add_child(light)
