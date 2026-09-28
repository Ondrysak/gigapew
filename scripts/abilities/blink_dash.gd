class_name BlinkDash
extends ActiveAbility

## Dashes along the movement input (or the view when standing still), briefly
## invulnerable, shoving and damaging every enemy on the path once.

@export var dash_distance := 9.0
@export var dash_duration := 0.16
@export var invulnerability := 0.35
@export var hit_radius := 1.7
@export var damage := 30.0
@export var knockback := 18.0
@export var fov_punch := 18.0
## Hidden streak (a thin line along -Z, length 1) pooled along the dash path.
@export var streak_template: Node3D
@export var streak_count := 18
@export var streak_lifetime := 0.4
## Hidden ground ring authored at radius 1, flashed at both dash ends.
@export var ring_template: Node3D
@export var ring_lifetime := 0.45
@export var ring_radius := 1.6

var _dashing := 0.0
var _direction := Vector3.FORWARD
var _query_buffer := PackedInt32Array()
var _struck := PackedInt32Array()
var _struck_count := 0
var _streaks: Array[Node3D] = []
var _streak_age := PackedFloat32Array()
var _streak_length := PackedFloat32Array()
var _rings: Array[Node3D] = []
var _ring_age := PackedFloat32Array()
var _next_ring := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	super()
	_rng.randomize()
	_query_buffer.resize(256)
	_struck.resize(64)
	_streaks = make_pool(streak_template, streak_count)
	_streak_age.resize(_streaks.size())
	_streak_age.fill(-1.0)
	_streak_length.resize(_streaks.size())
	_rings = make_pool(ring_template, 2)
	_ring_age.resize(_rings.size())
	_ring_age.fill(-1.0)

func _activate() -> bool:
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := player.global_basis * Vector3(movement.x, 0.0, movement.y)
	if direction.length_squared() < 0.01:
		direction = -player.camera.global_basis.z
		direction.y = 0.0
		if direction.length_squared() < 0.01:
			direction = -player.global_basis.z
	_direction = direction.normalized()
	var start := player.global_position
	player.dash(_direction * (dash_distance / dash_duration), dash_duration)
	player.grant_invulnerability(invulnerability)
	player.camera.fov += fov_punch
	player.add_shake(0.22)
	_dashing = dash_duration
	_struck_count = 0
	_flash_ring(start)
	_scatter_streaks(start)
	return true

func _ability_physics(delta: float) -> void:
	if _dashing <= 0.0:
		return
	_dashing -= delta
	_strike_around(player.global_position)
	if _dashing <= 0.0:
		_flash_ring(player.global_position)

func _strike_around(center: Vector3) -> void:
	if horde == null:
		return
	var count := horde.query_radius(center, hit_radius, _query_buffer)
	var amount := damage * damage_scale()
	for n in count:
		var index := _query_buffer[n]
		if _was_struck(index):
			continue
		if _struck_count >= _struck.size():
			_struck.resize(_struck_count * 2)
		_struck[_struck_count] = index
		_struck_count += 1
		# Shove sideways out of the lane, with a little forward carry.
		var away := horde.enemy_position(index) - center
		away.y = 0.0
		var side := away - _direction * away.dot(_direction)
		if side.length_squared() < 0.0001:
			side = _direction.cross(Vector3.UP)
		var push := side.normalized() * knockback + _direction * knockback * 0.35
		horde.damage(index, amount, push)

func _was_struck(index: int) -> bool:
	for n in _struck_count:
		if _struck[n] == index:
			return true
	return false

func _flash_ring(at: Vector3) -> void:
	if _rings.is_empty():
		return
	var ring := _rings[_next_ring]
	_ring_age[_next_ring] = 0.0
	_next_ring = (_next_ring + 1) % _rings.size()
	ring.global_position = Vector3(at.x, at.y - 0.85, at.z)
	ring.scale = Vector3.ONE * 0.2
	ring.show()

func _scatter_streaks(start: Vector3) -> void:
	# Streaks line the path ahead so the dash rushes through them.
	var side := _direction.cross(Vector3.UP).normalized()
	for index in range(_streaks.size()):
		var streak := _streaks[index]
		var along := _rng.randf_range(0.5, dash_distance + 3.0)
		var angle := _rng.randf() * TAU
		var offset := side * cos(angle) * _rng.randf_range(0.9, 1.8) + Vector3.UP * sin(angle) * _rng.randf_range(0.6, 1.2)
		var at := start + _direction * along + offset
		streak.global_position = at
		streak.global_basis = Basis.looking_at(_direction)
		_streak_length[index] = _rng.randf_range(1.2, 2.6)
		streak.scale = Vector3(1.0, 1.0, _streak_length[index])
		_streak_age[index] = _rng.randf_range(-0.04, 0.0)
		streak.hide()

func _process(delta: float) -> void:
	for index in range(_streaks.size()):
		var age := _streak_age[index]
		if age == -1.0:
			continue
		age += delta
		var streak := _streaks[index]
		if age >= streak_lifetime:
			_streak_age[index] = -1.0
			streak.hide()
			continue
		_streak_age[index] = age
		if age < 0.0:
			continue
		var fade := 1.0 - age / streak_lifetime
		streak.scale = Vector3(fade, fade, _streak_length[index] * (0.4 + fade * 0.6))
		streak.show()
	for index in range(_rings.size()):
		var age := _ring_age[index]
		if age < 0.0:
			continue
		age += delta
		var ring := _rings[index]
		if age >= ring_lifetime:
			_ring_age[index] = -1.0
			ring.hide()
			continue
		_ring_age[index] = age
		var t := age / ring_lifetime
		var radius := ring_radius * (1.0 - (1.0 - t) * (1.0 - t))
		ring.scale = Vector3(radius, maxf(0.05, 1.0 - t), radius)
