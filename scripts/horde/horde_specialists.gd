class_name HordeSpecialists
extends RefCounted

## Fixed slot state belongs to the same generation as Horde's body. Delayed
## action accounts retain intention, not a recycled source index. All clocks and
## movement are driven by Horde (tree pause therefore freezes hazards too).
const BOMBER_WINDUP := 1.2
const BOMBER_RUSH_SPEED := 16.0
const BOMBER_RUSH_TIME := 1.6
const BOMB_RADIUS := 4.2
const BOMB_DAMAGE := 150.0
const BOMB_PLAYER_DAMAGE := 12
const KICK_FUSE := 0.65
const PRECISION_FUSE := 0.06
const CORPSE_FUSE := 0.85
const CHAIN_FUSE := 0.16
const CORPSE_SPEED := 18.0
const CORPSE_LIFT := 4.5
const EXPLOSIONS_PER_FRAME := 16
const AMBUSH_WARNING := 0.95
const AMBUSH_HANG_LIMIT := 4.0
const AMBUSH_ROOF_LIMIT := 12.0
const AMBUSH_CLEARANCE := 1.25
const AMBUSH_TRAVEL := 4.0
const AMBUSH_SPEED := 6.0
const AMBUSH_RECOVERY := 0.85
const AMBUSH_LANDING_RADIUS := 1.4
const AMBUSH_LANDING_DAMAGE := 7
const SPRAY_WARNING := 0.9
const FUEL_CAPACITY := 64
const LOB_CAPACITY := 32
const FUEL_RADIUS := 2.1
const FUEL_LIFE := 8.0
const BURN_LIFE := 5.0
const FUEL_TICK := 0.4
const FUEL_HEIGHT := 0.55
const FUEL_BURST_DAMAGE := 80.0
const FUEL_BURN_DAMAGE := 6.0
const BURN_PLAYER_DAMAGE := 4
const LOB_GRAVITY := 14.0
const TELEGRAPH_COLOR := Color(1.0, 0.8, 0.16)
const LANDING_COLOR := Color(0.6, 0.4, 1.0)
const FUEL_COLOR := Color(0.18, 0.8, 0.12)
const BURN_COLOR := Color(1.0, 0.3, 0.035)
const BOMB_COLOR := Color(1.0, 0.08, 0.18)
const FRIENDLY_COLOR := Color(0.15, 0.9, 1.0)
const RING_CAPACITY := Horde.CAPACITY + FUEL_CAPACITY + LOB_CAPACITY

enum Ambush { NONE, HANG, WARN, DROP, LANDED }

var _h: Horde
var _life := PackedInt64Array()
var _ambush := PackedByteArray()
var _hang_time := PackedFloat32Array()
var _armed := PackedByteArray()
var _corpse := PackedByteArray()
var _fuse := PackedFloat32Array()
var _intent := PackedInt32Array()
var _finish_direction := PackedVector2Array()
var _bomb_slots := PackedInt32Array()
var _bomb_queued := PackedByteArray()
var _bomb_count := 0
# One account per possible delayed source, with one extra root ignition account.
const ACCOUNT_CAPACITY := Horde.CAPACITY + FUEL_CAPACITY
var _account_active := PackedByteArray()
var _account_pending := PackedInt32Array()
var _account_members := PackedInt32Array()
var _account_at := PackedVector3Array()
var _account_label: Array[String] = []
var _account_cursor := 0
var _damage_intent := -1
var _inside_blast := false
var _blast_suspend := 0
var _igniting := false
var _epoch := 0
var _explosions_left := EXPLOSIONS_PER_FRAME
var _clock := 0.0
var _floor_result := Vector3.INF
var _ray := PhysicsRayQueryParameters3D.new()
var _ray_excluded := RID()
var _fuel_pos := PackedVector3Array()
var _fuel_life := PackedFloat32Array()
var _fuel_tick := PackedFloat32Array()
var _fuel_burning := PackedByteArray()
var _fuel_friendly := PackedByteArray()
var _fuel_cursor := 0
var _ignition_queue := PackedInt32Array()
var _patch_hits := PackedInt32Array()
var _patch_generations := PackedInt64Array()
var _lob_pos := PackedVector3Array()
var _lob_vel := PackedVector3Array()
var _lob_life := PackedFloat32Array()
var _lob_cursor := 0
var _rings: MultiMeshInstance3D
var _liquid: MultiMeshInstance3D
var _blobs: MultiMeshInstance3D
var _ring_count := 0
var _liquid_count := 0
var _blob_count := 0

