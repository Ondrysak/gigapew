extends LabScenario

func title() -> String:
	return "Survival pickups"

func summary() -> String:
	return "Repair and global-XP magnets; saturation, pause and grounded recovery supplies"

func run() -> void:
	var game := await lab.start_game()
	game.horde.target = null
	var player := game.player
	var field := game.pickups
	field.supply_interval = 1.0e6
	field.repair_chance = 0.0
	field.xp_kill_interval = 1
	player.global_position = Vector3(0, 1, 12)
	await lab.wait(0.3)
	var repairs := [0]
	field.collected.connect(func(kind: StringName, amount: int):
		if kind == &"repair": repairs[0] += amount)
	field.spawn_magnet(Vector3(-2, 0, 8))
	field.spawn_repair(Vector3(2, 0, 8))
	lab.aim_at(Vector3(0, 0.5, 8))
	await lab.frames(3)
	await lab.capture("loot")
	var kits_before := field._repairs.count
	field.spawn_repair(player.global_position)
	await lab.wait(0.1)
	lab.check(field._repairs.count == kits_before + 1, "repair kit at full health is not consumed")
	player.health = player.max_health - 5
	player.health_changed.emit(player.health, player.max_health)
	await lab.wait(0.1)
	lab.check(player.health == player.max_health and field._repairs.count == kits_before and repairs[0] == 5, "repair kit heals only missing health and reports the real gain")
	await lab.capture("repair_collected")

	# Each gem is earned through a real horde kill, well outside pickup radius.
	game.run_state.xp_multiplier = 2.0
	var xp_before := _total_xp(game.run_state)
	for at in [Vector2(20, 12), Vector2(-20, 12), Vector2(0, -12), Vector2(18, -8), Vector2(-18, -8), Vector2(0, 30)]:
		_kill(game, at)
	field._gems.speeds[0] = field.initial_attract_speed
	# Walk-up utility magnets do not activate until actually collected.
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(-2, 1, 8)
	await lab.wait(0.06)
	lab.check(field._magnets.count == 0 and _total_xp(game.run_state) == xp_before, "collecting a magnet starts distant homing without instantly awarding XP")
	await lab.wait(0.15)
	await lab.capture("magnet_pull")
	await lab.wait(1.6)
	lab.check(field._gems.count == 0 and _total_xp(game.run_state) == xp_before + 12, "magnet gathers all distant and already-homing gems exactly once with the XP multiplier")
	_kill(game, Vector2(20, 12))
	await lab.wait(0.1)
	lab.check(field._gems.count == 1 and field._gems.speeds[0] == 0.0, "later XP drops are loose again instead of inheriting a permanent global vacuum")
	await lab.capture("magnet_done")

	# Exercise actual small-capacity storage, not a fake gem implementation.
	field.free()
	field = game.pickup_scene.instantiate() as PickupField
	field.max_gems = 2
	field.repair_chance = 0.0
	field.xp_kill_interval = 1
	field.supply_interval = 1.0e6
	game._round.add_child(field)
	field.setup(game.horde, player, game.run_state)
	field.collected.connect(game.hud.show_pickup)
	game.pickups = field
	xp_before = _total_xp(game.run_state)
	for n in 3:
		_kill(game, Vector2(20 + n * 0.2, 12))
	lab.check(field._gems.count == 2 and field._gems.values[0] + field._gems.values[1] == 3, "saturated XP storage merges a new kill instead of dropping its value")
	field.magnetize_xp()
	for n in 2:
		_kill(game, Vector2(20 + n * 0.2, 12))
	# Bound simulated homing time, not rendering time during pool/GPU setup.
	for frame in 180:
		if field._gems.count == 0:
			break
		await lab.get_tree().physics_frame
	var earned := _total_xp(game.run_state) - xp_before
	lab.check(field._gems.count == 0 and earned == 10, "overflow into a fully homing pool preserves all XP and awards no duplicates (loose=%d earned=%d)" % [field._gems.count, earned])

	# An explicit configured cadence proves the magnet boundary, not a default.
	field.magnet_kill_interval = 5
	field._nonboss_kills = 0
	var magnets_before := field._magnets.count
	for n in 4:
		_kill(game, Vector2(20, 12))
	lab.check(field._magnets.count == magnets_before, "configured regular magnet does not arrive one kill early")
	_kill(game, Vector2(20, 12))
	lab.check(field._magnets.count == magnets_before + 1, "configured magnet arrives exactly on its regular-kill threshold")

	# Timed recovery remains independent of a saturated ordinary repair pool.
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 1, 12)
	await lab.wait(0.3)
	for n in field._repairs.capacity:
		field.spawn_repair(Vector3(20, 0, 12))
	field.supply_interval = 0.2
	await lab.wait(0.7)
	lab.check(field._supplies.count == 2 and field._repairs.count == field._repairs.capacity, "timed repair remains available with saturated ordinary loot and bounded storage")
	var other_supply := field._supplies.positions[1]
	lab.check(Vector2(field._supplies.positions[0].x, field._supplies.positions[0].z).distance_to(Vector2(other_supply.x, other_supply.z)) > field.collect_distance, "timed crates stay separated so collecting one does not accidentally collect both")
	var supply_at := field._supplies.positions[0]
	lab.check(not game.horde.is_blocked(Vector2(supply_at.x, supply_at.z), 0.4) \
			and is_equal_approx(supply_at.y, game.horde.ground_height(Vector2(supply_at.x, supply_at.z)) + field.repair_height), "timed repair lands on real unblocked ground")
	lab.aim_at(supply_at)
	await lab.capture("supply")
	field.supply_interval = 1.0e6
	player.global_position = Vector3(supply_at.x, supply_at.y - field.repair_height + 0.9, supply_at.z)
	player.health = player.max_health - field.repair_heal
	await lab.wait(0.1)
	lab.check(field._supplies.count == 1 and player.health == player.max_health, "timed repair heals the player even when ordinary loot is saturated")

	field._supply_elapsed = 0.0
	field.supply_interval = 0.2
	lab.get_tree().paused = true
	await lab.wait(0.3)
	lab.check(field._supplies.count == 1 and field._supply_elapsed == 0.0, "paused game does not advance the supply timer")
	lab.get_tree().paused = false
	player.active = false
	await lab.wait(0.3)
	lab.check(field._supplies.count == 1 and field._supply_elapsed == 0.0, "inactive player does not advance the supply timer")
	player.active = true

	await _elevated_supplies()

