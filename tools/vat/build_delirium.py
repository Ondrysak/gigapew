"""Procedural, rigged and animated low-poly sources for the five "pure delirium"
enemies of the Hlavák sector (LUĎAS: LAST TIME KRATOS).

	blender -b --python tools/vat/build_delirium.py -- [out_dir]

Writes <out_dir>/<name>.blend for mys, svab, lahev, automat and jackpot. Each file
holds one armature, one skinned mesh (rigid parts are weight-1 to a single bone,
tails/antennae/bottle neck blend), Principled-BSDF materials without textures and
bone-only actions Walk (loop), Idle (loop), Attack and Death (one-shot) at 24 fps.
Units are metres, Z up, feet on z=0, facing -Y. bake_vat.py consumes the files
directly; see tools/vat/README.md.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

FPS = 24
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUT = os.path.join(PROJECT, "..", "kakaboomboom-downloads", "delirium")
# Creature faces -Y, so its right side is -X.
SIDES = (("_R", -1.0), ("_L", 1.0))
TAU = 2.0 * math.pi


# ---------------------------------------------------------------- utilities

def ease(w):
	w = min(1.0, max(0.0, w))
	return w * w * (3.0 - 2.0 * w)


def clamp01(w):
	return min(1.0, max(0.0, w))


def material(name, color, roughness=0.6, metallic=0.0, emission=None, strength=0.0):
	mat = bpy.data.materials.new(name)
	if mat.node_tree is None:
		mat.use_nodes = True
	tree = mat.node_tree
	tree.nodes.clear()
	out = tree.nodes.new("ShaderNodeOutputMaterial")
	bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.location = (-300, 0)
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Metallic"].default_value = metallic
	if emission is not None:
		bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
		bsdf.inputs["Emission Strength"].default_value = strength
	tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
	# Solid viewport/Workbench colour (glows read brighter there).
	shown = emission if emission is not None else color
	mat.diffuse_color = (*shown, 1.0)
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


def chain(axis, controls):
	"""Linear weight blend along a chain: controls = [(s, bone), ...] sorted by s."""
	def weights(co):
		s = axis(co)
		if s <= controls[0][0]:
			return [(controls[0][1], 1.0)]
		for (s0, b0), (s1, b1) in zip(controls, controls[1:]):
			if s <= s1:
				w = (s - s0) / (s1 - s0)
				return [(b0, 1.0 - w), (b1, w)]
		return [(controls[-1][1], 1.0)]
	return weights


def rot_matrix(rot):
	return Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()


class Skin:
	"""Accumulates primitives into one bmesh with per-vertex bone weights."""

	def __init__(self):
		self.bm = bmesh.new()
		self.dl = self.bm.verts.layers.deform.verify()
		self.groups = {}
		self.mats = []

	def _group(self, bone):
		if bone not in self.groups:
			self.groups[bone] = len(self.groups)
		return self.groups[bone]

	def _finish(self, verts, mat, bone, smooth):
		if mat not in self.mats:
			self.mats.append(mat)
		index = self.mats.index(mat)
		for face in {f for v in verts for f in v.link_faces}:
			face.material_index = index
			face.smooth = smooth
		for v in verts:
			weights = bone(v.co) if callable(bone) else [(bone, 1.0)]
			for name, w in weights:
				if w > 1e-4:
					v[self.dl][self._group(name)] = w

	def box(self, mat, bone, center, size, rot=(0, 0, 0)):
		m = Matrix.Translation(center) @ rot_matrix(rot) @ Matrix.Diagonal(Vector((*size, 1.0)))
		verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
		self._finish(verts, mat, bone, False)

	def ball(self, mat, bone, center, radii, rot=(0, 0, 0), u=10, v=6, smooth=True):
		if isinstance(radii, (int, float)):
			radii = (radii, radii, radii)
		m = Matrix.Translation(center) @ rot_matrix(rot) @ Matrix.Diagonal(Vector((*radii, 1.0)))
		verts = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=m)["verts"]
		self._finish(verts, mat, bone, smooth)

	def tube(self, mat, bone, p0, p1, r0, r1=None, segs=8, smooth=True, squash=1.0):
		"""Cone/cylinder from p0 (radius r0) to p1 (radius r1); squash scales the
		cross-section's second axis (flattened symbols)."""
		p0, p1 = Vector(p0), Vector(p1)
		d = p1 - p0
		q = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
		m = Matrix.Translation((p0 + p1) * 0.5) @ q.to_matrix().to_4x4() @ Matrix.Diagonal(Vector((1.0, squash, 1.0, 1.0)))
		verts = bmesh.ops.create_cone(
			self.bm, cap_ends=True, cap_tris=False, segments=segs,
			radius1=r0, radius2=r0 if r1 is None else r1, depth=d.length, matrix=m)["verts"]
		self._finish(verts, mat, bone, smooth)

	def loft(self, mat, bone, points, radii, segs=10, smooth=True, caps=True):
		"""Tube through points with per-ring radii (closed with n-gon caps)."""
		pts = [Vector(p) for p in points]
		n = len(pts)
		rings = []
		for i, p in enumerate(pts):
			t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
			ref = Vector((0.0, 0.0, 1.0)) if abs(t.z) < 0.9 else Vector((1.0, 0.0, 0.0))
			a = (ref - t * ref.dot(t)).normalized()
			b = t.cross(a)
			rings.append([
				self.bm.verts.new(p + radii[i] * (math.cos(TAU * k / segs) * a + math.sin(TAU * k / segs) * b))
				for k in range(segs)])
		for r0, r1 in zip(rings, rings[1:]):
			for k in range(segs):
				k1 = (k + 1) % segs
				self.bm.faces.new((r0[k], r0[k1], r1[k1], r1[k]))
		if caps:
			self.bm.faces.new(list(reversed(rings[0])))
			self.bm.faces.new(rings[-1])
		self._finish([v for ring in rings for v in ring], mat, bone, smooth)

	def build(self, name, rig):
		mesh = bpy.data.meshes.new(name)
		self.bm.to_mesh(mesh)
		self.bm.free()
		for mat in self.mats:
			mesh.materials.append(mat)
		obj = bpy.data.objects.new(name, mesh)
		bpy.context.scene.collection.objects.link(obj)
		for bone, _ in sorted(self.groups.items(), key=lambda item: item[1]):
			obj.vertex_groups.new(name=bone)
		obj.parent = rig
		modifier = obj.modifiers.new("Armature", "ARMATURE")
		modifier.object = rig
		return obj


def build_rig(name, bones):
	arm = bpy.data.armatures.new(name + "_rig")
	arm.display_type = "STICK"
	rig = bpy.data.objects.new(name + "_rig", arm)
	bpy.context.scene.collection.objects.link(rig)
	bpy.context.view_layer.objects.active = rig
	rig.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	for bone, head, tail, parent in bones:
		eb = arm.edit_bones.new(bone)
		eb.head = head
		eb.tail = tail
		eb.roll = 0.0
		if parent:
			eb.parent = arm.edit_bones[parent]
	bpy.ops.object.mode_set(mode="OBJECT")
	for pb in rig.pose.bones:
		pb.rotation_mode = "QUATERNION"
	return rig


# ---------------------------------------------------------------- animation

def keyed(t, keys):
	"""Interpolate channel dicts between (time, channels[, 'lin']) keys.
	A channel missing from a key is at rest (zero)."""
	if t <= keys[0][0]:
		return dict(keys[0][1])
	for k0, k1 in zip(keys, keys[1:]):
		t0, c0 = k0[0], k0[1]
		t1, c1 = k1[0], k1[1]
		if t <= t1:
			w = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
			if not (len(k1) > 2 and k1[2] == "lin"):
				w = ease(w)
			out = {}
			for name in set(c0) | set(c1):
				a = c0.get(name)
				b = c1.get(name)
				if a is None:
					a = (0.0,) * len(b)
				if b is None:
					b = (0.0,) * len(a)
				out[name] = tuple(x + (y - x) * w for x, y in zip(a, b))
			return out
	return dict(keys[-1][1])


def leg_ik(hip, target, a, b):
	"""Planar 2-bone IK in the (y, z) plane, knee pointing forward (-Y).
	Angles are rotations about +X in degrees (positive swings the limb to +Y):
	returns (thigh, knee relative to thigh, shin world)."""
	dy = target[0] - hip[0]
	dz = target[1] - hip[1]
	dist = min(max(math.hypot(dy, dz), abs(a - b) + 1e-4), (a + b) * 0.9995)
	phi = math.atan2(dy, -dz)
	alpha = math.acos(max(-1.0, min(1.0, (a * a + dist * dist - b * b) / (2.0 * a * dist))))
	thigh = phi - alpha
	knee_y = hip[0] + a * math.sin(thigh)
	knee_z = hip[1] - a * math.cos(thigh)
	shin = math.atan2(target[0] - knee_y, -(target[1] - knee_z))
	return math.degrees(thigh), math.degrees(shin - thigh), math.degrees(shin)


