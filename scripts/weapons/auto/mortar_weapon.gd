class_name MortarWeapon
extends AutoWeapon

## Lobs shells at random enemies in range; each lands with a radial blast.

## Hidden shell body, facing -Z along its flight direction.
@export var shell_template: Node3D
## Hidden blast flash authored with radius 1.
@export var blast_template: Node3D
@export var target_range := 25.0
@export var flight_time := 0.7
@export var arc_height := 6.0
@export var launch_height := 1.4
## Delay between shells in one salvo.
@export var salvo_interval := 0.09
@export var base_shells := 1
## Each listed weapon level adds one shell per salvo.
@export var extra_shell_levels := PackedInt32Array([3, 5])
@export var base_blast_radius := 2.6
## Fractional blast radius gain per level above 1.
@export var blast_radius_per_level := 0.08
@export var knockback := 8.0
@export var blast_duration := 0.28
## Blasts whose flash would reach within this distance of the camera still deal
## damage but skip the flash, so point-blank salvos never white out the view.
@export var min_view_clearance := 1.0

var _shells: Array[Node3D] = []
var _blasts: Array[Node3D] = []
## Seconds since launch; negative while waiting in the salvo.
var _shell_times := PackedFloat32Array()
var _shell_live := PackedByteArray()
var _shell_from := PackedVector3Array()
var _shell_to := PackedVector3Array()
var _blast_times := PackedFloat32Array()
var _blast_radii := PackedFloat32Array()
var _hits := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _salvo := 1
var _timer := 0.0

func _ready() -> void:
	_hits.resize(512)

func _refresh() -> void:
	_salvo = base_shells + extra_projectiles()
	for unlock in extra_shell_levels:
		if level >= unlock:
			_salvo += 1
	# Enough slots for shells from two overlapping salvos.
	var slots := _salvo * 2
	_grow_pool(shell_template, _shells, slots)
	_grow_pool(blast_template, _blasts, slots)
	_shell_times.resize(_shells.size())
	_shell_live.resize(_shells.size())
	_shell_from.resize(_shells.size())
	_shell_to.resize(_shells.size())
	_blast_times.resize(_blasts.size())
	_blast_radii.resize(_blasts.size())
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
	for index in range(_shells.size()):
		if _shell_live[index] == 0:
			continue
		var elapsed := _shell_times[index] + delta
		_shell_times[index] = elapsed
		if elapsed < 0.0:
			continue
		var shell := _shells[index]
		if elapsed >= flight_time:
			_shell_live[index] = 0
			shell.hide()
			_explode(_shell_to[index])
			continue
		var at := _arc_point(index, elapsed / flight_time)
		var ahead := _arc_point(index, minf(1.0, (elapsed + 0.02) / flight_time))
		shell.global_position = at
		if ahead.distance_squared_to(at) > 0.000001:
			var direction := (ahead - at).normalized()
			if absf(direction.y) < 0.99:
				shell.look_at(ahead, Vector3.UP)
		shell.show()

func _arc_point(index: int, t: float) -> Vector3:
	return _shell_from[index].lerp(_shell_to[index], t) + Vector3.UP * (arc_height * 4.0 * t * (1.0 - t))

func _fire_salvo() -> bool:
	var found := horde.query_radius(player.global_position, target_range, _hits)
	if found <= 0:
		return false
	var origin := player.global_position + Vector3.UP * launch_height
	var queued := 0
	for index in range(_shells.size()):
		if queued >= _salvo:
			break
		if _shell_live[index] != 0:
			continue
		var target := _hits[_rng.randi_range(0, found - 1)]
		var land := horde.enemy_position(target)
		land.y = 0.0
		_shell_from[index] = origin
		_shell_to[index] = land
		_shell_times[index] = -salvo_interval * queued
		_shell_live[index] = 1
		queued += 1
	return queued > 0

func _explode(at: Vector3) -> void:
	var radius := blast_radius()
	horde.damage_radius(at, radius, damage_amount(), knockback)
	if player.camera.global_position.distance_to(at) < radius + min_view_clearance:
		return
	var slot := 0
	for index in range(_blasts.size()):
		if _blast_times[index] <= 0.0:
			slot = index
			break
		if _blast_times[index] < _blast_times[slot]:
			slot = index
	var blast := _blasts[slot]
	blast.global_position = at
	blast.scale = Vector3.ONE * radius * 0.3
	blast.show()
	_blast_times[slot] = blast_duration
	_blast_radii[slot] = radius

func _process(delta: float) -> void:
	for index in range(_blasts.size()):
		if _blast_times[index] <= 0.0:
			continue
		_blast_times[index] -= delta
		var blast := _blasts[index]
		if _blast_times[index] <= 0.0:
			blast.hide()
			continue
		var progress := 1.0 - _blast_times[index] / blast_duration
		# Snap out to full radius, then collapse as the flash fades.
		var size := sin(minf(progress * 1.6, 1.0) * PI * 0.5) * (1.0 - progress * progress * 0.7)
		blast.scale = Vector3.ONE * maxf(size, 0.02) * _blast_radii[index]
