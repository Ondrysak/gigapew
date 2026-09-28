class_name ArenaPlayer
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal died
signal shot_fired
signal hit_confirmed(killed: bool)

const SPEED := 9.5
const JUMP_SPEED := 6.5
const GRAVITY := 21.0
const FIRE_INTERVAL := 0.16
const JUMP_GRACE := 0.12

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Node3D = $Head/Camera3D/Weapon
@onready var muzzle_flash: MeshInstance3D = $Head/Camera3D/Weapon/MuzzleFlash
@onready var muzzle_light: OmniLight3D = $Head/Camera3D/Weapon/MuzzleLight
@onready var sound: CombatAudio = $Sound
@onready var _weapon_rest: Vector3 = weapon.position

var active := true
var health := 100
var _fire_cooldown := 0.0
var _flash_time := 0.0
var _waiting_for_fire_release := false
var _coyote_time := 0.0
var _jump_buffer := 0.0
var _recoil := 0.0
var _landing_dip := 0.0
var _stride := 0.0
var _sway := Vector2.ZERO
var _trace_time := 0.0
var _impact_time := 0.0
var _tracer: MeshInstance3D
var _impact: MeshInstance3D
var _impact_material: StandardMaterial3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Reuse transient shot meshes instead of spawning a projectile for every shot.
	_tracer = MeshInstance3D.new()
	var trace_mesh := BoxMesh.new()
	trace_mesh.size = Vector3(0.014, 0.014, 1.0)
	_tracer.mesh = trace_mesh
	var trace_material := StandardMaterial3D.new()
	trace_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trace_material.albedo_color = Color(0.4, 1.0, 0.95)
	_tracer.material_override = trace_material
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracer)
	_tracer.top_level = true
	_tracer.hide()
	_impact = MeshInstance3D.new()
	var impact_mesh := SphereMesh.new()
	impact_mesh.radius = 1.0
	impact_mesh.height = 2.0
	impact_mesh.radial_segments = 8
	impact_mesh.rings = 4
	_impact.mesh = impact_mesh
	_impact_material = StandardMaterial3D.new()
	_impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact.material_override = _impact_material
	_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_impact)
	_impact.top_level = true
	_impact.hide()

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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0025)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * 0.0025, deg_to_rad(-85.0), deg_to_rad(85.0))
		_sway += event.relative * 0.00012
		_sway = _sway.clamp(Vector2(-0.025, -0.02), Vector2(0.025, 0.02))

func _process(delta: float) -> void:
	var blend := 1.0 - exp(-18.0 * delta)
	_recoil = lerpf(_recoil, 0.0, blend)
	_landing_dip = lerpf(_landing_dip, 0.0, 1.0 - exp(-12.0 * delta))
	_sway = _sway.lerp(Vector2.ZERO, blend)
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPEED, 0.0, 1.0)
	if active and is_on_floor():
		_stride += delta * 12.0 * speed_ratio
	var bob := Vector3(sin(_stride) * 0.012, absf(cos(_stride)) * 0.009, 0.0) * speed_ratio
	weapon.position = _weapon_rest + bob + Vector3(-_sway.x, _sway.y - _landing_dip, _recoil * 0.11)
	weapon.rotation.x = _recoil * 0.09
	weapon.rotation.z = -velocity.dot(global_basis.x) * 0.002
	camera.fov = lerpf(camera.fov, 90.0 + speed_ratio * 2.5, 1.0 - exp(-5.0 * delta))
	_flash_time = maxf(0.0, _flash_time - delta)
	muzzle_flash.visible = _flash_time > 0.0 and active
	muzzle_light.visible = muzzle_flash.visible
	_trace_time = maxf(0.0, _trace_time - delta)
	_tracer.visible = _trace_time > 0.0
	_impact_time = maxf(0.0, _impact_time - delta)
	_impact.visible = _impact_time > 0.0
	_impact.scale = Vector3.ONE * maxf(0.001, _impact_time * 0.9)

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return
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
	var acceleration := 65.0 if grounded else 26.0
	if movement.is_zero_approx() and grounded:
		acceleration = 85.0
	velocity.x = move_toward(velocity.x, direction.x * SPEED, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * SPEED, acceleration * delta)
	var falling_speed := velocity.y
	move_and_slide()
	if not grounded and is_on_floor() and falling_speed < -3.0:
		_landing_dip = minf(-falling_speed * 0.006, 0.055)
		sound.play_cue(&"land")

	_fire_cooldown = maxf(-delta, _fire_cooldown - delta)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _waiting_for_fire_release \
			and Input.is_action_pressed("fire") and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown += FIRE_INTERVAL

func _shoot() -> void:
	var end := camera.global_position - camera.global_basis.z * 40.0
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, end, 0xFFFFFFFF, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	sound.play_cue(&"shot")
	shot_fired.emit()
	if not hit.is_empty():
		end = hit["position"]
		var enemy := hit["collider"] as ArenaEnemy
		if enemy != null and enemy.health > 0:
			enemy.apply_knockback(-camera.global_basis.z)
			enemy.take_damage(25)
			var killed := enemy.health == 0
			hit_confirmed.emit(killed)
			sound.play_cue(&"kill" if killed else &"hit")
		_impact.global_position = end + hit["normal"] * 0.035
		_impact_material.albedo_color = Color(1.0, 0.3, 0.55) if enemy != null else Color(1.0, 0.8, 0.4)
		_impact_time = 0.13
	var start := muzzle_flash.global_position
	if start.distance_squared_to(end) > 0.01:
		_tracer.global_position = (start + end) * 0.5
		_tracer.global_basis = Basis.looking_at(end - start)
		_tracer.scale = Vector3(1.0, 1.0, start.distance_to(end))
		_trace_time = 0.045
	_flash_time = 0.045
	_recoil = 1.0

func take_damage(amount: int) -> void:
	if not active or amount <= 0:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, 100)
	sound.play_cue(&"hurt")
	if health == 0:
		active = false
		velocity = Vector3.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
