class_name BaseBackdrop
extends Node3D

## Original procedural workshop geometry; no imported art or moving menu camera.
func _ready() -> void:
	var steel := _material(Color(0.08, 0.12, 0.16), 0.65)
	var dark := _material(Color(0.025, 0.035, 0.05), 0.45)
	var trim := _material(Color(0.22, 0.34, 0.4), 0.75)
	var cyan := _material(Color(0.05, 0.8, 0.85), 0.3, true)
	var amber := _material(Color(1.0, 0.38, 0.07), 0.3, true)
	_box(Vector3(0, -0.2, 0), Vector3(26, 0.4, 22), steel)
	_box(Vector3(0, 4, -8), Vector3(26, 8, 0.4), dark)
	for x in [-12.0, -8.0, -4.0, 4.0, 8.0, 12.0]:
		_box(Vector3(x, 3.5, -7.7), Vector3(0.35, 7, 0.55), trim)
		_box(Vector3(x, 6.8, -7.35), Vector3(0.12, 1.3, 0.12), cyan)
	for z in [-6.0, -2.0, 2.0, 6.0, 10.0]:
		_box(Vector3(0, 0.025, z), Vector3(23, 0.025, 0.045), trim)
	for x in [-9.0, 9.0]:
		_box(Vector3(x, 0.03, 1), Vector3(0.09, 0.03, 15), amber)
	# Blast door and its inset mechanical slats.
	_box(Vector3(0, 3.1, -7.65), Vector3(5.4, 6.2, 0.25), trim)
	for y in range(8):
		_box(Vector3(0, 0.4 + y * 0.7, -7.45), Vector3(5, 0.12, 0.2), dark)
	_box(Vector3(0, 6.5, -7.25), Vector3(5.4, 0.1, 0.15), amber)
	_sign("KAKABOOMBOOM // FIELD WORKSHOP", Vector3(0, 7.25, -7.1), 0.012, cyan.albedo_color)
	# Recognizable steel workbenches: tops, four legs, tool boards and monitors.
	for x in [-6.0, 0.0, 6.0]:
		_box(Vector3(x, 1.4, -3.7), Vector3(4.4, 0.2, 1.8), trim)
		for dx in [-1.8, 1.8]:
			for dz in [-0.65, 0.65]:
				_box(Vector3(x + dx, 0.65, -3.7 + dz), Vector3(0.15, 1.3, 0.15), steel)
		_box(Vector3(x, 2.8, -4.55), Vector3(4.1, 2.3, 0.12), dark)
		_box(Vector3(x + 1.45, 1.95, -3.9), Vector3(0.9, 0.7, 0.12), cyan)
		for tool in range(5):
			_box(Vector3(x - 1.6 + tool * 0.45, 2.9, -4.4), Vector3(0.08, 0.65, 0.08), trim)
		_sign(["ARMOR FORGE", "WEAPON BENCH", "GADGET LAB"][int((x + 6.0) / 6.0)], Vector3(x, 4.2, -4.4), 0.009, cyan.albedo_color)
	# Armor stand with chest plate, shoulder plates and helmet.
	_box(Vector3(-6.8, 2.0, -3.6), Vector3(0.18, 1.1, 0.18), dark)
	_box(Vector3(-6.8, 2.45, -3.55), Vector3(0.8, 0.75, 0.45), steel)
	for x in [-7.35, -6.25]:
		_box(Vector3(x, 2.65, -3.55), Vector3(0.4, 0.35, 0.5), trim)
	_box(Vector3(-6.8, 3.1, -3.55), Vector3(0.5, 0.45, 0.48), trim)
	_box(Vector3(-6.8, 3.12, -3.28), Vector3(0.38, 0.09, 0.025), amber)
	# Three realistically sized receiver/barrel/stock displays at the gun bench.
	for index in range(3):
		var x := -1.3 + index * 1.0
		_box(Vector3(x, 1.65, -3.7), Vector3(0.45, 0.22, 0.18), steel)
		_box(Vector3(x + 0.45, 1.66, -3.7), Vector3(0.5, 0.08, 0.08), trim)
		_box(Vector3(x - 0.36, 1.62, -3.7), Vector3(0.28, 0.15, 0.13), dark)
		_box(Vector3(x - 0.05, 1.52, -3.7), Vector3(0.1, 0.21, 0.12), dark)
	# Crystal-powered gadget rigs and industrial forge.
	for index in range(3):
		var pos := Vector3(5.0 + index * 0.7, 1.65, -3.7)
		_cylinder(pos, 0.22, 0.3, steel)
		_box(pos + Vector3.UP * 0.3, Vector3(0.14, 0.35, 0.14), cyan)
	_cylinder(Vector3(-10, 1.1, -3.5), 0.85, 2.2, steel)
	_cylinder(Vector3(-10, 2.25, -3.5), 0.7, 0.12, amber)
	# Foreground deployment platform, crates, and floor strip lighting.
	_cylinder(Vector3(0, 0.07, 3.0), 3.8, 0.12, trim)
	_cylinder(Vector3(0, 0.15, 3.0), 3.6, 0.08, dark)
	for x in [-4.6, 4.6]:
		_box(Vector3(x, 0.06, 3), Vector3(0.08, 0.06, 5.0), cyan)
	for index in range(3):
		_box(Vector3(8.5 + index * 0.8, 0.5, 4.0 + index * 0.35), Vector3(0.9, 1, 0.9), steel)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.012, 0.022, 0.04)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.38, 0.54, 0.68)
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -30, 0)
	key.light_color = Color(0.6, 0.83, 1)
	key.light_energy = 1.8
	add_child(key)
	for x in [-7.0, 7.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 4, -2)
		light.light_color = Color(0.14, 0.8, 1) if x > 0 else Color(1, 0.38, 0.12)
		light.light_energy = 3.0
		light.omni_range = 10
		add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(11, 8.5, 14)
	camera.look_at(Vector3(0, -4, -2))
	camera.fov = 58
	camera.current = true

func _material(color: Color, metallic: float, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.65
	material.emission_enabled = glow
	material.emission = color if glow else Color.BLACK
	material.emission_energy_multiplier = 1.8
	return material

func _box(at: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	add_child(visual)

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
