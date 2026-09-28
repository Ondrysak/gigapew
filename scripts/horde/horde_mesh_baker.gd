class_name HordeMeshBaker
extends RefCounted

## Flattens an enemy model scene into one mesh so thousands of instances draw
## in a few calls. Each distinct source material becomes one surface whose
## ShaderMaterial copies its colors and adds per-instance flash/telegraph/bob.

static func bake(definition: HordeEnemyDefinition, shader: Shader) -> ArrayMesh:
	var root := definition.model_scene.instantiate() as Node3D
	var tools: Dictionary = {}
	var order: Array[Material] = []
	_collect(root, Transform3D.IDENTITY, tools, order)
	root.free()
	var mesh := ArrayMesh.new()
	for source in order:
		var tool: SurfaceTool = tools[source]
		tool.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material_for(source, definition, shader))
	return mesh

static func _collect(node: Node, parent: Transform3D, tools: Dictionary, order: Array[Material]) -> void:
	var local := parent
	if node is Node3D:
		local = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var material := instance.material_override
			if material == null:
				material = instance.get_surface_override_material(surface)
			if material == null:
				material = instance.mesh.surface_get_material(surface)
			if not tools.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = tool
				order.append(material)
			(tools[material] as SurfaceTool).append_from(instance.mesh, surface, local)
	for child in node.get_children():
		_collect(child, local, tools, order)

static func _material_for(source: Material, definition: HordeEnemyDefinition, shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	var standard := source as StandardMaterial3D
	if standard != null:
		material.set_shader_parameter("albedo", standard.albedo_color)
		material.set_shader_parameter("roughness", standard.roughness)
		material.set_shader_parameter("metallic", standard.metallic)
		if standard.emission_enabled:
			material.set_shader_parameter("emission", standard.emission)
			material.set_shader_parameter("emission_energy", standard.emission_energy_multiplier)
		elif standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			# Unshaded accents (eyes, lights) stay bright under batched lighting.
			material.set_shader_parameter("emission", standard.albedo_color)
			material.set_shader_parameter("emission_energy", 1.0)
	material.set_shader_parameter("flash_color", definition.flash_color)
	material.set_shader_parameter("telegraph_color", definition.telegraph_color)
	material.set_shader_parameter("bob_amplitude", definition.bob_amplitude)
	material.set_shader_parameter("bob_speed", definition.bob_speed)
	# Bodies pressed against the camera vanish; larger bodies vanish sooner.
	# Capped so a boss (whose contact distance exceeds the cap) always stays visible.
	material.set_shader_parameter("near_cull", minf(definition.radius + 0.8, 1.6))
	return material
