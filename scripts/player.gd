class_name ArenaPlayer
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died
signal shot_fired
signal hit_confirmed(killed: bool)
## Consecutive direct-hit shots; misses, taking damage or a 2.5 s gap reset it.
signal combo_changed(hits: int, bonus: float)
signal weapon_changed(definition: WeaponDefinition, index: int)
## Automatic rotation after an empty primary magazine; manual changes use weapon_changed only.
signal auto_swapped(hand: int)
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
const STARTING_RESERVE_MAGAZINES := 3
const MAX_RESERVE_MAGAZINES := 6
## Visual camera kick spring (radians, Hz-derived) and its accumulation cap.
const CAMERA_KICK_OMEGA := TAU * 5.0
const CAMERA_KICK_DAMPING := 0.85
const CAMERA_KICK_MAX := 0.012
const MAX_SHOTS_PER_TICK := 8
const FIRE_HITCH_LIMIT := 0.1
const MELEE_SWEEP_TIME := 0.065
signal melee_released(hand: int, secondary: bool)
var _melee_hand := -1
var _melee_phase := 0 # 1 windup, 2 sweep; cooldown owns recovery.
var _melee_left := 0.0
var _melee_elapsed := 0.0
var _melee_reach := 0.0
var _melee_arc := 0.0
var _melee_scale := 1.0
var _melee_push := 1.0
var _melee_stun := 0.0
var _melee_type := 0
var _melee_secondary := false
var _melee_damage := 0.0
var _melee_critical := false
var _melee_quickdraw := false
var _melee_alive_before := 0
var _melee_direct := false
var _melee_world := false
var _melee_wall: Dictionary = {}
var _melee_origin := Vector3.ZERO
var _melee_basis := Basis.IDENTITY
var _melee_seen := PackedInt32Array()
var _melee_generations := PackedInt32Array()
var _melee_shock_filter: Callable

## Only the focused gun fires; holstered guns reload and collect cross-charge.
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
signal secondary_fired(hand: int)
var secondary_charge := PackedFloat32Array()
var secondaries: Array[SecondaryFire] = []
var mining_tool: MiningTool
var _secondary_scenes: Array[PackedScene] = []
var _magazines := PackedInt32Array()
var _reserves := PackedInt32Array()
var _reloads := PackedFloat32Array()
var _draw_left := 0.0
var _alternate_held := false
var _alternate_drilling := false
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
# Per-shot direct/area components per slot, combined only after front plating.
var _hit_slots := PackedInt32Array()
var _hit_damage := PackedFloat32Array()
var _hit_direct_damage := PackedFloat32Array()
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
	_hit_direct_damage.resize(Horde.CAPACITY)
	_hit_lookup.resize(Horde.CAPACITY)
	_hit_lookup.fill(-1)
	_hit_critical.resize(Horde.CAPACITY)
	_hit_direct.resize(Horde.CAPACITY)
	_hit_push.resize(Horde.CAPACITY)
	_splash_hits.resize(Horde.CAPACITY)
	_melee_seen.resize(Horde.CAPACITY)
	_melee_generations.resize(Horde.CAPACITY)
	_melee_shock_filter = _melee_shock_target
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

