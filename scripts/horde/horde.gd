class_name Horde
extends Node3D

## Data-oriented crowd of up to CAPACITY enemies. No per-enemy nodes or physics
## bodies: positions live in packed arrays on the XZ plane with a feet height
## from a heightfield (the world's Elevation decks and ramps), crowding uses a
## uniform grid, and each enemy type draws as one MultiMesh. Enemies walk up
## ramps, drop off ledges and cannot climb cliffs. Weapons query enemies
## through raycast/query_radius/nearest and damage them by index.

signal enemy_killed(definition: HordeEnemyDefinition, position: Vector3)
signal boss_spawned(definition: HordeEnemyDefinition)
signal boss_health_changed(current: float, maximum: float)
signal boss_killed
signal damage_reported(at: Vector3, amount: float, damage_type: int, critical: bool, killed: bool)

const CAPACITY := 4096
const CELL := 2.0
const DEATH_TIME := 0.22
## Final fraction of an animated death spent shrinking away.
const DEATH_FADE := 0.3
## Extra distance at which melee enemies play their attack clip on the player.
const CONTACT_ANIMATION_MARGIN := 0.35
const FLASH_TIME := 0.12
const PLAYER_RADIUS := 0.4
const MAX_NEIGHBOR_CHECKS := 8
const SEPARATION := 0.45
const MAX_PROJECTILES := 512
## Enemy projectiles shrink to nothing between these camera distances (m).
const PROJECTILE_FADE_NEAR := 0.35
const PROJECTILE_FADE_FAR := 1.6
const BIG_RADIUS := 0.9
const BURN_DURATION := 2.0
const BURN_TICK := 0.5
const FROST_FACTOR := 0.55
const FROST_DURATION := 1.8
const SHOCK_RADIUS := 3.5
const SHOCK_TARGETS := 3
const SHOCK_CHECKS := 96
const RADIUS_DEPTH := 8

enum { FREE, ALIVE, DYING }
enum Mode { SEEK, WINDUP, CHARGE }

@export var enemy_shader: Shader
## Used for definitions with a vertex_animation (see HordeVertexAnimation).
@export var animated_enemy_shader: Shader
## HordeFx scene instanced at setup for hit sparks and death bursts; optional.
@export var fx_scene: PackedScene
@export var projectile_mesh: Mesh
@export var projectile_material: Material
@export var projectile_radius := 0.22
## Crowd contact hurts in ticks: every contact_tick seconds the player takes
## the summed contact_damage of touching enemies, capped at contact_cap.
@export var contact_tick := 0.5
@export var contact_cap := 4.0
## Hitscan forgiveness above each enemy's height so level shots at eye height
## still connect with short enemies.
@export var hit_headroom := 0.6

var alive_count := 0
var target: ArenaPlayer

var _defs: Array[HordeEnemyDefinition] = []
var _type_of: Dictionary = {}
var _t_behavior := PackedInt32Array()
var _t_speed := PackedFloat32Array()
var _t_radius := PackedFloat32Array()
var _t_height := PackedFloat32Array()
var _t_mass := PackedFloat32Array()
var _t_contact := PackedFloat32Array()
var _t_scale := PackedFloat32Array()
var _t_boss := PackedByteArray()
var _t_weak_offset := PackedVector3Array()
var _t_weak_radius_squared := PackedFloat32Array()
var _t_weak_top := PackedFloat32Array()
var _renderers: Array[MultiMeshInstance3D] = []
var _buffers: Array[PackedFloat32Array] = []

# Rendering: per-type animation setup (clip ids index the _clip_* arrays; -1 = none).
var _t_stride := PackedInt32Array()
var _t_death_time := PackedFloat32Array()
var _t_move_ref := PackedFloat32Array()
var _t_clip_move := PackedInt32Array()
var _t_clip_idle := PackedInt32Array()
var _t_clip_attack := PackedInt32Array()
var _t_clip_death := PackedInt32Array()
var _clip_count := PackedFloat32Array()
var _clip_fps := PackedFloat32Array()
var _clip_start := PackedFloat32Array()
var _clip_loop := PackedFloat32Array()
# Rendering: per-slot animation playback.
var _anim_clip := PackedInt32Array()
var _anim_frame := PackedFloat32Array()
var _anim_speed := PackedFloat32Array()
var _anim_prev := PackedVector2Array()
var _fx: HordeFx

var _state := PackedInt32Array()
var _type := PackedInt32Array()
var _mode := PackedInt32Array()
var _pos := PackedVector2Array()
var _knock := PackedVector2Array()
var _aim := PackedVector2Array()
var _yaw := PackedFloat32Array()
var _hp := PackedFloat32Array()
var _max_hp := PackedFloat32Array()
var _flash := PackedFloat32Array()
var _timer := PackedFloat32Array()
var _cooldown := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _death := PackedFloat32Array()
## Movement factor while slowed (1 = normal) and seconds of slow remaining.
var _slow := PackedFloat32Array()
var _slow_time := PackedFloat32Array()
## Strongest burn wins; refreshes extend duration without postponing its tick.
var _burn_time := PackedFloat32Array()
var _burn_tick := PackedFloat32Array()
var _burn_damage := PackedFloat32Array()
var _exposed := PackedFloat32Array()
var _stunned := PackedFloat32Array()
var _stamp := PackedInt32Array()
var _cell_of := PackedInt32Array()
var _query_id := 0

var _active := PackedInt32Array()
var _active_count := 0
var _dying := PackedInt32Array()
var _dying_count := 0
var _free := PackedInt32Array()
var _free_count := 0
var _big := PackedInt32Array()
var _boss_index := -1

var _area := Rect2()
## Walkable XZ rectangle enemies are confined to (read-only after setup).
var play_area: Rect2:
	get:
		return _area
## Slot of the living boss, or -1.
var boss_index: int:
	get:
		return _boss_index
var _grid_w := 1
var _grid_h := 1
var _cells := 1
var _cell_start := PackedInt32Array()
var _cell_cursor := PackedInt32Array()
var _cell_items := PackedInt32Array()

# Static obstacles: circles and axis-aligned boxes, bucketed per grid cell.
var _obstacle_center := PackedVector2Array()
var _obstacle_half := PackedVector2Array()
var _obstacle_circle := PackedByteArray()
var _cell_obstacle_start := PackedInt32Array()
var _cell_obstacle_items := PackedInt32Array()

var _contact_timer := 0.0
## Pathfinding shared by every enemy; rebuilt every FLOW_INTERVAL seconds.
var _flow := HordeFlowField.new()
var _flow_timer := 0.0
const FLOW_INTERVAL := 0.2
## Within this distance enemies ignore the flow field and close in directly.
const DIRECT_RANGE := 5.0
## Heightfield sample spacing (m), built from the world's `Elevation` boxes.
const HEIGHT_STEP := 0.5
## Tallest step enemies walk up; higher steps are cliffs they can only drop off.
const CLIMB := 0.3
## Extra rise allowed per metre travelled, so ramps up to ~30 degrees stay walkable.
const CLIMB_SLOPE := 0.6
const FALL_GRAVITY := 22.0
## Vertical gap beyond which an enemy counts as on another level than the player.
const LEVEL_GAP := 1.0
## With the player this close below, enemies walk straight off ledges at them.
const DROP_RANGE := 14.0
var _rng := RandomNumberGenerator.new()
# Ground height per HEIGHT_STEP sample (row-major), and per-slot feet height.
var _heights := PackedFloat32Array()
var _heights_w := 1
var _heights_h := 1
## Horde cells whose ground and neighbourhood are all at floor level (fast path).
var _cell_flat := PackedByteArray()
var _y := PackedFloat32Array()
var _vy := PackedFloat32Array()
# Ground height of the last _walkable result (avoids a second lookup).
var _step_ground := 0.0
var _cell_center := PackedVector2Array()

var _shot_pos := PackedVector3Array()
var _shot_vel := PackedVector3Array()
var _shot_life := PackedFloat32Array()
var _shot_damage := PackedFloat32Array()
var _shot_count := 0
var _shot_renderer: MultiMeshInstance3D
var _shot_buffer := PackedFloat32Array()

var _candidate_index := PackedInt32Array()
var _candidate_t := PackedFloat32Array()
## Each synchronous splash owns its target snapshot until its callbacks return.
var _radius_buffers: Array[PackedInt32Array] = []
var _radius_depth := 0
## Shock never uses the splash/raycast/caller scratch arrays.
var _chain_index := PackedInt32Array()
var _chain_distance := PackedFloat32Array()

