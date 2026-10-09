class_name ArenaPlayer
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died
signal shot_fired
signal hit_confirmed(killed: bool)
## Consecutive direct-hit shots; misses, taking damage or a 2.5 s gap reset it.
signal combo_changed(hits: int, bonus: float)
signal weapon_changed(definition: WeaponDefinition, index: int)
## Emitted after the class ability activates successfully.
signal ability_used(ability: ActiveAbility)
## A main-gun shot landed at least one critical hit (first critical target).
signal critical_hit(at: Vector3)

const SPEED := 9.5
const JUMP_SPEED := 6.5
const GRAVITY := 21.0
const JUMP_GRACE := 0.12
const MOUSE_SENSITIVITY := 0.0025
## Share of shot damage dealt to mineable colliders (before mining_multiplier).
const MINING_SHARE := 0.35
const COMBO_WINDOW := 2.5
const COMBO_MAX_BONUS := 0.4
## Visual camera kick spring (radians, Hz-derived) and its accumulation cap.
const CAMERA_KICK_OMEGA := TAU * 3.5
const CAMERA_KICK_DAMPING := 0.55
const CAMERA_KICK_MAX := 0.052
const FOV_PUNCH_MAX := 4.0

## Up to three simultaneous guns; selection focuses HUD/shop, not firing.
@export var weapons: Array[WeaponDefinition] = []
## Class ability; the root must be an ActiveAbility. Instanced in _ready.
@export var ability_scene: PackedScene
@export var base_max_health := 100
var selected_weapon := 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var sound: CombatAudio = $Sound

## Assigned by the stage before the player enters the tree.
var run_state: RunState
var horde: Horde
## Instanced from ability_scene; null when the scene has none.
var ability: ActiveAbility
var active := true
var max_health := 100
var health := 100
var _fire_cooldowns := PackedFloat32Array()
var combo_hits := 0
var _combo_left := 0.0
var _quickdraw_left := 0.0
var _waiting_for_fire_release := false
var _coyote_time := 0.0
var _jump_buffer := 0.0
var _regen := 0.0
var _invulnerable := 0.0
var _dash_velocity := Vector3.ZERO
var _dash_time := 0.0
## Spin progress and recovery belong to each hand, never the focused slot.
var _spins := PackedFloat32Array()
var _camera_rest_rotation := Vector3.ZERO
# Visual-only camera kick (pitch, yaw, roll) on a damped spring; never the player's aim.
var _camera_kick := Vector3.ZERO
var _camera_kick_velocity := Vector3.ZERO
var _fov_punch := 0.0
## 0..1 crosshair bloom from recent shots' spread and recoil; recovers over time.
var aim_bloom := 0.0
var _trauma := 0.0
var _shake_clock := 0.0
var _profile: Node
var _rng := RandomNumberGenerator.new()
var _views: Array[WeaponView] = []
var _directions: Array[PackedVector3Array] = []
var _view_scenes: Array[PackedScene] = []
var _query: PhysicsRayQueryParameters3D
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
# Per-shot combined damage per enemy slot; reused, never reallocated per shot.
var _hit_slots := PackedInt32Array()
var _hit_damage := PackedFloat32Array()
var _hit_count := 0
var _hit_lookup := PackedInt32Array()
var _hit_critical := PackedByteArray()
var _hit_direct := PackedByteArray()
var _hit_push := PackedVector3Array()
var _splash_hits := PackedInt32Array()
var _death_guards: Array[Callable] = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_profile = get_node_or_null(^"/root/Profile")
	_rng.randomize()
	refresh_stats()
	health = max_health
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [get_rid()])
	_camera_rest_rotation = camera.rotation
	_hits.resize(Horde.CAPACITY)
	_distances.resize(Horde.CAPACITY)
	_hit_slots.resize(Horde.CAPACITY)
	_hit_damage.resize(Horde.CAPACITY)
	_hit_lookup.resize(Horde.CAPACITY)
	_hit_lookup.fill(-1)
	_hit_critical.resize(Horde.CAPACITY)
	_hit_direct.resize(Horde.CAPACITY)
	_hit_push.resize(Horde.CAPACITY)
	_splash_hits.resize(Horde.CAPACITY)
	refresh_weapons()
	if ability_scene != null:
		var node := ability_scene.instantiate()
		ability = node as ActiveAbility
		if ability == null:
			push_error("ability_scene root must be an ActiveAbility")
			node.free()
		else:
			add_child(ability)
			ability.setup(self, horde, run_state)

