extends LabScenario

var _shots := 0
var _secondary_uses := 0
var _events: Dictionary = {}
var _horde: Horde

func title() -> String:
	return "Three-hand melee combat"

func summary() -> String:
	return "Real swings and charged releases, body reach/arc/height/cover, plating, upgrades, minerals, dry-gun fallback and cancellation"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	var horde := game.horde
	_horde = horde
	horde.target = null
	horde.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	player.shot_fired.connect(func(): _shots += 1)
	player.secondary_fired.connect(func(_hand: int): _secondary_uses += 1)
	horde.damage_reported.connect(_damage_report)
	for id in ["baton", "cleaver"]:
		_equip(game, id)
		await lab.wait(0.3)
		var target := _target(game, Vector2(0, 10))
		lab.aim_at(horde.enemy_position(target))
		var hp := horde._hp[target]
		var charges := player.secondary_charge.duplicate()
		await _tap(player)
		lab.check(horde._hp[target] < hp and _events.get(target, 0) == 1, "%s real input lands one direct HP transaction per swing" % id)
		lab.check(player.ammo(2) == 0 and player.reserve_ammo(2) == 0 and player.reserve_capacity(2) == 0 and not player.is_reloading(2), "%s stays ammo-free and never reloads" % id)
		lab.check(player.secondary_charge[0] > charges[0] and player.secondary_charge[1] > charges[1] and player.secondary_charge[2] == charges[2], "%s landed swing feeds only the other hands" % id)
		lab.fire(true)
		await lab.capture_strip(id + "_motion", 6, 0.04, 3)
		lab.fire(false)
		await lab.wait(0.2)
		await _charged(game, id)
	await _geometry(game)
	await _armor(game)
	await _upgrades(game)
	await _boss_interrupt(game)
	await _shock_cover(game)
	await _mineral(game)
	await _fallback(game)
	await _cancellation(game)
	horde.damage_reported.disconnect(_damage_report)
	horde.set_physics_process(true)

func _equip(game: ArenaGame, id: String) -> void:
	lab.fire(false)
	Input.action_release("mine")
	game.player.cancel_secondaries()
	var definitions: Array[WeaponDefinition] = [lab.weapon("pulse"), lab.weapon("rail"), lab.weapon(id)]
	game.run_state.initialize_hands(definitions)
	game.player.weapons = game.run_state.hand_definitions()
	game.player.refresh_weapons()
	game.player.select_weapon(2)
	game.player.global_position = Vector3(0, 1, 12)
	game.player.velocity = Vector3.ZERO
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO
	game.player._quickdraw_left = 0.0
	game.player._reset_combo()
	game.player._fire_cooldowns.fill(0.0)
	game.hud.set_hands(game.run_state, 2)

func _target(game: ArenaGame, at: Vector2, id: String = "robot_tank") -> int:
	game.horde.clear()
	_events.clear()
	var slot := game.horde.spawn(lab.enemy(id), at, 100.0)
	game.horde._rebuild_grid()
	return slot

func _tap(player: ArenaPlayer) -> void:
	await lab.wait(maxf(0.0, player._fire_cooldowns[player.selected_weapon]) + 0.03)
	var before := _shots
	lab.fire(true)
	await lab.get_tree().physics_frame
	await lab.get_tree().process_frame
	lab.fire(false)
	await lab.wait(player.weapons[player.selected_weapon].melee_windup + ArenaPlayer.MELEE_SWEEP_TIME + 0.06)
	lab.check(_shots == before + 1, "a single primary input releases exactly one swing, not an ammo-free firing loop")

func _damage_report(at: Vector3, _amount: float, _kind: int, _critical: bool, _killed: bool) -> void:
	var slot := _horde.nearest(at, 0.1)
	_events[slot] = int(_events.get(slot, 0)) + 1