func _kill(game: ArenaGame, at: Vector2) -> void:
	var slot := game.horde.spawn(lab.enemy("robot_grunt"), at)
	game.horde.damage(slot, 1.0e6)

func _total_xp(state: RunState) -> int:
	var total := state.xp
	for level in range(1, state.level):
		total += RunState.required_for(level)
	return total

func _elevated_supplies() -> void:
	lab.game.free()
	var game := await lab.start_game(&"scout", 1)
	var player := game.player
	var field := game.pickups
	var stand := Vector2.ZERO
	var top := 0.0
	for body in game.world.get_node("Elevation").get_children():
		if not body is StaticBody3D or body.global_basis.y.dot(Vector3.UP) < 0.99:
			continue
		var point := Vector2(body.global_position.x, body.global_position.z)
		var height := game.horde.ground_height(point)
		if height > top and not game.horde.is_blocked(point, 0.4):
			stand = point
			top = height
	lab.check(top > 1.0, "real Foundry geometry provides a reachable raised deck")
	player.global_position = Vector3(stand.x, top + 0.9, stand.y)
	player.velocity = Vector3.ZERO
	await lab.wait(0.3)
	# Force the normal ring outside the map to exercise the near-deck fallback.
	field.supply_min_distance = 200.0
	field.supply_max_distance = 200.0
	field._supply_elapsed = 0.0
	field.supply_interval = 0.2
	await lab.wait(0.3)
	lab.check(field._supplies.count == 1, "small-deck fallback supplies repair when the normal ring is unreachable")
	if field._supplies.count > 0:
		var at := field._supplies.positions[0]
		lab.check(is_equal_approx(at.y, top + field.repair_height) and player.global_position.distance_to(at) < 3.0, "raised-deck supply stays near the player on the same reachable surface")
		lab.aim_at(at)
		await lab.capture("raised_supply")
