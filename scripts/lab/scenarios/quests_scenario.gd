extends LabScenario

func title() -> String:
	return "Mining and kill contracts"

func summary() -> String:
	return "Real drill and firearm progress, exact species, no deadline and all three pod extractions"

func run() -> void:
	var game := await lab.start_game(&"driller", 0, true, 8721)
	game._rng.seed = 3981
	await lab.wait(0.3)
	await lab.capture("arrival")
	lab.check(game.quests.completed_count() == 0 and not game.round_shop.visible, "arrival exposes fresh mining and kill objectives without advancing")
	var gold := game.quests.quests[0].definition as ResourceDefinition
	game.run_state.add_resource(gold, 7)
	Profile.add_currency(gold.id, 11)
	game.deposits.drop(gold, 3, game.player.global_position)
	await lab.wait(0.8)
	lab.check(game.quests.quests[0].progress == 0, "carried ore, profile currency and collected reward nuggets do not count as mining")
	await _sustained_pressure(game)
	await _drill_input(game)
	await _fire_input(game)
	for stage in 3:
		if stage != 0:
			game.director.set_physics_process(false)
			game.player.grant_invulnerability(1.0e9)
			if game.run_state.level_up_ready.is_connected(game._on_level_up_ready):
				game.run_state.level_up_ready.disconnect(game._on_level_up_ready)
			await lab.wait(0.2)
		game.horde.set_physics_process(false)
		game.horde.clear()
		var old_quests := game.quests
		var complete_signals := [0]
		old_quests.completed.connect(func(): complete_signals[0] += 1)
		# A real last-kill callback may finish while an XP picker is already open.
		if stage == 0:
			_mine_targets(game)
			game.run_state.level_up_ready.connect(game._on_level_up_ready)
			game.run_state.add_xp(game.run_state.xp_required - game.run_state.xp)
			lab.check(game.round_state == ArenaGame.RoundState.LEVEL_UP, "an earned XP choice can remain open when the last kill arrives")
			_kill_targets(game)
			await lab.frames(2)
			lab.check(game.round_state == ArenaGame.RoundState.LEVEL_UP and not game.round_shop.visible, "completing a contract preserves an already earned upgrade choice")
			await lab.capture("complete_pending_choice")
			await lab.wait(game.level_up.input_delay + 0.05)
			game.level_up._choose(0)
		else:
			# Opposite order proves kill-only completion cannot skip the mining half.
			_kill_targets(game)
			await lab.frames(2)
			lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not game.quests.is_complete(), "stage %d stays playable when kill objectives finish before mining" % stage)
			_mine_targets(game)
		await _extract(game, stage)
		lab.check(game.round_state == ArenaGame.RoundState.SHOP and game.round_shop.visible and game.get_tree().paused, "stage %d extracts into the real shop only after every objective" % stage)
		lab.check(game.stages_cleared == stage + 1 and complete_signals[0] == 1, "stage %d counts one completed contract and emits completion once" % stage)
		await lab.capture("%s_extracted" % game.campaign[stage].id)
		var cleared := game.stages_cleared
		old_quests.record_mined(gold, 100000)
		game._on_quests_completed(old_quests.get_instance_id())
		lab.check(game.stages_cleared == cleared, "late/duplicate completion cannot bank or clear the same stage twice")
		if stage < 2:
			game._on_shop_continue()
			await lab.wait(0.3)
			# Pending earned XP is deliberately carried through the exchange.
			while game.round_state == ArenaGame.RoundState.LEVEL_UP:
				await lab.wait(game.level_up.input_delay + 0.05)
				game.level_up._choose(0)
				await lab.frames(2)
			lab.check(game.stage_index == stage + 1 and game.world is ProceduralWorld and game.quests != old_quests and game.quests.completed_count() == 0, "shop continues into a new generated level with fresh objectives")
			game._on_quests_completed(old_quests.get_instance_id())
			lab.check(game.round_state == ArenaGame.RoundState.PLAYING and game.stages_cleared == cleared, "old-level completion cannot finish the new level")
			await lab.capture("%s_new_contract" % game.campaign[stage + 1].id)
	lab.check(game._run_recorded and game.stages_cleared == game.campaign.size(), "all three quest-driven levels produce a recorded campaign victory")

