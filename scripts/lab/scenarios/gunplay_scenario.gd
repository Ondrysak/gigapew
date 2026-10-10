extends LabScenario

func title() -> String:
	return "Single-primary gunplay"

func summary() -> String:
	return "Unlimited sustained fire, weapon swaps retain upgrades, stable aim and menu input guards"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	player.global_position = Vector3(0, 1, 12)
	lab.equip_weapon("pulse")
	var target := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 6), 1000.0)
	await lab.wait(0.3)
	lab.aim_at(game.horde.enemy_position(target))
	var shots := [0]
	player.shot_fired.connect(func(): shots[0] += 1)
	var aim_before := player.head.global_basis
	var hp_before := game.horde._hp[target]
	lab.fire(true)
	await lab.wait(5.0)
	var first: int = shots[0]
	await lab.wait(2.0)
	lab.fire(false)
	lab.check(first >= 40 and shots[0] - first >= 15 and game.horde._hp[target] < hp_before, "primary continues actual damaging fire through a sustained burst without reloading")
	lab.check(player.head.global_basis.is_equal_approx(aim_before), "sustained shooting never drifts aim")
	await lab.capture("unlimited_fire")

	var build := game.run_state.primary
	build.upgrade(&"damage")
	build.upgrade(&"cadence")
	build.upgrade(&"projectiles")
	build.upgrade(&"frost")
	var rail := lab.weapon("rail")
	lab.check(game.run_state.swap_primary(rail), "a different main firearm can replace the equipped primary")
	player.refresh_weapon()
	lab.check(build.definition.damage == roundi(rail.damage * 1.2) and is_equal_approx(build.definition.fire_interval, rail.fire_interval / 1.15), "swapping reapplies damage and cadence ranks to the replacement's own base stats")
	lab.check(build.definition.pellet_count == rail.pellet_count + 2 and build.definition.damage_type == DamageType.Kind.FROST, "payload and elemental primary upgrades survive a swap")
	var upgraded_damage := build.definition.damage
	player.cycle_weapon(1)
	player.cycle_weapon(-1)
	lab.check(player.weapon.damage == upgraded_damage and build.rank(&"damage") == 1, "cycling back never compounds purchased upgrade ranks")
	await lab.capture("upgraded_swap")

	game._open_pause()
	var count: int = shots[0]
	Input.action_press(&"fire")
	await lab.wait(0.3)
	lab.check(shots[0] == count, "paused held trigger cannot shoot")
	game._on_resume()
	await lab.wait(0.35)
	lab.check(shots[0] == count, "a held menu click does not fire when play resumes")
	lab.fire(false)
	await lab.frames(2)
	lab.fire(true)
	await lab.wait(0.45)
	lab.fire(false)
	lab.check(shots[0] > count, "release and a fresh trigger press restores firing after the menu")