class Biped:
	"""Two-bone legs thigh_S/shin_S/foot_S under a translating 'hips' bone.
	Channels '_fS' = (dy, dz, toe pitch) place each ankle relative to rest."""

	def __init__(self, hip_z, thigh, shin, ankle_z):
		self.hip_z = hip_z
		self.a = thigh
		self.b = shin
		self.ankle_z = ankle_z

	def solve(self, ch):
		hips = ch.get("hips.l", (0.0, 0.0, 0.0))
		for sfx, _ in SIDES:
			foot = ch.pop("_f" + sfx, (0.0, 0.0, 0.0))
			thigh, knee, shin = leg_ik(
				(hips[1], self.hip_z + hips[2]), (foot[0], self.ankle_z + foot[1]), self.a, self.b)
			ch["thigh" + sfx + ".r"] = (thigh, 0.0, 0.0)
			ch["shin" + sfx + ".r"] = (knee, 0.0, 0.0)
			ch["foot" + sfx + ".r"] = (-shin + foot[2], 0.0, 0.0)
		return ch

	def angles(self, hips_z, foot=(0.0, 0.0)):
		"""Direct leg channels for a hips drop with planted feet (for keyposes)."""
		thigh, knee, shin = leg_ik((0.0, self.hip_z + hips_z), (foot[0], self.ankle_z + foot[1]), self.a, self.b)
		ch = {}
		for sfx, _ in SIDES:
			ch["thigh" + sfx + ".r"] = (thigh, 0.0, 0.0)
			ch["shin" + sfx + ".r"] = (knee, 0.0, 0.0)
			ch["foot" + sfx + ".r"] = (-shin, 0.0, 0.0)
		return ch


def foot_path(u, stride, lift, duty):
	"""Ankle offset over one gait cycle: stance slides front->back on the ground,
	swing arcs forward. Returns (dy, dz, toe pitch)."""
	u %= 1.0
	if u < duty:
		return (-0.5 * stride + stride * u / duty, 0.0, 0.0)
	w = (u - duty) / (1.0 - duty)
	return (0.5 * stride - stride * ease(w), lift * math.sin(math.pi * w), -14.0 * math.sin(math.pi * w))


def biped_gait(t, stride, lift, crouch, bob, duty=0.62):
	"""Hips height and both ankle targets; R leads, L half a cycle later.
	The hips dip at each heel strike (t = 0 and 0.5)."""
	return {
		"hips.l": (0.0, 0.0, -crouch - bob * (0.5 + 0.5 * math.cos(2.0 * TAU * t))),
		"_f_R": foot_path(t, stride, lift, duty),
		"_f_L": foot_path(t + 0.5, stride, lift, duty),
	}


def write_action(rig, mesh, name, frames, fn, loop):
	"""Sample fn(t), t in [0, 1], on frames 1..frames+1 and key every bone.
	Rotations are authored as XYZ Euler degrees about armature-space rest axes
	('bone.r') and translations in armature-space rest axes ('bone.l')."""
	act = bpy.data.actions.new(name)
	act.use_fake_user = True
	data = rig.animation_data or rig.animation_data_create()
	data.action = act
	rest = {pb.name: pb.bone.matrix_local.to_3x3() for pb in rig.pose.bones}
	inverse = {n: m.inverted() for n, m in rest.items()}
	previous = {}
	for i in range(frames + 1):
		ch = fn(i / frames)
		for pb in rig.pose.bones:
			n = pb.name
			r = ch.get(n + ".r", (0.0, 0.0, 0.0))
			q = (inverse[n] @ rot_matrix(r).to_3x3() @ rest[n]).to_quaternion()
			if n in previous and previous[n].dot(q) < 0.0:
				q.negate()
			previous[n] = q
			pb.rotation_quaternion = q
			pb.location = inverse[n] @ Vector(ch.get(n + ".l", (0.0, 0.0, 0.0)))
			pb.scale = (1.0, 1.0, 1.0)
			for path in ("rotation_quaternion", "location", "scale"):
				pb.keyframe_insert(path, frame=i + 1, group=n)
	# Bake floor contact into the root bone, not an object transform or a runtime
	# constraint. Check the complete deformed silhouette, including toes and props,
	# so rotating limbs cannot tunnel through z=0 between authored keyposes.
	for frame in range(1, frames + 2):
		bpy.context.scene.frame_set(frame)
		evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
		floor = min((evaluated.matrix_world @ v.co).z for v in evaluated.data.vertices)
		if floor < 0.0:
			root = rig.pose.bones["root"]
			root.location += inverse["root"] @ Vector((0.0, 0.0, -floor))
			root.keyframe_insert("location", frame=frame, group="root")
	act.use_frame_range = True
	act.frame_start = 1
	act.frame_end = frames + 1
	act.use_cyclic = loop
	return act


# ---------------------------------------------------------------- mys

