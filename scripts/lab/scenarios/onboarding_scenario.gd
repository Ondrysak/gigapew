extends LabScenario

## Guided start through the real campaign: one skill at first, the rest
## revealed by level with callouts and tips; a small first contract and a calm
## arrival; early level-ups without perks or gun mods; tips once per profile;
## and the experienced mode (Guided start off) showing everything at once.

func title() -> String:
	return "Guided start"

func summary() -> String:
	return "Gradual skills, small first contract, spawn grace, gated upgrades and one-time tips"

func run() -> void:
	var game := await lab.start_game(&"driller", 0, true, 8721, true)
	await lab.wait(0.6)
	var state := game.run_state
	var hud := game.hud
	lab.check(state.guided and state.unlocked_abilities == 1, "a guided run starts with only the first skill")
	lab.check(_tile_visible(hud, 0) and _tile_visible(hud, 1) and not _tile_visible(hud, 2) and not _tile_visible(hud, 4), "the HUD shows skill 1 and a teaser for skill 2 only")
	lab.check(hud.tutor.visible and hud.tutor.showing == &"basics" and not Profile.tip_seen(&"basics"), "the first tip explains moving and shooting")
	await lab.capture("arrival")
	await lab.wait(Tutor.SEEN_AFTER + 0.1)
	lab.check(Profile.tip_seen(&"basics"), "a tip counts as seen only after staying on screen")
	# Locked keys do nothing.
	await _key(1)
	lab.check(game.player.abilities[1].cooldown_remaining() == 0.0, "pressing a locked skill's key does nothing")
	# Calm arrival with the real director.
	game.horde.clear()
	game.director.set_physics_process(true)
	var grace := game.director.grace
	await lab.wait(1.0)
	lab.check(grace > 10.0 and game.horde.alive_count == 0 and game.director.grace < grace, "the first sector opens with a calm before spawning (%.0fs)" % grace)
	game.director.grace = 0.01
	await lab.wait(1.5)
	lab.check(game.horde.alive_count > 0, "spawning starts once the calm ends")
	game.director.set_physics_process(false)
	game.horde.clear()
	_check_offers(game, false)
	# The round shop shows locked skills by their unlock level.
	game._finish_stage_clear()
	await lab.wait(0.5)
	var card: Dictionary = game.round_shop._abilities[2]
	lab.check(card.buy.disabled, "the shop cannot purchase a locked skill")
	await lab.capture("shop_locked_skills")
	game.free()
	# A fresh guided run: leveling reveals skills one by one.
	game = await lab.start_game(&"scout", 0, true, 8721, true)
	await lab.wait(0.3)
	state = game.run_state
	hud = game.hud
	lab.check(not hud.tutor.visible or hud.tutor.showing != &"basics", "a seen tip never repeats on a later run")
	state.add_xp(state.xp_required - state.xp)
	await lab.wait(0.2)
	lab.check(state.level == 2 and state.unlocked_abilities == 2 and _tile_visible(hud, 1), "level 2 unlocks skill 2 on the HUD")
	await lab.capture("skill_unlocked")
	game.player.abilities[1]._cooldown = 0.0
	await _key(1)
	lab.check(game.player.abilities[1].cooldown_remaining() > 0.0, "the newly unlocked key now activates its skill")
	while state.level < RunState.ABILITY_UNLOCK_LEVELS[4]:
		state.add_xp(state.xp_required - state.xp)
	await lab.wait(0.2)
	lab.check(state.unlocked_abilities == 5, "level %d completes the five-skill kit" % state.level)
	lab.check(_tip_pending(hud, &"combos"), "owning Gravity Well and Pulse Barrier queues the combo tip")
	_check_offers(game, true)
	game.free()
	# Experienced mode: everything at once and no tips.
	game = await lab.start_game(&"scout", 0, true, 8721, false)
	await lab.wait(0.3)
	lab.check(not game.run_state.guided and game.run_state.unlocked_abilities == 5 and _tile_visible(game.hud, 4), "with Guided start off every skill is available immediately")
	game.hud.tutor.offer(&"mining")
	lab.check(not game.hud.tutor.visible and game.hud.tutor._queue.is_empty(), "with Guided start off no tips appear")

func _check_offers(game: ArenaGame, late: bool) -> void:
	var state := game.run_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var perks := 0
	var mods := 0
	var locked_skills := 0
	for _roll in 60:
		for offer in state.roll_offers(game.upgrade_pool, 3, rng):
			if offer.kind == UpgradeDefinition.Kind.PERK:
				perks += 1
			elif offer.kind == UpgradeDefinition.Kind.GUN_MOD:
				mods += 1
			elif offer.kind == UpgradeDefinition.Kind.ABILITY and not state.is_ability_unlocked(offer.ability_slot):
				locked_skills += 1
	if late:
		lab.check(perks > 0 and mods > 0 and locked_skills == 0, "by level %d perks and gun mods join the level-up cards" % state.level)
	else:
		lab.check(perks == 0 and mods == 0 and locked_skills == 0, "level-1 cards offer no perks, gun mods or locked skills")

func _tile_visible(hud: Node, slot: int) -> bool:
	return (hud._ability_tiles[slot].root as Control).visible

func _tip_pending(hud: Node, id: StringName) -> bool:
	if hud.tutor.showing == id:
		return true
	for queued: Dictionary in hud.tutor._queue:
		if queued.id == id:
			return true
	return false

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
