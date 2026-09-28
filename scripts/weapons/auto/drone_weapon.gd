class_name DroneWeapon
extends AutoWeapon

## Drones orbit the player's head and each snipe the nearest enemy in range.

## Hidden drone body; duplicated once per drone.
@export var drone_template: Node3D
## Hidden unit-length beam along -Z; duplicated once per drone.
@export var tracer_template: Node3D
@export var target_range := 18.0
@export var knockback := 2.0
@export var base_drones := 1
## Each listed weapon level adds one drone.
@export var extra_drone_levels := PackedInt32Array([3, 5])
@export var max_drones := 8
@export var orbit_radius := 1.5
@export var orbit_speed := 1.6
@export var height_offset := 0.35
@export var bob_height := 0.12
@export var tracer_duration := 0.07

var _drones: Array[Node3D] = []
var _tracers: Array[Node3D] = []
var _timers := PackedFloat32Array()
var _tracer_times := PackedFloat32Array()
var _active := 0
var _angle := 0.0

func _refresh() -> void:
	var count := base_drones + extra_projectiles()
	for unlock in extra_drone_levels:
		if level >= unlock:
			count += 1
	_active = clampi(count, 1, max_drones)
	_grow_pool(drone_template, _drones, _active)
	_grow_pool(tracer_template, _tracers, _active)
	var old := _timers.size()
	_timers.resize(maxi(_active, old))
	_tracer_times.resize(_timers.size())
	var cooldown := cooldown_time()
	for index in range(_drones.size()):
		if index >= old:
			# Stagger new drones so volleys ripple instead of stacking.
			_timers[index] = cooldown * float(index) / float(_active)
		if index >= _active:
			_drones[index].hide()
			_tracers[index].hide()

func _tick(delta: float) -> void:
	_angle = fmod(_angle + orbit_speed * delta, TAU)
	var center := player.head.global_position
	var bob_phase := Time.get_ticks_msec() * 0.003
	for index in range(_active):
		var drone := _drones[index]
		var angle := _angle + TAU * float(index) / float(_active)
		var at := center + Vector3(cos(angle) * orbit_radius, height_offset + sin(bob_phase + index) * bob_height, sin(angle) * orbit_radius)
		drone.global_position = at
		drone.show()
		_timers[index] -= delta
		if _timers[index] > 0.0:
			continue
		var target := horde.nearest(at, target_range)
		if target < 0:
			_timers[index] = 0.15
			continue
		_timers[index] = maxf(_timers[index] + cooldown_time(), 0.02)
		var hit_at := horde.enemy_position(target)
		var flat := Vector3(hit_at.x - at.x, 0.0, hit_at.z - at.z)
		if flat.length_squared() > 0.01:
			drone.look_at(hit_at, Vector3.UP)
		horde.damage(target, damage_amount(), flat.normalized() * knockback)
		place_beam(_tracers[index], at, hit_at)
		_tracer_times[index] = tracer_duration

func _process(delta: float) -> void:
	for index in range(_tracer_times.size()):
		if _tracer_times[index] > 0.0:
			_tracer_times[index] -= delta
			if _tracer_times[index] <= 0.0:
				_tracers[index].hide()
