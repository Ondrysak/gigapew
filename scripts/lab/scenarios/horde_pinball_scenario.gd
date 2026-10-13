extends LabScenario

## Horde side of the pinball contract, exercised through the public Horde and
## PinballProp APIs with real authored-arena colliders and physics frames.

const STEP := 1.0 / 60.0
const SHATTER_UPGRADE := preload("res://data/upgrades/build_shatter.tres")
const RETURN_UPGRADE := preload("res://data/upgrades/build_return.tres")
var _actions: Array[Dictionary] = []
var _kills := 0
var _explosions := 0

func title() -> String:
	return "Horde pinball"

func summary() -> String:
	return "Kicks launch light bodies and stagger heavy ones, wall splats stop at real colliders, frozen shatter credits once, parried shots reflect once and clip on walls, kegs explode once, hype/bouncer/thrower roles change play"

func run() -> void:
	var game := await lab.start_game()
	Music.stop(0.0)
	var horde := game.horde
	game.player.set_physics_process(false)
	horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	horde.action_killed.connect(_on_action)
	horde.enemy_killed.connect(_on_killed)
	await _kick_bodies(game)
	await _wall_splat(game)
	await _stomp_wall(game)
	await _shatter(game)
	await _reflect(game)
	await _kegs(game)
	await _hype(game)
	await _bouncer(game)
	await _thrower(game)
	horde.action_killed.disconnect(_on_action)
	horde.enemy_killed.disconnect(_on_killed)
	game.player.set_physics_process(true)
	horde.set_physics_process(true)

func _on_action(members: int, _position: Vector3, label: String) -> void:
	_actions.append({"members": members, "label": label})

func _on_killed(_definition: HordeEnemyDefinition, _position: Vector3) -> void:
	_kills += 1

func _members(label: String) -> int:
	var total := 0
	for action in _actions:
		if action["label"] == label:
			total += int(action["members"])
	return total

func _emissions(label: String) -> int:
	var count := 0
	for action in _actions:
		if action["label"] == label:
			count += 1
	return count

func _reset(game: ArenaGame, stand: Vector3 = Vector3(0, 1, 4), look: Vector3 = Vector3(0, 1, 9)) -> void:
	game.horde.clear()
	_simulate(game.horde, 1.0)
	_actions.clear()
	_kills = 0
	game.player.velocity = Vector3.ZERO
	game.player.global_position = stand
	lab.aim_at(look)

func _simulate(horde: Horde, seconds: float) -> void:
	for tick in ceili(seconds / STEP):
		horde._physics_process(STEP)

func _spawn(game: ArenaGame, id: String, xz: Vector2, health: float = -1.0) -> int:
	var definition := lab.enemy(id)
	game.horde.register_definition(definition)
	var slot := game.horde.spawn(definition, xz, 1.0 if health <= 0.0 else health / definition.max_health)
	game.horde._rebuild_grid()
	return slot

func _eye(game: ArenaGame) -> Vector3:
	return game.player.camera.global_position

func _forward(game: ArenaGame) -> Vector3:
	return -game.player.camera.global_basis.z

func _kick(game: ArenaGame) -> bool:
	return game.horde.kick(_eye(game), _forward(game), false, false)

