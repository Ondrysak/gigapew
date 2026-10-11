extends LabScenario

const CENTER := Vector2(0, 9)
var _megas := PackedInt32Array()

func title() -> String:
	return "Mega hallucinations"

func summary() -> String:
	return "Dense packs fuse without healing or early rewards; actual precision, primary kills, sparse XP, protected identities and moving silhouettes"

func run() -> void:
	var game := await lab.start_game()
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(0, 1, 17)
	game.player.velocity = Vector3.ZERO
	game.horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	game.horde._rng.seed = 60412
	var grunt := lab.enemy("robot_grunt")
	game.horde._t_speed[game.horde._type_of[grunt]] = 0.0
	await _conservation_and_combat(game, grunt)
	await _exclusions(game, grunt)
	await _motion_gallery(game, grunt)

func _reset(game: ArenaGame) -> void:
	game.horde.clear()
	game.hud.boss_panel.hide()
	_simulate(game.horde, 0.8)

func _simulate(horde: Horde, seconds: float) -> void:
	for tick in ceili(seconds / 0.05):
		horde._physics_process(0.05)

func _pack(game: ArenaGame, definition: HordeEnemyDefinition, count: int, reserved: bool = false) -> PackedInt32Array:
	var slots := PackedInt32Array()
	if reserved:
		game.horde.reserve_slots(count)
	for n in count:
		var point := CENTER + Vector2.from_angle(float(n) * TAU / count) * 0.3
		var slot := game.horde.spawn_reserved(definition, point, 200.0 / definition.max_health) if reserved else game.horde.spawn(definition, point, 200.0 / definition.max_health)
		slots.append(slot)
	game.horde._rebuild_grid()
	return slots

func _health(horde: Horde, maximum: bool = false) -> float:
	var total := 0.0
	for active in horde._active_count:
		var slot := horde._active[active]
		if horde.is_alive(slot):
			total += horde._max_hp[slot] if maximum else horde._hp[slot]
	return total

func _kill_progress(game: ArenaGame, definition: HordeEnemyDefinition) -> int:
	for quest in game.quests.quests:
		if quest["kind"] == &"kill" and quest["definition"] == definition:
			return int(quest["progress"])
	return -1

func _kill_target(game: ArenaGame, definition: HordeEnemyDefinition) -> int:
	for quest in game.quests.quests:
		if quest["kind"] == &"kill" and quest["definition"] == definition:
			return int(quest["target"])
	return -1

func _ground_xp(game: ArenaGame) -> int:
	var value := 0
	for n in game.pickups._gems.count:
		value += game.pickups._gems.values[n]
	return value

func _shot(game: ArenaGame, point: Vector3) -> void:
	game.player._process(1.0)
	game.player._reset_combo()
	game.player._quickdraw_left = 0.0
	lab.aim_at(point)
	game.player._shoot()