func _charged(game: ArenaGame, id: String) -> void:
	var player := game.player
	var target := _target(game, Vector2(0, 9))
	var rear := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 16), 100.0)
	var distant := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 3), 100.0)
	var high := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 9), 100.0)
	game.horde._y[high] = 8.0
	game.horde._rebuild_grid()
	var rear_hp := game.horde._hp[rear]
	var distant_hp := game.horde._hp[distant]
	var high_hp := game.horde._hp[high]
	lab.aim_at(game.horde.enemy_position(target))
	player.secondary_charge[2] = 100.0
	var hp := game.horde._hp[target]
	var uses := _secondary_uses
	Input.action_press("mine")
	await lab.wait(0.12)
	Input.action_release("mine")
	await lab.wait(0.15)
	lab.check(player.secondary_charge[2] == 100.0 and game.horde._hp[target] == hp and _secondary_uses == uses, "%s early charged release cancels free" % id)
	Input.action_press("mine")
	await lab.wait(0.7)
	lab.check(player.secondaries[2].charge_progress() >= 1.0 and player.secondary_charge[2] == 100.0, "%s real hold telegraphs charge without spending it" % id)
	await lab.capture(id + "_charged")
	Input.action_release("mine")
	await lab.wait(0.035)
	player.select_weapon(0)
	await lab.wait(0.4)
	lab.check(player.secondary_charge[2] == 100.0 and game.horde._hp[target] == hp and _secondary_uses == uses, "%s holstering queued windup cancels free with no delayed hit" % id)
	player.select_weapon(2)
	player._quickdraw_left = 0.0
	await lab.wait(0.25)
	Input.action_press("mine")
	await lab.wait(0.7)
	Input.action_release("mine")
	await lab.wait(0.34)
	lab.check(_secondary_uses == uses + 1 and is_equal_approx(player.secondary_charge[2], 100.0 - player.secondaries[2].charge_cost), "%s actual charged sweep pays its meter exactly once" % id)
	lab.check(game.horde._hp[target] < hp and game.horde._knock[target].length() > 0.0, "%s charged release deals real damage and clears space" % id)
	lab.check(game.horde._hp[rear] == rear_hp and game.horde._hp[distant] == distant_hp and game.horde._hp[high] == high_hp, "%s charged release respects forward, reach and vertical bounds" % id)
	if id == "baton":
		lab.check(game.horde.is_stunned(target), "Shock Discharge applies real stagger")
	await lab.capture(id + "_release")

func _geometry(game: ArenaGame) -> void:
	_equip(game, "cleaver")
	await lab.wait(0.3)
	var player := game.player
	var horde := game.horde
	horde.clear()
	_events.clear()
	var front := horde.spawn(lab.enemy("robot_tank"), Vector2(0, 10), 100.0)
	var side := horde.spawn(lab.enemy("robot_tank"), Vector2(1.4, 10), 100.0)
	var rear := horde.spawn(lab.enemy("robot_tank"), Vector2(0, 14), 100.0)
	var far := horde.spawn(lab.enemy("robot_tank"), Vector2(0, 5), 100.0)
	var high := horde.spawn(lab.enemy("robot_tank"), Vector2(-1, 10), 100.0)
	horde._y[high] = 6.0
	horde._rebuild_grid()
	var rear_hp := horde._hp[rear]
	var far_hp := horde._hp[far]
	var high_hp := horde._hp[high]
	lab.aim_at(horde.enemy_position(front))
	await _tap(player)
	lab.check(_events.get(front, 0) == 1 and _events.get(side, 0) == 1, "swept arc lands once on multiple forward bodies")
	lab.check(horde._hp[rear] == rear_hp and horde._hp[far] == far_hp and horde._hp[high] == high_hp, "rear, distant and vertically separated enemies cannot be hit")
	# Body extent, not its centre, determines the outer reach boundary.
	var extent := lab.enemy("robot_grunt")
	var reach := player.weapons[2].range_meters
	var edge := _target(game, Vector2(0, 12 - reach - extent.radius + 0.08), "robot_grunt")
	horde._y[edge] = player.camera.global_position.y - extent.height * 0.5
	horde._rebuild_grid()
	player.head.rotation = Vector3.ZERO
	await _tap(player)
	lab.check(_events.get(edge, 0) == 1, "a body whose near surface is in reach can be hit with its centre beyond reach")
	var outside := _target(game, Vector2(0, 12 - reach - extent.radius - 0.12), "robot_grunt")
	horde._y[outside] = player.camera.global_position.y - extent.height * 0.5
	horde._rebuild_grid()
	var outside_hp := horde._hp[outside]
	await _tap(player)
	lab.check(horde._hp[outside] == outside_hp, "a body whose entire near surface is beyond reach remains unharmed")
	var angle := deg_to_rad(player.weapons[2].melee_arc_degrees * 0.5 + 25.0)
	var lateral := _target(game, Vector2(sin(angle) * 2.5, 12 - cos(angle) * 2.5), "robot_grunt")
	horde._y[lateral] = player.camera.global_position.y - extent.height * 0.5
	horde._rebuild_grid()
	var lateral_hp := horde._hp[lateral]
	await _tap(player)
	lab.check(horde._hp[lateral] == lateral_hp, "a reachable forward body outside the arc cannot be hit")
	var raised := _target(game, Vector2(0, 10), "robot_grunt")
	horde._y[raised] = 1.8
	horde._rebuild_grid()
	lab.aim_at(horde.enemy_position(raised))
	await _tap(player)
	lab.check(_events.get(raised, 0) == 1, "pitching toward a reachable raised body lands a real vertical strike")
	var blocked := _target(game, Vector2(0, 10))
	lab.aim_at(horde.enemy_position(blocked))
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 4, 0.25)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	wall.global_position = Vector3(0, 1.5, 11)
	await lab.frames(3)
	var hp := horde._hp[blocked]
	await _tap(player)
	lab.check(horde._hp[blocked] == hp, "actual world cover occludes the forward sweep")
	wall.queue_free()
	await lab.frames(3)