def build_mys():
	fur = material("mys_fur", (0.93, 0.93, 0.9), roughness=0.85)
	pink = material("mys_pink", (0.96, 0.55, 0.62), roughness=0.55)
	eye = material("mys_eye", (0.75, 0.02, 0.05), roughness=0.2, emission=(1.0, 0.06, 0.06), strength=1.5)
	whisker = material("mys_whisker", (0.72, 0.72, 0.72), roughness=0.5)

	bones = [
		("root", (0, 0, 0), (0, 0, 0.12), None),
		("body", (0, 0.2, 0.25), (0, -0.12, 0.27), "root"),
		("head", (0, -0.14, 0.27), (0, -0.42, 0.25), "body"),
		("tail1", (0, 0.34, 0.21), (0, 0.52, 0.14), "body"),
		("tail2", (0, 0.52, 0.14), (0, 0.7, 0.09), "tail1"),
		("tail3", (0, 0.7, 0.09), (0, 0.88, 0.09), "tail2"),
		("tail4", (0, 0.88, 0.09), (0, 1.06, 0.14), "tail3"),
	]
	legs = {}
	for sfx, sx in SIDES:
		legs["leg_F" + sfx] = ((sx * 0.1, -0.12, 0.21), (sx * 0.11, -0.15, 0.025))
		legs["leg_B" + sfx] = ((sx * 0.11, 0.17, 0.21), (sx * 0.12, 0.16, 0.025))
	for bone, (hip, foot) in legs.items():
		bones.append((bone, hip, foot, "body"))
	rig = build_rig("mys", bones)

	s = Skin()
	s.ball(fur, "body", (0, 0.05, 0.26), (0.17, 0.3, 0.17), u=12, v=8)
	s.ball(fur, "head", (0, -0.27, 0.29), (0.12, 0.14, 0.115), u=12, v=8)
	s.tube(fur, "head", (0, -0.33, 0.275), (0, -0.47, 0.235), 0.085, 0.03)
	s.ball(pink, "head", (0, -0.48, 0.232), 0.032, u=8, v=5)
	for sfx, sx in SIDES:
		s.ball(fur, "body", (sx * 0.09, 0.18, 0.22), (0.1, 0.13, 0.12), u=8, v=6)
		s.ball(eye, "head", (sx * 0.07, -0.355, 0.33), 0.028, u=8, v=5)
		s.ball(fur, "head", (sx * 0.09, -0.22, 0.41), (0.075, 0.025, 0.075), u=10, v=6)
		s.ball(pink, "head", (sx * 0.09, -0.24, 0.41), (0.055, 0.012, 0.055), u=8, v=5)
		for k in range(3):
			s.box(whisker, "head", (sx * 0.12, -0.43, 0.235 + 0.012 * (k - 1)), (0.16, 0.005, 0.005),
				rot=(0, -sx * (k - 1) * 12, sx * 12))
	for bone, (hip, foot) in legs.items():
		s.tube(pink, bone, hip, foot, 0.03, 0.022)
		s.ball(pink, bone, (foot[0], foot[1] - 0.03, 0.02), (0.035, 0.05, 0.018), u=8, v=5)
	tail_pts = [(0, 0.3, 0.23), (0, 0.38, 0.2), (0, 0.47, 0.16), (0, 0.56, 0.125), (0, 0.65, 0.1),
		(0, 0.74, 0.088), (0, 0.83, 0.088), (0, 0.92, 0.1), (0, 1.0, 0.12), (0, 1.06, 0.145)]
	tail_r = [0.04 - 0.0034 * i for i in range(len(tail_pts))]
	s.loft(pink, chain(lambda co: co.y, [(0.3, "body"), (0.43, "tail1"), (0.61, "tail2"), (0.79, "tail3"), (0.97, "tail4")]),
		tail_pts, tail_r, segs=6)
	mesh = s.build("mys", rig)

	def tail(ch, t, amp, lag, speed=1.0):
		for i in range(1, 5):
			ch["tail%d.r" % i] = (3.0 * math.sin(TAU * speed * t - lag * i), 0.0, amp * math.sin(TAU * speed * t - lag * i))

	def legs_trot(ch, p, amp):
		for sfx, _ in SIDES:
			front = 0.0 if sfx == "_R" else math.pi
			ch["leg_F" + sfx + ".r"] = (amp * math.sin(p + front), 0.0, 0.0)
			ch["leg_B" + sfx + ".r"] = (amp * math.sin(p + front + math.pi), 0.0, 0.0)

	def walk(t):
		p = TAU * t
		ch = {
			"root.l": (0.0, 0.0, 0.015 * (0.5 + 0.5 * math.cos(2 * p))),
			"body.r": (3.0 * math.sin(2 * p), 0.0, 2.0 * math.sin(p)),
			"head.r": (-5.0 * math.sin(2 * p + 1.0), 0.0, 6.0 * math.sin(p)),
		}
		legs_trot(ch, p, 32.0)
		tail(ch, t, 11.0, 0.9)
		return ch

	def idle(t):
		p = TAU * t
		ch = {
			"body.r": (1.5 * math.sin(p), 0.0, 0.0),
			"head.r": (-4.0 + 4.0 * math.sin(4 * p), 0.0, 12.0 * math.sin(p)),
		}
		tail(ch, t, 10.0, 0.7)
		return ch

	attack_keys = [
		(0.0, {}),
		(0.35, {"root.l": (0, 0.06, 0.04), "body.r": (-28, 0, 0), "head.r": (-15, 0, 0),
			"leg_F_R.r": (-45, 0, 0), "leg_F_L.r": (-45, 0, 0), "tail1.r": (32, 0, 0), "tail2.r": (8, 0, 0)}),
		(0.55, {"root.l": (0, -0.2, 0.03), "body.r": (6, 0, 0), "head.r": (14, 0, 0),
			"leg_F_R.r": (-15, 0, 0), "leg_F_L.r": (-15, 0, 0), "leg_B_R.r": (25, 0, 0), "leg_B_L.r": (25, 0, 0)}),
		(0.7, {"root.l": (0, -0.18, 0.01), "body.r": (4, 0, 0), "head.r": (8, 0, 0)}),
		(1.0, {}),
	]

	def attack(t):
		ch = keyed(t, attack_keys)
		for i in range(1, 5):
			pitch = ch.get("tail%d.r" % i, (0.0, 0.0, 0.0))[0]
			ch["tail%d.r" % i] = (pitch, 0.0, 20.0 * math.sin(2.0 * TAU * t - 0.8 * i))
		return ch

	def death(t):
		# Squeak-jump, flip onto the back, legs twitch then go stiff.
		flip = ease(t / 0.4)
		hop = math.sin(math.pi * clamp01(t / 0.4))
		ch = {
			"root.r": (0.0, 180.0 * flip, 0.0),
			"root.l": (0.0, 0.0, 0.5 * flip + 0.25 * hop),
			"head.r": (-20.0 * flip, 0.0, 0.0),
		}
		decay = (clamp01(1.0 - (t - 0.4) / 0.45) if t > 0.4 else 1.0) * ease(t / 0.15)
		twitch = 30.0 * math.sin(t * 70.0) * decay
		for sfx, sx in SIDES:
			ch["leg_F" + sfx + ".r"] = (twitch - 25.0 * flip, 0.0, sx * 20.0 * flip)
			ch["leg_B" + sfx + ".r"] = (-twitch + 25.0 * flip, 0.0, sx * 20.0 * flip)
		for i in range(1, 5):
			ch["tail%d.r" % i] = (-8.0 * flip + 10.0 * math.sin(t * 50.0 - i) * decay, 0.0, 0.0)
		return ch

	return rig, mesh, [("Walk", 12, walk, True), ("Idle", 24, idle, True), ("Attack", 14, attack, False), ("Death", 24, death, False)]


# ---------------------------------------------------------------- svab

