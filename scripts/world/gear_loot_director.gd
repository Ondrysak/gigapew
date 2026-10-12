class_name GearLootDirector
extends Node3D

signal reward_ready(offers: Array[GearDefinition], title: String)
signal stash_looted(stash: GearStash)

const LOOT_SALT := 0x47454152
const APPROACH_DISTANCE := 6.0
const SPAWN_CLEARANCE := 8.0
const SITE_RADIUS := 1.1
const WALK_RADIUS := 0.42

## Public encounter state for the lab; no indices without their life generation.
var stashes: Array[GearStash] = []
var active := false
var initialized := false
var elite_site := Vector3.ZERO
var elite_definition: HordeEnemyDefinition
var elite_slot := -1
var elite_generation := -1
var elite_spawned := false
var elite_defeated := false
var elite_drop: GearStash

var _world: ProceduralWorld
var _horde: Horde
var _player: ArenaPlayer
var _state: RunState
var _rng := RandomNumberGenerator.new()
var _regular_definitions: Array[HordeEnemyDefinition] = []
var _floor_points: Array[Vector3] = []
var _encounters: Array[Dictionary] = []
var _reservation := 0
var _stage_index := 0
var _placement_delay := 8
var _elite_marker: Label3D
var _target: GearStash
var _space: PhysicsDirectSpaceState3D
var _floor_query := PhysicsRayQueryParameters3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()
var _clearance_query := PhysicsShapeQueryParameters3D.new()
var _clearance_shape := BoxShape3D.new()

func setup(world: ProceduralWorld, horde: Horde, player: ArenaPlayer, state: RunState, seed_value: int, stage_index: int) -> void:
	cancel()
	_world = world
	_horde = horde
	_player = player
	_state = state
	_stage_index = maxi(0, stage_index)
	_rng.seed = seed_value ^ LOOT_SALT ^ (stage_index * 104729)
	_regular_definitions.clear()
	for definition in horde.registered_definitions():
		if definition != null and not definition.is_boss and definition != elite_definition:
			_regular_definitions.append(definition)
	assert(not _regular_definitions.is_empty(), "Gear encounters require the stage's registered ordinary enemies.")
	var base := _regular_definitions[0]
	for definition in _regular_definitions:
		if definition.max_health > base.max_health:
			base = definition
	elite_definition = base.duplicate() as HordeEnemyDefinition
	elite_definition.display_name = "Podržtaškův výběrčí"
	elite_definition.max_health = base.max_health * 3.0
	elite_definition.is_boss = false
	horde.register_definition(elite_definition)
	horde.enemy_killed.connect(_on_enemy_killed)
	player.died.connect(cancel)
	_reservation = horde.reserve_slots(_quest_guard_count() + 3)
	_floor_query.collision_mask = 1
	_floor_query.exclude = [player.get_rid()]
	_sight_query.collision_mask = 1
	_sight_query.exclude = [player.get_rid()]
	_clearance_query.collision_mask = 1
	_clearance_query.exclude = [player.get_rid()]
	_clearance_query.shape = _clearance_shape
	_placement_delay = 8
	active = true
	initialized = false
	elite_spawned = false
	elite_defeated = false
	elite_slot = -1
	elite_generation = -1
	set_physics_process(true)

func cancel() -> void:
	active = false
	_target = null
	set_physics_process(false)
	if is_instance_valid(_horde):
		if _reservation > 0:
			_horde.release_reserved(_reservation)
		if _horde.enemy_killed.is_connected(_on_enemy_killed):
			_horde.enemy_killed.disconnect(_on_enemy_killed)
	_reservation = 0
	if is_instance_valid(_player) and _player.died.is_connected(cancel):
		_player.died.disconnect(cancel)
	for stash in stashes:
		if is_instance_valid(stash):
			stash.queue_free()
	stashes.clear()
	if is_instance_valid(_elite_marker):
		_elite_marker.queue_free()
	_elite_marker = null
	elite_drop = null
	_floor_points.clear()
	_encounters.clear()
	initialized = false

func _exit_tree() -> void:
	cancel()

