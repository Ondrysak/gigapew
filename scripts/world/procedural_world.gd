class_name ProceduralWorld
extends Node3D

## Built synchronously in _ready, before the game configures horde navigation.
## Disjoint convex islands, a clear cross and a perimeter circuit deliberately
## avoid maze generation: every ground-level free region connects to the circuit.
const PERIMETER_CLEARANCE := 7.0
const ISLAND_CLEARANCE := 5.0
const LANE_HALF_WIDTH := 3.0
const WALL_THICKNESS := 0.8
const SITE_SPACING := 7.0
const ModuleBatch = preload("res://scenes/levels/yard/module_batch.gd")
const YARD_FLOOR = preload("res://shaders/yard_floor.gdshader")
const FOUNDRY_FLOOR = preload("res://shaders/foundry_floor.gdshader")
const REACTOR_FLOOR = preload("res://shaders/reactor_floor.gdshader")
const YARD_WALL_ART = preload("res://assets/third_party/quaternius_megakit/WallAstra_Straight_Flat.gltf")
const REACTOR_WALL_ART = preload("res://assets/third_party/quaternius_megakit/WallAstra_Straight_Divided.gltf")
const FOUNDRY_STEEL = preload("res://scenes/levels/foundry/materials/foundry_steel.tres")
const FOUNDRY_WALL = preload("res://scenes/levels/foundry/materials/foundry_wall.tres")
const FOUNDRY_DARK = preload("res://scenes/levels/foundry/materials/foundry_dark.tres")

var level_seed: int
var mining_sites: Array[Dictionary] = []
var _stage: StageDefinition
var _rng := RandomNumberGenerator.new()
var _area: Rect2
var _theme: StringName
var _obstacles: Node3D
var _decoration: Node3D
var _occupied: Array[Rect2] = []
var _lane_center: Vector2
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
var _visual_batches: Dictionary = {}

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
	_obstacles = Node3D.new()
	_obstacles.name = "Obstacles"
	add_child(_obstacles)
	_decoration = Node3D.new()
	_decoration.name = "Architecture"
	add_child(_decoration)
	_configure_theme()
	_build_floor()
	_build_perimeter()
	_build_spawn()
	_build_islands()
	_build_lighting()
	_flush_visual_batches()

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
	_accent = _material(_accent_color, 0.4, 0.1, true)
	_secondary = _material(_secondary_color, 0.4, 0.1, true)

func _build_floor() -> void:
	var material := ShaderMaterial.new()
	match _theme:
		&"foundry": material.shader = FOUNDRY_FLOOR
		&"reactor": material.shader = REACTOR_FLOOR
		_: material.shader = YARD_FLOOR
	material.set_shader_parameter("area_center", _area.get_center())
	material.set_shader_parameter("area_half_extents", _area.size * 0.5)
	if _theme == &"foundry":
		material.set_shader_parameter("plate_origin", _area.position)
		material.set_shader_parameter("heat_edge_z", _area.position.y)
	var center := _area.get_center()
	_box_body(self, "Floor", Vector3(center.x, -0.5, center.y), Vector3(_area.size.x + 2.0, 1.0, _area.size.y + 2.0), material)