def build_svab():
	shell = material("svab_shell", (0.22, 0.09, 0.03), roughness=0.22, metallic=0.1)
	wing = material("svab_wing", (0.42, 0.18, 0.06), roughness=0.18, metallic=0.1)
	pale = material("svab_pale", (0.66, 0.45, 0.2), roughness=0.4)
	belly = material("svab_belly", (0.33, 0.15, 0.06), roughness=0.5)
	leg_mat = material("svab_leg", (0.3, 0.13, 0.05), roughness=0.4)
	black = material("svab_eye", (0.02, 0.02, 0.02), roughness=0.15)

	bones = [
		("root", (0, 0, 0), (0, 0, 0.15), None),
		("thorax", (0, 0.08, 0.24), (0, -0.22, 0.24), "root"),
		("head", (0, -0.24, 0.23), (0, -0.4, 0.2), "thorax"),
		("abdomen", (0, 0.08, 0.25), (0, 0.72, 0.22), "root"),
	]
	antenna = {}
	for sfx, sx in SIDES:
		pts = ((sx * 0.05, -0.37, 0.25), (sx * 0.2, -0.7, 0.36), (sx * 0.38, -1.02, 0.42))
		antenna[sfx] = pts
		bones.append(("ant1" + sfx, pts[0], pts[1], "head"))
		bones.append(("ant2" + sfx, pts[1], pts[2], "ant1" + sfx))
	# (hip y, knee, foot) per pair: front, middle, hind.
	pairs = [
		(-0.16, (0.34, -0.28, 0.3), (0.5, -0.46, 0.012)),
		(-0.04, (0.4, -0.04, 0.32), (0.6, 0.0, 0.012)),
		(0.08, (0.38, 0.26, 0.3), (0.56, 0.56, 0.012)),
	]
	leg_pts = {}
	for i, (hy, knee, foot) in enumerate(pairs):
		for sfx, sx in SIDES:
			hip = (sx * 0.12, hy, 0.21)
			kn = (sx * knee[0], knee[1], knee[2])
			ft = (sx * foot[0], foot[1], foot[2])
			leg_pts[(i, sfx)] = (hip, kn, ft)
			bones.append(("femur%d%s" % (i, sfx), hip, kn, "thorax"))
			bones.append(("tibia%d%s" % (i, sfx), kn, ft, "femur%d%s" % (i, sfx)))
	rig = build_rig("svab", bones)

	s = Skin()
	s.ball(pale, "thorax", (0, -0.1, 0.27), (0.22, 0.18, 0.085), u=14, v=6)
	s.ball(shell, "thorax", (0, -0.11, 0.282), (0.17, 0.14, 0.1), u=12, v=6)
	s.ball(belly, "thorax", (0, -0.02, 0.22), (0.15, 0.19, 0.09), u=10, v=6)
	s.ball(shell, "head", (0, -0.3, 0.21), (0.11, 0.08, 0.08), u=10, v=6)
	s.tube(belly, "head", (0, -0.36, 0.18), (0, -0.4, 0.13), 0.04, 0.015, segs=6)
	s.ball(belly, "abdomen", (0, 0.36, 0.22), (0.2, 0.37, 0.1), u=12, v=6)
	for sfx, sx in SIDES:
		s.ball(black, "head", (sx * 0.075, -0.33, 0.24), 0.032, u=8, v=5)
		s.ball(wing, "abdomen", (sx * 0.095, 0.3, 0.3), (0.13, 0.44, 0.05), rot=(0, 0, sx * 4), u=12, v=6)
		s.tube(belly, "abdomen", (sx * 0.06, 0.7, 0.23), (sx * 0.13, 0.86, 0.26), 0.02, 0.006, segs=5)
		pts = antenna[sfx]
		mid = tuple((a + b) * 0.5 for a, b in zip(pts[0], pts[1]))
		mid2 = tuple((a + b) * 0.5 for a, b in zip(pts[1], pts[2]))
		s.loft(leg_mat, chain(lambda co: -co.y, [(0.37, "head"), (0.53, "ant1" + sfx), (0.86, "ant2" + sfx)]),
			[pts[0], mid, pts[1], mid2, pts[2]], [0.014, 0.011, 0.009, 0.006, 0.003], segs=5)
	for (i, sfx), (hip, kn, ft) in leg_pts.items():
		femur, tibia = "femur%d%s" % (i, sfx), "tibia%d%s" % (i, sfx)
		s.tube(leg_mat, femur, hip, kn, 0.038, 0.03, segs=6)
		s.ball(leg_mat, tibia, kn, 0.032, u=6, v=4)
		s.tube(leg_mat, tibia, kn, ft, 0.028, 0.01, segs=6)
		# A couple of spines on each tibia.
		for k in (0.35, 0.65):
			base = Vector(kn).lerp(Vector(ft), k)
			s.tube(black, tibia, base, base + Vector((0.05 * math.copysign(1, hip[0]), 0.02, 0.03)), 0.009, 0.002, segs=4)
	mesh = s.build("svab", rig)

	tripod_a = {(0, "_R"), (1, "_L"), (2, "_R")}

	def legs_tripod(ch, t, swing, lift):
		for i in range(3):
			for sfx, sx in SIDES:
				u = (t + (0.0 if (i, sfx) in tripod_a else 0.5)) % 1.0
				if u < 0.5:
					f, up = 1.0 - 4.0 * u, 0.0
				else:
					w = (u - 0.5) / 0.5
					f, up = -1.0 + 2.0 * ease(w), math.sin(math.pi * w)
				ch["femur%d%s.r" % (i, sfx)] = (0.0, -sx * up * lift, -sx * f * swing)
				ch["tibia%d%s.r" % (i, sfx)] = (0.0, sx * up * 14.0, 0.0)

	def antennae(ch, t, amp, speed=1.0):
		for sfx, sx in SIDES:
			ch["ant1" + sfx + ".r"] = (6.0 * math.sin(TAU * speed * t + sx), 0.0, amp * math.sin(TAU * speed * t + sx))
			ch["ant2" + sfx + ".r"] = (0.0, 0.0, 1.5 * amp * math.sin(TAU * speed * t + sx - 1.0))

	def walk(t):
		p = TAU * t
		ch = {
			"root.l": (0.0, 0.0, 0.012 * math.cos(2 * p)),
			"thorax.r": (0.0, 0.0, 3.0 * math.sin(p)),
			"abdomen.r": (2.0 * math.sin(2 * p), 0.0, -4.0 * math.sin(p)),
			"head.r": (0.0, 0.0, 4.0 * math.sin(p + 0.5)),
		}
		legs_tripod(ch, t, 24.0, 22.0)
		antennae(ch, t, 10.0)
		return ch

	def idle(t):
		p = TAU * t
		ch = {"abdomen.r": (1.5 * math.sin(p), 0.0, 0.0), "head.r": (0.0, 0.0, 3.0 * math.sin(p))}
		antennae(ch, t, 14.0, speed=2.0)
		return ch

	front_up = {}
	front_strike = {}
	for sfx, sx in SIDES:
		front_up["femur0" + sfx + ".r"] = (0.0, -sx * 40.0, -sx * 25.0)
		front_up["tibia0" + sfx + ".r"] = (0.0, -sx * 20.0, 0.0)
		front_strike["femur0" + sfx + ".r"] = (0.0, -sx * 5.0, -sx * 30.0)
		front_strike["ant1" + sfx + ".r"] = (-20.0, 0.0, sx * 15.0)
	attack_keys = [
		(0.0, {}),
		(0.35, {"root.r": (-14, 0, 0), "root.l": (0, 0.05, 0.15), "head.r": (-10, 0, 0), "abdomen.r": (10, 0, 0), **front_up}),
		(0.55, {"root.r": (6, 0, 0), "root.l": (0, -0.28, 0.06), "head.r": (12, 0, 0), **front_strike}),
		(0.72, {"root.r": (4, 0, 0), "root.l": (0, -0.24, 0.04), "head.r": (8, 0, 0), **front_strike}),
		(1.0, {}),
	]

	def attack(t):
		ch = keyed(t, attack_keys)
		for sfx, sx in SIDES:
			ch["ant2" + sfx + ".r"] = (0.0, 0.0, 25.0 * math.sin(t * 30.0 + sx))
		return ch

	def death(t):
		# Flips over and dies the roach way: legs flail, then curl up.
		flip = ease(t / 0.35)
		hop = math.sin(math.pi * clamp01(t / 0.35))
		ch = {
			"root.r": (0.0, -180.0 * flip, 0.0),
			"root.l": (0.0, 0.0, 0.42 * flip + 0.45 * hop),
		}
		decay = clamp01(1.0 - (t - 0.3) / 0.5) * ease(t / 0.15)
		curl = ease((t - 0.45) / 0.45)
		for i in range(3):
			for sfx, sx in SIDES:
				flail = math.sin(t * 60.0 + i * 2.1 + sx) * decay
				# Positive lift folds the legs over the (now upturned) belly.
				ch["femur%d%s.r" % (i, sfx)] = (0.0, -sx * 20.0 * flail + sx * 25.0 * curl, -sx * 25.0 * flail)
				ch["tibia%d%s.r" % (i, sfx)] = (0.0, sx * 55.0 * curl, 0.0)
		for sfx, sx in SIDES:
			ch["ant1" + sfx + ".r"] = (15.0 * flip + 10 * math.sin(t * 40.0) * decay, 0.0, 0.0)
			ch["ant2" + sfx + ".r"] = (20.0 * curl, 0.0, 0.0)
		return ch

	return rig, mesh, [("Walk", 10, walk, True), ("Idle", 24, idle, True), ("Attack", 14, attack, False), ("Death", 28, death, False)]


# ---------------------------------------------------------------- lahev

