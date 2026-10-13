extends LabScenario

func title() -> String:
	return "Scored arena campaign"

func summary() -> String:
	return "Real primary-kill score, optional loot, finite cleanup, stage rewards, carried score and three-arena victory"

func run() -> void:
	var game := await lab.start_game(&"scout", 0, true, 5501)
	game._rng.seed = 7719
	var best_before := int(Profile.records.get("best_score", 0))
	lab.check(game.hud.arena_panel.visible and game.hud.arena_round_box.visible and not game.round_shop.visible, "arrival shows the arena score and set without a contract or extraction objective")
	await lab.capture("arrival")
	await _primary_kill_scores(game)
	var carried := 0
	for stage in game.campaign.size():
		var director := game.director
		var old_id := director.get_instance_id()
		var stage_start := game.arena_score
		var unopened := _unopened_cabinets(game)
		for frame in 30:
			if not unopened.is_empty():
				break
			await lab.get_tree().physics_frame
			unopened = _unopened_cabinets(game)
		var cleared := game.stages_cleared
		await _clear_arena(game)
		lab.check(game.round_state == ArenaGame.RoundState.SHOP and game.round_shop.visible and game.stages_cleared == cleared + 1, "stage %d opens its shop after the final real survivor is defeated" % stage)
		lab.check(not unopened.is_empty() and _all_unopened(unopened), "stage %d clears without opening any original optional venue cabinet" % stage)
		lab.check(game.arena_score >= stage_start, "stage %d arena score never resets during its finite combat" % stage)
		await lab.capture("%s_shop" % game.campaign[stage].id)
		game._on_arena_completed(old_id)
		lab.check(game.stages_cleared == cleared + 1, "duplicate arena completion cannot bank or clear a stage twice")
		carried = game.arena_score
		if stage + 1 < game.campaign.size():
			game._on_shop_continue()
			for frame in 80:
				await lab.frames(1)
				if game.round_state == ArenaGame.RoundState.PLAYING and game.stage_index == stage + 1:
					break
			game.director.set_physics_process(false)
			game.player.grant_invulnerability(1.0e9)
			lab.check(game.stage_index == stage + 1 and game.arena_score == carried and game.director.encounter_index == 0 and not game.director.finished, "shop continues into a fresh arena while carrying run score")
			game._on_arena_completed(old_id)
			lab.check(game.round_state == ArenaGame.RoundState.PLAYING and game.stages_cleared == cleared + 1, "a stale previous-arena signal cannot clear the next arena")
	lab.check(game._run_recorded and game.stages_cleared == game.campaign.size() and int(Profile.records.last_run.score) == carried, "three actual arena clears record a victory with the run score")
	lab.check(int(Profile.records.best_score) == maxi(best_before, carried), "the score attack record keeps the higher actual run score")

func _primary_kill_scores(game: ArenaGame) -> void:
	game.horde.clear()
	game.horde.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.set_process(false)
	game.run_state.crit_chance = 0.0
	var definition := lab.enemy("robot_grunt")
	game.horde.register_definition(definition)
	var target := game.horde.spawn(definition, Vector2(game.player.global_position.x, game.player.global_position.z - 6.0))
	game.horde._rebuild_grid()
	lab.aim_at(game.horde.enemy_position(target) + Vector3.UP * 0.5)
	var before := game.arena_score
	var shots := 0
	while game.horde.is_alive(target) and shots < 40:
		var hp := game.horde._hp[target]
		game.player._shoot(false)
		shots += 1
		if game.horde.is_alive(target):
			lab.check(game.arena_score == before, "nonlethal primary hit %d does not award arena score" % shots)
			if hp == game.horde._hp[target]:
				break
	lab.check(not game.horde.is_alive(target) and game.arena_score > before and game.player.drop_charge > 0.0, "an actual primary kill awards score and DROP charge")
	await lab.capture("primary_kill_score")
	game.player.set_physics_process(true)
	game.player.set_process(true)
	game.horde.set_physics_process(true)

func _clear_arena(game: ArenaGame) -> void:
	var director := game.director
	director.set_physics_process(false)
	director.grace = 0.0
	var held := false
	var visited: Array[StringName] = []
	for tick in 5000:
		if game.round_state in [ArenaGame.RoundState.LEVEL_UP, ArenaGame.RoundState.GEAR, ArenaGame.RoundState.ENCOUNTER_REWARD]:
			await _choose_reward(game)
		if director.phase_name == "ROUTE":
			await lab.frames(2)
			if game.round_state != ArenaGame.RoundState.ROUTE:
				game._resume_play()
			if director.route_choices.is_empty():
				break
			var choice: Dictionary = director.route_choices[0]
			lab.check(not visited.has(choice.id), "stage %d offers an unvisited venue for its next fight" % game.stage_index)
			visited.append(choice.id)
			await lab.wait(0.26)
			game.route_screen.choice_buttons[0].pressed.emit()
			await lab.frames(1)
		if director.phase_name == "TRAVEL":
			game.player.global_position = director.current_venue().arrival + Vector3.UP * 0.95
			game.player.velocity = Vector3.ZERO
			await lab.get_tree().physics_frame
		if director.phase_name == "CLEANUP" and game.horde.alive_count > 0 and not held:
			director._physics_process(600.0)
			await lab.frames(2)
			held = director.phase_name == "CLEANUP" and game.round_state == ArenaGame.RoundState.PLAYING
			lab.check(held, "stage %d stays in combat while real survivors remain" % game.stage_index)
		if held or director.phase_name != "PEAK" or director._outstanding() > 0:
			_defeat_all(game.horde)
		director._physics_process(0.5)
		if director.finished:
			break
	for frame in 12:
		await lab.frames(1)
		if game.round_state == ArenaGame.RoundState.SHOP:
			lab.check(visited.size() == director.encounter_count, "stage %d completes its required distinct venue fights" % game.stage_index)
			return
		if game.round_state in [ArenaGame.RoundState.LEVEL_UP, ArenaGame.RoundState.GEAR, ArenaGame.RoundState.ENCOUNTER_REWARD]:
			await _choose_reward(game)

func _choose_reward(game: ArenaGame) -> void:
	await lab.wait(0.3)
	await lab.key(KEY_ESCAPE if game.round_state == ArenaGame.RoundState.GEAR else KEY_1)
	await lab.frames(2)

func _defeat_all(horde: Horde) -> void:
	for active in horde._active_count:
		var slot := horde._active[active]
		if horde.is_alive(slot):
			horde.damage(slot, 1.0e6)

func _unopened_cabinets(game: ArenaGame) -> Array[MineralDeposit]:
	var cabinets: Array[MineralDeposit] = []
	for child in game.deposits.get_children():
		if child is MineralDeposit and child.health > 0.0:
			cabinets.append(child)
	return cabinets

func _all_unopened(cabinets: Array[MineralDeposit]) -> bool:
	for cabinet in cabinets:
		if not is_instance_valid(cabinet) or cabinet.yield_emitted != 0:
			return false
	return true