## Refresh effective hand definitions and caches outside the firing path.
## Cooldowns/spin survive upgrades and changes of focus.
func refresh_weapons() -> void:
	if not is_node_ready() and _query == null:
		return
	if weapons.size() > 3:
		weapons.resize(3)
	while _views.size() > weapons.size():
		var old := _views.pop_back() as WeaponView
		if old != null:
			old.queue_free()
		_view_scenes.pop_back()
		_directions.pop_back()
	_fire_cooldowns.resize(weapons.size())
	_spins.resize(weapons.size())
	for slot in range(weapons.size()):
		var definition := weapons[slot]
		if slot >= _views.size():
			_views.append(null)
			_view_scenes.append(null)
			var directions := PackedVector3Array()
			directions.resize(WeaponHand.MAX_PROJECTILES)
			_directions.append(directions)
		var scene := definition.view_scene if definition != null else null
		if _view_scenes[slot] != scene:
			if _views[slot] != null:
				_views[slot].queue_free()
				_views[slot] = null
			_view_scenes[slot] = scene
			if scene != null:
				var node := scene.instantiate()
				var view := node as WeaponView
				if view == null:
					node.free()
					push_error("Weapon view_scene root must be a WeaponView")
				else:
					# Set BEFORE _ready captures the authored resting transform.
					view.position = Vector3(-0.44, -0.27, -0.66) if slot == 0 \
							else Vector3(0.44, -0.27, -0.66) if slot == 1 \
							else Vector3(0.0, -0.35, -0.70)
					if slot == 2:
						view.scale *= 0.75
					camera.add_child(view)
					view.prepare(WeaponHand.MAX_PROJECTILES)
					_views[slot] = view
		if definition == null:
			continue
		if _views[slot] != null:
			_views[slot].configure(definition)
		var count := _projectile_count(definition)
		var radius := tan(deg_to_rad(definition.spread_degrees))
		# Bonus rays on precision guns still diverge enough to read as multishot.
		if count > definition.pellet_count:
			radius = maxf(radius, tan(deg_to_rad(1.5)))
		_directions[slot][0] = Vector3.FORWARD
		for pellet in range(1, count):
			var angle := TAU * float(pellet - 1) / float(count - 1)
			_directions[slot][pellet] = Vector3(cos(angle) * radius, sin(angle) * radius, -1.0).normalized()
	selected_weapon = clampi(selected_weapon, 0, maxi(0, weapons.size() - 1))
	if not weapons.is_empty() and weapons[selected_weapon] != null:
		weapon_changed.emit(weapons[selected_weapon], selected_weapon)

func _projectile_count(definition: WeaponDefinition) -> int:
	return clampi(definition.pellet_count + (run_state.projectile_bonus if run_state != null else 0), \
			1, WeaponHand.MAX_PROJECTILES)

func select_weapon(index: int) -> void:
	if not active or index < 0 or index >= _views.size() or weapons[index] == null:
		return
	if selected_weapon == index:
		return
	selected_weapon = index
	_quickdraw_left = 1.5 if run_state != null \
			and run_state.upgrade_levels.get(&"mod_quickdraw", 0) > 0 else 0.0
	weapon_changed.emit(weapons[index], index)

## Re-reads run upgrades; keeps current damage taken when max health grows.
func refresh_stats() -> void:
	var bonus := run_state.max_health_bonus if run_state != null else 0
	var previous := max_health
	max_health = base_max_health + bonus
	health = clampi(health + maxi(0, max_health - previous), 0, max_health)
	health_changed.emit(health, max_health)

## Blocks firing until the fire button is released (after menus and recapture).
func suppress_fire_until_release() -> void:
	_waiting_for_fire_release = Input.is_action_pressed("fire")

func heal(amount: int) -> void:
	if not active or amount <= 0 or health >= max_health:
		return
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)

## Ignores all incoming damage for at least `seconds`.
func grant_invulnerability(seconds: float) -> void:
	_invulnerable = maxf(_invulnerable, seconds)

func is_invulnerable() -> bool:
	return _invulnerable > 0.0

