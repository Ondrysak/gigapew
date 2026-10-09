extends LabScenario

var _shots := 0

func title() -> String:
	return "Held-fire tempo"

func summary() -> String:
	return "Real input cadence, upgraded Overspin above 60 shots/s, finite ammo, bounded catch-up and stable aim"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	player.global_position = Vector3(0, 1, 12)
	player.shot_fired.connect(_count_shot)
	for id in ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]:
		_equip(game, id)
		await lab.wait(0.3)
		player._magazines[0] = 200
		player._reserves[0] = 0
		# A spinning hand is measured only after its real warm-up.
		if player.weapons[0].spin_up_time > 0.0:
			lab.fire(true)
			await lab.wait(player.weapons[0].spin_up_time + 0.1)
			lab.fire(false)
			await lab.frames(1)
		var before := player.ammo(0)
		var aim := player.head.global_basis
		var body := player.rotation
		var result := await _sample(player, 0.65)
		var expected := result.y / player.weapons[0].fire_interval
		lab.check(absf(result.x - expected) <= 2.0, "%s held trigger follows elapsed physics cadence (%.0f / %.3fs)" % [id, result.x, result.y])
		lab.check(before - player.ammo(0) == int(result.x), "%s counts only paid rounds" % id)
		lab.check(player.head.global_basis.is_equal_approx(aim) and player.rotation.is_equal_approx(body), "%s firing never changes aim" % id)
		lab.check(player._camera_kick.length() < 0.02, "%s sustained camera recoil remains gentle" % id)
	_equip(game, "minigun")
	for n in 8:
		game.run_state.hands[0].upgrade(&"cadence")
	player.weapons = game.run_state.hand_definitions()
	player.refresh_weapons()
	game.run_state.fire_rate_multiplier = 2.0
	player._magazines[0] = 200
	player._reserves[0] = 0
	player.secondary_charge[0] = 100.0
	await lab.wait(0.3)
	Input.action_press("mine")
	await lab.frames(3)
	Input.action_release("mine")
	var before := player.ammo(0)
	var result := await _sample(player, 0.65)
	var expected := result.y / (player.weapons[0].fire_interval / (game.run_state.fire_rate_multiplier * player.secondaries[0].primary_rate_multiplier()))
	lab.check(result.x / result.y > 60.0 and absf(result.x - expected) <= 3.0, "upgraded Overspin exceeds one shot per physics tick without quantizing cadence (%.0f / %.3fs, expected %.1f)" % [result.x, result.y, expected])
	lab.check(before - player.ammo(0) == int(result.x), "multi-shot ticks consume exactly one real round per emitted shot")
	await lab.capture_strip("overspin", 4, 0.05, 4)
	player.cancel_secondaries()
	game.run_state.fire_rate_multiplier = 1.0
	await lab.wait(1.0)
	# A synthetic long physics delta isolates a hitch, while the trigger remains
	# real input. The normal loop is stopped only around this one deterministic tick.
	player.set_physics_process(false)
	player._fire_cooldowns[0] = 0.0
	var shots_before := _shots
	lab.fire(true)
	player._physics_process(1.0)
	lab.fire(false)
	lab.check(_shots - shots_before == 1, "idle/hitch time is discarded instead of banking a machine-gun burst")
	player._fire_cooldowns[0] = -10.0
	shots_before = _shots
	lab.fire(true)
	player._physics_process(1.0 / 60.0)
	lab.fire(false)
	lab.check(_shots - shots_before <= ArenaPlayer.MAX_SHOTS_PER_TICK and player._fire_cooldowns[0] >= 0.0, "exceptional backlog has a bounded catch-up and discards its excess")
	player.cancel_secondaries()
	_equip(game, "pulse")
	player._magazines[0] = 1
	player._reserves[0] = 0
	player._draw_left = 0.0
	var other_ammo := player.ammo(1)
	shots_before = _shots
	lab.fire(true)
	player._physics_process(1.0 / 60.0)
	lab.fire(false)
	lab.check(_shots == shots_before + 1 and player.selected_weapon == 1 and player.ammo(1) == other_ammo, "empty-magazine rotation cannot fire a ghost second gun in the same tick")
	player.set_physics_process(true)

func _equip(game: ArenaGame, id: String) -> void:
	lab.fire(false)
	game.player.cancel_secondaries()
	var definitions: Array[WeaponDefinition] = [lab.weapon(id), lab.weapon("rail"), lab.weapon("scatter")]
	game.run_state.initialize_hands(definitions)
	# A valid authored-capacity fixture keeps cadence sampling independent of
	# reload timing without putting more rounds in a hand than it can hold.
	game.run_state.hands[0].definition.magazine_size = 200
	game.player.weapons = game.run_state.hand_definitions()
	game.player.refresh_weapons()
	game.player.select_weapon(0)
	game.player._fire_cooldowns.fill(0.0)
	game.hud.set_hands(game.run_state, 0)

func _count_shot() -> void:
	_shots += 1

func _sample(player: ArenaPlayer, duration: float) -> Vector2:
	var before := _shots
	# physics_frame fires BEFORE player processing. Count completed ticks from
	# idle frames, including multiple physics ticks in a slow rendered frame.
	var started := Engine.get_physics_frames()
	var step := player.get_physics_process_delta_time()
	lab.fire(true)
	while float(Engine.get_physics_frames() - started) * step < duration:
		await lab.get_tree().process_frame
	var elapsed := float(Engine.get_physics_frames() - started) * step
	lab.fire(false)
	return Vector2(_shots - before, elapsed)
