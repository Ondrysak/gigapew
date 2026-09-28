class_name ArenaPlayer
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died
signal shot_fired
signal hit_confirmed(killed: bool)
signal weapon_changed(definition: WeaponDefinition, index: int)
## Emitted after the class ability activates successfully.
signal ability_used(ability: ActiveAbility)

const SPEED := 9.5
const JUMP_SPEED := 6.5
const GRAVITY := 21.0
const JUMP_GRACE := 0.12
const MOUSE_SENSITIVITY := 0.0025
## Share of shot damage dealt to mineable colliders (before mining_multiplier).
const MINING_SHARE := 0.35

## Main guns in slot order (1 to 3 entries; keys 1/2/3 and the wheel cycle them).
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
var _fire_cooldown := 0.0
var _waiting_for_fire_release := false
var _coyote_time := 0.0
var _jump_buffer := 0.0
var _regen := 0.0
var _invulnerable := 0.0
var _dash_velocity := Vector3.ZERO
var _dash_time := 0.0
## Spin-up progress 0..1 of the selected gun.
var _spin := 0.0
var _trauma := 0.0
var _shake_clock := 0.0
var _profile: Node
var _rng := RandomNumberGenerator.new()
var _views: Array[WeaponView] = []
var _directions: Array[PackedVector3Array] = []
var _view: WeaponView
var _query: PhysicsRayQueryParameters3D
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
# Per-shot combined damage per enemy slot; reused, never reallocated per shot.
var _hit_slots := PackedInt32Array()
var _hit_damage := PackedFloat32Array()
var _hit_count := 0
var _blast_points := PackedVector3Array()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_profile = get_node_or_null(^"/root/Profile")
	_rng.randomize()
	refresh_stats()
	health = max_health
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [get_rid()])
	_hit_slots.resize(64)
	_hit_damage.resize(64)
	var max_pellets := 1
	for definition in weapons:
		max_pellets = maxi(max_pellets, definition.pellet_count)
		var view := definition.view_scene.instantiate() as WeaponView
		camera.add_child(view)
		view.prepare(definition.pellet_count)
		view.hide()
		_views.append(view)
		var directions := PackedVector3Array()
		directions.append(Vector3.FORWARD)
		# A center pellet and an even cone ring make every burst reproducible.
		var radius := tan(deg_to_rad(definition.spread_degrees))
		for pellet in range(1, definition.pellet_count):
			var angle := TAU * float(pellet - 1) / float(definition.pellet_count - 1)
			directions.append(Vector3(cos(angle) * radius, sin(angle) * radius, -1.0).normalized())
		_directions.append(directions)
	_blast_points.resize(max_pellets)
	select_weapon(selected_weapon)
	if ability_scene != null:
		var node := ability_scene.instantiate()
		ability = node as ActiveAbility
		if ability == null:
			push_error("ability_scene root must be an ActiveAbility")
			node.free()
		else:
			add_child(ability)
			ability.setup(self, horde, run_state)

func select_weapon(index: int) -> void:
	if not active or index < 0 or index >= _views.size():
		return
	if _view == _views[index]:
		return
	if _view != null:
		_view.set_spin(0.0)
		_view.hide()
	selected_weapon = index
	_view = _views[index]
	_view.show()
	_spin = 0.0
	# The outstanding shot cooldown belongs to the player, not the view.
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
	if _view != null:
		_view.animate_motion(delta, speed_ratio, velocity.dot(global_basis.x), is_on_floor(), active)
		_view.set_spin(_spin if active else 0.0)
	camera.fov = lerpf(camera.fov, 90.0 + speed_ratio * 2.5, 1.0 - exp(-5.0 * delta))
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	_shake_clock += delta
	var shake := _trauma * _trauma * 0.12
	camera.h_offset = sin(_shake_clock * 71.0) * shake
	camera.v_offset = sin(_shake_clock * 53.0 + 1.3) * shake

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return
	_invulnerable = maxf(0.0, _invulnerable - delta)
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

	if _view == null:
		return
	var definition := weapons[selected_weapon]
	var trigger := captured and not _waiting_for_fire_release and Input.is_action_pressed("fire")
	if definition.spin_up_time > 0.0:
		if trigger:
			_spin = minf(1.0, _spin + delta / definition.spin_up_time)
		else:
			_spin = maxf(0.0, _spin - delta / maxf(0.01, definition.spin_down_time))
	_fire_cooldown = maxf(-delta, _fire_cooldown - delta)
	if trigger and _fire_cooldown <= 0.0:
		var interval := definition.fire_interval
		if definition.spin_up_time > 0.0:
			var eased := 1.0 - (1.0 - _spin) * (1.0 - _spin)
			interval *= lerpf(definition.spin_up_start_multiplier, 1.0, eased)
		var rate := run_state.fire_rate_multiplier if run_state != null else 1.0
		_fire_cooldown += interval / maxf(0.1, rate)
		_shoot()

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
		if _view != null:
			_view.land(falling_speed)
		sound.play_cue(&"land")

