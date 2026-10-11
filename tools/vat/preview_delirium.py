"""Workbench contact sheet per delirium creature (build_delirium.py output).

	blender -b --python tools/vat/preview_delirium.py -- <blend_dir> <png_dir> [names...]

Rows: Walk (3/4 front), Walk (side), Attack (side), Death (3/4 front), Idle (3/4
front, if present). Four poses per row include attack windup/impact and death's
final pose. Cameras fit the entire action, not just its first frame; ground is
z=0. A JSON report records frame numbers and full-action floor diagnostics.
"""

import json
import os
import sys

import bpy
import numpy
from mathutils import Vector

TILE = 300
NAMES = ("mys", "svab", "lahev", "automat", "jackpot")
FRONT = Vector((0.75, -1.0, 0.45)).normalized()
SIDE = Vector((1.0, -0.12, 0.12)).normalized()


def rig_and_mesh():
	rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent == rig)
	return rig, mesh


def set_action(rig, action, frame):
	data = rig.animation_data
	data.action = action
	if hasattr(data, "action_slot") and len(action.slots) > 0:
		data.action_slot = action.slots[0]
	bpy.context.scene.frame_set(int(frame))


def bounds(mesh):
	depsgraph = bpy.context.evaluated_depsgraph_get()
	evaluated = mesh.evaluated_get(depsgraph)
	points = [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]
	low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
	high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
	return low, high


def setup(scene, size):
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.render.resolution_x = TILE
	scene.render.resolution_y = TILE
	scene.render.film_transparent = False
	scene.render.resolution_percentage = 100
	scene.render.image_settings.file_format = "PNG"
	scene.render.image_settings.color_mode = "RGBA"
	shading = scene.display.shading
	shading.light = "STUDIO"
	shading.color_type = "MATERIAL"
	shading.show_shadows = True
	shading.show_cavity = True
	world = bpy.data.worlds.new("preview")
	world.color = (0.32, 0.34, 0.38)
	scene.world = world
	ground = bpy.data.meshes.new("ground")
	r = size * 4.0
	ground.from_pydata([(-r, -r, 0), (r, -r, 0), (r, r, 0), (-r, r, 0)], [], [(0, 1, 2, 3)])
	mat = bpy.data.materials.new("ground")
	mat.diffuse_color = (0.55, 0.55, 0.52, 1.0)
	ground.materials.append(mat)
	scene.collection.objects.link(bpy.data.objects.new("ground", ground))
	cam_data = bpy.data.cameras.new("cam")
	cam_data.type = "ORTHO"
	cam = bpy.data.objects.new("cam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam
	return cam


def aim(cam, target, direction, scale):
	cam.data.ortho_scale = scale
	cam.data.clip_end = scale * 50.0
	cam.location = target + direction * scale * 10.0
	cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()


def action_bounds(rig, mesh, action):
	start, end = (int(f) for f in action.frame_range)
	lows, highs = [], []
	for frame in range(start, end + 1):
		set_action(rig, action, frame)
		low, high = bounds(mesh)
		lows.append(low)
		highs.append(high)
	low = Vector(tuple(min(v[i] for v in lows) for i in range(3)))
	high = Vector(tuple(max(v[i] for v in highs) for i in range(3)))
	worst = min(range(len(lows)), key=lambda i: lows[i].z)
	return low, high, {"lowest_z": lows[worst].z, "lowest_frame": start + worst,
		"bounds": [list(low), list(high)]}


def fit_camera(cam, low, high, direction):
	target = (low + high) * 0.5
	right = direction.cross(Vector((0.0, 0.0, 1.0))).normalized()
	up = right.cross(direction).normalized()
	size = high - low
	width = sum(abs(right[i]) * size[i] for i in range(3))
	height = sum(abs(up[i]) * size[i] for i in range(3))
	aim(cam, target, direction, max(width, height) * 1.18)


def render_tile(path):
	bpy.context.scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	image = bpy.data.images.load(path)
	pixels = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(TILE, TILE, 4)
	bpy.data.images.remove(image)
	os.remove(path)
	return pixels


def preview(name, blend_dir, png_dir):
	bpy.ops.wm.open_mainfile(filepath=os.path.join(blend_dir, name + ".blend"))
	scene = bpy.context.scene
	rig, mesh = rig_and_mesh()
	actions = bpy.data.actions
	rows = [
		("Walk", FRONT, (0.0, 0.25, 0.5, 0.75)),
		("Walk", SIDE, (0.0, 0.25, 0.5, 0.75)),
		("Attack", SIDE, (0.0, 0.3, 0.5, 1.0)),
		("Death", FRONT, (0.0, 0.35, 0.7, 1.0)),
	]
	if "Idle" in actions:
		rows.append(("Idle", FRONT, (0.0, 0.25, 0.5, 0.75)))
	extents = {}
	report = {"actions": {}, "rows": []}
	for action_name, _, _ in rows:
		if action_name not in extents:
			low, high, contact = action_bounds(rig, mesh, actions[action_name])
			extents[action_name] = (low, high)
			report["actions"][action_name] = contact
	size = max(max(high - low) for low, high in extents.values())
	cam = setup(scene, size)
	sheet = numpy.zeros((TILE * len(rows), TILE * 4, 4), dtype=numpy.float32)
	tmp = os.path.join(png_dir, name + "_tile.png")
	for row, (action_name, direction, fractions) in enumerate(rows):
		action = actions[action_name]
		start, end = action.frame_range
		fit_camera(cam, *extents[action_name], direction)
		frames = [round(start + (end - start) * fraction) for fraction in fractions]
		report["rows"].append({"action": action_name, "view": "side" if direction == SIDE else "front", "frames": frames})
		for col, frame in enumerate(frames):
			set_action(rig, action, frame)
			y = (len(rows) - 1 - row) * TILE
			sheet[y:y + TILE, col * TILE:(col + 1) * TILE] = render_tile(tmp)
	print("full-action floor diagnostics:", name, report["actions"])
	image = bpy.data.images.new(name + "_sheet", TILE * 4, TILE * len(rows), alpha=True)
	image.pixels.foreach_set(sheet.ravel())
	image.filepath_raw = os.path.join(png_dir, name + ".png")
	image.file_format = "PNG"
	image.save()
	print("preview:", image.filepath_raw, "rows:", [r[0] for r in rows])
	with open(os.path.join(png_dir, name + ".json"), "w", encoding="utf-8") as handle:
		json.dump(report, handle, indent=2)


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	blend_dir, png_dir = os.path.abspath(argv[0]), os.path.abspath(argv[1])
	os.makedirs(png_dir, exist_ok=True)
	for name in argv[2:] or NAMES:
		preview(name, blend_dir, png_dir)


main()
