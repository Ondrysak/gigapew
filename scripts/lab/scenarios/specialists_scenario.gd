extends LabScenario

## New attack/counterplay paths through real Horde, weapon rays, roof colliders,
## F input, finite encounter cleanup and the actual SFX bus.
const STEP := 1.0 / 60.0
var _actions: Array[Dictionary] = []
var _kills := 0
var _scores: Array[String] = []

func title() -> String:
	return "Masta Blasta, Tarzan and absinthe"

func summary() -> String:
	return "Committed rushes, geometric backpack hits, kicked and executed corpse bombs, physical ceiling ambushes, ignitable floor fuel and sourced positional Kára calls"

func run() -> void:
	var game := await lab.start_game()
	game.player.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	game.horde.action_killed.connect(_on_action)
	game.horde.enemy_killed.connect(_on_killed)
	game.player.arena_scored.connect(_on_score)
	await _bomber(game)
	await _finisher_bomb(game)
	await _ambusher(game)
	await _fuel(game)
	await _dialogue(game)
	game.horde.action_killed.disconnect(_on_action)
	game.horde.enemy_killed.disconnect(_on_killed)
	game.player.arena_scored.disconnect(_on_score)
	game.free()
	await _venue_casts()

func _on_action(members: int, _at: Vector3, label: String) -> void:
	_actions.append({"members": members, "label": label})

func _on_killed(_definition: HordeEnemyDefinition, _at: Vector3) -> void:
	_kills += 1

func _on_score(_points: int, label: String) -> void:
	_scores.append(label)

func _credited() -> int:
	var total := 0
	for event in _actions:
		total += int(event.members)
	return total

func _reset(game: ArenaGame, stand := Vector3(0, 1, 4)) -> void:
	Input.action_release(&"mine")
	Input.action_release(&"fire")
	game.player.cancel_actions()
	game.horde.clear()
	_simulate(game.horde, 1.0)
	game.player.global_position = stand
	game.player.velocity = Vector3.ZERO
	game.player.health = game.player.max_health
	game.player.grant_invulnerability(1.0e9)
	game.player.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.voice.stop()
	_actions.clear()
	_kills = 0
	_scores.clear()

func _simulate(horde: Horde, seconds: float) -> void:
	for tick in ceili(seconds / STEP):
		horde._physics_process(STEP)

func _spawn(game: ArenaGame, id: String, point: Vector2, health := -1.0) -> int:
	var definition := lab.enemy(id)
	game.horde.register_definition(definition)
	var slot := game.horde.spawn(definition, point, 1.0 if health < 0.0 else health / definition.max_health)
	if slot < 0:
		lab.check(false, "%s fixture could not admit its body at %s" % [id, point])
	if slot >= 0:
		game.horde._cooldown[slot] = 99.0
	game.horde._rebuild_grid()
	return slot

