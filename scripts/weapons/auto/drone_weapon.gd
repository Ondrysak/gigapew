class_name DroneWeapon
extends AutoWeapon

## Drones orbit the player's head and each snipe the nearest enemy in range.
## Overclocked drones fire piercing beams through every enemy in the line.

## Hidden drone body facing -Z; duplicated once per drone.
@export var drone_template: Node3D
## Hidden unit-length beam along -Z; duplicated once per drone.
@export var tracer_template: Node3D
## Hidden unit-size impact spark.
@export var impact_template: Node3D
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
@export var tracer_duration := 0.09
@export var impact_size := 0.35
## Degrees the drone pitches back on each shot, recovering over the tracer.
@export var recoil_degrees := 25.0

@export_group("Overclock")
## Enemies each beam can pierce.
@export var beam_hits := 12
## Height the beam skims above the floor so it crosses the crowd lengthwise.
@export var beam_height := 0.6
@export var beam_width := 3.0
@export var beam_duration := 0.16

var _drones: Array[Node3D] = []
var _tracers: Array[Node3D] = []
var _impacts: AutoFxPool
var _timers := PackedFloat32Array()
var _tracer_times := PackedFloat32Array()
var _tracer_from := PackedVector3Array()
var _tracer_to := PackedVector3Array()
var _yaws := PackedFloat32Array()
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
var _active := 0
var _angle := 0.0

func _ready() -> void:
	_hits.resize(32)
	_distances.resize(32)

func _refresh() -> void:
	_active = scaled_count(base_drones, extra_drone_levels, max_drones)
	_grow_pool(drone_template, _drones, _active)
	_grow_pool(tracer_template, _tracers, _active)
	if _impacts == null:
		_impacts = AutoFxPool.new(self, impact_template, AutoFxPool.Style.SPARK)
	_impacts.reserve(_active * 2)
	var old := _timers.size()
	var size := maxi(_active, old)
	_timers.resize(size)
	_tracer_times.resize(size)
	_tracer_from.resize(size)
	_tracer_to.resize(size)
	_yaws.resize(size)
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
		if flat.length_squared() < 0.0001:
			flat = Vector3.FORWARD
		flat = flat.normalized()
		_yaws[index] = atan2(-flat.x, -flat.z)
		var end := hit_at
		if overclocked:
			end = _fire_beam(at, flat)
		else:
			horde.damage_direct(target, damage_amount(), at, flat * knockback)
		_impacts.spawn(end, impact_size * (1.6 if overclocked else 1.0), tracer_duration * 1.5)
		_tracer_from[index] = at
		_tracer_to[index] = end
		_tracer_times[index] = beam_duration if overclocked else tracer_duration

# Pierces the whole line at crowd height; returns where the beam is drawn to.
func _fire_beam(from: Vector3, flat: Vector3) -> Vector3:
	var origin := Vector3(from.x, beam_height, from.z)
	var count := horde.raycast(origin, flat, target_range, beam_hits, _hits, _distances)
	var amount := damage_amount()
	for n in range(count):
		horde.damage_direct(_hits[n], amount, origin, flat * knockback)
	return origin + flat * target_range

func _process(delta: float) -> void:
	if _impacts != null:
		_impacts.update(delta)
	for index in range(_tracer_times.size()):
		var drone := _drones[index]
		var recoil := 0.0
		if _tracer_times[index] > 0.0:
			_tracer_times[index] -= delta
			if _tracer_times[index] <= 0.0:
				_tracers[index].hide()
			else:
				# Tracers thin out instead of popping off.
				var duration := beam_duration if overclocked else tracer_duration
				var remaining := _tracer_times[index] / duration
				var width := (beam_width if overclocked else 1.0) * remaining
				place_beam(_tracers[index], _tracer_from[index], _tracer_to[index], width)
				recoil = deg_to_rad(recoil_degrees) * remaining
		if drone.visible:
			drone.rotation = Vector3(recoil, _yaws[index], 0.0)