## Refresh effective definitions outside the shot path. Upgrades preserve ammo,
## reload progress and charge; replacing a gun resets its magazine, reserve and meter.
func refresh_weapons() -> void:
	if not is_node_ready() and _query == null:
		return
	weapons.resize(mini(3, weapons.size()))
	while _views.size() > weapons.size():
		var old := _views.pop_back() as WeaponView
		if old != null:
			old.queue_free()
		var alt := secondaries.pop_back() as SecondaryFire
		if alt != null:
			alt.cancel()
			alt.queue_free()
		_secondary_scenes.pop_back()
		_view_scenes.pop_back()
		_directions.pop_back()
	_fire_cooldowns.resize(weapons.size())
	_spins.resize(weapons.size())
	_magazines.resize(weapons.size())
	_reserves.resize(weapons.size())
	_reloads.resize(weapons.size())
	secondary_charge.resize(weapons.size())
	for slot in range(weapons.size()):
		var definition := weapons[slot]
		var fresh := slot >= _views.size()
		if fresh:
			_views.append(null)
			_view_scenes.append(null)
			secondaries.append(null)
			_secondary_scenes.append(null)
			var directions := PackedVector3Array()
			directions.resize(WeaponHand.MAX_PROJECTILES)
			_directions.append(directions)
		var scene := definition.view_scene if definition != null else null
		if fresh or _view_scenes[slot] != scene:
			if _melee_hand == slot:
				cancel_secondaries()
			if _views[slot] != null:
				_views[slot].queue_free()
				_views[slot] = null
			_view_scenes[slot] = scene
			_magazines[slot] = definition.magazine_size if definition != null and definition.kind == WeaponDefinition.Kind.FIREARM else 0
			_reserves[slot] = _magazines[slot] * STARTING_RESERVE_MAGAZINES
			_reloads[slot] = 0.0
			secondary_charge[slot] = 35.0
			_fire_cooldowns[slot] = 0.0
			_spins[slot] = 0.0
			if scene != null:
				var view := scene.instantiate() as WeaponView
				view.position = Vector3(0.24, -0.22, -0.38)
				camera.add_child(view)
				view.prepare(WeaponHand.MAX_PROJECTILES)
				_views[slot] = view
		if definition == null:
			continue
		if _views[slot] != null:
			_views[slot].configure(definition)
		if fresh or _secondary_scenes[slot] != definition.secondary_scene:
			if secondaries[slot] != null:
				secondaries[slot].cancel()
				secondaries[slot].queue_free()
			secondaries[slot] = null
			_secondary_scenes[slot] = definition.secondary_scene
			if definition.secondary_scene != null:
				var alternate := definition.secondary_scene.instantiate() as SecondaryFire
				camera.add_child(alternate)
				alternate.setup(self, horde, run_state, slot, _views[slot], definition)
				alternate.fired.connect(_on_secondary_fired.bind(slot))
				secondaries[slot] = alternate
		elif secondaries[slot] != null:
			secondaries[slot].configure(definition)
		var count := _projectile_count(definition)
		var radius := tan(deg_to_rad(definition.spread_degrees))
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
	cancel_melee()
	if secondaries[selected_weapon] != null:
		secondaries[selected_weapon].cancel()
	_alternate_held = Input.is_action_pressed("mine")
	_alternate_drilling = false
	_draw_left = 0.2
	selected_weapon = index
	_quickdraw_left = 1.5 if run_state != null \
			and run_state.upgrade_levels.get(&"mod_quickdraw", 0) > 0 else 0.0
	weapon_changed.emit(weapons[index], index)

func ammo(hand: int) -> int:
	return _magazines[hand]

func reserve_ammo(hand: int) -> int:
	return _reserves[hand]

func reserve_capacity(hand: int) -> int:
	return weapons[hand].magazine_size * MAX_RESERVE_MAGAZINES if weapons[hand] != null and weapons[hand].kind == WeaponDefinition.Kind.FIREARM else 0

## Ammo packs restore one magazine's worth to every equipped gun's reserve.
## A pack stays in the world if all reserves are full.
func add_ammo(magazines: int = 1) -> bool:
	if not active or magazines <= 0:
		return false
	var gained := false
	for hand in weapons.size():
		if weapons[hand] == null or weapons[hand].kind == WeaponDefinition.Kind.MELEE:
			continue
		var before := _reserves[hand]
		_reserves[hand] = mini(reserve_capacity(hand), before + weapons[hand].magazine_size * magazines)
		gained = gained or _reserves[hand] > before
	return gained

## Pick a loaded, ready gun in hand order. Never bounce between empty guns.
func _auto_swap_empty() -> void:
	if weapons[selected_weapon] == null or weapons[selected_weapon].kind == WeaponDefinition.Kind.MELEE or _magazines[selected_weapon] > 0:
		return
	for offset in range(1, weapons.size()):
		var hand := (selected_weapon + offset) % weapons.size()
		if weapons[hand] != null and _views[hand] != null \
				and (weapons[hand].kind == WeaponDefinition.Kind.MELEE or (_magazines[hand] > 0 and _reloads[hand] == 0.0)):
			select_weapon(hand)
			auto_swapped.emit(hand)
			return

