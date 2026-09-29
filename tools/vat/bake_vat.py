"""Bake one rigged monster into a Vertex Animation Texture set for the horde.

Run headless through Blender (tested with Blender 5.2):

	blender -b -P tools/vat/bake_vat.py -- <monster_id> [--config tools/vat/monsters.json]

Outputs go to assets/monsters/<id>/ (see tools/vat/README.md for the format):
	<id>.glb             rest mesh (move clip frame 0) with materials/textures;
	                     UV2 (TEXCOORD_1).x = (column + 0.5) / vertex_count
	<id>_positions.exr   RGBA float32, Godot-space positions per column/frame
	<id>_normals.exr     RGBA float32, Godot-space normals per column/frame
	<id>_vat.tres        HordeVertexAnimation resource (clips, counts, textures)
"""

import bpy
import json
import math
import os
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, "..", ".."))
MAX_WIDTH = 4096
DEFAULT_FPS = 20.0


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	if not argv:
		raise SystemExit("usage: blender -b -P bake_vat.py -- <monster_id> [--config path]")
	config_path = os.path.join(HERE, "monsters.json")
	if "--config" in argv:
		config_path = argv[argv.index("--config") + 1]
	return argv[0], config_path


def load_config(path):
	with open(path, "r", encoding="utf-8") as handle:
		return json.load(handle)


def import_source(path):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	if path.lower().endswith(".fbx"):
		bpy.ops.import_scene.fbx(filepath=path)
	else:
		bpy.ops.import_scene.gltf(filepath=path)


def find_rig():
	rigs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
	if len(rigs) != 1:
		raise RuntimeError("expected exactly one armature, found %d" % len(rigs))
	return rigs[0]


def skinned_meshes(rig):
	meshes = []
	for obj in bpy.data.objects:
		if obj.type != "MESH":
			continue
		uses_rig = any(m.type == "ARMATURE" and m.object == rig for m in obj.modifiers)
		if uses_rig:
			meshes.append(obj)
	if not meshes:
		raise RuntimeError("no mesh is deformed by the armature")
	return meshes


def select_only(objects, active):
	for obj in bpy.context.view_layer.objects:
		obj.select_set(False)
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = active


def decimate(obj, ratio):
	"""Collapse-decimate the rest mesh; the modifier runs before the armature
	and interpolates vertex-group weights, so skinning survives."""
	if ratio >= 0.999:
		return
	select_only([obj], obj)
	modifier = obj.modifiers.new("VATDecimate", "DECIMATE")
	modifier.decimate_type = "COLLAPSE"
	modifier.ratio = ratio
	modifier.use_collapse_triangulate = True
	with bpy.context.temp_override(object=obj, active_object=obj):
		bpy.ops.object.modifier_move_to_index(modifier=modifier.name, index=0)
		bpy.ops.object.modifier_apply(modifier=modifier.name)


def join(meshes):
	if len(meshes) == 1:
		return meshes[0]
	active = meshes[0]
	select_only(meshes, active)
	with bpy.context.temp_override(active_object=active, object=active, selected_editable_objects=meshes, selected_objects=meshes):
		bpy.ops.object.join()
	return active


def prepare_uvs(mesh):
	"""Keep exactly one texture UV layer (created if missing) and add the VAT layer second."""
	while len(mesh.uv_layers) > 1:
		mesh.uv_layers.remove(mesh.uv_layers[-1])
	if len(mesh.uv_layers) == 0:
		mesh.uv_layers.new(name="UVMap")
	mesh.uv_layers.active_index = 0
	return mesh.uv_layers.new(name="VAT")


def build_columns(mesh):
	"""One column per (vertex, rest split normal). Returns per-loop column ids and a
	representative loop per column so flat-shaded corners keep their own normals."""
	loop_vert = [0] * len(mesh.loops)
	mesh.loops.foreach_get("vertex_index", loop_vert)
	normals = [0.0] * (len(mesh.loops) * 3)
	mesh.corner_normals.foreach_get("vector", normals)
	keys = {}
	loop_column = [0] * len(mesh.loops)
	column_loop = []
	column_vertex = []
	for loop in range(len(mesh.loops)):
		n = normals[loop * 3:loop * 3 + 3]
		key = (loop_vert[loop], round(n[0], 3), round(n[1], 3), round(n[2], 3))
		column = keys.get(key)
		if column is None:
			column = len(column_loop)
			keys[key] = column
			column_loop.append(loop)
			column_vertex.append(loop_vert[loop])
		loop_column[loop] = column
	return loop_column, column_loop, column_vertex


