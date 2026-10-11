class_name HordeFx
extends Node3D

## Pooled hit and death effects for the horde, one MultiMesh per particle kind.
## Robots throw sparks and tumbling debris; aliens spray goo droplets and leave
## short-lived floor splats. Every pool is a fixed-size ring (the oldest pieces
## are recycled when full); pieces are small, opaque and never white, so mass
## kills stay readable. Colours come from HordeEnemyDefinition.fx_color.

const STRIDE := 16
const GRAVITY := 16.0
const MEGA_CAPACITY := Horde.CAPACITY / 6
const FUSION_COLOR := Color(0.84, 0.52, 0.16)

enum { SPARK, DEBRIS, GOO, SPLAT, KIND_COUNT }

@export var spark_mesh: Mesh
@export var spark_material: Material
@export var debris_mesh: Mesh
@export var debris_material: Material
@export var goo_mesh: Mesh
@export var goo_material: Material
@export var splat_mesh: Mesh
@export var splat_material: Material
## Pool sizes per kind (SPARK, DEBRIS, GOO, SPLAT).
@export var capacities := PackedInt32Array([384, 192, 320, 96])
## Hit effects spawned per rendered frame at most; extra hits are skipped.
@export var max_hits_per_frame := 12
## Death bursts spawned per rendered frame at most; extra kills are skipped.
@export var max_deaths_per_frame := 24

var _renderers: Array[MultiMeshInstance3D] = []
var _buffers: Array[PackedFloat32Array] = []
# Particles of every kind live in shared flat arrays; kind k owns
# [_offset[k], _offset[k] + capacity) and its first _count[k] entries are live.
var _offset := PackedInt32Array()
var _capacity := PackedInt32Array()
var _count := PackedInt32Array()
var _cursor := PackedInt32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _color := PackedColorArray()
var _hits_this_frame := 0
var _deaths_this_frame := 0
var _rng := RandomNumberGenerator.new()
# Owning horde: debris lands on its heightfield (decks, ramps).
var _horde: Horde
# One shared segmented crown mesh; no per-enemy render nodes or dynamic pools.
var _mega_renderer: MultiMeshInstance3D
var _mega_buffer := PackedFloat32Array()
var _mega_indices := PackedInt32Array()
var _mega_time := 0.0
var _mega_generations := PackedInt64Array()
var _mega_count := 0
var _fusions_this_frame := 0
var _world_area := Rect2()

func _ready() -> void:
	# Only stale crown identities are checked while pause/rewards stop particles.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_horde = get_parent() as Horde
	var meshes: Array[Mesh] = [spark_mesh, debris_mesh, goo_mesh, splat_mesh]
	var materials: Array[Material] = [spark_material, debris_material, goo_material, splat_material]
	var total := 0
	for kind in KIND_COUNT:
		var capacity := capacities[kind] if kind < capacities.size() else 64
		_offset.append(total)
		_capacity.append(capacity)
		_count.append(0)
		_cursor.append(0)
		total += capacity
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = meshes[kind]
		multimesh.instance_count = capacity
		multimesh.visible_instance_count = 0
		var renderer := MultiMeshInstance3D.new()
		renderer.multimesh = multimesh
		renderer.material_override = materials[kind]
		renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Particles live around the crowd; a fixed box avoids per-frame AABB work.
		renderer.custom_aabb = AABB(Vector3(-200.0, -5.0, -200.0), Vector3(400.0, 40.0, 400.0))
		add_child(renderer)
		_renderers.append(renderer)
		var buffer := PackedFloat32Array()
		buffer.resize(capacity * STRIDE)
		_buffers.append(buffer)
	_pos.resize(total)
	_vel.resize(total)
	_life.resize(total)
	_max_life.resize(total)
	_size.resize(total)
	_spin.resize(total)
	_color.resize(total)
	_setup_mega_marks()
	_sync_world_bounds()
	if _horde != null:
		_horde.enemy_fused.connect(_on_enemy_fused)

func _setup_mega_marks() -> void:
	var segment := BoxMesh.new()
	segment.size = Vector3(0.50, 0.10, 0.12)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in 6:
		var angle := float(n) * TAU / 6.0
		var basis := Basis(Vector3.UP, -angle + PI * 0.5)
		var at := Vector3(cos(angle), 0.0, sin(angle))
		tool.append_from(segment, 0, Transform3D(basis, at))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = tool.commit()
	multimesh.instance_count = MEGA_CAPACITY
	multimesh.visible_instance_count = 0
	_mega_renderer = MultiMeshInstance3D.new()
	_mega_renderer.multimesh = multimesh
	_mega_renderer.material_override = material
	_mega_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mega_renderer)
	_mega_buffer.resize(MEGA_CAPACITY * STRIDE)
	_mega_indices.resize(Horde.CAPACITY)
	_mega_generations.resize(MEGA_CAPACITY)