func setup(horde: Horde) -> void:
	_h = horde
	_life.resize(Horde.CAPACITY)
	_ambush.resize(Horde.CAPACITY)
	_hang_time.resize(Horde.CAPACITY)
	_armed.resize(Horde.CAPACITY)
	_corpse.resize(Horde.CAPACITY)
	_fuse.resize(Horde.CAPACITY)
	_intent.resize(Horde.CAPACITY)
	_intent.fill(-1)
	_finish_direction.resize(Horde.CAPACITY)
	_bomb_slots.resize(Horde.CAPACITY)
	_bomb_queued.resize(Horde.CAPACITY)
	_account_active.resize(ACCOUNT_CAPACITY)
	_account_pending.resize(ACCOUNT_CAPACITY)
	_account_members.resize(ACCOUNT_CAPACITY)
	_account_at.resize(ACCOUNT_CAPACITY)
	_account_label.resize(ACCOUNT_CAPACITY)
	_fuel_pos.resize(FUEL_CAPACITY)
	_fuel_life.resize(FUEL_CAPACITY)
	_fuel_tick.resize(FUEL_CAPACITY)
	_fuel_burning.resize(FUEL_CAPACITY)
	_fuel_friendly.resize(FUEL_CAPACITY)
	_ignition_queue.resize(FUEL_CAPACITY)
	_patch_hits.resize(Horde.CAPACITY)
	_patch_generations.resize(Horde.CAPACITY)
	_lob_pos.resize(LOB_CAPACITY)
	_lob_vel.resize(LOB_CAPACITY)
	_lob_life.resize(LOB_CAPACITY)
	var segment := BoxMesh.new()
	segment.size = Vector3(0.28, 0.04, 0.075)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in 20:
		var angle := float(n) * TAU / 20.0
		surface.append_from(segment, 0, Transform3D(Basis(Vector3.UP, -angle + PI * 0.5), Vector3(cos(angle), 0.0, sin(angle))))
	_rings = _make_batch(surface.commit(), RING_CAPACITY, "SpecialistWarnings")
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.028
	disc.radial_segments = 32
	_liquid = _make_batch(disc, FUEL_CAPACITY, "AbsinthePools")
	var blob := SphereMesh.new()
	blob.radius = 0.17
	blob.height = 0.34
	_blobs = _make_batch(blob, LOB_CAPACITY, "AbsintheLobs")

func _make_batch(mesh: Mesh, capacity: int, batch_name: String) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = capacity
	batch.visible_instance_count = 0
	var renderer := MultiMeshInstance3D.new()
	renderer.name = batch_name
	renderer.multimesh = batch
	renderer.material_override = material
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	renderer.custom_aabb = AABB(Vector3(_h.play_area.position.x - 4.0, -8.0, _h.play_area.position.y - 4.0), Vector3(_h.play_area.size.x + 8.0, 40.0, _h.play_area.size.y + 8.0))
	_h.add_child(renderer)
	return renderer

