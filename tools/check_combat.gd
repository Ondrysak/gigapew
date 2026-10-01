extends SceneTree
## Real shots cover precision damage, luck interactions, piercing and splash.
## Nested blasts must retain their targets, including beyond pooled depth.
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.director.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.player.set_physics_process(false)
	await physics_frame
	await _check_precision(game)
	var horde = game.horde
	var definition = game._stage_enemies(game.campaign[0].schedule)[0]
	for levels in [2, horde.RADIUS_DEPTH + 2]:
		horde.clear()
		var groups: Array = []
		for depth in range(levels):
			var slots: Array[int] = []
			for target in range(3 if depth == 0 else 2):
				slots.append(horde.spawn(definition, Vector2(-12 + depth * 4 + target * 0.3, 6), 100.0 / definition.max_health))
			groups.append(slots)
		horde._rebuild_grid()
		var nested := {"depth": 0}
		var listener := func(_at: Vector3, _amount: float, _kind: int, _critical: bool, _killed: bool):
			if nested.depth + 1 < levels:
				nested.depth += 1
				horde.damage_radius(Vector3(-12 + nested.depth * 4, 0.5, 6), 1.0, 5.0 + nested.depth)
		horde.damage_reported.connect(listener)
		var count: int = horde.damage_radius(Vector3(-12, 0.5, 6), 1.0, 5.0)
		horde.damage_reported.disconnect(listener)
		_check(count == 3, "Nested blast changed the outer hit count")
		for depth in range(levels):
			for slot in groups[depth]:
				_check(is_equal_approx(horde._hp[slot], 95.0 - depth), "Nested blast lost, duplicated or substituted a target at depth %d" % depth)
	game.free()
	print("Combat regressions: failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)

func _check_precision(game) -> void:
	var horde = game.horde
	var player = game.player
	var state = game.run_state
	var definition = load("res://data/enemies/robot_spitter.tres")
	var gun = load("res://data/weapons/pulse.tres").duplicate()
	gun.damage = 10
	gun.pierce = 0
	player.weapons.assign([gun, null, null])
	player.refresh_weapons()
	player.global_position = Vector3(0, 1, 12)
	state.crit_chance = 0.0
	horde.clear()
	var slot: int = horde.spawn(definition, Vector2(0, 9), 1000.0 / definition.max_health)
	horde._yaw[slot] = 0.0
	horde._rebuild_grid()
	player._reset_combo()
	player.head.look_at(Vector3(0, 0.65, 9), Vector3.UP)
	player._shoot(0)
	_check(is_equal_approx(horde._hp[slot], 990.0), "Body hit changed unmodified base damage")
	horde._hp[slot] = 1000.0
	player._process(1.0)
	player._reset_combo()
	player.head.look_at(Vector3(0, 1.7, 9), Vector3.UP)
	player._shoot(0)
	_check(is_equal_approx(horde._hp[slot], 970.0), "Aimed headshot must earn x3 without a random crit roll")
	horde._hp[slot] = 1000.0
	state.crit_chance = 1.0
	player._process(1.0)
	player._reset_combo()
	player._shoot(0)
	_check(is_equal_approx(horde._hp[slot], 970.0), "Random and aimed crits must not double-stack")
	horde._hp[slot] = 1000.0
	player._process(1.0)
	player._reset_combo()
	player.head.look_at(Vector3(0, 0.65, 9), Vector3.UP)
	player._shoot(0)
	_check(is_equal_approx(horde._hp[slot], 980.0), "Rolled body crit must deal x2")
	state.crit_chance = 0.0
	horde._hp[slot] = 1000.0
	gun.pierce = 1
	var boss = load("res://data/enemies/robot_boss.tres")
	var rear: int = horde.spawn(boss, Vector2(0, 6.5), 1000.0 / boss.max_health)
	horde._rebuild_grid()
	var reported := {}
	var listener := func(at: Vector3, _amount: float, _kind: int, critical: bool, _killed: bool):
		reported[at.z] = critical
	horde.damage_reported.connect(listener)
	_shoot_at(player, Vector3(0, 1.7, 9))
	horde.damage_reported.disconnect(listener)
	_check(is_equal_approx(horde._hp[slot], 970.0) and is_equal_approx(horde._hp[rear], 990.0), "Piercing must resolve head/body damage separately per victim")
	_check(reported.get(9.0, false) and not reported.get(6.5, true), "Pierced body victim inherited another enemy's critical feedback")
	horde.clear()
	gun.pierce = 0
	gun.explosion_radius = 1.0
	gun.explosion_damage_fraction = 0.5
	player.refresh_weapons()
	slot = horde.spawn(definition, Vector2(0, 9), 1000.0 / definition.max_health)
	horde._yaw[slot] = 0.0
	var collateral: int = horde.spawn(definition, Vector2(0.8, 9), 1000.0 / definition.max_health)
	horde._rebuild_grid()
	_shoot_at(player, Vector3(0, 1.7, 9))
	_check(is_equal_approx(horde._hp[slot], 965.0) and is_equal_approx(horde._hp[collateral], 995.0), "Aimed headshot must not multiply collateral splash damage")
	gun.explosion_radius = 0.0
	player.refresh_weapons()
	horde.clear()
	slot = horde.spawn(definition, Vector2(0, 9), 1000.0 / definition.max_health)
	horde._yaw[slot] = 0.0
	horde._rebuild_grid()
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 0.8, 0.1)
	collision.shape = shape
	blocker.position = Vector3(0, 1.7, 9.25)
	blocker.add_child(collision)
	game.add_child(blocker)
	await physics_frame
	_shoot_at(player, Vector3(0, 1.7, 9))
	_check(is_equal_approx(horde._hp[slot], 990.0), "Head behind a world blocker incorrectly received precision bonus")
	blocker.free()
	horde._hp[slot] = 1000.0
	horde._y[slot] = 2.0
	_shoot_at(player, Vector3(0, 3.7, 9))
	_check(is_equal_approx(horde._hp[slot], 970.0), "Precision volume did not follow enemy feet height")
	horde.clear()
	var tank = load("res://data/enemies/robot_tank.tres")
	slot = horde.spawn(tank, Vector2(0, 9), 1000.0 / tank.max_health)
	horde._yaw[slot] = PI * 0.5
	horde._rebuild_grid()
	_shoot_at(player, Vector3(-0.8, 1.95, 9))
	_check(is_equal_approx(horde._hp[slot], 970.0), "Off-center weak core did not rotate with the enemy")
	horde.clear()
	slot = horde.spawn(definition, Vector2(0, 9), 1000.0 / definition.max_health)
	horde._yaw[slot] = 0.0
	horde._rebuild_grid()
	state.apply_upgrade(load("res://data/upgrades/perk_lucky_strike.tres"))
	_shoot_at(player, Vector3(0, 1.7, 9))
	_check(is_equal_approx(horde._hp[slot], 967.5), "Crit-damage perk failed to improve aimed precision damage")

func _shoot_at(player, at: Vector3) -> void:
	player._process(1.0)
	player._reset_combo()
	player.head.look_at(at, Vector3.UP)
	player._shoot(0)
