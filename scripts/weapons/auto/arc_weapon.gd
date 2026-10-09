class_name ArcWeapon
extends AutoWeapon

## Chain lightning: player -> nearest enemy -> next nearest unhit enemy...
## Overclocked, a side bolt forks off every struck enemy for extra hops.

## Hidden unit-length beam along -Z; one per jagged bolt piece.
@export var segment_template: Node3D
## Hidden unit-size spark popped on each struck enemy.
@export var spark_template: Node3D
@export var first_range := 11.0
@export var jump_range := 6.0
@export var base_jumps := 3
@export var jumps_per_level := 1
@export var max_jumps := 16
@export var knockback := 1.5
## Sub-segments per link, and their random sideways offset.
@export var jag_pieces := 4
@export var jag_amount := 0.35
@export var bolt_duration := 0.22
@export var jitter_interval := 0.04
@export var origin_height := 0.2
@export var spark_size := 0.5

@export_group("Overclock")
## Extra hops each fork makes from its struck enemy.
@export var fork_hops := 2
@export var fork_damage_scale := 0.7
@export var fork_width := 0.65

var _segments: Array[Node3D] = []
var _sparks: AutoFxPool
var _link_from := PackedVector3Array()
var _link_to := PackedVector3Array()
var _link_width := PackedFloat32Array()
var _chain := PackedVector3Array()
var _struck := PackedInt32Array()
var _hits := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _jumps := 3
var _timer := 0.0
var _bolt_time := 0.0
var _jitter_time := 0.0

func _ready() -> void:
	_hits.resize(256)

func _refresh() -> void:
	_jumps = clampi(base_jumps + jumps_per_level * (level - 1) + extra_projectiles(), 1, max_jumps)
	var links := _jumps * (1 + (fork_hops if overclocked else 0))
	_grow_pool(segment_template, _segments, links * jag_pieces)
	if _sparks == null:
		_sparks = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
	_sparks.reserve(links)
	if _timer <= 0.0:
		_timer = cooldown_time() * 0.5

func _tick(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	var origin := player.global_position + Vector3.UP * origin_height
	var current := horde.nearest(origin, first_range)
	if current < 0:
		_timer = 0.2
		return
	_timer += cooldown_time()
	_link_from.clear()
	_link_to.clear()
	_link_width.clear()
	_chain.clear()
	_struck.clear()
	var hop_range := jump_range * area_scale()
	var amount := damage_amount()
	var previous := origin
	while current >= 0 and _struck.size() < _jumps:
		previous = _strike(current, previous, amount, 1.0)
		_chain.append(previous)
		current = _next_target(previous, hop_range)
	if overclocked:
		for link in range(_chain.size()):
			var from := _chain[link]
			for _hop in range(fork_hops):
				var fork := _next_target(from, hop_range)
				if fork < 0:
					break
				from = _strike(fork, from, amount * fork_damage_scale, fork_width)
	_bolt_time = bolt_duration
	_jitter_time = 0.0
	_layout()
	play_cue()

# Damages one enemy, records the bolt link to it and returns its position.
func _strike(index: int, from: Vector3, amount: float, width: float) -> Vector3:
	var at := horde.enemy_position(index)
	var push := Vector3(at.x - from.x, 0.0, at.z - from.z).normalized()
	_struck.append(index)
	_link_from.append(from)
	_link_to.append(at)
	_link_width.append(width)
	horde.damage_direct(index, amount, from, push * knockback)
	_sparks.spawn(at, spark_size * width, bolt_duration * 1.4, _rng.randf() * TAU)
	return at

func _next_target(from: Vector3, radius: float) -> int:
	var found := horde.query_radius(from, radius, _hits)
	var best := -1
	var best_distance := INF
	for slot in range(found):
		var candidate := _hits[slot]
		if not horde.is_alive(candidate) or _struck.has(candidate):
			continue
		var distance := horde.enemy_position(candidate).distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best

# Re-randomizes the jagged bolt so it crackles while visible; it also thins
# out as it fades.
func _layout() -> void:
	var used := 0
	var fade := clampf(_bolt_time / bolt_duration, 0.0, 1.0)
	var thickness := lerpf(0.35, 1.0, fade)
	for link in range(_link_from.size()):
		var from := _link_from[link]
		var to := _link_to[link]
		var direction := (to - from).normalized()
		var side := direction.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var lift := side.cross(direction)
		var last := from
		var width := _link_width[link] * thickness
		for piece in range(1, jag_pieces + 1):
			var next := to
			if piece < jag_pieces:
				next = from.lerp(to, float(piece) / float(jag_pieces))
				next += side * _rng.randf_range(-jag_amount, jag_amount) + lift * _rng.randf_range(-jag_amount, jag_amount)
			place_beam(_segments[used], last, next, width)
			used += 1
			last = next
	for index in range(used, _segments.size()):
		_segments[index].hide()

func _process(delta: float) -> void:
	if _sparks != null:
		_sparks.update(delta)
	if _bolt_time <= 0.0:
		return
	_bolt_time -= delta
	if _bolt_time <= 0.0:
		for segment in _segments:
			segment.hide()
		return
	_jitter_time -= delta
	if _jitter_time <= 0.0:
		_jitter_time = jitter_interval
		_layout()
