class_name ArenaPlayer
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died
signal shot_fired
signal hit_confirmed(killed: bool)
## STYLE points from primary kills, never nonlethal hit spam.
signal combo_changed(hits: int, bonus: float)
signal weapon_changed(definition: WeaponDefinition)
signal ability_used(ability: ActiveAbility)
## A main-gun shot landed at least one critical hit (first critical target).
signal critical_hit(at: Vector3)
## Two skills combined: `id` is &"crush", &"collapse" or &"ram".
signal ability_combo(id: StringName)
signal arena_scored(points: int, label: String)
signal drop_fired(weapon_id: StringName)
## Kick/parry/combo payoff label for HUD callouts (also kept in last_action_label).
signal action_feedback(label: String)

const SPEED := 9.5
const JUMP_SPEED := 6.5
const GRAVITY := 21.0
const JUMP_GRACE := 0.12
const MOUSE_SENSITIVITY := 0.0025
const COMBO_WINDOW := 6.0
const COMBO_DECAY_INTERVAL := 1.5
const COMBO_MIN_WINDOW := 3.0
const COMBO_MIN_DECAY_INTERVAL := 0.45
const COMBO_PRESSURE_START := 10
const COMBO_PRESSURE_FULL := 100
const COMBO_MAX_BONUS := 0.4
const RHYTHM_MAX_BONUS := 9.0 # Only a banked DROP multiplies a manual perfect shot by ten.
const RHYTHM_PERFECT_WINDOW := 0.10
const SLIDE_DURATION := 0.8
const SLIDE_SPEED := 16.0
const SLIDE_HEIGHT := 0.85
const STANDING_HEIGHT := 1.8
## Visual camera kick spring (radians, Hz-derived) and its accumulation cap.
const CAMERA_KICK_OMEGA := TAU * 5.0
const CAMERA_KICK_DAMPING := 0.85
const CAMERA_KICK_MAX := 0.012
const MAX_SHOTS_PER_TICK := 8
const FIRE_HITCH_LIMIT := 0.1
const ABILITY_ACTIONS: Array[StringName] = [&"ability_1", &"ability_2", &"ability_3", &"ability_4", &"ability_5"]
const DROP_WEAPONS: Array[StringName] = [&"scatter", &"rail", &"autocannon", &"tvarohomet", &"maschine", &"cihlomet"]
## RMB: a fresh press parries the nearest incoming projectile, else kicks.
const KICK_RECOVERY := 0.4
const KICK_MISS_RECOVERY := 0.75
const PARRY_RECOVERY := 0.3
const PARRY_REACH := 3.2
const PARRY_HEAL := 6
## Kicking off a body mid-air bounces like a bumper; a whiff commits to a dive.
const STOMP_BOUNCE := 7.5
const STOMP_DIVE := 16.0
const KICK_PROP_RADIUS := 0.9
const KICK_PROP_REACH := 1.1
## Close finishes heal a small, budgeted amount; the budget refills slowly.
const FINISH_HEAL := 6
const FINISH_RANGE := 3.5
const FINISH_HEAL_BUDGET := 18.0
const FINISH_HEAL_REFILL := 4.0
## F execution commits to a collision-driven leap, then a flip kick and recovery.
## Selection is long-range; contact still requires a clear, close recorded life.
const FINISHER_REACH := 8.0
const FINISHER_DURATION := 0.80
const FINISHER_CONTACT := 0.46
const FINISHER_CONTACT_REACH := 2.3
const FINISHER_STANDOFF := 1.35
const FINISHER_LIFT := 5.0
const FINISHER_MAX_SPEED := 22.0
const FINISHER_HEAL := 12
const ACTION_STYLE := 10
## Rail direct hits on launched (airborne) bodies.
const AIR_MAIL_MULTIPLIER := 2.0
const AIR_MAIL_STYLE := 6
## Two equipped sources share one upgraded build and five independent abilities.
@export var weapon: WeaponDefinition
@export var ability_scenes: Array[PackedScene] = []
@export var base_max_health := 100

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var sound: CombatAudio = $Sound
@onready var body_shape: CollisionShape3D = $CollisionShape3D

## Assigned by the stage before the player enters the tree.
var run_state: RunState
var horde: Horde
var abilities: Array[ActiveAbility] = []
var active := true
var max_health := 100
var health := 100
var _fire_cooldown := 0.0
var mining_tool: MiningTool
var gear_effects: GearEffects
var _health_gear_multiplier := 1.0
# Preserve the unrounded fraction across curse toggles, including repeated swaps.
var _gear_health_fraction := 1.0
var _gear_health_snapshot := 100
var _draw_left := 0.0
var _waiting_for_mine_release := false
var combo_hits := 0
var arena_score := 0
var drop_charge := 0.0
var drop_ready: bool:
	get:
		return drop_charge >= 1.0
var last_drop_used := false
var _arena_recovery := false
var _action_charge_allowed := true
var last_action_label := ""
var kick_ready: bool:
	get:
		return _kick_recovery <= 0.0
var _kick_recovery := 0.0
var _waiting_for_kick_release := false
var _kick_view: KickView
var _kick_query: PhysicsShapeQueryParameters3D
var _heal_budget := FINISH_HEAL_BUDGET
var _action_credits := 0
var finisher_target := -1
var _finisher_target_generation := -1
var _finisher_slot := -1
var _finisher_generation := -1
var _finisher_left := 0.0
var _finisher_direction := Vector3.ZERO
var _finisher_travel_left := 0.0
var _finisher_speed := 0.0
var finisher_variant := KickView.Finish.FLIP
var _finisher_order := PackedInt32Array()
var _finisher_next := 0
var _last_finisher_variant := -1
var _last_kill_weapon: StringName = &""
var _combo_left := 0.0
## Snapshot the current phase's period; damage never extends its deadline.
var _combo_period := COMBO_WINDOW
var combo_intensity: float:
	get:
		return clampf(float(combo_hits) / float(COMBO_PRESSURE_FULL), 0.0, 1.0)