func _conservation_and_combat(game: ArenaGame, grunt: HordeEnemyDefinition) -> void:
	_reset(game)
	_pack(game, grunt, 5)
	_simulate(game.horde, 1.5)
	lab.check(game.horde.alive_count == 5 and game.horde.query_megas(_megas) == 0, "a sparse five-enemy pack stays ordinary")
	_reset(game)
	var slots := _pack(game, grunt, 8)
	var generations := PackedInt64Array()
	for n in slots.size():
		generations.append(game.horde.enemy_generation(slots[n]))
		game.horde.damage(slots[n], float(n + 1))
	var health_before := _health(game.horde)
	var maximum_before := _health(game.horde, true)
	var kills_before := game.kills
	var progress_before := _kill_progress(game, grunt)
	var xp_before := _ground_xp(game)
	lab.aim_at(Vector3(CENTER.x, 1.2, CENTER.y))
	await lab.capture("dense_before")
	_simulate(game.horde, 0.3)
	lab.check(game.horde.query_megas(_megas) == 0, "brief proximity does not immediately pop into a mega")
	_simulate(game.horde, 1.5)
	var mega_count := game.horde.query_megas(_megas)
	lab.check(mega_count > 0 and game.horde.alive_count < 8 and game.horde.population_count == 8, "persistent local crowd condenses visible bodies without freeing represented spawn pressure")
	lab.check(is_equal_approx(_health(game.horde), health_before) and is_equal_approx(_health(game.horde, true), maximum_before), "fusion preserves remaining and maximum health instead of healing damaged enemies")
	lab.check(game.kills == kills_before and _kill_progress(game, grunt) == progress_before and _ground_xp(game) == xp_before, "fusion grants no kills, species-contract progress or XP")
	if mega_count == 0:
		return
	var mega := _megas[0]
	var members := game.horde.fusion_members(mega)
	lab.check(members >= 6 and members <= 8 and game.horde.get_definition(mega) == grunt, "mega retains bounded constituent count and original quest species")
	var invalidated := true
	for n in slots.size():
		if game.horde.is_alive(slots[n]) and game.horde.fusion_members(slots[n]) > 1:
			invalidated = invalidated and game.horde.enemy_generation(slots[n]) != generations[n]
	lab.check(invalidated, "transformed body starts a new identity rather than retaining a stale pre-fusion hit target")
	_simulate(game.horde, 0.8)
	lab.aim_at(game.horde.enemy_position(mega))
	await lab.capture("mega_after")
	# Admission uses represented lives, not the smaller rendered body count.
	var budget := game.campaign[0].schedule.duplicate() as SpawnSchedule
	budget.max_alive = game.horde.population_count
	game.director.setup(game.horde, budget, game.player, 909)
	game.director.grace = 0.0
	game.director._physics_process(10.0)
	lab.check(game.horde.population_count == 8, "director cannot refill a full pressure budget merely because fusion freed render slots")
	var gun := lab.weapon("pulse").duplicate() as WeaponDefinition
	gun.damage = 10.0
	gun.pierce = 0
	game.run_state.initialize_primary(gun)
	game.player.refresh_weapon()
	game.run_state.equip_gear(GearCatalog.find(&"lighter"))
	var before := game.horde._hp[mega]
	_shot(game, game.horde.enemy_position(mega))
	var body_damage := before - game.horde._hp[mega]
	before = game.horde._hp[mega]
	_shot(game, game.horde.weak_spot_position(mega))
	var head_damage := before - game.horde._hp[mega]
	var precision := game.run_state.crit_multiplier + RunState.WEAK_SPOT_CRIT_BONUS
	lab.check(is_equal_approx(body_damage, 10.0) and is_equal_approx(head_damage, 10.0 * precision), "actual primary body and enlarged visible head shots retain exact damage and precision multiplier")
	await lab.capture("precision_hit")
	gun.damage = 10000.0
	game.run_state.initialize_primary(gun)
	game.player.refresh_weapon()
	_shot(game, game.horde.weak_spot_position(mega))
	lab.check(not game.horde.is_alive(mega) and game.kills == kills_before + members and game.horde.population_count == 8 - members, "one actual primary mega defeat credits each constituent exactly once and releases its full pressure budget")
	lab.check(_kill_progress(game, grunt) == mini(_kill_target(game, grunt), progress_before + members), "mega death credits the actual original species contract, with normal target clamping")
	var admitted := (game.pickups._nonboss_kills / game.pickups.xp_kill_interval) * grunt.xp_value
	lab.check(_ground_xp(game) - xp_before == admitted, "mega death preserves sparse every-third-kill XP admission, not a bonus mega drop")
	_reset(game)
	# Finish an eight-life primary streak, then prove the real next-hit explosion.
	var spitter := lab.enemy("robot_spitter")
	for n in 8 - members:
		game.horde.spawn(spitter, CENTER, 5.0 / spitter.max_health)
		game.horde._rebuild_grid()
		_shot(game, Vector3(CENTER.x, 0.6, CENTER.y))
		_reset(game)
	gun.damage = 10.0
	game.run_state.initialize_primary(gun)
	game.player.refresh_weapon()
	var victim := game.horde.spawn(spitter, CENTER, 5.0 / spitter.max_health)
	var neighbor := game.horde.spawn(spitter, CENTER + Vector2(1.8, 0), 1000.0 / spitter.max_health)
	game.horde._rebuild_grid()
	_shot(game, game.horde.enemy_position(victim))
	lab.check(not game.horde.is_alive(victim) and is_equal_approx(game.horde._hp[neighbor], 950.0), "primary mega constituents charge the lighter streak and its next killing hit deals the real 50-damage blast")
	await lab.capture("constituent_kill_reward")
	game.run_state.gear.clear()
	game.run_state.refresh_modifiers()
	game.run_state.gear_changed.emit()

