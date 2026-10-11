extends LabScenario

func title() -> String:
	return "Žižkov guarded machine"

func summary() -> String:
	return "Real shooting/prying, three response packs, conserved compartment loot, one earned choice and round-end escrow"

func run() -> void:
	await _earned_choice_and_clear()
	await _combat_first_and_cancel()

func _new_game() -> ArenaGame:
	if is_instance_valid(lab.game):
		lab.game.get_tree().paused = false
		lab.game.free()
	return await lab.start_game(&"driller")

func _encounter(game: ArenaGame) -> MiningDefense:
	await lab.wait(0.6)
	var encounter := game.mining_encounter
	lab.check(encounter != null and is_instance_valid(encounter.deposit), "Yard exposes the fixed authored wall-mounted guarded machine")
	if encounter == null or not is_instance_valid(encounter.deposit):
		return null
	return encounter

func _earned_choice_and_clear() -> void:
	var game := await _new_game()
	var encounter := await _encounter(game)
	if encounter == null:
		return
	var vein := encounter.deposit
	# Walk the real spawn-to-machine lane before aim_deposit repositions the fixture.
	var spawn_xz := Vector2(game.player.global_position.x, game.player.global_position.z)
	var vein_xz := Vector2(vein.global_position.x, vein.global_position.z)
	lab.aim_at(vein.global_position)
	Input.action_press(&"move_forward")
	for step in 40:
		var player_xz := Vector2(game.player.global_position.x, game.player.global_position.z)
		if player_xz.distance_to(vein_xz) <= 2.7:
			break
		await lab.wait(0.1)
	Input.action_release(&"move_forward")
	await lab.wait(0.15)
	var walked_xz := Vector2(game.player.global_position.x, game.player.global_position.z)
	lab.check(walked_xz.distance_to(vein_xz) <= 3.0 and walked_xz.distance_to(spawn_xz) > 10.0, "real forward movement reaches crowbar walk-up range from Yard spawn without teleporting")
	lab.check(await lab.aim_deposit(vein, 2.2), "walk-up camera ray reaches a real machine compartment")
	await lab.wait(0.4)
	lab.check(encounter.state == MiningDefense.State.WAITING and encounter.spawned_count == 0, "standing beside the frame does not start response")
	await lab.capture("waiting")
	var untouched := vein.health
	lab.aim_at(game.player.camera.global_position + Vector3.UP * 20.0)
	Input.action_press(&"mine")
	await lab.wait(0.5)
	Input.action_release(&"mine")
	lab.check(vein.health == untouched and encounter.state == MiningDefense.State.WAITING, "held F away from real compartments grants no salvage or response progress")
	lab.check(not encounter.claim_reward(), "waiting cannot claim an upgrade")
	lab.check(await lab.aim_deposit(vein, 2.2), "close crowbar ray reacquires a real compartment")
	Input.action_press(&"mine")
	await lab.wait(0.2)
	Input.action_release(&"mine")
	lab.check(vein.health < untouched and encounter.state == MiningDefense.State.MINING, "actual F-pried compartment damage starts response")
	var timer_before := encounter.remaining()
	var admitted_before := encounter.spawned_count
	var progress_before := encounter.progress()
	game.get_tree().paused = true
	await lab.wait(0.6)
	lab.check(encounter.remaining() == timer_before and encounter.spawned_count == admitted_before and encounter.progress() == progress_before, "paused encounter freezes admission timers, enemies and salvage progress")
	game.get_tree().paused = false
	await lab.wait(1.5)
	lab.check(encounter.spawned_count == 5 and encounter.enemies_remaining() > 0, "first bounded response actually admits five grunts")
	lab.check(await lab.aim_deposit(vein, 2.2), "crowbar points at a live latch under real pressure")
	Input.action_press(&"mine")
	await lab.wait(0.5)
	Input.action_release(&"mine")
	var cut := vein.health
	var emitted := vein.yield_emitted
	await lab.capture("prying_under_pressure")
	await lab.wait(0.5)
	lab.check(vein.health == cut and vein.yield_emitted == emitted, "loosened compartments and emitted loot persist after releasing the crowbar")
	lab.check(not encounter.claim_reward(), "partially emptied defended machine cannot reward")
	await _mine_all(vein)
	lab.check(vein.health == 0.0 and encounter.progress() == 1.0, "crowbar opens every real compartment")
	lab.check(vein.yield_emitted == vein.total_yield, "normal compartment loot conserves the complete currency budget")
	lab.check(encounter.state == MiningDefense.State.DEFENDING and not encounter.claim_reward(), "emptied machine still needs surviving response enemies defeated")
	await lab.capture("defending")
	await _prove_slot_reuse(game, encounter)
	await _finish_response(game, encounter)
	lab.check(encounter.completed_packs == 3 and encounter.spawned_count == 13, "three escalating real packs admit five grunts, four runners, then bulwark/support")
	lab.check(encounter.state == MiningDefense.State.READY and encounter.enemies_remaining() == 0, "ready requires an emptied machine and all actual response identities defeated")
	await lab.capture("ready")
	var level_before := game.run_state.level
	var pending_before := game.run_state.pending_level_ups
	var reward_signals := [0]
	encounter.reward_ready.connect(func(): reward_signals[0] += 1)
	# Genuine E input near the permanent frame, not a direct state assignment or mock reward.
	Input.action_press(&"interact")
	await lab.wait(0.1)
	Input.action_release(&"interact")
	await lab.wait(game.level_up.input_delay + 0.4)
	lab.check(encounter.state == MiningDefense.State.CLAIMED and reward_signals[0] == 1, "near-frame E claims exactly one earned response reward")
	lab.check(game.round_state == ArenaGame.RoundState.ENCOUNTER_REWARD and game.get_tree().paused, "real parent reward flow opens the three-card upgrade choice")
	lab.check(game.run_state.level == level_before and game.run_state.pending_level_ups == pending_before, "earning encounter choice does not fake XP or consume pending level-ups")
	Input.action_press(&"interact")
	await lab.wait(0.1)
	Input.action_release(&"interact")
	lab.check(not encounter.claim_reward() and reward_signals[0] == 1, "held/repeated E and public duplicate claim cannot award twice")
	await lab.capture("reward_dialog")
	if game.level_up._offers.is_empty():
		lab.check(false, "earned encounter dialog contains actual upgrade offers")
		return
	var selected: UpgradeDefinition = game.level_up._offers[0]
	var upgrade_before := game.run_state.level_of(selected)
	# Earned encounter and XP choices remain independent of the level contract.
	game.run_state.add_xp(game.run_state.xp_required - game.run_state.xp)
	var xp_pending := game.run_state.pending_level_ups
	var schedule := game.campaign[0].schedule
	game.director.boss_phase = true
	var boss := game.horde.spawn(schedule.boss, Vector2(0, -8), schedule.boss_health_multiplier)
	lab.check(boss >= 0, "real Yard boss spawns while earned chooser is open")
	if boss < 0:
		return
	game.horde.damage(boss, schedule.boss.max_health * schedule.boss_health_multiplier * 2.0)
	await lab.wait(0.2)
	lab.check(game.round_state == ArenaGame.RoundState.ENCOUNTER_REWARD and game.level_up.visible, "boss death cannot replace the earned encounter chooser")
	game.level_up._choose(0)
	await lab.wait(0.5)
	lab.check(game.run_state.level_of(selected) == upgrade_before + 1, "choosing applies the actual selected upgrade to the run")
	lab.check(game.round_state == ArenaGame.RoundState.LEVEL_UP and game.run_state.pending_level_ups == xp_pending - 1, "earned choice preserves and then presents the queued XP upgrade")
	await lab.capture("reward_then_levelup")
	game.level_up._choose(0)
	await lab.wait(0.3)
	lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not game.quests.is_complete(), "encounter and boss rewards do not skip unfinished level objectives")

