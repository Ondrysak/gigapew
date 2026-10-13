extends LabScenario

class PlacementHorde extends Horde:
	var block_all := false
	var block_large := false
	var block_ring := false

	func is_blocked(xz: Vector2, radius: float, feet: float = NAN, headroom: float = 2.2) -> bool:
		if block_all or (block_large and radius > 1.0):
			return true
		if block_ring and xz.length() >= 15.0 and xz.length() <= 33.0:
			return true
		return super.is_blocked(xz, radius, feet, headroom)

func title() -> String:
	return "Finite arena pressure and scarce loot"

func summary() -> String:
	return "Route choices, travel, local venue admissions, survivor cleanup, recovery, blocked placement and actual arena completion"

func run() -> void:
	await _stage_pressure()
	await _blocked_admissions()
	await _blocked_local_admissions()
	await _scarce_loot()
	await _live_wave()

func _new_game(class_id: StringName = &"scout", stage: int = 0, procedural: bool = false) -> ArenaGame:
	if is_instance_valid(lab.game):
		lab.game.free()
	return await lab.start_game(class_id, stage, procedural, 310 + stage)

## Procedural directors: ARRIVAL -> ROUTE (waits for an offered choice) ->
## TRAVEL (waits for the player at the venue) -> local BUILD/PEAK/CLEANUP ->
## RECOVERY -> ROUTE, never revisiting a completed venue.
func _stage_pressure() -> void:
	for stage in 3:
		var game := await _new_game(&"scout", stage, true)
		var horde := game.horde
		horde.set_physics_process(false)
		horde.clear()
		var definition := game.campaign[stage]
		var schedule := definition.schedule
		var world := game.world as ProceduralWorld
		# Isolate the pacing contract from the game's deferred stage reward callback.
		var director := _routed_director(game, schedule, 310 + stage, definition.arena_encounters)
		lab.check(director.is_routed(), "stage %d links %d finite fights over its %d physical venues" % [stage, definition.arena_encounters, world.combat_venues.size()])
		director.grace = definition.spawn_grace
		var completions := [0]
		var choice_events := [0]
		director.arena_completed.connect(func() -> void: completions[0] += 1)
		director.route_choices_changed.connect(func() -> void: choice_events[0] += 1)
		director._physics_process(director.grace)
		var first_ids := _choice_ids(director)
		lab.check(horde.alive_count == 0 and director.phase_name == "ROUTE" and director.encounter_index == 0 and director.recovering and choice_events[0] == 1, "stage %d arrival opens a STYLE-frozen route choice without admitting enemies" % stage)
		var twin := _routed_director(game, schedule, 310 + stage, definition.arena_encounters)
		twin._physics_process(definition.spawn_grace)
		lab.check(_choice_ids(twin) == first_ids and first_ids.size() == 3 and _distinct_kinds(director) == 3, "stage %d offers three distinct venue kinds with seed-stable identities %s" % [stage, first_ids])
		twin.free()
		for tick in 40:
			director._physics_process(15.0)
		lab.check(director.phase_name == "ROUTE" and horde.population_count == 0 and _choice_ids(director) == first_ids and not director.choose_route(&"nowhere"), "stage %d ROUTE waits for an actual offered choice and admits nobody meanwhile" % stage)
		var seen := {}
		var safe := true
		var authored := true
		var recoveries := {}
		var cleanup_held := false
		var species := {}
		var visited: Array[StringName] = []
		var kinds := {}
		var revisited := false
		var leaks: Array[String] = []
		var choices_ok := true
		var travel_held := false
		var arrivals_ok := true
		var frozen_checked := false
		var interrupted := stage != 0
		var venue: Dictionary = {}
		# Count every allocation as it opens; a short PEAK can open and drain
		# between two observation ticks and must still join the expected budget.
		var expected := [0]
		director.phase_changed.connect(func() -> void:
			if director.phase_name in ["BUILD", "PEAK"]:
				expected[0] += director._phase_budget
			elif director.phase_name == "BOSS":
				expected[0] += 1)
		for tick in 6000:
			if director.phase_name == "ROUTE":
				var ids := _choice_ids(director)
				for id in ids:
					revisited = revisited or visited.has(id)
				if not interrupted and not visited.is_empty():
					interrupted = true
					_interrupt_route(game, director, ids)
				var pick: StringName = ids[visited.size() % ids.size()]
				for choice in director.route_choices:
					if not kinds.has(choice.kind):
						pick = choice.id
						break
				# The parent's route modal pauses the tree; the choice still commits.
				game.get_tree().paused = true
				var chosen := director.choose_route(pick)
				game.get_tree().paused = false
				venue = director.current_venue()
				choices_ok = choices_ok and chosen and director.phase_name == "TRAVEL" and director.route_choices.is_empty() and director.current_venue_id == pick and director.current_venue_name == venue.name
				visited.append(pick)
				kinds[venue.kind] = true
				if not travel_held:
					for wait in 10:
						director._physics_process(1.0)
					travel_held = director.phase_name == "TRAVEL" and horde.population_count == 0 and director.recovering and director.current_venue_position.is_finite() and is_finite(director.route_distance())
				game.player.global_position = (venue.arrival as Vector3) + Vector3.UP * 0.9
				game.player.velocity = Vector3.ZERO
				director._physics_process(0.1)
				arrivals_ok = arrivals_ok and director.phase_name == "BUILD" and not director.recovering and director.encounter_index == visited.size()
				continue
			if not frozen_checked and director.phase_name == "BUILD" and director._phase_elapsed >= 6.0:
				frozen_checked = true
				var early := horde.population_count
				lab.check(early > 0 and early < schedule.max_alive, "stage %d starts its local fight with small real groups rather than a cap dump" % stage)
				var before := director.elapsed
				var remaining := director._outstanding()
				game.get_tree().paused = true
				director._physics_process(100.0)
				game.get_tree().paused = false
				game.player.active = false
				director._physics_process(100.0)
				game.player.active = true
				director._player = null
				director._physics_process(100.0)
				director._player = game.player
				lab.check(director.elapsed == before and director._outstanding() == remaining and horde.population_count == early, "pause, inactive and missing players freeze finite local allocations and phase time")
				for wait in 240:
					director._physics_process(0.5)
				var capped := horde.population_count
				lab.check(capped <= schedule.max_alive and capped > 0 and not director.finished and not director.recovering, "unopposed local combat stays capped and never grants recovery or deadline completion")
			var player := Vector2(game.player.global_position.x, game.player.global_position.z)
			var area: Rect2 = venue.admission_area
			for active in horde._active_count:
				var slot := horde._active[active]
				if not horde.is_alive(slot):
					continue
				var enemy: HordeEnemyDefinition = horde._defs[horde._type[slot]]
				species[enemy] = true
				var in_schedule := enemy == schedule.boss
				for wave in schedule.waves:
					in_schedule = in_schedule or wave.enemy == enemy
				authored = authored and in_schedule
				var identity := Vector2i(slot, horde.enemy_generation(slot))
				if seen.has(identity):
					continue
				seen[identity] = true
				var position := horde.enemy_position(slot)
				var point := Vector2(position.x, position.z)
				safe = safe and not horde.is_blocked(point, enemy.radius) and horde.is_reachable(point)
				safe = safe and point.distance_to(player) >= HordeDirector.MIN_SAFE_DISTANCE
				if not area.grow(4.0).has_point(point):
					leaks.append("%s at %s" % [venue.id, point])
			if director.phase_name == "CLEANUP" and horde.alive_count > 0 and not cleanup_held:
				var survivors := horde.population_count
				director._physics_process(600.0)
				cleanup_held = director.phase_name == "CLEANUP" and horde.population_count == survivors and not director.recovering
			if frozen_checked and (cleanup_held or director.phase_name != "PEAK" or director._outstanding() > 0):
				_defeat_all(horde)
			director._physics_process(0.5)
			if director.phase_name == "RECOVERY":
				recoveries[director.encounter_index] = true
				lab.check(horde.population_count == 0 and horde.alive_count == 0 and director.recovering and director.current_venue().is_empty(), "recovery requires all real engaged enemies defeated and closes the venue")
			if director.finished:
				break
		lab.check(safe and authored and species.size() >= 4, "stage %d admits reachable safe authored crowd and specialist roles" % stage)
		lab.check(leaks.is_empty(), "stage %d admits every body on its chosen venue's authored approaches, none district-wide %s" % [stage, leaks.slice(0, 4)])
		lab.check(choices_ok and travel_held and arrivals_ok, "stage %d choices commit even while paused, TRAVEL holds until physical arrival, arrival starts BUILD" % stage)
		lab.check(visited.size() == definition.arena_encounters and not revisited and director.completed_venues == visited and kinds.size() >= 3, "stage %d completes %d distinct venues %s of %d kinds and never re-offers one" % [stage, visited.size(), visited, kinds.size()])
		lab.check(cleanup_held and recoveries.size() == definition.arena_encounters - 1, "stage %d keeps live cleanup separate from each empty recovery" % stage)
		lab.check(director.finished and director.encounter_index == definition.arena_encounters and seen.size() == expected[0] and completions[0] == 1, "stage %d completes its entire %d-body finite budget only through actual defeats" % [stage, expected[0]])
		director._physics_process(1000.0)
		lab.check(completions[0] == 1 and horde.alive_count == 0 and director.route_choices.is_empty(), "completed arena emits once and never restarts admissions or choices")
		lab.log_line("arena stage=%d encounters=%d venues=%s admitted=%d expected=%d species=%d cap=%d" % [stage, director.encounter_index, visited, seen.size(), expected[0], species.size(), schedule.max_alive])
		if not director.finished:
			_log_stalled(director, horde, game.player)

