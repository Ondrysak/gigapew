class_name SeismicCharge
extends ActiveAbility

## Lobs a charge at the aimed point (world surface or first enemy in line,
## within max_range). It lands after flight_time and erupts in a heavy blast.

@export var max_range := 22.0
@export var flight_time := 0.6
@export var arc_height := 3.5
@export var blast_radius := 7.0
@export var blast_damage := 160.0
@export var blast_knockback := 32.0
## Thrown charge body (a Node3D in this scene; switched to top_level).
@export var charge: Node3D
## Flat ring authored at radius 1 marking the blast area during the flight.
@export var marker: Node3D
## Hidden flat ring authored at radius 1, expanded to blast_radius on impact.
@export var shock_template: Node3D
## Hidden flash authored at radius 1 (core fireball and pillar).
@export var flash_template: Node3D
@export var flash_radius := 2.4
@export var blast_duration := 0.55
## Flashes that would reach within this distance of the camera are skipped.
@export var min_view_clearance := 1.0
@export_group("Sound")
@export var impact_sound: AudioStream
@export var synth_impact: StringName = &"seismic_boom"

var _flight := -1.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _arc := 0.0
var _blast_age := -1.0
var _query: PhysicsRayQueryParameters3D
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
var _shock: Node3D
var _flash: Node3D
var _impact_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_impact_audio = make_audio(impact_sound, synth_impact, -3.0)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	_hits.resize(4)
	_distances.resize(4)
	for node in [charge, marker]:
		if node != null:
			node.top_level = true
			node.hide()
	var shocks := make_pool(shock_template, 1)
	_shock = shocks[0] if not shocks.is_empty() else null
	var flashes := make_pool(flash_template, 1)
	_flash = flashes[0] if not flashes.is_empty() else null

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
			# Back off the surface so a charge thrown at a wall drops in front of it.
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
	_arc = arc_height * clampf(_from.distance_to(_to) / max_range, 0.35, 1.0)
	_flight = 0.0
	if charge != null:
		charge.global_position = _from
		charge.show()
	if marker != null:
		marker.global_position = _to + Vector3.UP * 0.04
		marker.scale = Vector3(blast_radius, 1.0, blast_radius)
		marker.show()
	return true

func _drop_to_floor(space: PhysicsDirectSpaceState3D, at: Vector3, top: float) -> Vector3:
	_query.from = Vector3(at.x, maxf(at.y, top) + 1.0, at.z)
	_query.to = Vector3(at.x, -20.0, at.z)
	var floor_hit := space.intersect_ray(_query)
	if floor_hit.is_empty():
		return Vector3(at.x, 0.0, at.z)
	return floor_hit["position"]

func _ability_physics(delta: float) -> void:
	if _flight < 0.0:
		return
	_flight += delta
	if _flight >= flight_time:
		_flight = -1.0
		_detonate()

func _detonate() -> void:
	if charge != null:
		charge.hide()
	if marker != null:
		marker.hide()
	if horde != null:
		blast(_to, blast_radius, blast_damage * damage_scale(), blast_knockback)
	var distance := player.camera.global_position.distance_to(_to)
	player.add_shake(clampf(1.0 - distance / 30.0, 0.2, 0.75))
	if _impact_audio.stream != null:
		_impact_audio.play()
	_blast_age = 0.0
	if _shock != null:
		_shock.global_position = _to + Vector3.UP * 0.06
		_shock.scale = Vector3.ONE * 0.5
		_shock.show()
	if _flash != null:
		_flash.global_position = _to
		_flash.scale = Vector3.ONE * 0.3
		_flash.visible = distance > flash_radius + min_view_clearance

func _cancel_effects() -> void:
	_flight = -1.0
	_blast_age = -1.0

func _process(delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	if _flight >= 0.0:
		var t := minf(_flight / flight_time, 1.0)
		if charge != null:
			charge.global_position = _from.lerp(_to, t) + Vector3.UP * (_arc * 4.0 * t * (1.0 - t))
			charge.rotation = Vector3(t * 9.0, t * 5.0, 0.0)
		if marker != null:
			var pulse := 1.0 + sin(t * 26.0) * 0.04
			marker.scale = Vector3(blast_radius * pulse, 1.0, blast_radius * pulse)
	if _blast_age < 0.0:
		return
	_blast_age += delta
	if _blast_age >= blast_duration:
		_blast_age = -1.0
		if _shock != null:
			_shock.hide()
		if _flash != null:
			_flash.hide()
		return
	var p := _blast_age / blast_duration
	if _shock != null:
		var radius := lerpf(0.5, blast_radius, 1.0 - pow(1.0 - p, 3.0))
		_shock.scale = Vector3(radius, maxf(0.05, 1.0 - p), radius)
	if _flash != null and _flash.visible:
		var size := sin(minf(p * 1.8, 1.0) * PI * 0.5) * (1.0 - p * p * 0.8)
		_flash.scale = Vector3.ONE * maxf(size, 0.02) * flash_radius
