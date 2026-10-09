extends LabScenario

func title() -> String:
	return "Mining"

func summary() -> String:
	return "Drill a mineral deposit: approach, cutting feedback, section break"

func run() -> void:
	var game := await lab.start_game(&"driller")
	# Deposits are placed a few physics frames after the stage loads.
	await lab.wait(0.5)
	var deposit: MineralDeposit = null
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.global_position.y < 2.4:
			deposit = node
			break
	lab.check(deposit != null, "stage placed a reachable deposit")
	if deposit == null:
		return
	var normal := deposit.global_basis.z
	normal.y = 0.0
	var stand := deposit.global_position + normal.normalized() * 2.2
	game.player.global_position = Vector3(stand.x, game.player.global_position.y, stand.z)
	await lab.frames(2)
	lab.aim_at(deposit.global_position)
	await lab.wait(0.3)
	await lab.capture("approach")
	Input.action_press(&"mine")
	await lab.wait(0.8)
	await lab.capture("drilling")
	await lab.wait(1.6)
	await lab.capture("cut")
	Input.action_release(&"mine")