func _bomber(game: ArenaGame) -> void:
	var horde := game.horde
	_reset(game)
	var slot := _spawn(game, "masta_blasta", Vector2(0, 9))
	if slot < 0: return
	horde._cooldown[slot] = 0.0
	_simulate(horde, 0.1)
	lab.aim_at(horde.enemy_position(slot))
	var start := horde.enemy_position(slot)
	_simulate(horde, 0.55)
	lab.check(horde.is_alive(slot) and horde.enemy_position(slot).distance_to(start) < 0.1, "Masta Blasta gives a stationary arming warning rather than an instant rush")
	await lab.capture("blasta_arming")
	game.player.global_position.x = 7.0
	_simulate(horde, 0.75)
	var committed := horde._aim[slot]
	lab.check(absf(committed.x) < 0.05, "the armed rush keeps its warned lane after the player sidesteps")
	_simulate(horde, 2.4)
	lab.check(not horde.is_alive(slot) and _actions.is_empty(), "hostile self-detonation finishes its real life without manual STYLE credit")

	_reset(game, Vector3(0, 1, 14))
	slot = _spawn(game, "masta_blasta", Vector2(0, 9))
	if slot < 0: return
	horde._yaw[slot] = 0.0
	horde.damage_direct(slot, 1.0, game.player.camera.global_position, Vector3.ZERO, DamageType.Kind.KINETIC, true)
	_simulate(horde, 0.25)
	lab.check(horde.is_alive(slot) and not horde.specialist_actions_pending(), "a lucky critical is not a geometric backpack hit")
	var neighbor := _spawn(game, "robot_grunt", Vector2(1.8, 9), 50.0)
	lab.equip_weapon("pulse")
	# The seek tick above turns toward the player; restore the warned back-facing pose.
	horde._yaw[slot] = 0.0
	lab.aim_at(horde.weak_spot_position(slot))
	await lab.frames(2)
	await lab.capture("blasta_backpack")
	game.player._shoot(false)
	lab.check(horde.specialist_actions_pending(), "an actual gun ray through the visible backpack arms a delayed blast")
	_simulate(horde, 0.4)
	lab.check(not horde.is_alive(slot) and not horde.is_alive(neighbor) and _credited() == _kills, "backpack blast credits each real victim exactly once (credited=%d kills=%d)" % [_credited(), _kills])
	_simulate(horde, 1.5)
	lab.check(_credited() == _kills and not horde.specialist_actions_pending(), "a resolved backpack blast cannot repeat after its source is recycled")

	_reset(game, Vector3(0, 1, 14))
	slot = _spawn(game, "masta_blasta", Vector2(0, 9))
	if slot < 0: return
	var shielded := _spawn(game, "robot_grunt", Vector2(2.4, 9), 50.0)
	var barrier := StaticBody3D.new()
	barrier.position = Vector3(1.2, 1.5, 9)
	barrier.collision_layer = 1
	var barrier_shape := BoxShape3D.new()
	barrier_shape.size = Vector3(0.2, 3.0, 8.0)
	var barrier_collision := CollisionShape3D.new()
	barrier_collision.shape = barrier_shape
	barrier.add_child(barrier_collision)
	game.world.get_node("Obstacles").add_child(barrier)
	for frame in 3: await lab.get_tree().physics_frame
	horde.damage_direct(slot, 1.0, game.player.camera.global_position, Vector3.ZERO, DamageType.Kind.KINETIC, false, true)
	_simulate(horde, 0.2)
	lab.check(not horde.is_alive(slot) and horde.is_alive(shielded) and horde._hp[shielded] == 50.0, "a thin real wall occludes backpack splash even inside the nominal blast radius")
	barrier.free()

	_reset(game)
	slot = _spawn(game, "masta_blasta", Vector2(0, 5.7))
	if slot < 0: return
	var victim := _spawn(game, "robot_grunt", Vector2(0, 11), 50.0)
	game.player._invulnerable = 0.0
	var before := game.player.health
	lab.aim_at(horde.enemy_position(slot))
	var kicked := horde.kick(game.player.camera.global_position, -game.player.head.global_basis.z, false, false)
	lab.check(kicked and horde.is_launched(slot) and horde.specialist_actions_pending(), "RMB counterplay launches an armed live bomber instead of a canned explosion")
	var launch := horde.enemy_position(slot)
	_simulate(horde, 0.2)
	lab.check(horde.enemy_position(slot).distance_to(launch) > 1.0, "the reversed bomber actually travels through the arena")
	await lab.capture("blasta_kicked")
	_simulate(horde, 1.2)
	lab.check(not horde.is_alive(slot) and not horde.is_alive(victim) and game.player.health == before, "kicking the bomb into its crowd kills victims without punishing the player")
	lab.check(_credited() == _kills, "kick and delayed blast retain exact-once represented kill credit")
	game.player.grant_invulnerability(1.0e9)