## Moves at `dash_velocity` for `duration` seconds, overriding input and gravity.
func dash(dash_velocity: Vector3, duration: float) -> void:
	_dash_velocity = dash_velocity
	_dash_time = duration

func is_dashing() -> bool:
	return _dash_time > 0.0

## Adds camera shake trauma (0..1); shake strength grows with its square.
func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_waiting_for_fire_release = false
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_waiting_for_fire_release = true
		return
	if event.is_action_pressed("weapon_1"):
		select_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		select_weapon(1)
	elif event.is_action_pressed("weapon_3"):
		select_weapon(2)
	elif event.is_action_pressed("weapon_next") and not _views.is_empty():
		select_weapon((selected_weapon + 1) % _views.size())
	elif event.is_action_pressed("weapon_previous") and not _views.is_empty():
		select_weapon(posmod(selected_weapon - 1, _views.size()))
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := _mouse_sensitivity()
		rotate_y(-event.relative.x * sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		for view in _views:
			if view != null:
				view.aim(event.relative)

func _mouse_sensitivity() -> float:
	if _profile == null:
		return MOUSE_SENSITIVITY
	var settings: Variant = _profile.get(&"settings")
	if settings is Dictionary:
		return MOUSE_SENSITIVITY * float(settings.get("mouse_sensitivity", 1.0))
	return MOUSE_SENSITIVITY

func _process(delta: float) -> void:
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPEED, 0.0, 1.0)
	var mining := active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("mine")
	for slot in range(_views.size()):
		var view := _views[slot]
		if view != null:
			view.animate_motion(delta, speed_ratio, velocity.dot(global_basis.x), is_on_floor(), active, mining and slot == 0)
			view.set_spin(_spins[slot] if active else 0.0)
	_step_camera_kick(delta)
	camera.rotation = _camera_rest_rotation + _camera_kick
	# Abilities add to camera.fov directly; the shot punch rides on top and decays faster.
	var fov_base := camera.fov - _fov_punch
	_fov_punch *= exp(-11.0 * delta)
	camera.fov = lerpf(fov_base, 90.0 + speed_ratio * 2.5, 1.0 - exp(-5.0 * delta)) + _fov_punch
	aim_bloom *= exp(-5.0 * delta)
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	_shake_clock += delta
	var shake := _trauma * _trauma * 0.12
	camera.h_offset = sin(_shake_clock * 71.0) * shake
	camera.v_offset = sin(_shake_clock * 53.0 + 1.3) * shake

func _step_camera_kick(delta: float) -> void:
	# The spring is ~99% settled after 0.4 s; longer frames (hitches) would also
	# exceed the fixed-step integrator's stable range, so they simply rest it.
	if delta >= 0.4:
		_camera_kick = Vector3.ZERO
		_camera_kick_velocity = Vector3.ZERO
		return
	var steps := clampi(ceili(delta * 240.0), 1, 96)
	var step := delta / float(steps)
	for n in steps:
		_camera_kick_velocity -= (_camera_kick * (CAMERA_KICK_OMEGA * CAMERA_KICK_OMEGA) \
				+ _camera_kick_velocity * (2.0 * CAMERA_KICK_DAMPING * CAMERA_KICK_OMEGA)) * step
		_camera_kick += _camera_kick_velocity * step
	_clamp_camera_kick()