func is_reloading(hand: int) -> bool:
	return _reloads[hand] > 0.0

func reload_progress(hand: int) -> float:
	return 1.0 - _reloads[hand] / maxf(0.01, weapons[hand].reload_time)

func add_secondary_charge(hand: int, amount: float) -> void:
	if hand >= 0 and hand < secondary_charge.size():
		secondary_charge[hand] = clampf(secondary_charge[hand] + amount, 0.0, 100.0)

func _on_secondary_fired(hand: int) -> void:
	add_secondary_charge(hand, -secondaries[hand].charge_cost)
	secondary_fired.emit(hand)

func cancel_secondaries() -> void:
	cancel_melee()
	for alternate in secondaries:
		if alternate != null:
			alternate.cancel()
	_alternate_held = false
	_alternate_drilling = false

func drilling() -> bool:
	return _alternate_drilling and Input.is_action_pressed("mine")

## Re-reads run upgrades; keeps current damage taken when max health grows.
func refresh_stats() -> void:
	var bonus := run_state.max_health_bonus if run_state != null else 0
	var previous := max_health
	max_health = base_max_health + bonus
	health = clampi(health + maxi(0, max_health - previous), 0, max_health)
	health_changed.emit(health, max_health)

## Blocks firing until the fire button is released (after menus and recapture).
func suppress_fire_until_release() -> void:
	cancel_secondaries()
	_waiting_for_fire_release = Input.is_action_pressed("fire")
	_alternate_held = Input.is_action_pressed("mine")
	_alternate_drilling = false

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
	var mining := active and drilling()
	for slot in range(_views.size()):
		var view := _views[slot]
		if view != null:
			view.set_focus(slot == selected_weapon, slot, is_reloading(slot), reload_progress(slot))
			view.animate_motion(delta, speed_ratio, velocity.dot(global_basis.x), is_on_floor(), active, mining and slot == selected_weapon)
			view.set_spin(_spins[slot] if active else 0.0)
	_step_camera_kick(delta)
	camera.rotation = _camera_rest_rotation + _camera_kick
	# Abilities may change FOV; ease back without an additional firing punch.
	camera.fov = lerpf(camera.fov, 90.0 + speed_ratio * 2.5, 1.0 - exp(-5.0 * delta))
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
		cancel_secondaries()
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

	_draw_left = maxf(0.0, _draw_left - delta)
	var alternate := secondaries[selected_weapon] if not secondaries.is_empty() else null
	var held := captured and Input.is_action_pressed("mine")
	if held and not _alternate_held:
		_alternate_drilling = mining_tool != null and mining_tool.has_target()
		if not _alternate_drilling and alternate != null and _draw_left <= 0.0 \
				and alternate.is_ready() and secondary_charge[selected_weapon] >= alternate.charge_cost:
			alternate.press()
	elif not held and _alternate_held:
		if not _alternate_drilling and alternate != null:
			alternate.release()
		_alternate_drilling = false
	_alternate_held = held
	if not captured:
		cancel_secondaries()
	_step_melee(delta)
	var overspin := alternate != null and alternate.primary_rate_multiplier() > 1.0
	var trigger := captured and not _waiting_for_fire_release and not held \
			and Input.is_action_pressed("fire") and _draw_left <= 0.0
	if alternate != null and alternate.is_active() and not overspin:
		trigger = false
	# RMB starts Overspin; LMB remains its trigger even if RMB stays held.
	if overspin:
		trigger = captured and not _waiting_for_fire_release and Input.is_action_pressed("fire") and _draw_left <= 0.0
	for slot in range(weapons.size()):
		if not active or get_tree().paused:
			break
		var definition := weapons[slot]
		if definition == null or _views[slot] == null:
			continue
		var focused := slot == selected_weapon
		var shooting := trigger and focused
		var firearm := definition.kind == WeaponDefinition.Kind.FIREARM
		if firearm and _reloads[slot] > 0.0:
			_reloads[slot] = maxf(0.0, _reloads[slot] - delta / (1.6 if focused else 1.0))
			if _reloads[slot] == 0.0:
				var transferred := mini(definition.magazine_size - _magazines[slot], _reserves[slot])
				_magazines[slot] += transferred
				_reserves[slot] -= transferred
		elif firearm and _reserves[slot] > 0 and _magazines[slot] < definition.magazine_size \
				and (not focused or _magazines[slot] == 0):
			_reloads[slot] = definition.reload_time
		if definition.spin_up_time > 0.0:
			if focused and overspin:
				_spins[slot] = 1.0
			elif shooting:
				_spins[slot] = minf(1.0, _spins[slot] + delta / definition.spin_up_time)
			else:
				_spins[slot] = maxf(0.0, _spins[slot] - delta / maxf(0.01, definition.spin_down_time))
		# Only a continuously firing focused hand retains fractional overshoot.
		# Idle, drawing, reloading and long hitches cannot bank a burst.
		if shooting and _reloads[slot] == 0.0 and delta <= FIRE_HITCH_LIMIT:
			_fire_cooldowns[slot] -= delta
		else:
			_fire_cooldowns[slot] = maxf(0.0, _fire_cooldowns[slot] - delta)
		if not shooting or _reloads[slot] > 0.0:
			continue
		var interval := definition.fire_interval
		if definition.spin_up_time > 0.0:
			var eased := 1.0 - (1.0 - _spins[slot]) * (1.0 - _spins[slot])
			interval *= lerpf(definition.spin_up_start_multiplier, 1.0, eased)
		var rate := run_state.fire_rate_multiplier if run_state != null else 1.0
		if alternate != null:
			rate *= alternate.primary_rate_multiplier()
		interval = maxf(0.001, interval / maxf(0.1, rate))
		if not firearm:
			if _fire_cooldowns[slot] <= 0.0 and _melee_hand < 0:
				_fire_cooldowns[slot] += interval
				_begin_melee(slot, definition.melee_windup, definition.range_meters, definition.melee_arc_degrees, 1.0, 1.0, definition.melee_stun, definition.damage_type, false, interval)
			continue
		var shots := 0
		while active and not get_tree().paused and selected_weapon == slot and _magazines[slot] > 0 and _fire_cooldowns[slot] <= 0.0 and shots < MAX_SHOTS_PER_TICK:
			_fire_cooldowns[slot] += interval
			_magazines[slot] -= 1
			shots += 1
			_shoot(slot)
			if _magazines[slot] == 0 and _reserves[slot] > 0:
				_reloads[slot] = definition.reload_time
		if shots == MAX_SHOTS_PER_TICK:
			_fire_cooldowns[slot] = maxf(0.0, _fire_cooldowns[slot])
	# Rotate only after the entire shot/reload loop, avoiding two guns firing in
	# the same physics tick. Held RMB and active alternate effects retain focus.
	if active and trigger and not held and (alternate == null or not alternate.is_active()):
		_auto_swap_empty()

