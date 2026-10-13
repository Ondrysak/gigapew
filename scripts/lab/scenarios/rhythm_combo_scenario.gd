extends LabScenario

func title() -> String:
	return "Earned DROP and primary-kill style"

func summary() -> String:
	return "Real kills bank one charge; manual perfect heavy spends x10; tank hits, rapid fire, silence and held fire cannot farm/spend it"

func run() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	var music := AudioServer.get_bus_index(Music.BUS)
	var master_mute := AudioServer.is_bus_mute(master)
	var music_mute := AudioServer.is_bus_mute(music)
	# Dummy audio stays silent, but real routed beat timing must be available.
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_mute(music, false)
	await _run_checks()
	AudioServer.set_bus_mute(master, master_mute)
	AudioServer.set_bus_mute(music, music_mute)

func _run_checks() -> void:
	var game := await lab.start_game()
	game.director.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.horde.target = null
	game.player.global_position = Vector3(0, 1, 12)
	await lab.frames(8)
	game.player.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	game.run_state.damage_multiplier = 1.0
	_equip(game, "rail")
	var target := _target(game, 1000000.0)
	if not await _phase(0.04):
		return
	var base := _damage(game, target)
	lab.check(is_equal_approx(base, float(game.player.weapon.damage)) and not game.player.last_drop_used, "uncharged perfect rail is ordinary damage, never free x10")
	for shot in 30:
		_damage(game, target)
	lab.check(game.player.combo_hits == 0 and game.player.drop_charge == 0.0 and game.player.arena_score == 0, "nonlethal tank hits earn neither score, STYLE nor charge")
	game.horde.damage(target, 2000000.0)
	lab.check(game.player.arena_score == 0 and game.player.drop_charge == 0.0, "external and secondary kill paths do not enter primary scoring")
	for kill in 16:
		if game.player.drop_ready:
			break
		_kill(game)
	lab.check(game.player.drop_ready and game.player.drop_charge == 1.0 and game.player.arena_score > 0, "actual primary kills bank one bounded DROP")
	var bank := game.player.drop_charge
	_kill(game)
	lab.check(game.player.drop_charge == bank, "additional real kills cannot bank a second charge")
	target = _target(game, 1000000.0)
	if not await _phase(0.5):
		return
	lab.check(is_equal_approx(_damage(game, target), base) and game.player.drop_ready, "offbeat heavy has normal damage and retains banked DROP")
	if not await _phase(0.04):
		return
	lab.check(is_equal_approx(_damage(game, target, false), base) and game.player.drop_ready, "held automatic heavy shot on perfect beat cannot spend DROP")
	_equip(game, "pulse")
	if not await _phase(0.04):
		return
	lab.check(is_equal_approx(_damage(game, target), float(game.player.weapon.damage)) and game.player.drop_ready, "fast gun preserves charge even on perfect beat")
	_equip(game, "rail")
	game.run_state.fire_rate_multiplier = 8.0
	_damage(game, target)
	lab.check(game.player.drop_ready and not game.player.last_drop_used, "accelerated heavy respects its effective rapid cadence")
	game.run_state.fire_rate_multiplier = 1.0
	var music_bus := AudioServer.get_bus_index(Music.BUS)
	var old_mute := AudioServer.is_bus_mute(music_bus)
	AudioServer.set_bus_mute(music_bus, true)
	lab.check(is_equal_approx(_damage(game, target), base) and game.player.drop_ready, "muted music cannot consume banked DROP")
	AudioServer.set_bus_mute(music_bus, old_mute)
	Music.stop(0.0)
	lab.check(is_equal_approx(_damage(game, target), base) and game.player.drop_ready, "stopped/loading clock cannot consume DROP")
	Music.play(&"stage")
	if not await _phase(0.97):
		return
	var spent := _damage(game, target)
	lab.check(is_equal_approx(spent, base * 10.0) and game.player.last_drop_used and game.player.last_rhythm_bonus == 9.0 and not game.player.drop_ready, "fresh manual early-wrap perfect heavy spends exactly one x10 DROP")
	if not await _phase(0.04):
		return
	lab.check(is_equal_approx(_damage(game, target), base) and not game.player.last_drop_used, "next uncharged perfect heavy returns to baseline")
	game.player._reset_combo()
	lab.aim_at(game.horde.weak_spot_position(target))
	var hp := game.horde._hp[target]
	game.player._shoot(false)
	lab.check(is_equal_approx(hp - game.horde._hp[target], base * (game.run_state.crit_multiplier + RunState.WEAK_SPOT_CRIT_BONUS)), "actual rail precision retains its existing multiplier without DROP")
	var removed := [0.0]
	var listener := func(_at: Vector3, amount: float, _type: int, _crit: bool, _killed: bool): removed[0] += amount
	game.horde.damage_reported.connect(listener)
	_kill(game)
	game.horde.damage_reported.disconnect(listener)
	lab.check(is_equal_approx(removed[0], 1.0), "overkill event reports only the actual remaining HP")
	await _drop_combo_credit(game)
	var score := game.player.arena_score
	var charge := game.player.drop_charge
	var original_size := lab.get_tree().root.size
	lab.get_tree().root.size = Vector2i(960, 600)
	await lab.frames(3)
	await lab.capture("earned_drop_compact")
	game._open_pause()
	await lab.wait(0.3)
	lab.check(game.player.arena_score == score and game.player.drop_charge == charge, "pause never changes earned score or charge")
	game._on_resume()
	game.player.set_physics_process(false)
	lab.get_tree().root.size = original_size