func _physics_process(delta: float) -> void:
	if not _live():
		_target = null
		return
	if not initialized:
		_placement_delay -= 1
		if _placement_delay > 0 or _world.is_physics_processing():
			return
		_space = get_world_3d().direct_space_state
		_build_sites()
		return
	_space = get_world_3d().direct_space_state
	_update_encounters()
	_update_elite_marker()
	_target = target_stash()
	if _target == null or not _input_allowed():
		return
	if _target.source == GearStash.Source.ELITE_DROP:
		if Input.is_action_just_pressed(&"interact"):
			claim_stash(_target)
	elif Input.is_action_pressed(&"interact") and _target.advance_pry(delta):
		claim_stash(_target)

func _live() -> bool:
	return active and is_instance_valid(_world) and is_instance_valid(_horde) \
			and is_instance_valid(_player) and _player.active and _player.health > 0 \
			and is_inside_tree() and not get_tree().paused

func _input_allowed() -> bool:
	return _live() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## Nearest aimed, visible, unclaimed prop. Aim is measured against its small body,
## not its floating label; the wall ray is never bypassed for a nearby cache.
func target_stash() -> GearStash:
	if not initialized or not _input_allowed() or not is_instance_valid(_player.camera):
		return null
	var camera := _player.camera
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var best: GearStash = null
	var best_distance := INF
	for stash in stashes:
		if not is_instance_valid(stash) or stash.claimed:
			continue
		var distance := _player.global_position.distance_to(stash.aim_point())
		if distance > GearStash.REACH or distance >= best_distance:
			continue
		var toward := stash.aim_point() - from
		var along := toward.dot(forward)
		if along <= 0.0 or (toward - forward * along).length_squared() > 0.55 * 0.55:
			continue
		_sight_query.from = from
		_sight_query.to = stash.aim_point()
		if not get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty():
			continue
		best = stash
		best_distance = distance
	return best

## Explicit claim entry point also used by the lab. Guards never gate it.
## Offers become immutable at this reveal; declining the UI cannot unclaim loot.
func claim_stash(stash: GearStash) -> bool:
	if not _input_allowed() or not is_instance_valid(stash) or stash != target_stash():
		return false
	if stash.source != GearStash.Source.ELITE_DROP and stash.pry_progress < GearStash.PRY_SECONDS:
		return false
	var offers := GearCatalog.roll(_rng, stash.offer_count, _state.gear, stash.source != GearStash.Source.ELITE_DROP)
	if not stash.consume(offers):
		return false
	_target = null
	reward_ready.emit(stash.offers.duplicate(), stash.title)
	stash_looted.emit(stash)
	return true

func interaction_text() -> String:
	var target := target_stash()
	if target == null:
		return ""
	if target.source == GearStash.Source.ELITE_DROP:
		return "%s\n[E] Vzít výbavu" % target.title
	return "%s\nDrž [E] 2 s · vypáčit %d %%" % [target.title, roundi(target.pry_progress / GearStash.PRY_SECONDS * 100.0)]

func status_text() -> String:
	if not active or not initialized or not is_instance_valid(_player):
		return ""
	var quest := stashes[0]
	var quest_status := "vybráno" if quest.claimed else "%d m" % _distance(quest.global_position)
	var caches_done := 0
	var nearest := INF
	for stash in stashes:
		if stash.source != GearStash.Source.CACHE:
			continue
		if stash.claimed:
			caches_done += 1
		else:
			nearest = minf(nearest, _player.global_position.distance_to(stash.global_position))
	var cache_status := "hotovo" if caches_done == 2 else "%d m" % roundi(nearest)
	var elite_status := "%d m" % _distance(elite_site)
	if elite_defeated:
		elite_status = "vybráno" if is_instance_valid(elite_drop) and elite_drop.claimed else "výbava %d m" % _distance(elite_drop.global_position)
	elif elite_spawned and _elite_life_valid():
		elite_status = "%d m" % _distance(_horde.enemy_position(elite_slot))
	return "Hlídaná skrýš: %s\nKeše %d/2: %s\nElita (volitelně): %s" % [quest_status, caches_done, cache_status, elite_status]

func _distance(at: Vector3) -> int:
	return roundi(_player.global_position.distance_to(at))