func _log_stalled(director: HordeDirector, horde: Horde, player: ArenaPlayer) -> void:
	lab.log_line("stalled venue=%s phase=%s elapsed=%.1f alive=%d represented=%d outstanding=%d player=%s" % [director.current_venue_id, director.phase_name, director._phase_elapsed, horde.alive_count, horde.population_count, director._outstanding(), player.global_position])
	var at := Vector2(player.global_position.x, player.global_position.z)
	for index in director._remaining.size():
		if director._remaining[index] <= 0:
			continue
		var wave: SpawnWave = director._schedule.waves[index]
		var role := HordeDirector.lane_role(wave.enemy)
		lab.log_line("remaining enemy=%s role=%s radius=%.2f count=%d" % [wave.enemy.resource_path.get_file(), role, wave.enemy.radius, director._remaining[index]])
		for lane: Dictionary in director.current_venue().get("lanes", []):
			if not (lane.roles as Array).has(role):
				continue
			var clear := 0
			var distant := 0
			var farthest := 0.0
			for point: Vector3 in lane.points:
				var xz := Vector2(point.x, point.z)
				farthest = maxf(farthest, at.distance_to(xz))
				if not horde.is_blocked(xz, wave.enemy.radius) and horde.is_reachable(xz) and absf(horde.ground_height(xz) - point.y) <= 0.6:
					clear += 1
					if at.distance_to(xz) >= HordeDirector.MIN_SAFE_DISTANCE + wave.enemy.radius + Horde.PLAYER_RADIUS:
						distant += 1
			lab.log_line("lane=%s points=%d clear=%d safe_distance=%d farthest=%.1f" % [lane.id, (lane.points as PackedVector3Array).size(), clear, distant, farthest])