func _armor(game: ArenaGame) -> void:
	_equip(game, "cleaver")
	await lab.wait(0.3)
	var horde := game.horde
	var player := game.player
	player.global_position = Vector3(0, 1, 8)
	var slot := _target(game, Vector2(0, 10), "robot_bulwark")
	horde._yaw[slot] = 0.0
	lab.aim_at(horde.enemy_position(slot))
	var hp := horde._hp[slot]
	await _tap(player)
	var front := hp - horde._hp[slot]
	player.global_position = Vector3(0, 1, 12)
	player._reset_combo()
	lab.aim_at(horde.enemy_position(slot))
	hp = horde._hp[slot]
	await _tap(player)
	var rear := hp - horde._hp[slot]
	lab.check(rear > front * 2.0 and front > 0.0, "real melee uses attacker-origin plating: rear strike beats the front shield")

func _upgrades(game: ArenaGame) -> void:
	_equip(game, "cleaver")
	await lab.wait(0.3)
	var player := game.player
	var slot := _target(game, Vector2(0, 10))
	lab.aim_at(game.horde.enemy_position(slot))
	var hp := game.horde._hp[slot]
	await _tap(player)
	var baseline := hp - game.horde._hp[slot]
	var charge := player.secondary_charge[2]
	var cooldown := player._fire_cooldowns[2]
	var hand := game.run_state.hands[2]
	lab.check(hand.upgrade(&"damage") and hand.upgrade(&"cadence") and hand.upgrade(&"fire") and hand.upgrade(&"splash"), "melee accepts damage/cadence/element/splash upgrades")
	lab.check(not hand.upgrade(&"projectiles") and not hand.upgrade(&"pierce"), "melee rejects fake projectile and pierce upgrades")
	player.weapons = game.run_state.hand_definitions()
	player.refresh_weapons()
	lab.check(is_equal_approx(player.secondary_charge[2], charge) and is_equal_approx(player._fire_cooldowns[2], cooldown), "hand upgrades preserve charge and cooldown ownership")
	player._reset_combo()
	_events.clear()
	hp = game.horde._hp[slot]
	await _tap(player)
	lab.check(hp - game.horde._hp[slot] > baseline and _events.get(slot, 0) == 1 and game.horde._burn_time[slot] > 0.0, "upgraded real sweep combines damage/splash in one HP transaction and installs its element")
	game.run_state.crit_chance = 1.0
	player._reset_combo()
	hp = game.horde._hp[slot]
	await _tap(player)
	lab.check(hp - game.horde._hp[slot] > baseline * 2.0, "rolled critical melee meaningfully multiplies real damage")
	game.run_state.crit_chance = 0.0
	var rate_shots := _shots
	var elapsed := 0.0
	lab.fire(true)
	while elapsed < 0.85:
		await lab.get_tree().physics_frame
		elapsed += player.get_physics_process_delta_time()
	lab.fire(false)
	await lab.wait(0.15)
	lab.check(absf(float(_shots - rate_shots) - elapsed / player.weapons[2].fire_interval) <= 2.0, "upgraded melee cadence follows actual held-input swing releases")
	game.run_state.hands[2].upgrade(&"frost")
	player.weapons = game.run_state.hand_definitions()
	player.refresh_weapons()
	await _tap(player)
	lab.check(game.horde._slow_time[slot] > 0.0, "Frost conversion applies a real slow through the melee damage API")
	game.run_state.hands[2].upgrade(&"shock")
	player.weapons = game.run_state.hand_definitions()
	player.refresh_weapons()
	var conductor := game.horde.spawn(lab.enemy("robot_tank"), Vector2(1.8, 10), 100.0)
	game.horde._rebuild_grid()
	var conductor_hp := game.horde._hp[conductor]
	await _tap(player)
	lab.check(game.horde._hp[conductor] < conductor_hp, "Shock conversion deals real conductive damage to another enemy")

