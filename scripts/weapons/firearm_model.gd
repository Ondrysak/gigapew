extends Node3D
## Original hard-surface models: authored in metres, forward -Z. Built once per
## weapon kind and shared by all views; no geometry work during firing.
@export_enum("pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower") var kind := "pulse"

static var _models: Dictionary = {}
static var _materials: Dictionary = {}
static var _primitives: Dictionary = {}
var _surfaces: Dictionary = {}

func _ready() -> void:
	if not _models.has(kind):
		_build()
		_models[kind] = _commit()
	_add_mesh(_models[kind], self, "WeaponAndGlove")
	if kind == "minigun":
		if not _models.has("barrel_cluster"):
			_surfaces.clear()
			_build_cluster()
			_models["barrel_cluster"] = _commit()
		_add_mesh(_models["barrel_cluster"], get_parent().get_node("Spinner") as Node3D, "SixBarrelCluster")
	_surfaces.clear()

func _add_mesh(mesh: ArrayMesh, parent: Node3D, node_name: String) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.72
	match key:
		"steel":
			mat.albedo_color = Color(0.19, 0.205, 0.22)
			mat.metallic = 0.8
			mat.roughness = 0.43
		"edge":
			mat.albedo_color = Color(0.29, 0.30, 0.31)
			mat.metallic = 0.82
			mat.roughness = 0.38
		"polymer": mat.albedo_color = Color(0.065, 0.072, 0.077)
		"black": mat.albedo_color = Color(0.015, 0.021, 0.025)
		"olive": mat.albedo_color = Color(0.19, 0.21, 0.14)
		"tan": mat.albedo_color = Color(0.30, 0.245, 0.17)
		"red": mat.albedo_color = Color(0.34, 0.075, 0.045)
		"brass":
			mat.albedo_color = Color(0.56, 0.40, 0.18)
			mat.metallic = 0.7
		"glove": mat.albedo_color = Color(0.14, 0.17, 0.18)
		"rubber": mat.albedo_color = Color(0.037, 0.047, 0.048)
		"sleeve": mat.albedo_color = Color(0.21, 0.25, 0.23)
		"cyan", "violet", "amber", "pilot":
			var accents := {"cyan": Color(0.12, 0.65, 0.68), "violet": Color(0.49, 0.30, 0.71), "amber": Color(0.82, 0.46, 0.12), "pilot": Color(0.3, 0.55, 0.9)}
			mat.albedo_color = accents[key]
			mat.emission_enabled = true
			mat.emission = accents[key]
			mat.emission_energy_multiplier = 0.65
		"gauge": mat.albedo_color = Color(0.7, 0.72, 0.65)
	_materials[key] = mat
	return mat

func _primitive(shape: String) -> Mesh:
	if _primitives.has(shape):
		return _primitives[shape]
	var mesh: Mesh
	match shape:
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 1.0
			cylinder.radial_segments = 16
			mesh = cylinder
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 12
			sphere.rings = 8
			mesh = sphere
		"ring": mesh = _ring_mesh()
		_: mesh = _chamfer_mesh()
	_primitives[shape] = mesh
	return mesh

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, c, b]:
		surface.set_normal(normal)
		surface.add_vertex(point)

func _chamfer_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(-0.36, -0.5), Vector2(-0.5, -0.36), Vector2(-0.5, 0.36), Vector2(-0.36, 0.5), Vector2(0.36, 0.5), Vector2(0.5, 0.36), Vector2(0.5, -0.36), Vector2(0.36, -0.5)]
	for i in 8:
		var p: Vector2 = profile[i]
		var q: Vector2 = profile[(i + 1) % 8]
		var a := Vector3(p.x, p.y, -0.5)
		var b := Vector3(q.x, q.y, -0.5)
		var c := Vector3(q.x, q.y, 0.5)
		var d := Vector3(p.x, p.y, 0.5)
		_triangle(surface, a, c, b)
		_triangle(surface, a, d, c)
		_triangle(surface, Vector3(0, 0, -0.5), a, b)
		_triangle(surface, Vector3(0, 0, 0.5), c, d)
	return surface.commit()