func _sync_world_bounds() -> void:
	if _horde == null or _horde.play_area == _world_area:
		return
	_world_area = _horde.play_area
	var bounds := AABB(Vector3(_world_area.position.x - 4.0, -5.0, _world_area.position.y - 4.0), Vector3(_world_area.size.x + 8.0, 40.0, _world_area.size.y + 8.0))
	for renderer in _renderers:
		renderer.custom_aabb = bounds
	_mega_renderer.custom_aabb = bounds

func _update_mega_marks(delta: float) -> void:
	if _horde == null:
		return
	_mega_time += delta
	var count := mini(_horde.query_megas(_mega_indices), MEGA_CAPACITY)
	var multimesh := _mega_renderer.multimesh
	_mega_count = count
	if count == 0:
		multimesh.visible_instance_count = 0
		return
	var buffer := _mega_buffer
	_mega_buffer = PackedFloat32Array()
	for n in count:
		var slot := _mega_indices[n]
		_mega_generations[n] = _horde.enemy_generation(slot)
		var center := _horde.enemy_position(slot)
		var definition := _horde.get_definition(slot)
		var height := definition.height * _horde.enemy_body_scale(slot)
		var body_radius := _horde.enemy_radius(slot)
		var radius := body_radius * 0.85
		var ground_y := _horde.ground_height(Vector2(center.x, center.z))
		var floor_y := maxf(center.y - height * 0.5, ground_y)
		var yaw := float(slot) * 0.71 + _mega_time * 0.14
		var basis := Basis.from_euler(Vector3(0.08, yaw, 0.05)).scaled(Vector3.ONE * radius)
		var k := n * STRIDE
		buffer[k] = basis.x.x
		buffer[k + 1] = basis.y.x
		buffer[k + 2] = basis.z.x
		buffer[k + 3] = center.x
		buffer[k + 4] = basis.x.y
		buffer[k + 5] = basis.y.y
		buffer[k + 6] = basis.z.y
		buffer[k + 7] = floor_y + height + radius * 0.10
		buffer[k + 8] = basis.x.z
		buffer[k + 9] = basis.y.z
		buffer[k + 10] = basis.z.z
		buffer[k + 11] = center.z
		var brightness := 0.88 + float(_horde.fusion_members(slot) - 6) * 0.06
		buffer[k + 12] = FUSION_COLOR.r * brightness
		buffer[k + 13] = FUSION_COLOR.g * brightness
		buffer[k + 14] = FUSION_COLOR.b * brightness
		buffer[k + 15] = 1.0
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)
	multimesh.visible_instance_count = count
	_mega_buffer = buffer

func _on_enemy_fused(index: int, members: int) -> void:
	if _horde == null or _offset.is_empty() or _fusions_this_frame >= 4:
		return
	_fusions_this_frame += 1
	var center := _horde.enemy_position(index)
	var definition := _horde.get_definition(index)
	var height := definition.height * _horde.enemy_body_scale(index)
	var radius := clampf(_horde.enemy_radius(index) * 2.0, 0.6, 2.4)
	var pieces := mini(members + 4, 12)
	var duration := 0.38
	for n in pieces:
		var angle := float(n) * TAU / float(pieces) + float(index) * 0.71
		var radial := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var at := center + radial
		at.x = clampf(at.x, _horde.play_area.position.x, _horde.play_area.end.x)
		at.z = clampf(at.z, _horde.play_area.position.y, _horde.play_area.end.y)
		at.y = maxf(center.y - height * 0.15, _horde.ground_height(Vector2(at.x, at.z)) + 0.08)
		var velocity := Vector3((center.x - at.x) / duration, GRAVITY * duration * 0.5, (center.z - at.z) / duration)
		_emit(SPARK, at, velocity, duration, 0.035, FUSION_COLOR)

## Small burst where a non-lethal hit landed.
func burst_hit(definition: HordeEnemyDefinition, at: Vector3) -> void:
	if _hits_this_frame >= max_hits_per_frame or _offset.is_empty():
		return
	_hits_this_frame += 1
	var color := definition.fx_color
	if definition.faction == HordeEnemyDefinition.Faction.FLESH:
		for n in 2:
			_emit(GOO, at, _spray(3.5, 2.5), 0.45, _rng.randf_range(0.05, 0.08), color)
	else:
		for n in 3:
			_emit(SPARK, at, _spray(6.0, 3.5), _rng.randf_range(0.15, 0.3), 0.045, color)

## One scaled visual burst per dead body, independent of constituent rewards.
func burst_death(definition: HordeEnemyDefinition, at: Vector3, body_scale: float) -> void:
	if _offset.is_empty() or (_deaths_this_frame >= max_deaths_per_frame and not definition.is_boss):
		return
	_deaths_this_frame += 1
	var bulk := clampf(definition.radius * body_scale / 0.4, 0.8, 5.0)
	var reach := sqrt(bulk)
	var color := definition.fx_color
	var pieces := roundi(3.0 * bulk) * (3 if definition.is_boss else 1)
	if definition.faction == HordeEnemyDefinition.Faction.FLESH:
		for n in pieces + 2:
			_emit(GOO, at, _spray(4.5 * reach, 4.0), 0.8, _rng.randf_range(0.07, 0.13) * reach, color)
		var floor_y := _horde.ground_height(Vector2(at.x, at.z)) + 0.02
		_emit(SPLAT, Vector3(at.x, floor_y, at.z), Vector3.ZERO, 1.4, definition.radius * body_scale * 1.6, color.darkened(0.25))
	else:
		for n in pieces + 3:
			_emit(SPARK, at, _spray(8.0 * reach, 5.0), _rng.randf_range(0.25, 0.45), 0.05, color)
		var metal := Color(0.22, 0.24, 0.28).lerp(color, 0.2)
		for n in pieces:
			_emit(DEBRIS, at, _spray(4.5 * reach, 5.5), _rng.randf_range(0.7, 1.0), _rng.randf_range(0.07, 0.14) * reach, metal)

