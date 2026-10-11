class_name BaseBackdrop
extends Node3D

## A fixed pawnshop corner built from salvaged boards, crates and old stock.
func _ready() -> void:
	var steel := _material(Color(0.18, 0.16, 0.13), 0.35)
	var dark := _material(Color(0.075, 0.06, 0.045), 0.15)
	var rust := _material(Color(0.29, 0.16, 0.10), 0.20)
	var wood := _material(Color(0.26, 0.19, 0.11), 0.0)
	var paper := _material(Color(0.57, 0.50, 0.36), 0.0)
	var olive := _material(Color(0.23, 0.25, 0.16), 0.0)
	var oxblood := _material(Color(0.28, 0.095, 0.07), 0.0)
	var bone := Color(0.79, 0.72, 0.57)
	_box(Vector3(0, -0.2, 0), Vector3(26, 0.4, 22), dark)
	_box(Vector3(0, 4, -8), Vector3(26, 8, 0.4), steel)
	# Uneven wall boards, exposed rust and a shutter that has seen better nights.
	for index in range(13):
		var x := -12.0 + index * 2.0
		_box(Vector3(x, 3.4, -7.72), Vector3(1.9, 6.6 - (index % 3) * 0.13, 0.12), wood if index % 3 == 0 else dark)
		_box(Vector3(x + 0.7, 4.8 - (index % 4) * 0.8, -7.62), Vector3(0.035, 1.3, 0.025), rust)
	for index in range(9):
		_box(Vector3(0, 0.4 + index * 0.66, -7.42), Vector3(5, 0.58, 0.18), steel if index % 2 == 0 else dark)
		_box(Vector3(-1.3 + (index % 4) * 0.7, 0.5 + index * 0.66, -7.3), Vector3(0.75, 0.025, 0.02), rust)
	_box(Vector3(0, 6.8, -7.35), Vector3(12.6, 1.2, 0.18), paper)
	_sign("LUĎAS · BAZAR POSLEDNÍHO SETU", Vector3(0, 6.8, -7.2), 0.010, Color(0.12, 0.085, 0.055))
	_sign("VÝKUP / PRODEJ / NA SEKERU", Vector3(0, 5.8, -7.1), 0.006, bone)
	# Photocopied notices overlap, with torn corners and strips of brown tape.
	for index in range(7):
		var x := -10.2 + index * 3.3
		var y := 4.1 + (index % 3) * 0.45
		var flyer := _box(Vector3(x, y, -7.45), Vector3(1.65, 1.9, 0.035), paper)
		flyer.rotation_degrees.z = -5.0 + (index % 4) * 3.0
		_box(Vector3(x - 0.32, y + 0.93, -7.39), Vector3(0.62, 0.12, 0.04), wood)
		_box(Vector3(x + 0.72, y - 0.83, -7.40), Vector3(0.20, 0.23, 0.05), dark)
		_sign(["POSLEDNÍ\nPARTY", "VÝKUP\nGRAMCŮ", "BEZ\nZÁRUKY"][index % 3], Vector3(x, y + 0.12, -7.35), 0.006, Color(0.18, 0.13, 0.08))
	# Battered counters, shelves, hanging tools and hand-painted station signs.
	for index in range(3):
		var x := -6.0 + index * 6.0
		_box(Vector3(x, 1.4, -3.7), Vector3(4.4, 0.24, 1.8), wood)
		for dx in [-1.8, 1.8]:
			for dz in [-0.65, 0.65]:
				_box(Vector3(x + dx, 0.65, -3.7 + dz), Vector3(0.18, 1.3, 0.18), rust)
		_box(Vector3(x, 2.8, -4.55), Vector3(4.1, 2.3, 0.12), dark)
		for scratch in range(6):
			_box(Vector3(x - 1.7 + scratch * 0.6, 1.535, -3.5 + (scratch % 3) * 0.22), Vector3(0.42, 0.01, 0.035), steel)
		for tool in range(5):
			_box(Vector3(x - 1.6 + tool * 0.45, 2.9, -4.4), Vector3(0.08, 0.65, 0.08), steel)
		_box(Vector3(x, 4.2, -4.50), Vector3(4.25, 0.65, 0.08), paper)
		_sign(["HADRY Z BAZARU", "ZBRANĚ NA SEKERU", "VYCHYTÁVKY"][index], Vector3(x, 4.2, -4.4), 0.008, Color(0.18, 0.13, 0.08))
	# Old coat on a makeshift hanger, rather than a lit armour display.
	_box(Vector3(-6.8, 2.0, -3.6), Vector3(0.12, 1.1, 0.12), rust)
	_box(Vector3(-6.8, 2.45, -3.55), Vector3(0.8, 0.9, 0.32), olive)
	for x in [-7.35, -6.25]:
		var sleeve := _box(Vector3(x, 2.40, -3.55), Vector3(0.30, 0.8, 0.32), olive)
		sleeve.rotation_degrees.z = 12.0 if x < -6.8 else -12.0
	_box(Vector3(-6.8, 3.0, -3.55), Vector3(0.48, 0.25, 0.4), dark)
	# Original gun-shaped stock remains gun-shaped; this does not swap models.
	for index in range(3):
		var x := -1.3 + index * 1.0
		_box(Vector3(x, 1.65, -3.7), Vector3(0.45, 0.22, 0.18), steel)
		_box(Vector3(x + 0.45, 1.66, -3.7), Vector3(0.5, 0.08, 0.08), steel)
		_box(Vector3(x - 0.36, 1.62, -3.7), Vector3(0.28, 0.15, 0.13), wood)
		_box(Vector3(x - 0.05, 1.52, -3.7), Vector3(0.1, 0.21, 0.12), dark)
	# Dead electronics, bottle crates and an old barrel crowd the floor.
	for index in range(3):
		var pos := Vector3(5.0 + index * 0.7, 1.65, -3.7)
		_box(pos, Vector3(0.48, 0.30, 0.38), olive if index % 2 == 0 else steel)
		_box(pos + Vector3(0, 0.08, 0.2), Vector3(0.32, 0.06, 0.025), dark)
	_cylinder(Vector3(-10, 1.1, -3.5), 0.85, 2.2, rust)
	_cylinder(Vector3(-10, 2.25, -3.5), 0.7, 0.12, dark)
	for index in range(5):
		var pos := Vector3(7.8 + (index % 3) * 1.1, 0.48 + floori(index / 3.0) * 0.95, 3.2 + (index % 2) * 0.35)
		_box(pos, Vector3(1.0, 0.9, 0.85), wood if index % 2 == 0 else oxblood)
		for slat in range(3):
			_box(pos + Vector3(0, -0.3 + slat * 0.3, 0.44), Vector3(0.98, 0.045, 0.04), dark)
	for index in range(12):
		_box(Vector3(-9.0 + index * 1.5, 0.015, 1.5 + (index % 4) * 0.75), Vector3(0.65, 0.025, 0.12), steel)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.035, 0.025, 0.018)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.61, 0.51, 0.37)
	settings.ambient_light_energy = 0.55
	environment.environment = settings
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -30, 0)
	key.light_color = Color(0.85, 0.73, 0.53)
	key.light_energy = 1.2
	add_child(key)
	for x in [-7.0, 7.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 4, -2)
		light.light_color = Color(0.78, 0.61, 0.37)
		light.light_energy = 1.6
		light.omni_range = 10
		add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(11, 8.5, 14)
	camera.look_at(Vector3(0, -4, -2))
	camera.fov = 58
	camera.current = true

func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.92
	return material

func _box(at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	add_child(visual)
	return visual

func _cylinder(at: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	add_child(visual)

func _sign(text: String, at: Vector3, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = pixel_size
	label.font_size = 48
	label.modulate = color
	add_child(label)