func _kick_bodies(game: ArenaGame) -> void:
	var horde := game.horde
	_reset(game)
	var slot := _spawn(game, "robot_grunt", Vector2(0, 5.6))
	var before: float = horde._hp[slot]
	lab.check(_kick(game), "a fresh kick touches the live body in front")
	lab.check(is_equal_approx(before - horde._hp[slot], Horde.KICK_DAMAGE), "kick removes exactly its damage once")
	lab.check(horde.is_launched(slot), "a light body is launched")
	var start: Vector2 = horde._pos[slot]
	_simulate(horde, 0.2)
	lab.check(horde.combo_flags(slot) & Horde.AIRBORNE != 0, "launched body is actually airborne")
	_simulate(horde, 0.6)
	lab.check(horde._pos[slot].y - start.y > 3.0, "the launch carries the body several metres along the kick")
	await lab.capture("launch")
	_reset(game)
	var tank := _spawn(game, "robot_tank", Vector2(0, 5.9))
	start = horde._pos[tank]
	lab.check(_kick(game), "kick reaches a heavy body")
	lab.check(horde.is_stunned(tank) and not horde.is_launched(tank), "heavy body staggers instead of launching")
	_simulate(horde, 0.3)
	lab.check(horde.combo_flags(tank) & Horde.AIRBORNE == 0 and horde._pos[tank].distance_to(start) < 1.2, "heavy body stays grounded and constrained")
	_reset(game)
	var far := _spawn(game, "robot_grunt", Vector2(0, 8.5))
	lab.check(not _kick(game) and horde.enemy_health_fraction(far) == 1.0, "bodies beyond kick reach are untouched")
	_reset(game)
	var bulwark := _spawn(game, "robot_bulwark", Vector2(0, 5.9))
	horde._yaw[bulwark] = 0.0
	before = horde._hp[bulwark]
	_kick(game)
	lab.check(is_equal_approx(before - horde._hp[bulwark], Horde.KICK_DAMAGE * lab.enemy("robot_bulwark").front_damage_scale), "a kick into the front plate respects the plate")
	lab.check(not horde.is_launched(bulwark), "a plated heavy body is never launched")

## An authored box obstacle with open floor on one face, and a free spot behind it.
func _find_wall(horde: Horde) -> Dictionary:
	for o in horde._obstacle_center.size():
		if horde._obstacle_circle[o] != 0 or horde._obstacle_bottom[o] > 0.2 or horde._obstacle_top[o] < 1.8:
			continue
		var center: Vector2 = horde._obstacle_center[o]
		var half: Vector2 = horde._obstacle_half[o]
		if half.y < 0.7 or half.x > 3.0:
			continue
		for side in [1.0, -1.0]:
			var face: float = center.x + side * half.x
			var enemy := Vector2(face + side * 1.1, center.y)
			var stand := Vector2(face + side * 2.8, center.y)
			var behind := Vector2(center.x - side * (half.x + 1.2), center.y)
			var clear := true
			for point in [enemy, stand, behind, (enemy + stand) * 0.5]:
				if horde.is_blocked(point, 0.5) or absf(horde.ground_height(point) - horde.ground_height(stand)) > 0.05:
					clear = false
			if not clear:
				continue
			var floor_y := horde.ground_height(stand)
			if not horde._lane_clear(Vector3(stand.x, floor_y + 1.0, stand.y), Vector3(enemy.x, floor_y + 0.9, enemy.y)):
				continue
			if horde._lane_clear(Vector3(stand.x, floor_y + 1.4, stand.y), Vector3(behind.x, floor_y + 0.9, behind.y)):
				continue
			return {"face": face, "side": side, "enemy": enemy, "stand": stand, "behind": behind, "floor": floor_y}
	return {}

func _wall_splat(game: ArenaGame) -> void:
	var horde := game.horde
	var wall := _find_wall(horde)
	lab.check(not wall.is_empty(), "authored arena offers a real wall face for impacts")
	if wall.is_empty():
		return
	var floor_y: float = wall["floor"]
	var stand: Vector2 = wall["stand"]
	var enemy: Vector2 = wall["enemy"]
	_reset(game, Vector3(stand.x, floor_y + 1.0, stand.y), Vector3(enemy.x, floor_y + 0.9, enemy.y))
	var slot := _spawn(game, "robot_grunt", enemy, 40.0)
	lab.check(_kick(game), "kick toward the wall connects")
	var face: float = wall["face"]
	var side: float = wall["side"]
	var crossed := false
	for tick in 30:
		horde._physics_process(STEP)
		if (horde._pos[slot].x - face) * side < horde.enemy_radius(slot) - 0.05 and horde._state[slot] != Horde.FREE:
			crossed = true
	lab.check(not crossed, "launched body never passes through the collider face")
	lab.check(not horde.is_alive(slot), "the wall splat finishes the kicked body")
	lab.check(_emissions("WALL SPLAT") == 1 and _members("WALL SPLAT") == 1 and _kills == 1, "wall splat credits its kill exactly once")