var combo_fraction: float:
	get:
		return clampf(_combo_left / _combo_period, 0.0, 1.0)
var _quickdraw_left := 0.0
## Last primary shot's timing reward, published before shot_fired for HUD feedback.
var last_rhythm_bonus := 0.0
var _waiting_for_fire_release := false
var _coyote_time := 0.0
var _jump_buffer := 0.0
var _air_jump_available := true
var _waiting_for_jump_release := false
var _waiting_for_slide_release := false
var _slide_left := 0.0
var _slide_visual := 0.0
var _crouched := false
var _standing_query: PhysicsShapeQueryParameters3D
var _head_height := 0.55
var _regen := 0.0
var _invulnerable := 0.0
var _dash_velocity := Vector3.ZERO
var _dash_time := 0.0
var _ability_protection: Dictionary = {}
## Every combo trigger, for run stats and checks; callouts are rate-limited.
var combo_counts: Dictionary = {}
var _combo_quiet: Dictionary = {}
var _spin := 0.0
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
var _view: WeaponView
var _weapon_id: StringName = &""
var _directions := PackedVector3Array()
var _view_scene: PackedScene
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
var _hit_precision := PackedByteArray()
var _hit_direct := PackedByteArray()
var _hit_push := PackedVector3Array()
var _hit_generation := PackedInt64Array()
var _hit_position := PackedVector3Array()
## Defeated constituent lives, not a boolean: one fused victim can credit up to eight.
var _hit_killed := PackedByteArray()
## Horde combo flags (frozen/burning/electric/airborne) captured before damage.
var _hit_flags := PackedInt32Array()
var _hit_applied := PackedByteArray()
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
	body_shape.shape = body_shape.shape.duplicate()
	_head_height = head.position.y
	_standing_query = PhysicsShapeQueryParameters3D.new()
	_standing_query.shape = body_shape.shape.duplicate()
	(_standing_query.shape as CapsuleShape3D).height = STANDING_HEIGHT - 0.02
	_standing_query.exclude = [get_rid()]
	_standing_query.collision_mask = collision_mask
	_hits.resize(Horde.CAPACITY)
	_distances.resize(Horde.CAPACITY)
	_hit_slots.resize(Horde.CAPACITY)
	_hit_damage.resize(Horde.CAPACITY)
	_hit_direct_damage.resize(Horde.CAPACITY)
	_hit_lookup.resize(Horde.CAPACITY)
	_hit_lookup.fill(-1)
	_hit_critical.resize(Horde.CAPACITY)
	_hit_precision.resize(Horde.CAPACITY)
	_hit_direct.resize(Horde.CAPACITY)
	_hit_push.resize(Horde.CAPACITY)
	_splash_hits.resize(Horde.CAPACITY)
	_hit_generation.resize(Horde.CAPACITY)
	_hit_position.resize(Horde.CAPACITY)
	_hit_killed.resize(Horde.CAPACITY)
	_hit_applied.resize(Horde.CAPACITY)
	_hit_flags.resize(Horde.CAPACITY)
	_kick_query = PhysicsShapeQueryParameters3D.new()
	var reach := SphereShape3D.new()
	reach.radius = KICK_PROP_RADIUS
	_kick_query.shape = reach
	_kick_query.exclude = [get_rid()]
	_kick_view = KickView.new()
	camera.add_child(_kick_view)
	_finisher_order.resize(KickView.Finish.COUNT)
	for variation in KickView.Finish.COUNT:
		_finisher_order[variation] = variation
	_finisher_next = KickView.Finish.COUNT
	if horde != null:
		horde.action_killed.connect(_on_action_killed)
	_directions.resize(WeaponBuild.MAX_PROJECTILES)
	refresh_weapon()
	gear_effects = GearEffects.new()
	add_child(gear_effects)
	gear_effects.setup(self, horde, run_state)
	for slot in range(mini(5, ability_scenes.size())):
		var scene := ability_scenes[slot]
		if scene == null:
			continue
		var node := scene.instantiate()
		var skill := node as ActiveAbility
		if skill == null:
			push_error("ability_scenes roots must be ActiveAbility")
			node.free()
			continue
		skill.slot = slot
		add_child(skill)
		skill.setup(self, horde, run_state)
		abilities.append(skill)

## Effective definitions and ray patterns are rebuilt only on upgrade or swap.
func refresh_weapon() -> void:
	if run_state != null and run_state.primary != null:
		weapon = run_state.primary.definition
	var source := run_state.primary.source if run_state != null and run_state.primary != null else weapon
	_weapon_id = StringName(source.resource_path.get_file().get_basename()) if source != null else &""
	if _query == null:
		return
	var scene := weapon.view_scene if weapon != null else null
	if _view_scene != scene:
		if _view != null:
			_view.hide()
			_view.queue_free()
			_view = null
		_view_scene = scene
		_fire_cooldown = 0.0
		_spin = 0.0
		if scene != null:
			_view = scene.instantiate() as WeaponView
			_view.position = Vector3(0.24, -0.22, -0.38)
			camera.add_child(_view)
			_view.prepare(WeaponBuild.MAX_PROJECTILES)
	if weapon == null:
		return
	if _view != null:
		_view.configure(weapon)
	var count := _projectile_count(weapon)
	var radius := tan(deg_to_rad(weapon.spread_degrees))
	if count > weapon.pellet_count:
		radius = maxf(radius, tan(deg_to_rad(1.5)))
	_directions[0] = Vector3.FORWARD
	for pellet in range(1, count):
		var angle := TAU * float(pellet - 1) / float(count - 1)
		_directions[pellet] = Vector3(cos(angle) * radius, sin(angle) * radius, -1.0).normalized()
	weapon_changed.emit(weapon)

func _projectile_count(definition: WeaponDefinition) -> int:
	return clampi(definition.pellet_count + (run_state.projectile_bonus if run_state != null else 0), \
			1, WeaponBuild.MAX_PROJECTILES)

