extends LabScenario

func title() -> String:
	return "Five hero abilities"

func summary() -> String:
	return "Physical 1–5 inputs, every class kit, real combat effects, independent protection and skill ranks"

func run() -> void:
	for definition in Profile.roster.classes:
		var class_id: StringName = definition.id
		if is_instance_valid(lab.game):
			lab.game.free()
		var game := await lab.start_game(class_id)
		game.horde.target = null
		game.horde.set_physics_process(false)
		for slot in range(5):
			_prepare(game)
			var skill := game.player.abilities[slot]
			var before := _snapshot(game)
			await _key(slot)
			await lab.wait(0.07)
			await lab.capture("%s_%d_%s" % [class_id, slot + 1, game.run_state.ability_scenes[slot].resource_path.get_file().get_basename()])
			await lab.wait(1.3 if skill is RepairDrone or skill is PlatformTurret else 0.75)
			_check_effect(game, skill, before)
		await _independent_skills(game)
		if class_id == &"gunner":
			await _overlapping_protection(game)
		if class_id == &"scout":
			await _ranked_barrier(game)

func _prepare(game: ArenaGame) -> void:
	Input.action_release(&"fire")
	Input.action_release(&"mine")
	for skill in game.player.abilities:
		skill.cancel()
		skill._cooldown = 0.0
	game.horde.clear()
	game.player.active = true
	game.player._dash_time = 0.0
	game.player._invulnerable = 0.0
	game.player.velocity = Vector3.ZERO
	game.player.global_position = Vector3(0, 1, 12)
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO
	game.player.health = game.player.max_health - 30
	game.player.health_changed.emit(game.player.health, game.player.max_health)
	for at in [Vector2(0, 8.5), Vector2(0, 10.6), Vector2(-2, 9), Vector2(2, 9), Vector2(0, 6), Vector2(-4, 5), Vector2(4, 5)]:
		game.horde.spawn(lab.enemy("robot_tank"), at, 1000.0)
	game.horde._rebuild_grid()
	lab.aim_at(Vector3(0, 0.8, 8.5))

func _snapshot(game: ArenaGame) -> Dictionary:
	return {"position": game.player.global_position, "health": game.player.health,
		"hp": _enemy_hp(game.horde), "fire": game.run_state.fire_rate_multiplier,
		"cooldown": game.run_state.cooldown_multiplier}

func _check_effect(game: ArenaGame, skill: ActiveAbility, before: Dictionary) -> void:
	var prefix := "%s / %s" % [game.class_definition.display_name, skill.display_name]
	if skill is BlinkDash or skill is DrillDash or skill is GrappleVault:
		lab.check(game.player.global_position.distance_to(before.position) > 1.0, prefix + " moves the real player through the arena")
	elif skill is ReconFlare:
		lab.check(game.run_state.exposure_scale(Vector3(0, 0.8, 8.5)) > 1.0 and _enemy_hp(game.horde) < before.hp, prefix + " marks the real aimed enemy lane for stronger gun hits")
	elif skill is BattleFrenzy:
		lab.check(game.run_state.fire_rate_multiplier > before.fire and game.run_state.pierce_bonus > 0, prefix + " improves live primary cadence and penetration")
	elif skill is Overdrive:
		lab.check(game.run_state.cooldown_multiplier < before.cooldown, prefix + " accelerates actual automated-weapon recharge")
	elif skill is RepairDrone:
		lab.check(game.player.health > before.health and _enemy_hp(game.horde) < before.hp, prefix + " restores missing HP and zaps nearby enemies")
	elif skill is Bulwark or skill is PulseBarrier:
		var health := game.player.health
		game.player.take_damage(8)
		lab.check(game.player.health == health and _enemy_hp(game.horde) < before.hp, prefix + " blocks actual incoming damage and repels the nearby crowd")
	else:
		lab.check(_enemy_hp(game.horde) < before.hp, prefix + " damages actual enemies rather than only drawing effects")