## HUD/alternate consumers: windup and sweep belong to the focused hand.
func melee_busy() -> bool:
	return _melee_hand >= 0

func melee_progress() -> float:
	return clampf(_melee_elapsed / MELEE_SWEEP_TIME, 0.0, 1.0) if _melee_phase == 2 else 0.0

func begin_melee_secondary(hand: int, windup: float, reach: float, arc: float, damage_scale: float, push_scale: float, stun: float, damage_type: int) -> bool:
	if not active or hand != selected_weapon or melee_busy() or _draw_left > 0.0:
		return false
	_fire_cooldowns[hand] = maxf(_fire_cooldowns[hand], windup + MELEE_SWEEP_TIME + 0.25)
	_begin_melee(hand, windup, reach, arc, damage_scale, push_scale, stun, damage_type, true, windup + 0.35)
	return true

func _begin_melee(hand: int, windup: float, reach: float, arc: float, damage_scale: float, push_scale: float, stun: float, damage_type: int, secondary: bool, interval: float) -> void:
	_melee_hand = hand
	_melee_phase = 1
	_melee_left = windup
	_melee_elapsed = 0.0
	_melee_reach = reach
	_melee_arc = deg_to_rad(arc)
	_melee_scale = damage_scale
	_melee_push = push_scale
	_melee_stun = stun
	_melee_type = damage_type
	_melee_secondary = secondary
	_melee_seen.fill(-1)
	_melee_direct = false
	_melee_world = false
	_melee_wall.clear()
	for n in _hit_count:
		_hit_lookup[_hit_slots[n]] = -1
	_hit_count = 0
	_views[hand].melee_swing(windup, maxf(0.02, interval - windup - MELEE_SWEEP_TIME), secondary)

