extends LabScenario

func title() -> String:
	return "Boss"

func summary() -> String:
	return "Robot and alien bosses: arrival, fight, low health, kill without bypassing an unfinished contract"

func run() -> void:
	for stage in [0, 2]:
		await _fight(stage)

func _fight(stage: int) -> void:
	if is_instance_valid(lab.game):
		lab.game.free()
	var game := await lab.start_game(&"gunner", stage)
	var schedule := game.campaign[stage].schedule
	var tag := "robot" if stage == 0 else "alien"
	game.director.boss_phase = true
	var boss_at := lab.ahead(15.0)
	var slot := game.horde.spawn(schedule.boss, boss_at, schedule.boss_health_multiplier)
	lab.check(slot >= 0 and game.horde.boss_index == slot, "%s boss spawned and is tracked" % tag)
	for wave in schedule.waves.slice(0, 2):
		lab.spawn_pack(wave.enemy, lab.ahead(11.0, 5.0), 6, 2.0)
	lab.aim_at(game.horde.weak_spot_position(slot))
	await lab.wait(0.8)
	await lab.capture("%s_arrival" % tag)
	lab.check(game.hud.boss_panel.visible and game.hud.warning.visible, "%s boss frame and WARNING banner are up on arrival" % tag)
	lab.fire(true)
	await lab.wait(1.0)
	lab.aim_at(game.horde.weak_spot_position(slot))
	await lab.capture("%s_fight" % tag)
	lab.fire(false)
	var maximum := schedule.boss.max_health * schedule.boss_health_multiplier
	game.horde.damage(slot, maxf(0.0, maximum * game.horde.enemy_health_fraction(slot) - maximum * 0.12))
	await lab.wait(0.3)
	await lab.capture("%s_low" % tag)
	game.horde.damage(slot, maximum)
	await lab.wait(0.6)
	lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not game.quests.is_complete(), "%s boss death cannot bypass unfinished mining and kill objectives" % tag)
	await lab.capture("%s_cleared" % tag)