func _ring_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var a := float(i) * TAU / 24.0
		var b := float(i + 1) * TAU / 24.0
		var pa := Vector3(cos(a), sin(a), 0)
		var pb := Vector3(cos(b), sin(b), 0)
		for z: float in [-0.5, 0.5]:
			var oa := pa + Vector3(0, 0, z)
			var ob := pb + Vector3(0, 0, z)
			var ia := pa * 0.68 + Vector3(0, 0, z)
			var ib := pb * 0.68 + Vector3(0, 0, z)
			if z < 0:
				_triangle(surface, oa, ia, ib)
				_triangle(surface, oa, ib, ob)
			else:
				_triangle(surface, oa, ob, ib)
				_triangle(surface, oa, ib, ia)
		for radius: float in [1.0, 0.68]:
			var a0 := pa * radius + Vector3(0, 0, -0.5)
			var b0 := pb * radius + Vector3(0, 0, -0.5)
			var a1 := pa * radius + Vector3(0, 0, 0.5)
			var b1 := pb * radius + Vector3(0, 0, 0.5)
			if radius > 0.9:
				_triangle(surface, a0, b0, b1)
				_triangle(surface, a0, b1, a1)
			else:
				_triangle(surface, a0, a1, b1)
				_triangle(surface, a0, b1, b0)
	return surface.commit()