func _boss_interrupt(game: ArenaGame) -> void:
	_equip(game, "baton")
	await lab.wait(0.3)
	game.horde.clear()
	game.director.boss_phase = true
	var boss := game.horde.spawn(game.campaign[0].schedule.boss, Vector2(0, 8), 100.0)
	game.horde._rebuild_grid()
	lab.check(boss >= 0 and is_instance_valid(game.boss_fight), "Shock Discharge has a real Yard boss controller fixture")
	if not is_instance_valid(game.boss_fight):
		return
	game.boss_fight.approach_time = 0.1
	game.boss_fight.ram_warning_time = 2.0
	game.boss_fight.mortar_warning_time = 2.0
	lab.aim_at(game.horde.enemy_position(boss))
	game.player.secondary_charge[2] = 100.0
	for n in 150:
		if game.boss_fight.state == YardBossFight.State.RAM_WINDUP or game.boss_fight.state == YardBossFight.State.MORTAR_WINDUP:
			break
		await lab.wait(0.02)
	lab.check(game.boss_fight.state == YardBossFight.State.RAM_WINDUP or game.boss_fight.state == YardBossFight.State.MORTAR_WINDUP, "boss warning is live before the charged melee interruption")
	Input.action_press("mine")
	await lab.wait(0.7)
	Input.action_release("mine")
	await lab.wait(0.24)
	lab.check(game.horde.is_stunned(boss) and game.boss_fight.state == YardBossFight.State.RECOVERY, "charged Baton really staggers and interrupts the boss warning")
	game.director.boss_phase = false

func _shock_cover(game: ArenaGame) -> void:
	_equip(game, "baton")
	await lab.wait(0.3)
	var horde := game.horde
	var source := _target(game, Vector2(0, 10))
	var forward := horde.spawn(lab.enemy("robot_tank"), Vector2(-1.5, 10), 100.0)
	var rear := horde.spawn(lab.enemy("robot_tank"), Vector2(0, 13), 100.0)
	var covered := horde.spawn(lab.enemy("robot_tank"), Vector2(1.5, 10), 100.0)
	var far := horde.spawn(lab.enemy("robot_tank"), Vector2(0, 7), 100.0)
	horde._rebuild_grid()
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 3, 0.25)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	wall.global_position = Vector3(1.0, 1.5, 10.6)
	await lab.frames(3)
	lab.aim_at(horde.enemy_position(source))
	var rear_hp := horde._hp[rear]
	var covered_hp := horde._hp[covered]
	var far_hp := horde._hp[far]
	var forward_hp := horde._hp[forward]
	await _tap(game.player)
	lab.check(horde._hp[rear] == rear_hp and horde._hp[covered] == covered_hp and horde._hp[far] == far_hp, "real melee Shock cannot conduct behind the player, through cover or beyond swing reach")
	lab.check(horde._hp[forward] < forward_hp and _events.get(forward, 0) > 1, "valid forward neighbor receives real conduction as well as its one direct strike")
	wall.queue_free()
	await lab.frames(3)

func _mineral(game: ArenaGame) -> void:
	_equip(game, "cleaver")
	await lab.wait(0.3)
	game.horde.clear()
	var deposit: MineralDeposit
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.health > 0.0 and node.global_position.y < 2.4:
			deposit = node
			break
	lab.check(deposit != null, "melee mining has a live mineral fixture")
	if deposit == null:
		return
	lab.check(await lab.aim_deposit(deposit, 1.6), "melee aims at the real crystal surface")
	var hp := deposit.health
	await _tap(game.player)
	lab.check(deposit.health < hp, "primary melee fractures the aimed mineral within reach")
	lab.check(await lab.aim_deposit(deposit, 1.6), "contextual drill retains a live target")
	game.player.secondary_charge[2] = 100.0
	var uses := _secondary_uses
	Input.action_press("mine")
	await lab.wait(0.2)
	lab.check(game.player.drilling() and _secondary_uses == uses and game.player.secondary_charge[2] == 100.0, "mineral RMB takes drill precedence over the charged melee mode")
	Input.action_release("mine")
	await lab.frames(2)