func _finisher_bomb(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var player := game.player
	var slot := _spawn(game, "masta_blasta", Vector2(0, 9.5), 100.0)
	if slot < 0: return
	horde.damage(slot, 80.0)
	# A stunned victim cannot pick a random flanking lane out of the throw path.
	horde.stun(_spawn(game, "robot_grunt", Vector2(0, 18), 45.0), 3.0)
	player.set_physics_process(true)
	lab.aim_at(horde.enemy_position(slot))
	for frame in 3: await lab.get_tree().physics_frame
	lab.check(player.finisher_ready(), "the dazed bomber remains selectable through the real aimed F prompt")
	Input.action_press(&"mine")
	for frame in 2: await lab.get_tree().physics_frame
	Input.action_release(&"mine")
	lab.check(player.is_finishing(), "fresh F starts an actual leaping finisher against the bomber")
	horde.set_physics_process(true)
	await lab.capture_strip("blasta_finisher_motion", 12, 0.09)
	await lab.wait(0.35)
	lab.check(not horde.is_alive(slot) and not player.is_finishing() and _credited() == _kills and _kills >= 2, "finisher throws the corpse forward and its delayed blast credits original and crowd victims once (alive=%s finishing=%s credited=%d kills=%d)" % [horde.is_alive(slot), player.is_finishing(), _credited(), _kills])
	horde.set_physics_process(false)
	player.set_physics_process(false)

	_reset(game)
	slot = _spawn(game, "masta_blasta", Vector2(0, 5.7), 100.0)
	if slot < 0: return
	horde.damage(slot, 80.0)
	lab.check(horde.finish(slot, horde.enemy_generation(slot), player.camera.global_position), "successful close execution creates a real delayed corpse bomb")
	var director := HordeDirector.new()
	game.add_child(director)
	director.setup(horde, game.campaign[0].schedule, player, 918, 1)
	director.set_physics_process(false)
	director.encounter_index = 1
	director._set_phase("CLEANUP")
	director._physics_process(10.0)
	lab.check(horde.population_count == 0 and horde.specialist_actions_pending() and not director.finished, "cleanup waits for a corpse bomb without pretending the corpse is another living enemy")
	_simulate(horde, 2.0)
	director._physics_process(0.1)
	lab.check(director.phase_name == "BOSS_PENDING" and not director.finished and not horde.specialist_actions_pending() and _credited() == 1, "the real delayed resolution releases final cleanup into boss admission, never a free stage clear")
	director.free()

func _roof(game: ArenaGame) -> StaticBody3D:
	var roof := StaticBody3D.new()
	roof.name = "SpecialistFixtureRoof"
	roof.collision_layer = 1
	roof.set_meta("roof", true)
	roof.position = Vector3(0, 4.6, 12)
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 0.4, 12)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	roof.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.19, 0.16)
	mesh.material_override = material
	roof.add_child(mesh)
	game.world.get_node("Obstacles").add_child(roof)
	return roof

