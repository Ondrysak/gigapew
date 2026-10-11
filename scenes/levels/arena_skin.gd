extends Node3D

## Prague skin for the hand-built combat arenas (yard, foundry, reactor).
##
## The arenas keep every collider, group, node path and position they were
## authored with. When one enters the tree this node re-skins what is drawn:
## materials are swapped for plaster, brick, tobacco-stained tile and sodium
## lamps; cold lights are retinted; a few visual-only signs are added. Nothing
## here touches physics, scripts or the layout, and no random numbers are
## drawn. Shared resources (kit glTFs, the foundry .tres files) are never
## edited, only duplicated.

const WALL_SHADER := preload("res://shaders/zizkov_wall.gdshader")
const HLAVAK_WALL_SHADER := preload("res://shaders/hlavak_wall.gdshader")

## Subtrees that stay as authored: hazards read by their own colours.
const UNTOUCHED: Array[StringName] = [&"Hazards"]

@export_enum("yard", "foundry", "reactor") var arena := "yard"

var _replacements := {}
var _graded := {}
var _meshes := {}
var _dressing: Node3D
var _cornice: StandardMaterial3D
var _iron: StandardMaterial3D
var _beacon: StandardMaterial3D
var _roof: StandardMaterial3D

# Per-arena grading: `tint` multiplies textured kit surfaces, `lift` brightens
# flat greys, `sodium` replaces every cold glow, `violet` the purple one.
var _tint := Color(1.0, 0.8, 0.58)
var _lift := 1.5
var _sodium := Color(1.0, 0.62, 0.24)
var _violet := Color(0.62, 0.24, 0.5)
var _glow_scale := 1.0
## Kit trim name -> tint: wall plaster, brick/paint and iron differ per arena.
var _trims := {}

func _ready() -> void:
	match arena:
		"foundry":
			_tint = Color(0.85, 0.72, 0.56)
			_lift = 1.7
			_sodium = Color(1.0, 0.7, 0.38)
			_violet = Color(0.8, 0.3, 0.12)
			_trims = {"Dark": Color(0.5, 0.44, 0.38), "Trim_03": Color(0.8, 0.77, 0.68), "Trim_02": Color(0.82, 0.52, 0.4), "Trim_01": Color(0.6, 0.56, 0.5)}
		"reactor":
			_tint = Color(0.9, 0.8, 0.6)
			_lift = 1.7
			_sodium = Color(0.86, 0.74, 0.3)
			_violet = Color(0.55, 0.22, 0.8)
			_glow_scale = 0.7
			_trims = {"Dark": Color(0.45, 0.38, 0.32), "Trim_03": Color(0.9, 0.82, 0.64), "Trim_02": Color(0.78, 0.56, 0.44), "Trim_01": Color(0.66, 0.6, 0.54)}
		_:
			_trims = {"Dark": Color(0.55, 0.45, 0.36), "Trim_03": Color(0.95, 0.84, 0.64), "Trim_02": Color(0.95, 0.64, 0.48), "Trim_01": Color(0.72, 0.62, 0.52)}
	_build_replacements()
	_skin(self)
	_dressing = Node3D.new()
	_dressing.name = "PragueDressing"
	add_child(_dressing)
	match arena:
		"yard": _dress_yard()
		"foundry": _dress_foundry()
		"reactor": _dress_reactor()

# ------------------------------------------------------------------ materials

