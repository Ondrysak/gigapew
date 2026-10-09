class_name DrillDash
extends ActiveAbility

## Burrows forward along the view with a spinning drill, untouchable, grinding
## every enemy on the path once and erupting where it surfaces.

@export var dash_distance := 14.0
@export var dash_duration := 0.55
## Extra invulnerability after the dash ends.
@export var invulnerability_tail := 0.2
@export var hit_radius := 2.0
@export var damage := 80.0
@export var knockback := 16.0
@export var eruption_radius := 4.0
@export var eruption_damage := 50.0
@export var eruption_knockback := 22.0
@export var fov_punch := 10.0
## Drill visuals parented under this ability (follows the player), shown only
## while burrowing.
@export var drill: Node3D
## Child of the drill spun around its local Z axis.
@export var drill_bit: Node3D
@export var spin_speed := 38.0
## Hidden debris chunk pooled and flung along the path.
@export var debris_template: Node3D
@export var debris_count := 40
@export var debris_interval := 0.02
@export var debris_lifetime := 0.9
@export var debris_gravity := 22.0
## Chunks thrown up by the eruption at the end of the dash.
@export var eruption_debris := 14
## Hidden ground ring authored at radius 1, expanded to eruption_radius.
@export var ring_template: Node3D
@export var ring_lifetime := 0.5
@export_group("Sound")
@export var eruption_sound: AudioStream
@export var synth_eruption: StringName = &"seismic_boom"

var _dashing := 0.0
var _direction := Vector3.FORWARD
var _spawn_timer := 0.0
var _query_buffer := PackedInt32Array()
var _struck := PackedInt32Array()
var _struck_count := 0
var _debris: Array[Node3D] = []
var _debris_age := PackedFloat32Array()
var _debris_velocity := PackedVector3Array()
var _debris_spin := PackedVector3Array()
var _debris_floor := PackedFloat32Array()
var _next_debris := 0
var _ring: Node3D
var _ring_age := -1.0
var _rng := RandomNumberGenerator.new()
var _eruption_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_rng.randomize()
	_eruption_audio = make_audio(eruption_sound, synth_eruption, -5.0)
	_query_buffer.resize(256)
	_struck.resize(128)
	_debris = make_pool(debris_template, debris_count)
	_debris_age.resize(_debris.size())
	_debris_age.fill(-1.0)
	_debris_velocity.resize(_debris.size())
	_debris_spin.resize(_debris.size())
	_debris_floor.resize(_debris.size())
	var rings := make_pool(ring_template, 1)
	_ring = rings[0] if not rings.is_empty() else null
	if drill != null:
		drill.hide()

func is_drilling() -> bool:
	return _dashing > 0.0

func _activate() -> bool:
	var direction := -player.camera.global_basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = -player.global_basis.z
		direction.y = 0.0
	_direction = direction.normalized()
	player.dash(_direction * (dash_distance / dash_duration), dash_duration)
	player.grant_invulnerability(dash_duration + invulnerability_tail)
	player.camera.fov += fov_punch
	player.add_shake(0.3)
	_dashing = dash_duration
	_spawn_timer = 0.0
	_struck_count = 0
	if drill != null:
		drill.show()
	return true

func _ability_physics(delta: float) -> void:
	if _dashing <= 0.0:
		return
	if not player.active:
		_finish()
		return
	_dashing -= delta
	var center := player.global_position
	_grind_around(center)
	_spawn_timer -= delta
	while _spawn_timer <= 0.0:
		_spawn_timer += debris_interval
		_spit_debris(center, 1.0)
	player.add_shake(0.08)
	if _dashing <= 0.0:
		_erupt(player.global_position)
		_finish()

func _finish() -> void:
	_dashing = 0.0
	if drill != null:
		drill.hide()

func _exit_tree() -> void:
	_finish()

func _grind_around(center: Vector3) -> void:
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
		# Churn them out of the tunnel: sideways, up and back past the drill.
		var away := horde.enemy_position(index) - center
		away.y = 0.0
		var side := away - _direction * away.dot(_direction)
		if side.length_squared() < 0.0001:
			side = _direction.cross(Vector3.UP) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var push := side.normalized() * knockback + Vector3.UP * knockback * 0.35 - _direction * knockback * 0.25
		horde.damage_direct(index, amount, center, push)

func _was_struck(index: int) -> bool:
	for n in _struck_count:
		if _struck[n] == index:
			return true
	return false

func _erupt(at: Vector3) -> void:
	if horde != null:
		horde.damage_radius(at, eruption_radius, eruption_damage * damage_scale(), eruption_knockback)
	player.add_shake(0.55)
	player.camera.fov += fov_punch * 0.6
	if _eruption_audio.stream != null:
		_eruption_audio.play()
	for _n in eruption_debris:
		_spit_debris(at, 1.8)
	if _ring != null:
		_ring_age = 0.0
		_ring.global_position = Vector3(at.x, at.y - 0.85, at.z)
		_ring.scale = Vector3.ONE * 0.3
		_ring.show()

## Flings one pooled chunk from the ground around `center`; `force` scales it.
func _spit_debris(center: Vector3, force: float) -> void:
	if _debris.is_empty():
		return
	var index := _next_debris
	_next_debris = (_next_debris + 1) % _debris.size()
	var side := _direction.cross(Vector3.UP)
	var chunk := _debris[index]
	var floor_y := center.y - 0.85
	chunk.global_position = Vector3(center.x, floor_y + 0.1, center.z) + side * _rng.randf_range(-0.6, 0.6)
	chunk.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0)
	chunk.scale = Vector3.ONE * _rng.randf_range(0.6, 1.4)
	_debris_velocity[index] = (side * _rng.randf_range(-4.5, 4.5) - _direction * _rng.randf_range(1.0, 5.0)) * force + Vector3.UP * _rng.randf_range(4.0, 8.5) * force
	_debris_spin[index] = Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-12.0, 12.0), 0.0)
	_debris_floor[index] = floor_y
	_debris_age[index] = 0.0
	chunk.show()

func _process(delta: float) -> void:
	if _dashing > 0.0 and drill_bit != null:
		drill_bit.rotation.z = fmod(drill_bit.rotation.z + spin_speed * delta, TAU)
		# Slight judder sells the grinding.
		drill_bit.position.y = sin(Time.get_ticks_msec() * 0.09) * 0.02
	for index in range(_debris.size()):
		var age := _debris_age[index]
		if age < 0.0:
			continue
		age += delta
		var chunk := _debris[index]
		if age >= debris_lifetime:
			_debris_age[index] = -1.0
			chunk.hide()
			continue
		_debris_age[index] = age
		var velocity := _debris_velocity[index]
		velocity.y -= debris_gravity * delta
		var at := chunk.global_position + velocity * delta
		if at.y < _debris_floor[index]:
			at.y = _debris_floor[index]
			velocity = Vector3.ZERO
		_debris_velocity[index] = velocity
		chunk.global_position = at
		chunk.rotation += _debris_spin[index] * delta
		var fade := 1.0 - age / debris_lifetime
		chunk.scale = Vector3.ONE * maxf(0.05, minf(1.0, fade * 2.5))
	if _ring == null or _ring_age < 0.0:
		return
	_ring_age += delta
	if _ring_age >= ring_lifetime:
		_ring_age = -1.0
		_ring.hide()
		return
	var t := _ring_age / ring_lifetime
	var radius := lerpf(0.3, eruption_radius, 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t))
	_ring.scale = Vector3(radius, maxf(0.05, 1.0 - t), radius)