func _process(delta: float) -> void:
	if get_tree().paused:
		# No simulation, uploads or terrain queries unless a pooled identity changed.
		for n in _mega_count:
			var slot := _mega_indices[n]
			if not _horde.is_alive(slot) or _horde.enemy_generation(slot) != _mega_generations[n]:
				_update_mega_marks(0.0)
				break
		return
	_hits_this_frame = 0
	_deaths_this_frame = 0
	_fusions_this_frame = 0
	_sync_world_bounds()
	_update_mega_marks(delta)
	for kind in KIND_COUNT:
		_update(kind, delta)

func _emit(kind: int, at: Vector3, velocity: Vector3, life: float, size: float, color: Color) -> void:
	var capacity := _capacity[kind]
	var index := _count[kind]
	if index >= capacity:
		# Full: recycle round-robin.
		index = _cursor[kind]
		_cursor[kind] = (index + 1) % capacity
	else:
		_count[kind] = index + 1
	var i := _offset[kind] + index
	_pos[i] = at
	_vel[i] = velocity
	_life[i] = life
	_max_life[i] = life
	_size[i] = size
	_spin[i] = _rng.randf() * TAU
	_color[i] = color

func _spray(horizontal: float, upward: float) -> Vector3:
	var angle := _rng.randf() * TAU
	var push := _rng.randf_range(0.35, 1.0) * horizontal
	return Vector3(cos(angle) * push, _rng.randf_range(0.4, 1.0) * upward, sin(angle) * push)

func _update(kind: int, delta: float) -> void:
	var count := _count[kind]
	var multimesh := _renderers[kind].multimesh
	if count == 0:
		if multimesh.visible_instance_count != 0:
			multimesh.visible_instance_count = 0
		return
	var buffer := _buffers[kind]
	# Detach so in-place writes never copy-on-write the stored array.
	_buffers[kind] = PackedFloat32Array()
	var base := _offset[kind]
	var n := 0
	for index in count:
		var i := base + index
		var left := _life[i] - delta
		if left <= 0.0:
			continue
		var p := _pos[i]
		var v := _vel[i]
		if kind != SPLAT:
			v.y -= GRAVITY * delta
			p += v * delta
			if _horde != null and not _world_area.has_point(Vector2(p.x, p.z)):
				continue
			var ground := 0.03 + (_horde.ground_height(Vector2(p.x, p.z)) if _horde != null else 0.0)
			if p.y < ground:
				if kind == DEBRIS:
					# Bounce, then skid to rest.
					p.y = ground
					v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5) if v.y < -1.0 else Vector3(v.x * 0.9, 0.0, v.z * 0.9)
				else:
					continue
		var fraction := left / _max_life[i]
		var scale := _size[i]
		var angle := _spin[i]
		var tall := 1.0
		match kind:
			SPARK:
				scale *= fraction
				tall = 3.0
			SPLAT:
				# Spread fast, flat on the floor, then shrink away.
				scale *= minf(1.0, (1.0 - fraction) * 8.0) * minf(1.0, fraction * 3.0)
				tall = 0.08
			DEBRIS:
				angle += (1.0 - fraction) * 9.0
				scale *= minf(1.0, fraction * 4.0)
			_:
				scale *= minf(1.0, fraction * 3.0)
		var j := base + n
		_pos[j] = p
		_vel[j] = v
		_life[j] = left
		_max_life[j] = _max_life[i]
		_size[j] = _size[i]
		_spin[j] = _spin[i]
		_color[j] = _color[i]
		var c := cos(angle) * scale
		var s := sin(angle) * scale
		var tone := _color[j]
		var k := n * STRIDE
		buffer[k] = c
		buffer[k + 1] = 0.0
		buffer[k + 2] = s
		buffer[k + 3] = p.x
		buffer[k + 4] = 0.0
		buffer[k + 5] = scale * tall
		buffer[k + 6] = 0.0
		buffer[k + 7] = p.y
		buffer[k + 8] = -s
		buffer[k + 9] = 0.0
		buffer[k + 10] = c
		buffer[k + 11] = p.z
		buffer[k + 12] = tone.r
		buffer[k + 13] = tone.g
		buffer[k + 14] = tone.b
		buffer[k + 15] = fraction
		n += 1
	_count[kind] = n
	if _cursor[kind] >= n:
		_cursor[kind] = 0
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)
	multimesh.visible_instance_count = n
	_buffers[kind] = buffer
