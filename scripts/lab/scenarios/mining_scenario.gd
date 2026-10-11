extends LabScenario

func title() -> String:
	return "Close-range machine salvage"

func summary() -> String:
	return "Automatic crowbar, held F prying, gun/reach rejection, wall occlusion and pause"

func run() -> void:
	var game := await lab.start_game(&"driller")
	game.horde.target = null
	await lab.wait(0.5)
	var deposit: MineralDeposit
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.global_position.y < 2.4:
			deposit = node
			break
	lab.check(deposit != null, "stage supplies an accessible wall-mounted machine")
	if deposit == null:
		return
	var player := game.player
	lab.check(await lab.aim_deposit(deposit, 5.0), "distant camera ray hits a real machine compartment")
	var before := deposit.health
	for id in ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]:
		lab.equip_weapon(id)
		lab.fire(true)
		await lab.wait(0.25)
		lab.fire(false)
	lab.check(is_equal_approx(deposit.health, before) and deposit.yield_emitted == 0, "no primary firearm or explosion can break machine compartments at range")
	Input.action_press(&"mine")
	await lab.wait(0.35)
	Input.action_release(&"mine")
	lab.check(not player.mining_ready() and is_equal_approx(deposit.health, before), "F cannot pry beyond melee reach")
	await lab.capture("out_of_reach")

	lab.check(await lab.aim_deposit(deposit, 2.2), "close camera ray hits a real machine compartment")
	await lab.wait(0.15)
	lab.check(player.mining_ready() and not player.drilling(), "visible close compartment raises the idle crowbar before F is held")
	await lab.capture("automatic_crowbar")
	lab.fire(true)
	await lab.wait(0.2)
	lab.fire(false)
	lab.check(is_equal_approx(deposit.health, before), "left click cannot pry or damage a compartment while the crowbar is raised")
	Input.action_press(&"mine")
	await lab.capture_strip("crowbar_leverage", 6, 0.03)
	await lab.wait(0.2)
	Input.action_release(&"mine")
	lab.check(deposit.health < before and deposit.yield_emitted > 0, "held F breaks a real close compartment and releases its conserved currency")
	await lab.capture("f_prying")

	lab.check(await lab.aim_deposit(deposit, 2.2), "a remaining physical compartment can be aimed at after one door breaks")
	before = deposit.health
	game.get_tree().paused = true
	Input.action_press(&"mine")
	await lab.wait(0.3)
	Input.action_release(&"mine")
	lab.check(is_equal_approx(deposit.health, before), "paused F input cannot damage a machine")
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
	lab.check(not player.mining_ready() and is_equal_approx(deposit.health, before), "a machine behind real solid geometry never raises the crowbar or permits prying through a wall")
	blocker.free()
	player.rotation.y += PI
	await lab.wait(0.15)
	lab.check(not player.mining_ready(), "looking away from a machine returns to the primary firearm")
	await lab.capture("return_to_gun")

	for attempt in 30:
		if deposit.health <= 0.0:
			break
		if not await lab.aim_deposit(deposit, 2.2):
			lab.check(false, "every unopened compartment remains reachable by the real crowbar ray")
			return
		Input.action_press(&"mine")
		await lab.wait(0.85)
		Input.action_release(&"mine")
	await lab.frames(2)
	lab.check(deposit.health == 0.0 and deposit.yield_emitted == deposit.total_yield, "emptying the real machine emits its complete conserved currency budget")
	var removed := true
	for section: Dictionary in deposit._sections:
		removed = removed and (section["collider"] as CollisionShape3D).disabled and not (section["mesh"] as MeshInstance3D).visible
	lab.check(removed and not player.mining_ready(), "broken compartment surfaces disappear and the remaining housing cannot be harvested")
	await lab.capture("empty_housing")