## Completing the contract calls a drop pod; only holding its beam opens the shop.
func _extract(game: ArenaGame, stage: int) -> void:
	await lab.wait(0.2)
	# The last kills can earn XP choices; a player answers them mid-extraction.
	await _settle_choices(game)
	var pod := game.extraction
	lab.check(pod != null and game.round_state == ArenaGame.RoundState.PLAYING and not game.round_shop.visible, "stage %d completion calls a drop pod instead of opening the shop" % stage)
	if pod == null:
		return
	var player := game.player
	var away := player.global_position
	var id: StringName = game.campaign[stage].id
	lab.check(pod.distance_to(away) >= 20.0 and is_equal_approx(game.director.surge, pod.surge_multiplier), "stage %d pod lands %dm away while the director surges" % [stage, roundi(pod.distance_to(away))])
	# Fixture-length hold; landing, presence, pause and departure rules are real.
	pod.hold_time = 2.0
	await lab.wait(pod.landing_time + 0.3)
	lab.check(pod.state == ExtractionPod.State.WAITING and pod.progress == 0.0, "stage %d pod touches down and earns nothing while the player is away" % stage)
	await lab.capture("%s_pod_called" % id)
	_stand(player, pod.global_position)
	await lab.wait(0.8)
	lab.check(pod.player_inside() and pod.progress > 0.4, "standing in the beam accumulates extraction")
	await lab.capture("%s_holding_beam" % id)
	var held := pod.progress
	game.get_tree().paused = true
	await lab.wait(0.4)
	lab.check(is_equal_approx(pod.progress, held), "pause freezes extraction progress")
	game.get_tree().paused = false
	_stand(player, away)
	await lab.wait(0.4)
	lab.check(pod.progress >= held and pod.progress < pod.hold_time and game.round_state == ArenaGame.RoundState.PLAYING, "stepping out keeps progress without extracting")
	_stand(player, pod.global_position)
	await lab.wait(pod.hold_time - pod.progress + 0.6)

func _stand(player: ArenaPlayer, at: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, at.y + 0.1, at.z)

func _settle_choices(game: ArenaGame) -> void:
	while game.round_state == ArenaGame.RoundState.LEVEL_UP:
		await lab.wait(game.level_up.input_delay + 0.05)
		game.level_up._choose(0)
		await lab.frames(2)

func _sustained_pressure(game: ArenaGame) -> void:
	game.horde.set_physics_process(false)
	game.horde.clear()
	game.director.elapsed = game.campaign[0].schedule.ramp_duration
	# Completion cannot be earned merely by waiting beyond the old deadline.
	for tick in 50:
		game.director._physics_process(0.5)
	lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not game.director.boss_phase and game.horde.boss_index < 0, "waiting past the pressure horizon neither releases a timer boss nor completes the level")
	var species: Dictionary = {}
	var safe := true
	for index in game.horde._active_count:
		var slot := game.horde._active[index]
		var enemy := game.horde._defs[game.horde._type[slot]]
		species[enemy] = true
		safe = safe and not game.horde.is_blocked(game.horde._pos[slot], enemy.radius)
	var targets_present := true
	for quest: Dictionary in game.quests.quests:
		if quest.kind == &"kill" and not species.has(quest.definition):
			targets_present = false
	lab.check(targets_present and safe, "all requested enemy species continue spawning on clear ground after the ramp")
	var count := game.horde.alive_count
	var elapsed := game.director.elapsed
	game.get_tree().paused = true
	game.director._physics_process(10.0)
	lab.check(game.horde.alive_count == count and game.director.elapsed == elapsed, "pause freezes contract-level enemy admissions")
	game.get_tree().paused = false
	game.horde.clear()
	game.horde.set_physics_process(true)