func _stomp_wall(game: ArenaGame) -> void:
	_reset(game)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 6.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = Vector3(0.0, 2.5, 7.0)
	var slot := _spawn(game, "robot_grunt", Vector2(0.0, 6.5))
	await lab.frames(3)
	var hp := game.horde._hp[slot]
	var touched := game.horde.kick(Vector3(0.0, 3.0, 8.5), Vector3.FORWARD, false, true)
	lab.check(not touched and game.horde._hp[slot] == hp, "an airborne stomp cannot hit a body through a real dividing wall")
	wall.queue_free()
	await lab.frames(2)

func _shatter(game: ArenaGame) -> void:
	var horde := game.horde
	_reset(game)
	var target := _spawn(game, "robot_grunt", Vector2(0, 5.6), 25.0)
	horde.damage(target, 1.0, Vector3.ZERO, DamageType.Kind.FROST)
	lab.check(horde.combo_flags(target) & Horde.FROZEN != 0, "actual FROST damage marks the body frozen")
	for xz in [Vector2(-1.0, 7.4), Vector2(1.0, 7.4), Vector2(0, 7.9)]:
		_spawn(game, "robot_grunt", xz, 0.5)
	var tough := _spawn(game, "robot_grunt", Vector2(1.6, 6.9), 9000.0)
	_actions.clear()
	_kills = 0
	lab.check(_kick(game), "kick reaches the frozen body")
	lab.check(_members("KICK") == 1 and _members("SHATTER") == 3 and _emissions("SHATTER") == 1, "kick kill and one shatter burst are each credited once")
	lab.check(_kills == 4, "every shattered life dies exactly once")
	lab.check(horde.is_alive(tough) and not horde.is_launched(tough) and horde.combo_flags(tough) & Horde.FROZEN == 0, "shatter never launches or freezes survivors without the build")
	await lab.capture("shatter")
	game.grant_upgrade(SHATTER_UPGRADE)
	_reset(game)
	target = _spawn(game, "robot_grunt", Vector2(0, 5.6), 25.0)
	horde.damage(target, 1.0, Vector3.ZERO, DamageType.Kind.FROST)
	var edge := _spawn(game, "robot_grunt", Vector2(0, 9.0), 0.5)
	tough = _spawn(game, "robot_grunt", Vector2(1.6, 6.9), 9000.0)
	_kick(game)
	lab.check(not horde.is_alive(edge), "build_shatter widens the burst to a body 3.4 m away")
	lab.check(horde.combo_flags(tough) & Horde.FROZEN != 0 and not horde.is_launched(tough), "build_shatter re-freezes survivors without recursion")
	game.run_state.upgrade_levels.erase(&"build_shatter")

func _parry_from(game: ArenaGame, distance: float) -> bool:
	var eye := _eye(game)
	var forward := _forward(game)
	game.horde.launch_projectile(eye + forward * distance, -forward * 9.0, 3.0)
	return game.horde.parry_projectile(eye, forward, 3.2)

func _reflect(game: ArenaGame) -> void:
	var horde := game.horde
	_reset(game, Vector3(0, 1, 4), Vector3(0, 1, 12))
	var slot := _spawn(game, "robot_grunt", Vector2(0, 12), 60.0)
	var grunt_type: int = horde._type[slot]
	horde._t_speed[grunt_type] = 0.0
	lab.check(_parry_from(game, 1.5), "parry reflects a live projectile in front")
	lab.check(not horde.parry_projectile(_eye(game), _forward(game), 3.2), "a returned projectile cannot be reflected again")
	_simulate(horde, 0.8)
	lab.check(not horde.is_alive(slot) and _members("RETURN") == 1 and _emissions("RETURN") == 1, "returned shot kills and credits once")
	lab.check(horde._shot_count == 0, "returned shot is consumed on impact")
	# Homing only with build_return: an off-axis return misses at rank 0.
	_reset(game, Vector3(0, 1, 4), Vector3(2.5, 1, 12))
	slot = _spawn(game, "robot_grunt", Vector2(0, 12), 120.0)
	_parry_from(game, 1.5)
	_simulate(horde, 1.2)
	lab.check(horde.is_alive(slot), "rank-0 return flies straight past an off-axis body")
	game.grant_upgrade(RETURN_UPGRADE)
	_reset(game, Vector3(0, 1, 4), Vector3(2.5, 1, 12))
	slot = _spawn(game, "robot_grunt", Vector2(0, 12), 120.0)
	_parry_from(game, 1.5)
	_simulate(horde, 1.2)
	lab.check(not horde.is_alive(slot), "build_return homes and doubles damage to kill the same body")
	game.run_state.upgrade_levels.erase(&"build_return")
	var wall := _find_wall(horde)
	if not wall.is_empty():
		_reflect_through_wall(game, wall)
	horde._t_speed[grunt_type] = lab.enemy("robot_grunt").speed