func cancel_melee() -> void:
	if _melee_hand >= 0 and _melee_hand < _views.size() and _views[_melee_hand] != null:
		_views[_melee_hand].cancel_melee()
	_melee_hand = -1
	_melee_phase = 0
	for n in _hit_count:
		_hit_lookup[_hit_slots[n]] = -1
	_hit_count = 0

func _step_melee(delta: float) -> void:
	if _melee_hand < 0:
		return
	if not active or selected_weapon != _melee_hand or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		cancel_melee()
		return
	var hand := _melee_hand
	var definition := weapons[hand]
	if _melee_phase == 1:
		_melee_left -= delta
		if _melee_left > 0.0:
			return
		delta = minf(delta, -_melee_left)
		_melee_phase = 2
		_melee_origin = camera.global_position
		_melee_basis = head.global_basis
		_melee_quickdraw = _quickdraw_left > 0.0
		_quickdraw_left = 0.0
		var combo := minf(COMBO_MAX_BONUS, maxf(0.0, float(combo_hits - 2) * 0.08))
		_melee_damage = definition.damage * _melee_scale * (run_state.damage_multiplier if run_state != null else 1.0) * (1.0 + combo) * (1.75 if _melee_quickdraw else 1.0)
		_melee_critical = run_state != null and run_state.roll_critical()
		if _melee_critical:
			_melee_damage *= run_state.crit_multiplier
		_melee_alive_before = horde.alive_count if horde != null else 0
		if not _melee_secondary:
			shot_fired.emit()
		_views[hand].melee_release(sound)
		melee_released.emit(hand, _melee_secondary)
	var previous := _melee_elapsed / MELEE_SWEEP_TIME
	_melee_elapsed = minf(MELEE_SWEEP_TIME, _melee_elapsed + delta)
	_collect_melee(previous, _melee_elapsed / MELEE_SWEEP_TIME)
	if _melee_elapsed >= MELEE_SWEEP_TIME:
		_finish_melee()

func _collect_melee(previous: float, progress: float) -> void:
	var origin := _melee_origin
	var aim := _melee_basis
	var definition := weapons[_melee_hand]
	if horde != null:
		var count := horde.query_radius(origin, _melee_reach, _hits)
		var start := lerpf(-_melee_arc * 0.5, _melee_arc * 0.5, previous)
		var end := lerpf(-_melee_arc * 0.5, _melee_arc * 0.5, progress)
		for n in count:
			var slot := _hits[n]
			var generation := horde.enemy_generation(slot)
			if _melee_seen[slot] == generation:
				continue
			var at := horde.enemy_position(slot)
			var contact := _melee_target_contact(slot, start, end)
			if contact == Vector3.INF:
				continue
			_melee_seen[slot] = generation
			_melee_generations[slot] = generation
			var amount := _melee_damage * (run_state.exposure_scale(at) if run_state != null else 1.0)
			if run_state != null and run_state.upgrade_levels.get(&"mod_executioner", 0) > 0 and horde.enemy_health_fraction(slot) < 0.35:
				amount *= 1.6
			_add_hit(slot, amount, _melee_critical, true)
			_hit_push[_hit_lookup[slot]] += (-aim.z) * definition.knockback * _melee_push * (1.6 if _melee_quickdraw else 1.0)
			_melee_direct = true
			_views[_melee_hand].melee_contact(contact, true, _melee_critical)
			if definition.explosion_radius > 0.0:
				_collect_melee_splash(contact, origin, definition)
	if not _melee_world and previous <= 0.5 and progress >= 0.5:
		_melee_world = true
		_query.from = origin
		_query.to = origin - aim.z * _melee_reach
		_melee_wall = get_world_3d().direct_space_state.intersect_ray(_query)