func _clamp_camera_kick() -> void:
	var limit := Vector3(CAMERA_KICK_MAX, CAMERA_KICK_MAX * 0.4, CAMERA_KICK_MAX * 0.4)
	var kick := _camera_kick.clamp(Vector3(-CAMERA_KICK_MAX * 0.5, -limit.y, -limit.z), limit)
	for axis in 3:
		if kick[axis] != _camera_kick[axis]:
			_camera_kick_velocity[axis] = 0.0
	_camera_kick = kick

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return
	_invulnerable = maxf(0.0, _invulnerable - delta)
	if _combo_left > 0.0:
		_combo_left -= delta
		if _combo_left <= 0.0:
			_reset_combo()
	_quickdraw_left = maxf(0.0, _quickdraw_left - delta)
	if run_state != null and run_state.regen_per_second > 0.0 and health < max_health:
		_regen += run_state.regen_per_second * delta
		if _regen >= 1.0:
			heal(int(_regen))
			_regen -= floorf(_regen)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if ability != null and captured and Input.is_action_just_pressed("ability") and ability.activate():
		ability_used.emit(ability)
	if _dash_time > 0.0:
		_dash()
		_dash_time -= delta
	else:
		_move(delta)
	_stay_in_arena()

	var trigger := captured and not _waiting_for_fire_release and Input.is_action_pressed("fire")
	for slot in range(weapons.size()):
		if not active:
			break # A boss kill may synchronously open the round shop.
		var definition := weapons[slot]
		if definition == null or _views[slot] == null:
			continue
		if definition.spin_up_time > 0.0:
			if trigger:
				_spins[slot] = minf(1.0, _spins[slot] + delta / definition.spin_up_time)
			else:
				_spins[slot] = maxf(0.0, _spins[slot] - delta / maxf(0.01, definition.spin_down_time))
		_fire_cooldowns[slot] = maxf(-delta, _fire_cooldowns[slot] - delta)
		if trigger and _fire_cooldowns[slot] <= 0.0:
			var interval := definition.fire_interval
			if definition.spin_up_time > 0.0:
				var eased := 1.0 - (1.0 - _spins[slot]) * (1.0 - _spins[slot])
				interval *= lerpf(definition.spin_up_start_multiplier, 1.0, eased)
			var rate := run_state.fire_rate_multiplier if run_state != null else 1.0
			_fire_cooldowns[slot] += maxf(0.01, interval / maxf(0.1, rate))
			_shoot(slot)

## Grapples and dashes from raised decks can clear the perimeter walls; the
## player never leaves the stage's play area.
func _stay_in_arena() -> void:
	if horde == null:
		return
	var area := horde.play_area.grow(-0.35)
	if not area.has_area():
		return
	var at := global_position
	var x := clampf(at.x, area.position.x, area.end.x)
	var z := clampf(at.z, area.position.y, area.end.y)
	if x != at.x:
		velocity.x = 0.0
		_dash_velocity.x = 0.0
	if z != at.z:
		velocity.z = 0.0
		_dash_velocity.z = 0.0
	if x != at.x or z != at.z:
		global_position = Vector3(x, at.y, z)

func _dash() -> void:
	velocity = _dash_velocity
	move_and_slide()
	if _dash_time <= get_physics_process_delta_time():
		# Exit the dash carrying normal running speed.
		var flat := Vector3(_dash_velocity.x, 0.0, _dash_velocity.z)
		velocity = flat.normalized() * SPEED if not flat.is_zero_approx() else Vector3.ZERO

