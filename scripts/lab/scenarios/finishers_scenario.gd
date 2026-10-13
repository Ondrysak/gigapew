extends LabScenario

## Real damage, physics walls, actual F input, contact timing and action credit.
const STEP := 1.0 / 60.0
var _actions: Array[Dictionary] = []
var _kills := 0
var _removed := 0.0
var _callback_horde: Horde
var _callback_victim := -1
var _callback_finisher := -1
var _callback_finish_result := false
var _callback_armed := false

func title() -> String:
	return "Daze and deliberate finishers"

func summary() -> String:
	return "One finite non-boss daze; collision-driven leaping execution with front-flip contact, walls, ceilings, floors, generations and exact-once represented lives"

func run() -> void:
	var game := await lab.start_game()
	game.player.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	var horde := game.horde
	horde.action_killed.connect(_on_action)
	horde.enemy_killed.connect(_on_killed)
	horde.damage_reported.connect(_on_damage)
	await _daze_lifetime(game)
	_lethal_and_ambient(game)
	_aim_and_contact(game)
	await _walls_and_floors(game)
	_reuse_and_callbacks(game)
	_fusion_lives(game)
	# Player-facing captures start with a fresh scene, not the corpse/FX/boss
	# controller residue of deliberately accelerated Horde lifetime fixtures.
	horde.damage_reported.disconnect(_on_damage)
	horde.enemy_killed.disconnect(_on_killed)
	horde.action_killed.disconnect(_on_action)
	game.free()
	game = await lab.start_game()
	horde = game.horde
	horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	horde.action_killed.connect(_on_action)
	horde.enemy_killed.connect(_on_killed)
	horde.damage_reported.connect(_on_damage)
	await _player_finishers(game)
	horde.damage_reported.disconnect(_on_damage)
	horde.enemy_killed.disconnect(_on_killed)
	horde.action_killed.disconnect(_on_action)
	game.player.set_physics_process(true)
	horde.set_physics_process(true)

func _on_action(members: int, _position: Vector3, label: String) -> void:
	_actions.append({"members": members, "label": label})

func _on_killed(_definition: HordeEnemyDefinition, _position: Vector3) -> void:
	_kills += 1

func _on_damage(_at: Vector3, amount: float, _kind: int, _critical: bool, _killed: bool) -> void:
	_removed += amount
	if not _callback_armed:
		return
	_callback_armed = false
	_callback_horde.damage(_callback_victim, 10000.0)
	_callback_finish_result = _callback_horde.finish(_callback_finisher, _callback_horde.enemy_generation(_callback_finisher), Vector3(1.0, 1.4, 4.0))

func _members() -> int:
	var total := 0
	for action in _actions:
		if action["label"] == "FINISHER":
			total += int(action["members"])
	return total

func _reset(game: ArenaGame) -> void:
	Input.action_release(&"mine")
	game.player.cancel_actions()
	_callback_armed = false
	game.horde.clear()
	_simulate(game.horde, 1.0)
	_actions.clear()
	_kills = 0
	_removed = 0.0
	game.player.global_position = Vector3(0.0, 1.0, 4.0)
	game.player.velocity = Vector3.ZERO

func _simulate(horde: Horde, seconds: float) -> void:
	for tick in ceili(seconds / STEP):
		horde._physics_process(STEP)

func _spawn(game: ArenaGame, point: Vector2 = Vector2(0.0, 6.0), health: float = 100.0, id: String = "robot_grunt") -> int:
	var definition := lab.enemy(id)
	game.horde.register_definition(definition)
	var slot := game.horde.spawn(definition, point, health / definition.max_health)
	game.horde._rebuild_grid()
	return slot

func _daze(game: ArenaGame, slot: int) -> void:
	game.horde.damage(slot, game.horde._hp[slot] * 0.8)

func _aim(horde: Horde, slot: int, origin: Vector3 = Vector3(0.0, 1.4, 4.0), reach: float = 3.2) -> int:
	return horde.finisher_target(origin, horde.enemy_position(slot) - origin, reach)

