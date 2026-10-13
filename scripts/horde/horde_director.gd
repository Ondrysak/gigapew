class_name HordeDirector
extends Node

## Finite arena sets. Procedural worlds opt into routes with `configure_routes`
## after `setup`: ARRIVAL -> ROUTE (waits for `choose_route`) -> TRAVEL (waits
## for the player to physically reach the chosen venue) -> BUILD -> PEAK ->
## CLEANUP (every real survivor) -> RECOVERY (minimum empty breather) -> ROUTE.
## Each routed fight admits bodies only on its venue's authored lanes; completed
## venues are never offered again. Without routes the sets run automatically
## over the whole play area. ARRIVAL/ROUTE/TRAVEL/RECOVERY freeze STYLE.
signal arena_completed
signal phase_changed
signal boss_phase_started(definition: HordeEnemyDefinition)
## ROUTE published its choices, or a successful choice/interruption cleared them.
signal route_choices_changed

@export_range(0.0, 1.0) var behind_bias := 0.6

## Never admitted closer than this to the player, even inside a venue (plus radii).
const MIN_SAFE_DISTANCE := 4.0
## Preferred venue admission distance; nearer lane points only when out of view.
const PREFERRED_DISTANCE := 7.0
## cos(50 deg): lane points inside this view cone count as in sight.
const VIEW_CONE := 0.64
const ROUTE_CHOICES := 3
## Arrival: on the venue floor inside its footprint, or this near one of its entries.
const ARRIVAL_RADIUS := 3.0
## Phases without combat; `recovering` (STYLE freeze) holds during all of them.
const BREAK_PHASES: Array[String] = ["ARRIVAL", "ROUTE", "TRAVEL", "RECOVERY"]

var elapsed := 0.0
var boss_phase := false
## Arrival calm, independent of the music clock.
var grace := 0.0
var encounter_index := 0
var encounter_count := 4
var phase_name := "ARRIVAL"
var recovering := true
var finished := false
var phase_fraction := 0.0
## Non-empty only during ROUTE: {id, name, position, kind, tactic, distance},
## fixed for that ROUTE (deterministic per seed and set).
var route_choices: Array[Dictionary] = []
var current_venue_id: StringName = &""
var current_venue_name := ""
## Nearest street approach of the chosen venue (HUD beacon); INF without one.
var current_venue_position := Vector3.INF
var completed_venues: Array[StringName] = []

var _horde: Horde
var _schedule: SpawnSchedule
var _player: ArenaPlayer
var _remaining := PackedInt32Array()
var _blocked_attempts := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _phase_elapsed := 0.0
var _admission_cooldown := 0.0
var _wave_cursor := 0
var _search_cursor := 0
var _phase_budget := 0
var _venues: Array[Dictionary] = []
var _venue: Dictionary = {}
var _route_seed := 0
var _travel_distance := 0.0
var _lane_cursor := 0

func setup(horde: Horde, schedule: SpawnSchedule, player: ArenaPlayer, seed: int = -1, encounters: int = 4) -> void:
	_horde = horde
	_schedule = schedule
	_player = player
	elapsed = 0.0
	grace = 0.0
	boss_phase = false
	encounter_index = 0
	encounter_count = maxi(1, encounters)
	phase_name = "ARRIVAL"
	recovering = true
	finished = false
	phase_fraction = 0.0
	_phase_elapsed = 0.0
	_admission_cooldown = 0.0
	_wave_cursor = 0
	_search_cursor = 0
	_phase_budget = 0
	_remaining.resize(schedule.waves.size())
	_remaining.fill(0)
	_blocked_attempts.resize(schedule.waves.size())
	_blocked_attempts.fill(0)
	if seed == -1:
		_rng.randomize()
	else:
		_rng.seed = seed
	_route_seed = _rng.randi() if seed == -1 else seed
	_venues.clear()
	_clear_route()
	completed_venues.clear()