func _std(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _lamp(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

## Lit glass: shaded, so a board or pane still gets light and shadow on it.
func _glass(color: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var material := _std(color, 0.35)
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = energy
	return material

func _wall_shader(params: Dictionary = {}, shader: Shader = WALL_SHADER) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	return material

## Local sub-resource id (or shared .tres file name) -> replacement material.
func _build_replacements() -> void:
	match arena:
		"yard":
			var plaster := _wall_shader()
			_cornice = _std(Color(0.5, 0.42, 0.33), 0.9)
			_iron = _std(Color(0.06, 0.055, 0.05), 0.55, 0.5)
			_beacon = _lamp(Color(1.0, 0.1, 0.06), 1.5)
			_roof = _std(Color(0.2, 0.12, 0.085), 0.85)
			_replacements = {
				"Material_wall": plaster,
				"Material_plate": _wall_shader({"flaking": 0.55}),
				"Material_frame": _std(Color(0.2, 0.14, 0.1), 0.9),
				"Material_inset": _std(Color(0.035, 0.028, 0.024), 0.95),
				"Material_tower": _wall_shader({"windows": true}),
				"Material_cyan": _lamp(Color(0.62, 0.46, 0.24), 1.0),
				"Material_amber": _lamp(Color(0.85, 0.48, 0.15), 1.0),
			}
		"foundry":
			_replacements = {
				"foundry_wall.tres": _wall_shader({"brick_share": 0.85, "flaking": 0.7}),
				"foundry_steel.tres": _std(Color(0.3, 0.25, 0.2), 0.8, 0.2),
				"foundry_dark.tres": _std(Color(0.05, 0.042, 0.036), 0.9, 0.1),
				"foundry_accent.tres": _lamp(Color(0.78, 0.42, 0.13), 1.0),
				"foundry_glow.tres": _lamp(Color(1.0, 0.66, 0.24), 1.0),
			}
		"reactor":
			_replacements = {
				"mat_wall": _wall_shader({}, HLAVAK_WALL_SHADER),
				"mat_steel": _std(Color(0.34, 0.28, 0.2), 0.7, 0.35),
				"mat_dark": _std(Color(0.06, 0.05, 0.04), 0.9, 0.1),
				"mat_accent": _glass(Color(0.16, 0.12, 0.06), _sodium, 0.3),
				"mat_glow": _lamp(_violet, 1.0),
			}

func _key_of(material: Material) -> String:
	var path := material.resource_path
	if "::" in path:
		return path.get_slice("::", 1)
	return path.get_file()

func _is_local(material: Material) -> bool:
	return "::" in material.resource_path and material.resource_path.begins_with(scene_file_path)

func _skin(node: Node) -> void:
	if node is MeshInstance3D:
		_skin_mesh_instance(node as MeshInstance3D)
	elif _in_hazards(node):
		pass
	elif node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		if multi != null and multi.mesh != null:
			multi.mesh = _skin_mesh(multi.mesh)
	elif node is Light3D:
		_skin_light(node as Light3D)
	for child in node.get_children():
		_skin(child)

func _skin_mesh_instance(instance: MeshInstance3D) -> void:
	if instance.mesh == null:
		return
	if _in_hazards(instance):
		_skin_hazard(instance)
		return
	var special := _special_material(instance)
	if special != null:
		instance.material_override = special
		return
	if arena == "yard" and instance.name.contains("WindowBand"):
		# The facade shader paints lit windows; the neon bands would double up.
		instance.visible = false
		return
	if instance.material_override != null:
		instance.material_override = _skin_material(instance.material_override)
		return
	for index in instance.mesh.get_surface_count():
		var current := instance.get_active_material(index)
		if current == null:
			continue
		var replacement := _skin_material(current)
		if replacement != current:
			instance.set_surface_override_material(index, replacement)

func _skin_mesh(mesh: Mesh) -> Mesh:
	var cached: Mesh = _meshes.get(mesh)
	if cached != null:
		return cached
	var copy := mesh.duplicate() as Mesh
	for index in copy.get_surface_count():
		var current := copy.surface_get_material(index)
		if current != null:
			copy.surface_set_material(index, _skin_material(current))
	_meshes[mesh] = copy
	return copy

func _skin_material(material: Material) -> Material:
	var cached: Material = _graded.get(material)
	if cached != null:
		return cached
	var result: Material = material
	var key := _key_of(material)
	if _replacements.has(key) and (_is_local(material) or not material.resource_path.begins_with("res://assets")):
		result = _replacements[key]
	elif material is StandardMaterial3D and not _is_local(material):
		result = _grade(material as StandardMaterial3D)
	_graded[material] = result
	return result

## Generic grade for kit art: warm tint over the texture, no cold metal.
func _grade(source: StandardMaterial3D) -> StandardMaterial3D:
	var copy := source.duplicate() as StandardMaterial3D
	var glows := source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or source.emission_enabled
	if glows:
		copy.albedo_color = _glow(source.albedo_color)
		if source.emission_enabled:
			copy.emission = _glow(source.emission)
		return copy
	var color := source.albedo_color
	var luma := color.get_luminance()
	if source.albedo_texture != null:
		var tint := _trim_tint(source.resource_name)
		copy.albedo_color = Color(color.r * tint.r, color.g * tint.g, color.b * tint.b, color.a)
	elif color.s > 0.4 and (color.h < 0.12 or color.h > 0.93):
		copy.albedo_color = color
	else:
		var flat := Color(_tint.r, _tint.g, _tint.b) * (luma * _lift / maxf(_tint.get_luminance(), 0.01))
		copy.albedo_color = Color(minf(flat.r, 1.0), minf(flat.g, 1.0), minf(flat.b, 1.0), color.a)
	copy.metallic = minf(source.metallic, 0.15)
	copy.roughness = maxf(source.roughness, 0.85)
	return copy

func _trim_tint(material_name: String) -> Color:
	if material_name.contains("Dark"):
		return _trims.get("Dark", _tint)
	for trim: String in ["Trim_03", "Trim_02", "Trim_01"]:
		if material_name.contains(trim):
			return _trims.get(trim, _tint)
	return _tint

## Cold or white glow -> sodium; purple -> delirium; warm stays warm.
func _glow(color: Color) -> Color:
	var strength := maxf(color.r, maxf(color.g, color.b)) * _glow_scale
	var result := color
	if color.s < 0.25 or (color.h > 0.42 and color.h < 0.74):
		result = _sodium * strength
	elif color.h >= 0.74 and color.h < 0.93:
		result = _violet * strength
	result.a = color.a
	return result

func _skin_light(light: Light3D) -> void:
	var color := light.light_color
	if light is DirectionalLight3D:
		return
	if arena == "foundry":
		# Six identical orange lamps wash everything one colour; pull them to tungsten.
		light.light_color = color.lerp(Color(1.0, 0.86, 0.66), 0.4)
		return
	if color.s > 0.2 and color.h > 0.42 and color.h < 0.74:
		light.light_color = _sodium
	elif color.s > 0.2 and color.h >= 0.74 and color.h < 0.93:
		light.light_color = _violet.lerp(Color.WHITE, 0.3)

## Visual-only exceptions to the table: pieces whose job differs from the
## material they were authored with.
func _special_material(instance: MeshInstance3D) -> Material:
	var label := String(instance.name)
	if arena == "yard":
		if label == "UpperGuide" or label == "BaseGuide":
			return _cornice
		if label.contains("Slat"):
			return _iron
		if label.ends_with("Antenna"):
			return _iron
		if label.ends_with("Beacon"):
			return _beacon
		if label.ends_with("Crown") and instance.get_parent().name == &"Skyline":
			return _roof
	return null

func _in_hazards(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != self:
		if UNTOUCHED.has(parent.name) and parent.get_parent() == self:
			return true
		parent = parent.get_parent()
	return false

## Hazards keep their own look, except the idle shock-plate grid, which would
## otherwise glow like a holodeck: each plate owns a private material copy.
func _skin_hazard(instance: MeshInstance3D) -> void:
	var plate := instance.material_override as ShaderMaterial
	if plate != null and plate.shader != null and plate.shader.resource_path.ends_with("electric_floor.gdshader"):
		plate.set_shader_parameter("idle_glow", Color(0.78, 0.5, 0.14, 1.0))
		plate.set_shader_parameter("idle_strength", 0.18)

# ------------------------------------------------------------------ dressing

func _wall_group(name: String) -> Node3D:
	return get_node(name) as Node3D

## A flat sign: dark board, a label on both sides when `both`, optional glow.
func _board(parent: Node3D, at: Vector3, size: Vector2, text: String, font: int, color: Color, outline: Color, board: Material, pixel: float = 0.005) -> void:
	var holder := Node3D.new()
	holder.position = at
	parent.add_child(holder)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.1)
	mesh.mesh = box
	mesh.material_override = board
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh)
	var label := Label3D.new()
	label.text = text
	label.font_size = font
	label.pixel_size = pixel
	label.outline_size = 10
	label.modulate = color
	label.outline_modulate = outline
	label.double_sided = false
	label.position = Vector3(0.0, 0.0, 0.056)
	holder.add_child(label)

func _strip(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

func _local_light(parent: Node3D, at: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	parent.add_child(light)

## Deterministic 0..1 value from an index; dressing never draws from an RNG.
func _spread(index: int, salt: int) -> float:
	return fposmod(sin(float(index) * 12.9898 + float(salt) * 78.233) * 43758.5453, 1.0)

func _dress_yard() -> void:
	var board := _std(Color(0.045, 0.035, 0.035), 0.6, 0.2)
	var red := _lamp(Color(1.0, 0.12, 0.08), 1.6)
	var yellow := _lamp(Color(1.0, 0.76, 0.22), 1.4)
	var cream := Color(0.95, 0.85, 0.6)
	var brown := Color(0.15, 0.08, 0.02)
	# Herna NONSTOP on the east facade: board, neon frame, blade sign.
	var east := _wall_group("EastArchitecture")
	_board(east, Vector3(-9.6, 3.1, -31.8), Vector2(5.2, 1.0), "HERNA NONSTOP", 100, Color(1.0, 0.16, 0.1), Color(0.45, 0.0, 0.0), board)
	for edge in [-1.0, 1.0]:
		_strip(east, Vector3(-9.6, 3.1 + edge * 0.52, -31.72), Vector3(5.3, 0.05, 0.05), yellow)
		_strip(east, Vector3(-9.6 + edge * 2.65, 3.1, -31.72), Vector3(0.05, 1.07, 0.05), yellow)
	_board(east, Vector3(-9.6, 2.2, -31.8), Vector2(3.2, 0.5), "VÝHERNÍ AUTOMATY · 777", 40, Color(1.0, 0.82, 0.25), Color(0.3, 0.1, 0.0), board)
	_local_light(east, Vector3(-9.6, 2.6, -30.6), Color(1.0, 0.18, 0.1), 1.4, 8.0)
	# Hostinec on the west facade: shingle plus a lit PIVO blade sign.
	var west := _wall_group("WestArchitecture")
	_board(west, Vector3(9.6, 2.75, -31.8), Vector2(2.6, 0.5), "HOSTINEC U PÁNA HERNY", 40, cream, brown, board)
	var blade := Node3D.new()
	blade.position = Vector3(12.8, 3.2, -31.2)
	west.add_child(blade)
	_strip(blade, Vector3.ZERO, Vector3(0.1, 0.62, 0.84), board)
	for edge in [-1.0, 1.0]:
		_strip(blade, Vector3(0.0, edge * 0.33, 0.0), Vector3(0.12, 0.04, 0.88), yellow)
		var label := Label3D.new()
		label.text = "PIVO"
		label.font_size = 60
		label.pixel_size = 0.005
		label.outline_size = 10
		label.modulate = Color(1.0, 0.86, 0.35)
		label.outline_modulate = Color(0.4, 0.2, 0.0)
		label.double_sided = false
		label.position = Vector3(0.056 * edge, 0.0, 0.0)
		label.rotation = Vector3(0.0, PI * 0.5 * edge, 0.0)
		blade.add_child(label)
	_local_light(west, Vector3(12.0, 3.0, -30.4), Color(1.0, 0.7, 0.3), 1.2, 7.0)
	# Tabák on the south facade.
	var south := _wall_group("SouthArchitecture")
	_board(south, Vector3(9.6, 3.0, -31.8), Vector2(2.4, 0.56), "TABÁK · LOTO · NOVINY", 38, Color(0.95, 0.82, 0.5), brown, board)
	_strip(south, Vector3(9.6, 1.7, -31.86), Vector3(1.8, 1.0, 0.04), _lamp(Color(1.0, 0.62, 0.26), 0.9))
	# A sodium lamp hangs on a wire strung across the yard over every fill.
	var wire_material := _std(Color(0.04, 0.04, 0.04), 0.7)
	var lamp_shade := _std(Color(0.06, 0.055, 0.05), 0.55, 0.5)
	var lamp_glass := _lamp(Color(1.0, 0.62, 0.24), 3.0)
	for fill in ["CyanFill", "AmberFill", "CyanFillSouth", "AmberFillWest"]:
		var lamp := get_node(fill) as OmniLight3D
		var at := Vector3(lamp.position.x, 5.3, lamp.position.z)
		_strip(_dressing, Vector3(0.0, 5.7, lamp.position.z), Vector3(78.0, 0.025, 0.025), wire_material)
		_strip(_dressing, at, Vector3(0.34, 0.1, 0.34), lamp_shade)
		_strip(_dressing, at + Vector3(0.0, -0.08, 0.0), Vector3(0.26, 0.05, 0.26), lamp_glass)
		_strip(_dressing, at + Vector3(0.0, 0.2, 0.0), Vector3(0.02, 0.4, 0.02), wire_material)
	_build_tv_tower()

## Žižkovský vysílač, far beyond the roofs and exempt from fog.
func _build_tv_tower() -> void:
	var base := Vector3(-0.55, 0.0, -0.83).normalized() * 165.0
	var concrete := _std(Color(0.6, 0.58, 0.55), 0.55, 0.0)
	var cabin := _std(Color(0.32, 0.31, 0.3), 0.4, 0.4)
	var windows := _lamp(Color(1.0, 0.76, 0.46), 1.2)
	var beacon := _lamp(Color(1.0, 0.08, 0.05), 4.0)
	for material: StandardMaterial3D in [concrete, cabin, windows, beacon]:
		material.disable_fog = true
	for tube in [[Vector2(0.0, -2.6), 3.2, 134.0], [Vector2(-6.2, 3.4), 2.4, 118.0], [Vector2(6.2, 3.4), 2.4, 124.0]]:
		var offset: Vector2 = tube[0]
		var height: float = tube[2]
		_cylinder(base + Vector3(offset.x, height * 0.5, offset.y), tube[1], height, concrete)
		_cylinder(base + Vector3(offset.x, height + 0.4, offset.y), 0.7, 1.4, beacon)
	for level in [[66.0, 8.0], [93.0, 7.0]]:
		var tall: float = level[1]
		var pod := base + Vector3(0.0, level[0], 0.6)
		_strip(_dressing, pod, Vector3(19.0, tall, 13.0), cabin)
		_cylinder(pod + Vector3(-9.5, 0.0, 0.0), 3.25, tall, cabin)
		_cylinder(pod + Vector3(9.5, 0.0, 0.0), 3.25, tall, cabin)
		_strip(_dressing, pod + Vector3(0.0, tall * 0.12, 0.0), Vector3(19.1, 1.3, 13.1), windows)
	for mast in [[134.0, 160.0, 1.1], [160.0, 192.0, 0.65], [192.0, 216.0, 0.3]]:
		var low: float = mast[0]
		var high: float = mast[1]
		_cylinder(base + Vector3(0.0, (low + high) * 0.5, -2.6), mast[2], high - low, concrete)
		_cylinder(base + Vector3(0.0, high, -2.6), 0.6, 1.2, beacon)

func _cylinder(at: Vector3, radius: float, height: float, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dressing.add_child(instance)

func _dress_foundry() -> void:
	var board := _std(Color(0.05, 0.04, 0.035), 0.6, 0.2)
	var rod := _std(Color(0.05, 0.045, 0.04), 0.6, 0.4)
	var cream := Color(0.95, 0.85, 0.6)
	var brown := Color(0.15, 0.08, 0.02)
	# Tram-stop boards hung over the junction, readable from either end.
	_hang_sign(Vector3(0.0, 5.6, -6.5), Vector2(8.6, 1.5), "PALMOVKA · KOCOVINA", 140, cream, brown, board, rod)
	_hang_sign(Vector3(-18.0, 5.3, -6.5), Vector2(4.0, 1.0), "ZASTAVÁRNA", 110, Color(1.0, 0.7, 0.2), brown, board, rod)
	# The kit's corporate floor logo becomes stencilled road paint.
	var logo := get_node_or_null("FloorDetail/Decal11") as Node3D
	if logo != null:
		logo.visible = false
		var stencil := Label3D.new()
		stencil.text = "PALMOVKA"
		stencil.font_size = 120
		stencil.pixel_size = 0.009
		stencil.outline_size = 0
		stencil.modulate = Color(0.78, 0.7, 0.46, 0.85)
		stencil.shaded = true
		stencil.double_sided = false
		stencil.position = Vector3(logo.position.x, 0.04, logo.position.z)
		stencil.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		_dressing.add_child(stencil)
	_hang_sign(Vector3(18.0, 5.3, -6.5), Vector2(5.2, 1.0), "BAZAR · SLEVY 50 %", 72, Color(0.95, 0.34, 0.22), brown, board, rod)

## A board on two rods from the roof truss with the same text on both faces.
func _hang_sign(at: Vector3, size: Vector2, text: String, font: int, color: Color, outline: Color, board: Material, rod: Material) -> void:
	var holder := Node3D.new()
	holder.position = at
	_dressing.add_child(holder)
	for side in [-1.0, 1.0]:
		var face := Node3D.new()
		face.rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, 0.0)
		holder.add_child(face)
		_board(face, Vector3(0.0, 0.0, 0.0), size, text, font, color, outline, board)
		_strip(holder, Vector3(side * (size.x * 0.5 - 0.3), size.y * 0.5 + 0.8, 0.0), Vector3(0.04, 1.6, 0.04), rod)

func _dress_reactor() -> void:
	var texts: Array[String] = [
		"ODJEZDY\n23:59 TARTARUS", "NÁSTUPIŠTĚ 3\nDELIRIUM EXPRES", "POSLEDNÍ VLAK\n00:00", "ZPOŽDĚNÍ\n666 MIN", "PŘÍJEZDY\nBAN 24 H",
		"WC · 5 Kč\nHALA ZAVŘENA", "TABÁK · LOTO\nNONSTOP", "INFORMACE\nNEFUNGUJÍ",
	]
	var ink := Color(0.09, 0.05, 0.02)
	var index := 0
	for group in ["NorthInfrastructure", "EastInfrastructure", "SouthInfrastructure", "WestInfrastructure"]:
		var wall := _wall_group(group)
		for child in wall.get_children():
			if String(child.name).begins_with("Screen") and child is Node3D and not String(child.name).contains("Rule"):
				var label := Label3D.new()
				label.text = texts[index % texts.size()]
				label.font_size = 36
				label.pixel_size = 0.0085
				label.outline_size = 0
				label.modulate = ink
				label.double_sided = false
				label.position = (child as Node3D).position + Vector3(0.0, 0.0, 0.03)
				wall.add_child(label)
				index += 1
