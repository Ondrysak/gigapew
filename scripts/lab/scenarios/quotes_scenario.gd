extends LabScenario

func title() -> String:
	return "Quote-born weapons and upgrades"

func summary() -> String:
	return "Real shock chains, brick penetration, curd slowdown, retained gun ranks and ranked passive tradeoffs"

func run() -> void:
	var game := await lab.start_game(&"producer")
	game.horde.target = null
	game.horde.set_physics_process(false)
	game.player.global_position = Vector3(0, 1, 12)
	await _guns(game)
	await _upgrades(game)

func _guns(game: ArenaGame) -> void:
	for id: String in ["maschine", "cihlomet", "tvarohomet"]:
		game.horde.clear()
		lab.equip_weapon(id)
		game.player._reset_combo()
		var front := game.horde.spawn(lab.enemy("robot_grunt"), Vector2(0, 6), 1000.0)
		var other_at := Vector2(0, 4) if id == "cihlomet" else Vector2(2, 6)
		var recipe_id := StringName("weapon_" + id)
		Profile.add_currency(&"gold", 50)
		Profile.add_currency(&"crystal", 50)
		Profile.add_currency(&"shard", 10)
		lab.check(Profile.craft(recipe_id) and Profile.equip_craft(recipe_id), "%s can be crafted and equipped through the real Workshop profile path" % id)
		lab.check(Profile.primary_loadout(Profile.selected_class()) == lab.weapon(id) and Profile.available_primary_weapons(Profile.selected_class()).has(lab.weapon(id)), "%s is a normal selectable primary and retained as the crafted starting blueprint" % id)
		var other := game.horde.spawn(lab.enemy("robot_grunt"), other_at, 1000.0)
		game.horde._rebuild_grid()
		await lab.frames(3)
		lab.aim_at(game.horde.enemy_position(front))
		var front_hp: float = game.horde._hp[front]
		var other_hp: float = game.horde._hp[other]
		game.player._shoot()
		lab.check(game.horde._hp[front] < front_hp, "%s fires real primary damage" % id)
		lab.check(game.horde._hp[other] < other_hp, "%s damages a secondary victim through its distinct chain, penetration or splash" % id)
		if id == "cihlomet":
			lab.check(game.horde._knock[front].length() > 0.0 and game.horde._knock[other].length() > 0.0, "brick volley knocks back both penetrated victims")
		elif id == "tvarohomet":
			lab.check(game.horde._slow[front] < 1.0 and game.horde._slow[other] < 1.0 and game.horde._slow_time[other] > 0.0, "curd's direct hit and splash apply live frost slowdown")
		await lab.capture(id + "_impact")
	var build := game.run_state.primary
	build.upgrade(&"damage")
	build.upgrade(&"pierce")
	for id: String in ["maschine", "cihlomet", "tvarohomet"]:
		var source := lab.weapon(id)
		build.swap(source)
		game.player.refresh_weapon()
		lab.check(build.definition.damage == roundi(source.damage * 1.2) and build.definition.pierce == source.pierce + 1, "purchased gun ranks survive swap to %s without accumulating onto authored stats" % id)

func _upgrades(game: ArenaGame) -> void:
	var state := game.run_state
	var player := game.player
	var baseline_health: int = player.max_health
	var baseline_damage: float = state.damage_multiplier
	var baseline_pierce: int = state.pierce_bonus
	var baseline_pickup: float = state.pickup_radius
	var baseline_auto: float = state.cooldown_multiplier
	var baseline_speed: float = state.move_speed_multiplier
	var baseline_rate: float = state.fire_rate_multiplier
	var baseline_area: float = state.area_multiplier
	for id: String in ["nemakacenko", "tartarus", "krajic_chleba", "rave"]:
		var upgrade := load("res://data/upgrades/%s.tres" % id) as UpgradeDefinition
		for rank in range(3):
			game.grant_upgrade(upgrade)
		game.grant_upgrade(upgrade)
		lab.check(state.level_of(upgrade) == 3, "%s stops at its purchased third rank" % id)
		match id:
			"nemakacenko":
				lab.check(is_equal_approx(state.pickup_radius, baseline_pickup + 4.5) and is_equal_approx(state.cooldown_multiplier, baseline_auto - 0.3), "Nemakačenko expands live XP collection and shortens auto recharge")
			"tartarus":
				lab.check(player.max_health == baseline_health - 24 and player.health <= player.max_health and is_equal_approx(state.damage_multiplier, baseline_damage + 0.24) and state.pierce_bonus == baseline_pierce + 3, "Tartarus grants damage and piercing while really reducing and clamping player health")
			"krajic_chleba":
				lab.check(player.max_health == baseline_health + 21 and is_equal_approx(state.regen_per_second, 1.2) and is_equal_approx(state.move_speed_multiplier, baseline_speed - 0.09), "bread grants health and regeneration with the advertised movement cost")
			"rave":
				lab.check(is_equal_approx(state.fire_rate_multiplier, baseline_rate + 0.36) and is_equal_approx(state.area_multiplier, baseline_area + 0.24), "Rave changes effective primary cadence and effect area")
	player.health = player.max_health - 10
	player._regen = 0.0
	var before: int = player.health
	await lab.wait(1.1)
	lab.check(player.health > before and player.health <= player.max_health, "bread regeneration heals actual missing player HP over time")
	await lab.capture("ranked_passives")
