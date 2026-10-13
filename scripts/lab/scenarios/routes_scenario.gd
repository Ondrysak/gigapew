extends LabScenario

func title() -> String:
	return "Drafted guns and linked venue fights"

func summary() -> String:
	return "Real initial draft, atomic cancellation, route choice, physical doorway arrival and combat-time loadout restriction"

func run() -> void:
	var game := await lab.start_game(&"scout", 0, true, 5501, false, false)
	var draft := game.weapon_draft
	var initial := game.run_state.primary.source
	var pulse := lab.weapon("pulse")
	var scatter := lab.weapon("scatter")
	lab.check(game.round_state == ArenaGame.RoundState.DRAFT and lab.get_tree().paused and not draft.cancel(), "the initial run waits for a pair and cannot cancel back into an undrafted run")
	lab.check(not draft.select_pair(pulse, pulse) and game.run_state.primary.source == initial, "a duplicate draft is rejected without altering the equipped source")
	lab.check(draft.select_pair(pulse, scatter) and game.run_state.primary.source == initial, "a valid pending pair does not equip before confirmation")
	var window := lab.get_window()
	var original_size := window.size
	window.size = Vector2i(960, 600)
	await lab.frames(3)
	await lab.capture("initial_draft_compact")
	await lab.wait(draft.input_delay + 0.05)
	draft.confirm_button.grab_focus()
	await lab.key(KEY_ENTER)
	await lab.frames(3)
	lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not lab.get_tree().paused and game.run_state.primary.source == pulse and game.run_state.secondary_primary_source == scatter, "keyboard confirmation starts the run with the chosen distinct pair")
	game.director._physics_process(10.0)
	await lab.frames(3)
	lab.check(game.round_state == ArenaGame.RoundState.ROUTE and game.route_screen.choice_buttons.size() >= 2 and game.horde.alive_count == 0, "arrival offers alternative venue fights rather than spawning district-wide enemies")
	await lab.capture("route_choices_compact")
	var pair_a := game.run_state.primary.source
	var pair_b := game.run_state.secondary_primary_source
	await lab.wait(0.3)
	game.route_screen.loadout_button.pressed.emit()
	lab.check(game.round_state == ArenaGame.RoundState.DRAFT and draft.select_pair(lab.weapon("rail"), lab.weapon("autocannon")), "a cleared break allows selecting a different complementary pair")
	draft.cancel()
	await lab.frames(2)
	lab.check(game.round_state == ArenaGame.RoundState.ROUTE and game.run_state.primary.source == pair_a and game.run_state.secondary_primary_source == pair_b, "cancelling a break replacement preserves both guns and returns to route choice")
	var index := -1
	for n in game.director.route_choices.size():
		if game.director.route_choices[n].kind in [&"herna", &"hospoda", &"nonstop"]:
			index = n
			break
	lab.check(index >= 0, "the first route choice contains a furnished street venue")
	if index < 0:
		window.size = original_size
		return
	var choice: Dictionary = game.director.route_choices[index]
	var venue: Dictionary = {}
	var nearest := INF
	for site: Dictionary in game.world.kit_sites:
		if site.kind != choice.kind:
			continue
		var rect: Rect2 = site.rect
		var distance := rect.get_center().distance_to(Vector2(choice.position.x, choice.position.z))
		if distance < nearest:
			nearest = distance
			venue = site
	await lab.wait(0.3)
	game.route_screen.choice_buttons[index].pressed.emit()
	await lab.frames(2)
	lab.check(game.director.phase_name == "TRAVEL" and game.horde.alive_count == 0 and game.round_state == ArenaGame.RoundState.PLAYING, "choosing a venue resumes traversal without fighting remote enemies")
	var facing: Vector2 = venue.facing
	var outward := Vector3(facing.x, 0.0, facing.y).normalized()
	var door: Vector3 = venue.door
	game.player.global_position = door + outward * 2.0 + Vector3.UP * 0.95
	game.player.velocity = Vector3.ZERO
	game.player.rotation.y = atan2(outward.x, outward.z)
	game.player.head.rotation.x = 0.0
	for frame in 12:
		await lab.get_tree().physics_frame
	game.director.set_physics_process(true)
	Input.action_press(&"move_forward")
	for frame in 120:
		await lab.get_tree().physics_frame
		if game.director.phase_name in ["BUILD", "PEAK"]:
			break
	Input.action_release(&"move_forward")
	lab.check(game.director.phase_name in ["BUILD", "PEAK"] and game.director.current_venue_name == choice.name, "actual held-W entry through the chosen doorway starts that venue's fight")
	game._open_weapon_draft(true)
	lab.check(game.round_state == ArenaGame.RoundState.PLAYING and not draft.is_open() and game.run_state.primary.source == pair_a and game.run_state.secondary_primary_source == pair_b, "an active fight cannot reopen the catalogue or change its drafted pair")
	await lab.wait(1.0)
	await lab.capture("venue_fight_compact")
	lab.check(not game.hud.ability_row.get_global_rect().intersects(game.hud.primary_title.get_parent().get_parent().get_global_rect()) and not game.hud.ability_row.get_global_rect().intersects(game.hud.vitals.get_global_rect()), "compact combat HUD keeps skill tiles separate from both guns and vitals")
	window.size = original_size
	await lab.frames(2)
