extends LabScenario

func title() -> String:
	return "Recoil"

func summary() -> String:
	return "Frame strips after one heavy shot and during a sustained burst"

func run() -> void:
	var game := await lab.start_game(&"scout")
	lab.equip_weapon("rail")
	var target := lab.ahead(14.0)
	lab.spawn_pack(lab.enemy("robot_grunt"), target, 8, 2.0)
	lab.aim_at(Vector3(target.x, 1.0, target.y))
	await lab.wait(0.4)
	var camera := game.player.camera
	var rest_pitch := game.player.head.rotation.x
	var rest_camera := camera.rotation
	lab.fire(true)
	await lab.frames(2)
	lab.fire(false)
	var kicked := rad_to_deg(camera.rotation.x - rest_camera.x)
	lab.check(kicked > 0.0 and kicked < 0.4, "heavy shot stays gentle (%.2f deg)" % kicked)
	await lab.capture_strip("single_shot", 6, 0.035)
	await lab.wait(0.6)
	lab.check(is_equal_approx(game.player.head.rotation.x, rest_pitch), "recoil never moves the player's aim (head pitch unchanged)")
	var settled := rad_to_deg((camera.rotation - rest_camera).length())
	lab.check(settled < 0.05, "camera kick recovers to rest (%.3f deg left)" % settled)
	lab.equip_weapon("minigun")
	lab.fire(true)
	await lab.wait(1.0)
	var climb := 0.0
	for n in 12:
		await lab.frames(1)
		climb = maxf(climb, rad_to_deg(camera.rotation.x - rest_camera.x))
	lab.check(climb <= rad_to_deg(ArenaPlayer.CAMERA_KICK_MAX) + 0.01, "sustained fire kick stays capped (%.2f deg peak)" % climb)
	await lab.capture_strip("burst", 6, 0.03)
	lab.fire(false)