func _quest_guard_count() -> int:
	return 4 + mini(_stage_index, 2)

func _build_sites() -> void:
	# Reuse the horde's connected navigation layer: street, stairs and underground.
	# Carved cells alone are not proof that a reward is reachable through fixtures.
	var spawn := _world.get_node("PlayerSpawn") as Node3D
	var walkable := _world.layout_walkable if not _world.layout_walkable.is_empty() else _world.layout_open
	for z in _world.layout_height:
		for x in _world.layout_width:
			var key := z * _world.layout_width + x
			if walkable[key] != 1:
				continue
			var point := _cell_position(Vector2i(x, z))
			if _horde.is_reachable(Vector2(point.x, point.z)) \
					and _floor_clear(point, SITE_RADIUS) and point.distance_to(spawn.global_position) >= SPAWN_CLEARANCE:
				_floor_points.append(point)
	assert(_floor_points.size() >= 4, "Generated sector must have four reachable clear loot sites.")
	_shuffle_points()
	# Keep four sources, but give the new floor a stash whenever a safe site fits.
	for index in _floor_points.size():
		if _floor_points[index].y < _world.global_position.y - 2.0:
			var underground := _floor_points[index]
			_floor_points[index] = _floor_points[0]
			_floor_points[0] = underground
			break
	var chosen: Array[Vector3] = []
	for spacing: float in [10.0, 6.0, 2.4, 1.8]:
		for point in _floor_points:
			var clear := true
			for other in chosen:
				if point.distance_to(other) < spacing:
					clear = false
					break
			if clear:
				chosen.append(point)
			if chosen.size() == 4:
				break
		if chosen.size() == 4:
			break
	assert(chosen.size() == 4, "Four separate gear sources must fit on clear floor.")
	var quest := _create_stash(GearStash.Source.QUEST, "PODRŽTAŠKOVA SKRÝŠ", chosen[0])
	_create_stash(GearStash.Source.CACHE, "KEŠULKY BUDOU", chosen[1])
	_create_stash(GearStash.Source.CACHE, "TĚŽKÝ DNO", chosen[2])
	elite_site = chosen[3]
	_add_encounter(chosen[0], _quest_guard_count(), quest, false)
	_add_encounter(elite_site, 3, null, true)
	_elite_marker = Label3D.new()
	_elite_marker.name = "EliteMarker"
	_elite_marker.text = "VOLITELNĚ · PODRŽTAŠKŮV VÝBĚRČÍ"
	_elite_marker.font_size = 30
	_elite_marker.pixel_size = 0.003
	_elite_marker.modulate = Color(1.0, 0.42, 0.23)
	_elite_marker.outline_size = 6
	_elite_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_elite_marker)
	_elite_marker.global_position = elite_site + Vector3.UP * 2.4
	initialized = true

func _cell_position(cell: Vector2i) -> Vector3:
	var at := _world.layout_origin + (Vector2(cell) + Vector2.ONE * 0.5) * ProceduralWorld.CELL_SIZE
	var point := _world.to_global(Vector3(at.x, 0.0, at.y))
	point.y = _horde.ground_height(Vector2(point.x, point.z))
	return point

func _floor_clear(point: Vector3, radius: float) -> bool:
	var xz := Vector2(point.x, point.z)
	var ground := _horde.ground_height(xz)
	if _horde.is_blocked(xz, radius) or not is_finite(ground) or absf(point.y - ground) > 0.08:
		return false
	var local := _world.to_local(point)
	# Outdoor set-piece reservations stay intact. Indoor sites are reserved by the
	# building kit itself, so use actual clearance rather than the street predicate.
	if not _horde.is_roofed(xz) and ground >= _world.global_position.y - 0.08 \
			and not _world._area_clear(Rect2(Vector2(local.x, local.z) - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), 0.0):
		return false
	_clearance_shape.size = Vector3(radius * 2.0, 2.2, radius * 2.0)
	_clearance_query.transform = Transform3D(Basis(), point + Vector3.UP * 1.2)
	if not _space.intersect_shape(_clearance_query, 1).is_empty():
		return false
	_floor_query.from = point + Vector3.UP * 0.3
	_floor_query.to = point - Vector3.UP * 0.3
	var hit := _space.intersect_ray(_floor_query)
	return not hit.is_empty() and (hit["normal"] as Vector3).dot(Vector3.UP) > 0.99 \
			and absf((hit["position"] as Vector3).y - point.y) < 0.05

