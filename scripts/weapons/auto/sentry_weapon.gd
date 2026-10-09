class_name SentryWeapon
extends AutoWeapon

## Periodically deploys turrets at the player's feet. Each turret lasts a while
## and fires tracers at the nearest enemy in range, blinking before it expires.
## Overclocked turrets detonate when they expire.

## Hidden turret facing -Z with its base at y = 0.
@export var turret_template: Node3D
## Hidden unit-length beam along -Z; one per turret.
@export var tracer_template: Node3D
## Hidden unit-size impact spark.
@export var spark_template: Node3D
## Hidden blast flash authored with radius 1 (overclock detonation).
@export var blast_template: Node3D
## Hidden floor ring (radius 1) for deploys and detonations.
@export var shock_template: Node3D
@export var lifetime := 12.0
@export var base_turrets := 1
## Each listed weapon level adds one turret per deployment.
@export var extra_turret_levels := PackedInt32Array([3, 5])
@export var max_turrets := 8
@export var max_live_turrets := 24
@export var target_range := 20.0
## Seconds between a turret's shots at level 1.
@export var fire_interval := 0.5
## Fractional fire interval reduction per level above 1.
@export var fire_interval_per_level := 0.08
@export var min_fire_interval := 0.08
@export var muzzle_height := 0.85
@export var knockback := 1.5
## Distance from the player's feet when several turrets deploy at once.
@export var deploy_spread := 1.4
@export var deploy_time := 0.3
## Seconds before expiry that the turret starts blinking.
@export var expire_warning := 1.5
@export var tracer_duration := 0.07
@export var spark_size := 0.3
@export var deploy_ring_size := 1.2

@export_group("Overclock")
@export var detonation_damage_scale := 5.0
@export var detonation_radius := 4.0
@export var detonation_knockback := 9.0
@export var blast_duration := 0.32

var _turrets: Array[Node3D] = []
var _tracers: Array[Node3D] = []
var _sparks: AutoFxPool
var _blasts: AutoFxPool
var _shocks: AutoFxPool
## Remaining life per turret slot; <= 0 when idle.
var _life := PackedFloat32Array()
var _fire_timers := PackedFloat32Array()
var _yaws := PackedFloat32Array()
var _tracer_times := PackedFloat32Array()
var _tracer_from := PackedVector3Array()
var _tracer_to := PackedVector3Array()
var _rng := RandomNumberGenerator.new()
var _count := 1
var _timer := 0.0

func _refresh() -> void:
	_count = scaled_count(base_turrets, extra_turret_levels, max_turrets)
	var waves := ceili(lifetime / maxf(cooldown_time(), 0.5)) + 1
	var slots := mini(_count * waves, maxi(max_live_turrets, _count))
	_grow_pool(turret_template, _turrets, slots)
	_grow_pool(tracer_template, _tracers, slots)
	if _sparks == null:
		_sparks = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
		_blasts = AutoFxPool.new(self, blast_template, AutoFxPool.Style.BLAST)
		_shocks = AutoFxPool.new(self, shock_template, AutoFxPool.Style.RING)
	_sparks.reserve(slots)
	_shocks.reserve(_count * 2)
	if overclocked:
		_blasts.reserve(_count * 2)
	var size := _turrets.size()
	_life.resize(size)
	_fire_timers.resize(size)
	_yaws.resize(size)
	_tracer_times.resize(size)
	_tracer_from.resize(size)
	_tracer_to.resize(size)
	if _timer <= 0.0:
		_timer = 0.5

func shot_interval() -> float:
	var scale_by_level := maxf(0.2, 1.0 - fire_interval_per_level * (level - 1))
	return maxf(min_fire_interval, fire_interval * scale_by_level * run_state.cooldown_multiplier * run_state.cooldown_boost)