## Opts this run into venue routes. Returns false (automatic sets) when the world
## has fewer distinct admissible venues than sets: venues are never revisited.
func configure_routes(world: ProceduralWorld) -> bool:
	_venues.clear()
	_clear_route()
	completed_venues.clear()
	if world == null:
		return false
	var usable: Array[Dictionary] = []
	for venue in world.combat_venues:
		if not (venue.lanes as Array).is_empty():
			usable.append(venue)
	if usable.size() < encounter_count:
		return false
	_venues = usable
	return true

func is_routed() -> bool:
	return not _venues.is_empty()

## Accepted only during ROUTE (also while the tree is paused by a choice modal).
func choose_route(id: StringName) -> bool:
	if phase_name != "ROUTE":
		return false
	for choice in route_choices:
		if choice.id != id:
			continue
		for venue in _venues:
			if venue.id == id:
				_venue = venue
		current_venue_id = id
		current_venue_name = _venue.name
		route_choices.clear()
		_lane_cursor = 0
		_set_phase("TRAVEL")
		_update_target()
		_travel_distance = maxf(0.001, route_distance())
		route_choices_changed.emit()
		return true
	return false

## Chosen venue record from `ProceduralWorld.combat_venues`; empty between fights.
func current_venue() -> Dictionary:
	return _venue

## Player distance to `current_venue_position`; INF without a chosen venue.
func route_distance() -> float:
	if not current_venue_position.is_finite() or not is_instance_valid(_player):
		return INF
	return _player.global_position.distance_to(current_venue_position)

## Authored fixtures may release a boss explicitly. Unsafe placement remains retryable.
func release_boss() -> bool:
	if boss_phase or _schedule == null or _schedule.boss == null:
		return false
	if not is_instance_valid(_player) or not _player.active or not is_instance_valid(_horde):
		return false
	if _spawn_group(_schedule.boss, 1, _schedule.boss_health_multiplier) != 1:
		return false
	boss_phase = true
	boss_phase_started.emit(_schedule.boss)
	return true

func _physics_process(delta: float) -> void:
	if get_tree().paused or finished or _schedule == null or not is_instance_valid(_horde) or not is_instance_valid(_player) or not _player.active:
		return
	elapsed += delta
	if phase_name == "ARRIVAL":
		grace = maxf(0.0, grace - delta)
		if grace <= 0.0:
			_next_set()
		return
	_phase_elapsed += delta
	match phase_name:
		"ROUTE":
			# An external enemy reopens cleanup; the same choices return after it.
			if _horde.alive_count > 0 or _horde.population_count > 0:
				route_choices.clear()
				_set_phase("CLEANUP")
				route_choices_changed.emit()
		"TRAVEL":
			_update_target()
			phase_fraction = clampf(1.0 - route_distance() / _travel_distance, 0.0, 1.0)
			if _arrived():
				_begin_encounter()
		"BUILD", "PEAK":
			_admission_cooldown = maxf(0.0, _admission_cooldown - delta)
			if _admission_cooldown <= 0.0:
				_admit_group()
				_admission_cooldown = maxf(0.1, _schedule.peak_interval if phase_name == "PEAK" else _schedule.build_interval)
			var outstanding := _outstanding()
			phase_fraction = 1.0 - float(outstanding) / maxi(1, _phase_budget)
			var duration := _schedule.peak_duration if phase_name == "PEAK" else _schedule.build_duration
			if outstanding == 0 and _phase_elapsed >= duration:
				if phase_name == "BUILD":
					_begin_admissions(true)
				else:
					_set_phase("CLEANUP")
		"CLEANUP":
			# Neither elapsed time nor depleted allocations erase actual survivors.
			if _horde.alive_count == 0 and _horde.population_count == 0:
				if not _venue.is_empty():
					completed_venues.append(current_venue_id)
					_clear_route()
				if encounter_index == encounter_count:
					finished = true
					_set_phase("CLEAR")
					phase_fraction = 1.0
					arena_completed.emit()
				else:
					_set_phase("RECOVERY")
		"RECOVERY":
			# An explicitly authored external enemy also prevents a free next wave.
			if _horde.alive_count > 0 or _horde.population_count > 0:
				_set_phase("CLEANUP")
				return
			phase_fraction = clampf(_phase_elapsed / maxf(0.001, _schedule.recovery_duration), 0.0, 1.0)
			if _phase_elapsed >= _schedule.recovery_duration:
				_next_set()