func _drop_combo_credit(game: ArenaGame) -> void:
	_equip(game, "rail")
	for kill in 16:
		if game.player.drop_ready:
			break
		_kill(game)
	_equip(game, "scatter")
	var target := _target(game, 40.0)
	var grunt := lab.enemy("robot_grunt")
	var secondary := game.horde.spawn(grunt, Vector2(0.0, 3.5), 1.0 / grunt.max_health)
	game.horde.damage(target, 1.0, Vector3.ZERO, DamageType.Kind.FIRE)
	game.horde._rebuild_grid()
	if not await _phase(0.04):
		return
	var score := game.player.arena_score
	game.player._shoot(true)
	lab.check(game.player.last_drop_used and not game.horde.is_alive(target) and not game.horde.is_alive(secondary) and game.player.arena_score > score, "a spent shotgun DROP can finish a burning target and credit its actual flame-burst victim")
	lab.check(game.player.drop_charge == 0.0, "DROP's own manual chain windfall cannot recharge the bank it just spent")
	_equip(game, "rail")
	_kill(game)
	lab.check(game.player.drop_charge > 0.0, "an independent subsequent primary kill can charge DROP again")

func _equip(game: ArenaGame, id: String) -> void:
	game.run_state.initialize_primary(lab.weapon(id))
	game.player.refresh_weapon()

func _target(game: ArenaGame, health: float) -> int:
	game.horde.clear()
	var definition := lab.enemy("robot_tank")
	var slot := game.horde.spawn(definition, Vector2(0, 6), health / definition.max_health)
	game.horde._rebuild_grid()
	lab.aim_at(game.horde.enemy_position(slot) + Vector3.UP * 0.45)
	return slot

func _kill(game: ArenaGame) -> void:
	var slot := _target(game, 1.0)
	game.player._quickdraw_left = 0.0
	game.player._shoot(false)
	lab.check(not game.horde.is_alive(slot), "primary fixture actually kills its victim")

func _damage(game: ArenaGame, target: int, manual: bool = true) -> float:
	game.player._reset_combo()
	game.player._quickdraw_left = 0.0
	var before := game.horde._hp[target]
	game.player._shoot(manual)
	return before - game.horde._hp[target]

func _phase(goal: float) -> bool:
	for frame in 1800:
		await lab.get_tree().process_frame
		var phase := Music.beat_phase()
		if phase >= 0.0:
			var distance := absf(phase - goal)
			if minf(distance, 1.0 - distance) <= 0.024:
				return true
	lab.check(false, "native audible soundtrack exposes requested perfect/offbeat timing")
	return false