func _shoot() -> void:
	var definition := weapons[selected_weapon]
	var shot_damage := definition.damage * (run_state.damage_multiplier if run_state != null else 1.0)
	var pierce := definition.pierce + (run_state.pierce_bonus if run_state != null else 0)
	var mining := shot_damage * MINING_SHARE * (run_state.mining_multiplier if run_state != null else 1.0)
	_view.begin_shot(sound)
	shot_fired.emit()
	if definition.screen_shake > 0.0:
		add_shake(definition.screen_shake)
	_hit_count = 0
	var origin := camera.global_position
	var aim := camera.global_basis
	var forward := -aim.z
	var roll := Basis.IDENTITY
	if definition.pellet_count > 1 and definition.jitter_degrees > 0.0:
		roll = Basis(Vector3.FORWARD, _rng.randf() * TAU)
	var jitter := tan(deg_to_rad(definition.jitter_degrees))
	var space := get_world_3d().direct_space_state
	var directions := _directions[selected_weapon]
	var explosive := definition.explosion_radius > 0.0
	var alive_before := horde.alive_count if horde != null else 0
	_query.from = origin
	for pellet in range(definition.pellet_count):
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
		for n in hits:
			_add_hit(_hits[n], shot_damage)
		# The trace ends at the last enemy it stopped in, else at the wall.
		var stopped := hits > pierce
		var end := origin + direction * (_distances[hits - 1] if stopped else reach)
		if not stopped and not wall.is_empty():
			var collider: Object = wall["collider"]
			if collider != null and collider.has_method(&"take_mining_damage"):
				collider.take_mining_damage(mining)
		_view.show_ray(pellet, end, normal, stopped or not wall.is_empty(), hits > 0)
		if explosive:
			_blast_points[pellet] = end
	# Each enemy takes one combined hit per shot so pellets never double-kill.
	var confirmed := _hit_count > 0
	for n in _hit_count:
		horde.damage(_hit_slots[n], _hit_damage[n], forward * definition.knockback)
	if explosive:
		for pellet in range(definition.pellet_count):
			var at := _blast_points[pellet]
			if horde != null and horde.damage_radius(at, definition.explosion_radius, \
					shot_damage * definition.explosion_damage_fraction, definition.explosion_knockback) > 0:
				confirmed = true
			_view.show_blast(at, definition.explosion_radius)
	if confirmed:
		var killed := horde.alive_count < alive_before
		hit_confirmed.emit(killed)
		_view.confirm_hit(killed, sound)

func _add_hit(slot: int, amount: float) -> void:
	for n in _hit_count:
		if _hit_slots[n] == slot:
			_hit_damage[n] += amount
			return
	if _hit_count >= _hit_slots.size():
		_hit_slots.resize(_hit_count * 2)
		_hit_damage.resize(_hit_count * 2)
	_hit_slots[_hit_count] = slot
	_hit_damage[_hit_count] = amount
	_hit_count += 1

func take_damage(amount: int) -> void:
	if not active or amount <= 0 or _invulnerable > 0.0:
		return
	var armor := run_state.armor if run_state != null else 0.0
	health = maxi(0, health - maxi(1, amount - int(armor)))
	health_changed.emit(health, max_health)
	sound.play_cue(&"hurt")
	if health == 0:
		active = false
		velocity = Vector3.ZERO
		_dash_time = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
