class_name NovaWeapon
extends AutoWeapon

## Periodic radial pulse around the player that damages and shoves outward.
## Each extra projectile adds a weaker echo pulse shortly after.

## Hidden floor ring authored with radius 1 in the XZ plane.
@export var ring_template: Node3D
@export var base_radius := 4.5
## Fractional radius gain per level above 1.
@export var radius_per_level := 0.1
@export var knockback := 7.0
@export var ring_duration := 0.4
@export var ring_start_scale := 0.2
@export var ring_height := 0.06
@export var echo_delay := 0.3
@export var echo_damage_scale := 0.6

var _rings: Array[Node3D] = []
var _ring_times := PackedFloat32Array()
var _ring_radii := PackedFloat32Array()
var _timer := 0.0
var _echoes_left := 0
var _echo_timer := 0.0

func _refresh() -> void:
	_grow_pool(ring_template, _rings, 1 + extra_projectiles())
	_ring_times.resize(_rings.size())
	_ring_radii.resize(_rings.size())
	if _timer <= 0.0:
		_timer = cooldown_time() * 0.5

func pulse_radius() -> float:
	return base_radius * (1.0 + radius_per_level * (level - 1)) * area_scale()

func _tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer += cooldown_time()
		_pulse(1.0)
		_echoes_left = extra_projectiles()
		_echo_timer = echo_delay
	elif _echoes_left > 0:
		_echo_timer -= delta
		if _echo_timer <= 0.0:
			_echoes_left -= 1
			_echo_timer = echo_delay
			_pulse(echo_damage_scale)

func _pulse(strength: float) -> void:
	var center := player.global_position
	var radius := pulse_radius()
	horde.damage_radius(center, radius, damage_amount() * strength, knockback * strength)
	# Reuse a finished ring, else the one closest to finishing.
	var slot := 0
	for index in range(_rings.size()):
		if _ring_times[index] <= 0.0:
			slot = index
			break
		if _ring_times[index] < _ring_times[slot]:
			slot = index
	var ring := _rings[slot]
	ring.global_position = Vector3(center.x, ring_height, center.z)
	ring.scale = Vector3(radius * ring_start_scale, 1.0, radius * ring_start_scale)
	ring.show()
	_ring_times[slot] = ring_duration
	_ring_radii[slot] = radius

func _process(delta: float) -> void:
	for index in range(_rings.size()):
		if _ring_times[index] <= 0.0:
			continue
		_ring_times[index] -= delta
		var ring := _rings[index]
		if _ring_times[index] <= 0.0:
			ring.hide()
			continue
		var progress := 1.0 - _ring_times[index] / ring_duration
		var grow := lerpf(ring_start_scale, 1.0, 1.0 - pow(1.0 - progress, 3.0)) * _ring_radii[index]
		var fade := maxf(1.0 - progress * progress, 0.05)
		ring.scale = Vector3(grow, fade, grow)