func _reflect_through_wall(game: ArenaGame, wall: Dictionary) -> void:
	var horde := game.horde
	var floor_y: float = wall["floor"]
	var stand: Vector2 = wall["stand"]
	var behind: Vector2 = wall["behind"]
	_reset(game, Vector3(stand.x, floor_y + 1.0, stand.y), Vector3(behind.x, floor_y + 0.9, behind.y))
	var slot := _spawn(game, "robot_grunt", behind, 30.0)
	_parry_from(game, 1.2)
	_simulate(horde, 1.0)
	lab.check(horde.is_alive(slot) and horde.enemy_health_fraction(slot) == 1.0, "a wall between clips the returned shot")
	lab.check(horde._shot_count == 0 and _actions.is_empty(), "clipped shot ends without credit")

func _kegs(game: ArenaGame) -> void:
	var horde := game.horde
	_reset(game)
	var keg := PinballProp.new()
	game.add_child(keg)
	keg.global_position = Vector3(0, horde.ground_height(Vector2(0, 6)), 6)
	keg.setup(horde, game.player)
	keg.exploded.connect(_on_exploded)
	_explosions = 0
	for xz in [Vector2(-0.6, 9.5), Vector2(0.6, 9.5), Vector2(0, 10.2)]:
		_spawn(game, "robot_grunt", xz, 5.0)
	await lab.frames(2)
	lab.check(keg.kick(Vector3(0, 0, 1)), "a set-up keg accepts a kick")
	for frame in 120:
		await lab.get_tree().physics_frame
		if keg.is_spent():
			break
	lab.check(keg.is_spent() and _explosions == 1, "kicked keg detonates on reaching the crowd")
	lab.check(_members("KEG") == 3 and _emissions("KEG") == 1 and _kills == 3, "keg blast credits its kills once")
	await lab.capture("keg")
	lab.check(not keg.kick(Vector3(0, 0, 1)), "a spent keg cannot be kicked again")
	keg.take_hit(100.0, keg.global_position)
	await lab.frames(2)
	lab.check(_explosions == 1 and _emissions("KEG") == 1, "a spent keg never explodes twice")
	keg.queue_free()
	_reset(game)
	var shot := PinballProp.new()
	game.add_child(shot)
	shot.global_position = Vector3(0, horde.ground_height(Vector2(0, 8)), 8)
	shot.setup(horde, game.player)
	_spawn(game, "robot_grunt", Vector2(1.0, 8.5), 5.0)
	shot.take_hit(PinballProp.MAX_HEALTH, shot.global_position)
	lab.check(shot.is_spent() and _members("KEG") == 1, "shooting a keg detonates it in place")
	shot.queue_free()

func _on_exploded(_center: Vector3) -> void:
	_explosions += 1