func _routed_director(game: ArenaGame, schedule: SpawnSchedule, seed_value: int, encounters: int, horde: Horde = null) -> HordeDirector:
	var director := HordeDirector.new()
	game._round.add_child(director)
	director.set_physics_process(false)
	director.setup(game.horde if horde == null else horde, schedule, game.player, seed_value, encounters)
	director.configure_routes(game.world as ProceduralWorld)
	return director

func _choice_ids(director: HordeDirector) -> Array[StringName]:
	var ids: Array[StringName] = []
	for choice in director.route_choices:
		ids.append(choice.id)
	return ids

func _distinct_kinds(director: HordeDirector) -> int:
	var kinds := {}
	for choice in director.route_choices:
		kinds[choice.kind] = true
	return kinds.size()

## An external survivor during ROUTE reopens cleanup; the identical offer returns.
func _interrupt_route(game: ArenaGame, director: HordeDirector, ids: Array[StringName]) -> void:
	var horde := game.horde
	var at := (game.world as ProceduralWorld).arena_point(game.player.global_position)
	var slot := horde.spawn(lab.enemy("robot_grunt"), Vector2(at.x, at.z))
	director._physics_process(0.5)
	var reopened := slot >= 0 and director.phase_name == "CLEANUP" and director.route_choices.is_empty() and not director.recovering
	_defeat_all(horde)
	for tick in 40:
		director._physics_process(0.5)
		if director.phase_name == "ROUTE":
			break
	lab.check(reopened and director.phase_name == "ROUTE" and _choice_ids(director) == ids, "an external survivor during ROUTE reopens cleanup and the same seeded choices return after the breather")

