extends LabScenario

func title() -> String:
	return "Crowd pressure and scarce loot"

func summary() -> String:
	return "Actual stage directors, sparse kill admissions, conserved overflow, and accelerated live combat"

func run() -> void:
	await _stage_pressure()
	await _scarce_loot()
	await _live_wave()

func _new_game(class_id: StringName = &"scout", stage: int = 0) -> ArenaGame:
	if is_instance_valid(lab.game):
		lab.game.free()
	return await lab.start_game(class_id, stage)

func _stage_pressure() -> void:
	for stage in 3:
		var game := await _new_game(&"scout", stage)
		var horde := game.horde
		horde.set_physics_process(false)
		horde.clear()
		var schedule := game.campaign[stage].schedule
		var director := game.director
		director.setup(horde, schedule, game.player)
		director.elapsed = 0.0
		director.boss_phase = false
		director._rng.seed = 310 + stage
		# The stage's arrival calm admits nothing; ordinary groups follow promptly.
		director.grace = game.campaign[stage].spawn_grace
		for tick in ceili(director.grace / 0.5):
			director._physics_process(0.5)
		lab.check(_identities(horde).is_empty(), "stage %d keeps its %.0fs arrival calm free of spawns" % [stage, game.campaign[stage].spawn_grace])
		# Fixed half-second admissions exercise the director, not resource text.
		for tick in 12:
			director._physics_process(0.5)
		var early := _identities(horde)
		lab.check(not early.is_empty() and early.size() < schedule.max_alive / 4, "stage %d has prompt ordinary groups after the calm without filling its crowd cap" % stage)
		for tick in 168:
			director._physics_process(0.5)
		var later := _identities(horde)
		var ordinary := 0
		var specialists := 0
		var authored_identities := true
		for identity: Vector2i in later:
			var definition: HordeEnemyDefinition = horde._defs[horde._type[identity.x]]
			var authored := false
			for wave in schedule.waves:
				if definition == wave.enemy:
					authored = true
			authored_identities = authored_identities and authored
			if definition.behavior == HordeEnemyDefinition.Behavior.SWARM:
				ordinary += 1
			else:
				specialists += 1
		lab.check(authored_identities and later.size() > early.size() * 3 and later.size() <= schedule.max_alive, "stage %d ramps real scheduled identities within its cap (%d early, %d later)" % [stage, early.size(), later.size()])
		lab.check(ordinary > specialists * 3, "stage %d early pressure remains an ordinary crowd rather than specialist spam" % stage)
		var before := director.elapsed
		game.player.active = false
		director._physics_process(10.0)
		lab.check(director.elapsed == before and _identities(horde).size() == later.size(), "inactive player freezes stage %d admissions" % stage)
		game.player.active = true
		director._player = null
		director._physics_process(10.0)
		lab.check(director.elapsed == before, "missing player freezes stage %d admissions" % stage)
		director._player = game.player
		lab.log_line("stage=%d live=%d ordinary=%d specialists=%d cap=%d reserved=%d" % [stage, later.size(), ordinary, specialists, schedule.max_alive, horde._reserved_slots])
		# Release the deliberately unopposed early crowd so later specialists
		# can be admitted instead of being blocked by a cap with no player kills.
		horde.clear()
		director.elapsed = schedule.ramp_duration * 0.75
		for tick in 24:
			director._physics_process(0.5)
		ordinary = 0
		specialists = 0
		for identity: Vector2i in _identities(horde):
			var definition: HordeEnemyDefinition = horde._defs[horde._type[identity.x]]
			if definition.behavior == HordeEnemyDefinition.Behavior.SWARM:
				ordinary += 1
			else:
				specialists += 1
		lab.check(specialists > 0 and ordinary > specialists * 3, "stage %d later real admissions retain rare specialists beside a dominant ordinary crowd" % stage)

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
	_kill(game, boss)
	lab.check(field._nonboss_kills == 2 and field._gems.count == 1 and _ground_xp(field) == boss.xp_value, "boss admits exactly its authored XP reward without advancing regular kill cadence")
	_kill(game, lab.enemy("robot_grunt"))
	lab.check(field._nonboss_kills == 3 and field._gems.count == 2 and _ground_xp(field) == boss.xp_value + 1, "third regular kill earns only its own victim XP, not the skipped tank and spitter values")
	field.magnetize_xp()
	for regular_kill in range(4, 121):
		_kill(game, lab.enemy("robot_grunt"))
		if regular_kill == 119:
			lab.check(field._magnets.count == 1, "configured regular magnet does not arrive at kill 119")
	lab.check(field._magnets.count == 2, "configured 120-kill magnet admission remains independent of the boss reward")
	var admitted_xp := boss.xp_value + 40
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
	var player := game.player
	game.director._rng.seed = 20261009
	game.pickups._rng.seed = 20261009
	game.director.set_physics_process(true)
	var seen := {}
	Engine.time_scale = 6.0
	await _observe(game, seen, 12.0)
	var early := game.horde.population_count
	lab.check(early > 0 and early < game.campaign[0].schedule.max_alive / 4, "normal early live wave presents pressure rather than an instant cap dump")
	_aim_crowd(game)
	await lab.capture("live_early")
	lab.fire(true)
	await _observe(game, seen, 48.0)
	lab.fire(false)
	player.cycle_weapon(1)
	await lab.wait(0.15)
	_aim_crowd(game)
	lab.fire(true)
	await _observe(game, seen, 12.0)
	lab.fire(false)
	await lab.capture("live_swapped_primary")
	player.cycle_weapon(-1)
	await _observe(game, seen, 50.0)
	Engine.time_scale = 1.0
	_aim_crowd(game)
	await lab.frames(2)
	var late := game.horde.population_count
	lab.check(late > early * 3 and late <= game.campaign[0].schedule.max_alive and game.kills > 0, "accelerated normal gameplay ramps real represented pressure within the cap while held weapons kill actual enemies (%d early, %d late)" % [early, late])
	lab.check(seen.size() >= late and game.pickups._gems.count <= game.kills / 3, "observed live identities and actual kills leave sparse XP gems instead of a gem for every victim")
	var megas := PackedInt32Array()
	var mega_count := game.horde.query_megas(megas)
	lab.log_line("normal elapsed=%.1f bodies=%d represented=%d megas=%d observed_lives=%d kills=%d ground_xp_gems=%d magnets=%d repairs=%d supplies=%d" % [game.director.elapsed, game.horde.alive_count, late, mega_count, seen.size(), game.kills, game.pickups._gems.count, game.pickups._magnets.count, game.pickups._repairs.count, game.pickups._supplies.count])
	# Inspect the same stress crowd from the authored 3m overlook rather than
	# inside the unopposed robots surrounding the original camera.
	var lookout := Vector2(25.0, 25.0)
	player.global_position = Vector3(lookout.x, game.horde.ground_height(lookout) + 1.0, lookout.y)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	lab.aim_at(Vector3.ZERO)
	await lab.frames(2)
	await lab.capture("live_crowd_scarce_loot")

func _observe(game: ArenaGame, seen: Dictionary, seconds: float) -> void:
	var until := game.director.elapsed + seconds
	while game.director.elapsed < until:
		await lab.get_tree().physics_frame
		seen.merge(_identities(game.horde))

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
			lab.aim_at(game.horde.enemy_position(slot))
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