func _combat_first_and_cancel() -> void:
	var game := await _new_game()
	var encounter := await _encounter(game)
	if encounter == null:
		return
	var vein := encounter.deposit
	lab.check(await lab.aim_deposit(vein, 2.2), "second run crowbar reaches the authored compartment")
	var before := vein.health
	Input.action_press(&"mine")
	await lab.wait(0.35)
	Input.action_release(&"mine")
	lab.check(vein.health < before and encounter.state == MiningDefense.State.MINING, "first valid crowbar damage also starts the response")
	await _finish_response(game, encounter)
	lab.check(encounter.completed_packs == 3 and vein.health > 0.0 and encounter.state == MiningDefense.State.MINING, "clearing all response packs alone cannot make unopened compartments ready")
	lab.check(not encounter.claim_reward(), "combat-only completion cannot grant a reward")
	var admitted := encounter.spawned_count
	var emitted := vein.yield_emitted
	game.player.active = false
	await lab.wait(0.3)
	lab.check(encounter.state == MiningDefense.State.CANCELLED and not encounter.visible and vein.collision_layer == 0, "player inactivity cancels the encounter and removes harvestable late-hit colliders")
	Input.action_press(&"mine")
	Input.action_press(&"interact")
	await lab.wait(0.6)
	Input.action_release(&"mine")
	Input.action_release(&"interact")
	encounter.cancel()
	lab.check(encounter.spawned_count == admitted and vein.yield_emitted == emitted and not encounter.claim_reward(), "cancelled logic cannot spawn, release loot, claim or restart after repeated cancel")

