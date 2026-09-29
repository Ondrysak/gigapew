class_name HordeMeshBaker
extends RefCounted

## Flattens an enemy model scene into one mesh so thousands of instances draw
## in a few calls. Each distinct source material becomes one surface whose
## ShaderMaterial copies its colours/textures and adds per-instance
## flash/telegraph/frost/bob. Definitions with a vertex_animation use the VAT
## shader, which reads the baked clips through the mesh's UV2 and per-instance COLOR.

static func bake(definition: HordeEnemyDefinition, static_shader: Shader, animated_shader: Shader) -> ArrayMesh:
	var animated := definition.vertex_animation != null
	var root := definition.model_scene.instantiate() as Node3D
	var tools: Dictionary = {}
	var order: Array[Material] = []
	_collect(root, Transform3D.IDENTITY, tools, order)
	root.free()
	var mesh := ArrayMesh.new()
	for source in order:
		var tool: SurfaceTool = tools[source]
		if animated:
			# The VAT shader reads animation state from COLOR, which is the vertex
			# colour times the instance colour: force the vertex colour to white.
			var arrays := tool.commit_to_arrays()
			var colors := PackedColorArray()
			colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			colors.fill(Color.WHITE)
			arrays[Mesh.ARRAY_COLOR] = colors
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		else:
			tool.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material_for(source, definition, animated_shader if animated else static_shader))
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
	var standard := source as BaseMaterial3D
	if standard != null:
		material.set_shader_parameter("albedo", standard.albedo_color)
		material.set_shader_parameter("roughness", standard.roughness)
		material.set_shader_parameter("metallic", standard.metallic)
		if standard.albedo_texture != null:
			material.set_shader_parameter("albedo_texture", standard.albedo_texture)
		if standard.normal_enabled and standard.normal_texture != null:
			material.set_shader_parameter("use_normal_texture", true)
			material.set_shader_parameter("normal_texture", standard.normal_texture)
			material.set_shader_parameter("normal_scale", standard.normal_scale)
		# glTF imports share one ORM texture between roughness and metallic.
		var packed := standard.roughness_texture if standard.roughness_texture != null else standard.metallic_texture
		if packed != null:
			material.set_shader_parameter("orm_texture", packed)
			if standard.roughness_texture != null:
				material.set_shader_parameter("roughness_channel", _channel(standard.roughness_texture_channel))
			if standard.metallic_texture != null:
				material.set_shader_parameter("metallic_channel", _channel(standard.metallic_texture_channel))
		if standard.emission_enabled:
			material.set_shader_parameter("emission", standard.emission)
			material.set_shader_parameter("emission_energy", standard.emission_energy_multiplier)
		elif standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			# A flat white emission washes out textured Quaternius mechs.
			# Light their painted surface with a restrained textured glow.
			if standard.albedo_texture != null:
				material.set_shader_parameter("unshaded_texture_energy", 0.35)
			else:
				material.set_shader_parameter("emission", standard.albedo_color)
				material.set_shader_parameter("emission_energy", 1.0)
	material.set_shader_parameter("tint", definition.tint)
	material.set_shader_parameter("rim_color", definition.rim_color)
	material.set_shader_parameter("flash_color", definition.flash_color)
	material.set_shader_parameter("telegraph_color", definition.telegraph_color)
	material.set_shader_parameter("bob_amplitude", definition.bob_amplitude)
	material.set_shader_parameter("bob_speed", definition.bob_speed)
	# Bodies pressed against the camera vanish; larger bodies vanish sooner.
	# Capped so a boss (whose contact distance exceeds the cap) always stays visible.
	material.set_shader_parameter("near_cull", minf(definition.radius + 0.8, 1.6))
	var animation := definition.vertex_animation
	if animation != null:
		material.set_shader_parameter("vat_positions", animation.positions)
		material.set_shader_parameter("vat_normals", animation.normals)
		material.set_shader_parameter("vat_vertex_count", animation.vertex_count)
		material.set_shader_parameter("sway_amplitude", definition.sway_amplitude)
	return material

static func _channel(channel: BaseMaterial3D.TextureChannel) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1.0, 0.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
	return Vector4(1.0, 1.0, 1.0, 0.0) / 3.0
