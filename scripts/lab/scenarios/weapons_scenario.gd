extends LabScenario

const WEAPONS := ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]

func title() -> String:
	return "Weapons"

func summary() -> String:
	return "Every primary weapon (beer bottles, rebar spikes, vinyl discs, pigeons, molotovs, flame) mid-burst against a pack, plus a close-range flight strip"

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
		if id == "flamethrower":
			continue
		# Close targets keep the pooled projectiles large and in frame.
		game.horde.clear()
		lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(6.0), 8, 1.5)
		var near := lab.ahead(6.0)
		lab.aim_at(Vector3(near.x, 1.0, near.y))
		await lab.wait(0.2)
		if definition.fire_interval >= 0.19:
			# One shot, so the capture lands while its projectiles are still in the air.
			lab.fire(true)
			await lab.frames(2)
			lab.fire(false)
			await lab.capture(id + "_flight")
		else:
			lab.fire(true)
			await lab.wait(0.6 if definition.spin_up_time > 0.0 else 0.2)
			await lab.capture(id + "_flight")
		lab.fire(false)
		await lab.wait(0.3)