func _ambusher(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var definition := lab.enemy("tarzan")
	horde.register_definition(definition)
	var population := horde.population_count
	lab.check(horde.spawn(definition, Vector2(0, 12)) == -1 and horde.population_count == population, "Tarzan cannot appear floating in an uncovered street or consume phantom population")
	var roof := _roof(game)
	for frame in 3: await lab.get_tree().physics_frame
	horde._read_obstacles(game.world.get_node("Obstacles"))
	game.player.global_position = Vector3(0, 1, 8)
	var slot := _spawn(game, "tarzan", Vector2(0, 12))
	if slot < 0:
		roof.free()
		return
	var high := horde.enemy_position(slot)
	lab.check(high.y > 3.0 and (horde.combo_flags(slot) & Horde.AIRBORNE) != 0, "the actual roof holds Tarzan's shootable body above the floor")
	lab.aim_at(high)
	_simulate(horde, 0.12)
	await lab.capture("tarzan_warning")
	var landing := horde._attack_target[slot]
	game.player.global_position.x = 5.0
	_simulate(horde, 0.5)
	lab.check(horde.enemy_position(slot).y > 3.0 and horde._attack_target[slot].is_equal_approx(landing), "ceiling warning lasts and its landing target does not follow a dodge")
	_simulate(horde, 0.65)
	await lab.capture("tarzan_falling")
	_simulate(horde, 0.7)
	lab.check(horde.enemy_position(slot).y < 1.0 and horde._mode[slot] == Horde.Mode.RECOVER, "the ambusher physically drops to the floor then offers a recovery window")

	_reset(game, Vector3(0, 1, 8))
	slot = _spawn(game, "tarzan", Vector2(0, 12))
	if slot >= 0:
		var y := horde.enemy_position(slot).y
		horde.damage_direct(slot, 5.0, game.player.camera.global_position)
		_simulate(horde, 0.25)
		lab.check(horde.is_alive(slot) and horde.enemy_position(slot).y < y - 0.2, "a real gun hit knocks a ceiling enemy loose while it remains damageable")
		_simulate(horde, 0.2)
		game.player.global_position = horde.enemy_position(slot) + Vector3(0, -0.6, -1.5)
		lab.aim_at(horde.enemy_position(slot))
		lab.check(horde.kick(game.player.camera.global_position, -game.player.head.global_basis.z, false, false) and horde.is_launched(slot), "a midair kick turns the falling maintenance worker into a live projectile")
		lab.equip_weapon("rail")
		lab.aim_at(horde.enemy_position(slot))
		game.player._shoot(false)
		lab.check(not horde.is_alive(slot) and _scores.has("AIR MAIL"), "rail AIR MAIL consumes the actual airborne kicked body and reports its distinctive score")
	_reset(game)
	roof.free()
	for frame in 2: await lab.get_tree().physics_frame
	horde._read_obstacles(game.world.get_node("Obstacles"))

func _fuel_count(game: ArenaGame, burning := false) -> int:
	var count := 0
	for index in game.horde._specialists._fuel_life.size():
		if game.horde._specialists._fuel_life[index] > 0.0 and (not burning or game.horde._specialists._fuel_burning[index] != 0):
			count += 1
	return count

func _make_fuel(game: ArenaGame, warning_capture := false) -> bool:
	var slot := _spawn(game, "polejvac", Vector2(0, 13))
	if slot < 0: return false
	game.horde._cooldown[slot] = 0.0
	_simulate(game.horde, 0.15)
	lab.aim_at(game.horde.enemy_position(slot))
	if warning_capture:
		await lab.capture("polejvac_warning")
	_simulate(game.horde, 3.4)
	game.horde._cooldown[slot] = 99.0
	return _fuel_count(game) > 0

func _fuel(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var poured := await _make_fuel(game, true)
	lab.check(poured and _fuel_count(game, true) == 0, "the real committed spray leaves finite green liquid on a supported floor")
	if not poured: return
	game.player._invulnerable = 0.0
	var wet := game.player.health
	_simulate(horde, 0.5)
	lab.check(game.player.health == wet, "unlit absinthe is not an invisible damaging floor")
	game.player.global_position = Vector3(4, 1, 4)
	var slot := _spawn(game, "robot_grunt", Vector2(0, 4), 45.0)
	var survivor := _spawn(game, "robot_grunt", Vector2(1.2, 4), 250.0)
	horde.stun(survivor, 2.0)
	lab.equip_weapon("flamethrower")
	lab.aim_at(Vector3(0, 0.04, 4))
	await lab.capture("absinthe_liquid")
	game.player._shoot(false)
	lab.check(_fuel_count(game, true) > 0 and not horde.is_alive(slot) and _credited() == 1, "actual FIRE primary rays ignite bare-floor fuel and credit the upfront blast victim once")
	await lab.capture("absinthe_ignition")
	var hp := horde._hp[survivor]
	var credit := _credited()
	_simulate(horde, 1.0)
	lab.check(horde._hp[survivor] < hp and _credited() == credit, "finite fire keeps burning survivors without echoing manual ignition credit")
	_simulate(horde, 10.0)
	lab.check(_fuel_count(game) == 0, "fuel and fire expire rather than permanently carpeting an arena")

	_reset(game)
	if not await _make_fuel(game): return
	var wall := StaticBody3D.new()
	wall.position = Vector3(2, 1.5, 4)
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 3.0, 6.0)
	collision.shape = shape
	wall.add_child(collision)
	game.world.get_node("Obstacles").add_child(wall)
	for frame in 3: await lab.get_tree().physics_frame
	game.player.global_position = Vector3(4, 1, 4)
	lab.aim_at(Vector3(0, 0.04, 4))
	game.player._shoot(false)
	lab.check(_fuel_count(game, true) == 0, "a real wall clips FIRE rays before the fuel on its far side")
	wall.free()
	for frame in 2: await lab.get_tree().physics_frame
	# An automatic FIRE source can ignite liquid, but cannot masquerade as a
	# manual counterplay action merely because its burst killed a real enemy.
	var automatic := _spawn(game, "robot_grunt", Vector2(0, 4), 45.0)
	horde.damage(automatic, 1.0, Vector3.ZERO, DamageType.Kind.FIRE)
	lab.check(not horde.is_alive(automatic) and _fuel_count(game, true) > 0 and _actions.is_empty(), "automatic FIRE ignition damages the crowd without inventing manual STYLE")
	horde.clear()
	lab.check(_fuel_count(game) == 0 and not horde.specialist_actions_pending(), "stage clearing removes all finite specialist hazards and delayed damage")

func _dialogue(game: ArenaGame) -> void:
	_reset(game)
	var master := AudioServer.get_bus_index(&"Master")
	var sfx := AudioServer.get_bus_index(&"SFX")
	var muted := AudioServer.is_bus_mute(master)
	var sfx_muted := AudioServer.is_bus_mute(sfx)
	var sfx_db := AudioServer.get_bus_volume_db(sfx)
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_mute(sfx, false)
	AudioServer.set_bus_volume_db(sfx, 0.0)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var effect := AudioServer.get_bus_effect_count(sfx)
	AudioServer.add_bus_effect(sfx, capture)
	game.kara._voice.stop()
	game.kara._gap = 0.0
	game.kara._priority = -1
	for key: StringName in game.kara._cooldowns: game.kara._cooldowns[key] = 0.0
	var slot := _spawn(game, "polejvac", Vector2(0, 10))
	if slot >= 0:
		game.horde._cooldown[slot] = 0.0
		capture.clear_buffer()
		_simulate(game.horde, 0.1)
		# Positional playback starts on a physics tick, then the mixer fills
		# the bus; accept the first audible PCM within one second.
		var started := Time.get_ticks_msec()
		var energy := 0.0
		var sampled := 0
		while Time.get_ticks_msec() - started < 1000 and (sampled == 0 or sqrt(energy / sampled) <= 0.001):
			await lab.wait(0.05)
			for sample in capture.get_buffer(capture.get_frames_available()):
				energy += sample.length_squared() * 0.5
				sampled += 1
		var latency := Time.get_ticks_msec() - started
		lab.check(game.kara.last_clip == &"ohen" and sampled > 0 and sqrt(energy / sampled) > 0.001, "the sprayer's real warning routes the downloaded ohen MP3 into actual SFX PCM within %d ms" % latency)
		await lab.capture("kara_callout")
		var played := game.kara.played_count
		_simulate(game.horde, 0.2)
		lab.check(game.kara.played_count == played, "one attack warning does not restart its dialogue every physics frame")
	AudioServer.remove_bus_effect(sfx, effect)
	AudioServer.set_bus_mute(master, muted)
	AudioServer.set_bus_mute(sfx, sfx_muted)
	AudioServer.set_bus_volume_db(sfx, sfx_db)
	var guided := bool(Profile.settings.get("guided_start", true))
	Profile.set_setting("guided_start", true)
	for tip: StringName in [&"masta_blasta", &"tarzan", &"polejvac"]:
		game.hud.tutor.clear()
		game.hud.tutor.offer(tip)
		await lab.wait(0.3)
		await lab.capture("tip_" + String(tip))
	game.hud.tutor.clear()
	Profile.set_setting("guided_start", guided)

func _venue_casts() -> void:
	var game := await lab.start_game(&"scout", 0, true, 5501)
	var director := game.director
	game.player.set_physics_process(false)
	game.horde.set_physics_process(false)
	for kind: StringName in [&"hospoda", &"herna", &"nonstop", &"metro"]:
		for venue: Dictionary in (game.world as ProceduralWorld).combat_venues:
			if venue.kind != kind: continue
			director._venue = venue
			director.encounter_index = 2
			if kind in [&"hospoda", &"metro"]:
				var covered := false
				for lane: Dictionary in venue.lanes:
					if not (lane.roles as Array).has(&"ceiling"): continue
					for point: Vector3 in lane.points:
						var slot := game.horde.spawn(lab.enemy("tarzan"), Vector2(point.x, point.z))
						if slot >= 0:
							covered = game.horde.enemy_position(slot).y > float(venue.floor_y) + 2.0
							game.horde.clear()
							break
				lab.check(covered, "%s has an actual roof-supported ambusher admission, not just a lane label" % kind)
			break
	game.horde.clear()
	await lab.capture("specialist_venues")