func _fallback(game: ArenaGame) -> void:
	_equip(game, "baton")
	game.player.select_weapon(0)
	await lab.wait(0.3)
	var player := game.player
	player._magazines.fill(0)
	player._reserves.fill(0)
	player._reloads.fill(0.0)
	await lab.wait(0.2)
	lab.check(player.selected_weapon == 0, "idle empty firearm never steals focus for melee")
	lab.fire(true)
	await lab.wait(0.4)
	lab.fire(false)
	lab.check(player.selected_weapon == 2 and player.ammo(2) == 0, "both dry guns fall back to the real third-hand melee without cycling it")
	await lab.wait(0.2)
	lab.check(player.add_ammo() and player.reserve_ammo(0) > 0 and player.reserve_ammo(1) > 0 and player.reserve_ammo(2) == 0, "ammo packs feed only firearms, never melee")
	player.select_weapon(0)
	await lab.wait(0.3)
	lab.check(player.selected_weapon == 0, "manual return to an empty/reloading gun remains available")

func _impact_pause(game: ArenaGame, id: String) -> void:
	_equip(game, id)
	await lab.wait(0.3)
	game.horde.clear()
	var victims := PackedInt32Array()
	var health := PackedFloat32Array()
	for x in [-0.6, 0.0, 0.6]:
		var slot := game.horde.spawn(lab.enemy("robot_grunt"), Vector2(x, 10), 100.0)
		victims.append(slot)
		health.append(game.horde._hp[slot])
	game.horde._rebuild_grid()
	lab.aim_at(game.horde.enemy_position(victims[1]))
	var interrupted := {"value": false}
	var stop := func(_at: Vector3, _amount: float, _kind: int, _critical: bool, _killed: bool) -> void:
		if not interrupted.value:
			interrupted.value = true
			game._open_pause()
	game.horde.damage_reported.connect(stop)
	lab.fire(true)
	await lab.wait(0.4)
	lab.fire(false)
	game.horde.damage_reported.disconnect(stop)
	var damaged := 0
	for n in victims.size():
		if game.horde._hp[victims[n]] < health[n]:
			damaged += 1
	lab.check(interrupted.value and damaged == 1 and game.get_tree().paused, "%s synchronous impact pause cancels remaining contacts and elemental conduction (%d damaged)" % [id, damaged])
	game._on_resume()
	await lab.wait(0.4)
	var after_resume := 0
	for n in victims.size():
		if game.horde._hp[victims[n]] < health[n]:
			after_resume += 1
	lab.check(after_resume == 1, "%s resuming cannot replay interrupted contacts or conduction" % id)

func _cancellation(game: ArenaGame) -> void:
	await _impact_pause(game, "cleaver")
	await _impact_pause(game, "baton")
	_equip(game, "cleaver")
	await lab.wait(0.3)
	var player := game.player
	var slot := _target(game, Vector2(0, 10))
	lab.aim_at(game.horde.enemy_position(slot))
	var hp := game.horde._hp[slot]
	lab.fire(true)
	await lab.get_tree().physics_frame
	await lab.get_tree().process_frame
	lab.fire(false)
	player.select_weapon(0)
	await lab.wait(0.4)
	lab.check(game.horde._hp[slot] == hp, "manual swap cancels an unlanded primary swing")
	player.select_weapon(2)
	await lab.wait(0.3)
	player.secondary_charge[2] = 100.0
	Input.action_press("mine")
	await lab.wait(0.7)
	Input.action_release("mine")
	await lab.wait(0.03)
	game._open_pause()
	await lab.wait(0.4)
	lab.check(game.horde._hp[slot] == hp and player.secondary_charge[2] == 100.0 and not player.melee_busy(), "pause/menu cancels queued damage, freezes play and keeps the cancelled charge free")
	game._on_resume()
	await lab.wait(0.4)
	lab.check(game.horde._hp[slot] == hp, "resuming never resurrects a cancelled swing")
	Input.action_release("fire")
	Input.action_release("mine")
	player.suppress_fire_until_release()
	player.secondary_charge[2] = 100.0
	Input.action_press("mine")
	await lab.wait(0.7)
	Input.action_release("mine")
	await lab.wait(0.03)
	player._invulnerable = 0.0
	player.take_damage(10000)
	await lab.wait(0.4)
	lab.check(not player.active and game.horde._hp[slot] == hp and player.secondary_charge[2] == 100.0, "death cancels queued charged damage without spending its meter")