func _build_perimeter() -> void:
	var center := _area.get_center()
	var north := _box_body(self, "NorthWall", Vector3(center.x, _wall_height * 0.5, _area.position.y - WALL_THICKNESS * 0.5), Vector3(_area.size.x + WALL_THICKNESS * 2.0, _wall_height, WALL_THICKNESS), _wall)
	var south := _box_body(self, "SouthWall", Vector3(center.x, _wall_height * 0.5, _area.end.y + WALL_THICKNESS * 0.5), Vector3(_area.size.x + WALL_THICKNESS * 2.0, _wall_height, WALL_THICKNESS), _wall)
	var west := _box_body(self, "WestWall", Vector3(_area.position.x - WALL_THICKNESS * 0.5, _wall_height * 0.5, center.y), Vector3(WALL_THICKNESS, _wall_height, _area.size.y), _wall)
	var east := _box_body(self, "EastWall", Vector3(_area.end.x + WALL_THICKNESS * 0.5, _wall_height * 0.5, center.y), Vector3(WALL_THICKNESS, _wall_height, _area.size.y), _wall)
	_wall_sites(north, Vector3(_area.position.x, 1.5, _area.position.y), Vector3.RIGHT, Vector3.BACK, _area.size.x)
	_wall_sites(south, Vector3(_area.position.x, 1.5, _area.end.y), Vector3.RIGHT, Vector3.FORWARD, _area.size.x)
	_wall_sites(west, Vector3(_area.position.x, 1.5, _area.position.y), Vector3.BACK, Vector3.RIGHT, _area.size.y)
	_wall_sites(east, Vector3(_area.end.x, 1.5, _area.position.y), Vector3.BACK, Vector3.LEFT, _area.size.y)
	# All facade details stay on the wall, above the ore mounting band.
	for body: StaticBody3D in [north, south, west, east]:
		var shape := (body.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
		var horizontal := shape.size.x > shape.size.z
		var length: float = shape.size.x if horizontal else shape.size.z
		var trim_size := Vector3(length, 0.14, WALL_THICKNESS + 0.02) if horizontal else Vector3(WALL_THICKNESS + 0.02, 0.14, length)
		_visual(_box, _accent, Vector3(body.position.x, _wall_height - 0.4, body.position.z), trim_size)
		var panel_count := floori(length / 6.0)
		for index in panel_count:
			var offset := (float(index) + 0.5) * length / float(panel_count) - length * 0.5
			var position := body.position + (Vector3.RIGHT if horizontal else Vector3.BACK) * offset
			position.y = _wall_height * 0.65
			var panel_size := Vector3(4.8, 1.4, WALL_THICKNESS + 0.01) if horizontal else Vector3(WALL_THICKNESS + 0.01, 1.4, 4.8)
			_visual(_box, _dark, position, panel_size)
	_build_skyline()

func _wall_sites(support: StaticBody3D, start: Vector3, along: Vector3, normal: Vector3, length: float) -> void:
	# Seven metre spacing and corner margins separate even large ore patches.
	# Every site is on a real inward-facing wall, with continuous floor and no
	# islands within seven metres. No physics timing or random ray hits required.
	var count := floori((length - SITE_SPACING * 2.0) / SITE_SPACING) + 1
	var step := (length - SITE_SPACING * 2.0) / float(maxi(count - 1, 1))
	for index in count:
		mining_sites.append({"position": start + along * (SITE_SPACING + float(index) * step), "normal": normal, "support": support})

func _build_spawn() -> void:
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	# A seed-selected point on the clear circuit rather than a fixed center spawn.
	var side := _rng.randi_range(0, 3)
	var x := _rng.randf_range(_area.position.x + 9.0, _area.end.x - 9.0)
	var z := _rng.randf_range(_area.position.y + 9.0, _area.end.y - 9.0)
	match side:
		0: z = _area.position.y + 4.5
		1: z = _area.end.y - 4.5
		2: x = _area.position.x + 4.5
		3: x = _area.end.x - 4.5
	spawn.position = Vector3(x, 0.05, z)
	var toward_center := _area.get_center() - Vector2(x, z)
	spawn.rotation.y = atan2(-toward_center.x, -toward_center.y)
	add_child(spawn)
	# Flush floor markings, never raised props in the walk-up strip.
	_visual(_box, _accent, Vector3(x, 0.006, z - 1.8), Vector3(3.6, 0.01, 0.08))
	_visual(_box, _accent, Vector3(x, 0.006, z + 1.8), Vector3(3.6, 0.01, 0.08))

func _build_islands() -> void:
	_lane_center = _area.get_center() + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
	var interior := _area.grow(-PERIMETER_CLEARANCE)
	# Large landmarks first; smaller islands fill remaining space without ever
	# joining one another. Box yaw stays axis-aligned for the horde's parser.
	for index in _stage.cover_count:
		var landmark := index < 4
		var circular := _theme == &"reactor" or (index % 3 == 1)
		var size := _island_size(landmark, circular)
		for _attempt in 160:
			var point := Vector2(_rng.randf_range(interior.position.x + size.x * 0.5, interior.end.x - size.x * 0.5), _rng.randf_range(interior.position.y + size.z * 0.5, interior.end.y - size.z * 0.5))
			var footprint := Rect2(point - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
			if not _can_place(footprint):
				continue
			_occupied.append(footprint)
			var position := Vector3(point.x, size.y * 0.5, point.y)
			var is_rock := index % 4 == 3
			var material: Material = _rock if is_rock else _steel
			var label := "OreBearingRock%d" % index if is_rock else "IndustrialIsland%d" % index
			if circular:
				_cylinder_body(label, position, size.x * 0.5, size.y, material)
				if not is_rock:
					_dress_column(position, size, landmark)
			else:
				_box_body(_obstacles, label, position, size, material)
				if not is_rock:
					_dress_box(position, size, landmark)
			break
	# Explicit flat cross-lane markings make the circulation legible at speed.
	_visual(_box, _secondary, Vector3(_lane_center.x - LANE_HALF_WIDTH, 0.006, _area.get_center().y), Vector3(0.045, 0.01, _area.size.y - 4.0))
	_visual(_box, _secondary, Vector3(_lane_center.x + LANE_HALF_WIDTH, 0.006, _area.get_center().y), Vector3(0.045, 0.01, _area.size.y - 4.0))
	_visual(_box, _accent, Vector3(_area.get_center().x, 0.006, _lane_center.y - LANE_HALF_WIDTH), Vector3(_area.size.x - 4.0, 0.01, 0.045))
	_visual(_box, _accent, Vector3(_area.get_center().x, 0.006, _lane_center.y + LANE_HALF_WIDTH), Vector3(_area.size.x - 4.0, 0.01, 0.045))

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

func _can_place(footprint: Rect2) -> bool:
	if footprint.position.x < _lane_center.x + LANE_HALF_WIDTH and footprint.end.x > _lane_center.x - LANE_HALF_WIDTH:
		return false
	if footprint.position.y < _lane_center.y + LANE_HALF_WIDTH and footprint.end.y > _lane_center.y - LANE_HALF_WIDTH:
		return false
	for occupied in _occupied:
		if occupied.grow(ISLAND_CLEARANCE).intersects(footprint):
			return false
	return true

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
	# Reuse the authored kit's batched art only OUTSIDE the playable rectangle.
	# The inner wall faces remain simple, exact physical supports for mining.
	var batch := ModuleBatch.new()
	batch.name = "ExteriorWallModules"
	batch.source = REACTOR_WALL_ART if _theme == &"reactor" else YARD_WALL_ART
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
	environment.ambient_light_energy = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if _theme == &"foundry":
		environment.background_color = Color(0.045, 0.018, 0.012)
		environment.ambient_light_color = Color(0.72, 0.47, 0.32)
	elif _theme == &"reactor":
		environment.background_color = Color(0.018, 0.009, 0.042)
		environment.ambient_light_color = Color(0.39, 0.43, 0.75)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-1.0, -0.5, 0.0)
	key.light_color = Color(0.82, 0.86, 1.0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 70.0
	add_child(key)
	var center := _area.get_center()
	for sign_value in [-1.0, 1.0]:
		_add_fill(Vector3(center.x + _area.size.x * 0.27 * sign_value, 7.0, center.y - _area.size.y * 0.27), _accent_color, 2.8, 30.0)
		_add_fill(Vector3(center.x - _area.size.x * 0.27 * sign_value, 7.0, center.y + _area.size.y * 0.27), _secondary_color, 2.6, 30.0)

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

func _visual(mesh: Mesh, material: Material, position: Vector3, size: Vector3) -> void:
	if not _visual_batches.has(mesh):
		_visual_batches[mesh] = {}
	var materials: Dictionary = _visual_batches[mesh]
	if not materials.has(material):
		var copy := mesh.duplicate() as PrimitiveMesh
		copy.material = material
		materials[material] = {"mesh": copy, "transforms": []}
	materials[material]["transforms"].append(Transform3D(Basis.from_scale(size), position))

func _flush_visual_batches() -> void:
	for materials: Dictionary in _visual_batches.values():
		for entry: Dictionary in materials.values():
			var batch := ModuleBatch.new()
			batch.mesh = entry["mesh"]
			batch.transforms.assign(entry["transforms"])
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