func _world_hit(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = 1
	_ray.collide_with_areas = false
	var body := _h.target.get_rid() if is_instance_valid(_h.target) else RID()
	if body != _ray_excluded:
		_ray_excluded = body
		var excluded: Array[RID] = []
		if body.is_valid():
			excluded.append(body)
		_ray.exclude = excluded
	return _h.get_world_3d().direct_space_state.intersect_ray(_ray)

func _floor_at(xz: Vector2, radius: float = 0.0) -> bool:
	var height := _h.ground_height(xz)
	if not is_finite(height) or not _h.is_reachable(xz) or _h.is_blocked(xz, radius, height, 0.7):
		return false
	var hit := _world_hit(Vector3(xz.x, height + 0.35, xz.y), Vector3(xz.x, height - 0.8, xz.y))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.7 or absf((hit.position as Vector3).y - height) > 0.3:
		return false
	_floor_result = hit.position
	return true

## Actual roof underside across the whole body, not a layout/visual roof flag.
func spawn_height(definition: HordeEnemyDefinition, xz: Vector2) -> float:
	if definition.behavior != HordeEnemyDefinition.Behavior.AMBUSHER:
		return _h.ground_height(xz)
	if not _floor_at(xz, definition.radius):
		return NAN
	var floor_y := _floor_result.y
	var lowest := INF
	var highest := -INF
	for n in 5:
		var offset := Vector2.ZERO if n == 0 else Vector2.from_angle(float(n - 1) * PI * 0.5) * definition.radius
		var from := Vector3(xz.x + offset.x, floor_y + definition.height + 0.15, xz.y + offset.y)
		var hit := _world_hit(from, Vector3(from.x, floor_y + AMBUSH_ROOF_LIMIT, from.z))
		if hit.is_empty() or (hit.normal as Vector3).y > -0.7:
			return NAN
		lowest = minf(lowest, (hit.position as Vector3).y)
		highest = maxf(highest, (hit.position as Vector3).y)
	if lowest - floor_y < definition.height + AMBUSH_CLEARANCE or highest - lowest > 0.4:
		return NAN
	return lowest - definition.height - 0.08

func spawned(slot: int) -> void:
	_life[slot] = _h._generation[slot]
	_ambush[slot] = Ambush.HANG if _behavior(slot) == HordeEnemyDefinition.Behavior.AMBUSHER else Ambush.NONE
	_hang_time[slot] = 0.0
	_armed[slot] = 0
	_corpse[slot] = 0
	_fuse[slot] = 0.0
	_intent[slot] = -1
	_finish_direction[slot] = Vector2.ZERO

func _behavior(slot: int) -> int:
	return _h._t_behavior[_h._type[slot]]

func is_specialist(slot: int) -> bool:
	return _behavior(slot) >= HordeEnemyDefinition.Behavior.BOMBER

func holds_ceiling(slot: int) -> bool:
	return _ambush[slot] == Ambush.HANG or _ambush[slot] == Ambush.WARN

func is_airborne(slot: int) -> bool:
	return _ambush[slot] != Ambush.NONE and _h._y[slot] - _h.ground_height(_h._pos[slot]) > Horde.AIRBORNE_CLEARANCE

func is_corpse_bomb(slot: int) -> bool:
	return _corpse[slot] != 0 and _life[slot] == _h._generation[slot]

func interrupted(slot: int) -> void:
	if holds_ceiling(slot):
		_ambush[slot] = Ambush.DROP
		_h._attack_target[slot] = Vector3(_h._pos[slot].x, _h.ground_height(_h._pos[slot]), _h._pos[slot].y)
		_h._vy[slot] = -0.1
	if _behavior(slot) == HordeEnemyDefinition.Behavior.BOMBER and _intent[slot] < 0:
		_armed[slot] = 0

func _callout(slot: int, text: String, clip: StringName) -> void:
	if _life[slot] != _h._generation[slot] or _h._state[slot] == Horde.FREE:
		return
	_h._action_suspend += 1
	_h.enemy_callout.emit(slot, text, clip)
	_h._action_suspend -= 1

func steer(slot: int, route: Vector2, direct: Vector2, distance: float, delta: float) -> Vector2:
	var definition := _h._defs[_h._type[slot]]
	var behavior := _behavior(slot)
	if behavior == HordeEnemyDefinition.Behavior.AMBUSHER:
		return _steer_ambusher(slot, route, distance, delta)
	if behavior == HordeEnemyDefinition.Behavior.BOMBER and _intent[slot] >= 0:
		return Vector2.ZERO
	_h._cooldown[slot] = maxf(0.0, _h._cooldown[slot] - delta)
	match _h._mode[slot]:
		Horde.Mode.WINDUP:
			_h._timer[slot] -= delta
			if _h._timer[slot] <= 0.0:
				if behavior == HordeEnemyDefinition.Behavior.BOMBER:
					_h._mode[slot] = Horde.Mode.CHARGE
					_h._timer[slot] = maxf(BOMBER_RUSH_TIME, definition.charge_duration)
					_callout(slot, "ODPOČET DO AUTODESTRUKCE", &"rush")
				else:
					_lob(slot)
					_h._end_charge(slot, _h._type[slot])
			return Vector2.ZERO
		Horde.Mode.CHARGE:
			_h._timer[slot] -= delta
			if _h._timer[slot] <= 0.0:
				_queue_fuse(slot, PRECISION_FUSE)
				return Vector2.ZERO
			return _h._aim[slot] * maxf(BOMBER_RUSH_SPEED, definition.charge_speed)
		Horde.Mode.RECOVER:
			_h._timer[slot] -= delta
			if _h._timer[slot] <= 0.0:
				_h._mode[slot] = Horde.Mode.SEEK
			return Vector2.ZERO
	var move := route * definition.speed
	if behavior == HordeEnemyDefinition.Behavior.BOMBER:
		if _h._cooldown[slot] <= 0.0 and distance <= definition.charge_range and _h._lane_clear(_h.enemy_position(slot), _h.target.global_position):
			_h._begin_windup(slot, definition, direct)
			_h._timer[slot] = maxf(BOMBER_WINDUP, definition.telegraph_duration)
			_armed[slot] = 1
			_callout(slot, "ODPOČET DO AUTODESTRUKCE", &"warning")
			return Vector2.ZERO
	else:
		if distance < definition.preferred_range - 1.5:
			move = -direct * definition.speed * 0.7
		elif distance < definition.preferred_range + 1.5:
			move = Vector2.ZERO
		if _h._cooldown[slot] <= 0.0 and distance <= definition.attack_range:
			var xz := Vector2(_h.target.global_position.x, _h.target.global_position.z)
			if _floor_at(xz, FUEL_RADIUS) and _h._lane_clear(_h.enemy_position(slot), _floor_result + Vector3.UP * 0.35) and _has_fuel_room():
				var land := _floor_result
				_h._begin_windup(slot, definition, direct)
				_h._attack_target[slot] = land
				_h._timer[slot] = maxf(SPRAY_WARNING, definition.telegraph_duration)
				_callout(slot, "NEMÁTE VOHEŇ VOE DO PÍČI?", &"fire")
				return Vector2.ZERO
			_h._cooldown[slot] = 0.35
	return move

func _steer_ambusher(slot: int, route: Vector2, distance: float, delta: float) -> Vector2:
	var definition := _h._defs[_h._type[slot]]
	match _ambush[slot]:
		Ambush.HANG:
			_hang_time[slot] += delta
			if distance <= definition.attack_range or _hang_time[slot] >= AMBUSH_HANG_LIMIT:
				var xz := _h._pos[slot]
				var player_xz := Vector2(_h.target.global_position.x, _h.target.global_position.z)
				var offset := player_xz - xz
				var candidate := xz + offset.limit_length(AMBUSH_TRAVEL)
				if not _floor_at(candidate, _h._radius[slot]) or not body_path_clear(slot, xz, candidate):
					candidate = xz
				if not _floor_at(candidate, _h._radius[slot]):
					interrupted(slot)
					return Vector2.ZERO
				_h._attack_target[slot] = _floor_result
				_h._aim[slot] = (candidate - xz).normalized()
				_h._mode[slot] = Horde.Mode.WINDUP
				_h._timer[slot] = maxf(AMBUSH_WARNING, definition.telegraph_duration)
				_ambush[slot] = Ambush.WARN
				_callout(slot, "TARZAN ZE STROPU", &"warning")
			return Vector2.ZERO
		Ambush.WARN:
			_h._timer[slot] -= delta
			if _h._timer[slot] <= 0.0:
				_ambush[slot] = Ambush.DROP
				_h._mode[slot] = Horde.Mode.CHARGE
				_h._vy[slot] = -0.1
			return Vector2.ZERO
		Ambush.DROP:
			var land := _h._attack_target[slot]
			var offset := Vector2(land.x, land.z) - _h._pos[slot]
			var fall_time := maxf(0.1, (sqrt(_h._vy[slot] * _h._vy[slot] + 2.0 * Horde.FALL_GRAVITY * maxf(0.0, _h._y[slot] - land.y)) + _h._vy[slot]) / Horde.FALL_GRAVITY)
			return offset.limit_length(AMBUSH_SPEED * fall_time) / fall_time
		_:
			if _h._mode[slot] == Horde.Mode.RECOVER:
				_h._timer[slot] -= delta
				if _h._timer[slot] <= 0.0:
					_h._mode[slot] = Horde.Mode.SEEK
				return Vector2.ZERO
			return route * definition.speed

## Samples both edges at feet, centre and head against actual physics geometry.
func body_path_clear(slot: int, from: Vector2, to: Vector2) -> bool:
	if from.is_equal_approx(to):
		return true
	var side := (to - from).orthogonal().normalized() * _h._radius[slot]
	for band in 3:
		var y := _h._y[slot] + lerpf(0.08, _h._height[slot] - 0.06, float(band) * 0.5)
		for edge in 3:
			var offset := side * float(edge - 1)
			if not _h._lane_clear(Vector3(from.x + offset.x, y, from.y + offset.y), Vector3(to.x + offset.x, y, to.y + offset.y)):
				return false
	return true

## Physics ceilings stop kicks/corpse launches; swept feet stop falling through
## real decks even when their collider is not in the obstacle buckets.
func constrain_vertical(slot: int, xz: Vector2, next_y: float) -> float:
	var old_y := _h._y[slot]
	if is_equal_approx(old_y, next_y):
		return next_y
	var ascending := next_y > old_y
	var band := _h._height[slot] - 0.03 if ascending else 0.04
	for edge in 5:
		var offset := Vector2.ZERO if edge == 0 else Vector2.from_angle(float(edge - 1) * PI * 0.5) * _h._radius[slot] * 0.85
		var from := Vector3(xz.x + offset.x, old_y + band, xz.y + offset.y)
		var hit := _world_hit(from, Vector3(from.x, next_y + band, from.z))
		if hit.is_empty():
			continue
		if ascending and (hit.normal as Vector3).y < -0.5:
			next_y = minf(next_y, maxf(old_y, (hit.position as Vector3).y - _h._height[slot] - 0.02))
			_h._vy[slot] = 0.0
		elif not ascending and (hit.normal as Vector3).y > 0.7:
			next_y = maxf(next_y, (hit.position as Vector3).y)
			_h._vy[slot] = 0.0
	return next_y

func after_move(slot: int, intended: Vector2, actual: Vector2) -> void:
	if _behavior(slot) == HordeEnemyDefinition.Behavior.BOMBER and _armed[slot] != 0 and _h._mode[slot] == Horde.Mode.CHARGE and not intended.is_equal_approx(actual):
		_queue_fuse(slot, PRECISION_FUSE)
	if _ambush[slot] == Ambush.DROP and _h._y[slot] <= _h.ground_height(actual) + 0.03 and _h._vy[slot] <= 0.0:
		_ambush[slot] = Ambush.LANDED
		_h._vy[slot] = 0.0
		_h._mode[slot] = Horde.Mode.RECOVER
		_h._timer[slot] = maxf(AMBUSH_RECOVERY, _h._defs[_h._type[slot]].recovery_duration)
		if is_instance_valid(_h._fx):
			_h._fx.burst_kick(_h.enemy_position(slot), true)
		var player := _h.target
		if is_instance_valid(player) and player.active and absf(player.global_position.y - 0.9 - _h._y[slot]) < FUEL_HEIGHT and Vector2(player.global_position.x, player.global_position.z).distance_squared_to(actual) < AMBUSH_LANDING_RADIUS * AMBUSH_LANDING_RADIUS and _h._lane_clear(_h.enemy_position(slot), player.global_position):
			player.take_damage(AMBUSH_LANDING_DAMAGE)

func begin_frame() -> void:
	_explosions_left = EXPLOSIONS_PER_FRAME

func actions_pending() -> bool:
	return _bomb_count > 0

func hazards_pending() -> bool:
	for lob in LOB_CAPACITY:
		if _lob_life[lob] > 0.0:
			return true
	for pool in FUEL_CAPACITY:
		if _fuel_life[pool] > 0.0 and _fuel_burning[pool] != 0:
			return true
	return false

func telegraph_duration(slot: int) -> float:
	var authored := _h._defs[_h._type[slot]].telegraph_duration
	match _behavior(slot):
		HordeEnemyDefinition.Behavior.BOMBER:
			return maxf(BOMBER_WINDUP, authored)
		HordeEnemyDefinition.Behavior.AMBUSHER:
			return maxf(AMBUSH_WARNING, authored)
		HordeEnemyDefinition.Behavior.SPRAYER:
			return maxf(SPRAY_WARNING, authored)
	return authored

func _queue_fuse(slot: int, duration: float) -> void:
	_fuse[slot] = minf(_fuse[slot], duration) if _fuse[slot] > 0.0 else duration
	if _bomb_queued[slot] == 0:
		_bomb_queued[slot] = 1
		_bomb_slots[_bomb_count] = slot
		_bomb_count += 1

func _new_account(label: String) -> int:
	for n in ACCOUNT_CAPACITY:
		var account := (_account_cursor + n) % ACCOUNT_CAPACITY
		if _account_active[account] == 0:
			_account_active[account] = 1
			_account_pending[account] = 0
			_account_members[account] = 0
			_account_at[account] = Vector3.ZERO
			_account_label[account] = label
			_account_cursor = (account + 1) % ACCOUNT_CAPACITY
			return account
	return -1

func credit_action(account: int, members: int, at: Vector3) -> void:
	if account < 0 or _account_active[account] == 0:
		return
	_account_members[account] += members
	if members > 0:
		_account_at[account] = at

func _release_account(account: int) -> void:
	if account < 0 or _account_active[account] == 0:
		return
	_account_pending[account] -= 1
	if _account_pending[account] > 0:
		return
	var members := _account_members[account]
	var at := _account_at[account]
	var label := _account_label[account]
	_account_active[account] = 0
	if members > 0:
		_h._action_suspend += 1
		_h.action_killed.emit(members, at, label)
		_h._action_suspend -= 1

func reverse_kick(slot: int, account: int) -> int:
	if _h._action_suspend > 0:
		return account
	interrupted(slot)
	if _behavior(slot) != HordeEnemyDefinition.Behavior.BOMBER:
		return account
	if account < 0:
		account = _new_account("OBRÁCENEJ BOMBAŘ")
	_arm_friendly(slot, account, KICK_FUSE)
	return account

func prepare_finish(slot: int, origin: Vector3) -> int:
	if _behavior(slot) != HordeEnemyDefinition.Behavior.BOMBER:
		return -1
	var account := _new_account("FINISHER BOMBAŘ")
	_arm_friendly(slot, account, CORPSE_FUSE)
	# Executing wins a fresh throw window even if an earlier reversal was armed.
	_fuse[slot] = CORPSE_FUSE
	var away := _h._pos[slot] - Vector2(origin.x, origin.z)
	_finish_direction[slot] = away.normalized() if away.length_squared() > 0.0001 else Vector2(-sin(_h._yaw[slot]), -cos(_h._yaw[slot]))
	return account

func precision_hit(slot: int) -> void:
	if _behavior(slot) != HordeEnemyDefinition.Behavior.BOMBER or _h._action_suspend > 0:
		return
	var account := _intent[slot]
	if account < 0:
		account = _new_account("BATOH DO VZDUCHU")
	_arm_friendly(slot, account, PRECISION_FUSE)

func _arm_friendly(slot: int, account: int, fuse: float) -> void:
	if _intent[slot] != account:
		if _intent[slot] >= 0:
			_release_account(_intent[slot])
		_intent[slot] = account
		if account >= 0:
			_account_pending[account] += 1
	_armed[slot] = 1
	_queue_fuse(slot, fuse)

## Called after the ordinary death resets status; never grants a second life.
func died(slot: int) -> void:
	if _behavior(slot) == HordeEnemyDefinition.Behavior.BOMBER:
		if _inside_blast and _h._action_suspend == _blast_suspend and _intent[slot] < 0:
			_armed[slot] = 1
			_queue_fuse(slot, CHAIN_FUSE)
			_intent[slot] = _damage_intent
			if _damage_intent >= 0:
				_account_pending[_damage_intent] += 1
		if _intent[slot] >= 0 or (_inside_blast and _h._action_suspend == _blast_suspend and _armed[slot] != 0 and _fuse[slot] > 0.0):
			_corpse[slot] = 1
			_h._death[slot] = maxf(_h._death[slot], _fuse[slot] + Horde.DEATH_TIME)
			if _finish_direction[slot] != Vector2.ZERO:
				_h._knock[slot] = _finish_direction[slot] * CORPSE_SPEED
				_h._vy[slot] = CORPSE_LIFT
			return
	_armed[slot] = 0
	_fuse[slot] = 0.0
	_ambush[slot] = Ambush.NONE

func contact_bomber(slot: int) -> bool:
	if _behavior(slot) != HordeEnemyDefinition.Behavior.BOMBER or _armed[slot] == 0:
		return false
	_queue_fuse(slot, PRECISION_FUSE)
	return true

func impact_bomber(slot: int) -> bool:
	if _behavior(slot) != HordeEnemyDefinition.Behavior.BOMBER or _intent[slot] < 0:
		return false
	_queue_fuse(slot, PRECISION_FUSE)
	return true

func advance_corpse(slot: int, delta: float) -> bool:
	if not is_corpse_bomb(slot):
		return false
	var p := _h._pos[slot]
	var motion := p + _h._knock[slot] * delta
	var actual := _h._sweep_move(slot, motion)
	if not actual.is_equal_approx(motion) or _corpse_contact(slot, actual):
		_queue_fuse(slot, PRECISION_FUSE)
	_h._pos[slot] = actual
	_h._knock[slot] *= maxf(0.0, 1.0 - delta * 0.65)
	_h._vy[slot] -= Horde.FALL_GRAVITY * delta
	var next_y := maxf(_h.ground_height(actual), _h._y[slot] + _h._vy[slot] * delta)
	_h._y[slot] = constrain_vertical(slot, actual, next_y)
	_h._death[slot] = _fuse[slot] + Horde.DEATH_TIME
	return true

func _corpse_contact(slot: int, p: Vector2) -> bool:
	return _h._launch_contact(slot, p) >= 0

func update(delta: float) -> void:
	_clock += delta
	var epoch := _epoch
	# Sources cannot recycle while pending. Fuses resolve only in physics, after
	# the primary hit transaction and movement/impact snapshot have finished.
	var ready := _bomb_count
	for n in ready:
		var slot := _bomb_slots[n]
		if _armed[slot] == 0 or _life[slot] != _h._generation[slot]:
			continue
		_fuse[slot] -= delta
		if _fuse[slot] <= 0.0:
			if _explosions_left > 0:
				_explosions_left -= 1
				_explode(slot)
			else:
				_fuse[slot] = 0.00001
		if epoch != _epoch:
			return
	var kept := 0
	for n in _bomb_count:
		var slot := _bomb_slots[n]
		if _armed[slot] != 0 and _life[slot] == _h._generation[slot]:
			_bomb_slots[kept] = slot
			kept += 1
		else:
			_bomb_queued[slot] = 0
	_bomb_count = kept
	_update_lobs(delta)
	if epoch == _epoch:
		_update_fuel(delta)

func _explode(slot: int) -> void:
	var at := _h.enemy_position(slot)
	var account := _intent[slot]
	var friendly := account >= 0
	var epoch := _epoch
	_armed[slot] = 0
	_fuse[slot] = 0.0
	_corpse[slot] = 0
	_intent[slot] = -1
	if friendly:
		_callout(slot, "DO PRDELE CO SE DĚJE?!", &"reversed")
	if epoch != _epoch:
		return
	var outer := _h._action_open() if friendly else 0
	if not friendly:
		_h._action_suspend += 1
	# The exploding body is removed before splash and never queues itself again.
	if _h.is_alive(slot):
		_h._deal_damage(slot, _h._hp[slot], Vector3.ZERO, DamageType.Kind.KINETIC, false)
	elif _h._state[slot] == Horde.DYING:
		_h._death[slot] = Horde.DEATH_TIME
	if epoch != _epoch:
		if friendly:
			_h._action_close(outer, at, "BOMBAŘ", account)
		else:
			_h._action_suspend -= 1
		return
	var old_intent := _damage_intent
	var old_blast := _inside_blast
	var old_suspend := _blast_suspend
	_damage_intent = account
	_inside_blast = true
	_blast_suspend = _h._action_suspend
	_h._radius_core(at, BOMB_RADIUS, BOMB_DAMAGE, 12.0, DamageType.Kind.KINETIC, false)
	_inside_blast = old_blast
	_damage_intent = old_intent
	_blast_suspend = old_suspend
	if epoch == _epoch:
		ignite_radius(at, BOMB_RADIUS, friendly, account)
	if friendly:
		_h._action_close(outer, at, "BOMBAŘ", account)
	else:
		_h._action_suspend -= 1
		var player := _h.target
		if epoch == _epoch and is_instance_valid(player) and player.active and at.distance_squared_to(player.global_position) <= BOMB_RADIUS * BOMB_RADIUS and _h._lane_clear(at, player.global_position):
			player.take_damage(BOMB_PLAYER_DAMAGE)
	if epoch == _epoch and is_instance_valid(_h._fx):
		_h._fx.burst_flame(at, BOMB_RADIUS)
	if epoch == _epoch:
		_release_account(account)

func _has_fuel_room() -> bool:
	for n in FUEL_CAPACITY:
		if _fuel_life[n] <= 0.0:
			return true
	return false

func _lob(slot: int) -> void:
	for n in LOB_CAPACITY:
		var lob := (_lob_cursor + n) % LOB_CAPACITY
		if _lob_life[lob] > 0.0:
			continue
		var from := Vector3(_h._pos[slot].x, _h._y[slot] + _h._height[slot] * 0.85, _h._pos[slot].y)
		var land := _h._attack_target[slot]
		var flight := clampf(Vector2(land.x - from.x, land.z - from.z).length() / 10.0, 0.4, 1.1)
		_lob_pos[lob] = from
		_lob_vel[lob] = (land - from) / flight + Vector3.UP * (0.5 * LOB_GRAVITY * flight)
		_lob_life[lob] = flight + 1.0
		_lob_cursor = (lob + 1) % LOB_CAPACITY
		return

func _update_lobs(delta: float) -> void:
	for lob in LOB_CAPACITY:
		if _lob_life[lob] <= 0.0:
			continue
		var from := _lob_pos[lob]
		_lob_vel[lob] += Vector3.DOWN * LOB_GRAVITY * delta
		var next := from + _lob_vel[lob] * delta
		var hit := _world_hit(from, next)
		_lob_life[lob] -= delta
		if not hit.is_empty():
			_lob_life[lob] = 0.0
			if (hit.normal as Vector3).y > 0.7:
				_add_fuel(hit.position)
			if is_instance_valid(_h._fx):
				_h._fx.burst_bottle(hit.position)
		else:
			_lob_pos[lob] = next

func _add_fuel(at: Vector3) -> void:
	var xz := Vector2(at.x, at.z)
	if not _floor_at(xz, FUEL_RADIUS) or absf(_floor_result.y - at.y) > 0.25:
		return
	var center := _floor_result
	# A puddle never spans missing ground or projects onto another floor/deck.
	for n in 8:
		var edge := xz + Vector2.from_angle(float(n) * TAU / 8.0) * FUEL_RADIUS
		if not _floor_at(edge) or absf(_floor_result.y - center.y) > 0.3 or not _h._lane_clear(center + Vector3.UP * 0.15, _floor_result + Vector3.UP * 0.15):
			return
	for n in FUEL_CAPACITY:
		var pool := (_fuel_cursor + n) % FUEL_CAPACITY
		if _fuel_life[pool] > 0.0:
			continue
		_fuel_pos[pool] = center
		_fuel_life[pool] = FUEL_LIFE
		_fuel_tick[pool] = FUEL_TICK
		_fuel_burning[pool] = 0
		_fuel_friendly[pool] = 0
		_fuel_cursor = (pool + 1) % FUEL_CAPACITY
		return

func ignite_ray(origin: Vector3, direction: Vector3, max_distance: float) -> int:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001 or not is_finite(max_distance) or max_distance <= 0.0:
		return 0
	var aim := direction.normalized()
	if absf(aim.y) < 0.000001:
		return 0
	var ignited := 0
	for pool in FUEL_CAPACITY:
		if _fuel_life[pool] <= 0.0 or _fuel_burning[pool] != 0:
			continue
		var distance := (_fuel_pos[pool].y + 0.03 - origin.y) / aim.y
		if distance < 0.0 or distance > max_distance:
			continue
		var point := origin + aim * distance
		if Vector2(point.x, point.z).distance_squared_to(Vector2(_fuel_pos[pool].x, _fuel_pos[pool].z)) <= FUEL_RADIUS * FUEL_RADIUS and _h._lane_clear(origin, point + Vector3.UP * 0.03):
			ignited += _ignite_chain(pool, true, -1)
	return ignited

func ignite_radius(center: Vector3, radius: float, friendly: bool = true, account: int = -1) -> int:
	if not center.is_finite() or not is_finite(radius) or radius <= 0.0:
		return 0
	var ignited := 0
	for pool in FUEL_CAPACITY:
		if _fuel_life[pool] <= 0.0 or _fuel_burning[pool] != 0:
			continue
		var patch := _fuel_pos[pool]
		if absf(center.y - patch.y) > radius + FUEL_HEIGHT or Vector2(center.x, center.z).distance_squared_to(Vector2(patch.x, patch.z)) > (radius + FUEL_RADIUS) * (radius + FUEL_RADIUS):
			continue
		if _h._lane_clear(center, patch + Vector3.UP * 0.12):
			ignited += _ignite_chain(pool, friendly, account)
	return ignited

func fire_hit(slot: int, intentional: bool) -> void:
	if _inside_blast or _h._action_suspend > 0:
		return
	var center := _h.enemy_position(slot)
	for pool in FUEL_CAPACITY:
		if _fuel_life[pool] > 0.0 and _fuel_burning[pool] == 0 and _on_patch(slot, pool) and _h._lane_clear(center, _fuel_pos[pool] + Vector3.UP * 0.15):
			_ignite_chain(pool, true, -1, intentional)

func _ignite_chain(first: int, friendly: bool, existing_account: int, intentional: bool = true) -> int:
	if friendly and _h._action_suspend > 0:
		return 0
	if _igniting:
		return 0
	_igniting = true
	var account := existing_account
	var owns_account := friendly and intentional and account < 0
	if owns_account:
		account = _new_account("ABSINT V PLAMENECH")
		if account >= 0:
			_account_pending[account] += 1
	var epoch := _epoch
	var count := 1
	_ignition_queue[0] = first
	_fuel_burning[first] = 1
	var cursor := 0
	# Discover/mark the complete chain before any callback can re-enter it.
	while cursor < count:
		var pool := _ignition_queue[cursor]
		cursor += 1
		for other in FUEL_CAPACITY:
			if _fuel_life[other] <= 0.0 or _fuel_burning[other] != 0:
				continue
			if absf(_fuel_pos[other].y - _fuel_pos[pool].y) <= 0.3 and _fuel_pos[other].distance_squared_to(_fuel_pos[pool]) <= 4.0 * FUEL_RADIUS * FUEL_RADIUS and _h._lane_clear(_fuel_pos[pool] + Vector3.UP * 0.15, _fuel_pos[other] + Vector3.UP * 0.15):
				_fuel_burning[other] = 1
				_ignition_queue[count] = other
				count += 1
	for n in count:
		var pool := _ignition_queue[n]
		_fuel_life[pool] = BURN_LIFE
		_fuel_friendly[pool] = 1 if friendly else 0
		_fuel_tick[pool] = FUEL_TICK
		_patch_burst(pool, friendly, account, intentional)
		if epoch != _epoch:
			_igniting = false
			return n + 1
	_igniting = false
	if owns_account:
		_release_account(account)
	return count

func _on_patch(slot: int, pool: int) -> bool:
	var center := _fuel_pos[pool]
	return absf(_h._y[slot] - center.y) <= FUEL_HEIGHT and _h._pos[slot].distance_squared_to(Vector2(center.x, center.z)) <= (FUEL_RADIUS + _h._radius[slot] * 0.5) * (FUEL_RADIUS + _h._radius[slot] * 0.5)

func _damage_patch(pool: int, amount: float) -> void:
	var epoch := _epoch
	var at := _fuel_pos[pool] + Vector3.UP * 0.15
	var count := _h.query_radius(at, FUEL_RADIUS, _patch_hits)
	for n in count:
		var slot := _patch_hits[n]
		_patch_generations[n] = _h._generation[slot] if _on_patch(slot, pool) and _h._lane_clear(at, _h.enemy_position(slot)) else -1
	for n in count:
		var slot := _patch_hits[n]
		if _h.is_alive(slot) and _h._generation[slot] == _patch_generations[n]:
			_h._deal_damage(slot, amount, Vector3.ZERO, DamageType.Kind.FIRE, false)
			if epoch != _epoch:
				return

func _patch_burst(pool: int, friendly: bool, account: int, intentional: bool) -> void:
	var at := _fuel_pos[pool] + Vector3.UP * 0.15
	var epoch := _epoch
	var credited := friendly and intentional
	var outer := _h._action_open() if credited else 0
	if not credited:
		_h._action_suspend += 1
	var old_intent := _damage_intent
	var old_blast := _inside_blast
	var old_suspend := _blast_suspend
	_damage_intent = account
	# Automatic fire still ignites liquid, but its ordinary kills disarm packs
	# rather than manufacturing a hostile bomb or an intentional action account.
	_inside_blast = credited or not friendly
	_blast_suspend = _h._action_suspend
	_damage_patch(pool, FUEL_BURST_DAMAGE)
	_inside_blast = old_blast
	_damage_intent = old_intent
	_blast_suspend = old_suspend
	if credited:
		_h._action_close(outer, at, "ABSINT", account)
	else:
		_h._action_suspend -= 1
		if not friendly and epoch == _epoch:
			_hurt_player_patch(pool, BOMB_PLAYER_DAMAGE)
	if epoch == _epoch and is_instance_valid(_h._fx):
		_h._fx.burst_flame(at, FUEL_RADIUS)

func _hurt_player_patch(pool: int, amount: int) -> void:
	var player := _h.target
	if not is_instance_valid(player) or not player.active:
		return
	var at := _fuel_pos[pool]
	var feet := player.global_position.y - 0.9
	if absf(feet - at.y) <= FUEL_HEIGHT and Vector2(player.global_position.x, player.global_position.z).distance_squared_to(Vector2(at.x, at.z)) <= (FUEL_RADIUS + Horde.PLAYER_RADIUS) * (FUEL_RADIUS + Horde.PLAYER_RADIUS) and _h._lane_clear(at + Vector3.UP * 0.15, player.global_position):
		player.take_damage(amount)

func _update_fuel(delta: float) -> void:
	var epoch := _epoch
	for pool in FUEL_CAPACITY:
		if _fuel_life[pool] <= 0.0:
			continue
		_fuel_life[pool] = maxf(0.0, _fuel_life[pool] - delta)
		_fuel_tick[pool] -= delta
		if _fuel_life[pool] <= 0.0 or _fuel_tick[pool] > 0.0:
			continue
		_fuel_tick[pool] += FUEL_TICK
		if _fuel_burning[pool] != 0 and _fuel_friendly[pool] != 0:
			# Ambient DOT deliberately bypasses manual scopes and ignition hooks.
			_h._action_suspend += 1
			_damage_patch(pool, FUEL_BURN_DAMAGE)
			_h._action_suspend -= 1
		elif _fuel_burning[pool] != 0:
			_hurt_player_patch(pool, BURN_PLAYER_DAMAGE)
		if epoch != _epoch:
			return

func clear() -> void:
	_epoch += 1
	if _h != null:
		for d in _h._dying_count:
			var slot := _h._dying[d]
			if is_corpse_bomb(slot):
				_h._death[slot] = Horde.DEATH_TIME
	_bomb_count = 0
	_bomb_queued.fill(0)
	_armed.fill(0)
	_corpse.fill(0)
	_fuse.fill(0.0)
	_intent.fill(-1)
	_ambush.fill(Ambush.NONE)
	_account_active.fill(0)
	_fuel_life.fill(0.0)
	_lob_life.fill(0.0)
	_damage_intent = -1
	_inside_blast = false
	_igniting = false
	_blast_suspend = 0
	if _rings != null:
		_rings.multimesh.visible_instance_count = 0
		_liquid.multimesh.visible_instance_count = 0
		_blobs.multimesh.visible_instance_count = 0

func _ring(at: Vector3, radius: float, color: Color) -> void:
	if _ring_count >= RING_CAPACITY:
		return
	_rings.multimesh.set_instance_transform(_ring_count, Transform3D(Basis.IDENTITY.scaled(Vector3(radius, 1.0, radius)), at))
	_rings.multimesh.set_instance_color(_ring_count, color)
	_ring_count += 1

func draw() -> void:
	_ring_count = 0
	_liquid_count = 0
	_blob_count = 0
	for a in _h._active_count:
		var slot := _h._active[a]
		if not _h.is_alive(slot):
			continue
		var behavior := _behavior(slot)
		if behavior == HordeEnemyDefinition.Behavior.AMBUSHER and _ambush[slot] != Ambush.LANDED:
			var land := _h._attack_target[slot] if _ambush[slot] != Ambush.HANG else Vector3(_h._pos[slot].x, _h.ground_height(_h._pos[slot]), _h._pos[slot].y)
			_ring(land + Vector3.UP * 0.055, AMBUSH_LANDING_RADIUS, LANDING_COLOR if _ambush[slot] == Ambush.HANG else TELEGRAPH_COLOR)
		elif behavior == HordeEnemyDefinition.Behavior.SPRAYER and _h._mode[slot] == Horde.Mode.WINDUP:
			_ring(_h._attack_target[slot] + Vector3.UP * 0.055, FUEL_RADIUS, TELEGRAPH_COLOR)
		elif behavior == HordeEnemyDefinition.Behavior.BOMBER and _armed[slot] != 0:
			_ring(Vector3(_h._pos[slot].x, _h.ground_height(_h._pos[slot]) + 0.06, _h._pos[slot].y), _h._radius[slot] + 0.4, FRIENDLY_COLOR if _intent[slot] >= 0 else BOMB_COLOR)
	for d in _h._dying_count:
		var slot := _h._dying[d]
		if is_corpse_bomb(slot):
			_ring(_h.enemy_position(slot), 0.75 + 0.08 * sin(_clock * 18.0), FRIENDLY_COLOR if _intent[slot] >= 0 else BOMB_COLOR)
	for pool in FUEL_CAPACITY:
		if _fuel_life[pool] <= 0.0:
			continue
		var at := _fuel_pos[pool] + Vector3.UP * 0.035
		var color := BURN_COLOR if _fuel_burning[pool] != 0 else FUEL_COLOR
		_liquid.multimesh.set_instance_transform(_liquid_count, Transform3D(Basis.IDENTITY.scaled(Vector3(FUEL_RADIUS, 1.0, FUEL_RADIUS)), at))
		_liquid.multimesh.set_instance_color(_liquid_count, color.darkened(0.38))
		_liquid_count += 1
		_ring(at + Vector3.UP * (0.12 if _fuel_burning[pool] != 0 else 0.015), FUEL_RADIUS, color)
	for lob in LOB_CAPACITY:
		if _lob_life[lob] <= 0.0:
			continue
		_blobs.multimesh.set_instance_transform(_blob_count, Transform3D(Basis.IDENTITY, _lob_pos[lob]))
		_blobs.multimesh.set_instance_color(_blob_count, FUEL_COLOR)
		_blob_count += 1
	_rings.multimesh.visible_instance_count = _ring_count
	_liquid.multimesh.visible_instance_count = _liquid_count
	_blobs.multimesh.visible_instance_count = _blob_count