func _daze_lifetime(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var slot := _spawn(game)
	horde._mode[slot] = Horde.Mode.WINDUP
	horde._timer[slot] = 0.5
	horde._aim[slot] = Vector2.UP
	horde._attack_target[slot] = game.player.global_position
	horde._has_lane[slot] = 1
	horde.damage(slot, 79.0)
	lab.check(not horde.is_dazed(slot) and horde._hp[slot] == 21.0, "damage above the actual twenty-percent boundary does not daze")
	horde.damage(slot, 1.0)
	lab.check(horde.is_dazed(slot) and horde._hp[slot] == 20.0 and _removed == 80.0, "surviving damage at the boundary enters daze without changing removed or remaining HP")
	var start: Vector2 = horde._pos[slot]
	var player_hp := game.player.health
	_simulate(horde, 0.5)
	lab.check(horde._pos[slot] == start and game.player.health == player_hp, "dazed enemy does not voluntarily move or attack")
	var remaining: float = horde._daze_time[slot]
	horde.damage(slot, 1.0)
	lab.check(horde._daze_time[slot] == remaining and horde._hp[slot] == 19.0, "additional real damage never refreshes the once-per-life daze")
	lab.aim_at(horde.enemy_position(slot))
	await lab.capture("dazed_gold")
	_simulate(horde, 2.2)
	lab.check(horde.is_dazed(slot), "daze remains active just before its finite 2.8-second deadline")
	_simulate(horde, 0.15)
	lab.check(not horde.is_dazed(slot) and not horde.finish(slot, horde.enemy_generation(slot), Vector3(0.0, 1.4, 4.0)), "expired daze cannot execute")
	horde.damage(slot, 1.0)
	lab.check(not horde.is_dazed(slot) and horde._daze_time[slot] == 0.0, "later below-threshold hits cannot daze the same lifetime twice")
	_simulate(horde, 0.2)
	lab.check(horde._pos[slot].distance_to(start) > 0.01, "expiry resumes ordinary pursuit rather than a permanent freeze")

func _lethal_and_ambient(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var slot := _spawn(game)
	lab.check(horde.damage(slot, 1000.0) and not horde.is_alive(slot) and not horde.is_dazed(slot) and _removed == 100.0, "lethal damage kills normally instead of being clamped into daze")
	lab.check(_actions.is_empty() and _kills == 1, "ordinary lethal damage never earns a manual finisher action")
	_reset(game)
	slot = _spawn(game)
	_daze(game, slot)
	horde.damage(slot, 1.0, Vector3.ZERO, DamageType.Kind.FIRE)
	_simulate(horde, 2.1)
	lab.check(horde._hp[slot] < 19.0 and _actions.is_empty(), "ambient burn keeps dealing actual damage during daze without manual credit")
	horde.damage(slot, 1000.0)
	lab.check(not horde.is_alive(slot) and _members() == 0, "ambient or ordinary death removes a dazed body without inventing a finisher")
	_reset(game)
	var boss := _spawn(game, Vector2(0.0, 6.0), 100.0, "robot_boss")
	horde.damage(boss, 80.0)
	lab.check(not horde.is_dazed(boss) and horde.is_alive(boss) and not horde.finish(boss, horde.enemy_generation(boss), Vector3(0.0, 1.4, 4.0)), "boss damage remains real but boss mechanics never admit a finisher")

func _aim_and_contact(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var slot := _spawn(game)
	_daze(game, slot)
	var origin := Vector3(0.0, 1.4, 4.0)
	var generation := horde.enemy_generation(slot)
	lab.check(_aim(horde, slot) == slot and horde.finisher_target(origin, Vector3.RIGHT) == -1, "only the actual aimed dazed body is offered, not a nearby cone target")
	lab.check(horde.finisher_target(origin, Vector3.ZERO) == -1 and horde.finisher_target(origin, Vector3(INF, 0.0, 0.0)) == -1, "invalid aim has no execution target")
	lab.check(not horde.finish(slot, generation + 1, origin) and not horde.finish(slot, generation, Vector3(0.0, 1.4, 0.0)), "stale generations and out-of-reach contact preserve the live body")
	var shield := _spawn(game, Vector2(0.0, 5.0))
	lab.check(_aim(horde, slot) == -1 and not horde.finish(slot, generation, origin), "an intervening ordinary enemy blocks aimed selection and contact validation")
	horde.damage(shield, 1000.0)
	_actions.clear()
	_kills = 0
	lab.check(horde.finish(slot, generation, origin), "a valid deliberate contact kills the recorded dazed lifetime")
	lab.check(_members() == 1 and _actions.size() == 1 and _kills == 1 and _actions[0]["label"] == "FINISHER", "the actual finisher credits one represented life once through the existing action ledger")
	lab.check(not horde.finish(slot, generation, origin) and _members() == 1 and _kills == 1, "duplicate and dead-slot contact cannot credit twice")

func _walls_and_floors(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var slot := _spawn(game)
	_daze(game, slot)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 5.0, 0.12)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = Vector3(0.0, 1.5, 5.0)
	await lab.frames(3)
	lab.check(_aim(horde, slot) == -1 and not horde.finish(slot, horde.enemy_generation(slot), Vector3(0.0, 1.4, 4.0)), "a thin real physics wall blocks both selection and animation-contact execution")
	wall.queue_free()
	await lab.frames(2)
	lab.check(_aim(horde, slot) == slot, "removing the wall restores the unchanged original shot body")
	var origin := Vector3(0.0, 3.3, 4.5)
	lab.check(_aim(horde, slot, origin) == -1 and not horde.finish(slot, horde.enemy_generation(slot), origin), "aiming down at another floor cannot finish despite being inside nominal reach")
	horde._y[slot] = 2.0
	horde._rebuild_grid()
	origin = Vector3(0.0, 1.4, 4.5)
	lab.check(_aim(horde, slot, origin) == -1 and not horde.finish(slot, horde.enemy_generation(slot), origin), "a dazed body on an upper floor cannot execute from below")

func _reuse_and_callbacks(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var slot := _spawn(game)
	_daze(game, slot)
	var generation := horde.enemy_generation(slot)
	horde.clear()
	lab.check(not horde.is_dazed(slot) and horde._daze_time[slot] == 0.0 and horde._life_hp[slot] == 0.0, "clear immediately removes daze eligibility and lifetime HP")
	_simulate(horde, 1.0)
	var reused := _spawn(game)
	lab.check(reused == slot and horde.enemy_generation(reused) != generation and not horde.is_dazed(reused) and horde._daze_used[reused] == 0, "released slots reuse a fresh generation with no inherited daze")
	_daze(game, reused)
	lab.check(horde.is_dazed(reused) and not horde.finish(reused, generation, Vector3(0.0, 1.4, 4.0)), "the reused life gets its own daze but rejects the old animation contact")
	_reset(game)
	slot = _spawn(game)
	_daze(game, slot)
	_callback_victim = _spawn(game, Vector2(-2.0, 6.0))
	_callback_finisher = _spawn(game, Vector2(1.0, 6.0))
	_daze(game, _callback_finisher)
	_callback_horde = horde
	_callback_finish_result = true
	_callback_armed = true
	lab.check(horde.finish(slot, horde.enemy_generation(slot), Vector3(0.0, 1.4, 4.0)), "manual death completes despite synchronous damage callbacks")
	lab.check(_kills == 2 and _members() == 1 and _actions.size() == 1 and not _callback_finish_result and horde.is_alive(_callback_finisher), "callback automatic death is uncredited and callback finisher reentrancy cannot execute another body")

func _fusion_lives(game: ArenaGame) -> void:
	_reset(game)
	var horde := game.horde
	var definition := lab.enemy("robot_grunt")
	var type: int = horde._type_of[definition]
	var speed: float = horde._t_speed[type]
	horde._t_speed[type] = 0.0
	var slots := PackedInt32Array()
	for n in 8:
		var point := Vector2(0.0, 9.0) + Vector2.from_angle(float(n) * TAU / 8.0) * 0.3
		slots.append(_spawn(game, point))
		_daze(game, slots[n])
	_simulate(horde, 1.5)
	var megas := PackedInt32Array()
	lab.check(horde.query_megas(megas) == 0 and horde.alive_count == 8 and horde.population_count == 8, "fusion cannot consume any dazed life even in an eligible dense pack")
	_reset(game)
	for n in 8:
		var point := Vector2(0.0, 9.0) + Vector2.from_angle(float(n) * TAU / 8.0) * 0.3
		_spawn(game, point)
	_simulate(horde, 1.8)
	var count := horde.query_megas(megas)
	lab.check(count > 0, "ordinary undazed pack still uses the actual fusion consumer")
	if count > 0:
		var mega := megas[0]
		var members := horde.fusion_members(mega)
		_daze(game, mega)
		var at := horde.enemy_position(mega)
		var origin := Vector3(at.x, horde._y[mega] + 1.4, at.z - 2.6)
		game.player.global_position = Vector3(origin.x, origin.y - 0.4, origin.z)
		horde._rebuild_grid()
		lab.check(horde.is_dazed(mega) and horde.finish(mega, horde.enemy_generation(mega), origin), "a real fused body can be deliberately finished while dazed")
		lab.check(_members() == members and _kills == members and _actions.size() == 1 and horde.population_count == 8 - members, "finisher rewards and pressure release conserve all represented lives exactly once")
	horde._t_speed[type] = speed

func _player_fixture(game: ArenaGame, point: Vector2 = Vector2(0.0, 6.0)) -> int:
	game.player.set_physics_process(true)
	_reset(game)
	game.player.health = game.player.max_health - 30
	game.player._heal_budget = ArenaPlayer.FINISH_HEAL_BUDGET
	var slot := _spawn(game, point)
	_daze(game, slot)
	lab.aim_at(game.horde.enemy_position(slot))
	await lab.frames(3)
	# Hold the execution clock while native F reaches the contextual input
	# owner, then resume real physics to exercise the committed leap/contact.
	game.player.set_physics_process(false)
	return slot

func _press_finish(game: ArenaGame) -> void:
	Input.action_press(&"mine")
	await lab.frames(2)
	lab.check(game.player.is_finishing(), "a fresh native F press begins the deliberate execution")

func _player_finishers(game: ArenaGame) -> void:
	var player := game.player
	var horde := game.horde
	var slot := await _player_fixture(game)
	var score := player.arena_score
	var style := player.combo_hits
	var hp := player.health
	lab.check(player.finisher_ready() and game.hud.mining_prompt.visible, "an aimed close dazed body shows the contextual F finisher")
	await lab.capture("f_ready")
	await _paused_daze_visual(game, slot)
	await _press_finish(game)
	lab.check(horde.is_alive(slot) and _actions.is_empty() and not player._view.visible and not player.mining_tool.model.visible, "windup has no premature kill or overlapping gun/crowbar")
	await lab.capture("f_windup")
	player.set_physics_process(true)
	await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
	lab.check(not horde.is_alive(slot) and _members() == 1 and _kills == 1 and _actions.size() == 1, "real animation contact finishes and credits exactly one life")
	lab.check(player.arena_score > score and player.combo_hits > style and player.health == hp + ArenaPlayer.FINISHER_HEAL, "the real F finisher awards score, STYLE and a larger bounded close heal")
	await lab.capture("f_finished")
	var next := _spawn(game)
	_daze(game, next)
	await lab.wait(0.25)
	lab.check(horde.is_alive(next) and not player.is_finishing() and _members() == 1, "holding F through recovery never executes the next dazed body")
	Input.action_release(&"mine")
	await lab.frames(2)
	hp = player.health
	player._heal_budget = 3.0
	lab.fire(true)
	Input.action_press(&"mine")
	await lab.capture_strip("f_execution_motion", 12, 0.07)
	await lab.wait(0.15)
	Input.action_release(&"mine")
	lab.fire(false)
	lab.check(not horde.is_alive(next) and _members() == 2 and player.health > hp \
			and player.health <= hp + ceili(3.0 + ArenaPlayer.FINISH_HEAL_REFILL * ArenaPlayer.FINISHER_CONTACT), \
			"F wins over simultaneous fire and the execution consumes only the remaining shared healing budget")

	slot = await _player_fixture(game)
	await _press_finish(game)
	game.get_tree().paused = true
	await lab.frames(2)
	lab.check(not player.is_finishing() and horde.is_alive(slot), "pause cancels pending contact rather than completing a hidden execution")
	game.get_tree().paused = false
	player.set_physics_process(true)
	await lab.wait(0.25)
	lab.check(horde.is_alive(slot) and _members() == 0, "F held through pause cannot replay a finisher")
	Input.action_release(&"mine")
	await lab.frames(2)
	Input.action_press(&"mine")
	await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
	Input.action_release(&"mine")
	lab.check(not horde.is_alive(slot) and _members() == 1, "a fresh released F after pause executes normally")

	slot = await _player_fixture(game)
	await _press_finish(game)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	player.set_physics_process(true)
	await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
	lab.check(horde.is_alive(slot) and _members() == 0, "displacement outside the original leap budget cannot home or warp back into contact")

	slot = await _player_fixture(game)
	await _press_finish(game)
	horde.damage(slot, 1000.0)
	_simulate(horde, 1.0)
	var replacement := _spawn(game)
	_daze(game, replacement)
	player.set_physics_process(true)
	await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
	lab.check(horde.is_alive(replacement) and _members() == 0, "pending contact cannot kill a replacement lifetime after the original dies")

	# Real cabinet behind an aimed dazed body: the shared F must not both finish
	# and pay salvage. No substituted input owner or fake deposit is involved.
	_reset(game)
	var deposit: MineralDeposit
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.health > 0.0:
			deposit = node
			break
	if deposit != null and await lab.aim_deposit(deposit, 2.2):
		var at := player.camera.global_position - player.head.global_basis.z * 1.1
		slot = _spawn(game, Vector2(at.x, at.z))
		_daze(game, slot)
		lab.aim_at(horde.enemy_position(slot))
		await lab.frames(3)
		var before := deposit.yield_emitted
		Input.action_press(&"mine")
		await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
		Input.action_release(&"mine")
		lab.check(not horde.is_alive(slot) and deposit.yield_emitted == before and _members() == 1, "F finishes the aimed dazed enemy without also opening the real nearby cabinet")
	else:
		lab.check(false, "the shared-F fixture reaches a real native cabinet")

	await _leaping_finishers(game)

	slot = await _player_fixture(game)
	await _press_finish(game)
	player._invulnerable = 0.0
	player.take_damage(10000)
	player.set_physics_process(true)
	await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
	lab.check(not player.active and horde.is_alive(slot) and _members() == 0, "death cancels pending execution and can never heal or credit the dead player")
	Input.action_release(&"mine")

func _leaping_finishers(game: ArenaGame) -> void:
	var player := game.player
	var horde := game.horde
	var slot := await _player_fixture(game, Vector2(0.0, 11.5))
	var start := player.global_position
	var aim := player.head.rotation
	lab.check(player.finisher_ready(), "an aimed dazed body more than seven metres away offers the leap")
	await lab.capture("leap_ready")
	await _press_finish(game)
	horde.set_physics_process(true)
	player.set_physics_process(true)
	await lab.wait(0.16)
	lab.check(player.global_position.y > start.y + 0.25 \
			and Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() > 1.0 \
			and horde.is_alive(slot) and _members() == 0, \
			"the live finisher really travels forward and rises before any kill")
	await lab.capture_strip("leap_flip_motion", 9, 0.07)
	await lab.wait(0.15)
	lab.check(not horde.is_alive(slot) and _members() == 1 \
			and Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() > 5.0, \
			"the long leap closes the real distance and earns exactly one melee execution")
	lab.check(player.head.rotation == aim, "front-flip presentation never rotates the player's actual aim")
	Input.action_release(&"mine")

	horde.set_physics_process(false)
	slot = await _player_fixture(game, Vector2(0.0, 14.5))
	Input.action_press(&"mine")
	player.set_physics_process(true)
	await lab.wait(0.20)
	lab.check(not player.is_finishing() and horde.is_alive(slot) and _members() == 0, \
			"fresh F beyond the long selection range cannot launch or execute")
	Input.action_release(&"mine")

	for ceiling in [false, true]:
		slot = await _player_fixture(game, Vector2(0.0, 11.5))
		var hp := player.health
		await _press_finish(game)
		var obstacle := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 0.15, 10.0) if ceiling else Vector3(4.0, 5.0, 0.12)
		shape.shape = box
		obstacle.add_child(shape)
		game.add_child(obstacle)
		obstacle.global_position = Vector3(0.0, 2.3, 8.0) if ceiling else Vector3(0.0, 1.0, 7.0)
		await lab.frames(3)
		player.set_physics_process(true)
		await lab.wait(ArenaPlayer.FINISHER_DURATION + 0.10)
		lab.check(horde.is_alive(slot) and _members() == 0 and player.health == hp \
				and not player.is_finishing(), \
				"a real ceiling interrupts the rising leap without killing or healing" if ceiling \
				else "a wall entering the committed lane blocks real travel and execution")
		lab.check(player.global_position.y < 1.5 if ceiling else player.global_position.z < 7.0, \
				"the capsule stays below the ceiling" if ceiling else "the capsule never crosses the blocking wall")
		await lab.capture("leap_ceiling_blocked" if ceiling else "leap_wall_blocked")
		Input.action_release(&"mine")
		obstacle.queue_free()
		await lab.frames(2)

func _paused_daze_visual(game: ArenaGame, slot: int) -> void:
	var intensity := float(Profile.settings.get("hallucination_intensity", 0.65))
	Profile.set_setting("hallucination_intensity", 0.0)
	await lab.frames(2)
	game.get_tree().paused = true
	await RenderingServer.frame_post_draw
	var center := game.player.camera.unproject_position(game.horde.enemy_position(slot) + Vector3.UP * 0.25)
	var rect := Rect2i(Vector2i(center) - Vector2i(16, 24), Vector2i(32, 48))
	var before := lab.get_viewport().get_texture().get_image().get_region(rect).get_data()
	await lab.wait(0.3)
	await RenderingServer.frame_post_draw
	var after := lab.get_viewport().get_texture().get_image().get_region(rect).get_data()
	lab.check(before == after, "the visible daze highlight freezes pixel-for-pixel while gameplay is paused")
	game.get_tree().paused = false
	Profile.set_setting("hallucination_intensity", intensity)
	game.player.set_physics_process(true)
	await lab.frames(2)
	game.player.set_physics_process(false)
