extends LabScenario

func title() -> String:
	return "Kill-earned STYLE pressure and recovery"

func summary() -> String:
	return "Real primary kills drive groove and sensory layers; nonlethal hits cannot refresh style; true recovery freezes decay"

func run() -> void:
	Profile.set_setting("hallucination_intensity", 0.65)
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	game.horde.set_physics_process(false)
	game.director.set_physics_process(false)
	player.global_position = Vector3(0, 1, 12)
	lab.equip_weapon("rail")
	await lab.frames(8)
	var vision := game.get_node("HallucinationVision") as HallucinationVision
	var idle_vision := vision.effective_intensity
	var idle_music := game._crowd_intensity()
	_kill(game)
	var low_style := player.combo_hits
	var low_grace := player._combo_left
	lab.check(low_style > 0 and low_grace > ArenaPlayer.COMBO_MIN_WINDOW, "one actual kill earns STYLE with forgiving low-groove grace")
	for kill in 20:
		if player.combo_hits >= 100:
			break
		_kill(game)
	var high_style := player.combo_hits
	var high_grace := player._combo_left
	lab.check(high_style >= 100 and is_equal_approx(high_grace, ArenaPlayer.COMBO_MIN_WINDOW), "kill-earned hot groove saturates at a finite three-second grace")
	player.set_arena_recovery(true)
	await lab.wait(0.6)
	var hot_vision := vision.effective_intensity
	Music.set_intensity(game._crowd_intensity())
	await lab.wait(0.6)
	lab.check(player.combo_hits == high_style and is_equal_approx(player._combo_left, high_grace), "arena recovery preserves earned groove and its exact timer")
	lab.check(is_equal_approx(hot_vision, 0.65) and hot_vision > idle_vision, "kill-earned hot groove raises hallucinations to the saved ceiling")
	lab.check(game._crowd_intensity() == 1.0 and idle_music < 0.5 and Music._target_intensity == 1.0, "the same actual kill STYLE drives soundtrack intensity")
	await lab.capture("hot_kill_style")
	player.set_arena_recovery(false)
	player.grant_invulnerability(1.0e9)
	var target := _target(game, 1000000.0)
	var deadline := player._combo_left
	player._shoot(false)
	lab.check(player.combo_hits == high_style and is_equal_approx(player._combo_left, deadline), "nonlethal tank shot cannot refresh a hot STYLE deadline")
	var started := Time.get_ticks_msec()
	await _decay(player, high_style)
	var first := high_style - maxi(1, ceili(high_style * 0.1))
	lab.check(player.combo_hits == first and float(Time.get_ticks_msec() - started) / 1000.0 < 3.5, "combat idle expiry removes ten percent of earned STYLE after finite grace")
	await _decay(player, first)
	lab.check(player.combo_hits == first - maxi(1, ceili(first * 0.1)), "subsequent STYLE decay remains gradual")
	var score := player.arena_score
	var charge := player.drop_charge
	player._reset_combo()
	await lab.wait(0.7)
	Music.set_intensity(game._crowd_intensity())
	lab.check(is_equal_approx(vision.effective_intensity, idle_vision) and game._crowd_intensity() < 0.5, "cooled STYLE returns sensory drive to its baseline")
	lab.check(player.arena_score == score and player.drop_charge == charge, "STYLE decay never removes banked arena score or DROP")
	await lab.capture("cooled_style")

func _target(game: ArenaGame, health: float) -> int:
	game.horde.clear()
	var definition := lab.enemy("robot_tank")
	var slot := game.horde.spawn(definition, Vector2(0, 6), health / definition.max_health)
	game.horde._rebuild_grid()
	lab.aim_at(game.horde.enemy_position(slot) + Vector3.UP * 0.45)
	return slot

func _kill(game: ArenaGame) -> void:
	var slot := _target(game, 1.0)
	game.player._shoot(false)
	lab.check(not game.horde.is_alive(slot), "pressure fixture is defeated by a real primary transaction")

func _decay(player: ArenaPlayer, before: int) -> void:
	for frame in 600:
		await lab.get_tree().physics_frame
		if player.combo_hits < before:
			return
	lab.check(false, "active combat groove eventually decays")