## A single volume/cover predicate is shared by the real sweep and its shock
## conduction, so elemental upgrades cannot sneak through walls or hit rear bodies.
func _melee_target_contact(slot: int, start: float, end: float) -> Vector3:
	var at := horde.enemy_position(slot)
	var body := horde.get_definition(slot)
	var center := _melee_basis.transposed() * (at - _melee_origin)
	if center.z >= 0.0:
		return Vector3.INF
	var horizontal := Vector2(center.x, center.z).length()
	var angular_radius := asin(clampf(body.radius / maxf(0.001, horizontal), 0.0, 1.0))
	var angle := atan2(center.x, -center.z)
	if angle + angular_radius < start or angle - angular_radius > end:
		return Vector3.INF
	# Nearest real upright body surface, not radius-query level forgiveness.
	var contact := at
	contact.y = clampf(_melee_origin.y + (-_melee_basis.z).y * horizontal, at.y - body.height * 0.5, at.y + body.height * 0.5)
	var flat := Vector3(_melee_origin.x - at.x, 0.0, _melee_origin.z - at.z)
	contact += flat.normalized() * minf(body.radius, flat.length())
	var local := _melee_basis.transposed() * (contact - _melee_origin)
	if local.length_squared() > _melee_reach * _melee_reach or absf(local.y) > maxf(0.5, Vector2(local.x, local.z).length() * tan(deg_to_rad(30.0))):
		return Vector3.INF
	return contact if _melee_visible(_melee_origin, contact) else Vector3.INF

func _melee_shock_target(source: int, slot: int) -> bool:
	if _melee_hand < 0 or _melee_phase != 2 or not active or get_tree().paused:
		return false
	var contact := _melee_target_contact(slot, -_melee_arc * 0.5, _melee_arc * 0.5)
	return contact != Vector3.INF and _melee_visible(horde.enemy_position(source), contact)

func _melee_visible(origin: Vector3, contact: Vector3) -> bool:
	_query.from = origin
	_query.to = contact
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()

func _collect_melee_splash(contact: Vector3, origin: Vector3, definition: WeaponDefinition) -> void:
	var count := horde.query_radius(contact, definition.explosion_radius, _splash_hits)
	for n in count:
		var slot := _splash_hits[n]
		var at := horde.enemy_position(slot)
		if (_melee_basis.transposed() * (at - origin)).z >= 0.0 or not _melee_visible(contact, at) or not _melee_visible(origin, at):
			continue
		_melee_generations[slot] = horde.enemy_generation(slot)
		_add_hit(slot, _melee_damage * definition.explosion_damage_fraction, _melee_critical, false)
		_hit_push[_hit_lookup[slot]] += (at - contact).normalized() * definition.explosion_knockback

