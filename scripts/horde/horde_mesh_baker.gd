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

## A second, small native mesh containing only rest-selected head/limb triangles.
## UV2.x retains the VAT column; UV2.y encodes piece + 8*depth + 32*fork.
## Never clip against animated positions: a walking limb keeps the same triangles.
static func bake_anatomy(body: ArrayMesh, definition: HordeEnemyDefinition) -> ArrayMesh:
	var height := definition.height / maxf(definition.model_scale, 0.001)
	var weak := definition.weak_spot_offset
	var radius := maxf(definition.weak_spot_radius, height * 0.08)
	var upright := weak.y > height * 0.6 and absf(weak.z) < height * 0.3
	var bounds := body.get_aabb()
	var neck := minf(weak.y - radius * 1.4, height * 0.58)
	var front := weak.z + radius * 0.6
	var min_points: Array[Vector3] = []
	var max_points: Array[Vector3] = []
	var counts := PackedInt32Array()
	counts.resize(6)
	for piece in 6:
		min_points.append(Vector3(INF, INF, INF))
		max_points.append(Vector3(-INF, -INF, -INF))
	var selected: Array = []
	for surface in body.get_surface_count():
		var arrays := body.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for vertex in vertices.size():
				indices[vertex] = vertex
		var pieces: Array[PackedInt32Array] = []
		for piece in 6:
			pieces.append(PackedInt32Array())
		for triangle in range(0, indices.size(), 3):
			var a := indices[triangle]
			var b := indices[triangle + 1]
			var c := indices[triangle + 2]
			var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
			var head := center.y >= neck if upright else center.z <= front and center.y > height * 0.25
			var piece := -1
			if not head:
				var side := 0 if center.x < weak.x else 1
				if upright:
					if center.y < height * 0.36:
						piece = 4 + side
					elif absf(center.x - weak.x) > bounds.size.x * 0.23 and center.y < neck:
						piece = 2 + side
				elif center.y < height * 0.50 and absf(center.x - weak.x) > maxf(radius * 0.85, bounds.size.x * 0.18):
					piece = (2 if center.z < weak.z * 0.2 else 4) + side
			for target in range(0, 2) if head else range(piece, piece + 1):
				if target < 0:
					continue
				var subset := pieces[target]
				pieces[target] = PackedInt32Array()
				for index in [a, b, c]:
					subset.append(index)
					min_points[target] = min_points[target].min(vertices[index])
					max_points[target] = max_points[target].max(vertices[index])
					counts[target] += 1
				pieces[target] = subset
		selected.append(pieces)
	var mesh := ArrayMesh.new()
	var head_origin := (min_points[0] + max_points[0]) * 0.5 if counts[0] > 0 else weak
	var head_width := maxf(max_points[0].x - min_points[0].x, radius * 2.0) if counts[0] > 0 else radius * 2.0
	var head_radius := (max_points[0] - min_points[0]).length() * 0.5 if counts[0] > 0 else radius
	var pivots := PackedVector3Array()
	var tips := PackedVector3Array()
	for piece in range(2, 6):
		var low := min_points[piece]
		var high := max_points[piece]
		var middle := (low + high) * 0.5
		var left := piece % 2 == 0
		if counts[piece] == 0:
			pivots.append(weak)
			tips.append(weak)
		elif upright:
			pivots.append(Vector3(middle.x, high.y, middle.z))
			tips.append(Vector3(middle.x, low.y, middle.z))
		else:
			pivots.append(Vector3(high.x if left else low.x, high.y, middle.z))
			tips.append(Vector3(low.x if left else high.x, low.y, middle.z))
	var pivot_refs := PackedVector4Array()
	var tip_refs := PackedVector4Array()
	for piece in 6:
		var pivot := head_origin if piece < 2 else pivots[piece - 2]
		var tip := head_origin if piece < 2 else tips[piece - 2]
		pivot_refs.append(_anatomy_reference(body, selected, piece, pivot))
		tip_refs.append(_anatomy_reference(body, selected, piece, tip))
	for surface in body.get_surface_count():
		var arrays := body.surface_get_arrays(surface)
		var pieces: Array[PackedInt32Array] = selected[surface]
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := false
		for piece in 6:
			for depth in (4 if piece < 2 else 3):
				for fork in (1 if piece < 2 else 1 << depth):
					var encoded := float(piece + 1 + depth * 8 + fork * 32)
					for index in pieces[piece]:
						_append_anatomy_vertex(tool, arrays, index, encoded)
						emitted = true
		if not emitted:
			continue
		tool.commit(mesh)
		var material := body.surface_get_material(surface).duplicate() as ShaderMaterial
		material.set_shader_parameter("anatomy_enabled", true)
		material.set_shader_parameter("anatomy_upright", upright)
		material.set_shader_parameter("anatomy_head_origin", head_origin)
		material.set_shader_parameter("anatomy_head_width", head_width)
		material.set_shader_parameter("anatomy_head_radius", head_radius)
		material.set_shader_parameter("anatomy_pivot_refs", pivot_refs)
		material.set_shader_parameter("anatomy_tip_refs", tip_refs)
		var names := ["left_arm", "right_arm", "left_leg", "right_leg"]
		for piece in 4:
			material.set_shader_parameter("anatomy_" + names[piece], pivots[piece])
			material.set_shader_parameter("anatomy_" + names[piece] + "_tip", tips[piece])
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