func _next_set() -> void:
	if is_routed():
		_enter_route()
	else:
		_begin_encounter()

func _enter_route() -> void:
	route_choices = _pick_choices()
	_set_phase("ROUTE")
	route_choices_changed.emit()

## Up to three uncompleted venues, distinct kinds first, in an order fixed by
## the run seed and set number (re-entering ROUTE offers the same identities).
func _pick_choices() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for venue in _venues:
		if not completed_venues.has(venue.id):
			candidates.append(venue)
	var keys := {}
	for venue in candidates:
		keys[venue.id] = hash([_route_seed, encounter_index, String(venue.id)])
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(keys[a.id]) < int(keys[b.id]) if keys[a.id] != keys[b.id] else String(a.id) < String(b.id))
	var picked: Array[Dictionary] = []
	var kinds := {}
	for distinct in [true, false]:
		for venue in candidates:
			if picked.size() >= ROUTE_CHOICES or picked.has(venue) or (distinct and kinds.has(venue.kind)):
				continue
			picked.append(venue)
			kinds[venue.kind] = true
	var choices: Array[Dictionary] = []
	for venue in picked:
		var position := _nearest_approach(venue)
		var distance := _player.global_position.distance_to(position) if is_instance_valid(_player) else INF
		choices.append({"id": venue.id, "name": venue.name, "position": position, "kind": venue.kind, "tactic": venue.tactic, "distance": distance})
	return choices

func _nearest_approach(venue: Dictionary) -> Vector3:
	var best: Vector3 = venue.position
	if not is_instance_valid(_player):
		return best
	var from := _player.global_position
	var nearest := INF
	for point: Vector3 in venue.approaches:
		if point.distance_squared_to(from) < nearest:
			nearest = point.distance_squared_to(from)
			best = point
	return best

func _update_target() -> void:
	if not _venue.is_empty():
		current_venue_position = _nearest_approach(_venue)

func _arrived() -> bool:
	var at := _player.global_position
	var floor_y := float(_venue.floor_y)
	if absf(at.y - 0.9 - floor_y) > 1.0:
		return false
	var xz := Vector2(at.x, at.z)
	if (_venue.bounds as Rect2).grow(0.5).has_point(xz):
		return true
	for entry: Vector3 in _venue.entries:
		if Vector2(entry.x, entry.z).distance_to(xz) <= ARRIVAL_RADIUS:
			return true
	return false

func _clear_route() -> void:
	_venue = {}
	route_choices.clear()
	current_venue_id = &""
	current_venue_name = ""
	current_venue_position = Vector3.INF

func _begin_encounter() -> void:
	encounter_index += 1
	_begin_admissions(false)

func _begin_admissions(peak: bool) -> void:
	_remaining.fill(0)
	_blocked_attempts.fill(0)
	_phase_budget = 0
	for index in _schedule.waves.size():
		var wave := _schedule.waves[index]
		if wave == null or wave.enemy == null or wave.enemy.is_boss or wave.peak != peak:
			continue
		if encounter_index < wave.encounter_start or encounter_index > wave.encounter_end:
			continue
		var count := maxi(0, wave.count + wave.count_growth * (encounter_index - wave.encounter_start))
		_remaining[index] = count
		_phase_budget += count
	_admission_cooldown = 0.0
	_set_phase("PEAK" if peak else "BUILD")

func _set_phase(next: String) -> void:
	phase_name = next
	recovering = next in BREAK_PHASES
	_phase_elapsed = 0.0
	phase_fraction = 0.0
	phase_changed.emit()