## `elevation` (optional) holds StaticBody3D decks and ramps, each with one
## BoxShape3D; their top faces become walkable ground for the horde.
func setup(definitions: Array[HordeEnemyDefinition], area: Rect2, obstacles: Node, player: ArenaPlayer, elevation: Node = null) -> void:
	target = player
	_area = area
	_rng.randomize()
	# Packed arrays are values: resize each member directly, never via a temp list.
	_state.resize(CAPACITY)
	_type.resize(CAPACITY)
	_mode.resize(CAPACITY)
	_stamp.resize(CAPACITY)
	_cell_of.resize(CAPACITY)
	_state.fill(FREE)
	_stamp.fill(0)
	_yaw.resize(CAPACITY)
	_hp.resize(CAPACITY)
	_max_hp.resize(CAPACITY)
	_flash.resize(CAPACITY)
	_timer.resize(CAPACITY)
	_cooldown.resize(CAPACITY)
	_phase.resize(CAPACITY)
	_death.resize(CAPACITY)
	_slow.resize(CAPACITY)
	_slow.fill(1.0)
	_slow_time.resize(CAPACITY)
	_slow_time.fill(0.0)
	_burn_time.resize(CAPACITY)
	_burn_time.fill(0.0)
	_burn_tick.resize(CAPACITY)
	_burn_tick.fill(0.0)
	_burn_damage.resize(CAPACITY)
	_burn_damage.fill(0.0)
	_exposed.resize(CAPACITY)
	_exposed.fill(0.0)
	_stunned.resize(CAPACITY)
	_stunned.fill(0.0)
	_pos.resize(CAPACITY)
	_y.resize(CAPACITY)
	_y.fill(0.0)
	_vy.resize(CAPACITY)
	_vy.fill(0.0)
	_knock.resize(CAPACITY)
	_aim.resize(CAPACITY)
	_active.resize(CAPACITY)
	_dying.resize(CAPACITY)
	_cell_items.resize(CAPACITY)
	_free.resize(CAPACITY)
	for slot in CAPACITY:
		_free[slot] = CAPACITY - 1 - slot
	_free_count = CAPACITY
	_grid_w = maxi(1, ceili(_area.size.x / CELL))
	_grid_h = maxi(1, ceili(_area.size.y / CELL))
	_cells = _grid_w * _grid_h
	_cell_start.resize(_cells + 1)
	_cell_cursor.resize(_cells)
	_candidate_index.resize(64)
	_candidate_t.resize(64)
	_radius_buffers.clear()
	_radius_depth = 0
	for depth in RADIUS_DEPTH:
		var buffer := PackedInt32Array()
		buffer.resize(CAPACITY)
		_radius_buffers.append(buffer)
	_chain_index.resize(SHOCK_TARGETS)
	_chain_distance.resize(SHOCK_TARGETS)
	var bounds := AABB(Vector3(_area.position.x - 4.0, -2.0, _area.position.y - 4.0), Vector3(_area.size.x + 8.0, 12.0, _area.size.y + 8.0))
	_setup_rendering()
	for definition in definitions:
		_register(definition, bounds)
	_read_obstacles(obstacles)
	_read_elevation(elevation)
	_cell_center.resize(_cells)
	var cell_heights := PackedFloat32Array()
	cell_heights.resize(_cells)
	for cell in _cells:
		_cell_center[cell] = _area.position + (Vector2(cell % _grid_w, cell / _grid_w) + Vector2(0.5, 0.5)) * CELL
		cell_heights[cell] = ground_height(_cell_center[cell])
	_flow.setup(_grid_w, _grid_h, _area.position, CELL, _rect_blocked, cell_heights)
	_shot_pos.resize(MAX_PROJECTILES)
	_shot_vel.resize(MAX_PROJECTILES)
	_shot_life.resize(MAX_PROJECTILES)
	_shot_damage.resize(MAX_PROJECTILES)
	var shots := MultiMesh.new()
	shots.transform_format = MultiMesh.TRANSFORM_3D
	shots.mesh = projectile_mesh
	shots.instance_count = MAX_PROJECTILES
	shots.visible_instance_count = 0
	_shot_renderer = MultiMeshInstance3D.new()
	_shot_renderer.multimesh = shots
	_shot_renderer.material_override = projectile_material
	_shot_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shot_renderer.custom_aabb = bounds
	add_child(_shot_renderer)
	_shot_buffer.resize(MAX_PROJECTILES * 12)

func _register(definition: HordeEnemyDefinition, bounds: AABB) -> void:
	if _type_of.has(definition):
		return
	_type_of[definition] = _defs.size()
	_defs.append(definition)
	_t_behavior.append(definition.behavior)
	_t_speed.append(definition.speed)
	_t_radius.append(definition.radius)
	_t_height.append(definition.height)
	_t_mass.append(maxf(0.05, definition.mass))
	_t_contact.append(definition.contact_damage)
	_t_scale.append(definition.model_scale)
	_t_boss.append(1 if definition.is_boss else 0)
	var weak_offset := definition.weak_spot_offset * definition.model_scale
	var weak_radius := definition.weak_spot_radius * definition.model_scale
	_t_weak_offset.append(weak_offset)
	_t_weak_radius_squared.append(weak_radius * weak_radius)
	_t_weak_top.append(weak_offset.y + weak_radius if weak_radius > 0.0 else 0.0)
	_register_renderer(definition, bounds)

func _setup_rendering() -> void:
	_anim_clip.resize(CAPACITY)
	_anim_clip.fill(-1)
	_anim_frame.resize(CAPACITY)
	_anim_speed.resize(CAPACITY)
	_anim_prev.resize(CAPACITY)
	if fx_scene != null and _fx == null:
		_fx = fx_scene.instantiate() as HordeFx
		add_child(_fx)
		enemy_killed.connect(_fx.burst_death)

func _register_renderer(definition: HordeEnemyDefinition, bounds: AABB) -> void:
	var animation := definition.vertex_animation
	var animated := animation != null
	var stride := 20 if animated else 16
	_t_stride.append(stride)
	_t_move_ref.append(maxf(0.1, definition.move_clip_speed * definition.model_scale))
	var move := _add_clip(animation, definition.move_clip) if animated else -1
	if animated and move < 0:
		push_warning("%s: move clip '%s' missing; using the first clip" % [definition.display_name, definition.move_clip])
		move = _add_clip(animation, animation.clips[0].name)
	_t_clip_move.append(move)
	_t_clip_idle.append(_add_clip(animation, definition.idle_clip) if animated else -1)
	_t_clip_attack.append(_add_clip(animation, definition.attack_clip) if animated else -1)
	var death := _add_clip(animation, definition.death_clip) if animated else -1
	_t_clip_death.append(death)
	_t_death_time.append(maxf(0.1, definition.death_duration) if death >= 0 else DEATH_TIME)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = animated
	multimesh.mesh = HordeMeshBaker.bake(definition, enemy_shader, animated_enemy_shader)
	multimesh.instance_count = 64
	multimesh.visible_instance_count = 0
	var renderer := MultiMeshInstance3D.new()
	renderer.name = definition.display_name
	renderer.multimesh = multimesh
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if definition.is_boss else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	renderer.custom_aabb = bounds
	add_child(renderer)
	_renderers.append(renderer)
	var buffer := PackedFloat32Array()
	buffer.resize(64 * stride)
	_buffers.append(buffer)

# Appends `clip_name` of `animation` to the clip tables; returns its id or -1.
func _add_clip(animation: HordeVertexAnimation, clip_name: StringName) -> int:
	var index := animation.find_clip(clip_name)
	if index < 0:
		return -1
	var clip := animation.clips[index]
	_clip_start.append(clip.start_frame)
	_clip_count.append(maxi(1, clip.frame_count))
	_clip_fps.append(clip.fps)
	_clip_loop.append(1.0 if clip.loop else 0.0)
	return _clip_start.size() - 1