def set_pose(rig, action, frame):
	data = rig.animation_data or rig.animation_data_create()
	data.action = action
	if hasattr(data, "action_slot") and len(action.slots) > 0:
		data.action_slot = action.slots[0]
	scene = bpy.context.scene
	whole = math.floor(frame)
	scene.frame_set(int(whole), subframe=float(frame - whole))


def evaluated_arrays(obj, column_loop, column_vertex):
	"""World-space positions and normals per column for the current frame."""
	depsgraph = bpy.context.evaluated_depsgraph_get()
	evaluated = obj.evaluated_get(depsgraph)
	mesh = evaluated.to_mesh()
	coords = [0.0] * (len(mesh.vertices) * 3)
	mesh.vertices.foreach_get("co", coords)
	normals = [0.0] * (len(mesh.loops) * 3)
	mesh.corner_normals.foreach_get("vector", normals)
	world = evaluated.matrix_world.copy()
	evaluated.to_mesh_clear()
	rotation = world.to_3x3().inverted_safe().transposed()
	positions = []
	out_normals = []
	for column in range(len(column_loop)):
		v = column_vertex[column]
		positions.append(world @ Vector(coords[v * 3:v * 3 + 3]))
		l = column_loop[column]
		out_normals.append((rotation @ Vector(normals[l * 3:l * 3 + 3])).normalized())
	return positions, out_normals


def resolve_action(name):
	if name in bpy.data.actions:
		return bpy.data.actions[name]
	for action in bpy.data.actions:
		# FBX imports name actions "Armature|Armature|Clip".
		if action.name.split("|")[-1] == name:
			return action
	raise RuntimeError("action %r not found; available: %s" % (name, [a.name for a in bpy.data.actions]))


def clip_samples(action, loop, fps):
	start, end = action.frame_range
	scene_fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
	seconds = max((end - start) / scene_fps, 1.0 / fps)
	if loop:
		count = max(1, round(seconds * fps))
		frames = [start + (end - start) * k / count for k in range(count)]
		rate = count / seconds
	else:
		count = max(2, round(seconds * fps) + 1)
		frames = [start + (end - start) * k / (count - 1) for k in range(count)]
		rate = (count - 1) / seconds
	return frames, rate


def normalisation(positions, spec):
	"""Matrix mapping Blender world space to normalised Blender space: yaw so the
	model faces +Y (Godot -Z), feet at z=0 (+lift), fitted size, centred XY."""
	yaw = Matrix.Rotation(math.radians(spec.get("yaw", 180.0)), 4, "Z")
	turned = [yaw @ p for p in positions]
	low = Vector((min(p.x for p in turned), min(p.y for p in turned), min(p.z for p in turned)))
	high = Vector((max(p.x for p in turned), max(p.y for p in turned), max(p.z for p in turned)))
	size = high - low
	fit = spec.get("fit", "height")
	if fit == "height":
		scale = spec["size"] / max(size.z, 1e-6)
	elif fit == "footprint":
		scale = spec["size"] / max(size.x, size.y, 1e-6)
	else:
		raise RuntimeError("unknown fit %r" % fit)
	center = Vector(((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, low.z))
	offset = Matrix.Translation(Vector((0.0, 0.0, spec.get("lift", 0.0))))
	return offset @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center) @ yaw


def to_godot(v):
	# Blender Z-up (+Y forward) -> glTF/Godot Y-up (-Z forward).
	return (v.x, v.z, -v.y)


def write_exr(path, width, height, pixels):
	image = bpy.data.images.new(os.path.basename(path), width=width, height=height, alpha=True, float_buffer=True)
	image.colorspace_settings.name = "Non-Color"
	image.pixels.foreach_set(pixels)
	image.filepath_raw = path
	image.file_format = "OPEN_EXR"
	image.save()
	bpy.data.images.remove(image)


def apply_materials(mesh, spec):
	overrides = spec.get("materials", {})
	for material in mesh.materials:
		if material is None or material.name not in overrides:
			continue
		override = overrides[material.name]
		material.use_nodes = True
		bsdf = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
		if bsdf is None:
			continue
		if "color" in override:
			socket = bsdf.inputs["Base Color"]
			for link in list(socket.links):
				material.node_tree.links.remove(link)
			socket.default_value = (*override["color"], 1.0)
		if "emission" in override:
			bsdf.inputs["Emission Color"].default_value = (*override["emission"], 1.0)
			bsdf.inputs["Emission Strength"].default_value = override.get("emission_strength", 1.0)