func _exclusions(game: ArenaGame, grunt: HordeEnemyDefinition) -> void:
	_reset(game)
	var slots := _pack(game, grunt, 8, true)
	var identities := PackedInt64Array()
	for slot in slots:
		identities.append(game.horde.enemy_generation(slot))
	_simulate(game.horde, 2.0)
	var protected := game.horde.query_megas(_megas) == 0 and game.horde.alive_count == 8
	for n in slots.size():
		protected = protected and game.horde.is_alive(slots[n]) and game.horde.enemy_generation(slots[n]) == identities[n]
	lab.check(protected, "reserved stash/elite/response enemies remain eight separate tracked lives even in a dense pack")
	for effect in [&"frost", &"burn", &"stun", &"tag"]:
		_reset(game)
		slots = _pack(game, grunt, 8)
		for slot in slots:
			match effect:
				&"frost": game.horde.slow(slot, 0.55, 10.0)
				&"burn": game.horde.damage(slot, 1.0, Vector3.ZERO, DamageType.Kind.FIRE)
				&"stun": game.horde.stun(slot, 10.0)
				&"tag": game.horde.expose(slot, 10.0)
		_simulate(game.horde, 1.5)
		lab.check(game.horde.query_megas(_megas) == 0 and game.horde.alive_count == 8, "active %s targets cannot fuse away the player's ongoing effect" % effect)
	_reset(game)
	_pack(game, grunt, 8)
	game.player.global_position = Vector3(0, 1, 11)
	_simulate(game.horde, 1.5)
	lab.check(game.horde.query_megas(_megas) == 0, "bodies already on top of the player never abruptly enlarge into a contact threat")
	game.player.global_position = Vector3(0, 1, 17)
	# Isolate role simulation from spawning eight authored boss controllers/cues.
	game.horde.boss_spawned.disconnect(game._on_boss_spawned)
	for id in ["robot_spitter", "robot_tank", "robot_bulwark", "robot_boss"]:
		_reset(game)
		var definition := lab.enemy(id)
		game.horde.register_definition(definition)
		_pack(game, definition, 8)
		_simulate(game.horde, 1.5)
		lab.check(game.horde.query_megas(_megas) == 0, "%s retains its authored specialist/boss role instead of merging" % id)
	game.horde.boss_spawned.connect(game._on_boss_spawned)
	_reset(game)
	var mouse := lab.enemy("alien_grunt")
	game.horde.register_definition(mouse)
	game.horde._t_speed[game.horde._type_of[mouse]] = 0.0
	_pack(game, grunt, 4)
	_pack(game, mouse, 4)
	_simulate(game.horde, 1.5)
	lab.check(game.horde.query_megas(_megas) == 0 and game.horde.population_count == 8, "four plus four different species do not turn into an ambiguous mixed-species mega")
	await lab.capture("separate_species")

func _motion_gallery(game: ArenaGame, grunt: HordeEnemyDefinition) -> void:
	_reset(game)
	_pack(game, grunt, 8)
	lab.aim_at(Vector3(CENTER.x, 1.2, CENTER.y))
	game.horde.set_physics_process(true)
	await lab.capture_strip("fusion_transition", 9, 0.25)
	game.horde.set_physics_process(false)
	if game.horde.query_megas(_megas) == 0:
		lab.check(false, "motion gallery has a real fused enemy")
		return
	var mega := _megas[0]
	var type := int(game.horde._type_of[grunt])
	game.horde._t_speed[type] = grunt.speed
	# Sparse ordinary bodies beside the mega show gait and silhouette contrast.
	game.horde.spawn(grunt, CENTER + Vector2(-3, 0), 200.0 / grunt.max_health)
	game.horde.spawn(grunt, CENTER + Vector2(3, 0), 200.0 / grunt.max_health)
	lab.aim_at(game.horde.enemy_position(mega))
	game.horde.set_physics_process(true)
	await lab.capture_strip("heavy_gait", 6, 0.12)
	game.horde.set_physics_process(false)
	var before := game.horde.alive_count
	var population := game.horde.population_count
	game.get_tree().paused = true
	await lab.wait(0.4)
	lab.check(game.horde.alive_count == before and game.horde.population_count == population, "pause freezes actual fused crowd state")
	await lab.capture("paused_mega")
	game.get_tree().paused = false
	lab.log_line("fusion gallery bodies=%d represented=%d mega_members=%d" % [before, population, game.horde.fusion_members(mega)])