func _hype(game: ArenaGame) -> void:
	var horde := game.horde
	_reset(game)
	var hype := _spawn(game, "hype_man", Vector2(0, 14))
	# The source holds still so the measured window stays inside its aura.
	var hype_type: int = horde._type[hype]
	horde._t_speed[hype_type] = 0.0
	horde._cooldown[hype] = 99.0
	var grunt := _spawn(game, "robot_grunt", Vector2(2, 14))
	_simulate(horde, 0.3)
	lab.check(horde.hype_level(grunt) >= 1, "an ally inside the aura is hyped")
	var health_before: float = horde._hp[grunt]
	var start: Vector2 = horde._pos[grunt]
	_simulate(horde, 0.25)
	var hyped_speed: float = horde._pos[grunt].distance_to(start) / 0.25
	lab.check(hyped_speed > lab.enemy("robot_grunt").speed * 1.15, "hype actually speeds the ally up")
	lab.check(horde._hp[grunt] == health_before, "hype never heals or adds health")
	await lab.capture("hype")
	horde.damage(hype, 1.0e6)
	horde._t_speed[hype_type] = lab.enemy("hype_man").speed
	_simulate(horde, 0.45)
	lab.check(horde.hype_level(grunt) == 0, "the buff ceases once the source dies")
	start = horde._pos[grunt]
	_simulate(horde, 0.25)
	lab.check(horde._pos[grunt].distance_to(start) / 0.25 < lab.enemy("robot_grunt").speed * 1.08, "ally returns to its normal pace")
	lab.check(_actions.is_empty(), "external deaths never earn pinball credit")

func _bouncer(game: ArenaGame) -> void:
	var horde := game.horde
	var player := game.player
	_reset(game)
	var bouncer := _spawn(game, "bouncer", Vector2(0.3, 4.6))
	horde._cooldown[bouncer] = 99.0
	horde._physics_process(STEP)
	var reach := horde.enemy_radius(bouncer) + Horde.PLAYER_RADIUS
	var flat := Vector2(player.global_position.x, player.global_position.z)
	lab.check(flat.distance_to(horde._pos[bouncer]) >= reach - 0.03, "a bouncer physically pushes the player out of its body")
	_reset(game)
	bouncer = _spawn(game, "bouncer", Vector2(0, 6.4))
	horde._cooldown[bouncer] = 0.0
	_simulate(horde, 0.1)
	lab.check(horde._mode[bouncer] == Horde.Mode.WINDUP, "an adjacent bouncer telegraphs its shove")
	_simulate(horde, 0.8)
	lab.check(player.velocity.z < -5.0, "a landed shove throws the player back")
	_reset(game)
	bouncer = _spawn(game, "bouncer", Vector2(0, 6.4))
	horde._cooldown[bouncer] = 0.0
	_simulate(horde, 0.1)
	player.global_position = Vector3(3.2, 1, 6.4)
	_simulate(horde, 0.8)
	lab.check(player.velocity.length() < 0.5, "sidestepping the committed windup dodges the shove")
	_reset(game)
	bouncer = _spawn(game, "bouncer", Vector2(0, 6.4))
	horde._cooldown[bouncer] = 0.0
	_simulate(horde, 0.1)
	_kick(game)
	lab.check(horde.is_stunned(bouncer) and not horde.is_launched(bouncer) and horde._mode[bouncer] == Horde.Mode.SEEK, "a kick staggers the bouncer out of its windup")

func _thrower(game: ArenaGame) -> void:
	var horde := game.horde
	var player := game.player
	for dodge in [false, true]:
		_reset(game)
		player._invulnerable = 0.0
		player.health = player.max_health
		var thrower := _spawn(game, "bottle_thrower", Vector2(0, 14))
		horde._cooldown[thrower] = 0.0
		var thrown := false
		for tick in 120:
			horde._physics_process(STEP)
			if horde._shot_count > 0:
				thrown = horde._shot_flags[0] & Horde.SHOT_LOBBED != 0
				break
		lab.check(thrown, "the thrower lobs a bottle after its windup")
		if dodge:
			player.global_position = Vector3(4, 1, 4)
		var before := player.health
		horde._cooldown[thrower] = 99.0
		_simulate(horde, 2.0)
		if dodge:
			lab.check(player.health == before, "leaving the committed spot dodges the bottle")
		else:
			lab.check(player.health < before, "staying on the spot takes the bottle splash")
	player.grant_invulnerability(1.0e9)