def downscale_textures(max_size):
	for image in bpy.data.images:
		if image.size[0] > max_size or image.size[1] > max_size:
			factor = max_size / max(image.size[0], image.size[1])
			image.scale(max(1, int(image.size[0] * factor)), max(1, int(image.size[1] * factor)))


def export_rest_mesh(obj, rig, clip_action, clip_frame, matrix, loop_column, column_count, path):
	set_pose(rig, clip_action, clip_frame)
	depsgraph = bpy.context.evaluated_depsgraph_get()
	evaluated = obj.evaluated_get(depsgraph)
	mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
	mesh.transform(matrix @ obj.matrix_world)
	vat = mesh.uv_layers["VAT"]
	uvs = [0.0] * (len(mesh.loops) * 2)
	for loop in range(len(mesh.loops)):
		uvs[loop * 2] = (loop_column[loop] + 0.5) / column_count
		uvs[loop * 2 + 1] = 0.5
	vat.data.foreach_set("uv", uvs)
	rest = bpy.data.objects.new(os.path.splitext(os.path.basename(path))[0], mesh)
	bpy.context.scene.collection.objects.link(rest)
	select_only([rest], rest)
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format="GLB",
		use_selection=True,
		export_yup=True,
		export_apply=False,
		export_texcoords=True,
		export_normals=True,
		export_tangents=False,
		export_materials="EXPORT",
		export_animations=False,
		export_skins=False,
		export_morph=False,
	)
	return len(mesh.vertices)


def write_import_files(out_dir, monster_id):
	texture_params = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=0
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""
	for suffix in ("positions", "normals"):
		path = os.path.join(out_dir, "%s_%s.exr.import" % (monster_id, suffix))
		if not os.path.exists(path):
			with open(path, "w", encoding="utf-8") as handle:
				handle.write(texture_params)
	scene_import = os.path.join(out_dir, "%s.glb.import" % monster_id)
	if not os.path.exists(scene_import):
		with open(scene_import, "w", encoding="utf-8") as handle:
			handle.write("""[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/force_disable_compression=true
skins/use_named_skins=true
animation/import=false
import_script/path=""
gltf/naming_version=1
gltf/embedded_image_handling=1
""")


def write_resource(out_dir, monster_id, column_count, clips):
	res_dir = "res://" + os.path.relpath(out_dir, PROJECT).replace(os.sep, "/")
	lines = [
		'[gd_resource type="Resource" script_class="HordeVertexAnimation" load_steps=%d format=3]' % (4 + len(clips)),
		"",
		'[ext_resource type="Script" path="res://scripts/data/horde_vertex_animation.gd" id="1_vat"]',
		'[ext_resource type="Script" path="res://scripts/data/horde_vertex_animation_clip.gd" id="2_clip"]',
		'[ext_resource type="Texture2D" path="%s/%s_positions.exr" id="3_positions"]' % (res_dir, monster_id),
		'[ext_resource type="Texture2D" path="%s/%s_normals.exr" id="4_normals"]' % (res_dir, monster_id),
		"",
	]
	for index, clip in enumerate(clips):
		lines += [
			'[sub_resource type="Resource" id="Clip_%d"]' % index,
			'script = ExtResource("2_clip")',
			'name = &"%s"' % clip["name"],
			"start_frame = %d" % clip["start"],
			"frame_count = %d" % clip["frames"],
			"fps = %s" % repr(round(clip["fps"], 4)),
			"loop = %s" % ("true" if clip["loop"] else "false"),
			"",
		]
	lines += [
		"[resource]",
		'script = ExtResource("1_vat")',
		'positions = ExtResource("3_positions")',
		'normals = ExtResource("4_normals")',
		"vertex_count = %d" % column_count,
		"clips = Array[ExtResource(\"2_clip\")]([%s])" % ", ".join('SubResource("Clip_%d")' % i for i in range(len(clips))),
		"",
	]
	with open(os.path.join(out_dir, "%s_vat.tres" % monster_id), "w", encoding="utf-8") as handle:
		handle.write("\n".join(lines))