func _outstanding() -> int:
	var total := 0
	for remaining in _remaining:
		total += remaining
	return total

func _admit_group() -> void:
	var available := maxi(0, _schedule.max_alive - _horde.population_count)
	if available == 0:
		return
	# Rotate through allocations; one blocked specialist cannot starve the crowd.
	for offset in _remaining.size():
		var index := (_wave_cursor + offset) % _remaining.size()
		if _remaining[index] <= 0:
			continue
		var wave := _schedule.waves[index]
		var count := mini(available, mini(_remaining[index], maxi(1, wave.group_size)))
		var admitted := _spawn_group(wave.enemy, count, wave.health_multiplier)
		if admitted == 0 and count > 1:
			# A narrow approach can accept individuals without an impossible cluster.
			admitted = _spawn_group(wave.enemy, 1, wave.health_multiplier)
		if admitted == 0:
			_blocked_attempts[index] += 1
			if _blocked_attempts[index] >= 8:
				# Preserve the allocated fight, not impossible geometry: replace a
				# persistently unplaceable body with an authored smaller crowd role.
				var substitute := _smaller_enemy(wave.enemy)
				if substitute != null:
					admitted = _spawn_group(substitute, 1, wave.health_multiplier)
		if admitted > 0:
			_remaining[index] -= admitted
			_blocked_attempts[index] = 0
			_wave_cursor = (index + 1) % _remaining.size()
			return
	_wave_cursor = (_wave_cursor + 1) % maxi(1, _remaining.size())

func _smaller_enemy(original: HordeEnemyDefinition) -> HordeEnemyDefinition:
	var smallest: HordeEnemyDefinition
	for wave in _schedule.waves:
		if wave == null or wave.enemy == null or wave.enemy.is_boss:
			continue
		if encounter_index < wave.encounter_start or encounter_index > wave.encounter_end:
			continue
		if wave.enemy.radius >= original.radius:
			continue
		if smallest == null or wave.enemy.radius < smallest.radius:
			smallest = wave.enemy
	return smallest

## Returns exact admitted bodies. Failed or partial groups never consume phantom budget.
func _spawn_group(definition: HordeEnemyDefinition, count: int, health_multiplier: float) -> int:
	if definition == null or count <= 0:
		return 0
	var spread := sqrt(float(count)) * definition.radius * 2.2 if count > 1 else 0.0
	var center := _pick_point(definition.radius + spread) if _venue.is_empty() else _pick_lane_point(lane_role(definition), definition.radius + spread)
	if not center.is_finite():
		return 0
	var admitted := 0
	for member in count:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * spread
		var point := center + offset
		if _horde.is_blocked(point, definition.radius) or not _horde.is_reachable(point) \
				or absf(_horde.ground_height(point) - _horde.ground_height(center)) > Horde.LEVEL_GAP:
			continue
		if _horde.spawn(definition, point, health_multiplier) >= 0:
			admitted += 1
	return admitted

## Venue lane role of an enemy: crowd, fast, heavy, ranged or support.
static func lane_role(definition: HordeEnemyDefinition) -> StringName:
	match definition.behavior:
		HordeEnemyDefinition.Behavior.RANGED, HordeEnemyDefinition.Behavior.THROWER:
			return &"ranged"
		HordeEnemyDefinition.Behavior.HYPE:
			return &"support"
		HordeEnemyDefinition.Behavior.RUNNER:
			return &"fast"
		HordeEnemyDefinition.Behavior.CHARGER, HordeEnemyDefinition.Behavior.BOUNCER, HordeEnemyDefinition.Behavior.CARRIER:
			return &"heavy"
	return &"heavy" if definition.radius >= 0.7 else &"crowd"

