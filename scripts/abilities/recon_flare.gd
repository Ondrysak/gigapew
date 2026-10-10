class_name ReconFlare
extends ActiveAbility

## Fires a flare at the aimed point (world surface or first enemy in line,
## within max_range). Where it lands it lights a zone for zone_duration: main-
## gun hits on enemies inside deal +exposure_bonus damage, and every
## pulse_interval the zone marks (tiny damage flash) and slows the enemies in it.

@export var max_range := 30.0
@export var flight_time := 0.45
@export var arc_height := 2.5
@export var zone_radius := 9.0
@export var zone_duration := 6.0
## Extra main-gun damage fraction on enemies inside the zone (0.5 = +50%).
@export var exposure_bonus := 0.5
@export var pulse_interval := 0.6
## Per-pulse marking damage (scaled by the run's damage multiplier).
@export var reveal_damage := 2.0
@export var slow_factor := 0.8
@export var slow_duration := 0.7
## Flare body (a Node3D in this scene; switched to top_level). Rests glowing at
## the zone center while lit.
@export var flare: Node3D
## Lit-zone visuals (switched to top_level), placed at the landing point.
@export var zone: Node3D
## Child of zone: flat ring authored at radius 1, scaled to zone_radius.
@export var zone_ring: Node3D
## Child of zone: flat ring authored at radius 1, swept outwards every pulse.
@export var sweep: Node3D
@export_group("Sound")
@export var land_sound: AudioStream
@export var synth_land: StringName = &"blink"

var _flight := -1.0
var _lit := 0.0
var _pulse := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _arc := 0.0
var _query: PhysicsRayQueryParameters3D
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
var _query_buffer := PackedInt32Array()
var _land_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_land_audio = make_audio(land_sound, synth_land, -10.0)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	_hits.resize(4)
	_distances.resize(4)
	_query_buffer.resize(256)
	for node in [flare, zone]:
		if node != null:
			node.top_level = true
			node.hide()

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	super(p_player, p_horde, p_run_state)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [p_player.get_rid()])

func is_ready() -> bool:
	return super() and _flight < 0.0

func _activate() -> bool:
	var camera := player.camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var space := player.get_world_3d().direct_space_state
	var reach := max_range
	_query.from = origin
	_query.to = origin + direction * max_range
	var wall := space.intersect_ray(_query)
	var target := origin + direction * max_range
	var ground := false
	if not wall.is_empty():
		target = wall["position"]
		reach = origin.distance_to(target)
		ground = Vector3(wall["normal"]).y > 0.5
		if not ground:
			target -= direction * 0.5
	if horde != null and horde.raycast(origin, direction, reach, 1, _hits, _distances) > 0:
		target = horde.enemy_position(_hits[0])
		ground = false
	if horde != null:
		var area := horde.play_area
		target.x = clampf(target.x, area.position.x, area.end.x)
		target.z = clampf(target.z, area.position.y, area.end.y)
	if not ground:
		target = _drop_to_floor(space, target, origin.y)
	_from = origin + camera.global_basis.x * 0.3 - camera.global_basis.y * 0.25
	_to = target
	if _lit > 0.0:
		_finish()
	_arc = arc_height * clampf(_from.distance_to(_to) / max_range, 0.35, 1.0)
	_flight = 0.0
	if flare != null:
		flare.global_position = _from
		flare.show()
	return true

func _drop_to_floor(space: PhysicsDirectSpaceState3D, at: Vector3, top: float) -> Vector3:
	_query.from = Vector3(at.x, maxf(at.y, top) + 1.0, at.z)
	_query.to = Vector3(at.x, -20.0, at.z)
	var floor_hit := space.intersect_ray(_query)
	if floor_hit.is_empty():
		return Vector3(at.x, 0.0, at.z)
	return floor_hit["position"]

func _ability_physics(delta: float) -> void:
	if _flight < 0.0 and _lit <= 0.0:
		return
	if not player.active:
		_finish()
		return
	if _flight >= 0.0:
		_flight += delta
		if _flight >= flight_time:
			_flight = -1.0
			_land()
	if _lit <= 0.0:
		return
	_lit -= delta
	if _lit <= 0.0:
		_finish()
		return
	_pulse -= delta
	if _pulse <= 0.0:
		_pulse += pulse_interval
		_mark()

func _land() -> void:
	_lit = zone_duration * duration_scale()
	_pulse = 0.0
	if run_state != null:
		run_state.add_exposure_zone(self, _to, zone_radius, exposure_bonus * ability_damage_scale(rank()))
	if flare != null:
		flare.global_position = _to + Vector3.UP * 0.12
		flare.rotation = Vector3.ZERO
	if zone != null:
		zone.global_position = _to + Vector3.UP * 0.05
		zone.show()
	if _land_audio.stream != null:
		_land_audio.play()

## One reveal pulse: marks (flash) and lightly slows every enemy in the zone.
func _mark() -> void:
	if horde == null:
		return
	var count := horde.query_radius(_to, zone_radius, _query_buffer)
	for n in count:
		horde.slow(_query_buffer[n], slow_factor, slow_duration)
	horde.damage_radius(_to, zone_radius, reveal_damage * damage_scale(), 0.0)

func _finish() -> void:
	_flight = -1.0
	_lit = 0.0
	if run_state != null:
		run_state.remove_exposure_zone(self)
	if flare != null:
		flare.hide()
	if zone != null:
		zone.hide()

func _exit_tree() -> void:
	# The RunState outlives the stage; never leave the zone behind.
	if _lit > 0.0 or _flight >= 0.0:
		_finish()

func _cancel_effects() -> void:
	_finish()

func _process(_delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	if _flight >= 0.0 and flare != null:
		var t := minf(_flight / flight_time, 1.0)
		flare.global_position = _from.lerp(_to, t) + Vector3.UP * (_arc * 4.0 * t * (1.0 - t) + 0.12 * t)
		flare.rotation = Vector3(t * 11.0, t * 4.0, 0.0)
	if _lit <= 0.0 or zone == null:
		return
	var elapsed := zone_duration * duration_scale() - _lit
	var grow := minf(1.0, elapsed / 0.25)
	if zone_ring != null:
		var pulse := zone_radius * grow * (1.0 + sin(elapsed * 9.0) * 0.025)
		zone_ring.scale = Vector3(pulse, 1.0, pulse)
	if sweep != null:
		var p := clampf(1.0 - _pulse / pulse_interval, 0.0, 1.0)
		var radius := lerpf(0.3, zone_radius, 1.0 - (1.0 - p) * (1.0 - p))
		sweep.scale = Vector3(radius, maxf(0.05, 1.0 - p), radius)
	# Flicker through the final second as a warning.
	var shown := _lit >= 1.0 or fmod(_lit, 0.2) >= 0.08
	zone.visible = shown
	if flare != null:
		flare.visible = shown