## Wheel/Q toggles the two drafted guns; replacements happen only during breaks.
func quick_swap() -> void:
	if not active or run_state == null or run_state.primary == null:
		return
	if run_state.swap_equipped():
		_draw_left = 0.2
		_quickdraw_left = 1.5 if run_state.upgrade_levels.get(&"mod_quickdraw", 0) > 0 else 0.0
		refresh_weapon()

## Menu transitions cancel input, not independently running ability effects.
func cancel_actions() -> void:
	_waiting_for_fire_release = Input.is_action_pressed("fire")
	_waiting_for_mine_release = Input.is_action_pressed("mine")
	_waiting_for_jump_release = Input.is_action_pressed("jump")
	_waiting_for_slide_release = Input.is_action_pressed("slide")
	_waiting_for_kick_release = Input.is_action_pressed("kick")
	_jump_buffer = 0.0
	_slide_left = 0.0
	if is_finishing() and sound != null:
		sound.stop_finisher()
	if is_finishing() and _finisher_slot >= 0:
		velocity.x = 0.0
		velocity.z = 0.0
	_finisher_left = 0.0
	_finisher_slot = -1
	finisher_target = -1
	_finisher_travel_left = 0.0
	_finisher_direction = Vector3.ZERO
	if _kick_view != null:
		_kick_view.cancel()
	if mining_tool != null:
		mining_tool.cancel()

func mining_ready() -> bool:
	return active and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not is_finishing() and not finisher_ready() and mining_tool != null and mining_tool.has_target()

func drilling() -> bool:
	return active and mining_tool != null and mining_tool.is_smashing()


## Upgrade growth keeps damage taken; changing the curse preserves health fraction.
func refresh_stats() -> void:
	var bonus := run_state.max_health_bonus if run_state != null else 0
	var multiplier := run_state.gear_health_multiplier if run_state != null else 1.0
	var previous := max_health
	max_health = maxi(1, floori(float(base_max_health + bonus) * multiplier))
	if not is_equal_approx(multiplier, _health_gear_multiplier):
		if health != _gear_health_snapshot:
			_gear_health_fraction = float(health) / float(maxi(1, previous))
		health = clampi(floori(_gear_health_fraction * float(max_health)), 1 if health > 0 else 0, max_health)
	else:
		health = clampi(health + maxi(0, max_health - previous), 0, max_health)
		_gear_health_fraction = float(health) / float(max_health)
	_health_gear_multiplier = multiplier
	_gear_health_snapshot = health
	health_changed.emit(health, max_health)

## Blocks firing until the fire button is released (after menus and recapture).
func suppress_fire_until_release() -> void:
	cancel_actions()

func heal(amount: int) -> void:
	if not active or amount <= 0 or health >= max_health:
		return
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)

## Ignores all incoming damage for at least `seconds`.
func grant_invulnerability(seconds: float) -> void:
	_invulnerable = maxf(_invulnerable, seconds)

## Source ownership lets independent shields expire without cancelling each other.
func set_ability_protection(source: ActiveAbility, enabled: bool) -> void:
	if enabled:
		_ability_protection[source] = true
	else:
		_ability_protection.erase(source)

func is_invulnerable() -> bool:
	return _invulnerable > 0.0 or not _ability_protection.is_empty()

func is_shielded_by_other(source: ActiveAbility) -> bool:
	for key in _ability_protection:
		if key != source:
			return true
	return false

func active_gravity_well() -> GravityWell:
	for skill in abilities:
		if skill is GravityWell and (skill as GravityWell).is_active():
			return skill
	return null

## Ticking effects may trigger a combo many times a second; the HUD callout
## for each combo is spaced out while every trigger still counts.
func announce_combo(id: StringName) -> void:
	combo_counts[id] = int(combo_counts.get(id, 0)) + 1
	if float(_combo_quiet.get(id, 0.0)) > 0.0:
		return
	_combo_quiet[id] = 1.2
	add_shake(0.12)
	ability_combo.emit(id)

## Moves at `dash_velocity` for `duration` seconds, overriding input and gravity.
func dash(dash_velocity: Vector3, duration: float) -> void:
	_dash_velocity = dash_velocity
	_dash_time = duration
	if gear_effects != null:
		gear_effects.begin_dash()

func is_dashing() -> bool:
	return _dash_time > 0.0

func is_sliding() -> bool:
	return _slide_left > 0.0

func set_arena_recovery(enabled: bool) -> void:
	_arena_recovery = enabled

## Adds camera shake trauma (0..1); shake strength grows with its square.
func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)

