extends LabScenario

const GUNS := ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]

func title() -> String:
	return "Alternate fire"

func summary() -> String:
	return "Six real RMB modes: expose, charged lance, stagger, overspin, grenade, napalm; mining shots"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	for id in GUNS:
		player.cancel_secondaries()
		game.horde.clear()
		player.global_position = Vector3(0, 1, 12)
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3.ZERO
		var definitions: Array[WeaponDefinition] = [lab.weapon(id), lab.weapon("rail"), lab.weapon("scatter")]
		game.run_state.initialize_hands(definitions)
		player.weapons = game.run_state.hand_definitions()
		player.refresh_weapons()
		player.select_weapon(0)
		game.hud.set_hands(game.run_state, 0)
		var range_m := 4.0 if id == "scatter" else 7.0
		var target := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 12 - range_m), 100.0)
		await lab.wait(0.35)
		lab.aim_at(game.horde.enemy_position(target))
		player.secondary_charge[0] = 100.0
		var before := game.horde.enemy_health_fraction(target)
		if id == "rail":
			# A cancelled charge never spends energy or fires a weak fake lance.
			Input.action_press("mine")
			await lab.wait(0.2)
			Input.action_release("mine")
			await lab.frames(2)
			lab.check(is_equal_approx(player.secondary_charge[0], 100.0) and is_equal_approx(game.horde.enemy_health_fraction(target), before), "early lance release cancels without damage or charge cost")
			Input.action_press("mine")
			await lab.wait(0.2)
			player.select_weapon(1)
			await lab.wait(0.75)
			Input.action_release("mine")
			await lab.frames(2)
			lab.check(is_equal_approx(player.secondary_charge[0], 100.0) and is_equal_approx(game.horde.enemy_health_fraction(target), before), "swapping during lance charge cancels without a delayed shot")
			player.select_weapon(0)
			await lab.wait(0.25)
		if id == "minigun":
			lab.fire(true)
			await lab.wait(0.9)
			var start := player.ammo(0)
			await lab.wait(0.7)
			var normal := start - player.ammo(0)
			lab.fire(false)
			Input.action_press("mine")
			await lab.frames(2)
			Input.action_release("mine")
			start = player.ammo(0)
			lab.fire(true)
			await lab.wait(0.7)
			lab.fire(false)
			lab.check(start - player.ammo(0) >= normal * 1.6, "Overspin increases actual shot cadence after spin-up")
			await lab.capture(id)
		elif id == "rail":
			Input.action_press("mine")
			await lab.wait(0.85)
			await lab.capture("rail_charging")
			Input.action_release("mine")
			await lab.frames(2)
			await lab.capture("rail_lance")
		else:
			Input.action_press("mine")
			await lab.frames(2)
			Input.action_release("mine")
			await lab.wait(0.12 if id == "pulse" else 0.04 if id == "scatter" else 0.65)
			await lab.capture(id)
		lab.check(player.secondary_charge[0] == 0.0, "%s consumes the focused alternate meter exactly once" % id)
		lab.check(game.horde.enemy_health_fraction(target) < before, "%s alternate deals real damage" % id)
		if id == "pulse":
			lab.check(game.horde.is_exposed(target), "Tag Burst exposes the target for other guns")
			player.select_weapon(1)
			await lab.wait(0.25)
			var hp := game.horde._hp[target]
			game.run_state.crit_chance = 0.0
			player._reset_combo()
			lab.aim_at(Vector3(0, 0.65, 5))
			player._shoot(1)
			lab.check(is_equal_approx(hp - game.horde._hp[target], player.weapons[1].damage * game.run_state.damage_multiplier * 1.35), "a swapped Rail body hit uses Tag Burst's +35% window")
			player.select_weapon(0)
			await lab.wait(4.1)
			lab.check(not game.horde.is_exposed(target), "Tag Burst's damage window expires")
		if id == "scatter":
			lab.check(game.horde.is_stunned(target), "Concussion applies stagger to a regular enemy")
			game.horde._knock[target] = Vector2.ZERO
			var position := game.horde.enemy_position(target)
			game.horde.target = player
			await lab.wait(0.2)
			lab.check(game.horde.enemy_position(target).distance_to(position) < 0.01, "stagger suspends pursuit even when the player is a live target")
			game.horde.target = null
			var boss := game.horde.spawn(lab.enemy("robot_boss"), Vector2(6, 4), 10.0)
			game.horde.stun(boss, 1.2)
			await lab.wait(0.4)
			lab.check(not game.horde.is_stunned(boss) and game.horde.is_stunned(target), "boss stagger expires before regular-enemy stagger")
			await lab.wait(0.8)
			lab.check(not game.horde.is_stunned(target), "regular stagger also expires")
		if id == "flamethrower":
			var hp := game.horde.enemy_health_fraction(target)
			await lab.wait(0.8)
			lab.check(game.horde.enemy_health_fraction(target) < hp and game.horde._slow_time[target] > 0.0, "Napalm persists, burns and slows after the projectile lands")
			await lab.capture("napalm_patch")
		await lab.wait(0.3)
	# Special shots interact with the actual mineral collider, outside drill range.
	game.horde.clear()
	for id in ["rail", "autocannon"]:
		var deposit: MineralDeposit
		for node in game.deposits.get_children():
			if node is MineralDeposit and node.global_position.y < 2.4 and node.health > 0.0:
				deposit = node
				break
		if deposit == null:
			lab.check(false, "mining alternate has a reachable deposit")
			continue
		var definitions: Array[WeaponDefinition] = [lab.weapon(id), lab.weapon("pulse"), lab.weapon("scatter")]
		game.run_state.initialize_hands(definitions)
		player.weapons = game.run_state.hand_definitions()
		player.refresh_weapons()
		player.select_weapon(0)
		await lab.wait(0.4)
		lab.check(await lab.aim_deposit(deposit, 5.0), "%s aims at a live mineral collider" % id)
		if id == "autocannon":
			# Compensate the real launch impulse and gravity, not a hitscan proxy.
			var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, player.camera.global_position - player.head.global_basis.z * 12.0, 0xFFFFFFFF, [player.get_rid()])
			var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var point: Vector3 = hit["position"]
				var flight := player.camera.global_position.distance_to(point) / 19.0
				lab.aim_at(point - Vector3.UP * (2.0 * flight - 4.5 * flight * flight))
		player.secondary_charge[0] = 100.0
		var hp := deposit.health
		Input.action_press("mine")
		await lab.wait(0.85 if id == "rail" else 0.05)
		Input.action_release("mine")
		await lab.wait(0.6)
		lab.check(deposit.health < hp, "%s alternate fractures an actual mineral section outside drill reach" % id)
		await lab.capture(id + "_mining")
