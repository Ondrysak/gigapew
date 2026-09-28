class_name HordeDirector
extends Node

## Runs a SpawnSchedule: ramps each wave's spawn rate over time, places groups
## on a ring around the player (biased behind them), then releases the boss.

signal boss_phase_started(definition: HordeEnemyDefinition)

## Share of groups placed behind the player's view rather than anywhere.
@export_range(0.0, 1.0) var behind_bias := 0.6

var elapsed := 0.0
var boss_phase := false
var _horde: Horde
var _schedule: SpawnSchedule
var _player: ArenaPlayer
var _accumulated := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()

func setup(horde: Horde, schedule: SpawnSchedule, player: ArenaPlayer) -> void:
	_horde = horde
	_schedule = schedule
	_player = player
	_accumulated.resize(schedule.waves.size())
	_accumulated.fill(0.0)
	_rng.randomize()

func remaining() -> float:
	return maxf(0.0, _schedule.duration - elapsed)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.active:
		return
	elapsed += delta
	if not boss_phase and elapsed >= _schedule.duration:
		boss_phase = true
		if _schedule.boss != null:
			_spawn_group(_schedule.boss, 1, _schedule.boss_health_multiplier)
		boss_phase_started.emit(_schedule.boss)
	for w in _schedule.waves.size():
		var wave := _schedule.waves[w]
		# Waves reaching the stage end keep their final rate through the boss fight.
		var open_ended := wave.end_time >= _schedule.duration
		if elapsed < wave.start_time or (elapsed > wave.end_time and not open_ended):
			continue
		var span := maxf(0.001, wave.end_time - wave.start_time)
		var progress := clampf((elapsed - wave.start_time) / span, 0.0, 1.0)
		_accumulated[w] += lerpf(wave.rate_start, wave.rate_end, progress) * delta
		var group := maxi(1, wave.group_size)
		while _accumulated[w] >= group:
			_accumulated[w] -= group
			if _horde.alive_count + group > _schedule.max_alive:
				# Full crowd: drop the backlog instead of bursting later.
				_accumulated[w] = 0.0
				break
			_spawn_group(wave.enemy, group, wave.health_multiplier)

func _spawn_group(definition: HordeEnemyDefinition, count: int, health_multiplier: float) -> void:
	var center := _pick_point(definition.radius)
	var spread := sqrt(float(count)) * (definition.radius * 2.2)
	for n in count:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * spread
		_horde.spawn(definition, center + offset, health_multiplier)

func _pick_point(radius: float) -> Vector2:
	var player := Vector2(_player.global_position.x, _player.global_position.z)
	var forward := -_player.global_basis.z
	var facing := atan2(forward.z, forward.x)
	var best := player
	for attempt in 8:
		var angle := _rng.randf() * TAU
		if _rng.randf() < behind_bias:
			angle = facing + PI + _rng.randf_range(-1.9, 1.9)
		var distance := _rng.randf_range(_schedule.spawn_distance_min, _schedule.spawn_distance_max)
		var point := player + Vector2.from_angle(angle) * distance
		# Near a wall the ring leaves the arena: pull the point back inside.
		point = point.clamp(_horde_area_min(radius), _horde_area_max(radius))
		best = point
		if point.distance_to(player) >= _schedule.spawn_distance_min * 0.6 and not _horde.is_blocked(point, radius):
			return point
	return best

func _horde_area_min(radius: float) -> Vector2:
	return _horde.play_area.position + Vector2.ONE * (radius + 1.0)

func _horde_area_max(radius: float) -> Vector2:
	return _horde.play_area.end - Vector2.ONE * (radius + 1.0)