func _input(event: InputEvent) -> void:
	if not active or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_waiting_for_fire_release = false
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			cancel_actions()
			_waiting_for_fire_release = true
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or get_tree().paused:
		return
	if event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_previous") \
			or event.is_action_pressed("weapon_swap"):
		quick_swap()
	if event is InputEventMouseMotion:
		var sensitivity := _mouse_sensitivity()
		rotate_y(-event.relative.x * sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		if _view != null:
			_view.aim(event.relative)

func _mouse_sensitivity() -> float:
	if _profile == null:
		return MOUSE_SENSITIVITY
	var settings: Variant = _profile.get(&"settings")
	if settings is Dictionary:
		return MOUSE_SENSITIVITY * float(settings.get("mouse_sensitivity", 1.0))
	return MOUSE_SENSITIVITY

func _process(delta: float) -> void:
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPEED, 0.0, 1.0)
	var mining := mining_tool != null and mining_tool.is_presented()
	if _view != null:
		_view.visible = active and not mining and not is_finishing()
		_view.set_sliding(is_sliding() and active)
		_view.animate_motion(delta, speed_ratio, velocity.dot(global_basis.x), is_on_floor(), active)
		_view.set_spin(_spin if active and not mining and not is_finishing() else 0.0)
	_kick_view.set_sliding(is_sliding() and active and not mining and not is_finishing())
	_slide_visual = lerpf(_slide_visual, 1.0 if is_sliding() and active else 0.0, 1.0 - exp(-14.0 * delta))
	_step_camera_kick(delta)
	var flight := clampf((FINISHER_DURATION - _finisher_left) / FINISHER_CONTACT, 0.0, 1.0) if is_finishing() else 0.0
	var leap_bank := sin(flight * PI)
	# The limbs perform the acrobatics; bounded motion never steers actual aim.
	var flourish := Vector3(-sin(flight * TAU) * 0.16, 0.0, leap_bank * 0.14)
	match finisher_variant:
		KickView.Finish.CORKSCREW:
			flourish = Vector3(-leap_bank * 0.06, 0.0, sin(flight * TAU) * 0.20)
		KickView.Finish.DROP_KICK:
			flourish = Vector3(leap_bank * 0.10, 0.0, -leap_bank * 0.07)
		KickView.Finish.AXE_KICK:
			flourish = Vector3(-sin(flight * TAU) * 0.22, 0.0, leap_bank * 0.05)
	camera.rotation = _camera_rest_rotation + _camera_kick + flourish + Vector3(0.0, 0.0, _slide_visual * 0.055)
	camera.fov = lerpf(camera.fov, 90.0 + speed_ratio * 2.5 + _slide_visual * 6.0 + leap_bank * 18.0, 1.0 - exp(-8.0 * delta))
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
	if not active or get_tree().paused:
		cancel_actions()
		velocity = Vector3.ZERO
		return
	_invulnerable = maxf(0.0, _invulnerable - delta)
	for id: StringName in _combo_quiet:
		_combo_quiet[id] = maxf(0.0, float(_combo_quiet[id]) - delta)
	if combo_hits > 0 and not _arena_recovery:
		_combo_left -= delta
		while _combo_left <= 0.0 and combo_hits > 0:
			_lose_combo(maxi(1, ceili(combo_hits * 0.1)))
			if combo_hits > 0:
				_combo_period = _combo_phase_period(false)
				_combo_left += _combo_period
	_quickdraw_left = maxf(0.0, _quickdraw_left - delta)
	_kick_recovery = maxf(0.0, _kick_recovery - delta)
	_heal_budget = minf(FINISH_HEAL_BUDGET, _heal_budget + FINISH_HEAL_REFILL * delta)
	if run_state != null and run_state.regen_per_second > 0.0 and health < max_health:
		_regen += run_state.regen_per_second * delta
		if _regen >= 1.0:
			heal(int(_regen))
			_regen -= floorf(_regen)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not Input.is_action_pressed("fire"):
		_waiting_for_fire_release = false
	if not Input.is_action_pressed("mine"):
		_waiting_for_mine_release = false
	if not Input.is_action_pressed("kick"):
		_waiting_for_kick_release = false
	if not captured:
		cancel_actions()
	if captured and not is_finishing():
		for skill in abilities:
			if run_state != null and not run_state.is_ability_unlocked(skill.slot):
				continue
			if Input.is_action_pressed(ABILITY_ACTIONS[skill.slot]) and Input.is_action_just_pressed(ABILITY_ACTIONS[skill.slot]) and skill.activate():
				ability_used.emit(skill)
		# One fresh press, one strike: held or recovering presses are consumed.
		if active and not _waiting_for_kick_release and Input.is_action_just_pressed("kick"):
			_waiting_for_kick_release = true
			if _kick_recovery <= 0.0 and not drilling() and not is_finishing():
				_kick()
	if is_finishing() and _finisher_slot >= 0:
		_move_finisher(delta)
	elif _dash_time > 0.0:
		var dash_start := global_position
		_dash()
		_dash_time -= delta
		if gear_effects != null:
			gear_effects.record_dash_step(dash_start, global_position)
	else:
		_move(delta)
	_stay_in_arena()
	_step_finisher(delta)
	_update_finisher_target()
	_draw_left = maxf(0.0, _draw_left - delta)
	if weapon == null or _view == null:
		return
	var shooting := captured and not _waiting_for_fire_release and not is_finishing() \
			and not (mining_tool != null and mining_tool.is_presented()) \
			and not (mining_tool != null and mining_tool.finisher_press_pending()) \
			and Input.is_action_pressed("fire") and _draw_left <= 0.0
	if weapon.spin_up_time > 0.0:
		if shooting:
			_spin = minf(1.0, _spin + delta / weapon.spin_up_time)
		else:
			_spin = maxf(0.0, _spin - delta / maxf(0.01, weapon.spin_down_time))
	# Continuous fire retains fractional overshoot; idle and hitches cannot bank bursts.
	if shooting and delta <= FIRE_HITCH_LIMIT:
		_fire_cooldown -= delta
	else:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if not shooting:
		return
	var interval := weapon.fire_interval
	if weapon.spin_up_time > 0.0:
		var eased := 1.0 - (1.0 - _spin) * (1.0 - _spin)
		interval *= lerpf(weapon.spin_up_start_multiplier, 1.0, eased)
	var rate := run_state.fire_rate_multiplier if run_state != null else 1.0
	interval = maxf(0.001, interval / maxf(0.1, rate))
	var shots := 0
	while active and not get_tree().paused and _fire_cooldown <= 0.0 and shots < MAX_SHOTS_PER_TICK:
		_fire_cooldown += interval
		shots += 1
		_shoot(shots == 1 and Input.is_action_just_pressed("fire"))
	if shots == MAX_SHOTS_PER_TICK:
		_fire_cooldown = maxf(0.0, _fire_cooldown)


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
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not Input.is_action_pressed("jump"):
		_waiting_for_jump_release = false
	if not Input.is_action_pressed("slide"):
		_waiting_for_slide_release = false
	if grounded:
		_air_jump_available = true
	_coyote_time = JUMP_GRACE if grounded else maxf(0.0, _coyote_time - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if captured and not _waiting_for_jump_release and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_GRACE
	if not grounded:
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if captured else Vector2.ZERO
	var direction := global_basis * Vector3(movement.x, 0.0, movement.y)
	var speed := SPEED * (run_state.move_speed_multiplier if run_state != null else 1.0)
	if captured and not _waiting_for_slide_release and Input.is_action_just_pressed("slide") \
			and grounded and not _crouched and Vector2(velocity.x, velocity.z).length() >= speed * 0.5:
		_slide_left = SLIDE_DURATION
		_set_crouched(true)
		var flat := Vector3(velocity.x, 0.0, velocity.z).normalized()
		var launch := maxf(SLIDE_SPEED, speed * 1.5) * (1.0 + 0.25 * float(_rank(&"build_slide")))
		velocity.x = flat.x * launch
		velocity.z = flat.z * launch
		sound.play_cue(&"land", 0.8)
		add_shake(0.08)
	_slide_left = maxf(0.0, _slide_left - delta)
	if _crouched and _slide_left <= 0.0 and _can_stand():
		_set_crouched(false)
	if _jump_buffer > 0.0 and not _crouched and (_coyote_time > 0.0 or _air_jump_available):
		if _coyote_time <= 0.0:
			_air_jump_available = false
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_coyote_time = 0.0
		sound.play_cue(&"jump")
	if is_sliding():
		# Preserve launch momentum; steering cannot invent more speed.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		var current_speed := maxf(speed, horizontal.length() - 5.0 * delta)
		if not direction.is_zero_approx():
			horizontal = horizontal.move_toward(direction.normalized() * current_speed, 8.0 * delta)
		horizontal = horizontal.normalized() * current_speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	else:
		var acceleration := 65.0 if grounded else 26.0
		if movement.is_zero_approx() and grounded:
			acceleration = 85.0
		if _crouched:
			speed *= 0.45
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	var falling_speed := velocity.y
	move_and_slide()
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0
	if not grounded and is_on_floor() and falling_speed < -3.0:
		if _view != null:
			_view.land(falling_speed)
		sound.play_cue(&"land")

func _set_crouched(enabled: bool) -> void:
	_crouched = enabled
	(body_shape.shape as CapsuleShape3D).height = SLIDE_HEIGHT if enabled else STANDING_HEIGHT
	body_shape.position.y = (SLIDE_HEIGHT - STANDING_HEIGHT) * 0.5 if enabled else 0.0
	head.position.y = -0.12 if enabled else _head_height

func _can_stand() -> bool:
	_standing_query.transform = global_transform
	return get_world_3d().direct_space_state.intersect_shape(_standing_query, 1).is_empty()

## RMB strike, resolved this tick with no aim or movement lock: parry a real
## incoming projectile in reach first, otherwise kick bodies and props. Only
## actual kills (via Horde.action_killed) earn score, STYLE and charge.
func _kick() -> void:
	var origin := camera.global_position
	var forward := -head.global_basis.z
	var return_rank := _rank(&"build_return")
	if horde != null and horde.parry_projectile(origin, forward, PARRY_REACH + 0.75 * float(return_rank)):
		_kick_recovery = 0.0 if return_rank > 0 else PARRY_RECOVERY
		heal(PARRY_HEAL)
		_kick_view.parry()
		if _view != null:
			_view.brace(0.6)
		sound.play_cue(&"hit", 1.7)
		add_shake(0.08)
		_feedback("PARRY")
		return
	var sliding := is_sliding()
	var credits := _action_credits
	var slam := not sliding and not is_on_floor()
	# Airborne kicks drive down into whatever is below and ahead.
	var direction := (forward + Vector3.DOWN * 1.5).normalized() if slam else forward
	var landed := horde != null and horde.kick(origin, direction, sliding, slam)
	if _kick_props(forward, slam):
		landed = true
	var kind := KickView.Kind.STOMP if slam else (KickView.Kind.SLIDE if sliding else KickView.Kind.KICK)
	_kick_view.kick(kind, landed)
	if _view != null:
		_view.brace(1.0)
	if not landed:
		_kick_recovery = KICK_MISS_RECOVERY
		if slam:
			velocity.y = minf(velocity.y, -STOMP_DIVE)
		sound.play_cue(&"jump", 0.6)
		add_shake(0.03)
		return
	_kick_recovery = 0.0 if sliding and _rank(&"build_slide") > 0 else KICK_RECOVERY
	if slam:
		velocity.y = STOMP_BOUNCE
		_air_jump_available = true
	sound.play_cue(&"land", 1.5)
	add_shake(0.28 if slam else 0.22)
	# A strike that already finished bodies keeps Horde's payoff callout.
	if _action_credits == credits:
		_feedback("STOMP" if slam else ("SLIDE KICK" if sliding else "KICK"))

func is_finishing() -> bool:
	return _finisher_left > 0.0

func finisher_ready() -> bool:
	return active and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not is_finishing() and horde != null and horde.is_dazed(finisher_target) \
			and horde.enemy_generation(finisher_target) == _finisher_target_generation

func _update_finisher_target() -> void:
	finisher_target = -1
	if active and not is_finishing() and horde != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		finisher_target = horde.finisher_target(camera.global_position, -head.global_basis.z, FINISHER_REACH)
		_finisher_target_generation = horde.enemy_generation(finisher_target)

## Shuffle a cached four-move bag; its boundary also cannot repeat the last move.
func _choose_finisher() -> void:
	if _finisher_next == KickView.Finish.COUNT:
		for index in range(KickView.Finish.COUNT - 1, 0, -1):
			var other := _rng.randi_range(0, index)
			var swap := _finisher_order[index]
			_finisher_order[index] = _finisher_order[other]
			_finisher_order[other] = swap
		if _finisher_order[0] == _last_finisher_variant:
			var other := _rng.randi_range(1, KickView.Finish.COUNT - 1)
			var swap := _finisher_order[0]
			_finisher_order[0] = _finisher_order[other]
			_finisher_order[other] = swap
		_finisher_next = 0
	finisher_variant = _finisher_order[_finisher_next] as KickView.Finish
	_finisher_next += 1
	_last_finisher_variant = finisher_variant

## MiningTool owns fresh F presses; this claims a valid enemy before salvage.
func try_finisher() -> bool:
	if not active or get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or is_finishing() or _waiting_for_mine_release or horde == null:
		return false
	var slot := horde.finisher_target(camera.global_position, -head.global_basis.z, FINISHER_REACH)
	if slot < 0:
		return false
	_finisher_slot = slot
	_finisher_generation = horde.enemy_generation(slot)
	var offset := horde.enemy_position(slot) - global_position
	offset.y = 0.0
	_finisher_direction = offset.normalized()
	_finisher_travel_left = maxf(0.0, offset.length() - FINISHER_STANDOFF)
	_finisher_speed = minf(FINISHER_MAX_SPEED, maxf(6.0, _finisher_travel_left / FINISHER_CONTACT))
	_dash_time = 0.0
	_dash_velocity = Vector3.ZERO
	_slide_left = 0.0
	if _crouched and _can_stand():
		_set_crouched(false)
	_jump_buffer = 0.0
	velocity.y = FINISHER_LIFT
	_finisher_left = FINISHER_DURATION
	finisher_target = -1
	_waiting_for_mine_release = true
	_waiting_for_fire_release = Input.is_action_pressed("fire")
	mining_tool.cancel()
	_choose_finisher()
	_kick_view.finish(FINISHER_DURATION, FINISHER_CONTACT, finisher_variant)
	sound.play_finisher(finisher_variant, false)
	add_shake(0.10)
	if _view != null:
		_view.brace(1.0)
	return true

## Spend only the launch's original travel budget: no homing or correction warp.
## CharacterBody sweeps the real capsule; an obstruction interrupts the action.
func _move_finisher(delta: float) -> void:
	if horde == null or not horde.is_dazed(_finisher_slot) \
			or horde.enemy_generation(_finisher_slot) != _finisher_generation:
		_interrupt_finisher()
		_move(delta)
		return
	var step := minf(_finisher_travel_left, _finisher_speed * delta)
	var launch_velocity := _finisher_direction * (step / delta)
	velocity.x = launch_velocity.x
	velocity.z = launch_velocity.z
	velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	_finisher_travel_left = maxf(0.0, _finisher_travel_left - maxf(0.0, (global_position - before).dot(_finisher_direction)))
	if is_on_wall() or is_on_ceiling():
		_interrupt_finisher()
		sound.play_cue(&"land", 0.75)
		add_shake(0.14)

func _interrupt_finisher() -> void:
	_finisher_left = 0.0
	_finisher_slot = -1
	_finisher_travel_left = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_kick_view.cancel()
	sound.stop_finisher()

func _step_finisher(delta: float) -> void:
	if not is_finishing():
		return
	var before := _finisher_left
	_finisher_left = maxf(0.0, _finisher_left - delta)
	var contact := FINISHER_DURATION - FINISHER_CONTACT
	if before > contact and _finisher_left <= contact:
		if horde != null and horde.finish(_finisher_slot, _finisher_generation, camera.global_position, FINISHER_CONTACT_REACH):
			velocity.y = minf(velocity.y, -3.0)
			sound.play_finisher(finisher_variant, true)
			add_shake(0.55)
			hit_confirmed.emit(true)
		_finisher_slot = -1

## Kickable props in front (or below, for a stomp) with a clear line from the body.
func _kick_props(forward: Vector3, slam: bool) -> bool:
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	var center := global_position + (Vector3.DOWN * 0.9 if slam else flat * KICK_PROP_REACH + Vector3.DOWN * 0.3)
	_kick_query.transform = Transform3D(Basis.IDENTITY, center)
	var space := get_world_3d().direct_space_state
	var kicked := false
	for contact: Dictionary in space.intersect_shape(_kick_query, 8):
		var prop := contact["collider"] as PinballProp
		if prop == null:
			continue
		_query.from = global_position
		_query.to = prop.global_position + Vector3.UP * 0.4
		var blocker := space.intersect_ray(_query)
		if not blocker.is_empty() and blocker["collider"] != prop:
			continue
		if prop.kick((flat + Vector3.UP * 0.35).normalized()):
			kicked = true
	return kicked

func _rank(id: StringName) -> int:
	return int(run_state.upgrade_levels.get(id, 0)) if run_state != null else 0

func _feedback(label: String) -> void:
	last_action_label = label
	action_feedback.emit(label)

func _close_finish(at: Vector3) -> bool:
	var offset := at - global_position
	return Vector2(offset.x, offset.z).length() <= FINISH_RANGE and absf(offset.y) <= 2.5

## One budgeted close-finish heal; death and full health take precedence.
func _recover_finish(amount: int) -> void:
	if not active or health >= max_health:
		return
	var granted := mini(amount, floori(_heal_budget))
	if granted <= 0:
		return
	_heal_budget -= granted
	heal(granted)

## Horde credits each intentionally defeated life (kick, reflected shot, combo,
## prop) exactly once per emission; primary damage never arrives here.
func _on_action_killed(members: int, at: Vector3, label: String) -> void:
	if not active or members <= 0:
		return
	_action_credits += 1
	_award(members, members * ACTION_STYLE + mini(32, (members - 1) * 4), label, _action_charge_allowed)
	if _close_finish(at):
		_recover_finish(FINISHER_HEAL if label == "FINISHER" else FINISH_HEAL)
	_feedback(label)

## Faster-than-eighth-note guns keep their ordinary damage, even during spin-up.
func rhythm_eligible() -> bool:
	var beat := Music.beat_seconds()
	if not active or weapon == null or beat <= 0.0:
		return false
	if not DROP_WEAPONS.has(_weapon_id):
		return false
	var rate := run_state.fire_rate_multiplier if run_state != null else 1.0
	return weapon.fire_interval / maxf(0.1, rate) >= beat * 0.5

func _perfect_beat() -> bool:
	var phase := Music.beat_phase()
	return phase >= 0.0 and minf(phase, 1.0 - phase) <= RHYTHM_PERFECT_WINDOW

func weapon_id() -> StringName:
	return _weapon_id

func drop_effect_label() -> String:
	match weapon_id():
		&"scatter": return "ODHOZ"
		&"rail": return "PRŮRAZ"
		&"autocannon": return "VELKÝ VÝBUCH"
		&"tvarohomet": return "MRAZIVÁ VLNA"
		&"maschine": return "ZKRAT"
		&"cihlomet": return "DEMOLICE"
	return "SÍLA"

func _shoot(manual_trigger: bool = true) -> void:
	var definition := weapon
	var view := _view
	var id := weapon_id()
	var quickdraw := _quickdraw_left > 0.0
	if quickdraw:
		_quickdraw_left = 0.0
	var combo_bonus := _combo_bonus()
	var perfect := _perfect_beat()
	var airborne := not is_on_floor()
	var sliding := is_sliding()
	last_drop_used = manual_trigger and drop_ready and rhythm_eligible() and perfect
	last_rhythm_bonus = RHYTHM_MAX_BONUS if last_drop_used else 0.0
	var previous_action_charge := _action_charge_allowed
	_action_charge_allowed = previous_action_charge and not last_drop_used
	if last_drop_used:
		drop_charge = 0.0
		drop_fired.emit(id)
	var shot_damage := definition.damage * (run_state.damage_multiplier if run_state != null else 1.0) \
			* (1.0 + combo_bonus) * (1.0 + last_rhythm_bonus) * (1.75 if quickdraw else 1.0)
	var pierce := definition.pierce + (run_state.pierce_bonus if run_state != null else 0)
	if last_drop_used and id == &"rail":
		pierce = Horde.CAPACITY - 1
	var blast_radius := definition.explosion_radius * (1.8 if last_drop_used else 1.0)
	var longshot: bool = run_state != null and int(run_state.upgrade_levels.get(&"mod_longshot", 0)) > 0
	var executioner: bool = run_state != null and int(run_state.upgrade_levels.get(&"mod_executioner", 0)) > 0
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
	var jitter := tan(deg_to_rad(definition.jitter_degrees))
	var space := get_world_3d().direct_space_state
	var directions := _directions
	var explosive := definition.explosion_radius > 0.0
	var blast_center := Vector3.INF
	var critical_at := Vector3.INF
	var rail := id == &"rail"
	var air_mail := false
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
			if precision:
				_hit_precision[_hit_lookup[slot]] = 1
			var hit_index := _hit_lookup[slot]
			# AIR MAIL: a rail slug through a launched body, in this same transaction.
			if rail and (_hit_flags[hit_index] & Horde.AIRBORNE) != 0:
				_hit_direct_damage[hit_index] += direct_damage * (AIR_MAIL_MULTIPLIER - 1.0)
				air_mail = true
			if _hit_direct[hit_index] == 0:
				_hit_push[hit_index] += forward * definition.knockback * (1.6 if quickdraw else 1.0) \
						* (4.0 if last_drop_used and (id == &"scatter" or id == &"cihlomet") else 1.0)
				_hit_direct[hit_index] = 1
		if last_drop_used and id == &"scatter" and pellet == 0:
			view.show_blast(origin + direction * minf(reach, 3.0), 2.0)
		# The trace ends at the last enemy it stopped in, else at the wall.
		var stopped := hits > pierce
		var end := origin + direction * (_distances[hits - 1] if stopped else reach)
		if not stopped and not wall.is_empty():
			var collider: Object = wall["collider"]
			# Shootable world objects (explosive barrels, switches) take the full shot.
			if collider != null and collider.has_method(&"take_hit"):
				collider.take_hit(shot_damage, wall["position"])
		view.show_ray(pellet, end, normal, stopped or not wall.is_empty(), stopped, ray_critical)
		if explosive:
			blast_center = end
			if horde != null:
				var splash_count := horde.query_radius(end, blast_radius, _splash_hits)
				for n in splash_count:
					var slot := _splash_hits[n]
					var away := horde.enemy_position(slot) - end
					away.y = 0.0
					var push := away.normalized() * definition.explosion_knockback * (2.5 if last_drop_used else 1.0) if away.length_squared() > 0.0001 else Vector3.ZERO
					_add_hit(slot, pellet_damage * definition.explosion_damage_fraction, critical, false)
					_hit_push[_hit_lookup[slot]] += push
			view.show_blast(end, blast_radius)
	# Direct pellets and splash aggregate before any deaths or feedback.
	var confirmed := _hit_count > 0
	for n in _hit_count:
		_hit_applied[n] = 0
		_hit_killed[n] = 0
		var slot := _hit_slots[n]
		if not horde.is_alive(slot) or horde.enemy_generation(slot) != _hit_generation[n]:
			continue
		_hit_position[n] = horde.enemy_position(slot)
		if last_drop_used:
			if definition.damage_type == DamageType.Kind.FROST:
				horde.slow(slot, 0.12, 5.0)
			elif definition.damage_type == DamageType.Kind.SHOCK:
				horde.stun(slot, 1.5)
			elif id == &"scatter" or id == &"cihlomet":
				horde.stun(slot, 0.6)
		_hit_applied[n] = 1
		var members := horde.fusion_members(slot)
		_hit_killed[n] = members if horde.damage_combined(slot, _hit_direct_damage[n], origin, _hit_damage[n], _hit_push[n], definition.damage_type, _hit_critical[n] != 0) else 0
	if horde != null and blast_center != Vector3.INF:
		horde.blast_react(blast_center, blast_radius, definition.explosion_knockback * (2.5 if last_drop_used else 1.0))
	if horde != null and last_drop_used and id == &"scatter":
		horde.blast_react(origin + forward * 3.0, 3.0, 26.0)
	var kills := _score_primary_kills(id, perfect, airborne, sliding, rail)
	if air_mail:
		_feedback("AIR MAIL")
	# Combos read flags captured before this shot's damage and run once per
	# target after primary capture; Horde credits their kills via action_killed.
	if horde != null:
		for n in _hit_count:
			if _hit_applied[n] == 0 or _hit_flags[n] == 0 or horde.enemy_generation(_hit_slots[n]) != _hit_generation[n]:
				continue
			horde.trigger_weapon_combo(_hit_slots[n], _hit_flags[n], id, origin, _hit_damage[n] + _hit_direct_damage[n])
	# Gear consumes only these captured primary transactions, never secondary kills.
	if gear_effects != null:
		gear_effects.process_primary_shot(_hit_count, _hit_slots, _hit_generation, _hit_position, _hit_direct_damage, _hit_killed, _hit_applied)
	if confirmed:
		var killed := kills > 0
		hit_confirmed.emit(killed)
		view.confirm_hit(killed, sound, combo_hits, critical_at != Vector3.INF)
		add_shake(0.095 if killed else 0.035)
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
	_action_charge_allowed = previous_action_charge


## Read captured kills before gear can kill/reuse another slot. No global death
## event, damage magnitude, random critical or secondary status kill earns charge.
func _score_primary_kills(id: StringName, perfect: bool, airborne: bool, sliding: bool, rail: bool) -> int:
	var kills := 0
	var precision_kills := 0
	var air_mail_kills := 0
	var close := false
	for n in _hit_count:
		if _hit_applied[n] == 0 or _hit_killed[n] == 0:
			continue
		kills += _hit_killed[n]
		if _hit_precision[n] != 0:
			precision_kills += _hit_killed[n]
		if rail and (_hit_flags[n] & Horde.AIRBORNE) != 0:
			air_mail_kills += _hit_killed[n]
		close = close or _close_finish(_hit_position[n])
	if kills == 0:
		return 0
	var style := kills * 8
	var label := "KILL"
	if precision_kills > 0:
		style += precision_kills * 6
		label = "PRECISION"
	if perfect:
		style += kills * 4
		label = "BEAT"
	if airborne:
		style += kills * 4
		label = "AIR"
	if sliding:
		style += kills * 5
		label = "SLIDE"
	if kills > 1:
		style += mini(32, (kills - 1) * 4)
		label = "MULTI"
	if air_mail_kills > 0:
		style += air_mail_kills * AIR_MAIL_STYLE
		label = "AIR MAIL"
	if _last_kill_weapon != &"" and _last_kill_weapon != id:
		style += 6
		label = "VARIETY"
	_last_kill_weapon = id
	# DROP may replenish from kills, but its one-shot windfall cannot self-bank.
	_award(kills, style, label, not last_drop_used)
	if close:
		_recover_finish(FINISH_HEAL)
	return kills

func _award(kills: int, style: int, label: String, charge: bool) -> void:
	if charge:
		drop_charge = minf(1.0, drop_charge + minf(0.32, float(style) / 100.0))
	combo_hits += style
	_combo_period = _combo_phase_period(true)
	_combo_left = _combo_period
	combo_changed.emit(combo_hits, _combo_bonus())
	var points := kills * 100 + style * 10
	arena_score += points
	arena_scored.emit(points, label)

## The low-chain grace stays generous; pressure saturates instead of reaching zero.
func _combo_phase_period(grace: bool) -> float:
	var pressure := clampf(float(combo_hits - COMBO_PRESSURE_START) / float(COMBO_PRESSURE_FULL - COMBO_PRESSURE_START), 0.0, 1.0)
	return lerpf(COMBO_WINDOW, COMBO_MIN_WINDOW, pressure) if grace else lerpf(COMBO_DECAY_INTERVAL, COMBO_MIN_DECAY_INTERVAL, pressure)

func _combo_bonus() -> float:
	return COMBO_MAX_BONUS * clampf(float(combo_hits) / float(COMBO_PRESSURE_FULL), 0.0, 1.0)

func _lose_combo(beats: int) -> void:
	if combo_hits == 0:
		return
	combo_hits = maxi(0, combo_hits - beats)
	if combo_hits == 0:
		_combo_left = 0.0
		_combo_period = COMBO_WINDOW
	combo_changed.emit(combo_hits, _combo_bonus())

func _reset_combo() -> void:
	_lose_combo(combo_hits)

func _add_hit(slot: int, amount: float, critical: bool, direct: bool) -> void:
	var index := _hit_lookup[slot]
	var generation := horde.enemy_generation(slot)
	if index < 0:
		index = _hit_count
		_hit_count += 1
		_hit_lookup[slot] = index
		_hit_generation[index] = -1
	if _hit_generation[index] != generation:
		_hit_slots[index] = slot
		_hit_generation[index] = generation
		_hit_position[index] = horde.enemy_position(slot)
		_hit_damage[index] = 0.0
		_hit_direct_damage[index] = 0.0
		_hit_critical[index] = 0
		_hit_precision[index] = 0
		_hit_push[index] = Vector3.ZERO
		_hit_direct[index] = 0
		_hit_flags[index] = horde.combo_flags(slot)
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
	if not active or amount <= 0 or is_invulnerable():
		return
	var armor := run_state.armor if run_state != null else 0.0
	var incoming := maxi(1, amount - int(armor))
	if gear_effects != null:
		incoming = gear_effects.absorb_damage(incoming)
	if incoming > 0:
		_lose_combo(2)
	health = maxi(0, health - incoming)
	if health == 0 and _survives_lethal_hit():
		health = 1
	health_changed.emit(health, max_health)
	sound.play_cue(&"hurt")
	if health == 0:
		_reset_combo()
		active = false
		cancel_actions()
		velocity = Vector3.ZERO
		_dash_time = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()

func _survives_lethal_hit() -> bool:
	for guard in _death_guards:
		if guard.is_valid() and guard.call():
			return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		cancel_actions()
