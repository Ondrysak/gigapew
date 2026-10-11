class_name HordeArmorMesh
extends RefCounted

const FRONT_CENTER := Vector3(0, 1.15, -1.3)
const FRONT_SIZE := Vector3(1.8, 1.35, 0.24)

## Static, non-VAT overlay: one shared mesh and one fixed-capacity MultiMesh per
## plated type. Core coordinates are exactly the definition's precision sphere.
## Dressed as the herna door a Vyhazovač holds out, with a glowing NONSTOP
## strip; the rear weak spot is his fat gold money pouch.
static func bake(core_offset: Vector3, core_radius: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var plate := BoxMesh.new()
	plate.size = FRONT_SIZE
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.17, 0.08)
	wood.roughness = 0.8
	_append(mesh, plate, FRONT_CENTER, wood)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.12, 0.07, 0.04)
	frame.roughness = 0.7
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.1, FRONT_SIZE.y, 0.03)
		_append(mesh, post, FRONT_CENTER + Vector3(side * (FRONT_SIZE.x * 0.5 - 0.05), 0.0, -FRONT_SIZE.z * 0.5 - 0.015), frame)
	var handle := BoxMesh.new()
	handle.size = Vector3(0.18, 0.05, 0.06)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.66, 0.25)
	brass.metallic = 1.0
	brass.roughness = 0.3
	_append(mesh, handle, FRONT_CENTER + Vector3(0.6, -0.1, -FRONT_SIZE.z * 0.5 - 0.03), brass)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.65, 0.13, 0.035)
	var neon := StandardMaterial3D.new()
	neon.albedo_color = Color(1, 0.12, 0.06)
	neon.emission_enabled = true
	neon.emission = Color(1, 0.08, 0.03)
	neon.emission_energy_multiplier = 1.6
	_append(mesh, stripe, Vector3(0, 1.56, -1.435), neon)
	# A short strap from his back carries the pouch, which hangs outside his body.
	var strap := BoxMesh.new()
	var reach := maxf(0.05, core_offset.z - 0.3)
	strap.size = Vector3(0.07, 0.07, reach)
	_append(mesh, strap, Vector3(core_offset.x, core_offset.y, 0.3 + reach * 0.5), frame)
	var core := SphereMesh.new()
	core.radius = core_radius
	core.height = core.radius * 1.6
	core.radial_segments = 12
	core.rings = 6
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1, 0.78, 0.2)
	gold.emission_enabled = true
	gold.emission = Color(1, 0.62, 0.1)
	gold.emission_energy_multiplier = 1.4
	_append(mesh, core, core_offset, gold)
	return mesh

static func _append(mesh: ArrayMesh, primitive: PrimitiveMesh, offset: Vector3, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(primitive, 0, Transform3D(Basis.IDENTITY, offset))
	surface.set_material(material)
	surface.commit(mesh)
