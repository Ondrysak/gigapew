extends LabScenario

func title() -> String:
	return "Gunplay rotation"

func summary() -> String:
	return "Focused fire, empty-magazine swaps, holstered reloads, cross-charge and contextual mining"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	player.global_position = Vector3(0, 1, 12)
	game.horde.target = null
	var definitions: Array[WeaponDefinition] = [lab.weapon("pulse"), lab.weapon("rail"), lab.weapon("scatter")]
	game.run_state.initialize_hands(definitions)
	player.weapons = game.run_state.hand_definitions()
	player.refresh_weapons()
	game.hud.set_hands(game.run_state, 0)
	var target := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 6), 100.0)
	await lab.frames(3)
	lab.aim_at(game.horde.enemy_position(target))
	var focused_charge := player.secondary_charge[0]
	var other_charge := player.secondary_charge[1]
	var aim_before := player.head.global_basis
	lab.fire(true)
	await lab.wait(0.7)
	lab.fire(false)
	lab.check(player.ammo(0) < definitions[0].magazine_size, "focused trigger consumes the active magazine")
	lab.check(player.ammo(1) == definitions[1].magazine_size and player.ammo(2) == definitions[2].magazine_size, "offhands never fire with the focused trigger")
	lab.check(player.secondary_charge[1] > other_charge and is_equal_approx(player.secondary_charge[0], focused_charge), "landed fire charges only the other guns")
	lab.check(player.head.global_basis.is_equal_approx(aim_before), "sustained shooting never drifts aim")
	await lab.capture("focused")
	var remaining := player.ammo(0)
	var reserve_before := player.reserve_ammo(0)
	var charge_before := player.secondary_charge[1]
	game.run_state.hands[0].upgrade(&"damage")
	player.weapons = game.run_state.hand_definitions()
	player.refresh_weapons()
	lab.check(player.ammo(0) == remaining and player.reserve_ammo(0) == reserve_before \
			and is_equal_approx(player.secondary_charge[1], charge_before), "upgrades preserve magazine, reserves and cross-charge")
	player.select_weapon(1)
	lab.fire(true)
	await lab.wait(0.08)
	lab.check(player.ammo(1) == definitions[1].magazine_size, "swap draw window prevents instant double fire")
	await lab.wait(0.25)
	lab.fire(false)
	lab.check(player.ammo(1) < definitions[1].magazine_size, "draw finishes and the new gun fires")
	await lab.wait(definitions[0].reload_time + 0.1)
	lab.check(player.ammo(0) == definitions[0].magazine_size and remaining < player.ammo(0), "holstered partial magazine refills while another gun is held")
	lab.check(player.reserve_ammo(0) == reserve_before - (definitions[0].magazine_size - remaining), "partial reload consumes exactly the missing rounds from reserve")
	player.select_weapon(2)
	await lab.wait(0.3)
	lab.fire(true)
	await lab.wait(3.5)
	lab.fire(false)
	lab.check(player.selected_weapon == 0 and player.ammo(2) == 0 and player.is_reloading(2), "empty primary automatically swaps to the next loaded gun and reloads the holstered gun")
	await lab.capture("auto_swap")
	await lab.wait(definitions[2].reload_time + 0.1)
	lab.check(player.ammo(2) == definitions[2].magazine_size, "empty holstered gun reloads automatically")
	await lab.capture("rotation_ready")
	# RMB on a deposit is a drill, even with a full alternate meter.
	var deposit: MineralDeposit
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.global_position.y < 2.4:
			deposit = node
			break
	lab.check(deposit != null, "contextual mining has a reachable stage deposit")
	if deposit != null:
		lab.check(await lab.aim_deposit(deposit, 2.2), "mining setup aims at a live crystal section, not the geode's hollow")
		player.secondary_charge[0] = 60.0
		var fired := [0]
		player.secondary_fired.connect(func(_hand: int): fired[0] += 1)
		Input.action_press("mine")
		await lab.wait(0.65)
		lab.check(player.drilling() and player.secondary_charge[0] > 60.0 and fired[0] == 0, "deposit RMB drills and charges the focused gun without firing alternate")
		await lab.capture("drill_charge")
		Input.action_release("mine")
