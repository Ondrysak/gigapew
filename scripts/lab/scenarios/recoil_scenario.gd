extends LabScenario

func title() -> String:
	return "Recoil"

func summary() -> String:
	return "Frame strips after one heavy shot and during a sustained burst"

func run() -> void:
	var game := await lab.start_game(&"scout")
	var rail := lab.weapon("rail")
	var hand_definitions: Array[WeaponDefinition] = [rail, rail, rail]
	game.run_state.initialize_hands(hand_definitions)
	game.player.weapons = game.run_state.hand_definitions()
	game.player.refresh_weapons()
	var target := lab.ahead(14.0)
	lab.spawn_pack(lab.enemy("robot_grunt"), target, 8, 2.0)
	lab.aim_at(Vector3(target.x, 1.0, target.y))
	await lab.wait(0.4)
	var camera := game.player.camera
	var rest_pitch := game.player.head.rotation.x
	var rest_camera := camera.rotation
	# One trigger pull: every hand fires once, then the release stops the next.
	lab.fire(true)
	await lab.frames(2)
	lab.fire(false)
	var kicked := rad_to_deg(camera.rotation.x - rest_camera.x)
	lab.check(kicked > 0.5, "heavy shot visibly kicks the camera (%.2f deg)" % kicked)
	await lab.capture_strip("single_shot", 6, 0.035)
	await lab.wait(0.6)
	lab.check(is_equal_approx(game.player.head.rotation.x, rest_pitch), "recoil never moves the player's aim (head pitch unchanged)")
	var settled := rad_to_deg((camera.rotation - rest_camera).length())
	lab.check(settled < 0.05, "camera kick recovers to rest (%.3f deg left)" % settled)
	var minigun := lab.weapon("minigun")
	hand_definitions = [minigun, minigun, minigun]
	game.run_state.initialize_hands(hand_definitions)
	game.player.weapons = game.run_state.hand_definitions()
	game.player.refresh_weapons()
	lab.fire(true)
	await lab.wait(1.0)
	var climb := 0.0
	for n in 12:
		await lab.frames(1)
		climb = maxf(climb, rad_to_deg(camera.rotation.x - rest_camera.x))
	lab.check(climb <= rad_to_deg(ArenaPlayer.CAMERA_KICK_MAX) + 0.01, "sustained fire kick stays capped (%.2f deg peak)" % climb)
	await lab.capture_strip("burst", 6, 0.03)
	lab.fire(false)