func _move(delta: float) -> void:
	var grounded := is_on_floor()
	_coyote_time = JUMP_GRACE if grounded else maxf(0.0, _coyote_time - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_GRACE
	if not grounded:
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if _jump_buffer > 0.0 and _coyote_time > 0.0:
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_coyote_time = 0.0
		sound.play_cue(&"jump")

	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(movement.x, 0.0, movement.y)
	var speed := SPEED * (run_state.move_speed_multiplier if run_state != null else 1.0)
	var acceleration := 65.0 if grounded else 26.0
	if movement.is_zero_approx() and grounded:
		acceleration = 85.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	var falling_speed := velocity.y
	move_and_slide()
	if not grounded and is_on_floor() and falling_speed < -3.0:
		for view in _views:
			if view != null:
				view.land(falling_speed)
		sound.play_cue(&"land")

func _shoot(hand: int) -> void:
	var definition := weapons[hand]
	var view := _views[hand]
	var quickdraw := hand == selected_weapon and _quickdraw_left > 0.0
	if quickdraw:
		_quickdraw_left = 0.0 # The focused hand spends its capacitor, even on a miss.
	var combo_bonus := minf(COMBO_MAX_BONUS, maxf(0.0, float(combo_hits - 2) * 0.08))
	var shot_damage := definition.damage * (run_state.damage_multiplier if run_state != null else 1.0) \
			* (1.0 + combo_bonus) * (1.75 if quickdraw else 1.0)
	var pierce := definition.pierce + (run_state.pierce_bonus if run_state != null else 0)
	var longshot: bool = run_state != null and int(run_state.upgrade_levels.get(&"mod_longshot", 0)) > 0
	var executioner: bool = run_state != null and int(run_state.upgrade_levels.get(&"mod_executioner", 0)) > 0
	var mining := shot_damage * MINING_SHARE * (run_state.mining_multiplier if run_state != null else 1.0)
	view.begin_shot(sound)
	shot_fired.emit()
	if definition.screen_shake > 0.0:
		add_shake(definition.screen_shake)
	for n in _hit_count:
		_hit_lookup[_hit_slots[n]] = -1
	_hit_count = 0
	var origin := camera.global_position
	var aim := camera.global_basis
	var forward := -aim.z
	var roll := Basis.IDENTITY
	var pellet_count := _projectile_count(definition)
	if pellet_count > 1 and definition.jitter_degrees > 0.0:
		roll = Basis(Vector3.FORWARD, _rng.randf() * TAU)
	var jitter := tan(deg_to_rad(definition.jitter_degrees))
	var space := get_world_3d().direct_space_state
	var directions := _directions[hand]
	var explosive := definition.explosion_radius > 0.0
	var alive_before := horde.alive_count if horde != null else 0
	var critical_at := Vector3.INF
	var direct_confirmed := false
	_query.from = origin
	for pellet in range(pellet_count):
		var local := roll * directions[pellet]
		if jitter > 0.0:
			local = (local + Vector3(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter), 0.0)).normalized()
		var direction := aim * local
		# World geometry (walls, obstacles) limits every ray; enemies are not physics bodies.
		var reach := definition.range_meters
		_query.to = origin + direction * reach
		var wall := space.intersect_ray(_query)
		var normal := Vector3.ZERO
		if not wall.is_empty():
			reach = origin.distance_to(wall["position"])
			normal = wall["normal"]
		var hits := 0
		if horde != null:
			hits = horde.raycast(origin, direction, reach, pierce + 1, _hits, _distances)
		# Lucky rolls stay per pellet; head/core crits are resolved per pierced enemy.
		var pellet_damage := shot_damage
		var critical := run_state != null and run_state.roll_critical()
		var ray_critical := critical
		if critical:
			pellet_damage *= run_state.crit_multiplier
			if hits > 0 and critical_at == Vector3.INF:
				critical_at = horde.enemy_position(_hits[0])
		for n in hits:
			var slot := _hits[n]
			var exposure := run_state.exposure_scale(horde.enemy_position(slot)) if run_state != null else 1.0
			var precision := horde.weak_spot_hit(slot, origin, direction, reach)
			var hit_critical := critical or precision
			ray_critical = ray_critical or hit_critical
			var direct_damage := pellet_damage * exposure
			if precision:
				var multiplier := run_state.crit_multiplier if run_state != null else RunState.BASE_CRIT_MULTIPLIER
				direct_damage = shot_damage * exposure * (multiplier + RunState.WEAK_SPOT_CRIT_BONUS)
			if hit_critical and critical_at == Vector3.INF:
				critical_at = origin + direction * _distances[n]
			if longshot and _distances[n] > 15.0:
				direct_damage *= 1.4
			if executioner and horde.enemy_health_fraction(slot) < 0.35:
				direct_damage *= 1.6
			_add_hit(slot, direct_damage, hit_critical)
			var hit_index := _hit_lookup[slot]
			if _hit_direct[hit_index] == 0:
				_hit_push[hit_index] += forward * definition.knockback * (1.6 if quickdraw else 1.0)
				_hit_direct[hit_index] = 1
		direct_confirmed = direct_confirmed or hits > 0
		# The trace ends at the last enemy it stopped in, else at the wall.
		var stopped := hits > pierce
		var end := origin + direction * (_distances[hits - 1] if stopped else reach)
		if not stopped and not wall.is_empty():
			var collider: Object = wall["collider"]
			if collider != null and collider.has_method(&"take_mining_damage"):
				collider.take_mining_damage(mining, wall["position"], int(wall["shape"]))
			# Shootable world objects (explosive barrels, switches) take the full shot.
			if collider != null and collider.has_method(&"take_hit"):
				collider.take_hit(shot_damage, wall["position"])
		view.show_ray(pellet, end, normal, stopped or not wall.is_empty(), stopped, ray_critical)
		if explosive:
			if horde != null:
				var splash_count := horde.query_radius(end, definition.explosion_radius, _splash_hits)
				for n in splash_count:
					var slot := _splash_hits[n]
					var away := horde.enemy_position(slot) - end
					away.y = 0.0
					var push := away.normalized() * definition.explosion_knockback if away.length_squared() > 0.0001 else Vector3.ZERO
					_add_hit(slot, pellet_damage * definition.explosion_damage_fraction, critical)
					_hit_push[_hit_lookup[slot]] += push
			view.show_blast(end, definition.explosion_radius)
	# Direct pellets and splash aggregate before any deaths or feedback.
	var confirmed := _hit_count > 0
	for n in _hit_count:
		horde.damage(_hit_slots[n], _hit_damage[n], _hit_push[n], definition.damage_type, _hit_critical[n] != 0)
	if direct_confirmed:
		combo_hits += 1 # One beat per direct-hit shot, not per pellet or blast victim.
		_combo_left = COMBO_WINDOW
		combo_changed.emit(combo_hits, minf(COMBO_MAX_BONUS, maxf(0.0, float(combo_hits - 2) * 0.08)))
	else:
		_reset_combo()
	if confirmed:
		var killed := horde.alive_count < alive_before
		hit_confirmed.emit(killed)
		view.confirm_hit(killed, sound, combo_hits, critical_at != Vector3.INF)
		add_shake(0.095 if killed else 0.035)
	if critical_at != Vector3.INF:
		critical_hit.emit(critical_at)
	# Camera kick is a bounded temporary child rotation, never player/head aim.
	var kick := deg_to_rad(clampf(definition.recoil_degrees, 0.15, 0.6)) * 2.4
	# Kicks landing on an already-raised view add less, so sustained fire plateaus.
	var room := 1.0 - clampf(_camera_kick.x / CAMERA_KICK_MAX, 0.0, 1.0)
	var side := -1.0 if hand == 0 else 1.0 if hand == 1 else _rng.randf_range(-1.0, 1.0)
	var impulse := Vector3(kick * room, kick * (side * 0.25 + _rng.randf_range(-0.15, 0.15)), kick * _rng.randf_range(-0.4, 0.4))
	_camera_kick += impulse * 0.5
	_camera_kick_velocity += impulse * CAMERA_KICK_OMEGA
	_clamp_camera_kick()
	camera.rotation = _camera_rest_rotation + _camera_kick
	if definition.recoil_degrees >= 0.4:
		var punch := minf((definition.recoil_degrees - 0.3) * 6.0, FOV_PUNCH_MAX - _fov_punch)
		if punch > 0.0:
			_fov_punch += punch
			camera.fov += punch
	var bloom := 0.08 + definition.spread_degrees / 14.0 + definition.jitter_degrees / 10.0 + definition.recoil_degrees * 0.5
	aim_bloom = minf(1.0, aim_bloom + bloom * (1.0 - aim_bloom * 0.6))

