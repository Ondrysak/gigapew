class_name ArcWeapon
extends AutoWeapon

## Chain lightning: player -> nearest enemy -> next nearest unhit enemy...

## Hidden unit-length beam along -Z; one per jagged bolt piece.
@export var segment_template: Node3D
## Hidden spark shown on each struck enemy.
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
@export var bolt_duration := 0.18
@export var jitter_interval := 0.04
@export var origin_height := 0.2

var _segments: Array[Node3D] = []
var _sparks: Array[Node3D] = []
var _points := PackedVector3Array()
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
	_grow_pool(segment_template, _segments, _jumps * jag_pieces)
	_grow_pool(spark_template, _sparks, _jumps)
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
	_points.clear()
	_struck.clear()
	_points.append(origin)
	var hop_range := jump_range * area_scale()
	var amount := damage_amount()
	while current >= 0 and _struck.size() < _jumps:
		var at := horde.enemy_position(current)
		var previous := _points[_points.size() - 1]
		var push := Vector3(at.x - previous.x, 0.0, at.z - previous.z).normalized()
		_struck.append(current)
		_points.append(at)
		horde.damage(current, amount, push * knockback)
		current = _next_target(at, hop_range)
	_bolt_time = bolt_duration
	_jitter_time = 0.0
	_layout()

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

# Re-randomizes the jagged bolt so it crackles while visible.
func _layout() -> void:
	var used := 0
	for link in range(_points.size() - 1):
		var from := _points[link]
		var to := _points[link + 1]
		var direction := (to - from).normalized()
		var side := direction.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var lift := side.cross(direction)
		var last := from
		for piece in range(1, jag_pieces + 1):
			var next := to
			if piece < jag_pieces:
				next = from.lerp(to, float(piece) / float(jag_pieces))
				next += side * _rng.randf_range(-jag_amount, jag_amount) + lift * _rng.randf_range(-jag_amount, jag_amount)
			place_beam(_segments[used], last, next)
			used += 1
			last = next
		var spark := _sparks[link]
		spark.global_position = to
		spark.show()
	for index in range(used, _segments.size()):
		_segments[index].hide()
	for index in range(_points.size() - 1, _sparks.size()):
		_sparks[index].hide()

func _process(delta: float) -> void:
	if _bolt_time <= 0.0:
		return
	_bolt_time -= delta
	if _bolt_time <= 0.0:
		for segment in _segments:
			segment.hide()
		for spark in _sparks:
			spark.hide()
		return
	_jitter_time -= delta
	if _jitter_time <= 0.0:
		_jitter_time = jitter_interval
		_layout()