func _shuffle_points() -> void:
	for index in range(_floor_points.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var swap := _floor_points[index]
		_floor_points[index] = _floor_points[other]
		_floor_points[other] = swap

func _create_stash(kind: GearStash.Source, title: String, at: Vector3) -> GearStash:
	var stash := GearStash.new()
	stash.name = "GearStash%d" % stashes.size()
	stash.configure(kind, title)
	add_child(stash)
	stash.global_position = at
	stashes.append(stash)
	return stash

func _add_encounter(at: Vector3, count: int, stash: GearStash, elite: bool) -> void:
	var pack: Array[Dictionary] = []
	var points: Array[Vector3] = _floor_points.duplicate()
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(at) < b.distance_squared_to(at))
	for index in count:
		var definition := elite_definition if elite and index == 0 else _regular_definitions[_rng.randi_range(0, _regular_definitions.size() - 1)]
		var point := at
		for candidate in points:
			if candidate.distance_to(at) >= 1.8 and absf(candidate.y - at.y) <= Horde.LEVEL_GAP \
					and not _horde.is_blocked(Vector2(candidate.x, candidate.z), definition.radius):
				point = candidate
				points.erase(candidate)
				break
		pack.append({"definition": definition, "position": point, "elite": elite and index == 0})
	_encounters.append({"position": at, "stash": stash, "started": false, "pending": pack})

func _update_encounters() -> void:
	for encounter in _encounters:
		if not encounter.started:
			if _player.global_position.distance_to(encounter.position) > APPROACH_DISTANCE:
				continue
			encounter.started = true
			var stash := encounter.stash as GearStash
			if is_instance_valid(stash):
				stash.guards_started = true
		var pending: Array = encounter.pending
		while not pending.is_empty():
			if _reservation == 0:
				_reservation = _horde.reserve_slots(pending.size())
				if _reservation == 0:
					break
			var guard: Dictionary = pending[0]
			var at: Vector3 = guard.position
			var slot := _horde.spawn_reserved(guard.definition, Vector2(at.x, at.z))
			if slot < 0:
				break
			_horde.release_reserved(1)
			_reservation -= 1
			pending.pop_front()
			if guard.elite:
				elite_slot = slot
				elite_generation = _horde.enemy_generation(slot)
				elite_spawned = true

func _elite_life_valid() -> bool:
	return elite_spawned and is_instance_valid(_horde) and _horde.is_alive(elite_slot) \
			and _horde.enemy_generation(elite_slot) == elite_generation \
			and _horde.get_definition(elite_slot) == elite_definition

func _update_elite_marker() -> void:
	if not is_instance_valid(_elite_marker) or elite_defeated:
		return
	if _elite_life_valid():
		_elite_marker.global_position = _horde.enemy_position(elite_slot) + Vector3.UP * (elite_definition.height * 0.5 + 0.8)

func _on_enemy_killed(definition: HordeEnemyDefinition, at: Vector3) -> void:
	if not active or not initialized or elite_defeated or not elite_spawned or definition != elite_definition:
		return
	if _horde.enemy_generation(elite_slot) != elite_generation or _horde.get_definition(elite_slot) != elite_definition:
		return
	elite_defeated = true
	if is_instance_valid(_elite_marker):
		_elite_marker.hide()
	# Project a death on a ramp/deck back to the nearest proven reachable ground
	# pickup point, rather than leaving the drop inside cover or above the floor.
	_space = get_world_3d().direct_space_state
	var drop_at := elite_site
	var best := INF
	for point in _floor_points:
		var distance := point.distance_squared_to(at)
		if distance < best and _floor_clear(point, 0.6):
			best = distance
			drop_at = point
	elite_drop = _create_stash(GearStash.Source.ELITE_DROP, "VÝBĚRČÍHO VÝBAVA", drop_at)
