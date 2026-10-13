extends LabScenario

## Real RMB input against the real horde: every strike goes through the action
## map and ArenaPlayer._physics_process; credits are counted from the actual
## Horde.action_killed / ArenaPlayer.arena_scored signals.

var _actions: Array[String] = []
var _action_members := 0
var _scores: Array[String] = []
var _deaths := 0

func title() -> String:
	return "Pinball combat: kick, parry, combos"

func summary() -> String:
	return "RMB parry/kick/slide launch/stomp, AIR MAIL, shatter, flame burst, conduction, kegs, exact-once credit, budgeted healing, heavy stagger, ceilings, pause and death gating"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.director.set_physics_process(false)
	# Medkit drops would blur the healing ledger; the field is not under test.
	game.pickups.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	game.horde.action_killed.connect(_on_action_killed)
	game.horde.enemy_killed.connect(_on_enemy_killed)
	player.arena_scored.connect(_on_scored)
	lab.equip_weapon("rail")
	lab.check(game.run_state.equip_pair(_source(game, "rail"), _source(game, "scatter")), "fixture drafts a real rail + shotgun pair")
	player.refresh_weapon()
	await _kick_and_air_mail(game)
	await _kick_credit(game)
	await _finish_healing(game)
	await _parry(game)
	await _slide(game)
	await _stomp(game)
	await _heavy(game)
	await _combos(game)
	await _keg(game)
	await _movement_visuals(game)
	await _pause_and_death(game)

func _on_action_killed(members: int, _at: Vector3, label: String) -> void:
	_actions.append(label)
	_action_members += members

func _on_enemy_killed(_definition: HordeEnemyDefinition, _at: Vector3) -> void:
	_deaths += 1

func _on_scored(_points: int, label: String) -> void:
	_scores.append(label)

func _source(game: ArenaGame, id: String) -> WeaponDefinition:
	for source in game.run_state.available_weapons:
		if source.resource_path.get_file().get_basename() == id:
			return source
	return null

func _reset(game: ArenaGame, at: Vector3 = Vector3(0, 1, 12)) -> void:
	game.horde.clear()
	var player := game.player
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player._slide_left = 0.0
	player._kick_recovery = 0.0
	player._heal_budget = ArenaPlayer.FINISH_HEAL_BUDGET
	game.run_state.regen_per_second = 0.0
	player.last_action_label = ""
	await lab.frames(6)
	_actions.clear()
	_scores.clear()
	_action_members = 0
	_deaths = 0

func _spawn(game: ArenaGame, id: String, at: Vector2, health: float) -> int:
	var definition := lab.enemy(id)
	var slot := game.horde.spawn(definition, at, health / definition.max_health)
	game.horde._rebuild_grid()
	return slot

## One fresh RMB press through the action map, then release.
func _strike() -> void:
	Input.action_press(&"kick")
	await lab.frames(2)
	Input.action_release(&"kick")
	await lab.frames(2)

func _airborne(game: ArenaGame, slot: int) -> bool:
	return (game.horde.combo_flags(slot) & Horde.AIRBORNE) != 0

func _only(labels: Array[String], label: String) -> bool:
	return labels.size() == 1 and labels[0] == label