func _reset_combo() -> void:
	if combo_hits == 0:
		return
	combo_hits = 0
	_combo_left = 0.0
	combo_changed.emit(0, 0.0)

func _add_hit(slot: int, amount: float, critical: bool) -> void:
	var index := _hit_lookup[slot]
	if index < 0:
		index = _hit_count
		_hit_count += 1
		_hit_lookup[slot] = index
		_hit_slots[index] = slot
		_hit_damage[index] = 0.0
		_hit_critical[index] = 0
		_hit_push[index] = Vector3.ZERO
		_hit_direct[index] = 0
	_hit_damage[index] += amount
	if critical:
		_hit_critical[index] = 1

## Registers a callable returning true to survive a lethal hit at 1 HP
## (e.g. the Last Stand perk). Guards are asked in registration order.
func add_death_guard(guard: Callable) -> void:
	if not _death_guards.has(guard):
		_death_guards.append(guard)

func remove_death_guard(guard: Callable) -> void:
	_death_guards.erase(guard)

func take_damage(amount: int) -> void:
	if not active or amount <= 0 or _invulnerable > 0.0:
		return
	_reset_combo()
	var armor := run_state.armor if run_state != null else 0.0
	health = maxi(0, health - maxi(1, amount - int(armor)))
	if health == 0 and _survives_lethal_hit():
		health = 1
	health_changed.emit(health, max_health)
	sound.play_cue(&"hurt")
	if health == 0:
		active = false
		velocity = Vector3.ZERO
		_dash_time = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()

func _survives_lethal_hit() -> bool:
	for guard in _death_guards:
		if guard.is_valid() and guard.call():
			return true
	return false
