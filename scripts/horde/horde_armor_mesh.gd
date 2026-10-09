class_name HordeArmorMesh
extends RefCounted

const FRONT_CENTER := Vector3(0, 1.15, -1.3)
const FRONT_SIZE := Vector3(1.8, 1.35, 0.24)

## Static, non-VAT overlay: one shared mesh and one fixed-capacity MultiMesh per
## plated type. Core coordinates are exactly the definition's precision sphere.
static func bake(core_offset: Vector3, core_radius: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var plate := BoxMesh.new()
	plate.size = FRONT_SIZE
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.3, 0.23, 0.07)
	steel.metallic = 0.7
	steel.roughness = 0.45
	_append(mesh, plate, FRONT_CENTER, steel)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.65, 0.13, 0.035)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(1, 0.65, 0.04)
	amber.emission_enabled = true
	amber.emission = Color(1, 0.45, 0.01)
	amber.emission_energy_multiplier = 0.8
	_append(mesh, stripe, Vector3(0, 1.56, -1.435), amber)
	var bezel := BoxMesh.new()
	bezel.size = Vector3(core_radius * 2.6, core_radius * 2.6, 0.12)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.035, 0.05, 0.05)
	_append(mesh, bezel, core_offset - Vector3(0, 0, 0.18), dark)
	var core := SphereMesh.new()
	core.radius = core_radius
	core.height = core.radius * 2.0
	core.radial_segments = 12
	core.rings = 6
	var teal := StandardMaterial3D.new()
	teal.albedo_color = Color(0.12, 1, 0.78)
	teal.emission_enabled = true
	teal.emission = Color(0.05, 1, 0.6)
	teal.emission_energy_multiplier = 2.0
	_append(mesh, core, core_offset, teal)
	return mesh

static func _append(mesh: ArrayMesh, primitive: PrimitiveMesh, offset: Vector3, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(primitive, 0, Transform3D(Basis.IDENTITY, offset))
	surface.set_material(material)
	surface.commit(mesh)
