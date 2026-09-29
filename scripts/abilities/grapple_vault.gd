class_name GrappleVault
extends ActiveAbility

## Grapples up and forward along the movement input (or the view when standing
## still), briefly invulnerable, then slams down: the landing shockwave damages
## and hurls back every enemy around the touchdown point.

@export var leap_speed := 13.0
@export var lift_speed := 9.0
@export var rise_time := 0.32
@export var invulnerability := 0.5
@export var fov_punch := 10.0
@export var landing_radius := 5.5
@export var landing_damage := 60.0
@export var landing_knockback := 26.0
@export var landing_shake := 0.45
## The slam triggers after this long airborne even if no floor was touched.
@export var safety_timeout := 2.5
## Grapple line (a thin line along -Z, length 1; switched to top_level) drawn
## from the player to the anchor during the rise.
@export var line: Node3D
@export var line_fade := 0.2
## Hidden ground ring authored at radius 1, expanded to landing_radius.
@export var ring_template: Node3D
@export var ring_lifetime := 0.5
## Hidden dust flash authored at radius 1, flashed at the landing point.
@export var dust_template: Node3D
@export var dust_lifetime := 0.4
@export var dust_radius := 2.2
@export_group("Sound")
@export var land_sound: AudioStream
@export var synth_land: StringName = &"seismic_boom"

var _air_time := -1.0
var _left_ground := false
var _line_age := -1.0
var _direction := Vector3.FORWARD
var _anchor := Vector3.ZERO
var _rings: Array[Node3D] = []
var _ring_age := PackedFloat32Array()
var _ring_radius := PackedFloat32Array()
var _next_ring := 0
var _dust: Node3D
var _dust_age := -1.0
var _land_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_land_audio = make_audio(land_sound, synth_land, -6.0)
	if line != null:
		line.top_level = true
		line.hide()
	_rings = make_pool(ring_template, 2)
	_ring_age.resize(_rings.size())
	_ring_age.fill(-1.0)
	_ring_radius.resize(_rings.size())
	var dusts := make_pool(dust_template, 1)
	_dust = dusts[0] if not dusts.is_empty() else null

func is_ready() -> bool:
	return super() and _air_time < 0.0

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
	var leap := _direction * leap_speed + Vector3.UP * lift_speed
	player.dash(leap, rise_time)
	player.grant_invulnerability(invulnerability)
	player.camera.fov += fov_punch
	player.add_shake(0.15)
	# The hook bites a little past and above the apex of the rise.
	_anchor = start + leap * rise_time + _direction * 2.5 + Vector3.UP * 1.5
	_air_time = 0.0
	_left_ground = false
	_line_age = 0.0
	_flash_ring(start, 1.4)
	return true

func _ability_physics(delta: float) -> void:
	if _air_time < 0.0:
		return
	if not player.active:
		_air_time = -1.0
		_line_age = -1.0
		if line != null:
			line.hide()
		return
	_air_time += delta
	if not player.is_on_floor():
		_left_ground = true
	elif not player.is_dashing() and (_left_ground or _air_time > rise_time + 0.1):
		_slam()
		return
	if _air_time >= safety_timeout:
		_slam()

func _slam() -> void:
	_air_time = -1.0
	var at := player.global_position
	if horde != null:
		horde.damage_radius(at, landing_radius, landing_damage * damage_scale(), landing_knockback)
	player.add_shake(landing_shake)
	if _land_audio.stream != null:
		_land_audio.play()
	_flash_ring(at, landing_radius)
	if _dust != null:
		_dust_age = 0.0
		_dust.global_position = Vector3(at.x, at.y - 0.85, at.z)
		_dust.scale = Vector3.ONE * 0.2
		_dust.show()

func _flash_ring(at: Vector3, radius: float) -> void:
	if _rings.is_empty():
		return
	var ring := _rings[_next_ring]
	_ring_age[_next_ring] = 0.0
	_ring_radius[_next_ring] = radius
	_next_ring = (_next_ring + 1) % _rings.size()
	ring.global_position = Vector3(at.x, at.y - 0.85, at.z)
	ring.scale = Vector3.ONE * 0.2
	ring.show()

func _process(delta: float) -> void:
	_update_line(delta)
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
		var radius := _ring_radius[index] * (1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t))
		ring.scale = Vector3(maxf(radius, 0.05), maxf(0.05, 1.0 - t), maxf(radius, 0.05))
	if _dust_age >= 0.0 and _dust != null:
		_dust_age += delta
		if _dust_age >= dust_lifetime:
			_dust_age = -1.0
			_dust.hide()
		else:
			var p := _dust_age / dust_lifetime
			var size := sin(minf(p * 2.0, 1.0) * PI * 0.5) * (1.0 - p * p * 0.8) * dust_radius
			_dust.scale = Vector3(maxf(size, 0.02), maxf(size * 0.35, 0.02), maxf(size, 0.02))

func _update_line(delta: float) -> void:
	if _line_age < 0.0 or line == null:
		return
	_line_age += delta
	var total := rise_time + line_fade
	if _line_age >= total:
		_line_age = -1.0
		line.hide()
		return
	var hand := player.global_position + Vector3.UP * 0.3 + _direction * 0.3
	var span := _anchor - hand
	var length := span.length()
	if length < 0.2:
		line.hide()
		return
	var fade := 1.0 if _line_age <= rise_time else 1.0 - (_line_age - rise_time) / line_fade
	line.global_position = hand
	line.global_basis = Basis.looking_at(span / length)
	line.scale = Vector3(fade, fade, length)
	line.show()