func _tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer += cooldown_time()
		_deploy()
	var amount := damage_amount()
	for index in range(_turrets.size()):
		if _life[index] <= 0.0:
			continue
		_life[index] -= delta
		if _life[index] <= 0.0:
			_expire(index)
			continue
		_fire_timers[index] -= delta
		if _fire_timers[index] > 0.0:
			continue
		var muzzle := _turrets[index].global_position + Vector3.UP * muzzle_height
		var target := horde.nearest(muzzle, target_range)
		if target < 0:
			_fire_timers[index] = 0.2
			continue
		_fire_timers[index] = maxf(_fire_timers[index] + shot_interval(), 0.02)
		var hit_at := horde.enemy_position(target)
		var flat := Vector3(hit_at.x - muzzle.x, 0.0, hit_at.z - muzzle.z)
		if flat.length_squared() > 0.0001:
			flat = flat.normalized()
			_yaws[index] = atan2(-flat.x, -flat.z)
		# Fire from the barrel tip in the new facing.
		var tip := muzzle + Vector3(-sin(_yaws[index]), 0.0, -cos(_yaws[index])) * 0.58
		horde.damage_direct(target, amount, tip, flat * knockback)
		_tracer_from[index] = tip
		_tracer_to[index] = hit_at
		_tracer_times[index] = tracer_duration
		_sparks.spawn(hit_at, spark_size, 0.12)

func _deploy() -> void:
	var feet := player.global_position
	var turn := _rng.randf() * TAU
	for k in range(_count):
		var at := Vector3(feet.x, 0.0, feet.z)
		if _count > 1:
			var angle := turn + TAU * float(k) / float(_count)
			at += Vector3(cos(angle), 0.0, sin(angle)) * deploy_spread
		at.y = horde.ground_height(Vector2(at.x, at.z))
		var slot := _free_slot()
		if _life[slot] > 0.0:
			_expire(slot)
		_life[slot] = lifetime
		_fire_timers[slot] = deploy_time + 0.05 * k
		_yaws[slot] = player.global_rotation.y
		_turrets[slot].global_position = at
		_shocks.spawn(at + Vector3.UP * 0.04, deploy_ring_size, 0.35)
	play_cue()

# An idle slot, else the turret closest to expiring (recycled early).
func _free_slot() -> int:
	var slot := 0
	for index in range(_life.size()):
		if _life[index] <= 0.0:
			return index
		if _life[index] < _life[slot]:
			slot = index
	return slot

func _expire(index: int) -> void:
	_life[index] = 0.0
	_turrets[index].hide()
	_tracers[index].hide()
	_tracer_times[index] = 0.0
	if not overclocked:
		return
	var at := _turrets[index].global_position + Vector3.UP * 0.5
	var radius := detonation_radius * area_scale()
	horde.damage_radius(at, radius, damage_amount() * detonation_damage_scale, detonation_knockback)
	_shocks.spawn(Vector3(at.x, 0.05, at.z), radius, 0.4)
	if not crowds_view(at, radius):
		_blasts.spawn(at, radius, blast_duration)
	play_cue()

func _process(delta: float) -> void:
	if _sparks == null:
		return
	_sparks.update(delta)
	_blasts.update(delta)
	_shocks.update(delta)
	for index in range(_turrets.size()):
		if _tracer_times[index] > 0.0:
			_tracer_times[index] -= delta
			if _tracer_times[index] <= 0.0:
				_tracers[index].hide()
			else:
				place_beam(_tracers[index], _tracer_from[index], _tracer_to[index], _tracer_times[index] / tracer_duration)
		var life := _life[index]
		if life <= 0.0:
			continue
		var turret := _turrets[index]
		# Pop up on deploy, blink faster and faster before expiring.
		var grow := clampf((lifetime - life) / deploy_time, 0.0, 1.0)
		var size := 1.0 - pow(1.0 - grow, 3.0) + sin(grow * PI) * 0.15
		turret.global_transform = Transform3D(Basis(Vector3.UP, _yaws[index]).scaled(Vector3.ONE * maxf(size, 0.05)), turret.global_position)
		turret.visible = life > expire_warning or fmod(life * lerpf(12.0, 4.0, life / expire_warning), 1.0) > 0.35