## Local placement keeps the venue budget when every lane point is blocked.
func _blocked_local_admissions() -> void:
	var game := await _new_game(&"scout", 0, true)
	var world := game.world as ProceduralWorld
	game.horde.set_physics_process(false)
	game.horde.clear()
	var grunt := lab.enemy("robot_grunt")
	var horde := PlacementHorde.new()
	game._round.add_child(horde)
	horde.setup([grunt], game.campaign[0].play_area, world.get_node("Obstacles"), game.player, world.get_node_or_null("Elevation"), world.get_node_or_null("Ground"))
	horde.set_layout(world)
	horde.set_physics_process(false)
	var wave := SpawnWave.new()
	wave.enemy = grunt
	wave.count = 6
	wave.count_growth = 0
	wave.group_size = 2
	var schedule := SpawnSchedule.new()
	schedule.waves = [wave]
	schedule.max_alive = 6
	schedule.build_duration = 0.0
	schedule.peak_duration = 0.0
	var director := _routed_director(game, schedule, 512, 1, horde)
	director._physics_process(0.1)
	var chosen := director.phase_name == "ROUTE" and director.choose_route(director.route_choices[0].id)
	var venue := director.current_venue()
	game.player.global_position = (venue.arrival as Vector3) + Vector3.UP * 0.9
	horde.block_all = true
	director._physics_process(0.1)
	for tick in 30:
		director._physics_process(1.0)
	lab.check(chosen and director.phase_name == "BUILD" and horde.alive_count == 0 and director._outstanding() == 6 and not director.finished, "blocked venue lanes consume no phantom budget, never fall back district-wide and grant no completion")
	horde.block_all = false
	var admitted := 0
	var local := true
	for tick in 40:
		director._physics_process(1.0)
		for active in horde._active_count:
			var slot := horde._active[active]
			if horde.is_alive(slot):
				var at := horde.enemy_position(slot)
				local = local and (venue.admission_area as Rect2).grow(4.0).has_point(Vector2(at.x, at.z))
		admitted += horde.population_count
		_defeat_all(horde)
		if director.finished:
			break
	director._physics_process(1.0)
	lab.check(admitted == 6 and local and director.finished, "reopened %s lanes admit the whole six-body allocation locally, then complete" % venue.id)

func _blocked_admissions() -> void:
	var game := await _new_game()
	var grunt := lab.enemy("robot_grunt")
	var large := grunt.duplicate() as HordeEnemyDefinition
	large.radius = 2.0
	var horde := PlacementHorde.new()
	game._round.add_child(horde)
	horde.setup([grunt, large], Rect2(-40, -40, 80, 80), null, game.player)
	horde.set_physics_process(false)
	game.player.global_position = Vector3(0, 0.9, 0)
	var wave := SpawnWave.new()
	wave.enemy = large
	wave.count = 7
	wave.count_growth = 0
	wave.group_size = 3
	var alternative := SpawnWave.new()
	alternative.enemy = grunt
	alternative.count = 0
	alternative.count_growth = 0
	var schedule := SpawnSchedule.new()
	schedule.waves = [wave, alternative]
	schedule.max_alive = 3
	schedule.build_duration = 0.0
	schedule.peak_duration = 0.0
	var director := HordeDirector.new()
	game._round.add_child(director)
	director.set_physics_process(false)
	director.setup(horde, schedule, game.player, 444, 1)
	director._physics_process(0.1)
	horde.block_all = true
	for tick in 30:
		director._physics_process(1.0)
	lab.check(horde.alive_count == 0 and director._outstanding() == 7 and not director.finished, "temporarily impossible placement consumes no phantom budget and grants no completion")
	horde.block_all = false
	horde.block_large = true
	horde.block_ring = true
	var admitted := 0
	var capped := false
	var within_cap := true
	for tick in 100:
		director._physics_process(1.0)
		capped = capped or horde.population_count == schedule.max_alive
		within_cap = within_cap and horde.population_count <= schedule.max_alive
		if horde.population_count == schedule.max_alive or director.phase_name == "CLEANUP":
			admitted += horde.population_count
			_defeat_all(horde)
		if director.finished:
			break
	admitted += horde.population_count
	_defeat_all(horde)
	director._physics_process(1.0)
	lab.check(within_cap and capped and admitted == 7 and director.finished, "blocked ring uses reachable whole-arena approaches and unplaceable specialist budget becomes seven actual smaller opponents within the life cap")