def build_lahev():
	glass = material("lahev_glass", (0.2, 0.07, 0.02), roughness=0.12, metallic=0.05)
	label = material("lahev_label", (0.92, 0.84, 0.62), roughness=0.7)
	red = material("lahev_red", (0.72, 0.06, 0.05), roughness=0.5)
	black = material("lahev_black", (0.03, 0.03, 0.03), roughness=0.5)
	gold = material("lahev_gold", (0.95, 0.7, 0.22), roughness=0.3, metallic=0.5)
	cork = material("lahev_cork", (0.72, 0.52, 0.3), roughness=0.9)
	eye_white = material("lahev_eye", (1.0, 0.86, 0.84), roughness=0.3)
	glove = material("lahev_glove", (0.95, 0.95, 0.93), roughness=0.6)
	shoe = material("lahev_shoe", (0.25, 0.12, 0.05), roughness=0.4)

	bones = [
		("root", (0, 0, 0), (0, 0, 0.2), None),
		("hips", (0, 0, 0.4), (0, 0, 0.55), "root"),
		("body", (0, 0, 0.42), (0, 0, 1.2), "hips"),
		("neck", (0, 0, 1.2), (0, 0, 1.5), "body"),
		("cork", (0, 0, 1.5), (0, 0, 1.7), "neck"),
	]
	arms = {}
	for sfx, sx in SIDES:
		shoulder, elbow, wrist = (sx * 0.28, 0, 1.0), (sx * 0.47, 0, 0.82), (sx * 0.56, -0.05, 0.62)
		arms[sfx] = (shoulder, elbow, wrist)
		bones.append(("arm1" + sfx, shoulder, elbow, "body"))
		bones.append(("arm2" + sfx, elbow, wrist, "arm1" + sfx))
		bones.append(("thigh" + sfx, (sx * 0.13, 0, 0.4), (sx * 0.13, 0, 0.25), "hips"))
		bones.append(("shin" + sfx, (sx * 0.13, 0, 0.25), (sx * 0.13, 0, 0.1), "thigh" + sfx))
		bones.append(("foot" + sfx, (sx * 0.13, 0, 0.1), (sx * 0.13, -0.14, 0.1), "shin" + sfx))
	rig = build_rig("lahev", bones)

	s = Skin()
	rings = [(0.37, 0.2), (0.39, 0.27), (0.43, 0.3), (1.05, 0.3), (1.13, 0.27), (1.2, 0.19),
		(1.27, 0.115), (1.47, 0.1), (1.49, 0.12), (1.54, 0.12), (1.55, 0.1)]
	s.loft(glass, chain(lambda co: co.z, [(1.16, "body"), (1.26, "neck")]),
		[(0, 0, z) for z, _ in rings], [r for _, r in rings], segs=16)
	s.loft(label, "body", [(0, 0, 0.6), (0, 0, 0.96)], [0.308, 0.308], segs=16, smooth=True)
	s.loft(red, "body", [(0, 0, 0.88), (0, 0, 0.92)], [0.314, 0.314], segs=16)
	s.loft(black, "body", [(0, 0, 0.64), (0, 0, 0.67)], [0.314, 0.314], segs=16)
	s.loft(gold, "neck", [(0, 0, 1.3), (0, 0, 1.37)], [0.118, 0.118], segs=12)
	s.ball(red, "body", (0, -0.305, 0.77), (0.13, 0.02, 0.085), u=12, v=6)
	s.ball(label, "body", (0, -0.322, 0.775), (0.045, 0.012, 0.045), u=8, v=5)
	s.box(black, "body", (0, -0.33, 0.745), (0.07, 0.01, 0.012), rot=(0, 30, 0))
	s.box(black, "body", (0, -0.33, 0.745), (0.07, 0.01, 0.012), rot=(0, -30, 0))
	s.tube(cork, "cork", (0, 0, 1.5), (0, 0, 1.67), 0.085, 0.095, segs=10)
	for sfx, sx in SIDES:
		s.ball(eye_white, "body", (sx * 0.1, -0.265, 1.04), 0.08, u=10, v=7)
		s.ball(black, "body", (sx * 0.09, -0.335, 1.035), 0.036, u=8, v=5)
		s.box(black, "body", (sx * 0.1, -0.33, 1.14), (0.14, 0.03, 0.028), rot=(0, -sx * 18, 0))
		shoulder, elbow, wrist = arms[sfx]
		s.ball(black, "arm1" + sfx, shoulder, 0.05, u=8, v=5)
		s.tube(black, "arm1" + sfx, shoulder, elbow, 0.036, 0.034)
		s.tube(black, "arm2" + sfx, elbow, wrist, 0.034, 0.032)
		s.ball(glove, "arm2" + sfx, (wrist[0] + sx * 0.02, wrist[1] - 0.01, wrist[2] - 0.05), 0.075, u=8, v=6)
		s.tube(glove, "arm2" + sfx, (wrist[0], wrist[1], wrist[2] + 0.03), (wrist[0], wrist[1], wrist[2] - 0.02), 0.055, 0.06)
		s.tube(black, "thigh" + sfx, (sx * 0.13, 0, 0.42), (sx * 0.13, 0, 0.25), 0.05, 0.046)
		s.ball(black, "shin" + sfx, (sx * 0.13, 0, 0.25), 0.047, u=8, v=5)
		s.tube(black, "shin" + sfx, (sx * 0.13, 0, 0.25), (sx * 0.13, 0, 0.1), 0.046, 0.042)
		s.box(shoe, "foot" + sfx, (sx * 0.13, -0.05, 0.05), (0.14, 0.27, 0.1))
		s.ball(shoe, "foot" + sfx, (sx * 0.13, -0.17, 0.055), (0.075, 0.07, 0.055), u=8, v=5)
	mesh = s.build("lahev", rig)

	legs = Biped(0.4, 0.15, 0.15, 0.1)

	def arm_swing(ch, amp, t):
		for sfx, sx in SIDES:
			phase = 0.0 if sfx == "_L" else math.pi
			ch["arm1" + sfx + ".r"] = (amp * math.sin(TAU * t + phase), 0.0, 0.0)
			ch["arm2" + sfx + ".r"] = (-15.0 + 8.0 * math.sin(TAU * t + phase), 0.0, 0.0)

	def walk(t):
		p = TAU * t
		ch = biped_gait(t, 0.26, 0.08, 0.035, 0.02)
		ch["body.r"] = (4.0, 9.0 * math.sin(p), 4.0 * math.sin(p))
		ch["neck.r"] = (0.0, -6.0 * math.sin(p - 0.6), 0.0)
		ch["cork.r"] = (0.0, 0.0, 3.0 * math.sin(2 * p))
		arm_swing(ch, 28.0, t)
		return legs.solve(ch)

	def idle(t):
		p = TAU * t
		ch = {"hips.l": (0.0, 0.0, -0.01 - 0.01 * math.sin(p))}
		ch["body.r"] = (2.0 * math.sin(p), 3.0 * math.sin(p + 1.0), 0.0)
		ch["neck.r"] = (0.0, 4.0 * math.sin(p - 0.5), 0.0)
		arm_swing(ch, 6.0, t)
		return legs.solve(ch)

	def arms(angle1, angle2, spread=0.0):
		ch = {}
		for sfx, sx in SIDES:
			ch["arm1" + sfx + ".r"] = (angle1, sx * spread, 0.0)
			ch["arm2" + sfx + ".r"] = (angle2, 0.0, 0.0)
		return ch

	attack_keys = [
		(0.0, {"hips.l": (0, 0, -0.01)}),
		(0.3, {"hips.l": (0, 0.04, -0.035), "body.r": (-18, 0, 0), "neck.r": (-10, 0, 0), **arms(-40, -50, 25)}),
		(0.45, {"hips.l": (0, -0.06, -0.05), "body.r": (52, 0, 0), "neck.r": (22, 0, 0), **arms(55, -10, -10)}),
		(0.62, {"hips.l": (0, -0.05, -0.05), "body.r": (46, 0, 0), "neck.r": (26, 0, 0), **arms(45, -10, -10)}),
		(0.82, {"hips.l": (0, 0, -0.02), "body.r": (8, 0, 0), **arms(5, -15)}),
		(1.0, {"hips.l": (0, 0, -0.01)}),
	]

	def attack(t):
		return legs.solve(keyed(t, attack_keys))

	death_keys = [
		(0.0, {}),
		(0.15, {"hips.l": (0.03, 0, -0.02), "body.r": (0, 14, 0), "neck.r": (0, 10, 0), **arms(-60, -30, 40)}),
		(0.32, {"hips.l": (-0.03, 0.02, -0.02), "body.r": (-6, -10, 0), "neck.r": (0, -12, 0), **arms(-80, -20, 60)}),
		(0.6, {"hips.r": (-90, 0, 0), "root.l": (0, 0, -0.1),
			"thigh_R.r": (-45, 0, 0), "thigh_L.r": (-25, 0, 0), "shin_R.r": (30, 0, 0), **arms(-120, -10, 70)}),
		(0.7, {"hips.r": (-83, 0, 0), "root.l": (0, 0, -0.08),
			"thigh_R.r": (-20, 0, 0), "thigh_L.r": (-35, 0, 0), **arms(-100, -20, 80)}),
		(0.85, {"hips.r": (-90, 0, 0), "root.l": (0, 0, -0.1),
			"thigh_R.r": (12, 0, 0), "thigh_L.r": (8, 0, 0), "shin_R.r": (10, 0, 0), **arms(-95, -10, 85)}),
		(1.0, {"hips.r": (-90, 0, 0), "root.l": (0, 0, -0.1),
			"thigh_R.r": (15, 0, 0), "thigh_L.r": (10, 0, 0), "shin_R.r": (12, 0, 0), **arms(-92, -5, 88)}),
	]

	def death(t):
		return keyed(t, death_keys)

	return rig, mesh, [("Walk", 20, walk, True), ("Idle", 24, idle, True), ("Attack", 24, attack, False), ("Death", 30, death, False)]


# ---------------------------------------------------------------- slot machines

def seven(s, mat, bone, x, y, z, size):
	s.box(mat, bone, (x, y, z + 0.45 * size), (0.9 * size, 0.25 * size, 0.25 * size))
	s.box(mat, bone, (x + 0.05 * size, y, z - 0.08 * size), (0.25 * size, 0.25 * size, size), rot=(0, -22, 0))


def cherry(s, red, green, bone, x, y, z, size):
	r = 0.32 * size
	s.ball(red, bone, (x - 0.28 * size, y, z - 0.25 * size), (r, 0.5 * r, r), u=8, v=5)
	s.ball(red, bone, (x + 0.3 * size, y, z - 0.3 * size), (r, 0.5 * r, r), u=8, v=5)
	top = (x + 0.12 * size, y, z + 0.55 * size)
	s.tube(green, bone, (x - 0.28 * size, y, z - 0.05 * size), top, 0.06 * size, segs=4)
	s.tube(green, bone, (x + 0.3 * size, y, z - 0.1 * size), top, 0.06 * size, segs=4)
	s.ball(green, bone, (top[0] + 0.2 * size, y, top[2] + 0.02 * size), (0.22 * size, 0.04 * size, 0.1 * size), rot=(0, -20, 0), u=6, v=4)


def bell(s, mat, dark, bone, x, y, z, size):
	s.ball(mat, bone, (x, y, z + 0.05 * size), (0.42 * size, 0.15 * size, 0.45 * size), u=10, v=6)
	s.box(mat, bone, (x, y, z - 0.38 * size), (1.0 * size, 0.2 * size, 0.14 * size))
	s.ball(mat, bone, (x, y, z + 0.55 * size), 0.1 * size, u=6, v=4)
	s.ball(dark, bone, (x, y - 0.02 * size, z - 0.5 * size), 0.1 * size, u=6, v=4)


