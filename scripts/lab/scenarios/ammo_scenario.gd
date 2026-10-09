extends LabScenario

func title() -> String:
	return "Ammo and automatic rotation"

func summary() -> String:
	return "Empty-trigger swaps, draw timing, reload eligibility, finite reserves and dry-gun recovery"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.horde.target = null
	game.pickups.supply_interval = 1.0e6
	player.global_position = Vector3(0, 1, 12)
	await lab.wait(0.3)
	var shots := [0]
	player.shot_fired.connect(func(): shots[0] += 1)
	var original_rail := player.ammo(1)
	player._magazines[0] = 1
	player._reserves[0] = 0
	lab.fire(true)
	await lab.wait(0.04)
	lab.check(player.selected_weapon == 1 and player.ammo(0) == 0, "last primary round rotates forward to a loaded gun even when its own reserve is exhausted")
	lab.check(shots[0] == 1 and player.ammo(1) == original_rail, "auto-swap never fires a second gun in the same tick")
	await lab.wait(0.08)
	lab.check(shots[0] == 1 and player.ammo(1) == original_rail, "automatic rotation retains the normal draw lock")
	await lab.wait(0.25)
	lab.fire(false)
	lab.check(shots[0] == 2 and player.ammo(1) == original_rail - 1, "held primary resumes on the automatically selected gun after its draw")
	await lab.capture("automatic")

	# A partially loaded gun in a reload is not ready to inherit the trigger.
	player.cancel_secondaries()
	player.select_weapon(0)
	player._draw_left = 0.0
	player._fire_cooldowns.fill(0.0)
	player._reloads.fill(0.0)
	player._magazines[0] = 1
	player._magazines[1] = 1
	player._reserves[1] = original_rail - 1
	player._reloads[1] = 0.8
	lab.fire(true)
	await lab.wait(0.06)
	lab.fire(false)
	lab.check(player.selected_weapon == 2 and player.ammo(1) == 1, "automatic rotation skips a loaded but still-reloading gun")
	player.select_weapon(1)
	lab.check(player.selected_weapon == 1, "manual selection can override the automatic choice")
	await lab.wait(1.4)
	lab.check(player.ammo(1) == original_rail and player.reserve_ammo(1) == 0, "partial reload transfers only missing rounds from a finite reserve")

	player.select_weapon(0)
	player._draw_left = 0.0
	player._magazines[0] = 0
	player._reloads.fill(0.0)
	player._reserves.fill(0)
	await lab.wait(0.25)
	lab.check(player.selected_weapon == 0, "an idle empty gun remains manually selected until primary is requested")

	# Both inputs held during a lance must not steal focus or spend main ammo.
	player.select_weapon(1)
	player._draw_left = 0.0
	player._magazines[1] = 0
	player.secondary_charge[1] = 100.0
	var before_alternate: int = shots[0]
	Input.action_press("mine")
	lab.fire(true)
	await lab.wait(0.2)
	lab.check(player.selected_weapon == 1 and player.secondaries[1].charge_progress() > 0.0 and shots[0] == before_alternate, "a charged alternate keeps focus even with an empty magazine and held primary")
	Input.action_release("mine")
	lab.fire(false)
	await lab.frames(3)
	lab.check(is_equal_approx(player.secondary_charge[1], 100.0), "early lance cancellation remains free with dry main ammo")

	player.select_weapon(0)
	player._draw_left = 0.0
	player._magazines.fill(0)
	player._reserves.fill(0)
	player._reloads.fill(0.0)
	var before_dry: int = shots[0]
	lab.fire(true)
	await lab.wait(0.4)
	lab.fire(false)
	lab.check(player.selected_weapon == 0 and shots[0] == before_dry and not player.is_reloading(0), "all-dry loadout neither cycles forever, fires free rounds nor starts an impossible reload")
	await lab.capture("dry")

	# A final partial reserve must not become a full magazine out of thin air.
	player._reserves[0] = 3
	await lab.wait(player.weapons[0].reload_time * 1.6 + 0.15)
	lab.check(player.ammo(0) == 3 and player.reserve_ammo(0) == 0 and not player.is_reloading(0), "in-hand reload transfers the last three reserve rounds without manufacturing ammo")
	lab.fire(true)
	await lab.wait(0.5)
	lab.fire(false)
	lab.check(player.ammo(0) == 0 and player.reserve_ammo(0) == 0 and shots[0] == before_dry + 3, "the last partial magazine supplies exactly three real shots")

	player._magazines[1] = 1
	player.active = false
	lab.fire(true)
	await lab.wait(0.3)
	lab.check(player.selected_weapon == 0 and player.ammo(1) == 1 and shots[0] == before_dry + 3, "inactive player cannot fire or automatically change guns")
	lab.fire(false)
	player.active = true
