class_name RocketWeapon
extends AutoWeapon

## Fires salvos of homing rockets from the player's shoulders. Rockets pop up,
## then steer toward their targets and explode on contact. Overclocked rockets
## split into smaller homing rockets when they explode.

## Hidden rocket body facing -Z.
@export var rocket_template: Node3D
## Hidden unit-length beam along -Z used as the exhaust trail.
@export var trail_template: Node3D
## Hidden blast flash authored with radius 1.
@export var blast_template: Node3D
## Hidden floor ring (radius 1) that expands to the blast radius.
@export var shock_template: Node3D
@export var target_range := 26.0
@export var base_rockets := 2
## Each listed weapon level adds one rocket per salvo.
@export var extra_rocket_levels := PackedInt32Array([3, 5])
@export var max_rockets := 12
## Delay between rockets in one salvo.
@export var launch_interval := 0.08
@export var launch_height := 1.6
@export var launch_speed := 7.0
@export var cruise_speed := 22.0
@export var acceleration := 30.0
## Seconds of unguided pop-up flight before homing starts.
@export var boost_time := 0.22
## How quickly rockets turn toward their target (per second).
@export var turn_rate := 6.0
@export var max_life := 3.0
@export var hit_distance := 0.9
@export var base_blast_radius := 2.5
## Fractional blast radius gain per level above 1.
@export var blast_radius_per_level := 0.06
@export var knockback := 6.0
@export var blast_duration := 0.26
## Exhaust trail length responsiveness; higher gives shorter trails.
@export var trail_follow := 9.0
@export var trail_width := 1.0

@export_group("Overclock")
@export var split_count := 2
@export var split_damage_scale := 0.5
@export var split_radius_scale := 0.6
@export var split_retarget_range := 10.0
@export var split_scale := 0.65

var _rockets: Array[Node3D] = []
var _trails: Array[Node3D] = []
var _blasts: AutoFxPool
var _shocks: AutoFxPool
## 0 = free, 1 = rocket, 2 = split rocket.
var _kind := PackedByteArray()
## 1 while the position is still relative to the player (waiting to launch).
var _pending := PackedByteArray()
## Seconds since launch; negative while waiting in the salvo.
var _age := PackedFloat32Array()
var _target := PackedInt32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _tail := PackedVector3Array()
var _hits := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _salvo := 2
var _timer := 0.0

func _ready() -> void:
	_hits.resize(512)

func _refresh() -> void:
	_salvo = scaled_count(base_rockets, extra_rocket_levels, max_rockets)
	var slots := _salvo * 2 * (1 + (split_count if overclocked else 0))
	_grow_pool(rocket_template, _rockets, slots)
	_grow_pool(trail_template, _trails, slots)
	if _blasts == null:
		_blasts = AutoFxPool.new(self, blast_template, AutoFxPool.Style.BLAST)
		_shocks = AutoFxPool.new(self, shock_template, AutoFxPool.Style.RING)
	_blasts.reserve(slots)
	_shocks.reserve(slots)
	var size := _rockets.size()
	_kind.resize(size)
	_pending.resize(size)
	_age.resize(size)
	_target.resize(size)
	_pos.resize(size)
	_vel.resize(size)
	_tail.resize(size)
	if _timer <= 0.0:
		_timer = cooldown_time() * 0.5

func blast_radius() -> float:
	return base_blast_radius * (1.0 + blast_radius_per_level * (level - 1)) * area_scale()

func _tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		if _fire_salvo():
			_timer += cooldown_time()
		else:
			_timer = 0.25
	for index in range(_rockets.size()):
		if _kind[index] == 0:
			continue
		var age := _age[index] + delta
		_age[index] = age
		if age < 0.0:
			continue
		if _pending[index] != 0:
			# Leaves the launcher now: start from the player's current shoulder.
			_pending[index] = 0
			_pos[index] += player.global_position
			_tail[index] = _pos[index]
		_fly(index, age, delta)