def build_automat():
	red = material("automat_red", (0.62, 0.04, 0.05), roughness=0.35, metallic=0.3)
	chrome = material("automat_chrome", (0.86, 0.86, 0.9), roughness=0.22, metallic=0.5)
	gold = material("automat_gold", (1.0, 0.74, 0.2), roughness=0.3, metallic=0.5)
	dark = material("automat_dark", (0.03, 0.03, 0.04), roughness=0.5)
	reel = material("automat_reel", (0.95, 0.93, 0.85), roughness=0.5)
	symbol_red = material("automat_symbol_red", (0.85, 0.04, 0.04), roughness=0.4)
	green = material("automat_green", (0.1, 0.55, 0.12), roughness=0.5)
	yellow = material("automat_yellow", (1.0, 0.78, 0.1), roughness=0.35, metallic=0.4)
	leg_mat = material("automat_leg", (0.2, 0.2, 0.22), roughness=0.4, metallic=0.4)
	marquee = material("automat_marquee", (1.0, 0.45, 0.1), roughness=0.4, emission=(1.0, 0.45, 0.08), strength=2.0)
	bulb = material("automat_bulb", (1.0, 0.95, 0.7), roughness=0.2, emission=(1.0, 0.9, 0.55), strength=4.0)
	knob = material("automat_knob", (0.85, 0.03, 0.03), roughness=0.15)
	lamps = [material("automat_lamp_%d" % i, c, roughness=0.3, emission=c, strength=1.5)
		for i, c in enumerate(((1.0, 0.1, 0.05), (1.0, 0.8, 0.05), (0.1, 0.9, 0.2)))]

	reel_x = (-0.27, 0.0, 0.27)
	bones = [
		("root", (0, 0, 0), (0, 0, 0.3), None),
		("hips", (0, 0, 0.72), (0, 0, 0.9), "root"),
		("body", (0, 0, 0.76), (0, 0, 2.0), "hips"),
		("lever", (0.56, 0, 1.3), (0.56, 0, 1.9), "body"),
	]
	for i, x in enumerate(reel_x):
		bones.append(("reel%d" % i, (x - 0.11, -0.24, 1.5), (x + 0.11, -0.24, 1.5), "body"))
	for sfx, sx in SIDES:
		bones.append(("thigh" + sfx, (sx * 0.3, 0, 0.72), (sx * 0.3, 0, 0.45), "hips"))
		bones.append(("shin" + sfx, (sx * 0.3, 0, 0.45), (sx * 0.3, 0, 0.16), "thigh" + sfx))
		bones.append(("foot" + sfx, (sx * 0.3, 0, 0.16), (sx * 0.3, -0.25, 0.16), "shin" + sfx))
	rig = build_rig("automat", bones)

	s = Skin()
	s.box(red, "body", (0, 0, 1.4), (1.0, 0.76, 1.3))
	s.box(chrome, "body", (0, 0, 0.79), (1.06, 0.8, 0.1))
	s.box(chrome, "body", (0, 0, 2.05), (1.06, 0.8, 0.06))
	s.box(gold, "body", (0, 0, 1.24), (1.02, 0.78, 0.04))
	s.tube(yellow, "body", (0, -0.35, 2.05), (0, 0.35, 2.05), 0.5, segs=16, smooth=False)
	s.tube(marquee, "body", (0, -0.37, 2.06), (0, -0.35, 2.06), 0.42, segs=16, smooth=False)
	for k in range(7):
		a = math.radians(12 + k * 26)
		s.ball(bulb, "body", (0.47 * math.cos(a), -0.36, 2.05 + 0.47 * math.sin(a)), 0.04, u=6, v=4)
	# Reel window: chrome bezel, black panel; the reels poke through its front.
	s.box(chrome, "body", (0, -0.37, 1.5), (0.94, 0.03, 0.54))
	s.box(dark, "body", (0, -0.385, 1.5), (0.88, 0.02, 0.48))
	for i, x in enumerate(reel_x):
		bone = "reel%d" % i
		s.tube(reel, bone, (x - 0.115, -0.24, 1.5), (x + 0.115, -0.24, 1.5), 0.19, segs=14, smooth=True)
	cherry(s, symbol_red, green, "reel0", reel_x[0], -0.43, 1.5, 0.12)
	seven(s, symbol_red, "reel1", reel_x[1], -0.43, 1.5, 0.12)
	bell(s, yellow, dark, "reel2", reel_x[2], -0.43, 1.5, 0.12)
	# Coin slot, buttons, tray.
	s.box(chrome, "body", (0.3, -0.385, 1.08), (0.14, 0.03, 0.2))
	s.box(dark, "body", (0.3, -0.402, 1.1), (0.024, 0.01, 0.12))
	for i, lamp in enumerate(lamps):
		s.box(lamp, "body", (-0.33 + i * 0.14, -0.39, 1.08), (0.1, 0.04, 0.06))
	s.box(chrome, "body", (0, -0.43, 0.9), (0.56, 0.14, 0.08))
	s.box(dark, "body", (0, -0.445, 0.93), (0.5, 0.1, 0.03))
	# Lever (its one arm).
	s.tube(chrome, "lever", (0.5, 0, 1.3), (0.64, 0, 1.3), 0.09, segs=10)
	s.tube(chrome, "lever", (0.6, 0, 1.3), (0.6, 0, 1.94), 0.032, segs=8)
	s.ball(knob, "lever", (0.6, 0, 2.0), 0.095, u=10, v=7)
	for sfx, sx in SIDES:
		x = sx * 0.3
		s.tube(leg_mat, "thigh" + sfx, (x, 0, 0.78), (x, 0, 0.45), 0.13, 0.115, segs=10)
		s.ball(chrome, "shin" + sfx, (x, 0, 0.45), 0.125, u=10, v=6)
		s.tube(leg_mat, "shin" + sfx, (x, 0, 0.45), (x, 0, 0.17), 0.11, 0.1, segs=10)
		s.box(leg_mat, "foot" + sfx, (x, -0.07, 0.08), (0.3, 0.5, 0.16))
		s.box(chrome, "foot" + sfx, (x, -0.33, 0.07), (0.3, 0.06, 0.12))
	mesh = s.build("automat", rig)

	legs = Biped(0.72, 0.27, 0.29, 0.16)

	def walk(t):
		p = TAU * t
		ch = biped_gait(t, 0.5, 0.2, 0.07, 0.035)
		ch["body.r"] = (3.0, 5.0 * math.sin(p), 3.0 * math.sin(p))
		ch["lever.r"] = (12.0 * math.sin(2 * p - 1.2), 0.0, 0.0)
		for i in range(3):
			ch["reel%d.r" % i] = (4.0 * math.sin(2 * p + i), 0.0, 0.0)
		return legs.solve(ch)

	def idle(t):
		p = TAU * t
		ch = {"hips.l": (0.0, 0.0, -0.02 - 0.015 * math.sin(p)), "body.r": (1.5 * math.sin(p), 0.0, 0.0),
			"lever.r": (6.0 * math.sin(p - 0.8), 0.0, 0.0)}
		return legs.solve(ch)

	attack_keys = [
		(0.0, {"hips.l": (0, 0, -0.03)}),
		(0.28, {"hips.l": (0, 0.1, -0.08), "body.r": (-14, 0, 0), "lever.r": (-40, 0, 0)}),
		(0.4, {"hips.l": (0, -0.12, -0.08), "body.r": (0, 0, 0), "lever.r": (20, 0, 0), "_f_R": (-0.3, 0.16, -10)}, "lin"),
		(0.5, {"hips.l": (0, -0.35, -0.08), "body.r": (16, 0, 0), "lever.r": (128, 0, 0), "_f_R": (-0.6, 0, 0), "_f_L": (-0.1, 0, 0)}),
		(0.66, {"hips.l": (0, -0.33, -0.09), "body.r": (13, 0, 0), "lever.r": (118, 0, 0), "_f_R": (-0.6, 0, 0), "_f_L": (-0.1, 0, 0)}),
		(0.82, {"hips.l": (0, -0.15, -0.06), "body.r": (4, 0, 0), "lever.r": (30, 0, 0), "_f_R": (-0.3, 0.14, -8)}),
		(1.0, {"hips.l": (0, 0, -0.03)}),
	]

	def attack(t):
		ch = keyed(t, attack_keys)
		for i in range(3):
			ch["reel%d.r" % i] = (360.0 * (2 + i) * ease(t / (0.6 + 0.13 * i)), 0.0, 0.0)
		return legs.solve(ch)

	death_keys = [
		(0.0, {}),
		(0.12, {"body.r": (0, 8, 0), "lever.r": (25, 0, 0), "hips.l": (0, 0, -0.03)}),
		(0.25, {"body.r": (-6, -7, 0), "lever.r": (-20, 0, 0), "hips.l": (0, 0, -0.03)}),
		(0.58, {"hips.r": (-90, 0, 0), "root.l": (0, 0, -0.33), "lever.r": (12, 0, 0),
			"thigh_R.r": (-30, 0, 0), "thigh_L.r": (-18, 0, 0), "shin_R.r": (15, 0, 0)}),
		(0.7, {"hips.r": (-82, 0, 0), "root.l": (0, 0, -0.29), "lever.r": (8, 0, 0),
			"thigh_R.r": (-10, 0, 0), "thigh_L.r": (-25, 0, 0)}),
		(0.84, {"hips.r": (-90, 0, 0), "root.l": (0, 0, -0.33), "lever.r": (4, 0, 0),
			"thigh_R.r": (-12, 0, 0), "thigh_L.r": (-8, 0, 0), "shin_R.r": (12, 0, 0), "shin_L.r": (8, 0, 0)}),
		(1.0, {"hips.r": (-90, 0, 0), "root.l": (0, 0, -0.33), "lever.r": (0, 0, 0),
			"thigh_R.r": (-10, 0, 0), "thigh_L.r": (-6, 0, 0), "shin_R.r": (10, 0, 0), "shin_L.r": (6, 0, 0)}),
	]

	def death(t):
		ch = keyed(t, death_keys)
		for i in range(3):
			ch["reel%d.r" % i] = (360.0 * (3 + i) * ease(t / (0.7 + 0.1 * i)), 0.0, 0.0)
		return ch

	return rig, mesh, [("Walk", 24, walk, True), ("Idle", 32, idle, True), ("Attack", 24, attack, False), ("Death", 32, death, False)]


