extends LabScenario

func title() -> String:
	return "Single-primary gunplay"

func summary() -> String:
	return "Unlimited fire, forgiving hit-chain grace/decay, unchanged damage bonus, weapon upgrades, stable aim and menu input guards"

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

	var chain: int = player.combo_hits
	lab.check(chain >= 7, "real sustained direct hits build a capped-bonus chain")
	await lab.wait(3.0)
	lab.check(player.combo_hits == chain, "a three-second movement gap preserves the full hit chain")
	await lab.capture("combo_grace")
	var remaining: float = player._combo_left
	lab.aim_at(player.camera.global_position + Vector3.UP * 10.0)
	player._shoot()
	lab.check(player.combo_hits == chain and is_equal_approx(player._combo_left, remaining), "an actual missed shot neither erases nor refreshes the chain")
	var health_before: int = player.health
	player._invulnerable = 0.0
	player.take_damage(1)
	lab.check(player.health == health_before - 1 and player.combo_hits == chain - 2, "real nonlethal damage costs two beats rather than the whole chain")
	player.grant_invulnerability(1.0e9)
	chain = player.combo_hits
	await _wait_decay(player)
	var first_decay := maxi(0, chain - maxi(1, ceili(chain * 0.1)))
	lab.check(player.combo_hits == first_decay and first_decay > 0, "idle expiry removes only one ten-percent step instead of wiping the chain")
	await lab.capture("combo_decay")
	await _wait_decay(player)
	var second_decay := maxi(0, first_decay - maxi(1, ceili(first_decay * 0.1)))
	lab.check(player.combo_hits == second_decay, "idle decay continues gradually at the next interval")
	var body := game.horde.enemy_position(target) + Vector3.UP * 0.45
	player.global_position = game.horde.enemy_position(target) + Vector3(0, 1, 6)
	await lab.frames(2)
	lab.aim_at(body)
	game.horde._hp[target] = 10000.0
	var damage_before: float = game.horde._hp[target]
	player._shoot()
	lab.check(player.combo_hits == second_decay + 1 and game.horde._hp[target] < damage_before, "a fresh real hit resumes the decaying chain")
	lab.check(absf((damage_before - game.horde._hp[target]) - player.weapon.damage * game.run_state.damage_multiplier * 1.4) < 0.05, "the next real body shot retains the existing forty-percent bonus cap")
	chain = player.combo_hits
	await lab.wait(3.0)
	lab.check(player.combo_hits == chain, "a renewed hit restores the full grace period")
	await lab.capture("combo_renewed")

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
	var paused_chain: int = player.combo_hits
	var paused_grace: float = player._combo_left
	lab.check(shots[0] == count, "paused held trigger cannot shoot")
	game._on_resume()
	lab.check(player.combo_hits == paused_chain and is_equal_approx(player._combo_left, paused_grace), "pause preserves both combo count and remaining decay time")
	await lab.wait(0.35)
	lab.check(shots[0] == count, "a held menu click does not fire when play resumes")
	lab.fire(false)
	await lab.frames(2)
	lab.fire(true)
	await lab.wait(0.45)
	lab.fire(false)
	lab.check(shots[0] > count, "release and a fresh trigger press restores firing after the menu")

func _wait_decay(player: ArenaPlayer) -> void:
	var before := player.combo_hits
	for frame in 600:
		await lab.get_tree().physics_frame
		if player.combo_hits < before:
			return
	lab.check(false, "an idle hit chain eventually decays")
