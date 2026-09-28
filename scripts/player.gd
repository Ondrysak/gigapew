class_name ArenaPlayer
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died
signal shot_fired
signal hit_confirmed(killed: bool)
signal weapon_changed(definition: WeaponDefinition, index: int)

const SPEED := 9.5
const JUMP_SPEED := 6.5
const GRAVITY := 21.0
const JUMP_GRACE := 0.12

@export var weapons: Array[WeaponDefinition] = []
@export var base_max_health := 100
var selected_weapon := 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var sound: CombatAudio = $Sound

## Assigned by the stage before the player enters the tree.
var run_state: RunState
var horde: Horde
var active := true
var max_health := 100
var health := 100
var _fire_cooldown := 0.0
var _waiting_for_fire_release := false
var _coyote_time := 0.0
var _jump_buffer := 0.0
var _regen := 0.0
var _views: Array[WeaponView] = []
var _directions: Array[PackedVector3Array] = []
var _view: WeaponView
var _query: PhysicsRayQueryParameters3D
var _shot_damage: Dictionary = {}
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh_stats()
	health = max_health
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [get_rid()])
	for definition in weapons:
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
	select_weapon(selected_weapon)

func select_weapon(index: int) -> void:
	if not active or index < 0 or index >= _views.size():
		return
	if _view == _views[index]:
		return
	if _view != null:
		_view.hide()
	selected_weapon = index
	_view = _views[index]
	_view.show()
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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
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
	elif event.is_action_pressed("weapon_next") and not weapons.is_empty():
		select_weapon((selected_weapon + 1) % weapons.size())
	elif event.is_action_pressed("weapon_previous") and not weapons.is_empty():
		select_weapon(posmod(selected_weapon - 1, weapons.size()))
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0025)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * 0.0025, deg_to_rad(-85.0), deg_to_rad(85.0))
		if _view != null:
			_view.aim(event.relative)

func _process(delta: float) -> void:
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPEED, 0.0, 1.0)
	if _view != null:
		_view.animate_motion(delta, speed_ratio, velocity.dot(global_basis.x), is_on_floor(), active)
	camera.fov = lerpf(camera.fov, 90.0 + speed_ratio * 2.5, 1.0 - exp(-5.0 * delta))

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return
	if run_state != null and run_state.regen_per_second > 0.0 and health < max_health:
		_regen += run_state.regen_per_second * delta
		if _regen >= 1.0:
			heal(int(_regen))
			_regen -= floorf(_regen)
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

	_fire_cooldown = maxf(-delta, _fire_cooldown - delta)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _waiting_for_fire_release \
			and Input.is_action_pressed("fire") and _fire_cooldown <= 0.0 and _view != null:
		var rate := run_state.fire_rate_multiplier if run_state != null else 1.0
		_fire_cooldown += weapons[selected_weapon].fire_interval / maxf(0.1, rate)
		_shoot()

func _shoot() -> void:
	var definition := weapons[selected_weapon]
	var damage_scale := run_state.damage_multiplier if run_state != null else 1.0
	var pierce := definition.pierce + (run_state.pierce_bonus if run_state != null else 0)
	_view.begin_shot(sound)
	shot_fired.emit()
	_shot_damage.clear()
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	_query.from = origin
	for pellet in range(definition.pellet_count):
		var direction := camera.global_basis * _directions[selected_weapon][pellet]
		# World geometry (walls, obstacles) limits every ray; enemies are not physics bodies.
		var reach := definition.range_meters
		_query.to = origin + direction * reach
		var wall := get_world_3d().direct_space_state.intersect_ray(_query)
		var normal := Vector3.ZERO
		if not wall.is_empty():
			reach = origin.distance_to(wall["position"])
			normal = wall["normal"]
		var hits := 0
		if horde != null:
			hits = horde.raycast(origin, direction, reach, pierce + 1, _hits, _distances)
		for n in hits:
			_shot_damage[_hits[n]] = float(_shot_damage.get(_hits[n], 0.0)) + definition.damage * damage_scale
		# The trace ends at the last enemy it stopped in, else at the wall.
		var stopped := hits > pierce
		var end := origin + direction * (_distances[hits - 1] if stopped else reach)
		_view.show_ray(pellet, end, normal, stopped or not wall.is_empty(), hits > 0)
	# Each enemy takes one combined hit per shot so pellets never double-kill.
	var confirmed := false
	var killed := false
	for index: int in _shot_damage:
		confirmed = true
		if horde.damage(index, _shot_damage[index], forward * definition.knockback):
			killed = true
	if confirmed:
		hit_confirmed.emit(killed)
		_view.confirm_hit(killed, sound)

func take_damage(amount: int) -> void:
	if not active or amount <= 0:
		return
	var armor := run_state.armor if run_state != null else 0.0
	health = maxi(0, health - maxi(1, amount - int(armor)))
	health_changed.emit(health, max_health)
	sound.play_cue(&"hurt")
	if health == 0:
		active = false
		velocity = Vector3.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
