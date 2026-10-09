extends SecondaryFire

## Six weapon-specific alternate modes share ray/ballistic pools, not behaviour.
enum Mode { TAG, LANCE, CONCUSSION, OVERSPIN, BREACH, NAPALM }
@export var mode: Mode = Mode.TAG
var _holding := false
var _charge := 0.0
var _sustain := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _projectile_time := 0.0
var _projectile_velocity := Vector3.ZERO
var _patch_time := 0.0
var _patch_tick := 0.0
var _query: PhysicsRayQueryParameters3D
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
var _projectile: MeshInstance3D
var _patch: MeshInstance3D
var _charge_glow: MeshInstance3D
var _flames: Array[MeshInstance3D] = []
var _patch_center := Vector3.ZERO

func _ready() -> void:
	_hits.resize(Horde.CAPACITY)
	_distances.resize(Horde.CAPACITY)
	if mode == Mode.LANCE:
		_charge_glow = _sphere(Color(0.12, 0.85, 1.0, 0.6), 0.02)
	if mode == Mode.BREACH or mode == Mode.NAPALM:
		_projectile = _sphere(Color(1, 0.48, 0.1), 0.10)
	if mode == Mode.NAPALM:
		_patch = _sphere(Color(1, 0.27, 0.04, 0.32), 1.0)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.16
		mesh.height = 0.65
		mesh.radial_segments = 7
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1, 0.38, 0.045, 0.65)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for n in 8:
			var flame := MeshInstance3D.new()
			flame.mesh = mesh
			flame.material_override = material
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(flame)
			flame.top_level = true
			flame.hide()
			_flames.append(flame)

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState, p_hand: int, p_view: WeaponView, p_definition: WeaponDefinition) -> void:
	super.setup(p_player, p_horde, p_run_state, p_hand, p_view, p_definition)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [player.get_rid()])

func _sphere(color: Color, radius: float) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.mesh = mesh
	sphere.material_override = material
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sphere)
	sphere.top_level = true
	sphere.hide()
	return sphere

func is_active() -> bool:
	return _holding or _burst_left > 0 or _sustain > 0.0

func primary_rate_multiplier() -> float:
	return 2.0 if mode == Mode.OVERSPIN and _sustain > 0.0 else 1.0

func primary_spread_multiplier() -> float:
	return 0.2 if mode == Mode.OVERSPIN and _sustain > 0.0 else 1.0

func charge_progress() -> float:
	return clampf(_charge / 0.7, 0.0, 1.0) if _holding else 0.0

func press() -> bool:
	if not is_ready() or is_active() or _projectile_time > 0.0:
		return false
	match mode:
		Mode.TAG:
			_burst_left = 3
			_burst_timer = 0.0
			_release_shot()
		Mode.LANCE:
			_holding = true
			_charge = 0.0
			_charge_glow.show()
		Mode.CONCUSSION:
			_concussion()
			_release_shot()
		Mode.OVERSPIN:
			_sustain = 3.0
			player.sound.play_cue(&"rail")
			_release_shot()
		Mode.BREACH, Mode.NAPALM:
			_launch()
			_release_shot()
	return true

func release() -> void:
	if mode != Mode.LANCE or not _holding:
		return
	_holding = false
	_charge_glow.hide()
	if _charge >= 0.7:
		_line(definition.damage * 3.0, 64, false, 260.0)
		_release_shot()
	_charge = 0.0

func cancel() -> void:
	_holding = false
	_charge = 0.0
	_sustain = 0.0
	_burst_left = 0
	if _charge_glow != null:
		_charge_glow.hide()
	# Projectiles and patches persist when holstered, but not after run/stage end.
	if player != null and not player.active:
		_projectile_time = 0.0
		_patch_time = 0.0
		if _projectile != null:
			_projectile.hide()
		if _patch != null:
			_patch.hide()
		for flame in _flames:
			flame.hide()

func _physics_process(delta: float) -> void:
	if player == null or not player.active:
		cancel()
		return
	_sustain = maxf(0.0, _sustain - delta)
	if _holding:
		_charge = minf(1.0, _charge + delta)
		_charge_glow.global_position = view.muzzle.global_position
		_charge_glow.scale = Vector3.ONE * lerpf(0.4, 1.5, charge_progress())
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer += 0.09
			_burst_left -= 1
			_line(definition.damage * 0.65, 2, true)
	if _projectile_time > 0.0:
		_projectile_time = maxf(0.0, _projectile_time - delta)
		var from := _projectile.global_position
		_projectile_velocity += Vector3.DOWN * 9.0 * delta
		var to := from + _projectile_velocity * delta
		var direction := to - from
		var length := direction.length()
		_query.from = from
		_query.to = to
		var wall := get_world_3d().direct_space_state.intersect_ray(_query)
		var reach := from.distance_to(wall["position"]) if not wall.is_empty() else length
		var count := horde.raycast(from, direction / maxf(0.001, length), reach, 1, _hits, _distances)
		if count > 0:
			to = from + direction.normalized() * _distances[0]
		elif not wall.is_empty():
			to = wall["position"]
		_projectile.global_position = to
		if count > 0 or not wall.is_empty() or _projectile_time == 0.0:
			_impact(to, wall if count == 0 else {})
	if _patch_time > 0.0:
		_patch_time = maxf(0.0, _patch_time - delta)
		_patch_tick -= delta
		if _patch_tick <= 0.0:
			_patch_tick += 0.25
			var count := horde.query_radius(_patch_center, 3.2, _hits)
			for n in count:
				var slot := _hits[n]
				if _visible(_patch_center + Vector3.UP * 0.25, horde.enemy_position(slot)):
					horde.slow(slot, 0.45, 0.5)
					horde.damage(slot, _damage(definition.damage * 1.8), Vector3.ZERO, DamageType.Kind.FIRE)
		for n in _flames.size():
			var angle := n * TAU / _flames.size()
			_flames[n].global_position = _patch_center + Vector3(cos(angle) * 1.8, 0.22 + sin(_patch_time * 12 + n) * 0.08, sin(angle) * 1.8)
			_flames[n].scale = Vector3(1.3, 2.0 + sin(_patch_time * 9 + n) * 0.6, 1.3)
			_flames[n].visible = _patch_time > 0.0
		_patch.visible = _patch_time > 0.0

