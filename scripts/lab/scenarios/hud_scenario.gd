extends LabScenario

func title() -> String:
	return "HUD"

func summary() -> String:
	return "In-run HUD: loot and XP, gear and cooldown, surrounded, low health, death screen"

func run() -> void:
	var game := await lab.start_game(&"scout")
	var state := game.run_state
	for definition in game.resources:
		state.add_resource(definition, 12)
	state.add_xp(float(state.xp_required) * 0.6)
	lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(9.0), 14, 3.0)
	lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(-9.0), 14, 3.0)
	lab.spawn_pack(lab.enemy("robot_runner"), lab.ahead(0.0, 10.0), 8, 2.0)
	var target := lab.ahead(9.0)
	lab.aim_at(Vector3(target.x, 1.0, target.y))
	await lab.wait(0.8)
	await lab.capture("play")
	# Gear: shop armor, per-hand upgrades, a gun mod, focus on hand 2, ability cooling down.
	state.buy_shop_stat(&"armor")
	state.buy_shop_stat(&"armor")
	state.hands[1].upgrade(&"fire")
	state.hands[1].upgrade(&"projectiles")
	state.hands[1].upgrade(&"damage")
	state.hands[2].upgrade(&"pierce")
	for upgrade in game.upgrade_pool.upgrades:
		if upgrade.kind == UpgradeDefinition.Kind.GUN_MOD:
			game.grant_upgrade(upgrade)
			break
	var player := game.player
	player.select_weapon(1)
	game.hud.set_hands(state, 1)
	if player.ability != null:
		player.ability._cooldown = player.ability.cooldown_total() * 0.6
	await lab.wait(0.3)
	lab.check(game.hud.armor_box.visible, "armor readout appears once armor > 0")
	lab.check(game.hud.mod_row.get_child_count() > 0, "installed gun mod shows in the hands header")
	await lab.capture("gear")
	player._invulnerable = 0.0
	player.take_damage(player.health - 18)
	await lab.wait(0.15)
	await lab.capture("low_health")
	player.take_damage(999)
	await lab.wait(0.6)
	lab.check(game.round_state == ArenaGame.RoundState.LOST, "lethal damage ends the run")
	await lab.capture("dead")
