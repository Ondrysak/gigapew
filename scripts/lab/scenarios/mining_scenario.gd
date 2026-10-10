extends LabScenario

func title() -> String:
	return "Close-range mining"

func summary() -> String:
	return "Automatic drill, F cutting, gun/long-range rejection, occlusion and pause"

func run() -> void:
	var game := await lab.start_game(&"driller")
	game.horde.target = null
	await lab.wait(0.5)
	var deposit: MineralDeposit
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.global_position.y < 2.4:
			deposit = node
			break
	lab.check(deposit != null, "stage supplies an accessible mineral deposit")
	if deposit == null:
		return
	var player := game.player
	lab.check(await lab.aim_deposit(deposit, 5.0), "distant camera ray hits a real ore section")
	var before := deposit.health
	for id in ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]:
		lab.equip_weapon(id)
		lab.fire(true)
		await lab.wait(0.25)
		lab.fire(false)
	lab.check(is_equal_approx(deposit.health, before) and deposit.yield_emitted == 0, "no primary firearm or its explosion can mine ore at range")
	Input.action_press(&"mine")
	await lab.wait(0.35)
	Input.action_release(&"mine")
	lab.check(not player.mining_ready() and is_equal_approx(deposit.health, before), "F cannot drill beyond melee reach")
	await lab.capture("out_of_reach")

	lab.check(await lab.aim_deposit(deposit, 2.2), "close camera ray hits a real ore section")
	await lab.wait(0.15)
	lab.check(player.mining_ready() and not player.drilling(), "reachable aimed ore equips the idle drill before F is held")
	await lab.capture("automatic_drill")
	lab.fire(true)
	await lab.wait(0.2)
	lab.fire(false)
	lab.check(is_equal_approx(deposit.health, before), "left click does not drill or damage ore in automatic mining mode")
	Input.action_press(&"mine")
	await lab.wait(0.35)
	Input.action_release(&"mine")
	lab.check(deposit.health < before and deposit.yield_emitted > 0, "held F fractures a real close-range section and releases its conserved ore")
	await lab.capture("f_cutting")

	lab.check(await lab.aim_deposit(deposit, 2.2), "a remaining section can be acquired after a fracture")
	before = deposit.health
	game.get_tree().paused = true
	Input.action_press(&"mine")
	await lab.wait(0.3)
	Input.action_release(&"mine")
	lab.check(is_equal_approx(deposit.health, before), "paused F input cannot damage a mineral")
	game.get_tree().paused = false
	player.suppress_fire_until_release()

	var blocker := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 0.2)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	blocker.add_child(collider)
	game._round.add_child(blocker)
	blocker.global_position = player.camera.global_position - player.head.global_basis.z * 0.5
	blocker.global_basis = player.head.global_basis
	await lab.wait(0.1)
	Input.action_press(&"mine")
	await lab.wait(0.3)
	Input.action_release(&"mine")
	lab.check(not player.mining_ready() and is_equal_approx(deposit.health, before), "nearby ore behind real solid geometry never equips or drills through the wall")
	blocker.free()
	player.rotation.y += PI
	await lab.wait(0.15)
	lab.check(not player.mining_ready(), "looking away from ore returns to the primary firearm")
	await lab.capture("return_to_gun")