func _defeat_all(horde: Horde) -> void:
	for active in horde._active_count:
		var slot := horde._active[active]
		if horde.is_alive(slot):
			horde.damage(slot, 1.0e6)

func _scarce_loot() -> void:
	var game := await _new_game()
	game.horde.target = null
	game.horde.set_physics_process(false)
	game.horde.boss_spawned.disconnect(game._on_boss_spawned)
	game.horde.boss_killed.disconnect(game._on_boss_killed)
	game.pickups.free()
	var field := game.pickup_scene.instantiate() as PickupField
	field.max_gems = 2
	field.xp_kill_interval = 3
	field.magnet_kill_interval = 120
	field.repair_chance = 0.004
	field.supply_interval = 50.0
	game._round.add_child(field)
	field.setup(game.horde, game.player, game.run_state)
	field.set_physics_process(false)
	game.pickups = field
	game.player.global_position = Vector3(0, 0.9, 12)
	game.player.velocity = Vector3.ZERO
	game.run_state.xp_multiplier = 1.0
	var xp_before := _total_xp(game.run_state)
	var mirror := RandomNumberGenerator.new()
	# Choose a deterministic first-roll repair success, then independently predict
	# every subsequent roll. No dependence on randomized scene startup or supply.
	var seed_value := 0
	for candidate in 10000:
		mirror.seed = candidate
		if mirror.randf() < field.repair_chance:
			seed_value = candidate
			break
	field._rng.seed = seed_value
	mirror.seed = seed_value
	var expected_repairs := 0
	for kill in 121:
		if mirror.randf() < field.repair_chance:
			expected_repairs += 1
	_kill(game, lab.enemy("robot_tank"))
	_kill(game, lab.enemy("robot_spitter"))
	lab.check(field._gems.count == 0 and field._magnets.count == 0, "two real high-XP victims do not bank XP or admit early regular utility loot")
	var boss := game.campaign[0].schedule.boss
	var grunt := lab.enemy("robot_grunt")
	_kill(game, boss)
	lab.check(field._nonboss_kills == 2 and field._gems.count == 1 and _ground_xp(field) == boss.xp_value, "boss admits exactly its authored XP reward without advancing regular kill cadence")
	_kill(game, grunt)
	lab.check(field._nonboss_kills == 3 and field._gems.count == 2 and _ground_xp(field) == boss.xp_value + grunt.xp_value, "third regular kill earns only its own victim XP, not the skipped tank and spitter values")
	field.magnetize_xp()
	for regular_kill in range(4, 121):
		_kill(game, grunt)
		if regular_kill == 119:
			lab.check(field._magnets.count == 1, "configured regular magnet does not arrive at kill 119")
	lab.check(field._magnets.count == 2, "configured 120-kill magnet admission remains independent of the boss reward")
	var admitted_xp := boss.xp_value + 40 * grunt.xp_value
	lab.check(field._gems.count == 2 and _ground_xp(field) == admitted_xp and field._gems.speeds[0] > 0.0 and field._gems.speeds[1] > 0.0, "sparse admissions overflow into an entirely homing pool without losing or inventing XP")
	lab.check(expected_repairs > 0 and field._repairs.count == expected_repairs, "seeded real kill repair admissions match the reduced probability (%d kits)" % expected_repairs)
	field._physics_process(0.0)
	await lab.frames(2)
	lab.aim_at(Vector3(20, 0.5, 12))
	await lab.capture("scarce_ground_loot")
	field.supply_interval = 1.0e6
	field.set_physics_process(true)
	for frame in 240:
		if field._gems.count == 0:
			break
		await lab.get_tree().physics_frame
	field.set_physics_process(false)
	lab.check(field._gems.count == 0 and _total_xp(game.run_state) - xp_before == admitted_xp, "magnet arrival awards every admitted XP value once, never skipped victim XP")

	# Timed recovery uses an explicit long interval and the normal grounded search.
	field.supply_interval = 50.0
	field._supply_elapsed = 0.0
	field._physics_process(49.9)
	lab.check(field._supplies.count == 0, "timed supply does not admit a pack before its configured 50-second boundary")
	field._physics_process(0.11)
	lab.check(field._supplies.count == 1, "timed supply admits one reachable grounded pack at its boundary")
	if field._supplies.count > 0:
		var at := field._supplies.positions[0]
		lab.check(not game.horde.is_blocked(Vector2(at.x, at.z), 0.4) and is_equal_approx(at.y, game.horde.ground_height(Vector2(at.x, at.z)) + field.repair_height), "scarce timed repair retains real bounded ground placement")
	field._supply_elapsed = 0.0
	lab.get_tree().paused = true
	field._physics_process(100.0)
	lab.check(field._supply_elapsed == 0.0 and field._supplies.count == 1, "pause prevents scarce supply progress and collection")
	lab.get_tree().paused = false
	game.player.active = false
	field._physics_process(100.0)
	lab.check(field._supply_elapsed == 0.0, "inactive player cannot advance scarce supplies")
	game.player.active = true
	var invalid_player := ArenaPlayer.new()
	field._player = invalid_player
	invalid_player.free()
	field._physics_process(100.0)
	lab.check(field._supply_elapsed == 0.0 and field._supplies.count == 1, "freed player cannot advance supplies or consume ground loot")
	field._player = game.player