def build_jackpot():
	gold = material("jackpot_gold", (1.0, 0.78, 0.22), roughness=0.3, metallic=0.45)
	red = material("jackpot_red", (0.72, 0.04, 0.08), roughness=0.35, metallic=0.1)
	chrome = material("jackpot_chrome", (0.88, 0.88, 0.92), roughness=0.2, metallic=0.5)
	dark = material("jackpot_dark", (0.03, 0.02, 0.05), roughness=0.5)
	reel = material("jackpot_reel", (0.96, 0.94, 0.86), roughness=0.5)
	symbol_red = material("jackpot_seven", (0.9, 0.03, 0.04), roughness=0.35)
	face = material("jackpot_marquee", (0.9, 0.08, 0.55), roughness=0.4, emission=(1.0, 0.08, 0.55), strength=3.0)
	eyes = material("jackpot_eyes", (1.0, 0.95, 0.4), roughness=0.3, emission=(1.0, 0.92, 0.3), strength=6.0)
	bulb = material("jackpot_bulb", (1.0, 0.95, 0.7), roughness=0.2, emission=(1.0, 0.88, 0.5), strength=5.0)
	jewel = material("jackpot_jewel", (0.9, 0.0, 0.1), roughness=0.1, emission=(1.0, 0.0, 0.1), strength=1.0)
	glove = material("jackpot_glove", (0.8, 0.04, 0.04), roughness=0.3)
	cuff = material("jackpot_cuff", (0.95, 0.95, 0.92), roughness=0.6)
	leg_mat = material("jackpot_leg", (0.24, 0.18, 0.12), roughness=0.4, metallic=0.4)
	lamps = [material("jackpot_lamp_%d" % i, c, roughness=0.3, emission=c, strength=2.0)
		for i, c in enumerate(((1.0, 0.1, 0.05), (1.0, 0.8, 0.05), (0.1, 0.9, 0.2), (0.15, 0.4, 1.0)))]

	reel_x = (-0.55, 0.0, 0.55)
	bones = [
		("root", (0, 0, 0), (0, 0, 0.4), None),
		("hips", (0, 0, 1.3), (0, 0, 1.6), "root"),
		("body", (0, 0, 1.35), (0, 0, 3.6), "hips"),
		("crown", (0, 0, 4.66), (0, 0, 5.2), "body"),
	]
	for i, x in enumerate(reel_x):
		bones.append(("reel%d" % i, (x - 0.22, -0.45, 2.75), (x + 0.22, -0.45, 2.75), "body"))
	arms = {}
	for sfx, sx in SIDES:
		shoulder, elbow, wrist = (sx * 1.2, 0, 3.05), (sx * 1.45, -0.1, 2.28), (sx * 1.5, -0.32, 1.55)
		arms[sfx] = (shoulder, elbow, wrist)
		bones.append(("upper" + sfx, shoulder, elbow, "body"))
		bones.append(("fore" + sfx, elbow, wrist, "upper" + sfx))
		bones.append(("thigh" + sfx, (sx * 0.6, 0, 1.3), (sx * 0.6, 0, 0.75), "hips"))
		bones.append(("shin" + sfx, (sx * 0.6, 0, 0.75), (sx * 0.6, 0, 0.25), "thigh" + sfx))
		bones.append(("foot" + sfx, (sx * 0.6, 0, 0.25), (sx * 0.6, -0.45, 0.25), "shin" + sfx))
	rig = build_rig("jackpot", bones)

	s = Skin()
	s.box(gold, "body", (0, 0, 2.5), (2.2, 1.5, 2.2))
	s.box(red, "body", (0, 0, 1.42), (2.3, 1.6, 0.16))
	s.box(red, "body", (0, 0, 3.6), (2.3, 1.6, 0.12))
	for sx in (-1, 1):
		s.box(red, "body", (sx * 1.1, -0.75, 2.5), (0.14, 0.14, 2.2))
	# Marquee arch with an angry glowing face and a ring of bulbs.
	s.tube(gold, "body", (0, -0.7, 3.62), (0, 0.7, 3.62), 1.1, segs=20, smooth=False)
	s.tube(face, "body", (0, -0.73, 3.64), (0, -0.7, 3.64), 0.92, segs=20, smooth=False)
	for sx in (-1, 1):
		s.box(eyes, "body", (sx * 0.36, -0.745, 4.08), (0.4, 0.03, 0.13), rot=(0, -sx * 20, 0))
		s.box(eyes, "body", (sx * 0.3, -0.745, 3.78), (0.3, 0.03, 0.08), rot=(0, sx * 14, 0))
	s.box(eyes, "body", (0, -0.745, 3.73), (0.32, 0.03, 0.08))
	for k in range(13):
		a = math.radians(6 + k * 14)
		s.ball(bulb, "body", (1.02 * math.cos(a), -0.74, 3.62 + 1.02 * math.sin(a)), 0.075, u=6, v=4)
	# Reel window: bezel + black panel, three spinning 7s.
	s.box(chrome, "body", (0, -0.74, 2.75), (1.9, 0.05, 0.92))
	s.box(dark, "body", (0, -0.765, 2.75), (1.78, 0.03, 0.82))
	for sx in (-1, 1):
		s.box(lamps[0], "body", (sx * 0.95, -0.8, 2.75), (0.08, 0.04, 0.08), rot=(0, 45, 0))
	for i, x in enumerate(reel_x):
		bone = "reel%d" % i
		s.tube(reel, bone, (x - 0.23, -0.45, 2.75), (x + 0.23, -0.45, 2.75), 0.4, segs=16, smooth=True)
		seven(s, symbol_red, bone, x, -0.86, 2.75, 0.26)
	s.box(chrome, "body", (0.62, -0.77, 2.12), (0.26, 0.05, 0.34))
	s.box(dark, "body", (0.62, -0.8, 2.14), (0.045, 0.02, 0.22))
	for i, lamp in enumerate(lamps):
		s.box(lamp, "body", (-0.85 + i * 0.26, -0.78, 2.1), (0.18, 0.06, 0.1))
	s.box(chrome, "body", (0, -0.85, 1.68), (1.2, 0.26, 0.14))
	s.box(dark, "body", (0, -0.87, 1.73), (1.1, 0.2, 0.06))
	# Crown of light bulbs.
	s.tube(gold, "crown", (0, 0, 4.66), (0, 0, 4.86), 0.55, 0.6, segs=14, smooth=False)
	for k in range(7):
		a = TAU * k / 7 - math.pi / 2
		c, d = math.cos(a), math.sin(a)
		s.tube(gold, "crown", (0.5 * c, 0.5 * d, 4.84), (0.62 * c, 0.62 * d, 5.3), 0.11, 0.03, segs=5, smooth=False)
		s.ball(bulb, "crown", (0.63 * c, 0.63 * d, 5.35), 0.1, u=8, v=5)
		s.ball(jewel, "crown", (0.6 * math.cos(a + math.pi / 7), 0.6 * math.sin(a + math.pi / 7), 4.76), 0.06, u=6, v=4)
	for sfx, sx in SIDES:
		shoulder, elbow, wrist = arms[sfx]
		s.ball(red, "upper" + sfx, shoulder, 0.3, u=10, v=6)
		s.tube(gold, "upper" + sfx, shoulder, elbow, 0.21, 0.18, segs=10)
		s.ball(red, "fore" + sfx, elbow, 0.21, u=10, v=6)
		s.tube(gold, "fore" + sfx, elbow, wrist, 0.18, 0.2, segs=10)
		s.tube(cuff, "fore" + sfx, (wrist[0], wrist[1] + 0.03, wrist[2] + 0.08), (wrist[0], wrist[1] - 0.02, wrist[2] - 0.1), 0.24, 0.25, segs=12)
		s.ball(glove, "fore" + sfx, (wrist[0] + sx * 0.02, wrist[1] - 0.08, wrist[2] - 0.32), (0.3, 0.32, 0.34), u=12, v=8)
		s.ball(glove, "fore" + sfx, (wrist[0] - sx * 0.22, wrist[1] - 0.2, wrist[2] - 0.2), (0.12, 0.12, 0.15), u=8, v=5)
		x = sx * 0.6
		s.tube(leg_mat, "thigh" + sfx, (x, 0, 1.4), (x, 0, 0.75), 0.28, 0.24, segs=12)
		s.ball(gold, "shin" + sfx, (x, 0, 0.75), 0.27, u=10, v=6)
		s.tube(leg_mat, "shin" + sfx, (x, 0, 0.75), (x, 0, 0.27), 0.24, 0.22, segs=12)
		s.box(red, "foot" + sfx, (x, -0.12, 0.13), (0.66, 0.96, 0.26))
		s.box(gold, "foot" + sfx, (x, -0.62, 0.11), (0.66, 0.08, 0.2))
	mesh = s.build("jackpot", rig)

	legs = Biped(1.3, 0.55, 0.5, 0.25)

	def arm_pose(ch, upper, fore, spread=0.0):
		for sfx, sx in SIDES:
			ch["upper" + sfx + ".r"] = (upper, 0.0, 0.0) if not spread else (upper, sx * spread, 0.0)
			ch["fore" + sfx + ".r"] = (fore, 0.0, 0.0)
		return ch

	def walk(t):
		p = TAU * t
		ch = biped_gait(t, 0.9, 0.35, 0.14, 0.07)
		ch["body.r"] = (3.0, 4.0 * math.sin(p), 3.0 * math.sin(p))
		ch["crown.r"] = (0.0, -6.0 * math.sin(p - 0.8), 0.0)
		for sfx, sx in SIDES:
			phase = 0.0 if sfx == "_L" else math.pi
			ch["upper" + sfx + ".r"] = (-18.0 * math.sin(p + phase), sx * 4.0, 0.0)
			ch["fore" + sfx + ".r"] = (-18.0 - 10.0 * math.sin(p + phase), 0.0, 0.0)
		for i in range(3):
			ch["reel%d.r" % i] = (3.0 * math.sin(2 * p + i), 0.0, 0.0)
		return legs.solve(ch)

	def idle(t):
		p = TAU * t
		ch = {"hips.l": (0.0, 0.0, -0.04 - 0.03 * math.sin(p)), "body.r": (1.5 * math.sin(p), 0.0, 0.0),
			"crown.r": (0.0, 3.0 * math.sin(p - 0.7), 0.0)}
		arm_pose(ch, -4.0 * math.sin(p), -15.0 - 5.0 * math.sin(p), 3.0)
		return legs.solve(ch)

	attack_keys = [
		(0.0, {"hips.l": (0, 0, -0.06), **arm_pose({}, 0, -10)}),
		(0.36, {"hips.l": (0, 0.15, -0.08), "body.r": (-12, 0, 0), "crown.r": (-10, 0, 0), **arm_pose({}, -168, -25, 6)}),
		(0.5, {"hips.l": (0, -0.25, -0.55), "body.r": (40, 0, 0), "crown.r": (14, 0, 0), **arm_pose({}, -40, -12, 4)}),
		(0.56, {"hips.l": (0, -0.25, -0.52), "body.r": (37, 0, 0), "crown.r": (5, 0, 0), **arm_pose({}, -42, -12, 4)}),
		(0.68, {"hips.l": (0, -0.24, -0.53), "body.r": (39, 0, 0), "crown.r": (9, 0, 0), **arm_pose({}, -41, -12, 4)}),
		(1.0, {"hips.l": (0, 0, -0.06), **arm_pose({}, 0, -10)}),
	]

	def attack(t):
		ch = keyed(t, attack_keys)
		for i in range(3):
			ch["reel%d.r" % i] = (360.0 * (1 + i) * ease((t - 0.45) / 0.45), 0.0, 0.0)
		return legs.solve(ch)

	buckle = legs.angles(-0.68)
	lying = {**buckle, "hips.r": (-90, 0, 0), "root.l": (0, 0, 0.12), "hips.l": (0, 0, -0.68)}
	death_keys = [
		(0.0, {}),
		(0.1, {"body.r": (0, 7, 0), "crown.r": (0, -10, 0), "upper_R.r": (-70, 0, 20), "upper_L.r": (-30, 0, -10)}),
		(0.22, {"body.r": (-6, -7, 0), "crown.r": (0, 12, 0), "upper_R.r": (-20, 0, -10), "upper_L.r": (-80, 0, -20)}),
		(0.42, {**buckle, "hips.l": (0, 0, -0.68), "body.r": (14, 0, 0), "crown.r": (8, 0, 0), **arm_pose({}, -15, -20, 10)}),
		(0.55, {**buckle, "hips.l": (0, 0, -0.68), "hips.r": (-12, 0, 0), "body.r": (6, 0, 0), **arm_pose({}, -40, -20, 25)}),
		(0.78, {**lying, **arm_pose({}, -60, -10, 50), "crown.r": (0, 0, 8)}),
		(0.87, {**lying, "hips.r": (-83, 0, 0), "root.l": (0, 0, 0.16), **arm_pose({}, -30, -20, 55),
			"crown.r": (0, 6, -5)}),
		(1.0, {**lying, **arm_pose({}, 20, -5, 60), "crown.r": (0, 0, 0)}),
	]

	def death(t):
		ch = keyed(t, death_keys)
		for i in range(3):
			ch["reel%d.r" % i] = (360.0 * (2 + i) * ease(t / (0.6 + 0.12 * i)), 0.0, 0.0)
		return ch

	return rig, mesh, [("Walk", 32, walk, True), ("Idle", 40, idle, True), ("Attack", 36, attack, False), ("Death", 48, death, False)]