func _finish_melee() -> void:
	var hand := _melee_hand
	if _melee_secondary and secondaries[hand] != null:
		secondaries[hand].call(&"commit_swing")
	if not _melee_wall.is_empty():
		var collider: Object = _melee_wall["collider"]
		if collider != null and collider.has_method(&"take_mining_damage"):
			collider.take_mining_damage(_melee_damage * MINING_SHARE * (run_state.mining_multiplier if run_state != null else 1.0), _melee_wall["position"], int(_melee_wall["shape"]))
			_views[hand].melee_contact(_melee_wall["position"], false, false)
		elif collider != null and collider.has_method(&"take_hit"):
			collider.take_hit(_melee_damage, _melee_wall["position"])
			_views[hand].melee_contact(_melee_wall["position"], false, false)
	var confirmed := false
	var critical_at := Vector3.INF
	for n in _hit_count:
		# Damage callbacks can synchronously cancel the remaining contacts.
		if _melee_hand != hand or not active or get_tree().paused:
			return
		var slot := _hit_slots[n]
		if not horde.is_alive(slot) or horde.enemy_generation(slot) != _melee_generations[slot]:
			continue
		confirmed = true
		if _hit_direct_damage[n] > 0.0 and _melee_stun > 0.0:
			horde.stun(slot, _melee_stun)
		if _melee_critical:
			critical_at = horde.enemy_position(slot)
		horde.damage_combined(slot, _hit_direct_damage[n], _melee_origin, _hit_damage[n], _hit_push[n], _melee_type, _hit_critical[n] != 0, _melee_shock_filter)
	if _melee_hand != hand or not active or get_tree().paused:
		return
	if _melee_direct:
		combo_hits += 1
		_combo_left = COMBO_WINDOW
		combo_changed.emit(combo_hits, minf(COMBO_MAX_BONUS, maxf(0.0, float(combo_hits - 2) * 0.08)))
	else:
		_reset_combo()
	if confirmed:
		var killed := horde.alive_count < _melee_alive_before
		hit_confirmed.emit(killed)
		_views[hand].confirm_hit(killed, sound, combo_hits, _melee_critical)
		for other in weapons.size():
			if other != hand:
				add_secondary_charge(other, minf(weapons[hand].fire_interval, 0.8) * 22.0 + (8.0 if killed else 0.0))
	if critical_at != Vector3.INF:
		critical_hit.emit(critical_at)
	_melee_hand = -1
	_melee_phase = 0
	if _melee_secondary and secondaries[hand] != null:
		secondaries[hand].call(&"finish_swing")

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
	# Camera kick is presentation only: ray aim is the head's stable basis.
	var aim := head.global_basis
	var forward := -aim.z
	var roll := Basis.IDENTITY
	var pellet_count := _projectile_count(definition)
	if pellet_count > 1 and definition.jitter_degrees > 0.0:
		roll = Basis(Vector3.FORWARD, _rng.randf() * TAU)
	var alternate := secondaries[hand]
	var jitter := tan(deg_to_rad(definition.jitter_degrees)) * (alternate.primary_spread_multiplier() if alternate != null else 1.0)
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
			_add_hit(slot, direct_damage, hit_critical, true)
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
					_add_hit(slot, pellet_damage * definition.explosion_damage_fraction, critical, false)
					_hit_push[_hit_lookup[slot]] += push
			view.show_blast(end, definition.explosion_radius)
	# Direct pellets and splash aggregate before any deaths or feedback.
	var confirmed := _hit_count > 0
	for n in _hit_count:
		horde.damage_combined(_hit_slots[n], _hit_direct_damage[n], origin, _hit_damage[n], _hit_push[n], definition.damage_type, _hit_critical[n] != 0)
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
		# Landed fire feeds the OTHER guns: damage upgrades cannot farm faster.
		var charge := minf(definition.fire_interval, 0.8) * 22.0 + (8.0 if killed else 0.0)
		for other in weapons.size():
			if other != hand:
				add_secondary_charge(other, charge)
	if critical_at != Vector3.INF:
		critical_hit.emit(critical_at)
	# Camera kick is a bounded temporary child rotation, never player/head aim.
	var kick := deg_to_rad(clampf(definition.recoil_degrees, 0.04, 0.3))
	var room := 1.0 - clampf(_camera_kick.x / CAMERA_KICK_MAX, 0.0, 1.0)
	var impulse := Vector3(kick * room, kick * _rng.randf_range(-0.08, 0.08), kick * _rng.randf_range(-0.1, 0.1))
	_camera_kick += impulse * 0.5
	_camera_kick_velocity += impulse * CAMERA_KICK_OMEGA
	_clamp_camera_kick()
	camera.rotation = _camera_rest_rotation + _camera_kick
	var bloom := 0.08 + definition.spread_degrees / 14.0 + definition.jitter_degrees / 10.0 + definition.recoil_degrees * 0.5
	aim_bloom = minf(1.0, aim_bloom + bloom * (1.0 - aim_bloom * 0.6))

func _reset_combo() -> void:
	if combo_hits == 0:
		return
	combo_hits = 0
	_combo_left = 0.0
	combo_changed.emit(0, 0.0)

func _add_hit(slot: int, amount: float, critical: bool, direct: bool) -> void:
	var index := _hit_lookup[slot]
	if index < 0:
		index = _hit_count
		_hit_count += 1
		_hit_lookup[slot] = index
		_hit_slots[index] = slot
		_hit_damage[index] = 0.0
		_hit_direct_damage[index] = 0.0
		_hit_critical[index] = 0
		_hit_push[index] = Vector3.ZERO
		_hit_direct[index] = 0
	if direct:
		_hit_direct_damage[index] += amount
	else:
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
		cancel_secondaries()
		velocity = Vector3.ZERO
		_dash_time = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()

func _survives_lethal_hit() -> bool:
	for guard in _death_guards:
		if guard.is_valid() and guard.call():
			return true
	return false