func _live_wave() -> void:
	var game := await _new_game(&"gunner")
	game.director._rng.seed = 20261009
	game.pickups._rng.seed = 20261009
	game.director.set_physics_process(true)
	var seen := {}
	Engine.time_scale = 6.0
	await _observe(game, seen, 8.0)
	var early := game.horde.population_count
	lab.check(early > 0 and early <= game.campaign[0].schedule.max_alive, "live BUILD presents capped actual opponents")
	_aim_crowd(game)
	await lab.capture("live_arena_build")
	lab.fire(true)
	await _observe(game, seen, 45.0)
	lab.fire(false)
	var state := game.run_state
	if state.secondary_primary_source == null:
		var partner := state.available_weapons[(state.available_weapons.find(state.primary.source) + 1) % state.available_weapons.size()]
		state.equip_pair(state.primary.source, partner)
	game.player.quick_swap()
	lab.fire(true)
	await _observe(game, seen, 20.0)
	lab.fire(false)
	Engine.time_scale = 1.0
	lab.check(game.kills > 0 and game.horde.population_count <= game.campaign[0].schedule.max_alive, "normal held weapons defeat live finite arena opponents without exceeding the cap")
	lab.check(game.pickups._gems.count <= game.kills / 3, "actual arena defeats retain sparse XP rather than one gem per victim")
	_aim_crowd(game)
	await lab.frames(2)
	await lab.capture("live_arena_combat")
	lab.log_line("live arena encounter=%d phase=%s bodies=%d represented=%d seen=%d kills=%d" % [game.director.encounter_index, game.director.phase_name, game.horde.alive_count, game.horde.population_count, seen.size(), game.kills])

func _observe(game: ArenaGame, seen: Dictionary, seconds: float) -> void:
	var observed := 0.0
	var aiming := 0.0
	while observed < seconds and not game.director.finished and game.player.active:
		await lab.get_tree().physics_frame
		var delta := game.get_physics_process_delta_time()
		observed += delta
		aiming += delta
		seen.merge(_identities(game.horde))
		if aiming >= 0.2:
			aiming = 0.0
			_aim_crowd(game)

func _identities(horde: Horde) -> Dictionary:
	var identities := {}
	for active in horde._active_count:
		var slot := horde._active[active]
		if horde.is_alive(slot):
			identities[Vector2i(slot, horde.enemy_generation(slot))] = true
	return identities

func _aim_crowd(game: ArenaGame) -> void:
	for active in game.horde._active_count:
		var slot := game.horde._active[active]
		if game.horde.is_alive(slot):
			lab.aim_at(game.horde.weak_spot_position(slot))
			return

func _kill(game: ArenaGame, definition: HordeEnemyDefinition) -> void:
	var slot := game.horde.spawn(definition, Vector2(20, 12))
	if slot < 0:
		lab.check(false, "loot fixture can admit its real enemy victim")
		return
	game.horde.damage(slot, 1.0e6)

func _ground_xp(field: PickupField) -> int:
	var total := 0
	for index in field._gems.count:
		total += field._gems.values[index]
	return total

func _total_xp(state: RunState) -> int:
	var total := state.xp
	for level in range(1, state.level):
		total += RunState.required_for(level)
	return total