func _read_obstacles(root: Node) -> void:
	if root != null:
		for body in root.get_children():
			if not body is StaticBody3D:
				continue
			for child in body.get_children():
				var collider := child as CollisionShape3D
				if collider == null or collider.shape == null:
					continue
				var world := (body as Node3D).global_transform * collider.transform
				var center := Vector2(world.origin.x, world.origin.z)
				if collider.shape is CylinderShape3D:
					var radius := (collider.shape as CylinderShape3D).radius * world.basis.get_scale().x
					_obstacle_center.append(center)
					_obstacle_half.append(Vector2(radius, radius))
					_obstacle_circle.append(1)
				elif collider.shape is BoxShape3D:
					# Yaw is a multiple of 90 degrees: project the box extents onto X/Z.
					var half := (collider.shape as BoxShape3D).size * 0.5
					var x_axis := world.basis.x * half.x
					var z_axis := world.basis.z * half.z
					_obstacle_center.append(center)
					_obstacle_half.append(Vector2(absf(x_axis.x) + absf(z_axis.x), absf(x_axis.z) + absf(z_axis.z)))
					_obstacle_circle.append(0)
	# Bucket obstacles into every cell their footprint (plus largest enemy) touches.
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(_cells)
	var margin := 2.0
	for index in _obstacle_center.size():
		var low := _obstacle_center[index] - _obstacle_half[index] - Vector2(margin, margin)
		var high := _obstacle_center[index] + _obstacle_half[index] + Vector2(margin, margin)
		for cz in range(_cell_z(low.y), _cell_z(high.y) + 1):
			for cx in range(_cell_x(low.x), _cell_x(high.x) + 1):
				buckets[cz * _grid_w + cx].append(index)
	_cell_obstacle_start.resize(_cells + 1)
	var total := 0
	for cell in _cells:
		_cell_obstacle_start[cell] = total
		total += buckets[cell].size()
		_cell_obstacle_items.append_array(buckets[cell])
	_cell_obstacle_start[_cells] = total

# Heightfield from the top faces of the Elevation boxes (a vertical ray against
# each oriented box), then marks horde cells that are plain floor.
func _read_elevation(root: Node) -> void:
	_heights_w = maxi(2, ceili(_area.size.x / HEIGHT_STEP))
	_heights_h = maxi(2, ceili(_area.size.y / HEIGHT_STEP))
	_heights.resize(_heights_w * _heights_h)
	_heights.fill(0.0)
	if root != null:
		for body in root.get_children():
			if not body is StaticBody3D:
				continue
			for child in body.get_children():
				var collider := child as CollisionShape3D
				if collider != null and collider.shape is BoxShape3D:
					_rasterise_box(collider.global_transform, (collider.shape as BoxShape3D).size * 0.5)
	# A flat cell has no raised sample within one sample of it, so lookups there
	# can skip interpolation entirely.
	var per := roundi(CELL / HEIGHT_STEP)
	_cell_flat.resize(_cells)
	for cell in _cells:
		var cx := cell % _grid_w
		var cz := cell / _grid_w
		var flat := 1
		for sz in range(maxi(0, cz * per - 1), mini(_heights_h, (cz + 1) * per + 1)):
			for sx in range(maxi(0, cx * per - 1), mini(_heights_w, (cx + 1) * per + 1)):
				if _heights[sz * _heights_w + sx] != 0.0:
					flat = 0
		_cell_flat[cell] = flat