static func _anatomy_reference(body: ArrayMesh, selected: Array, piece: int, joint: Vector3) -> Vector4:
	var nearest := INF
	var reference := Vector4(joint.x, joint.y, joint.z, 0.0)
	for surface in body.get_surface_count():
		var arrays := body.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var pieces: Array[PackedInt32Array] = selected[surface]
		for index in pieces[piece]:
			var distance := vertices[index].distance_squared_to(joint)
			if distance < nearest:
				nearest = distance
				var vertex := vertices[index]
				reference = Vector4(vertex.x, vertex.y, vertex.z, uv2s[index].x if not uv2s.is_empty() else 0.0)
	return reference

static func _append_anatomy_vertex(tool: SurfaceTool, arrays: Array, index: int, piece: float) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	if not normals.is_empty():
		tool.set_normal(normals[index])
	if not tangents.is_empty():
		var at := index * 4
		tool.set_tangent(Plane(Vector3(tangents[at], tangents[at + 1], tangents[at + 2]), tangents[at + 3]))
	tool.set_uv(uvs[index] if not uvs.is_empty() else Vector2.ZERO)
	tool.set_uv2(Vector2(uv2s[index].x if not uv2s.is_empty() else 0.0, piece))
	tool.set_color(Color.WHITE)
	tool.add_vertex(vertices[index])

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
	material.set_shader_parameter("fusion_body_height", definition.height / maxf(definition.model_scale, 0.001))
	material.set_shader_parameter("fusion_weak_spot", Vector4(definition.weak_spot_offset.x, definition.weak_spot_offset.y, definition.weak_spot_offset.z, definition.weak_spot_radius))
	# Bodies pressed against the camera vanish; larger bodies vanish sooner.
	# Capped so a boss (whose contact distance exceeds the cap) always stays visible.
	material.set_shader_parameter("near_cull", minf(definition.radius + 0.8, 1.6))
	# Textured surfaces (the face) carry their own dirt; flat clothes and skin get the shader's.
	var textured := standard != null and standard.albedo_texture != null
	material.set_shader_parameter("grime", definition.grime * (0.4 if textured else 1.0))
	if textured and definition.face_atlas != Vector2i.ONE:
		material.set_shader_parameter("face_atlas", Vector4(definition.face_atlas.x, definition.face_atlas.y, definition.face_first, definition.face_count))
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