CREATURES = {
	"mys": build_mys,
	"svab": build_svab,
	"lahev": build_lahev,
	"automat": build_automat,
	"jackpot": build_jackpot,
}


def build(name, out_dir):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
	scene = bpy.context.scene
	scene.render.fps = FPS
	scene.render.fps_base = 1.0
	scene.unit_settings.system = "METRIC"
	scene.unit_settings.scale_length = 1.0
	rig, mesh, actions = CREATURES[name]()
	# A constant rest offset puts the lowest sole exactly on the ground. The
	# armature object itself never receives animation keys.
	rig.location.z = -min(v.co.z for v in mesh.data.vertices)
	ranges = {}
	made = {}
	for action_name, frames, fn, loop in actions:
		made[action_name] = write_action(rig, mesh, action_name, frames, fn, loop)
		ranges[action_name] = [1, frames + 1]
	walk = made["Walk"]
	rig.animation_data.action = walk
	if hasattr(rig.animation_data, "action_slot") and len(walk.slots) > 0:
		rig.animation_data.action_slot = walk.slots[0]
	scene.frame_start, scene.frame_end = ranges["Walk"]
	scene.frame_set(1)
	path = os.path.join(out_dir, name + ".blend")
	bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)
	return {"file": path, "verts": len(mesh.data.vertices), "faces": len(mesh.data.polygons), "bones": len(rig.data.bones), "actions": ranges}


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	names = [a for a in argv if a in CREATURES]
	dirs = [a for a in argv if a not in CREATURES]
	out_dir = os.path.abspath(dirs[0] if dirs else DEFAULT_OUT)
	os.makedirs(out_dir, exist_ok=True)
	report = {}
	for name in names or list(CREATURES):
		report[name] = build(name, out_dir)
		print("delirium:", name, json.dumps(report[name]))
	with open(os.path.join(out_dir, "delirium_report.json"), "w", encoding="utf-8") as handle:
		json.dump(report, handle, indent=2)


main()