func _fly(index: int, age: float, delta: float) -> void:
	var position_now := _pos[index]
	var velocity := _vel[index]
	var target := _target[index]
	if not horde.is_alive(target):
		target = horde.nearest(position_now, target_range)
		_target[index] = target
	var speed := minf(velocity.length() + acceleration * delta, cruise_speed)
	var heading := velocity.normalized() if velocity.length_squared() > 0.0001 else Vector3.UP
	var aim := position_now
	if target >= 0:
		aim = horde.enemy_position(target)
		if age > boost_time:
			var wanted := (aim - position_now).normalized()
			if wanted.length_squared() > 0.5:
				# Steering tightens with age so late rockets cannot orbit a target.
				var turned := heading.slerp(wanted, minf(1.0, turn_rate * (1.0 + age * 2.0) * delta))
				if turned.length_squared() > 0.0001:
					heading = turned.normalized()
	velocity = heading * speed
	position_now += velocity * delta
	_pos[index] = position_now
	_vel[index] = velocity
	var close := target >= 0 and position_now.distance_squared_to(aim) < hit_distance * hit_distance
	if close or position_now.y <= 0.05 or age >= max_life:
		_explode(index)
		return
	var rocket := _rockets[index]
	var up := Vector3.RIGHT if absf(heading.y) > 0.99 else Vector3.UP
	var body_scale := split_scale if _kind[index] == 2 else 1.0
	rocket.global_transform = Transform3D(Basis.looking_at(heading, up).scaled(Vector3.ONE * body_scale), position_now)
	rocket.show()
	_tail[index] = _tail[index].lerp(position_now, 1.0 - exp(-trail_follow * delta))
	place_beam(_trails[index], _tail[index], position_now, trail_width * body_scale)

func _fire_salvo() -> bool:
	var found := horde.query_radius(player.global_position, target_range, _hits)
	if found <= 0:
		return false
	var right := player.global_basis.x
	var queued := 0
	for index in range(_rockets.size()):
		if queued >= _salvo:
			break
		if _kind[index] != 0:
			continue
		# Alternate shoulders and fan the pop-up outward.
		var side := 1.0 if queued % 2 == 0 else -1.0
		var launch := Vector3.UP * launch_height + right * side * 0.45
		var spread := right * side * _rng.randf_range(0.3, 0.8) + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
		_start(index, 1, launch, (Vector3.UP + spread).normalized() * launch_speed, _hits[_rng.randi_range(0, found - 1)], -launch_interval * queued)
		_pending[index] = 1
		queued += 1
	return queued > 0

func _start(index: int, kind: int, at: Vector3, velocity: Vector3, target: int, delay: float) -> void:
	_kind[index] = kind
	_pending[index] = 0
	_pos[index] = at
	_tail[index] = at
	_vel[index] = velocity
	_target[index] = target
	_age[index] = delay

func _explode(index: int) -> void:
	var split := _kind[index] == 2
	var at := _pos[index]
	_kind[index] = 0
	_rockets[index].hide()
	_trails[index].hide()
	var radius := blast_radius() * (split_radius_scale if split else 1.0)
	horde.damage_radius(at, radius, damage_amount() * (split_damage_scale if split else 1.0), knockback)
	_shocks.spawn(Vector3(at.x, 0.05, at.z), radius, 0.3)
	if not crowds_view(at, radius):
		_blasts.spawn(at, radius, blast_duration * (0.7 if split else 1.0))
	if split:
		return
	play_cue()
	if overclocked:
		_split(at)

func _split(at: Vector3) -> void:
	var found := horde.query_radius(at, split_retarget_range, _hits)
	var left := split_count
	for index in range(_rockets.size()):
		if left <= 0:
			return
		if _kind[index] != 0:
			continue
		var angle := _rng.randf() * TAU
		var velocity := Vector3(cos(angle), 1.2, sin(angle)).normalized() * launch_speed
		var target := _hits[_rng.randi_range(0, found - 1)] if found > 0 else -1
		_start(index, 2, at + Vector3.UP * 0.3, velocity, target, 0.0)
		left -= 1
