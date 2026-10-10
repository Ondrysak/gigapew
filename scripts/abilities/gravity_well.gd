class_name GravityWell
extends ActiveAbility

## Aim a persistent singularity at a nearby lane. Each pulse interrupts attacks,
## slows movement and applies an inward impulse through the Horde damage API.
@export var duration := 5.0
@export var radius := 7.0
@export var max_range := 16.0
@export var tick_interval := 0.25
@export var tick_damage := 5.0
@export var pull_strength := 10.0
@export var slow_factor := 0.35
@export var interrupt_duration := 0.12
@export var field: Node3D
@export var boundary: Node3D
@export var vortex: Node3D
@export var core: Node3D
@export_group("Collapse combo")
## Pulse Barrier near an active well detonates it: base damage, scaled up by
## each held enemy (+10%, capped at +150%), flinging the pack outward.
@export var collapse_damage := 70.0
@export var collapse_knockback := 28.0
@export var collapse_reach := 6.0
const COLLAPSE_TIME := 0.35

var _remaining := 0.0
var _tick := 0.0
var _center := Vector3.ZERO
var _query: PhysicsRayQueryParameters3D
var _targets := PackedInt32Array()
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
var _collapse_age := -1.0

func _ready() -> void:
	super()
	_targets.resize(512)
	_hits.resize(1)
	_distances.resize(1)
	if field != null:
		field.top_level = true
		field.hide()

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	super(p_player, p_horde, p_run_state)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [p_player.get_rid()])

func is_ready() -> bool:
	return super() and _remaining <= 0.0 and _collapse_age < 0.0

func is_active() -> bool:
	return _remaining > 0.0

## True when a blast of `blast_radius` at `at` reaches into the field.
func overlaps(at: Vector3, blast_radius: float) -> bool:
	return _remaining > 0.0 and Vector2(at.x - _center.x, at.z - _center.z).length() <= radius + blast_radius

func in_collapse_reach(at: Vector3) -> bool:
	return _remaining > 0.0 and Vector2(at.x - _center.x, at.z - _center.z).length() <= radius + collapse_reach

## Ends the field in one burst whose power grows with the pack it holds.
func collapse() -> void:
	if _remaining <= 0.0 or horde == null:
		return
	var held := horde.query_radius(_center, radius, _targets)
	var amount := collapse_damage * damage_scale() * (1.0 + minf(1.5, held * 0.1))
	horde.damage_radius(_center, radius + 1.5, amount, collapse_knockback)
	_remaining = 0.0
	_collapse_age = 0.0
	player.add_shake(0.35)

func _activate() -> bool:
	if horde == null or field == null:
		return false
	var origin := player.camera.global_position
	var direction := -player.camera.global_basis.z
	_query.from = origin
	_query.to = origin + direction * max_range
	var space := player.get_world_3d().direct_space_state
	var wall := space.intersect_ray(_query)
	var reach := max_range
	var target := _query.to
	if not wall.is_empty():
		target = wall["position"]
		reach = origin.distance_to(target)
	if horde.raycast(origin, direction, reach, 1, _hits, _distances) > 0:
		target = horde.enemy_position(_hits[0])
	var area := horde.play_area
	target.x = clampf(target.x, area.position.x, area.end.x)
	target.z = clampf(target.z, area.position.y, area.end.y)
	_query.from = Vector3(target.x, maxf(origin.y, target.y) + 1.0, target.z)
	_query.to = Vector3(target.x, -20.0, target.z)
	var floor_hit := space.intersect_ray(_query)
	if floor_hit.is_empty():
		return false
	_center = floor_hit["position"]
	field.global_position = _center + Vector3.UP * 0.08
	field.show()
	_remaining = duration * duration_scale()
	_tick = 0.0
	player.add_shake(0.16)
	return true

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_finish()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick += tick_interval
	var count := horde.query_radius(_center, radius, _targets)
	var amount := tick_damage * damage_scale()
	for n in count:
		var index := _targets[n]
		var inward := _center - horde.enemy_position(index)
		inward.y = 0.0
		var distance := inward.length()
		var impulse := inward / maxf(distance, 0.001) * minf(pull_strength, distance / tick_interval)
		horde.slow(index, slow_factor, tick_interval * 1.25)
		horde.stun(index, interrupt_duration * duration_scale())
		horde.damage_direct(index, amount, _center, impulse)

func _process(delta: float) -> void:
	if _collapse_age >= 0.0:
		_animate_collapse(delta)
		return
	if not effects_allowed() or get_tree().paused or _remaining <= 0.0:
		return
	var fade := minf(1.0, _remaining / 0.4)
	var elapsed := duration * duration_scale() - _remaining
	var grow := minf(1.0, elapsed / 0.25)
	if boundary != null:
		boundary.scale = Vector3(radius * grow * fade, 1.0, radius * grow * fade)
	if vortex != null:
		vortex.rotation.y = fmod(vortex.rotation.y - delta * 3.5, TAU)
		var sweep := 1.0 - fmod(elapsed, tick_interval) / tick_interval
		vortex.scale = Vector3.ONE * radius * (0.2 + sweep * 0.65) * fade
	if core != null:
		core.rotation.y = fmod(core.rotation.y + delta * 4.0, TAU)
		core.scale = Vector3.ONE * (1.0 + sin(effect_time() * 10.0) * 0.12) * fade

## The field flares outward and the core bursts before the field vanishes.
func _animate_collapse(delta: float) -> void:
	if get_tree().paused:
		return
	_collapse_age += delta
	var t := minf(1.0, _collapse_age / COLLAPSE_TIME)
	if boundary != null:
		boundary.scale = Vector3(radius * (1.0 + t * 0.8), 1.0, radius * (1.0 + t * 0.8))
	if vortex != null:
		vortex.scale = Vector3.ONE * radius * (1.0 - t) * 0.6
	if core != null:
		core.scale = Vector3.ONE * (1.0 + t * 3.0) * (1.0 - t)
	if t >= 1.0:
		_finish()

func _finish() -> void:
	_remaining = 0.0
	_collapse_age = -1.0
	if field != null:
		field.hide()

func _cancel_effects() -> void:
	_finish()
