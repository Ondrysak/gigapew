extends LabScenario

const WEAPONS := ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]

func title() -> String:
	return "Weapons"

func summary() -> String:
	return "Every primary weapon, including thrown beer bottles, mid-burst against a pack"

func run() -> void:
	var game := await lab.start_game(&"scout")
	for id in WEAPONS:
		var definition := lab.weapon(id)
		game.horde.clear()
		lab.equip_weapon(id)
		var distance := 7.0 if id == "flamethrower" else 12.0
		lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(distance), 14, 2.5)
		var target := lab.ahead(distance)
		lab.aim_at(Vector3(target.x, 1.0, target.y))
		await lab.wait(0.25)
		lab.fire(true)
		# Spin-up guns need longer to reach their real cadence.
		await lab.wait(1.1 if definition.spin_up_time > 0.0 else 0.35)
		await lab.capture(id)
		lab.fire(false)
		await lab.wait(0.3)