func _damage(base: float) -> float:
	return base * (run_state.damage_multiplier if run_state != null else 1.0)

func _visible(from: Vector3, to: Vector3) -> bool:
	_query.from = from
	_query.to = to
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()

func _line(base_damage: float, pierce: int, tag := false, mining := 0.0) -> void:
	var origin := player.camera.global_position
	var direction := -player.head.global_basis.z
	_query.from = origin
	_query.to = origin + direction * definition.range_meters
	var wall := get_world_3d().direct_space_state.intersect_ray(_query)
	var reach := origin.distance_to(wall["position"]) if not wall.is_empty() else definition.range_meters
	var count := horde.raycast(origin, direction, reach, pierce, _hits, _distances)
	view.begin_shot(player.sound)
	var killed := false
	for n in count:
		var slot := _hits[n]
		if tag:
			horde.expose(slot, 4.0)
		killed = horde.damage(slot, _damage(base_damage), direction * definition.knockback, definition.damage_type) or killed
	var stopped := count >= pierce
	var end := origin + direction * (_distances[count - 1] if stopped else reach)
	view.show_ray(0, end, wall.get("normal", Vector3.ZERO), count > 0 or not wall.is_empty(), count > 0, mode == Mode.LANCE)
	if mining > 0.0 and not stopped and not wall.is_empty():
		_mine(wall, mining)
	if count > 0:
		player.hit_confirmed.emit(killed)
		view.confirm_hit(killed, player.sound, 0, mode == Mode.LANCE)

func _concussion() -> void:
	var origin := player.camera.global_position
	var forward := -player.head.global_basis.z
	var count := horde.query_radius(origin, 8.0, _hits)
	var hits := 0
	var killed := false
	for n in count:
		var slot := _hits[n]
		var at := horde.enemy_position(slot)
		var offset := at - origin
		if offset.normalized().dot(forward) < 0.72 or not _visible(origin, at):
			continue
		horde.stun(slot, 1.2)
		killed = horde.damage(slot, _damage(definition.damage * 2.0), forward * 36.0) or killed
		hits += 1
	view.begin_shot(player.sound)
	# Nine traces describe the actual forward cone, not an omnidirectional bubble.
	for n in 9:
		var angle := n * TAU / 8.0
		var direction := forward if n == 8 else player.head.global_basis * Vector3(cos(angle) * 0.7, sin(angle) * 0.7, -1).normalized()
		view.show_ray(n, origin + direction * 7.0, Vector3.ZERO, false, false)
	if hits > 0:
		player.hit_confirmed.emit(killed)
		view.confirm_hit(killed, player.sound, 0)

func _launch() -> void:
	_projectile_time = 1.8
	_projectile.global_position = player.camera.global_position
	_projectile_velocity = -player.head.global_basis.z * (19.0 if mode == Mode.BREACH else 13.0) + Vector3.UP * 2.0
	_projectile.show()
	view.begin_shot(player.sound)

func _impact(at: Vector3, wall: Dictionary) -> void:
	_projectile_time = 0.0
	_projectile.hide()
	if not wall.is_empty():
		at += wall["normal"] * 0.05
	if mode == Mode.BREACH:
		var count := horde.query_radius(at, 4.0, _hits)
		var hits := 0
		var killed := false
		for n in count:
			var slot := _hits[n]
			var enemy_at := horde.enemy_position(slot)
			if not _visible(at + Vector3.UP * 0.06, enemy_at):
				continue
			hits += 1
			killed = horde.damage(slot, _damage(definition.damage * 3.0), (enemy_at - at).normalized() * 30.0, definition.damage_type) or killed
		if not wall.is_empty():
			_mine(wall, 220.0)
		view.show_blast(at, 4.0)
		if hits > 0:
			player.hit_confirmed.emit(killed)
			view.confirm_hit(killed, player.sound, 0)
	else:
		_patch_center = Vector3(at.x, horde.ground_height(Vector2(at.x, at.z)) + 0.06, at.z)
		_patch_time = 4.0
		_patch_tick = 0.0
		_patch.global_position = _patch_center
		_patch.scale = Vector3(3.2, 0.08, 3.2)
		_patch.show()
		for flame in _flames:
			flame.show()

func _mine(wall: Dictionary, amount: float) -> void:
	var collider: Object = wall["collider"]
	if collider is MineralDeposit:
		collider.take_mining_damage(amount * (run_state.mining_multiplier if run_state != null else 1.0), wall["position"], int(wall["shape"]))
	elif collider != null and collider.has_method(&"take_hit"):
		collider.take_hit(_damage(amount), wall["position"])
