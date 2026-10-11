extends LabScenario

func title() -> String:
	return "Combat"

func summary() -> String:
	return "Thrown beer bottles against a mixed human hallucination pack (flight, glass, hits)"

func run() -> void:
	var game := await lab.start_game(&"scout")
	var reported := {"amount": 0.0}
	game.horde.damage_reported.connect(func(_at: Vector3, amount: float, _kind: int, _critical: bool, _killed: bool): reported.amount += amount)
	var target := lab.ahead(12.0)
	lab.spawn_pack(lab.enemy("robot_grunt"), target, 16, 3.0)
	lab.spawn_pack(lab.enemy("robot_runner"), lab.ahead(16.0, 4.0), 6, 1.5)
	lab.spawn_pack(lab.enemy("robot_spitter"), lab.ahead(18.0, -4.0), 3, 1.0)
	lab.aim_at(Vector3(target.x, 1.0, target.y))
	await lab.wait(0.4)
	await lab.capture("ready")
	lab.fire(true)
	await lab.wait(0.1)
	await lab.capture("muzzle")
	await lab.wait(0.7)
	await lab.capture("hits")
	await lab.wait(1.2)
	await lab.capture("sustained")
	lab.fire(false)
	lab.check(reported.amount > 0.0, "held fire damaged the pack (%.0f dealt)" % reported.amount)
	lab.check(game.kills > 0, "sustained fire killed enemies (%d)" % game.kills)
