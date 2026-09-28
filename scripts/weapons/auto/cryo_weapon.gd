class_name CryoWeapon
extends AutoWeapon

## A frost aura around the player pulses periodically, damaging and slowing
## every enemy inside. Overclocked, enemies that die while chilled shatter and
## damage their neighbours, which can chain through a frozen crowd.

## Hidden floor disc (radius 1) that follows the player.
@export var aura_template: Node3D
## Hidden floor ring (radius 1) that expands on each pulse.
@export var pulse_template: Node3D
## Hidden unit-size ice burst (overclock shatter).
@export var shatter_template: Node3D
@export var base_radius := 5.0
## Fractional radius gain per level above 1.
@export var radius_per_level := 0.08
@export var slow_factor := 0.45
@export var slow_duration := 1.5
@export var pulse_duration := 0.45
@export var aura_height := 0.03
## Aura radians per second, for a slow shimmer.
@export var aura_spin := 0.5

@export_group("Overclock")
@export var shatter_damage_scale := 2.0
@export var shatter_radius := 2.0
@export var shatter_knockback := 3.0
@export var shatter_duration := 0.3
## Shatters resolved per physics tick; the rest wait for following ticks.
@export var max_shatters_per_tick := 24

var _aura: Node3D
var _pulses: AutoFxPool
var _shatters: AutoFxPool
var _hits := PackedInt32Array()
## Enemies chilled by this weapon (overclock only), unordered.
var _chilled := PackedInt32Array()
var _chilled_count := 0
## Clock time each enemy index stays chilled until; 0 when not listed.
var _chill_until := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _clock := 0.0
var _bump := 0.0
var _yaw := 0.0

func _ready() -> void:
	_hits.resize(512)
	_chilled.resize(256)
	_chill_until.resize(Horde.CAPACITY)
	_aura = aura_template.duplicate() as Node3D
	add_child(_aura)
	_aura.top_level = true
	_aura.hide()

func _refresh() -> void:
	if _pulses == null:
		_pulses = AutoFxPool.new(self, pulse_template, AutoFxPool.Style.RING)
		_pulses.inner_scale = 0.15
		_shatters = AutoFxPool.new(self, shatter_template, AutoFxPool.Style.BLAST)
	_pulses.reserve(2)
	if overclocked:
		_shatters.reserve(24)
	if _timer <= 0.0:
		_timer = cooldown_time() * 0.5

func field_radius() -> float:
	return base_radius * (1.0 + radius_per_level * (level - 1)) * area_scale()

func _tick(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer += cooldown_time()
		_pulse()
	if overclocked and _chilled_count > 0:
		_resolve_chilled()

func _pulse() -> void:
	var center := player.global_position
	var radius := field_radius()
	var amount := damage_amount()
	var found := horde.query_radius(center, radius, _hits)
	for n in range(found):
		var index := _hits[n]
		# Slow first so a killing pulse still counts as "killed while slowed".
		horde.slow(index, slow_factor, slow_duration)
		if overclocked:
			_chill(index)
		horde.damage(index, amount)
	_pulses.spawn(Vector3(center.x, aura_height + 0.02, center.z), radius, pulse_duration)
	_bump = 1.0
	play_cue()

func _chill(index: int) -> void:
	if _chill_until[index] <= 0.0:
		if _chilled_count >= _chilled.size():
			_chilled.resize(_chilled.size() * 2)
		_chilled[_chilled_count] = index
		_chilled_count += 1
	_chill_until[index] = _clock + slow_duration

# Shatters chilled enemies that died (to anything) and forgets thawed ones.
func _resolve_chilled() -> void:
	var shattered := 0
	var cursor := 0
	while cursor < _chilled_count:
		var index := _chilled[cursor]
		var dead := not horde.is_alive(index)
		if dead and shattered >= max_shatters_per_tick:
			cursor += 1
			continue
		if not dead and _chill_until[index] > _clock:
			cursor += 1
			continue
		# Swap-remove, then re-examine the entry moved into this cursor.
		_chill_until[index] = 0.0
		_chilled_count -= 1
		_chilled[cursor] = _chilled[_chilled_count]
		if dead:
			shattered += 1
			_shatter(horde.enemy_position(index))

func _shatter(at: Vector3) -> void:
	var radius := shatter_radius * area_scale()
	horde.damage_radius(at, radius, damage_amount() * shatter_damage_scale, shatter_knockback)
	_shatters.spawn(at, radius * 0.6, shatter_duration, _rng.randf() * TAU)

func _process(delta: float) -> void:
	if _pulses == null:
		return
	_pulses.update(delta)
	_shatters.update(delta)
	if not is_instance_valid(player):
		_aura.hide()
		return
	_bump = maxf(0.0, _bump - delta * 3.0)
	_yaw = fmod(_yaw + aura_spin * delta, TAU)
	var at := player.global_position
	var size := field_radius() * (1.0 + _bump * 0.06)
	_aura.global_position = Vector3(at.x, aura_height, at.z)
	_aura.rotation = Vector3(0.0, _yaw, 0.0)
	_aura.scale = Vector3(size, 1.0 + _bump, size)
	_aura.show()