func _part(shape: String, material: String, at: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	if not _surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = surface
	var transform := Transform3D(Basis.from_euler(rotation) * Basis.from_scale(size), at)
	var surface: SurfaceTool = _surfaces[material]
	surface.append_from(_primitive(shape), 0, transform)

func _box(material: String, at: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	_part("chamfer", material, at, size, rotation)

func _tube(material: String, at: Vector3, radius: float, length: float) -> void:
	_part("ring", material, at, Vector3(radius, radius, length))

func _rod(material: String, a: Vector3, b: Vector3, radius: float) -> void:
	var direction := b - a
	var rotation := Quaternion(Vector3.UP, direction.normalized())
	if not _surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = surface
	var surface: SurfaceTool = _surfaces[material]
	surface.append_from(_primitive("cylinder"), 0, Transform3D(Basis(rotation) * Basis.from_scale(Vector3(radius, direction.length(), radius)), (a + b) * 0.5))

func _joint(material: String, at: Vector3, size: Vector3) -> void:
	_part("sphere", material, at, size)

func _commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: String in _surfaces:
		var surface: SurfaceTool = _surfaces[key]
		surface.set_material(_material(key))
		surface.commit(mesh)
	return mesh

func _build() -> void:
	_common_receiver()
	match kind:
		"pulse": _pulse()
		"rail": _rail()
		"scatter": _scatter()
		"minigun": _minigun()
		"autocannon": _autocannon()
		"flamethrower": _flamethrower()
	_hand()

func _common_receiver() -> void:
	var finish := "olive" if kind == "autocannon" else "steel"
	_box(finish, Vector3(0, 0, 0), Vector3(0.082, 0.082, 0.235))
	_box("polymer", Vector3(0, -0.039, 0.012), Vector3(0.078, 0.033, 0.18))
	_box("polymer", Vector3(0, -0.12, 0.075), Vector3(0.038, 0.15, 0.055), Vector3(-0.18, 0, 0))
	# Open trigger guard, trigger, safety and ejection port.
	_rod("steel", Vector3(-0.022, -0.055, 0.033), Vector3(-0.022, -0.113, -0.025), 0.004)
	_rod("steel", Vector3(-0.022, -0.113, -0.025), Vector3(-0.022, -0.06, -0.04), 0.004)
	_rod("steel", Vector3(0.022, -0.055, 0.033), Vector3(0.022, -0.113, -0.025), 0.004)
	_rod("steel", Vector3(0.022, -0.113, -0.025), Vector3(0.022, -0.06, -0.04), 0.004)
	_rod("edge", Vector3(0, -0.061, 0.006), Vector3(0, -0.087, 0.017), 0.003)
	_box("black", Vector3(0.042, 0.007, -0.035), Vector3(0.003, 0.027, 0.058))
	_box("edge", Vector3(0.044, 0.006, -0.016), Vector3(0.003, 0.019, 0.028))
	_box("edge", Vector3(-0.044, -0.019, 0.045), Vector3(0.006, 0.008, 0.024), Vector3(0.2, 0, 0))
	# Skeleton stock is small enough to remain below the sight picture.
	_rod("steel", Vector3(-0.021, 0.015, 0.115), Vector3(-0.021, -0.02, 0.215), 0.007)
	_rod("steel", Vector3(0.021, 0.015, 0.115), Vector3(0.021, -0.02, 0.215), 0.007)
	_box("polymer", Vector3(0, -0.025, 0.225), Vector3(0.055, 0.096, 0.032))
	_box("rubber", Vector3(0, -0.025, 0.244), Vector3(0.055, 0.094, 0.009))
	_box("polymer", Vector3(0, 0.025, 0.145), Vector3(0.05, 0.025, 0.075))
	for z in [-0.075, 0.025, 0.085]:
		for side in [-1.0, 1.0]:
			_part("cylinder", "edge", Vector3(side * 0.0425, -0.021, z), Vector3(0.005, 0.003, 0.005), Vector3(0, 0, PI / 2))
	_top_rail(-0.08, 0.095, 0.047)
	_sights()

func _top_rail(front: float, back: float, height: float) -> void:
	_box("black", Vector3(0, height, (front + back) / 2), Vector3(0.029, 0.012, back - front))
	var count := int((back - front) / 0.015)
	for index in count:
		_box("steel", Vector3(0, height + 0.01, front + index * 0.015), Vector3(0.038, 0.009, 0.008))

func _sights() -> void:
	# Thin open rear aperture, not a glowing panel or opaque sight block.
	for side in [-1.0, 1.0]:
		_box("black", Vector3(side * 0.016, 0.078, 0.05), Vector3(0.006, 0.034, 0.02))
	_box("black", Vector3(0, 0.096, 0.05), Vector3(0.038, 0.006, 0.02))
	_box("steel", Vector3(0, 0.064, -0.405), Vector3(0.013, 0.032, 0.018))
	_joint("amber", Vector3(0, 0.082, -0.406), Vector3(0.002, 0.002, 0.002))

func _vents(width: float, front: float, back: float, height: float, finish: String) -> void:
	for side in [-1.0, 1.0]:
		_box(finish, Vector3(side * width, height, (front + back) / 2), Vector3(0.008, 0.065, back - front))
		for i in 8:
			_box("black", Vector3(side * (width + 0.0045), height + 0.009, lerpf(front + 0.018, back - 0.018, i / 7.0)), Vector3(0.002, 0.026, 0.012), Vector3(0.2, 0, 0))

func _pulse() -> void:
	# Compact carbine: enclosed barrel, practical curved magazine and gas tube.
	_tube("steel", Vector3(0, 0, -0.287), 0.015, 0.33)
	_vents(0.04, -0.355, -0.12, 0, "polymer")
	_box("polymer", Vector3(0, -0.035, -0.235), Vector3(0.076, 0.015, 0.23))
	_top_rail(-0.35, -0.12, 0.037)
	_tube("black", Vector3(0, 0, -0.45), 0.022, 0.05)
	for side in [-1.0, 1.0]:
		_box("black", Vector3(side * 0.022, 0, -0.454), Vector3(0.002, 0.01, 0.018))
	_box("steel", Vector3(0, -0.102, -0.047), Vector3(0.048, 0.117, 0.06), Vector3(-0.13, 0, 0))
	_box("polymer", Vector3(0, -0.17, -0.035), Vector3(0.047, 0.045, 0.057), Vector3(-0.25, 0, 0))
	for side in [-1.0, 1.0]:
		for z in [-0.064, -0.046]:
			_box("black", Vector3(side * 0.025, -0.107, z), Vector3(0.002, 0.09, 0.004))
	_box("cyan", Vector3(-0.043, 0.026, 0.022), Vector3(0.002, 0.005, 0.022))
	_rod("edge", Vector3(0, 0.027, -0.35), Vector3(0, 0.027, -0.14), 0.006)

func _rail() -> void:
	# Long, exposed acceleration rails and ceramic insulators, not luminous slabs.
	for side in [-1.0, 1.0]:
		_box("steel", Vector3(side * 0.038, 0, -0.29), Vector3(0.027, 0.035, 0.36))
		_box("black", Vector3(side * 0.041, -0.026, -0.28), Vector3(0.027, 0.025, 0.32))
		for i in 7:
			var z := -0.14 - i * 0.043
			_box("tan", Vector3(side * 0.039, 0, z), Vector3(0.036, 0.047, 0.012))
			_box("violet", Vector3(side * 0.058, 0.012, z), Vector3(0.002, 0.006, 0.008))
	_tube("black", Vector3(0, 0, -0.46), 0.029, 0.03)
	_box("polymer", Vector3(0, -0.093, -0.044), Vector3(0.055, 0.093, 0.086))
	for side in [-1.0, 1.0]:
		_tube("steel", Vector3(side * 0.056, -0.006, 0.04), 0.016, 0.095)
		_tube("violet", Vector3(side * 0.056, -0.006, 0.082), 0.017, 0.004)
	# Small tubular optic on rings, kept close to the receiver.
	_box("steel", Vector3(0, 0.075, -0.019), Vector3(0.025, 0.036, 0.073))
	_tube("black", Vector3(0, 0.102, -0.03), 0.025, 0.105)
	_tube("edge", Vector3(0, 0.102, 0.019), 0.028, 0.012)
	_part("cylinder", "violet", Vector3(0, 0.102, 0.015), Vector3(0.017, 0.002, 0.017), Vector3(PI / 2, 0, 0))
	_part("cylinder", "steel", Vector3(0.031, 0.109, -0.03), Vector3(0.008, 0.018, 0.008), Vector3(0, 0, PI / 2))

func _scatter() -> void:
	# Pump shotgun: steel barrel and tube magazine, ribbed polymer fore-end.
	_tube("steel", Vector3(0, 0.006, -0.291), 0.022, 0.365)
	_tube("steel", Vector3(0, -0.043, -0.245), 0.018, 0.25)
	_tube("edge", Vector3(0, 0.006, -0.463), 0.025, 0.023)
	_box("tan", Vector3(0, -0.04, -0.245), Vector3(0.069, 0.055, 0.135))
	for i in 9:
		_box("polymer", Vector3(0, -0.046, -0.303 + i * 0.015), Vector3(0.074, 0.053, 0.005))
	_rod("edge", Vector3(-0.035, -0.025, -0.28), Vector3(-0.035, -0.025, -0.055), 0.003)
	_box("black", Vector3(-0.046, 0.004, 0.009), Vector3(0.008, 0.067, 0.14))
	for i in 4:
		var z := 0.055 - i * 0.032
		_part("cylinder", "red", Vector3(-0.054, 0.011, z), Vector3(0.01, 0.05, 0.01))
		_part("cylinder", "brass", Vector3(-0.054, -0.018, z), Vector3(0.0105, 0.009, 0.0105))
	_box("steel", Vector3(0, 0.036, 0.029), Vector3(0.012, 0.012, 0.06))

func _minigun() -> void:
	# Compact powered rotary gun with gearbox, motor, linked ammunition feed.
	_tube("steel", Vector3(0, 0, -0.102), 0.071, 0.065)
	_tube("black", Vector3(0, 0, -0.08), 0.076, 0.018)
	_box("steel", Vector3(0, -0.048, -0.07), Vector3(0.108, 0.049, 0.155))
	_tube("steel", Vector3(0.062, -0.038, 0.018), 0.024, 0.145)
	for i in 6:
		_tube("black", Vector3(0.062, -0.038, -0.038 + i * 0.018), 0.025, 0.005)
	_box("olive", Vector3(-0.091, -0.07, 0.018), Vector3(0.082, 0.127, 0.13))
	_box("black", Vector3(-0.091, -0.004, 0.018), Vector3(0.087, 0.013, 0.139))
	for i in 7:
		var x := -0.116 + i * 0.013
		var y := 0.021 + sin(i * 0.45) * 0.018
		_rod("brass", Vector3(x, y, -0.029), Vector3(x, y, 0.022), 0.005)
		_box("steel", Vector3(x, y, 0.003), Vector3(0.008, 0.015, 0.007))
	for side in [-1.0, 1.0]:
		_rod("steel", Vector3(side * 0.029, 0.042, -0.068), Vector3(side * 0.029, 0.09, -0.068), 0.005)
	_rod("polymer", Vector3(-0.029, 0.09, -0.068), Vector3(0.029, 0.09, -0.068), 0.009)
	_box("amber", Vector3(0.044, 0.017, 0.062), Vector3(0.002, 0.006, 0.011))

func _build_cluster() -> void:
	_tube("steel", Vector3(0, 0, -0.135), 0.063, 0.025)
	_tube("steel", Vector3(0, 0, -0.39), 0.063, 0.018)
	_tube("black", Vector3(0, 0, -0.43), 0.061, 0.018)
	_rod("black", Vector3(0, 0, -0.11), Vector3(0, 0, -0.446), 0.017)
	for i in 6:
		var angle := i * TAU / 6.0
		var at := Vector3(cos(angle) * 0.043, sin(angle) * 0.043, -0.292)
		_tube("steel", at, 0.011, 0.362)
		_tube("edge", Vector3(at.x, at.y, -0.465), 0.014, 0.021)
		_part("cylinder", "edge", Vector3(at.x, at.y, -0.12), Vector3(0.004, 0.003, 0.004), Vector3(PI / 2, 0, 0))
	_box("tan", Vector3(0.059, 0, -0.39), Vector3(0.003, 0.011, 0.018))

func _autocannon() -> void:
	# Heavy, grounded drum-fed cannon: ported brake and ribbed heat shield.
	_tube("steel", Vector3(0, 0, -0.274), 0.025, 0.31)
	_vents(0.048, -0.335, -0.108, 0.004, "olive")
	_box("steel", Vector3(0, -0.035, -0.215), Vector3(0.093, 0.023, 0.21))
	_box("steel", Vector3(0, 0, -0.443), Vector3(0.08, 0.055, 0.062))
	_tube("black", Vector3(0, 0, -0.467), 0.023, 0.016)
	for side in [-1.0, 1.0]:
		for z in [-0.459, -0.441, -0.423]:
			_box("black", Vector3(side * 0.041, 0, z), Vector3(0.002, 0.026, 0.009))
	_part("cylinder", "steel", Vector3(0, -0.135, -0.044), Vector3(0.074, 0.091, 0.074), Vector3(0, 0, PI / 2))
	for side in [-1.0, 1.0]:
		_part("cylinder", "olive", Vector3(side * 0.047, -0.135, -0.044), Vector3(0.062, 0.006, 0.062), Vector3(0, 0, PI / 2))
		_part("cylinder", "edge", Vector3(side * 0.051, -0.135, -0.044), Vector3(0.017, 0.007, 0.017), Vector3(0, 0, PI / 2))
		for i in 8:
			var angle := i * TAU / 8.0
			_box("black", Vector3(side * 0.051, -0.135 + cos(angle) * 0.045, -0.044 + sin(angle) * 0.045), Vector3(0.003, 0.012, 0.004), Vector3(angle, 0, 0))
	_box("black", Vector3(0, -0.066, -0.044), Vector3(0.046, 0.04, 0.044))
	_top_rail(-0.31, -0.13, 0.045)
	_rod("edge", Vector3(-0.047, 0.02, 0.045), Vector3(-0.047, 0.02, -0.025), 0.005)

func _flamethrower() -> void:
	# Industrial burner with underside fuel bottle, valve, gauge and hoses.
	_tube("steel", Vector3(0, 0, -0.277), 0.025, 0.325)
	_vents(0.035, -0.34, -0.12, 0, "steel")
	_tube("black", Vector3(0, 0, -0.453), 0.037, 0.044)
	_tube("edge", Vector3(0, 0, -0.469), 0.039, 0.013)
	_rod("steel", Vector3(0, -0.041, -0.27), Vector3(0, -0.041, -0.461), 0.005)
	_joint("pilot", Vector3(0, -0.041, -0.476), Vector3(0.003, 0.008, 0.009))
	_part("cylinder", "red", Vector3(-0.044, -0.115, -0.041), Vector3(0.041, 0.145, 0.041))
	_joint("red", Vector3(-0.044, -0.188, -0.041), Vector3(0.041, 0.025, 0.041))
	_joint("red", Vector3(-0.044, -0.043, -0.041), Vector3(0.041, 0.023, 0.041))
	for y in [-0.155, -0.075]:
		_part("cylinder", "steel", Vector3(-0.044, y, -0.041), Vector3(0.043, 0.011, 0.043))
	_rod("brass", Vector3(-0.044, -0.042, -0.041), Vector3(-0.044, 0.01, -0.041), 0.008)
	_rod("steel", Vector3(-0.065, -0.016, -0.041), Vector3(-0.023, -0.016, -0.041), 0.003)
	# Segmented hose curves alongside the receiver, away from the reticle.
	var hose := [Vector3(-0.072, -0.055, -0.041), Vector3(-0.088, -0.035, -0.105), Vector3(-0.071, -0.017, -0.18), Vector3(-0.038, -0.015, -0.225)]
	for i in 3:
		_rod("rubber", hose[i], hose[i + 1], 0.008)
		_joint("rubber", hose[i + 1], Vector3.ONE * 0.008)
	_part("cylinder", "steel", Vector3(-0.052, 0.042, -0.085), Vector3(0.021, 0.015, 0.021), Vector3(0.45, 0, 0))
	_part("cylinder", "gauge", Vector3(-0.052, 0.05, -0.081), Vector3(0.017, 0.001, 0.017), Vector3(0.45, 0, 0))
	_box("black", Vector3(-0.052, 0.052, -0.082), Vector3(0.003, 0.002, 0.016), Vector3(0.45, 0.6, 0))
	for i in 3:
		_box("tan", Vector3(0.041, 0.008, -0.17 - i * 0.031), Vector3(0.002, 0.029, 0.008), Vector3(0.35, 0, 0))

func _finger(a: Vector3, b: Vector3, c: Vector3, radius: float) -> void:
	_rod("glove", a, b, radius)
	_rod("glove", b, c, radius * 0.9)
	_joint("glove", a, Vector3.ONE * radius)
	_joint("rubber", b, Vector3.ONE * (radius * 1.03))
	_joint("glove", c, Vector3.ONE * (radius * 0.9))

func _hand() -> void:
	# Anatomical rounded palm, four separately curled fingers and opposed thumb.
	# Hand wraps the pistol grip, rather than sitting beside it as a box-shaped paw.
	_joint("glove", Vector3(0.027, -0.137, 0.089), Vector3(0.028, 0.054, 0.04))
	_joint("rubber", Vector3(0.046, -0.133, 0.106), Vector3(0.012, 0.04, 0.026))
	for i in 4:
		var y := -0.097 - i * 0.024
		var radius := 0.0095 if i < 3 else 0.008
		_finger(Vector3(0.046, y, 0.068), Vector3(0.022, y - 0.005, 0.028), Vector3(-0.017, y - 0.007, 0.034), radius)
		_joint("rubber", Vector3(0.046, y, 0.075), Vector3(0.009, 0.009, 0.013))
	_finger(Vector3(0.006, -0.137, 0.119), Vector3(-0.031, -0.104, 0.103), Vector3(-0.025, -0.079, 0.053), 0.012)
	# Wrist and tapered jacket sleeve continue to the lower screen edge.
	_rod("glove", Vector3(0.028, -0.179, 0.117), Vector3(0.035, -0.206, 0.179), 0.024)
	_rod("rubber", Vector3(0.033, -0.199, 0.168), Vector3(0.035, -0.213, 0.192), 0.031)
	_box("black", Vector3(0.056, -0.203, 0.178), Vector3(0.024, 0.015, 0.032))
	_rod("sleeve", Vector3(0.035, -0.21, 0.189), Vector3(0.055, -0.278, 0.37), 0.037)
	_joint("sleeve", Vector3(0.048, -0.25, 0.296), Vector3(0.039, 0.041, 0.086))
	for z in [0.23, 0.275, 0.32]:
		_box("olive", Vector3(0.061, -0.235 - (z - 0.23) * 0.3, z), Vector3(0.009, 0.057, 0.008), Vector3(0.35, 0, 0))
