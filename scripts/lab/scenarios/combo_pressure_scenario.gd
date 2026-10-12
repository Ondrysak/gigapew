extends LabScenario

func title() -> String:
	return "Combo pressure, typography and sensory drive"

func summary() -> String:
	return "Real hits shorten high-chain timers, drive hallucinations and soundtrack layers, then decay with the chain"

func run() -> void:
	Profile.set_setting("hallucination_intensity", 0.65)
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	game.horde.set_physics_process(false)
	game.director.set_physics_process(false)
	player.global_position = Vector3(0, 1, 12)
	var gun := lab.weapon("pulse").duplicate() as WeaponDefinition
	gun.damage = 0.01
	gun.jitter_degrees = 0.0
	gun.spread_degrees = 0.0
	gun.pierce = 0
	game.run_state.initialize_primary(gun)
	player.refresh_weapon()
	var target := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 6), 1000.0)
	game.horde._rebuild_grid()
	await lab.frames(3)
	lab.aim_at(game.horde.enemy_position(target))
	var vision := game.get_node("HallucinationVision") as HallucinationVision
	var idle_vision := vision.effective_intensity
	var idle_music := game._crowd_intensity()
	for shot in 10:
		player._shoot()
	var low_grace: float = player._combo_left
	lab.check(player.combo_hits == 10 and is_equal_approx(low_grace, ArenaPlayer.COMBO_WINDOW), "ten actual direct hits retain the full forgiving grace")
	for shot in 90:
		player._shoot()
	var high_grace: float = player._combo_left
	var start := Time.get_ticks_msec()
	lab.check(player.combo_hits == 100 and is_equal_approx(high_grace, ArenaPlayer.COMBO_MIN_WINDOW), "high real chains shorten their next grace to three seconds")
	await lab.wait(0.6)
	var hot_vision := vision.effective_intensity
	Music.set_intensity(game._crowd_intensity())
	await lab.wait(1.0)
	lab.check(is_equal_approx(hot_vision, 0.65) and hot_vision > idle_vision * 3.0, "the 100-hit chain raises hallucinations to the saved ceiling")
	lab.check(game._crowd_intensity() == 1.0 and idle_music < 0.5 and Music._target_intensity == 1.0 and Music._stem_gain(&"stage", &"lead") > 0.0, "the same real chain drives the soundtrack into its lead layer")
	await lab.capture("hot_combo")
	player.grant_invulnerability(1.0e9)
	while player.combo_hits == 100:
		await lab.get_tree().physics_frame
	var expired := float(Time.get_ticks_msec() - start) / 1000.0
	lab.check(player.combo_hits == 90 and expired > 2.0 and expired < 3.5, "the first high-chain idle step arrives after the shortened grace and removes ten percent")
	var decay_start := Time.get_ticks_msec()
	while player.combo_hits == 90:
		await lab.get_tree().physics_frame
	var interval := float(Time.get_ticks_msec() - decay_start) / 1000.0
	lab.check(player.combo_hits == 81 and interval < 0.8, "the next high-chain decay step fires faster than the low-chain 1.5 seconds")
	player._reset_combo()
	await lab.wait(0.7)
	Music.set_intensity(game._crowd_intensity())
	lab.check(is_equal_approx(vision.effective_intensity, idle_vision) and game._crowd_intensity() < 0.5, "a wiped chain returns hallucination and soundtrack drive to their idle baseline")
	await lab.capture("cooled_down")
