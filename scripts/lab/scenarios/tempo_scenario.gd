extends LabScenario

var _shots := 0

func title() -> String:
	return "Held-fire tempo"

func summary() -> String:
	return "Real input cadence, upgraded fire above 60 shots/s, bounded catch-up and stable aim"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	player.global_position = Vector3(0, 1, 12)
	player.shot_fired.connect(_count_shot)
	for id in ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]:
		lab.equip_weapon(id)
		await lab.wait(0.3)
		if player.weapon.spin_up_time > 0.0:
			lab.fire(true)
			await lab.wait(player.weapon.spin_up_time + 0.1)
			lab.fire(false)
			await lab.frames(1)
		var aim := player.head.global_basis
		var body := player.rotation
		var result := await _sample(player, 0.65)
		var expected := result.y / player.weapon.fire_interval
		lab.check(absf(result.x - expected) <= 2.0, "%s held trigger follows elapsed physics cadence (%.0f / %.3fs)" % [id, result.x, result.y])
		lab.check(player.head.global_basis.is_equal_approx(aim) and player.rotation.is_equal_approx(body), "%s firing never changes aim" % id)
		lab.check(player._camera_kick.length() < 0.02, "%s sustained camera recoil remains gentle" % id)
	lab.equip_weapon("minigun")
	while game.run_state.primary.upgrade(&"cadence"):
		pass
	player.refresh_weapon()
	game.run_state.fire_rate_multiplier = 2.0
	lab.fire(true)
	await lab.wait(player.weapon.spin_up_time + 0.1)
	lab.fire(false)
	var result := await _sample(player, 0.65)
	var expected := result.y / (player.weapon.fire_interval / game.run_state.fire_rate_multiplier)
	lab.check(result.x / result.y > 60.0 and absf(result.x - expected) <= 3.0, "upgraded primary exceeds one shot per physics tick without quantizing cadence (%.0f / %.3fs, expected %.1f)" % [result.x, result.y, expected])
	await lab.capture_strip("rapid_primary", 4, 0.05, 4)
	game.run_state.fire_rate_multiplier = 1.0
	await lab.wait(1.0)

	# Stop the loop only around deterministic hitch/backlog boundary ticks.
	player.set_physics_process(false)
	player._fire_cooldown = 0.0
	var shots_before := _shots
	lab.fire(true)
	player._physics_process(1.0)
	lab.fire(false)
	lab.check(_shots - shots_before == 1, "idle/hitch time is discarded instead of banking a machine-gun burst")
	player._fire_cooldown = -10.0
	shots_before = _shots
	lab.fire(true)
	player._physics_process(1.0 / 60.0)
	lab.fire(false)
	lab.check(_shots - shots_before <= ArenaPlayer.MAX_SHOTS_PER_TICK and player._fire_cooldown >= 0.0, "exceptional backlog has bounded catch-up and discards its excess")
	player.set_physics_process(true)

func _count_shot() -> void:
	_shots += 1

func _sample(player: ArenaPlayer, duration: float) -> Vector2:
	var before := _shots
	# physics_frame fires before player processing. Count completed ticks.
	var started := Engine.get_physics_frames()
	var step := player.get_physics_process_delta_time()
	lab.fire(true)
	while float(Engine.get_physics_frames() - started) * step < duration:
		await lab.get_tree().process_frame
	var elapsed := float(Engine.get_physics_frames() - started) * step
	lab.fire(false)
	return Vector2(_shots - before, elapsed)