def bake(monster_id, config):
	spec = config["monsters"][monster_id]
	downloads = os.path.expanduser(os.environ.get("KAKABOOMBOOM_DOWNLOADS", config["downloads"]))
	if not os.path.isabs(downloads):
		downloads = os.path.join(PROJECT, downloads)
	import_source(os.path.join(downloads, spec["source"]))
	rig = find_rig()
	if rig.animation_data is not None:
		for track in list(rig.animation_data.nla_tracks):
			rig.animation_data.nla_tracks.remove(track)
	meshes = skinned_meshes(rig)
	for obj in meshes:
		decimate(obj, spec.get("decimate", 1.0))
		if spec.get("smooth", False):
			# FBX commonly marks every triangle edge sharp. Merely toggling
			# face smoothing leaves those edge flags intact.
			sharp = obj.data.attributes.get("sharp_edge")
			if sharp is not None:
				sharp.data.foreach_set("value", [False] * len(sharp.data))
			custom = obj.data.attributes.get("custom_normal")
			if custom is not None:
				obj.data.attributes.remove(custom)
			for face in obj.data.polygons:
				face.use_smooth = True
			obj.data.update()
	obj = join(meshes)
	mesh = obj.data
	apply_materials(mesh, spec)
	downscale_textures(config.get("max_texture_size", 1024))
	prepare_uvs(mesh)
	loop_column, column_loop, column_vertex = build_columns(mesh)
	column_count = len(column_loop)
	fps = spec.get("fps", config.get("fps", DEFAULT_FPS))

	clips = spec["clips"]
	move = clips[0]
	move_action = resolve_action(move["action"])
	set_pose(rig, move_action, move_action.frame_range[0])
	rest_positions, _ = evaluated_arrays(obj, column_loop, column_vertex)
	matrix = normalisation(rest_positions, spec)
	normal_matrix = matrix.to_3x3().inverted_safe().transposed()

	width = min(column_count, MAX_WIDTH)
	rows = (column_count + width - 1) // width
	position_rows = []
	normal_rows = []
	baked = []
	start = 0
	for clip in clips:
		action = resolve_action(clip["action"])
		loop = clip.get("loop", True)
		frames, rate = clip_samples(action, loop, fps)
		for frame in frames:
			set_pose(rig, action, frame)
			positions, normals = evaluated_arrays(obj, column_loop, column_vertex)
			pos_row = [0.0] * (width * rows * 4)
			nrm_row = [0.0] * (width * rows * 4)
			for column in range(column_count):
				p = to_godot(matrix @ positions[column])
				n = to_godot((normal_matrix @ normals[column]).normalized())
				k = column * 4
				pos_row[k:k + 4] = (p[0], p[1], p[2], 1.0)
				nrm_row[k:k + 4] = (n[0], n[1], n[2], 1.0)
			position_rows.append(pos_row)
			normal_rows.append(nrm_row)
		baked.append({"name": clip["name"], "action": action.name, "start": start, "frames": len(frames), "fps": rate, "loop": loop})
		start += len(frames)

	height = start * rows
	if height > 16384:
		raise RuntimeError("VAT too tall (%d rows)" % height)
	out_dir = os.path.join(PROJECT, config.get("output", "assets/monsters"), monster_id)
	os.makedirs(out_dir, exist_ok=True)
	# Blender images are bottom-up; flip frames AND within-frame rows.
	# Wrapped columns must live at frame * rows + column // width in Godot.
	position_pixels = []
	normal_pixels = []
	row_size = width * 4
	for frame in reversed(range(start)):
		for row in reversed(range(rows)):
			span = slice(row * row_size, (row + 1) * row_size)
			position_pixels.extend(position_rows[frame][span])
			normal_pixels.extend(normal_rows[frame][span])
	write_exr(os.path.join(out_dir, "%s_positions.exr" % monster_id), width, height, position_pixels)
	write_exr(os.path.join(out_dir, "%s_normals.exr" % monster_id), width, height, normal_pixels)
	gpu_vertices = export_rest_mesh(obj, rig, move_action, move_action.frame_range[0], matrix, loop_column, column_count, os.path.join(out_dir, "%s.glb" % monster_id))
	write_import_files(out_dir, monster_id)
	write_resource(out_dir, monster_id, column_count, baked)
	report = {
		"id": monster_id,
		"source_vertices": len(mesh.vertices),
		"columns": column_count,
		"texture": [width, height],
		"clips": baked,
		"materials": [m.name for m in mesh.materials if m is not None],
		"textures": {image.name: list(image.size) for image in bpy.data.images if image.size[0] > 0},
		"rest_vertices": gpu_vertices,
	}
	reports = os.path.join(HERE, "reports")
	os.makedirs(reports, exist_ok=True)
	with open(os.path.join(reports, "%s.json" % monster_id), "w", encoding="utf-8") as handle:
		json.dump(report, handle, indent=1)
	print("VAT_REPORT " + json.dumps(report))


if __name__ == "__main__":
	monster, config_file = parse_args()
	bake(monster, load_config(config_file))