func _independent_skills(game: ArenaGame) -> void:
	_prepare(game)
	# The barrier is cast beyond collapse reach so both skills stay independent.
	await _key(3)
	var gravity := game.player.abilities[3] as GravityWell
	await lab.wait(0.1)
	var gravity_cooldown := gravity.cooldown_remaining()
	game.player.global_position = Vector3(0, 1, 26)
	await _key(4)
	var barrier := game.player.abilities[4] as PulseBarrier
	var health := game.player.health
	game.player.take_damage(9)
	lab.check(gravity._remaining > 0.0 and barrier._remaining > 0.0 and game.player.health == health, "keys 4 and 5 coexist as an enemy control field and real player protection beyond collapse reach")
	lab.check(gravity.cooldown_remaining() <= gravity_cooldown and not gravity.is_ready() and not barrier.is_ready(), "activating another skill does not reset or bypass the first skill's cooldown")
	var left := gravity._remaining
	var shield_left := barrier._remaining
	var hp := _enemy_hp(game.horde)
	var cooldown := barrier.cooldown_remaining()
	game.get_tree().paused = true
	await _key(4)
	await lab.wait(0.25)
	lab.check(gravity._remaining == left and barrier._remaining == shield_left and barrier.cooldown_remaining() == cooldown and _enemy_hp(game.horde) == hp, "pause freezes ability effects/cooldowns and rejects numeric activation")
	game.get_tree().paused = false
	await lab.capture("%s_control_and_barrier" % game.class_definition.id)
	game.player.active = false
	await lab.wait(0.1)
	lab.check(gravity._remaining == 0.0 and barrier._remaining == 0.0 and not game.player.is_invulnerable(), "inactive player cancels fields and releases their protection")
	game.player.active = true

func _overlapping_protection(game: ArenaGame) -> void:
	_prepare(game)
	await _key(0)
	await _key(4)
	var bulwark := game.player.abilities[0] as Bulwark
	var barrier := game.player.abilities[4] as PulseBarrier
	await lab.wait(barrier.duration + 0.2)
	var health := game.player.health
	game.player.take_damage(10)
	lab.check(barrier._remaining == 0.0 and bulwark.is_shielded() and game.player.health == health, "a short barrier expiry cannot remove another active shield's protection")
	bulwark.cancel()
	game.player.take_damage(10)
	lab.check(game.player.health < health, "ending the final shield restores actual incoming damage")

func _ranked_barrier(game: ArenaGame) -> void:
	_prepare(game)
	var barrier := game.player.abilities[4] as PulseBarrier
	var slot := game.horde.nearest(Vector3(0, 0.8, 8.5), 1.0)
	var hp := game.horde._hp[slot]
	await _key(4)
	var damage := hp - game.horde._hp[slot]
	var cooldown := barrier.cooldown_total()
	barrier.cancel()
	var offer := game.run_state.ability_upgrade_offer(4)
	game.grant_upgrade(offer)
	_prepare(game)
	slot = game.horde.nearest(Vector3(0, 0.8, 8.5), 1.0)
	hp = game.horde._hp[slot]
	await _key(4)
	lab.check(is_equal_approx(hp - game.horde._hp[slot], damage * 1.25) and is_equal_approx(barrier.cooldown_total(), cooldown * 0.88), "an earned skill rank improves real pulse damage and independent recharge")
	await lab.wait(barrier.duration + 0.05)
	var health := game.player.health
	game.player.take_damage(10)
	lab.check(barrier._remaining > 0.0 and game.player.health == health, "ranked barrier remains protective past its base duration")
	await lab.capture("ranked_barrier")
	await lab.wait(0.3)
	game.player.take_damage(10)
	lab.check(barrier._remaining == 0.0 and game.player.health < health, "the upgraded barrier still expires and releases incoming damage")

func _key(slot: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_1 + slot
	event.keycode = KEY_1 + slot
	event.pressed = true
	Input.parse_input_event(event)
	await lab.get_tree().physics_frame
	await lab.get_tree().physics_frame
	event.pressed = false
	Input.parse_input_event(event)
	await lab.get_tree().process_frame

func _enemy_hp(horde: Horde) -> float:
	var total := 0.0
	for active in horde._active_count:
		var slot := horde._active[active]
		if horde.is_alive(slot):
			total += horde._hp[slot]
	return total