func _kick_and_air_mail(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	var grunt := _spawn(game, "robot_grunt", lab.ahead(1.6), 90000.0)
	lab.aim_at(game.horde.enemy_position(grunt))
	var grounded := not _airborne(game, grunt)
	var hp := game.horde._hp[grunt]
	player._shoot(false)
	var grounded_damage := hp - game.horde._hp[grunt]
	lab.check(grounded and grounded_damage > 0.0 and player.last_action_label != "AIR MAIL", "a grounded rail hit is ordinary damage")
	await _reset(game)
	grunt = _spawn(game, "robot_grunt", lab.ahead(1.6), 90000.0)
	lab.aim_at(game.horde.enemy_position(grunt))
	var rest_y := game.horde.enemy_position(grunt).y
	var score := player.arena_score
	var style := player.combo_hits
	var charge := player.drop_charge
	await _strike()
	lab.check(player.last_action_label == "KICK" and not player.kick_ready, "a fresh RMB kick connects with a real body and starts recovery")
	var air_damage := 0.0
	var apex := rest_y
	for frame in 40:
		await lab.get_tree().physics_frame
		var at := game.horde.enemy_position(grunt)
		apex = maxf(apex, at.y)
		if air_damage == 0.0 and _airborne(game, grunt) and at.y > rest_y + 0.3:
			lab.aim_at(at)
			hp = game.horde._hp[grunt]
			player._shoot(false)
			air_damage = hp - game.horde._hp[grunt]
	lab.check(apex > rest_y + 0.3, "the kick launches a light body into real flight (apex +%.2f m)" % (apex - rest_y))
	lab.check(air_damage >= grounded_damage * 1.8 and player.last_action_label == "AIR MAIL", "rail through a launched body pays AIR MAIL in the same primary transaction (%.0f vs %.0f)" % [air_damage, grounded_damage])
	lab.check(player.arena_score == score and player.combo_hits == style and player.drop_charge == charge and _actions.is_empty(), "nonlethal kick and AIR MAIL hits earn no score, STYLE or charge")
	await lab.capture("air_mail")
	# A lethal AIR MAIL is one primary credit, never an extra action credit.
	await _reset(game)
	grunt = _spawn(game, "robot_grunt", lab.ahead(1.6), 90000.0)
	lab.aim_at(game.horde.enemy_position(grunt))
	await _strike()
	var shot := false
	for frame in 40:
		await lab.get_tree().physics_frame
		if not shot and _airborne(game, grunt) and game.horde.enemy_position(grunt).y > rest_y + 0.3:
			game.horde._hp[grunt] = 1.0
			lab.aim_at(game.horde.enemy_position(grunt))
			player._shoot(false)
			shot = true
	await lab.wait(0.6)
	lab.check(shot and not game.horde.is_alive(grunt) and _only(_scores, "AIR MAIL") and _actions.is_empty(), "a lethal AIR MAIL credits its life exactly once as a primary kill")

func _kick_credit(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	player.health = player.max_health - 40
	var victim := _spawn(game, "robot_grunt", lab.ahead(1.5), 0.5)
	lab.aim_at(game.horde.enemy_position(victim))
	var style := player.combo_hits
	var charge := player.drop_charge
	var score := player.arena_score
	await _strike()
	await lab.wait(1.0)
	lab.check(not game.horde.is_alive(victim) and _action_members == 1 and _deaths == 1 and _only(_scores, "KICK"), "a lethal kick credits its defeated life exactly once (%s / %s)" % [_actions, _scores])
	lab.check(player.combo_hits == style + ArenaPlayer.ACTION_STYLE and player.drop_charge > charge and player.arena_score > score, "the kick kill awards STYLE, score and DROP charge")
	lab.check(player.health == player.max_health - 40 + ArenaPlayer.FINISH_HEAL, "a close kick finish heals one bounded step")
	await lab.wait(ArenaPlayer.KICK_RECOVERY)
	var health := player.health
	await _strike()
	await lab.wait(0.5)
	lab.check(_scores.size() == 1 and _action_members == 1 and player.health == health, "kicking the defeated body or empty air never scores or heals")
	await _strike()
	lab.check(_scores.size() == 1 and player._kick_recovery < ArenaPlayer.KICK_MISS_RECOVERY - 0.3, "a press during miss recovery is consumed, not buffered into a new kick")

func _finish_healing(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	player.health = player.max_health - 60
	var start := player.health
	var gains: Array[int] = []
	for kill in 5:
		var close := _spawn(game, "robot_grunt", lab.ahead(2.0), 1.0)
		lab.aim_at(game.horde.enemy_position(close))
		var before := player.health
		player._shoot(false)
		gains.append(player.health - before)
		lab.check(not game.horde.is_alive(close), "close finish fixture is an actual primary kill")
	lab.check(gains[0] == ArenaPlayer.FINISH_HEAL and player.health - start == int(ArenaPlayer.FINISH_HEAL_BUDGET), "close primary finishes heal per transaction within the budget (%s)" % [gains])
	await _reset(game)
	player.health = player.max_health - 60
	var far := _spawn(game, "robot_grunt", lab.ahead(12.0), 1.0)
	lab.aim_at(game.horde.enemy_position(far))
	var score := player.arena_score
	player._shoot(false)
	lab.check(not game.horde.is_alive(far) and player.arena_score > score and player.health == player.max_health - 60, "a distant kill scores but never heals")
	# A pierced multi-kill is one transaction: one heal step, not one per body.
	await _reset(game)
	player.health = player.max_health - 60
	var line: Array[int] = []
	for n in 3:
		line.append(_spawn(game, "robot_grunt", lab.ahead(1.8 + n * 0.9), 1.0))
	var through := lab.ahead(2.5)
	lab.aim_at(Vector3(through.x, game.horde.ground_height(through) + 0.9, through.y))
	player._shoot(false)
	var dead := 0
	for slot in line:
		dead += 0 if game.horde.is_alive(slot) else 1
	lab.check(dead == 3 and player.health == player.max_health - 60 + ArenaPlayer.FINISH_HEAL, "a close multi-kill transaction heals exactly once (%d dead)" % dead)

func _launch_at(game: ArenaGame, distance: float, speed: float) -> void:
	var player := game.player
	var forward := -player.head.global_basis.z
	var from := player.camera.global_position + forward * distance
	game.horde.launch_projectile(from, -forward * speed, 10.0)

func _parry(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	player.health = player.max_health - 30
	var thrower := _spawn(game, "robot_grunt", lab.ahead(9.0), 1.0)
	# Rank-zero returns fly straight; isolate credit from a grunt's dodge lane.
	game.horde.stun(thrower, 2.0)
	lab.aim_at(game.horde.enemy_position(thrower))
	var score := player.arena_score
	var style := player.combo_hits
	var charge := player.drop_charge
	_launch_at(game, 2.4, 6.0)
	await _strike()
	lab.check(player.last_action_label == "PARRY" and player.health == player.max_health - 30 + ArenaPlayer.PARRY_HEAL, "RMB on an incoming projectile parries it and heals once")
	lab.check(player.arena_score == score and player.combo_hits == style and player.drop_charge == charge, "a parry alone earns no score, STYLE or charge")
	await lab.capture("parry")
	await lab.wait(1.5)
	lab.check(not game.horde.is_alive(thrower) and _only(_actions, "RETURN") and _action_members == 1 and _only(_scores, "RETURN"), "the returned projectile credits its kill exactly once (%s)" % [_actions])
	# Whiffed parries are ordinary missed kicks: no heal, full miss recovery.
	await _reset(game)
	player.health = player.max_health - 30
	await _strike()
	await lab.wait(ArenaPlayer.PARRY_RECOVERY + 0.05)
	lab.check(player.health == player.max_health - 30 and not player.kick_ready, "a parry with nothing to return neither heals nor skips recovery")
	# build_return: longer reach and a recovery refund on success.
	await _reset(game)
	lab.aim_at(Vector3(lab.ahead(9.0).x, 1.0, lab.ahead(9.0).y))
	_launch_at(game, ArenaPlayer.PARRY_REACH + 0.45, 1.0)
	await _strike()
	lab.check(player.last_action_label != "PARRY", "rank 0 parry reach is bounded")
	await _reset(game)
	game.grant_upgrade(load("res://data/upgrades/build_return.tres") as UpgradeDefinition)
	lab.aim_at(Vector3(lab.ahead(9.0).x, 1.0, lab.ahead(9.0).y))
	_launch_at(game, ArenaPlayer.PARRY_REACH + 0.45, 1.0)
	await _strike()
	lab.check(player.last_action_label == "PARRY" and player.kick_ready, "RETURN build extends parry reach and refunds recovery")

func _slide_speed(game: ArenaGame) -> float:
	var player := game.player
	await _reset(game)
	Input.action_press(&"move_forward")
	await lab.wait(0.3)
	Input.action_press(&"slide")
	await lab.frames(2)
	Input.action_release(&"slide")
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release(&"move_forward")
	return speed if player.is_sliding() else 0.0

func _slide(game: ArenaGame) -> void:
	var player := game.player
	var plain := await _slide_speed(game)
	await lab.wait(1.0)
	game.grant_upgrade(load("res://data/upgrades/build_slide.tres") as UpgradeDefinition)
	var boosted := await _slide_speed(game)
	lab.check(plain > 0.0 and absf(boosted / plain - 1.25) < 0.08, "SLIDE build launches the slide faster (%.1f -> %.1f m/s)" % [plain, boosted])
	var grunt := _spawn(game, "robot_grunt", lab.ahead(2.2), 90000.0)
	lab.aim_at(game.horde.enemy_position(grunt))
	var aim := player.head.global_basis
	await _strike()
	lab.check(player.last_action_label == "SLIDE KICK" and player.kick_ready, "a landed slide kick launches and the SLIDE build refunds recovery")
	lab.check(player.head.global_basis.is_equal_approx(aim), "kicking never moves the player's aim")
	await lab.capture("slide_kick")
	await lab.wait(1.0)

func _stomp(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	var grunt := _spawn(game, "robot_grunt", lab.ahead(3.0), 90000.0)
	var body := game.horde.enemy_position(grunt)
	var top := body.y + 1.0
	# A real low ceiling right above the bounce.
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 0.3, 5)
	shape.shape = box
	ceiling.add_child(shape)
	game.add_child(ceiling)
	var hover := top + 1.4
	# Free bounce apex is ~1.3 m; the ceiling sits 0.9 m above the head.
	ceiling.global_position = Vector3(body.x, hover + 0.9 + 0.9 + 0.15, body.z + 0.6)
	await lab.frames(2)
	player.global_position = Vector3(body.x, hover, body.z + 0.6)
	player.velocity = Vector3.ZERO
	lab.aim_at(body)
	# Teleporting a fixture does not refresh CharacterBody3D's floor contacts.
	await lab.get_tree().physics_frame
	await lab.get_tree().physics_frame
	await _strike()
	lab.check(player.last_action_label == "STOMP" and player.velocity.y > 0.0 and player._air_jump_available, "an airborne kick stomps the body below and bounces like a bumper")
	var peak := player.global_position.y
	for frame in 20:
		await lab.get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	lab.check(peak + 0.9 <= ceiling.global_position.y - 0.15 + 0.03, "the stomp bounce stops at a real ceiling")
	ceiling.queue_free()
	await _reset(game)
	player.global_position = Vector3(0, 6, 12)
	await lab.frames(2)
	await _strike()
	lab.check(player.velocity.y <= -ArenaPlayer.STOMP_DIVE + 1.0 and not player.kick_ready, "a whiffed air kick commits to a dive with miss recovery")
	await lab.wait(1.0)

func _heavy(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	var tank := _spawn(game, "robot_tank", lab.ahead(2.0), 90000.0)
	var rest := game.horde.enemy_position(tank).y
	lab.aim_at(game.horde.enemy_position(tank))
	await _strike()
	var stunned := game.horde.is_stunned(tank)
	var launched := false
	var highest := rest
	for frame in 30:
		await lab.get_tree().physics_frame
		launched = launched or _airborne(game, tank)
		highest = maxf(highest, game.horde.enemy_position(tank).y)
	lab.check(player.last_action_label == "KICK" and stunned and not launched and highest < rest + 0.15, "a heavy body staggers instead of launching")

func _combos(game: ArenaGame) -> void:
	var player := game.player
	# FROZEN + kick: the frozen body dies outright and shatters onto a neighbour.
	await _reset(game)
	var frozen := _spawn(game, "robot_grunt", lab.ahead(1.6), 20.0)
	# Behind the victim: outside the kick cone, inside the shatter radius.
	var neighbour := _spawn(game, "robot_grunt", lab.ahead(3.8), 1.0)
	game.horde.damage(frozen, 1.0, Vector3.ZERO, DamageType.Kind.FROST)
	lab.check((game.horde.combo_flags(frozen) & Horde.FROZEN) != 0, "frost leaves a real FROZEN state")
	lab.aim_at(game.horde.enemy_position(frozen))
	await _strike()
	await lab.wait(0.5)
	lab.check(_actions.has("SHATTER") and not game.horde.is_alive(frozen) and not game.horde.is_alive(neighbour) and _action_members == _deaths and _deaths == 2, "kicking a frozen body shatters it, each life credited once (%s)" % [_actions])
	# BURNING + shotgun: flame burst onto neighbours outside the pellet cone.
	await _reset(game)
	player.quick_swap()
	lab.check(player.weapon_id() == &"scatter", "the drafted shotgun is a quick swap away")
	var burning := _spawn(game, "robot_grunt", lab.ahead(3.0), 90000.0)
	_spawn(game, "robot_grunt", lab.ahead(3.0, 1.4), 1.0)
	_spawn(game, "robot_grunt", lab.ahead(3.0, -1.4), 1.0)
	game.horde.damage(burning, 1.0, Vector3.ZERO, DamageType.Kind.FIRE)
	lab.aim_at(game.horde.enemy_position(burning))
	_actions.clear()
	player._shoot(false)
	await lab.frames(2)
	lab.check(_actions.has("FLAME BURST") and _action_members == _deaths and _deaths >= 1, "a shotgun blast on a burning body flame-bursts its neighbours once (%s)" % [_actions])
	await lab.capture("flame_burst")
	# ELECTRIC + explosive: conduction.
	await _reset(game)
	lab.check(game.run_state.equip_pair(_source(game, "autocannon"), _source(game, "rail")), "a break replacement drafts an explosive gun")
	player.refresh_weapon()
	var charged := _spawn(game, "robot_grunt", lab.ahead(6.0), 90000.0)
	_spawn(game, "robot_grunt", lab.ahead(6.0, 4.2), 1.0)
	game.horde.damage(charged, 1.0, Vector3.ZERO, DamageType.Kind.SHOCK)
	lab.check((game.horde.combo_flags(charged) & Horde.ELECTRIC) != 0, "shock leaves a real ELECTRIC charge")
	lab.aim_at(game.horde.enemy_position(charged))
	player._shoot(false)
	await lab.frames(2)
	lab.check(_actions.has("CONDUCTION") and _action_members == _deaths and _deaths >= 1, "an explosive shot conducts through a charged body, each life credited once (%s)" % [_actions])
	await lab.capture("conduction")
	# Ambient burn ticks are not intentional actions.
	await _reset(game)
	var ember := _spawn(game, "robot_grunt", lab.ahead(8.0), 21.0)
	game.horde.damage(ember, 20.0, Vector3.ZERO, DamageType.Kind.FIRE)
	await lab.wait(2.5)
	lab.check(not game.horde.is_alive(ember), "burn ticks finish the ember fixture")
	lab.check(_actions.is_empty() and _scores.is_empty(), "ambient burn deaths never enter action credit")
	lab.check(game.run_state.equip_pair(_source(game, "rail"), _source(game, "scatter")), "the original pair is restored")
	player.refresh_weapon()

func _keg(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	var keg := PinballProp.new()
	game.add_child(keg)
	var spot := lab.ahead(1.3)
	keg.global_position = Vector3(spot.x, game.horde.ground_height(spot), spot.y)
	keg.setup(game.horde, player)
	for n in 3:
		_spawn(game, "robot_grunt", lab.ahead(5.0, float(n - 1) * 0.8), 1.0)
	await lab.frames(4)
	var start := keg.global_position
	lab.aim_at(keg.global_position + Vector3.UP * 0.3)
	await _strike()
	lab.check(keg.is_armed() or keg.is_spent(), "RMB kicks a real keg prop")
	var moved := 0.0
	for frame in 200:
		await lab.get_tree().physics_frame
		if is_instance_valid(keg):
			moved = maxf(moved, keg.global_position.distance_to(start))
		if not is_instance_valid(keg) or keg.is_spent():
			break
	await lab.wait(0.5)
	lab.check(moved > 0.5 and _actions.count("KEG") == 1 and _action_members == _deaths and _deaths >= 1, "a kicked keg flies, explodes once and credits each life once (%s)" % [_actions])
	if is_instance_valid(keg):
		var credited := _action_members
		lab.check(not keg.kick(Vector3.FORWARD) and _action_members == credited, "a spent keg cannot be kicked again for credit")
		keg.queue_free()

func _pause_and_death(game: ArenaGame) -> void:
	var player := game.player
	await _reset(game)
	var grunt := _spawn(game, "robot_grunt", lab.ahead(1.6), 90000.0)
	lab.aim_at(game.horde.enemy_position(grunt))
	var label := [0]
	player.action_feedback.connect(func(_text: String) -> void: label[0] += 1)
	game._open_pause()
	Input.action_press(&"kick")
	await lab.wait(0.2)
	game._on_resume()
	await lab.wait(0.3)
	lab.check(label[0] == 0 and not player._kick_view.is_animating(), "a kick held through the pause menu cannot fire on resume")
	Input.action_release(&"kick")
	await lab.frames(2)
	await _strike()
	lab.check(label[0] == 1 and player.last_action_label == "KICK", "a fresh press after release kicks again")
	Input.action_press(&"kick")
	await lab.wait(1.0)
	lab.check(label[0] == 1, "holding RMB never repeats the kick")
	Input.action_release(&"kick")
	await lab.frames(2)
	# Death precedence: no heal, kick or credit after the killing blow.
	player._invulnerable = 0.0
	player.health = 1
	player._kick_recovery = 0.0
	player.take_damage(50)
	lab.check(not player.active and player.health == 0, "the killing blow lands")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _strike()
	game.horde.action_killed.emit(1, player.global_position, "KICK")
	lab.check(label[0] == 1 and player.health == 0 and not player._kick_view.is_animating(), "a dead player cannot kick, heal or be credited")

func _movement_visuals(game: ArenaGame) -> void:
	await _reset(game)
	var slot := _spawn(game, "robot_grunt", lab.ahead(1.6), 90000.0)
	lab.aim_at(game.horde.enemy_position(slot))
	await _strike()
	await lab.capture_strip("standing_kick_motion", 6, 0.045)
	await _slide_speed(game)
	await lab.capture_strip("slide_pose_motion", 4, 0.05)
	slot = _spawn(game, "robot_grunt", lab.ahead(2.2), 90000.0)
	lab.aim_at(game.horde.enemy_position(slot))
	await _strike()
	await lab.capture_strip("slide_kick_motion", 6, 0.045)
	await _reset(game)
	slot = _spawn(game, "robot_grunt", lab.ahead(1.0), 90000.0)
	game.player.global_position.y = 4.0
	await lab.get_tree().physics_frame
	await lab.get_tree().physics_frame
	lab.aim_at(game.horde.enemy_position(slot))
	await _strike()
	await lab.capture_strip("stomp_motion", 6, 0.045)
