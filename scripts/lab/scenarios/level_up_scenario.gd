extends LabScenario

func title() -> String:
	return "Level-up"

func summary() -> String:
	return "Upgrade cards: new picks of every kind, ranked picks, overclock, choosing"

func run() -> void:
	var game := await lab.start_game(&"engineer")
	var state := game.run_state
	var by_kind := {}
	for upgrade in game.upgrade_pool.upgrades:
		if not by_kind.has(upgrade.kind):
			by_kind[upgrade.kind] = []
		(by_kind[upgrade.kind] as Array).append(upgrade)
	var weapon: UpgradeDefinition = by_kind[UpgradeDefinition.Kind.WEAPON][0]
	var perk: UpgradeDefinition = by_kind[UpgradeDefinition.Kind.PERK][0]
	var mod: UpgradeDefinition = by_kind[UpgradeDefinition.Kind.GUN_MOD][0]
	var stat: UpgradeDefinition = by_kind[UpgradeDefinition.Kind.STAT][0]
	await _present(game, [weapon, perk, mod], 0.12)
	await lab.capture("entrance")
	await lab.wait(0.4)
	await lab.capture("new_picks")
	for card in game.level_up._cards:
		lab.check(card.icon_rect.texture != null, "%s card shows an icon" % card.name_label.text)
	# Mixed: an owned perk mid-rank, an instant supply pick and a new stat.
	state.apply_upgrade(perk)
	var mixed: Array[UpgradeDefinition] = [perk]
	for upgrade in game.upgrade_pool.upgrades:
		if upgrade.repeatable:
			mixed.append(upgrade)
			break
	mixed.append(by_kind[UpgradeDefinition.Kind.STAT][1])
	await _present(game, mixed)
	await lab.capture("mixed_picks")
	# Ranked: an owned weapon one level from max, an owned stat, and its overclock.
	for n in weapon.max_level - 1:
		state.apply_upgrade(weapon)
	state.apply_upgrade(stat)
	var overclock: UpgradeDefinition = null
	for upgrade in by_kind.get(UpgradeDefinition.Kind.OVERCLOCK, []):
		if upgrade.overclock_target == weapon:
			overclock = upgrade
	var ranked: Array[UpgradeDefinition] = [weapon, stat]
	if overclock != null:
		ranked.append(overclock)
	await _present(game, ranked)
	await lab.capture("ranked_picks")
	var before := state.level_of(weapon)
	game.level_up._arming = 0.0
	game.level_up._choose(0)
	await lab.wait(0.6)
	lab.check(state.level_of(weapon) == before + 1, "choosing card 1 levels %s to %d" % [weapon.display_name, before + 1])
	lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not game.get_tree().paused, "choosing resumes play")
	await lab.capture("after_pick")

func _present(game: ArenaGame, offers: Array, settle: float = 0.5) -> void:
	var typed: Array[UpgradeDefinition] = []
	typed.assign(offers)
	game.round_state = ArenaGame.RoundState.LEVEL_UP
	game.get_tree().paused = true
	game.level_up.present(typed, game.run_state)
	await lab.wait(settle)
