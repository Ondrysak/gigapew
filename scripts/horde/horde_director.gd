class_name HordeDirector
extends Node

## Ordinary species spawn indefinitely; elapsed only controls the pressure ramp.
## Boss release is explicit for authored encounters, never a campaign countdown.
signal boss_phase_started(definition: HordeEnemyDefinition)

## Share of groups placed behind the player's view rather than anywhere.
@export_range(0.0, 1.0) var behind_bias := 0.6

var elapsed := 0.0
var boss_phase := false
## Spawn-rate multiplier, raised while the player extracts.
var surge := 1.0
## Seconds before spawning starts (a calm arrival); counts down unpaused.
var grace := 0.0
var _horde: Horde
var _schedule: SpawnSchedule
var _player: ArenaPlayer
var _accumulated := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()

func setup(horde: Horde, schedule: SpawnSchedule, player: ArenaPlayer, seed: int = -1) -> void:
	_horde = horde
	_schedule = schedule
	_player = player
	elapsed = 0.0
	boss_phase = false
	_accumulated.resize(schedule.waves.size())
	_accumulated.fill(0.0)
	if seed == -1:
		_rng.randomize()
	else:
		_rng.seed = seed

## Returns false when there is currently no safe boss placement; callers may retry.
func release_boss() -> bool:
	if boss_phase or _schedule == null or _schedule.boss == null:
		return false
	if not is_instance_valid(_player) or not _player.active or not is_instance_valid(_horde):
		return false
	if not _spawn_group(_schedule.boss, 1, _schedule.boss_health_multiplier):
		return false
	boss_phase = true
	boss_phase_started.emit(_schedule.boss)
	return true

func _physics_process(delta: float) -> void:
	if get_tree().paused or _schedule == null or not is_instance_valid(_horde) or not is_instance_valid(_player) or not _player.active:
		return
	if grace > 0.0:
		grace = maxf(0.0, grace - delta)
		return
	elapsed = minf(elapsed + delta, maxf(0.0, _schedule.ramp_duration))
	for w in _schedule.waves.size():
		var wave := _schedule.waves[w]
		if wave == null or wave.enemy == null or wave.enemy.is_boss:
			continue
		# Start/end mark a pressure ramp, not availability windows. Every ordinary
		# species has its opening rate immediately and retains its final rate forever.
		var span := maxf(0.001, wave.end_time - wave.start_time)
		var progress := clampf((elapsed - wave.start_time) / span, 0.0, 1.0)
		var rate := maxf(0.0, lerpf(wave.rate_start, wave.rate_end, progress))
		_accumulated[w] += rate * surge * delta
		var group := maxi(1, wave.group_size)
		while _accumulated[w] >= group:
			_accumulated[w] -= group
			if _horde.population_count + group > _schedule.max_alive:
				# Full crowd: drop the backlog instead of bursting later.
				_accumulated[w] = 0.0
				break
			if not _spawn_group(wave.enemy, group, wave.health_multiplier):
				# A blocked ring is not permission to spawn inside cover or store a burst.
				_accumulated[w] = 0.0
				break

func _spawn_group(definition: HordeEnemyDefinition, count: int, health_multiplier: float) -> bool:
	if definition == null or count <= 0:
		return false
	var spread := sqrt(float(count)) * (definition.radius * 2.2) if count > 1 else 0.0
	# Reserve clearance for the entire group, not just its center.
	var center := _pick_point(definition.radius + spread)
	if not center.is_finite():
		return false
	var spawned := false
	for n in count:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * spread
		var point := center + offset
		if _horde.is_blocked(point, definition.radius) or not _horde.is_reachable(point) \
				or absf(_horde.ground_height(point) - _horde.ground_height(center)) > Horde.LEVEL_GAP:
			continue
		if _horde.spawn(definition, point, health_multiplier) >= 0:
			spawned = true
	return spawned

func _pick_point(radius: float) -> Vector2:
	var player := Vector2(_player.global_position.x, _player.global_position.z)
	var forward := -_player.global_basis.z
	var facing := atan2(forward.z, forward.x)
	var minimum := _horde_area_min(radius)
	var maximum := _horde_area_max(radius)
	if minimum.x > maximum.x or minimum.y > maximum.y:
		return Vector2.INF
	var feet := _player.global_position.y - 0.9
	var fallback := Vector2.INF
	var underground := feet < -2.0
	for attempt in (48 if underground else 24):
		var angle := _rng.randf() * TAU
		if _rng.randf() < behind_bias:
			angle = facing + PI + _rng.randf_range(-1.9, 1.9)
		var distance := _rng.randf_range(_schedule.spawn_distance_min, _schedule.spawn_distance_max)
		var minimum_distance := _schedule.spawn_distance_min * 0.6
		if underground and attempt >= 24:
			# A metro hall need not fit the street-sized ring. Keep a safe approach
			# distance and the same behind-player bias on its own floor.
			minimum_distance = maxf(6.0, radius + Horde.PLAYER_RADIUS + 2.0)
			distance = _rng.randf_range(minimum_distance, maxf(minimum_distance, minf(12.0, _schedule.spawn_distance_min)))
		var point := player + Vector2.from_angle(angle) * distance
		# Near a wall the ring leaves the arena: pull the point back inside.
		point = point.clamp(minimum, maximum)
		if point.distance_to(player) < minimum_distance \
				or _horde.is_blocked(point, radius) or not _horde.is_reachable(point):
			continue
		# Prefer the player's actual level, particularly inside the underground.
		if absf(_horde.ground_height(point) - feet) <= Horde.LEVEL_GAP:
			return point
		if not fallback.is_finite():
			fallback = point
	return fallback

func _horde_area_min(radius: float) -> Vector2:
	return _horde.play_area.position + Vector2.ONE * (radius + 1.0)

func _horde_area_max(radius: float) -> Vector2:
	return _horde.play_area.end - Vector2.ONE * (radius + 1.0)
