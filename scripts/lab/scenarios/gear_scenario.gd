extends LabScenario

func title() -> String:
	return "Skrýše, výbava a hlášky"

func summary() -> String:
	return "Real item choices/replacement, run-only gear, discoveries and every combat effect"

func run() -> void:
	_profile_and_inventory()
	var game := await lab.start_game(&"scout")
	await _picker(game)
	await _combat(game)
	await _salvage(game)
	await _world_sources()

func _profile_and_inventory() -> void:
	Profile.enter_sandbox()
	var rng := RandomNumberGenerator.new()
	rng.seed = 717
	var empty: Array[GearDefinition] = []
	var locked := GearCatalog.roll(rng, 6, empty, false)
	var locked_ids := _ids(locked)
	lab.check(locked_ids.has(&"mirror") and locked_ids.has(&"trainers") and locked_ids.has(&"gloves") and not locked_ids.has(&"wire") and not locked_ids.has(&"glass"), "regular drops exclude undiscovered advanced gear")
	Profile.discover_gear(&"wire")
	var unlocked := _ids(GearCatalog.roll(rng, 6, empty, false))
	lab.check(unlocked.has(&"wire") and not unlocked.has(&"glass"), "discovering wire adds it to future regular drops without unlocking the curse")
	Profile.enter_sandbox()
	Profile._apply_data({"discovered_gear": ["wire", "glass", "wire", "not_an_item"]})
	lab.check(Profile.has_discovered_gear(&"wire") and Profile.has_discovered_gear(&"glass") and not Profile.has_discovered_gear(&"not_an_item"), "profile loading retains real discoveries and ignores invalid item IDs")
	var state := RunState.new()
	for id in [&"mirror", &"trainers", &"wire", &"gloves"]:
		state.equip_gear(GearCatalog.find(id))
	lab.check(not state.equip_gear(GearCatalog.find(&"glass")) and not state.equip_gear(GearCatalog.find(&"mirror"), 1) and not state.equip_gear(GearCatalog.find(&"glass"), 4), "full inventory cannot silently replace, duplicate gear or accept an invalid slot")
	state.equip_gear(GearCatalog.find(&"glass"), 2)
	lab.check(state.has_gear(&"glass") and not state.has_gear(&"wire") and is_equal_approx(state.damage_multiplier, 1.5) and is_equal_approx(state.gear_health_multiplier, 0.65), "explicit replacement activates both sides of the glass curse")
	state.equip_gear(GearCatalog.find(&"wire"), 2)
	lab.check(is_equal_approx(state.damage_multiplier, 1.0) and is_equal_approx(state.gear_health_multiplier, 1.0), "replacing the curse restores derived stats without modifier accumulation")
	var fresh := RunState.new()
	lab.check(not fresh.has_gear(&"wire") and Profile.has_discovered_gear(&"wire"), "a new run retains discoveries, not equipped gear")

