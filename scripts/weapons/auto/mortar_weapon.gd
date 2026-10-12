class_name MortarWeapon
extends AutoWeapon

## Lobs shells at random enemies in range; each lands with a radial blast.
## A floor marker shows where each shell will land. Overclocked shells burst
## into cluster bomblets that scatter around the impact.

## Hidden shell body, facing -Z along its flight direction.
@export var shell_template: Node3D
## Hidden blast flash authored with radius 1.
@export var blast_template: Node3D
## Hidden floor ring (radius 1) that expands to the exact blast radius.
@export var shock_template: Node3D
## Hidden floor reticle (radius 1) marking a landing spot.
@export var marker_template: Node3D
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
@export var shock_duration := 0.35

@export_group("Overclock")
@export var bomblets := 4
@export var bomblet_flight_time := 0.4
@export var bomblet_arc_height := 1.8
## Bomblets land this far from the impact (scaled by area).
@export var bomblet_spread := Vector2(1.6, 3.4)
@export var bomblet_radius_scale := 0.55
@export var bomblet_damage_scale := 0.5

var _shells: Array[Node3D] = []
var _markers: Array[Node3D] = []
var _blasts: AutoFxPool
var _shocks: AutoFxPool
## Seconds since launch; negative while waiting in the salvo.
var _shell_times := PackedFloat32Array()
var _shell_flight := PackedFloat32Array()
var _shell_arc := PackedFloat32Array()
## 0 = free, 1 = shell, 2 = bomblet.
var _shell_kind := PackedByteArray()
var _shell_from := PackedVector3Array()
var _shell_to := PackedVector3Array()
var _hits := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _salvo := 1
var _timer := 0.0

func _ready() -> void:
	_hits.resize(512)

func _refresh() -> void:
	_salvo = scaled_count(base_shells, extra_shell_levels, 64)
	# Enough slots for shells (and their bomblets) from two overlapping salvos.
	var slots := _salvo * 2 * (1 + (bomblets if overclocked else 0))
	_grow_pool(shell_template, _shells, slots)
	_grow_pool(marker_template, _markers, slots)
	if _blasts == null:
		_blasts = AutoFxPool.new(self, blast_template, AutoFxPool.Style.BLAST)
		_shocks = AutoFxPool.new(self, shock_template, AutoFxPool.Style.RING)
	_blasts.reserve(slots)
	_shocks.reserve(slots)
	_shell_times.resize(_shells.size())
	_shell_flight.resize(_shells.size())
	_shell_arc.resize(_shells.size())
	_shell_kind.resize(_shells.size())
	_shell_from.resize(_shells.size())
	_shell_to.resize(_shells.size())
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
		var kind := _shell_kind[index]
		if kind == 0:
			continue
		var elapsed := _shell_times[index] + delta
		_shell_times[index] = elapsed
		if elapsed < 0.0:
			continue
		var shell := _shells[index]
		var flight := _shell_flight[index]
		if elapsed >= flight:
			_shell_kind[index] = 0
			shell.hide()
			_markers[index].hide()
			_land(_shell_to[index], kind == 2)
			continue
		var at := _arc_point(index, elapsed / flight)
		var ahead := _arc_point(index, minf(1.0, (elapsed + 0.02) / flight))
		shell.global_position = at
		if ahead.distance_squared_to(at) > 0.000001:
			var direction := (ahead - at).normalized()
			if absf(direction.y) < 0.99:
				shell.look_at(ahead, Vector3.UP)
		shell.show()

func _arc_point(index: int, t: float) -> Vector3:
	return _shell_from[index].lerp(_shell_to[index], t) + Vector3.UP * (_shell_arc[index] * 4.0 * t * (1.0 - t))

func _fire_salvo() -> bool:
	var found := horde.query_radius(player.global_position, target_range, _hits)
	# Sky-fired shells cannot originate inside a room or underground ceiling.
	if horde.is_roofed(Vector2(player.global_position.x, player.global_position.z)):
		return false
	if found <= 0:
		return false
	var origin := player.global_position + Vector3.UP * launch_height
	var queued := 0
	for index in range(_shells.size()):
		if queued >= _salvo:
			break
		if _shell_kind[index] != 0:
			continue
		var target := _hits[_rng.randi_range(0, found - 1)]
		var land := horde.enemy_position(target)
		var xz := Vector2(land.x, land.z)
		if horde.is_roofed(xz) or horde.is_blocked(xz, 0.0) or not horde.is_reachable(xz):
			continue
		land.y = horde.ground_height(Vector2(land.x, land.z))
		_launch(index, 1, origin, land, flight_time, arc_height, -salvo_interval * queued)
		queued += 1
	return queued > 0

func _launch(index: int, kind: int, from: Vector3, to: Vector3, flight: float, arc: float, delay: float) -> void:
	_shell_kind[index] = kind
	_shell_from[index] = from
	_shell_to[index] = to
	_shell_flight[index] = flight
	_shell_arc[index] = arc
	_shell_times[index] = delay
	_shells[index].scale = Vector3.ONE * (0.6 if kind == 2 else 1.0)

func _land(at: Vector3, bomblet: bool) -> void:
	var radius := blast_radius() * (bomblet_radius_scale if bomblet else 1.0)
	var amount := damage_amount() * (bomblet_damage_scale if bomblet else 1.0)
	horde.damage_radius(at, radius, amount, knockback * (0.5 if bomblet else 1.0))
	_shocks.spawn(at + Vector3.UP * 0.05, radius, shock_duration)
	if not crowds_view(at, radius):
		_blasts.spawn(at, radius, blast_duration * (0.7 if bomblet else 1.0))
	if bomblet:
		return
	play_cue()
	if overclocked:
		_scatter_bomblets(at)

func _scatter_bomblets(at: Vector3) -> void:
	var left := bomblets
	var turn := _rng.randf() * TAU
	for index in range(_shells.size()):
		if left <= 0:
			return
		if _shell_kind[index] != 0:
			continue
		var angle := turn + TAU * float(left) / float(bomblets)
		var distance := _rng.randf_range(bomblet_spread.x, bomblet_spread.y) * area_scale()
		var to := at + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var xz := Vector2(to.x, to.z)
		if horde.is_roofed(xz) or horde.is_blocked(xz, 0.0) or not horde.is_reachable(xz):
			continue
		to.y = horde.ground_height(xz)
		_launch(index, 2, at + Vector3.UP * 0.3, to, bomblet_flight_time * _rng.randf_range(0.85, 1.15), bomblet_arc_height, 0.0)
		left -= 1

func _process(delta: float) -> void:
	if _blasts == null:
		return
	_blasts.update(delta)
	_shocks.update(delta)
	# Landing reticles tighten and brighten as their shell comes down.
	for index in range(_shells.size()):
		var marker := _markers[index]
		if _shell_kind[index] != 1:
			if marker.visible:
				marker.hide()
			continue
		var progress := clampf((_shell_times[index] + salvo_interval * 4.0) / (_shell_flight[index] + salvo_interval * 4.0), 0.0, 1.0)
		var size := blast_radius() * lerpf(1.25, 0.55, progress)
		marker.global_position = _shell_to[index] + Vector3.UP * 0.04
		marker.scale = Vector3(size, 1.0, size)
		marker.rotation = Vector3(0.0, progress * PI, 0.0)
		marker.show()
