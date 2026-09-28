class_name ArenaEnemy
extends CharacterBody3D

signal died

const ARMOR_COLOR := Color(0.68, 0.035, 0.28, 1.0)
const ARMOR_EMISSION := Color(0.36, 0.008, 0.07, 1.0)
const FLASH_COLOR := Color(1.0, 0.87, 0.73, 1.0)
const HIT_FLASH_DURATION := 0.14

var target: ArenaPlayer
var health: int = 50
var _dying := false
var _contact_cooldown := 0.0
var _knockback := Vector3.ZERO
var _flash_time := 0.0
var _visual_phase := 0.0
var _pursuing := false

@onready var _visual: Node3D = $Visual
@onready var _armor: StandardMaterial3D = $Visual/Torso.material_override
@onready var _left_shoulder: Node3D = $Visual/LeftShoulder
@onready var _right_shoulder: Node3D = $Visual/RightShoulder
@onready var _head: Node3D = $Visual/Head
@onready var _exhaust: MeshInstance3D = $Visual/Exhaust

func _ready() -> void:
	_visual_phase = position.x * 0.37 + position.z * 0.73

func _process(delta: float) -> void:
	if _dying:
		return

	_visual_phase += delta * 5.0
	_visual.position.y = sin(_visual_phase) * 0.055
	_visual.rotation.x = lerpf(_visual.rotation.x, -0.12 if _pursuing else 0.0, 1.0 - exp(-10.0 * delta))
	_left_shoulder.rotation.x = sin(_visual_phase) * 0.12
	_right_shoulder.rotation.x = -sin(_visual_phase) * 0.12
	_exhaust.scale.y = 1.0 + sin(_visual_phase * 2.7) * 0.2

	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		var strength := _flash_time / HIT_FLASH_DURATION
		_set_flash(strength)
		_visual.scale = Vector3(1.0 + strength * 0.1, 1.0 - strength * 0.08, 1.0 + strength * 0.1)

func _physics_process(delta: float) -> void:
	if _dying:
		return

	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0

	_pursuing = is_instance_valid(target) and target.active
	if _pursuing:
		var difference := target.global_position - global_position
		var horizontal := Vector3(difference.x, 0.0, difference.z)
		if horizontal.length_squared() > 0.0001:
			horizontal = horizontal.normalized()
			_visual.rotation.y = rotate_toward(_visual.rotation.y, atan2(-horizontal.x, -horizontal.z), delta * 10.0)
		velocity.x = horizontal.x * 3.6 + _knockback.x
		velocity.z = horizontal.z * 3.6 + _knockback.z
		_knockback = _knockback.move_toward(Vector3.ZERO, delta * 16.0)
		move_and_slide()
		var separation := target.global_position - global_position
		if Vector2(separation.x, separation.z).length_squared() <= 1.5625 \
				and absf(separation.y) <= 1.2 and _contact_cooldown <= 0.0:
			target.take_damage(10)
			_contact_cooldown = 0.75
	else:
		_knockback = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()

func apply_knockback(direction: Vector3) -> void:
	if _dying:
		return
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() > 0.0001:
		_knockback = horizontal.normalized() * 6.5

func take_damage(amount: int) -> void:
	if _dying or amount <= 0:
		return
	health = maxi(0, health - amount)
	_flash_time = HIT_FLASH_DURATION
	_set_flash(1.0)
	if health == 0:
		_die()

func _set_flash(strength: float) -> void:
	# The armor resource is local to each scene instance, never shared by enemies.
	_armor.albedo_color = ARMOR_COLOR.lerp(FLASH_COLOR, strength)
	_armor.emission = ARMOR_EMISSION.lerp(FLASH_COLOR, strength)
	_armor.emission_energy_multiplier = lerpf(0.25, 1.8, strength)

func _die() -> void:
	_dying = true
	set_physics_process(false)
	velocity = Vector3.ZERO
	# Layer removal makes a second ray ignore this body even before the deferred shape update.
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.set_deferred("disabled", true)
	died.emit()

	var death := create_tween().set_parallel(true)
	death.tween_property(_visual, "scale", Vector3(1.3, 0.35, 1.3), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	death.tween_property(_left_shoulder, "position", Vector3(-0.95, -0.15, 0.2), 0.3)
	death.tween_property(_right_shoulder, "position", Vector3(0.95, -0.15, -0.2), 0.3)
	death.tween_property(_left_shoulder, "rotation:z", 1.8, 0.3)
	death.tween_property(_right_shoulder, "rotation:z", -1.8, 0.3)
	death.tween_property(_head, "position:y", 1.3, 0.3)
	death.tween_property(_visual, "position:y", -0.5, 0.3)
	death.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.18).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	death.chain().tween_callback(queue_free)