func _drill_input(game: ArenaGame) -> void:
	var deposit: MineralDeposit
	for child in game.deposits.get_children():
		if child is MineralDeposit and child.definition.resource == game.quests.quests[0].definition and child.health > 0.0:
			deposit = child
			break
	if deposit == null:
		lab.check(false, "generated contract supplies a live reachable drilling target")
		return
	lab.check(await lab.aim_deposit(deposit, 2.2), "camera and real physics ray acquire a guaranteed procedural ore section")
	var before := deposit.yield_emitted
	Input.action_press(&"mine")
	await lab.wait(0.9)
	Input.action_release(&"mine")
	lab.check(deposit.yield_emitted > before and game.quests.quests[0].progress == deposit.yield_emitted, "actual held F fractures ore and advances mining by exactly conserved emitted units")
	await lab.capture("drilling_progress")
	var progress: int = game.quests.quests[0].progress
	game.get_tree().paused = true
	Input.action_press(&"mine")
	await lab.wait(0.3)
	Input.action_release(&"mine")
	lab.check(game.quests.quests[0].progress == progress, "paused held drill cannot advance ore objectives")
	game.get_tree().paused = false

func _fire_input(game: ArenaGame) -> void:
	var quest: Dictionary = game.quests.quests[2]
	var enemy := quest.definition as HordeEnemyDefinition
	game.horde.set_physics_process(false)
	game.horde.clear()
	# Face back into the clear ore circuit, not through the wall just drilled.
	var stand := game.player.global_position
	var away := game.player.global_basis.z
	var target := stand + away * 5.0
	var point := Vector2(target.x, target.z)
	lab.check(not game.horde.is_blocked(point, enemy.radius), "procedural ore circuit provides a clear real shooting fixture")
	var slot := game.horde.spawn(enemy, point, 0.04)
	if slot < 0:
		lab.check(false, "real firearm quest target is admitted")
		return
	game.horde._rebuild_grid()
	lab.equip_weapon("scatter")
	await lab.wait(0.3)
	lab.aim_at(game.horde.weak_spot_position(slot))
	var before: int = quest.progress
	lab.fire(true)
	await lab.wait(0.6)
	lab.fire(false)
	lab.check(quest.progress == before + 1, "real LMB weapon damage advances exactly its matching species kill objective")
	await lab.capture("kill_progress")
	var unchanged: Array = []
	for other: Dictionary in game.quests.quests:
		if other.kind == &"kill":
			unchanged.append(other.progress)
	for definition in game.horde._defs:
		var requested := false
		for other: Dictionary in game.quests.quests:
			if other.kind == &"kill" and other.definition == definition:
				requested = true
		if not requested and not definition.is_boss:
			var unrelated := game.horde.spawn(definition, point)
			if unrelated >= 0:
				game.horde.damage(unrelated, 1000000.0)
			break
	var after: Array = []
	for other: Dictionary in game.quests.quests:
		if other.kind == &"kill":
			after.append(other.progress)
	lab.check(after == unchanged, "a different ordinary species death cannot advance either requested kill counter")

func _mine_targets(game: ArenaGame) -> void:
	var deposits := game.deposits.get_children()
	for quest: Dictionary in game.quests.quests:
		if quest.kind != &"mine":
			continue
		for child in deposits:
			if quest.progress >= quest.target:
				break
			if not is_instance_valid(child) or not child is MineralDeposit or child.definition.resource != quest.definition:
				continue
			var deposit := child as MineralDeposit
			# Fast fixture extraction still uses real section damage and conserved loot.
			for shape: int in deposit._shape_to_fragment:
				if quest.progress >= quest.target:
					break
				var fragment: int = deposit._shape_to_fragment[shape]
				var section: Dictionary = deposit._sections[fragment]
				if float(section.health) > 0.0:
					deposit.take_mining_damage(1000000.0, deposit.to_global(section.weak_position), shape)
		lab.check(quest.progress == quest.target, "%s objective completes from real mineable sections and caps overshoot" % quest.name)

func _kill_targets(game: ArenaGame) -> void:
	for quest: Dictionary in game.quests.quests:
		if quest.kind != &"kill":
			continue
		var definition := quest.definition as HordeEnemyDefinition
		for kill in quest.target - quest.progress:
			var point := Vector2(game.player.global_position.x, game.player.global_position.z)
			var slot := game.horde.spawn(definition, point)
			if slot < 0:
				lab.check(false, "kill fixture has sufficient actual horde capacity")
				return
			game.horde.damage(slot, 1000000.0)
		lab.check(quest.progress == quest.target, "%s objective counts its exact real deaths" % quest.name)