func _ids(items: Array[GearDefinition]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for item in items:
		ids.append(item.id)
	return ids

func _picker(game: ArenaGame) -> void:
	var offers: Array[GearDefinition] = [GearCatalog.find(&"mirror"), GearCatalog.find(&"trainers"), GearCatalog.find(&"wire")]
	game._pending_gear_rewards.append({"offers": offers, "title": "KEŠULKY BUDOU · ODMĚNA ZE SKRÝŠE"})
	game._present_gear_reward()
	await lab.wait(0.35)
	await lab.capture("quest_choice")
	await _click(game.gear_screen.offer_buttons[0])
	lab.check(game.run_state.has_gear(&"mirror") and game.round_state == ArenaGame.RoundState.PLAYING, "clicking an actual reward card equips the selected item and resumes combat")
	for id in [&"trainers", &"wire", &"gloves"]:
		game.run_state.equip_gear(GearCatalog.find(id))
	var curse: Array[GearDefinition] = [GearCatalog.find(&"glass")]
	game._pending_gear_rewards.append({"offers": curse, "title": "NEJSEM SKLENIČKA · PROKLETÝ NÁLEZ"})
	game._present_gear_reward()
	await lab.wait(0.35)
	await lab.capture("curse_offer")
	await _click(game.gear_screen.offer_buttons[0])
	lab.check(not game.run_state.has_gear(&"glass") and game.round_state == ArenaGame.RoundState.GEAR, "choosing a fifth item waits for an explicit replacement instead of silently equipping a curse")
	await lab.capture("replacement")
	await _click(game.gear_screen.replacement_buttons[1])
	lab.check(game.run_state.has_gear(&"glass") and not game.run_state.has_gear(&"trainers"), "actual replacement-card click discards exactly the selected slot")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.keycode = KEY_G
	key.pressed = true
	Input.parse_input_event(key)
	await lab.wait(0.35)
	lab.check(game.gear_screen.visible and game.get_tree().paused, "G opens inspect-only gear cards and pauses gameplay")
	await lab.capture("inventory")
	await _click(game.gear_screen.leave_button)
	var health_before := game.player.health
	game.run_state.equip_gear(GearCatalog.find(&"trainers"), 1)
	lab.check(game.player.health >= health_before and game.player.health <= game.player.max_health and game.player.max_health == game.player.base_max_health, "removing the curse restores maximum health with a bounded health transition")

func _click(button: Button) -> void:
	await lab.frames(2)
	var point := button.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await lab.frames(1)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	await lab.wait(0.35)

func _only_gear(game: ArenaGame, id: StringName) -> void:
	game.run_state.gear.clear()
	game.run_state.refresh_modifiers()
	game.run_state.gear_changed.emit()
	if id != &"":
		game.run_state.equip_gear(GearCatalog.find(id))

func _target(game: ArenaGame, at: Vector2, hp: float = 1000.0) -> int:
	var enemy := lab.enemy("robot_spitter")
	var slot := game.horde.spawn(enemy, at, hp / enemy.max_health)
	game.horde._yaw[slot] = 0.0
	game.horde._rebuild_grid()
	return slot

func _shot(game: ArenaGame, at: Vector3) -> void:
	game.player._reset_combo()
	lab.aim_at(at)
	game.player._shoot()

func _combat(game: ArenaGame) -> void:
	var player := game.player
	var horde := game.horde
	player.set_physics_process(false)
	horde.set_physics_process(false)
	horde.target = null
	horde.clear()
	player.global_position = Vector3(0, 1, 12)
	var gun := lab.weapon("pulse").duplicate() as WeaponDefinition
	gun.damage = 10
	gun.pierce = 0
	gun.explosion_radius = 0.0
	game.run_state.initialize_primary(gun)
	player.refresh_weapon()
	_only_gear(game, &"mirror")
	var main := _target(game, Vector2(0, 9))
	var other := _target(game, Vector2(1.8, 9))
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[main], 990.0) and is_equal_approx(horde._hp[other], 996.0), "mirror adds exactly one 40%-damage bounce from an actual primary body hit")
	await lab.capture("ricochet")
	_only_gear(game, &"")
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[other], 996.0), "replacing the mirror stops secondary bounce damage")
	_only_gear(game, &"wire")
	horde.clear()
	main = _target(game, Vector2(0, 9))
	other = _target(game, Vector2(1.8, 9))
	for hit in 3:
		_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[other], 1000.0), "wire does not discharge before the fourth direct-hit shot")
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[other], 975.0), "fourth direct-hit shot causes exactly 25 chain damage")
	await lab.capture("chain_shock")
	for hit in 3:
		_shot(game, Vector3(0, 0.65, 9))
	horde.clear()
	main = _target(game, Vector2(0, 9))
	other = _target(game, Vector2(1.8, 9))
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[other], 1000.0), "wire charge cannot leak into a reused enemy slot")
	_only_gear(game, &"lighter")
	horde.clear()
	for kill in 8:
		main = _target(game, Vector2(0, 9), 5.0)
		_shot(game, Vector3(0, 0.65, 9))
		# Release the corpse slot; streak belongs to the player, not the victim.
		horde.clear()
	other = _target(game, Vector2(1.8, 9))
	main = _target(game, Vector2(0, 9), 5.0)
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[other], 950.0), "eight primary kills prime the next killing hit for one 50-damage explosion")
	await lab.capture("kill_explosion")
	_only_gear(game, &"glass")
	horde.clear()
	main = _target(game, Vector2(0, 9))
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(is_equal_approx(horde._hp[main], 985.0) and player.max_health == roundi(player.base_max_health * 0.65), "glass boosts real gun damage by 50% while reducing maximum health by 35%")
	_only_gear(game, &"trainers")
	horde.clear()
	player.global_position = Vector3(0, 0.1, 12)
	main = _target(game, Vector2(0, 11.5))
	player.set_physics_process(true)
	player.dash(Vector3(0, 0, -12), 0.3)
	await lab.wait(0.45)
	lab.check(horde._hp[main] < 1000.0, "a real dash leaves a damaging trainer trail behind the player")
	await lab.capture("dash_trail")
	await lab.wait(2.1)
	var after := horde._hp[main]
	await lab.wait(0.3)
	lab.check(is_equal_approx(horde._hp[main], after), "expired dash trails stop damaging enemies")
	player.set_physics_process(false)