## Only the chosen venue's authored lanes; groups rotate between the lanes that
## accept their role (pincers through both doors). Preferred: far and out of
## sight; then far; then the minimum safe ring out of sight; otherwise retry.
func _pick_lane_point(role: StringName, radius: float) -> Vector2:
	var lanes: Array = _venue.lanes
	var accepted: Array[int] = []
	for index in lanes.size():
		if (lanes[index].roles as Array).has(role):
			accepted.append(index)
	if accepted.is_empty():
		for index in lanes.size():
			accepted.append(index)
	var player := Vector2(_player.global_position.x, _player.global_position.z)
	var look := -_player.global_basis.z
	var forward := Vector2(look.x, look.z).normalized()
	for attempt in 3:
		var distance := (MIN_SAFE_DISTANCE if attempt == 2 else PREFERRED_DISTANCE) + radius + Horde.PLAYER_RADIUS
		var hidden := attempt != 1
		for offset in accepted.size():
			var slot := (_lane_cursor + offset) % accepted.size()
			var points: PackedVector3Array = lanes[accepted[slot]].points
			var start := _rng.randi() % points.size()
			for step in points.size():
				var point := points[(start + step) % points.size()]
				var xz := Vector2(point.x, point.z)
				var away := xz - player
				if away.length() < distance or (hidden and away.normalized().dot(forward) > VIEW_CONE):
					continue
				if _horde.is_blocked(xz, radius) or not _horde.is_reachable(xz) or absf(_horde.ground_height(xz) - point.y) > 0.6:
					continue
				_lane_cursor = (slot + 1) % accepted.size()
				return xz
	return Vector2.INF

func _pick_point(radius: float) -> Vector2:
	var player := Vector2(_player.global_position.x, _player.global_position.z)
	var forward := -_player.global_basis.z
	var facing := atan2(forward.z, forward.x)
	var minimum := _horde.play_area.position + Vector2.ONE * (radius + 1.0)
	var maximum := _horde.play_area.end - Vector2.ONE * (radius + 1.0)
	if minimum.x > maximum.x or minimum.y > maximum.y:
		return Vector2.INF
	# Account for cluster spread too: even its nearest member stays safely away.
	var safe_distance := 8.0 + radius + Horde.PLAYER_RADIUS
	var feet := _player.global_position.y - 0.9
	for attempt in 24:
		var angle := _rng.randf() * TAU
		if _rng.randf() < behind_bias:
			angle = facing + PI + _rng.randf_range(-1.9, 1.9)
		var ring_min := maxf(safe_distance, _schedule.spawn_distance_min)
		var distance := _rng.randf_range(ring_min, maxf(ring_min, _schedule.spawn_distance_max))
		var point := (player + Vector2.from_angle(angle) * distance).clamp(minimum, maximum)
		if _safe_point(point, player, radius, safe_distance, feet):
			return point
	# The preferred ring may lie entirely inside venue walls. Exhaust a bounded
	# floor grid instead of discarding budget or teleporting through those walls.
	var columns := maxi(1, ceili((maximum.x - minimum.x) / 3.0) + 1)
	var rows := maxi(1, ceili((maximum.y - minimum.y) / 3.0) + 1)
	var cells := columns * rows
	for offset in cells:
		var cell := (_search_cursor + offset) % cells
		var x := lerpf(minimum.x, maximum.x, float(cell % columns) / maxi(1, columns - 1))
		var z := lerpf(minimum.y, maximum.y, float(cell / columns) / maxi(1, rows - 1))
		var point := Vector2(x, z)
		if _safe_point(point, player, radius, safe_distance, feet):
			_search_cursor = (cell + 1) % cells
			return point
	_search_cursor = (_search_cursor + 1) % cells
	return Vector2.INF

func _safe_point(point: Vector2, player: Vector2, radius: float, distance: float, feet: float) -> bool:
	return point.distance_to(player) >= distance \
		and not _horde.is_blocked(point, radius) and _horde.is_reachable(point) \
		and absf(_horde.ground_height(point) - feet) <= Horde.LEVEL_GAP