func _rasterise_box(box: Transform3D, half: Vector3) -> void:
	var bounds := box * AABB(-half, half * 2.0)
	var x0 := clampi(floori((bounds.position.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var x1 := clampi(floori((bounds.end.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var z0 := clampi(floori((bounds.position.z - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	var z1 := clampi(floori((bounds.end.z - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	var inverse := box.affine_inverse()
	var down := inverse.basis * Vector3.DOWN
	var top := bounds.end.y + 1.0
	for sz in range(z0, z1 + 1):
		for sx in range(x0, x1 + 1):
			var start := inverse * Vector3(_area.position.x + (sx + 0.5) * HEIGHT_STEP, top, _area.position.y + (sz + 0.5) * HEIGHT_STEP)
			# Slab test in box space; the parameter stays in world metres.
			var enter := 0.0
			var leave := INF
			for axis in 3:
				var d := down[axis]
				if absf(d) < 0.000001:
					if absf(start[axis]) > half[axis]:
						leave = -1.0
				else:
					var t0 := (-half[axis] - start[axis]) / d
					var t1 := (half[axis] - start[axis]) / d
					enter = maxf(enter, minf(t0, t1))
					leave = minf(leave, maxf(t0, t1))
			if enter <= leave:
				var index := sz * _heights_w + sx
				_heights[index] = maxf(_heights[index], top - enter)

## Walkable ground height at `xz`: interpolated along ramps, exact at cliffs.
func ground_height(xz: Vector2) -> float:
	if _cell_flat.is_empty():
		return 0.0
	var local := xz - _area.position
	if _cell_flat[clampi(int(local.y / CELL), 0, _grid_h - 1) * _grid_w + clampi(int(local.x / CELL), 0, _grid_w - 1)] == 1:
		return 0.0
	var fx := local.x / HEIGHT_STEP - 0.5
	var fz := local.y / HEIGHT_STEP - 0.5
	var ix := clampi(floori(fx), 0, _heights_w - 2)
	var iz := clampi(floori(fz), 0, _heights_h - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var k := iz * _heights_w + ix
	var a := _heights[k]
	var b := _heights[k + 1]
	var c := _heights[k + _heights_w]
	var d := _heights[k + _heights_w + 1]
	if maxf(maxf(a, b), maxf(c, d)) - minf(minf(a, b), minf(c, d)) > CLIMB:
		if tz >= 0.5:
			return d if tx >= 0.5 else c
		return b if tx >= 0.5 else a
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

# True when the ground inside `rect` contains a cliff enemies cannot walk up.
func _rect_rough(rect: Rect2) -> bool:
	var x0 := clampi(floori((rect.position.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var x1 := clampi(floori((rect.end.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var z0 := clampi(floori((rect.position.y - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	var z1 := clampi(floori((rect.end.y - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	for sz in range(z0, z1 + 1):
		for sx in range(x0, x1 + 1):
			var k := sz * _heights_w + sx
			var h := _heights[k]
			if (sx > 0 and absf(_heights[k - 1] - h) > CLIMB) \
					or (sx < _heights_w - 1 and absf(_heights[k + 1] - h) > CLIMB) \
					or (sz > 0 and absf(_heights[k - _heights_w] - h) > CLIMB) \
					or (sz < _heights_h - 1 and absf(_heights[k + _heights_w] - h) > CLIMB):
				return true
	return false

func _cell_x(x: float) -> int:
	return clampi(int((x - _area.position.x) / CELL), 0, _grid_w - 1)

func _cell_z(z: float) -> int:
	return clampi(int((z - _area.position.y) / CELL), 0, _grid_h - 1)

# ---------------------------------------------------------------- spawning

func spawn(definition: HordeEnemyDefinition, xz: Vector2, health_multiplier := 1.0) -> int:
	if _free_count == 0:
		return -1
	var type: int = _type_of[definition]
	_free_count -= 1
	var slot := _free[_free_count]
	var radius := _t_radius[type]
	xz.x = clampf(xz.x, _area.position.x + radius, _area.end.x - radius)
	xz.y = clampf(xz.y, _area.position.y + radius, _area.end.y - radius)
	_state[slot] = ALIVE
	_type[slot] = type
	_mode[slot] = Mode.SEEK
	_pos[slot] = xz
	_y[slot] = ground_height(xz)
	_vy[slot] = 0.0
	_knock[slot] = Vector2.ZERO
	_hp[slot] = definition.max_health * health_multiplier
	_max_hp[slot] = _hp[slot]
	_flash[slot] = 0.0
	_cooldown[slot] = _rng.randf_range(0.5, definition.attack_cooldown)
	_slow[slot] = 1.0
	_slow_time[slot] = 0.0
	_burn_time[slot] = 0.0
	_burn_tick[slot] = 0.0
	_burn_damage[slot] = 0.0
	_exposed[slot] = 0.0
	_stunned[slot] = 0.0
	_phase[slot] = _rng.randf() * TAU
	_yaw[slot] = _rng.randf() * TAU
	_active[_active_count] = slot
	_active_count += 1
	alive_count += 1
	if radius > BIG_RADIUS:
		_big.append(slot)
	if definition.is_boss:
		_boss_index = slot
		boss_spawned.emit(definition)
		boss_health_changed.emit(_hp[slot], _max_hp[slot])
	_reset_animation(slot)
	return slot

## True when a disc at xz would overlap an obstacle or leave the play area.
func is_blocked(xz: Vector2, radius: float) -> bool:
	if not _area.grow(-radius).has_point(xz):
		return true
	var cell := _cell_z(xz.y) * _grid_w + _cell_x(xz.x)
	for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
		var o := _cell_obstacle_items[k]
		var delta := xz - _obstacle_center[o]
		var half := _obstacle_half[o]
		if _obstacle_circle[o] == 1:
			if delta.length() < half.x + radius:
				return true
		elif absf(delta.x) < half.x + radius and absf(delta.y) < half.y + radius:
			return true
	return false

# True when any obstacle or cliff overlaps `rect` (used to rasterise the flow field).
func _rect_blocked(rect: Rect2) -> bool:
	if _rect_rough(rect):
		return true
	var center := rect.get_center()
	var cell := _cell_z(center.y) * _grid_w + _cell_x(center.x)
	for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
		var o := _cell_obstacle_items[k]
		var c := _obstacle_center[o]
		var half := _obstacle_half[o]
		if _obstacle_circle[o] == 1:
			var closest := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
			if closest.distance_squared_to(c) < half.x * half.x:
				return true
		elif Rect2(c - half, half * 2.0).intersects(rect):
			return true
	return false

## Removes every enemy without rewards (stage clear).
func clear() -> void:
	for a in _active_count:
		var slot := _active[a]
		if _state[slot] == ALIVE:
			_begin_death(slot)
	_active_count = 0
	alive_count = 0
	_shot_count = 0

# ---------------------------------------------------------------- queries

## Slows an enemy's movement (including charges) to `factor` for `duration`
## seconds. The strongest active slow wins; the longest duration is kept.
func slow(index: int, factor: float, duration: float) -> void:
	if not is_alive(index):
		return
	if _slow_time[index] <= 0.0:
		_slow[index] = 1.0
	_slow[index] = minf(_slow[index], clampf(factor, 0.0, 1.0))
	_slow_time[index] = maxf(_slow_time[index], duration)

## Tag Burst creates a cross-gun damage window, never a permanent multiplier.
func expose(index: int, duration: float) -> void:
	if is_alive(index):
		_exposed[index] = maxf(_exposed[index], duration)

func is_exposed(index: int) -> bool:
	return is_alive(index) and _exposed[index] > 0.0

## Bosses get a short stagger; regular enemies stop attacks as well as movement.
func stun(index: int, duration: float) -> void:
	if is_alive(index):
		_stunned[index] = maxf(_stunned[index], duration * (0.25 if _t_boss[_type[index]] != 0 else 1.0))

func is_stunned(index: int) -> bool:
	return is_alive(index) and _stunned[index] > 0.0

func is_alive(index: int) -> bool:
	return index >= 0 and index < CAPACITY and _state[index] == ALIVE

## Fraction of current health for a live slot, for precise finishing effects.
func enemy_health_fraction(index: int) -> float:
	if not is_alive(index):
		return 0.0
	return _hp[index] / maxf(1.0, _max_hp[index])

func enemy_position(index: int) -> Vector3:
	var p := _pos[index]
	return Vector3(p.x, _y[index] + _t_height[_type[index]] * 0.5, p.y)

func get_definition(index: int) -> HordeEnemyDefinition:
	return _defs[_type[index]]

## Uses the same feet position, scale and yaw as the rendered enemy.
func weak_spot_position(index: int) -> Vector3:
	var offset := _t_weak_offset[_type[index]]
	var yaw := _yaw[index]
	var c := cos(yaw)
	var s := sin(yaw)
	var p := _pos[index]
	return Vector3(p.x + offset.x * c + offset.z * s, _y[index] + offset.y, p.y - offset.x * s + offset.z * c)

## A normalized gun ray must intersect the head/core before the world blocker.
func weak_spot_hit(index: int, origin: Vector3, direction: Vector3, max_distance: float) -> bool:
	if not is_alive(index):
		return false
	var radius_squared := _t_weak_radius_squared[_type[index]]
	if radius_squared <= 0.0:
		return false
	var offset := weak_spot_position(index) - origin
	var distance := clampf(offset.dot(direction), 0.0, max_distance)
	return (offset - direction * distance).length_squared() <= radius_squared

func query_radius(center: Vector3, radius: float, out: PackedInt32Array) -> int:
	_query_id += 1
	var c := Vector2(center.x, center.z)
	var count := 0
	var reach := radius + 1.0
	for cz in range(_cell_z(c.y - reach), _cell_z(c.y + reach) + 1):
		for cx in range(_cell_x(c.x - reach), _cell_x(c.x + reach) + 1):
			var cell := cz * _grid_w + cx
			for k in range(_cell_start[cell], _cell_start[cell + 1]):
				count = _collect_in_radius(_cell_items[k], c, center.y, radius, out, count)
	for slot in _big:
		count = _collect_in_radius(slot, c, center.y, radius, out, count)
	return count

# Discs in XZ, skipping bodies on a clearly different level than `cy`.
func _collect_in_radius(slot: int, c: Vector2, cy: float, radius: float, out: PackedInt32Array, count: int) -> int:
	if _state[slot] != ALIVE or _stamp[slot] == _query_id:
		return count
	_stamp[slot] = _query_id
	var r := radius + _t_radius[_type[slot]]
	if (_pos[slot] - c).length_squared() > r * r:
		return count
	var half := _t_height[_type[slot]] * 0.5
	if absf(_y[slot] + half - cy) > radius + half + LEVEL_GAP:
		return count
	if count >= out.size():
		out.resize(maxi(16, out.size() * 2))
	out[count] = slot
	return count + 1

func nearest(center: Vector3, max_radius: float) -> int:
	var c := Vector2(center.x, center.z)
	var best := -1
	var best_d2 := max_radius * max_radius
	var cx0 := _cell_x(c.x)
	var cz0 := _cell_z(c.y)
	var rings := ceili(max_radius / CELL) + 1
	for ring in rings:
		# Cells on this ring are at least (ring - 1) * CELL away.
		if best >= 0 and pow(maxf(0.0, (ring - 1) * CELL), 2.0) > best_d2:
			break
		for cz in range(cz0 - ring, cz0 + ring + 1):
			if cz < 0 or cz >= _grid_h:
				continue
			var edge := cz == cz0 - ring or cz == cz0 + ring
			var step := 1 if edge else ring * 2
			var cx := cx0 - ring
			while cx <= cx0 + ring:
				if cx >= 0 and cx < _grid_w:
					var cell := cz * _grid_w + cx
					for k in range(_cell_start[cell], _cell_start[cell + 1]):
						var slot := _cell_items[k]
						if _state[slot] != ALIVE:
							continue
						var d2 := (_pos[slot] - c).length_squared()
						if d2 < best_d2:
							best_d2 = d2
							best = slot
				cx += maxi(1, step)
	for slot in _big:
		if _state[slot] == ALIVE and (_pos[slot] - c).length_squared() < best_d2:
			best_d2 = (_pos[slot] - c).length_squared()
			best = slot
	return best

## Ray against enemy cylinders; writes up to max_hits nearest hits.
func raycast(origin: Vector3, direction: Vector3, max_distance: float, max_hits: int, out_hits: PackedInt32Array, out_distances: PackedFloat32Array) -> int:
	_query_id += 1
	var candidates := 0
	var h := Vector2(direction.x, direction.z)
	var o := Vector2(origin.x, origin.z)
	for slot in _big:
		candidates = _ray_test(slot, origin, direction, o, h, max_distance, candidates)
	var cx := _cell_x(o.x)
	var cz := _cell_z(o.y)
	var step_x := 1 if h.x > 0.0 else -1
	var step_z := 1 if h.y > 0.0 else -1
	var local := o - _area.position
	var next_x := INF if absf(h.x) < 0.00001 else ((cx + (1 if step_x > 0 else 0)) * CELL - local.x) / h.x
	var next_z := INF if absf(h.y) < 0.00001 else ((cz + (1 if step_z > 0 else 0)) * CELL - local.y) / h.y
	var delta_x := INF if absf(h.x) < 0.00001 else CELL / absf(h.x)
	var delta_z := INF if absf(h.y) < 0.00001 else CELL / absf(h.y)
	var entered := 0.0
	# Neighbor cells are included so bodies overlapping a cell edge still hit.
	while entered <= max_distance:
		for nz in range(maxi(0, cz - 1), mini(_grid_h, cz + 2)):
			for nx in range(maxi(0, cx - 1), mini(_grid_w, cx + 2)):
				var cell := nz * _grid_w + nx
				for k in range(_cell_start[cell], _cell_start[cell + 1]):
					candidates = _ray_test(_cell_items[k], origin, direction, o, h, max_distance, candidates)
		if candidates >= max_hits and _kth_smallest(candidates, max_hits) < entered - CELL:
			break
		if next_x < next_z:
			cx += step_x
			entered = next_x
			next_x += delta_x
		else:
			cz += step_z
			entered = next_z
			next_z += delta_z
		if cx < 0 or cz < 0 or cx >= _grid_w or cz >= _grid_h or (next_x == INF and next_z == INF):
			break
	# Selection-sort the nearest max_hits candidates into the outputs.
	var hits := mini(candidates, max_hits)
	if out_hits.size() < hits:
		out_hits.resize(hits)
	if out_distances.size() < hits:
		out_distances.resize(hits)
	for n in hits:
		var best := n
		for m in range(n + 1, candidates):
			if _candidate_t[m] < _candidate_t[best]:
				best = m
		var t := _candidate_t[best]
		var slot := _candidate_index[best]
		_candidate_t[best] = _candidate_t[n]
		_candidate_index[best] = _candidate_index[n]
		_candidate_t[n] = t
		_candidate_index[n] = slot
		out_hits[n] = slot
		out_distances[n] = t
	return hits

func _kth_smallest(count: int, k: int) -> float:
	# Upper bound of the k nearest: the largest of the first k after partial scan.
	var worst := 0.0
	var taken := 0
	var threshold := -INF
	while taken < k:
		var best := INF
		for m in count:
			if _candidate_t[m] > threshold and _candidate_t[m] < best:
				best = _candidate_t[m]
		threshold = best
		worst = best
		taken += 1
	return worst

func _ray_test(slot: int, origin: Vector3, direction: Vector3, o: Vector2, h: Vector2, max_distance: float, candidates: int) -> int:
	if _state[slot] != ALIVE or _stamp[slot] == _query_id:
		return candidates
	_stamp[slot] = _query_id
	var type := _type[slot]
	var radius := _t_radius[type] + 0.08
	var m := o - _pos[slot]
	var a := h.length_squared()
	var c := m.length_squared() - radius * radius
	var t := 0.0
	var t_exit := max_distance
	if a < 0.000001:
		if c > 0.0:
			return candidates
	else:
		var b := m.dot(h)
		var disc := b * b - a * c
		if disc < 0.0:
			return candidates
		var root := sqrt(disc)
		t = (-b - root) / a
		t_exit = (-b + root) / a
		if t_exit < 0.0:
			return candidates
		t = maxf(t, 0.0)
	if t > max_distance:
		return candidates
	var y_enter := origin.y + direction.y * t
	var y_exit := origin.y + direction.y * minf(t_exit, max_distance)
	var base := _y[slot]
	var top := base + maxf(_t_height[type] + hit_headroom, _t_weak_top[type])
	if minf(y_enter, y_exit) > top or maxf(y_enter, y_exit) < base:
		return candidates
	if y_enter > top and direction.y < 0.0:
		t = (top - origin.y) / direction.y
	elif y_enter < base and direction.y > 0.0:
		t = (base - origin.y) / direction.y
	if candidates >= _candidate_t.size():
		_candidate_t.resize(candidates * 2)
		_candidate_index.resize(candidates * 2)
	_candidate_index[candidates] = slot
	_candidate_t[candidates] = t
	return candidates + 1

## Positions for radar display, sampled evenly across the living crowd.
func sample_positions(out: PackedVector2Array, max_count: int) -> int:
	var stride := maxi(1, ceili(float(_active_count) / max_count))
	var count := 0
	var a := 0
	while a < _active_count and count < max_count:
		var slot := _active[a]
		if _state[slot] == ALIVE:
			if count >= out.size():
				out.resize(max_count)
			out[count] = _pos[slot]
			count += 1
		a += stride
	return count

# ---------------------------------------------------------------- damage

func damage(index: int, amount: float, knockback := Vector3.ZERO, damage_type: int = 0, critical: bool = false) -> bool:
	if not is_alive(index) or amount <= 0.0:
		return false
	var at := enemy_position(index)
	var killed := _deal_damage(index, amount, knockback, damage_type, critical)
	match damage_type:
		DamageType.Kind.FIRE:
			if is_alive(index):
				if _burn_time[index] <= 0.0:
					_burn_tick[index] = BURN_TICK
				_burn_time[index] = BURN_DURATION
				_burn_damage[index] = maxf(_burn_damage[index], amount * 0.15)
		DamageType.Kind.FROST:
			slow(index, FROST_FACTOR, FROST_DURATION)
		DamageType.Kind.SHOCK:
			_chain_shock(index, at, amount * 0.4, critical)
	return killed

## Shared health/reward path, deliberately without secondary type effects.
func _deal_damage(index: int, amount: float, knockback: Vector3, damage_type: int, critical: bool) -> bool:
	if not is_alive(index) or amount <= 0.0:
		return false
	var before := _hp[index]
	if _exposed[index] > 0.0:
		amount *= 1.35
	_hp[index] = maxf(0.0, before - minf(amount, before))
	# Report the stored HP delta, including packed-float rounding.
	var removed := before - _hp[index]
	if removed <= 0.0:
		return false
	var at := enemy_position(index)
	var definition := _defs[_type[index]]
	var was_boss := index == _boss_index
	_flash[index] = 1.0
	_knock[index] += Vector2(knockback.x, knockback.z) / _t_mass[_type[index]]
	var killed := _hp[index] <= 0.0
	if killed:
		_begin_death(index)
		alive_count -= 1
		if was_boss:
			_boss_index = -1
	if was_boss:
		boss_health_changed.emit(_hp[index], _max_hp[index])
	damage_reported.emit(at, removed, damage_type, critical, killed)
	if killed:
		enemy_killed.emit(definition, at)
		if was_boss:
			boss_killed.emit()
	elif _fx != null:
		_fx.burst_hit(definition, at)
	return killed

## One-hop conduction to the three closest targets among at most 96 local
## grid entries. Fixed candidate storage keeps crowd-density work bounded.
func _chain_shock(source: int, center: Vector3, amount: float, critical: bool) -> void:
	var c := Vector2(center.x, center.z)
	_chain_index.fill(-1)
	_chain_distance.fill(INF)
	var checks := 0
	for cz in range(_cell_z(c.y - SHOCK_RADIUS), _cell_z(c.y + SHOCK_RADIUS) + 1):
		for cx in range(_cell_x(c.x - SHOCK_RADIUS), _cell_x(c.x + SHOCK_RADIUS) + 1):
			var cell := cz * _grid_w + cx
			for k in range(_cell_start[cell], _cell_start[cell + 1]):
				if checks >= SHOCK_CHECKS:
					break
				checks += 1
				var slot := _cell_items[k]
				if slot == source or not is_alive(slot):
					continue
				var d2 := enemy_position(slot).distance_squared_to(center)
				if d2 > SHOCK_RADIUS * SHOCK_RADIUS:
					continue
				for rank in SHOCK_TARGETS:
					if d2 < _chain_distance[rank]:
						for shift in range(SHOCK_TARGETS - 1, rank, -1):
							_chain_index[shift] = _chain_index[shift - 1]
							_chain_distance[shift] = _chain_distance[shift - 1]
						_chain_index[rank] = slot
						_chain_distance[rank] = d2
						break
			if checks >= SHOCK_CHECKS:
				break
		if checks >= SHOCK_CHECKS:
			break
	# Capture all three before emitting signals: a synchronous callback can
	# start another shock and overwrite the selection scratch.
	var first := _chain_index[0]
	var second := _chain_index[1]
	var third := _chain_index[2]
	if first >= 0:
		_deal_damage(first, amount, Vector3.ZERO, DamageType.Kind.SHOCK, critical)
	if second >= 0:
		_deal_damage(second, amount, Vector3.ZERO, DamageType.Kind.SHOCK, critical)
	if third >= 0:
		_deal_damage(third, amount, Vector3.ZERO, DamageType.Kind.SHOCK, critical)

func _update_burns(delta: float) -> void:
	# Death only marks slots here; compacting stays in _rebuild_grid afterward.
	# Thus a DOT kill cannot swap a survivor past this iteration.
	for a in _active_count:
		var slot := _active[a]
		if not is_alive(slot) or _burn_time[slot] <= 0.0:
			continue
		var elapsed := minf(delta, _burn_time[slot])
		_burn_time[slot] = maxf(0.0, _burn_time[slot] - delta)
		_burn_tick[slot] -= elapsed
		while _burn_tick[slot] <= 0.00001 and is_alive(slot):
			_burn_tick[slot] += BURN_TICK
			_deal_damage(slot, _burn_damage[slot], Vector3.ZERO, DamageType.Kind.FIRE, false)
		if _burn_time[slot] <= 0.0:
			_burn_damage[slot] = 0.0
			_burn_tick[slot] = 0.0

func damage_radius(center: Vector3, radius: float, amount: float, knockback_strength := 0.0, damage_type: int = 0, critical: bool = false) -> int:
	if amount <= 0.0:
		return 0
	if _radius_depth >= RADIUS_DEPTH:
		# Exceptional deeper callback nesting scans slots directly. It remains
		# bounded by CAPACITY and cannot overwrite an ancestor's target list.
		return _damage_radius_scan(center, radius, amount, knockback_strength, damage_type, critical)
	var depth := _radius_depth
	_radius_depth += 1
	var buffer := _radius_buffers[depth]
	# Packed arrays use copy-on-write; detach while this invocation owns it.
	_radius_buffers[depth] = PackedInt32Array()
	var count := query_radius(center, radius, buffer)
	var damaged := 0
	var c := Vector2(center.x, center.z)
	for n in count:
		damaged += _damage_radius_slot(buffer[n], c, amount, knockback_strength, damage_type, critical)
	_radius_buffers[depth] = buffer
	_radius_depth -= 1
	return damaged

func _damage_radius_slot(slot: int, center: Vector2, amount: float, knockback_strength: float, damage_type: int, critical: bool) -> int:
	if not is_alive(slot):
		return 0
	var away := _pos[slot] - center
	var push := Vector3.ZERO
	if knockback_strength > 0.0 and away.length_squared() > 0.0001:
		away = away.normalized() * knockback_strength
		push = Vector3(away.x, 0.0, away.y)
	var before := _hp[slot]
	damage(slot, amount, push, damage_type, critical)
	return 1 if _hp[slot] < before else 0

func _damage_radius_scan(center: Vector3, radius: float, amount: float, knockback_strength: float, damage_type: int, critical: bool) -> int:
	var c := Vector2(center.x, center.z)
	var damaged := 0
	for slot in CAPACITY:
		if not is_alive(slot):
			continue
		var reach := radius + _t_radius[_type[slot]]
		if _pos[slot].distance_squared_to(c) > reach * reach:
			continue
		var half := _t_height[_type[slot]] * 0.5
		if absf(_y[slot] + half - center.y) > radius + half + LEVEL_GAP:
			continue
		damaged += _damage_radius_slot(slot, c, amount, knockback_strength, damage_type, critical)
	return damaged

func _begin_death(slot: int) -> void:
	_state[slot] = DYING
	_slow[slot] = 1.0
	_slow_time[slot] = 0.0
	_burn_time[slot] = 0.0
	_burn_tick[slot] = 0.0
	_burn_damage[slot] = 0.0
	_death[slot] = _t_death_time[_type[slot]]
	_flash[slot] = 1.0
	_dying[_dying_count] = slot
	_dying_count += 1
	if _t_radius[_type[slot]] > BIG_RADIUS:
		var at := _big.find(slot)
		if at >= 0:
			_big.remove_at(at)

# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	_update_burns(delta)
	_rebuild_grid()
	_flow_timer -= delta
	if _flow_timer <= 0.0 and is_instance_valid(target):
		_flow_timer = FLOW_INTERVAL
		_flow.update(Vector2(target.global_position.x, target.global_position.z), target.global_position.y - 0.9)
	var chasing := is_instance_valid(target) and target.active
	var player := Vector2.ZERO
	var player_y := 0.0
	if is_instance_valid(target):
		player = Vector2(target.global_position.x, target.global_position.z)
		player_y = target.global_position.y - 0.9
	var contact := 0.0
	var knock_decay := minf(1.0, 7.0 * delta)
	var turn := minf(1.0, 10.0 * delta)
	var origin := _area.position
	var inverse_cell := 1.0 / CELL
	var last_x := _grid_w - 1
	var last_z := _grid_h - 1
	for a in _active_count:
		var i := _active[a]
		if not is_alive(i):
			continue
		_exposed[i] = maxf(0.0, _exposed[i] - delta)
		var stunned := _stunned[i] > 0.0
		_stunned[i] = maxf(0.0, _stunned[i] - delta)
		var type := _type[i]
		var p := _pos[i]
		var to := player - p
		var distance := to.length()
		var direction := to / distance if distance > 0.001 else Vector2.ZERO
		var radius := _t_radius[type]
		var reach := radius + PLAYER_RADIUS
		var move := Vector2.ZERO
		var rise := player_y - _y[i]
		# Follow the flow field (around walls, up ramps) unless close on the same
		# level, or with the player below within DROP_RANGE: then go straight in,
		# walking off ledges and falling.
		var route := direction
		var straight := (distance <= DIRECT_RANGE and rise <= LEVEL_GAP) or (rise < -LEVEL_GAP and distance <= DROP_RANGE)
		if not straight:
			var cell := _cell_of[i]
			var flow := _flow.direction_at(cell, _y[i])
			if flow != Vector2.ZERO:
				# Drift toward the cell's centre line (sideways only): obstacles can
				# poke into a cell's edge, and a body there would push straight into
				# the face. A slight pull toward the player smooths crowds on one
				# level; with the player up on a deck it drags bodies into corners.
				var offset := _cell_center[cell] - p
				var side := Vector2(-flow.y, flow.x)
				var steer := flow + side * (side.dot(offset) * 0.5)
				if rise <= LEVEL_GAP:
					steer += direction * 0.25
				route = steer.normalized()
		var face := route
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta / FLASH_TIME)
		if chasing and not stunned:
			move = _steer(i, type, route, direction, distance, delta)
			if _mode[i] == Mode.CHARGE:
				face = _aim[i]
			var touching := distance < reach + 0.15 and rise < _t_height[type] and rise > -1.9
			if touching:
				contact += _t_contact[type]
				if _mode[i] == Mode.CHARGE:
					target.take_damage(ceili(_t_contact[type] * 2.0))
					_end_charge(i, type)
			if distance < reach and _mode[i] != Mode.CHARGE:
				move = Vector2.ZERO
		if _slow_time[i] > 0.0:
			_slow_time[i] -= delta
			move *= _slow[i]
		p += (move + _knock[i]) * delta + _separation(i, p, radius)
		_knock[i] -= _knock[i] * knock_decay
		var clamped := _constrain(p, radius)
		var feet := _y[i]
		var landing := clampi(int((clamped.y - origin.y) * inverse_cell), 0, last_z) * _grid_w \
				+ clampi(int((clamped.x - origin.x) * inverse_cell), 0, last_x)
		# Floor to plain floor (most of the crowd) needs no height work.
		if feet != 0.0 or _cell_flat[landing] == 0:
			clamped = _walkable(i, _pos[i], clamped)
			# Walk up ramps at once; fall off ledges under gravity.
			if feet > _step_ground + 0.001:
				_vy[i] -= FALL_GRAVITY * delta
				_y[i] = maxf(_step_ground, feet + _vy[i] * delta)
			else:
				_y[i] = _step_ground
				_vy[i] = 0.0
		if _mode[i] == Mode.CHARGE and not clamped.is_equal_approx(p):
			_end_charge(i, type)
		_pos[i] = clamped
		if face != Vector2.ZERO:
			_yaw[i] = lerp_angle(_yaw[i], atan2(-face.x, -face.y), turn)
	_update_dying(delta)
	_update_projectiles(delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if chasing and contact > 0.0 and _contact_timer <= 0.0:
		_contact_timer = contact_tick
		target.take_damage(ceili(minf(contact, contact_cap)))

## Accepts a move unless it climbs a cliff; then slides along one axis or stays.
func _walkable(i: int, from: Vector2, to: Vector2) -> Vector2:
	var limit := _y[i] + CLIMB + from.distance_to(to) * CLIMB_SLOPE
	_step_ground = ground_height(to)
	if _step_ground <= limit:
		return to
	var slide := Vector2(to.x, from.y)
	_step_ground = ground_height(slide)
	if _step_ground <= limit:
		return slide
	slide = Vector2(from.x, to.y)
	_step_ground = ground_height(slide)
	if _step_ground <= limit:
		return slide
	_step_ground = ground_height(from)
	return from

## `route` is the path direction (flow field); `direct` points straight at the
## player and is used for aiming attacks and backing off.
func _steer(i: int, type: int, route: Vector2, direct: Vector2, distance: float, delta: float) -> Vector2:
	var definition := _defs[type]
	var behavior := _t_behavior[type]
	_cooldown[i] = maxf(0.0, _cooldown[i] - delta)
	match _mode[i]:
		Mode.WINDUP:
			_timer[i] -= delta
			if _timer[i] <= 0.0:
				_cooldown[i] = definition.attack_cooldown
				if behavior == HordeEnemyDefinition.Behavior.RANGED:
					_fire(i, type)
					_mode[i] = Mode.SEEK
				else:
					_mode[i] = Mode.CHARGE
					_aim[i] = direct
					_timer[i] = definition.charge_duration
			return Vector2.ZERO
		Mode.CHARGE:
			_timer[i] -= delta
			if _timer[i] <= 0.0:
				_mode[i] = Mode.SEEK
			return _aim[i] * definition.charge_speed
	var move := route * _t_speed[type]
	if behavior == HordeEnemyDefinition.Behavior.RANGED:
		if distance < definition.preferred_range - 1.5:
			move = -direct * _t_speed[type] * 0.7
		elif distance < definition.preferred_range + 1.5:
			move = Vector2.ZERO
		if _cooldown[i] <= 0.0 and distance <= definition.attack_range:
			_mode[i] = Mode.WINDUP
			_timer[i] = definition.telegraph_duration
	elif behavior == HordeEnemyDefinition.Behavior.CHARGER:
		if _cooldown[i] <= 0.0 and distance <= definition.charge_range and distance > 2.0:
			_mode[i] = Mode.WINDUP
			_timer[i] = definition.telegraph_duration
			return Vector2.ZERO
	return move

func _end_charge(i: int, type: int) -> void:
	_mode[i] = Mode.SEEK
	_cooldown[i] = _defs[type].attack_cooldown

func _separation(i: int, p: Vector2, radius: float) -> Vector2:
	var push := Vector2.ZERO
	var checks := 0
	var feet := _y[i]
	var cell := _cell_of[i]
	var cx := cell % _grid_w
	var cz := cell / _grid_w
	for nz in range(maxi(0, cz - 1), mini(_grid_h, cz + 2)):
		for nx in range(maxi(0, cx - 1), mini(_grid_w, cx + 2)):
			var neighbor := nz * _grid_w + nx
			for k in range(_cell_start[neighbor], _cell_start[neighbor + 1]):
				var j := _cell_items[k]
				if j == i:
					continue
				var away := p - _pos[j]
				var d2 := away.length_squared()
				var reach := radius + _t_radius[_type[j]]
				# Bodies on another level (deck above, floor below) never shove.
				if d2 < reach * reach and absf(feet - _y[j]) <= LEVEL_GAP:
					if d2 < 0.000001:
						away = Vector2(float(i & 7) - 3.5, float(j & 7) - 3.5)
						d2 = away.length_squared()
					var d := sqrt(d2)
					# Heavier neighbors shove harder.
					push += away * ((reach - d) / d) * minf(2.0, _t_mass[_type[j]] / _t_mass[_type[i]])
				checks += 1
				if checks >= MAX_NEIGHBOR_CHECKS:
					return (push * SEPARATION).limit_length(0.25)
	return (push * SEPARATION).limit_length(0.25)

func _constrain(p: Vector2, radius: float) -> Vector2:
	p.x = clampf(p.x, _area.position.x + radius, _area.end.x - radius)
	p.y = clampf(p.y, _area.position.y + radius, _area.end.y - radius)
	var cell := _cell_z(p.y) * _grid_w + _cell_x(p.x)
	for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
		var o := _cell_obstacle_items[k]
		var center := _obstacle_center[o]
		var half := _obstacle_half[o]
		var delta := p - center
		if _obstacle_circle[o] == 1:
			var reach := half.x + radius
			var d2 := delta.length_squared()
			if d2 < reach * reach:
				p = center + (delta / sqrt(d2) if d2 > 0.000001 else Vector2.RIGHT) * reach
		else:
			var gap_x := half.x + radius - absf(delta.x)
			var gap_z := half.y + radius - absf(delta.y)
			if gap_x > 0.0 and gap_z > 0.0:
				if gap_x < gap_z:
					p.x += gap_x * signf(delta.x if delta.x != 0.0 else 1.0)
				else:
					p.y += gap_z * signf(delta.y if delta.y != 0.0 else 1.0)
	return p

func _rebuild_grid() -> void:
	_cell_cursor.fill(0)
	var n := 0
	for a in _active_count:
		var slot := _active[a]
		if _state[slot] != ALIVE:
			continue
		_active[n] = slot
		n += 1
		var p := _pos[slot]
		var cell := _cell_z(p.y) * _grid_w + _cell_x(p.x)
		_cell_of[slot] = cell
		_cell_cursor[cell] += 1
	_active_count = n
	var total := 0
	for cell in _cells:
		_cell_start[cell] = total
		var count := _cell_cursor[cell]
		_cell_cursor[cell] = total
		total += count
	_cell_start[_cells] = total
	for a in n:
		var slot := _active[a]
		var cell := _cell_of[slot]
		_cell_items[_cell_cursor[cell]] = slot
		_cell_cursor[cell] += 1

func _update_dying(delta: float) -> void:
	var n := 0
	for d in _dying_count:
		var slot := _dying[d]
		_death[slot] -= delta
		if _death[slot] > 0.0:
			_dying[n] = slot
			n += 1
		else:
			_state[slot] = FREE
			_free[_free_count] = slot
			_free_count += 1
	_dying_count = n

# ---------------------------------------------------------------- projectiles

func _fire(i: int, type: int) -> void:
	if _shot_count >= MAX_PROJECTILES or not is_instance_valid(target):
		return
	var definition := _defs[type]
	var from := Vector3(_pos[i].x, _y[i] + _t_height[type] * 0.7, _pos[i].y)
	var aim := target.global_position + Vector3(0.0, 0.2, 0.0) - from
	_shot_pos[_shot_count] = from
	_shot_vel[_shot_count] = aim.normalized() * definition.projectile_speed
	_shot_life[_shot_count] = 30.0 / maxf(1.0, definition.projectile_speed) + 1.0
	_shot_damage[_shot_count] = definition.projectile_damage
	_shot_count += 1

func _update_projectiles(delta: float) -> void:
	if not is_instance_valid(target) or not target.active:
		_shot_count = 0
		return
	var center := target.global_position
	var hit_reach := projectile_radius + PLAYER_RADIUS
	var n := 0
	for s in _shot_count:
		var p := _shot_pos[s] + _shot_vel[s] * delta
		var life := _shot_life[s] - delta
		var closest := Vector3(center.x, clampf(p.y, center.y - 0.9, center.y + 0.9), center.z)
		if p.distance_squared_to(closest) < hit_reach * hit_reach:
			target.take_damage(ceili(_shot_damage[s]))
			continue
		if life <= 0.0 or p.y < ground_height(Vector2(p.x, p.z)) or is_blocked(Vector2(p.x, p.z), 0.0):
			continue
		_shot_pos[n] = p
		_shot_vel[n] = _shot_vel[s]
		_shot_life[n] = life
		_shot_damage[n] = _shot_damage[s]
		n += 1
	_shot_count = n

# ---------------------------------------------------------------- rendering

func _process(delta: float) -> void:
	var player := Vector2(INF, INF)
	if is_instance_valid(target):
		player = Vector2(target.global_position.x, target.global_position.z)
	for type in _defs.size():
		_draw_type(type, delta, player)
	_draw_projectiles()

func _draw_type(type: int, delta: float, player: Vector2) -> void:
	var renderer := _renderers[type]
	var multimesh := renderer.multimesh
	var buffer := _buffers[type]
	# Detach from the array so writes do not copy-on-write the shared data.
	_buffers[type] = PackedFloat32Array()
	var stride := _t_stride[type]
	var animated := stride == 20
	var needed := 0
	for a in _active_count:
		if _type[_active[a]] == type and _state[_active[a]] == ALIVE:
			needed += 1
	for d in _dying_count:
		if _type[_dying[d]] == type:
			needed += 1
	if needed > multimesh.instance_count:
		var capacity := multimesh.instance_count
		while capacity < needed:
			capacity *= 2
		multimesh.instance_count = mini(capacity, CAPACITY)
		buffer.resize(multimesh.instance_count * stride)
	var scale := _t_scale[type]
	var reach := _t_radius[type] + PLAYER_RADIUS + CONTACT_ANIMATION_MARGIN
	var reach2 := reach * reach
	var k := 0
	for a in _active_count:
		var slot := _active[a]
		if _type[slot] == type and _state[slot] == ALIVE:
			k = _write_instance(buffer, k, slot, scale, scale, _flash[slot], stride)
			if animated:
				_animate(buffer, k - 8, slot, type, delta, _pos[slot].distance_squared_to(player) < reach2)
	var death_clip := _t_clip_death[type]
	var duration := _t_death_time[type]
	for d in _dying_count:
		var slot := _dying[d]
		if _type[slot] != type:
			continue
		var left := _death[slot] / duration
		if death_clip >= 0:
			# Play the death clip over most of the time, then shrink away quickly.
			var fade := clampf(left / DEATH_FADE, 0.02, 1.0)
			k = _write_instance(buffer, k, slot, scale * fade, scale * fade, 0.35 * left * left, stride)
			var progress := minf(1.0, (1.0 - left) / (1.0 - DEATH_FADE))
			_write_clip(buffer, k - 8, death_clip, progress * (_clip_count[death_clip] - 1.0), 0.0)
			continue
		# Collapse inward: slight widen on impact, then shrink away to nothing.
		var widen := 1.0 + 0.15 * sin(left * PI)
		# Dying bodies glow faintly and fade with their collapse; mass kills
		# must not paint the view white.
		k = _write_instance(buffer, k, slot, scale * maxf(0.02, left) * widen, scale * maxf(0.02, left * left), 0.35 * left, stride)
		if animated:
			# Freeze the pose the enemy died in.
			var clip := _anim_clip[slot] if _anim_clip[slot] >= 0 else _t_clip_move[type]
			_write_clip(buffer, k - 8, clip, _anim_frame[slot], _clip_loop[clip])
	if multimesh.instance_count > 0:
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)
	multimesh.visible_instance_count = k / stride
	_buffers[type] = buffer

# Writes transform and INSTANCE_CUSTOM; for stride 20 the caller fills COLOR at k + 12.
func _write_instance(buffer: PackedFloat32Array, k: int, slot: int, scale_xz: float, scale_y: float, flash: float, stride: int) -> int:
	var yaw := _yaw[slot]
	var c := cos(yaw)
	var s := sin(yaw)
	var p := _pos[slot]
	var telegraph := 0.0
	if _mode[slot] == Mode.WINDUP and _state[slot] == ALIVE:
		var duration := _defs[_type[slot]].telegraph_duration
		telegraph = clampf(1.0 - _timer[slot] / maxf(0.001, duration), 0.01, 1.0)
	elif _mode[slot] == Mode.CHARGE and _state[slot] == ALIVE:
		telegraph = 1.0
	buffer[k] = c * scale_xz
	buffer[k + 1] = 0.0
	buffer[k + 2] = s * scale_xz
	buffer[k + 3] = p.x
	buffer[k + 4] = 0.0
	buffer[k + 5] = scale_y
	buffer[k + 6] = 0.0
	buffer[k + 7] = _y[slot]
	buffer[k + 8] = -s * scale_xz
	buffer[k + 9] = 0.0
	buffer[k + 10] = c * scale_xz
	buffer[k + 11] = p.y
	var custom := k + stride - 4
	buffer[custom] = flash
	buffer[custom + 1] = -1.0 if _stunned[slot] > 0.0 else telegraph
	buffer[custom + 2] = _phase[slot]
	buffer[custom + 3] = -1.0 if _exposed[slot] > 0.0 else (1.0 - _slow[slot]) if _slow_time[slot] > 0.0 else 0.0
	return k + stride

func _reset_animation(slot: int) -> void:
	_anim_clip[slot] = -1
	_anim_prev[slot] = _pos[slot]
	_anim_speed[slot] = _t_speed[_type[slot]]

# Picks and advances the clip of a living animated enemy and writes its COLOR.
# Gait playback follows the measured ground speed; windups play the attack clip
# timed to the telegraph, charges and melee contact loop it.
func _animate(buffer: PackedFloat32Array, at: int, slot: int, type: int, delta: float, touching: bool) -> void:
	var p := _pos[slot]
	var moved := minf(p.distance_to(_anim_prev[slot]) / maxf(delta, 0.0001), 40.0)
	_anim_prev[slot] = p
	if _stunned[slot] > 0.0 and _anim_clip[slot] >= 0:
		_write_clip(buffer, at, _anim_clip[slot], _anim_frame[slot], 0.0)
		return
	var speed := _anim_speed[slot] + (moved - _anim_speed[slot]) * minf(1.0, delta * 6.0)
	_anim_speed[slot] = speed
	var attack := _t_clip_attack[type]
	var mode := _mode[slot]
	if attack >= 0 and mode == Mode.WINDUP:
		var progress := clampf(1.0 - _timer[slot] / maxf(0.001, _defs[type].telegraph_duration), 0.0, 1.0)
		_anim_clip[slot] = attack
		_anim_frame[slot] = progress * (_clip_count[attack] - 1.0)
		_write_clip(buffer, at, attack, _anim_frame[slot], 0.0)
		return
	var clip := _t_clip_move[type]
	var rate := 1.0
	if attack >= 0 and (mode == Mode.CHARGE or touching):
		clip = attack
	else:
		var reference := _t_move_ref[type]
		rate = clampf(speed / reference, 0.5, 3.0)
		var idle := _t_clip_idle[type]
		if idle >= 0 and speed < reference * 0.15:
			clip = idle
			rate = 1.0
	var count := _clip_count[clip]
	if clip != _anim_clip[slot]:
		_anim_clip[slot] = clip
		# Gait clips start at a per-enemy offset so crowds do not march in step.
		_anim_frame[slot] = 0.0 if clip == attack else _phase[slot] / TAU * count
	_anim_frame[slot] = fmod(_anim_frame[slot] + delta * _clip_fps[clip] * rate, count)
	_write_clip(buffer, at, clip, _anim_frame[slot], 1.0)

func _write_clip(buffer: PackedFloat32Array, at: int, clip: int, frame: float, loop: float) -> void:
	buffer[at] = frame
	buffer[at + 1] = _clip_start[clip]
	buffer[at + 2] = _clip_count[clip]
	buffer[at + 3] = loop

func _draw_projectiles() -> void:
	var buffer := _shot_buffer
	_shot_buffer = PackedFloat32Array()
	# A spit only counts as a hit within a body width of the player's axis, so
	# it would otherwise fill the view for its last frame; it shrinks away instead.
	var eye := target.camera.global_position if is_instance_valid(target) else Vector3.INF
	for s in _shot_count:
		var k := s * 12
		var p := _shot_pos[s]
		var size := clampf((p.distance_to(eye) - PROJECTILE_FADE_NEAR) / (PROJECTILE_FADE_FAR - PROJECTILE_FADE_NEAR), 0.0, 1.0)
		buffer[k] = size
		buffer[k + 1] = 0.0
		buffer[k + 2] = 0.0
		buffer[k + 3] = p.x
		buffer[k + 4] = 0.0
		buffer[k + 5] = size
		buffer[k + 6] = 0.0
		buffer[k + 7] = p.y
		buffer[k + 8] = 0.0
		buffer[k + 9] = 0.0
		buffer[k + 10] = size
		buffer[k + 11] = p.z
	RenderingServer.multimesh_set_buffer(_shot_renderer.multimesh.get_rid(), buffer)
	_shot_renderer.multimesh.visible_instance_count = _shot_count
	_shot_buffer = buffer