func _mine_all(vein: MineralDeposit) -> void:
	for attempt in 30:
		if vein.health <= 0.0:
			break
		lab.check(await lab.aim_deposit(vein, 2.2), "crowbar reacquires a remaining physical compartment")
		Input.action_press(&"mine")
		await lab.wait(0.85)
		Input.action_release(&"mine")
	await lab.wait(0.1)

func _finish_response(game: ArenaGame, encounter: MiningDefense) -> void:
	var deadline := Time.get_ticks_msec() + 25000
	var seen_packs := PackedByteArray([0, 0, 0])
	while encounter.completed_packs < 3 and Time.get_ticks_msec() < deadline:
		var slots := encounter.response_slots()
		if not slots.is_empty():
			seen_packs[mini(encounter.pack_index, 2)] = 1
			for slot in slots:
				lab.check(game.horde.is_alive(slot), "response survivor is a real live Horde identity before deterministic damage")
				game.horde.damage(slot, 100000.0)
		await lab.wait(0.3)
	await lab.wait(0.1)
	# A helper may begin after part of pack one was already killed for the slot-reuse boundary.
	lab.check(encounter.completed_packs == 3, "every response pack actually spawns and clears within bounded admission time")
	lab.check(seen_packs[1] == 1 and seen_packs[2] == 1, "runner escalation and bulwark/support pressure occur in actual play")

func _prove_slot_reuse(game: ArenaGame, encounter: MiningDefense) -> void:
	var slots := encounter.response_slots()
	if slots.is_empty():
		lab.check(false, "slot-reuse boundary has a real response survivor")
		return
	var killed := slots[0]
	var generation := game.horde.enemy_generation(killed)
	var survivors := encounter.enemies_remaining()
	var corpse_lifetime: float = game.horde.get_definition(killed).death_duration
	game.horde.damage(killed, 100000.0)
	# A rendered death clip retains its slot until the configured lifetime ends.
	await lab.wait(corpse_lifetime + 0.1)
	var outsider := game.horde.spawn(lab.enemy("robot_grunt"), Vector2(10, -8))
	lab.check(outsider == killed and game.horde.enemy_generation(outsider) != generation, "Horde reuses the defeated response slot with a distinct generation")
	lab.check(encounter.enemies_remaining() == survivors - 1 and not encounter.response_slots().has(outsider), "unrelated reused slot is never counted as a surviving response enemy")
	if outsider >= 0:
		game.horde.damage(outsider, 100000.0)