func _salvage(game: ArenaGame) -> void:
	_only_gear(game, &"gloves")
	game.player.set_physics_process(true)
	game.player._invulnerable = 0.0
	var deposit: MineralDeposit
	for child in game.deposits.get_children():
		if child is MineralDeposit and child.health > 0:
			deposit = child
			break
	if deposit == null:
		lab.check(false, "salvage fixture has a live compartment")
		return
	lab.check(await lab.aim_deposit(deposit, 2.2), "glove fixture acquires a real machine latch")
	Input.action_press(&"mine")
	await lab.wait(1.1)
	Input.action_release(&"mine")
	lab.check(game.player.gear_effects.salvage_shield > 0.0, "opening a real compartment grants the glove shield")
	var hp := game.player.health
	game.player.take_damage(12)
	lab.check(game.player.health == hp and is_equal_approx(game.player.gear_effects.salvage_shield, 8.0), "glove shield absorbs damage before health and spends only absorbed points")
	game.player.take_damage(12)
	lab.check(game.player.health == hp - 4 and game.player.gear_effects.salvage_shield == 0.0, "damage exceeding the remaining shield reaches health")
	await lab.capture("salvage_shield")
	game.player.grant_invulnerability(1.0e9)

func _world_sources() -> void:
	if is_instance_valid(lab.game):
		lab.game.free()
	for stage in 3:
		var game := await lab.start_game(&"scout", stage, true, 8811 + stage)
		game.horde.set_physics_process(false)
		game.player.set_physics_process(false)
		var loot := game.gear_loot
		for attempt in 60:
			if loot.initialized:
				break
			await lab.wait(0.1)
		lab.check(loot.initialized and loot.stashes.size() == 3, "sector %d supplies a guarded quest stash and two exploration caches" % stage)
		if not loot.initialized:
			game.free()
			continue
		var quest := loot.stashes[0]
		_stand_at_stash(game, quest)
		await lab.wait(0.15)
		lab.check(loot.target_stash() == quest and quest.guards_started and game.horde.alive_count >= 4, "sector %d approaching the quest stash activates its finite defenders" % stage)
		await lab.capture("sector_%d_stash" % stage)
		Input.action_press(&"interact")
		await lab.wait(0.5)
		Input.action_release(&"interact")
		var progress := quest.pry_progress
		game.get_tree().paused = true
		Input.action_press(&"interact")
		await lab.wait(0.35)
		Input.action_release(&"interact")
		game.get_tree().paused = false
		game.player.global_position += Vector3(0, 0, 5)
		await lab.wait(0.3)
		lab.check(progress > 0.3 and is_equal_approx(quest.pry_progress, progress) and not quest.claimed, "sector %d pause and retreat preserve partial opening without paying a reward" % stage)
		_stand_at_stash(game, quest)
		Input.action_press(&"interact")
		await lab.wait(2.0)
		Input.action_release(&"interact")
		lab.check(quest.claimed and game.gear_screen.visible and game._gear_offers.size() == 3 and game.horde.alive_count >= 4, "sector %d can steal a three-choice reward while the guards are still alive" % stage)
		await lab.capture("sector_%d_reward" % stage)
		var discovered := quest.offers[0].id
		await _click(game.gear_screen.leave_button)
		lab.check(not loot.claim_stash(quest) and Profile.has_discovered_gear(discovered) and not game.run_state.has_gear(discovered), "declining keeps the discovery, leaves gear unequipped and cannot reroll the claimed stash")
		var cache := loot.stashes[1]
		_stand_at_stash(game, cache)
		Input.action_press(&"interact")
		await lab.wait(2.3)
		Input.action_release(&"interact")
		lab.check(cache.claimed and game._gear_offers.size() == 1, "exploration cache reveals one random item instead of the quest's three choices")
		await _click(game.gear_screen.offer_buttons[0])
		game.player.global_position = loot.elite_site + Vector3(0, 0.1, 2)
		await lab.wait(0.2)
		lab.check(loot.elite_spawned and loot.elite_generation == game.horde.enemy_generation(loot.elite_slot), "sector %d elite hunt tracks an actual spawned lifetime" % stage)
		if loot.elite_spawned:
			var elite_at := game.horde.enemy_position(loot.elite_slot)
			var sight := PhysicsRayQueryParameters3D.create(Vector3.ZERO, elite_at, 1, [game.player.get_rid()])
			for point in loot._floor_points:
				var distance := point.distance_to(elite_at)
				if distance < 3.5 or distance > 6.0:
					continue
				sight.from = point + Vector3.UP * 1.6
				if game.get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
					game.player.global_position = point + Vector3.UP * 0.1
					break
			lab.aim_at(game.horde.enemy_position(loot.elite_slot))
			await lab.capture("sector_%d_elite" % stage)
			game.horde.damage(loot.elite_slot, loot.elite_definition.max_health * 2.0)
			await lab.frames(2)
			lab.check(loot.elite_defeated and is_instance_valid(loot.elite_drop) and not game.gear_screen.visible, "elite death creates an intentional pickup, never auto-equips gear")
			_stand_at_stash(game, loot.elite_drop)
			Input.action_press(&"interact")
			await lab.wait(0.4)
			Input.action_release(&"interact")
			lab.check(loot.elite_drop.claimed and game._gear_offers.size() == 1, "E claims exactly one item from the elite drop")
			await _click(game.gear_screen.offer_buttons[0])
		var held_ids := _ids(game.run_state.gear)
		game._load_stage((stage + 1) % 3, 9300 + stage)
		game.director.set_physics_process(false)
		lab.check(_ids(game.run_state.gear) == held_ids and game.gear_loot != loot, "sector changes retain equipped gear but discard old loot encounters")
		# Let the new sector render before teardown so pending texture uploads
		# do not outlive their owners at batch shutdown.
		await lab.frames(3)
		if is_instance_valid(lab.game):
			lab.game.free()

func _stand_at_stash(game: ArenaGame, stash: GearStash) -> void:
	game.player.velocity = Vector3.ZERO
	game.player.global_position = stash.global_position + Vector3(0, 0.1, 2.0)
	lab.aim_at(stash.aim_point())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.player.cancel_actions()
