extends LabScenario

func title() -> String:
	return "Primary kills, paired guns and physical movement"

func summary() -> String:
	return "Sustained fire and stable aim, kill-earned STYLE, two-slot swap, double jump, slide clearance, ceilings, walls and menu guards"

func run() -> void:
	var game := await lab.start_game()
	var player := game.player
	game.director.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.horde.target = null
	player.global_position = Vector3(0, 1, 12)
	lab.equip_weapon("pulse")
	var target := game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 6), 1000.0)
	game.horde._rebuild_grid()
	await lab.frames(8)
	lab.aim_at(game.horde.enemy_position(target) + Vector3.UP * 0.45)
	var shots := [0]
	player.shot_fired.connect(func(): shots[0] += 1)
	var aim_before := player.head.global_basis
	var hp_before := game.horde._hp[target]
	lab.fire(true)
	await lab.wait(1.2)
	lab.fire(false)
	lab.check(shots[0] >= 6 and game.horde._hp[target] < hp_before, "held trigger delivers sustained real damage without reload")
	lab.check(player.head.global_basis.is_equal_approx(aim_before), "sustained shooting never drifts aim")
	lab.check(player.combo_hits == 0 and player.drop_charge == 0.0, "tank hit spam never creates STYLE or DROP")
	for kill in 4:
		game.horde.clear()
		target = game.horde.spawn(lab.enemy("robot_tank"), Vector2(0, 6), 0.001)
		game.horde._rebuild_grid()
		lab.aim_at(game.horde.enemy_position(target) + Vector3.UP * 0.45)
		player._shoot(false)
		lab.check(not game.horde.is_alive(target), "STYLE fixture is an actual primary kill")
	var style := player.combo_hits
	lab.check(style >= 32 and player.arena_score > 0, "actual primary kills award arena score and STYLE")
	var remaining := player._combo_left
	lab.aim_at(player.camera.global_position + Vector3.UP * 10.0)
	player._shoot(false)
	lab.check(player.combo_hits == style and is_equal_approx(player._combo_left, remaining), "a missed shot neither earns nor refreshes STYLE")
	player.set_arena_recovery(true)
	await lab.wait(0.5)
	lab.check(player.combo_hits == style and is_equal_approx(player._combo_left, remaining), "true arena recovery freezes style pressure")
	player.set_arena_recovery(false)
	player.grant_invulnerability(1.0e9)
	await _wait_decay(player)
	lab.check(player.combo_hits == style - maxi(1, ceili(style * 0.1)), "combat idle expiry decays STYLE by one ten-percent step")
	var build := game.run_state.primary
	build.upgrade(&"damage")
	build.upgrade(&"cadence")
	build.upgrade(&"projectiles")
	build.upgrade(&"frost")
	var original := build.source
	var partner: WeaponDefinition = null
	for source in game.run_state.available_weapons:
		if source != original:
			partner = source
			break
	lab.check(partner != null and game.run_state.equip_pair(original, partner), "the drafted pair commits two distinct sources")
	build = game.run_state.primary
	player.refresh_weapon()
	player.quick_swap()
	lab.check(build.source == partner and build.rank(&"damage") == 1, "quick toggle draws the drafted partner with purchased ranks intact")
	player.quick_swap()
	lab.check(build.source == original and game.run_state.secondary_primary_source == partner, "second quick toggle returns to the first drafted gun")
	var seen := {}
	var notch := InputEventAction.new()
	notch.action = &"weapon_next"
	notch.pressed = true
	for wheel in 5:
		player._input(notch)
		seen[build.source] = true
	lab.check(seen.size() == 2 and seen.has(original) and seen.has(partner), "combat wheel only alternates the drafted pair, never a catalog entry")
	lab.check(build.definition.damage == roundi(build.source.damage * 1.2) and is_equal_approx(build.definition.fire_interval, build.source.fire_interval / 1.15), "shared upgrade ranks reapply once to the selected gun's own stats")
	lab.check(build.definition.pellet_count == build.source.pellet_count + 2 and build.definition.damage_type == DamageType.Kind.FROST, "payload and elemental build upgrades survive quick swaps")

	game._open_pause()
	var count: int = shots[0]
	Input.action_press(&"fire")
	Input.action_press(&"jump")
	Input.action_press(&"slide")
	await lab.wait(0.2)
	game._on_resume()
	await lab.wait(0.3)
	lab.check(shots[0] == count and player._jump_buffer == 0.0 and not player.is_sliding(), "held menu trigger/jump/slide cannot replay on resume")
	Input.action_release(&"jump")
	Input.action_release(&"slide")
	lab.fire(false)
	await lab.frames(2)
	lab.fire(true)
	await lab.wait(0.3)
	lab.fire(false)
	lab.check(shots[0] > count, "fresh trigger after release restores fire")
	await _movement(game)

func _movement(game: ArenaGame) -> void:
	var player := game.player
	game.horde.clear()
	var fixture := Node3D.new()
	game.add_child(fixture)
	_box(fixture, Vector3(0, 30, 0), Vector3(20, 1, 20))
	_box(fixture, Vector3(0, 31.8, -4), Vector3(8, 0.3, 3))
	_box(fixture, Vector3(7.5, 33, 0), Vector3(0.5, 6, 20))
	_box(fixture, Vector3(-4, 33.15, 3), Vector3(3, 0.3, 3))
	var original_area := game.horde.play_area
	game.horde.play_area = Rect2(-8, -8, 16, 16)
	player.global_position = Vector3(0, 31.4, 3)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await lab.frames(8)
	lab.check(player.is_on_floor(), "movement fixture uses real native floor collision")
	await _press(&"jump", 2)
	await lab.frames(10)
	var falling := player.velocity.y
	await _press(&"jump", 2)
	lab.check(player.velocity.y > falling and not player._air_jump_available, "fresh airborne press performs exactly one real second jump")
	var second := player.velocity.y
	await _press(&"jump", 2)
	lab.check(player.velocity.y < second and not player._air_jump_available, "third airborne press cannot create another jump")
	await lab.wait(1.2)
	player.global_position = Vector3(0, 31.4, 0)
	player.velocity = Vector3.ZERO
	await lab.frames(5)
	Input.action_press(&"move_forward")
	await lab.wait(0.25)
	var aim := player.head.global_basis
	await _press(&"slide", 2)
	lab.check(player.is_sliding() and is_equal_approx((player.body_shape.shape as CapsuleShape3D).height, ArenaPlayer.SLIDE_HEIGHT) and player.head.position.y < 0.0, "momentum slide physically shrinks collider and lowers head")
	lab.fire(true)
	var z := player.global_position.z
	await lab.wait(0.12)
	lab.fire(false)
	Input.action_release(&"move_forward")
	lab.check(player.global_position.z < z and player.head.global_basis.is_equal_approx(aim), "sliding advances under native collision while shooting without aim drift")
	player.global_position = Vector3(0, 31.4, -4)
	player.velocity = Vector3.ZERO
	player._slide_left = 0.0
	await lab.frames(4)
	lab.check(player._crouched and not player._can_stand(), "low ceiling prevents unsafe standing after slide expires")
	player.global_position = Vector3(0, 31.4, 3)
	await lab.frames(4)
	lab.check(not player._crouched and is_equal_approx((player.body_shape.shape as CapsuleShape3D).height, ArenaPlayer.STANDING_HEIGHT), "leaving tunnel restores full collider and head clearance")
	player.global_position = Vector3(-4, 31.4, 3)
	player.velocity = Vector3.ZERO
	await lab.frames(3)
	await _press(&"jump", 2)
	await lab.frames(5)
	lab.check(player.global_position.y <= 32.11 and player.velocity.y <= 0.0, "jump collides with real overhead geometry rather than passing through ceiling")
	player.global_position = Vector3(6, 31.4, 3)
	player.velocity = Vector3.ZERO
	Input.action_press(&"move_right")
	await lab.wait(0.5)
	Input.action_release(&"move_right")
	lab.check(player.global_position.x < 7.0, "native wall collision blocks movement before arena clamp")
	player.global_position = Vector3(0, 34, 0)
	player.dash(Vector3(1000, 0, 1000), 0.1)
	await lab.frames(4)
	var bounds := game.horde.play_area.grow(-0.35)
	lab.check(player.global_position.x >= bounds.position.x and player.global_position.x <= bounds.end.x and player.global_position.z >= bounds.position.y and player.global_position.z <= bounds.end.y, "dash and airborne movement remain inside arena boundaries")
	game._open_pause()
	lab.check(not player.is_sliding() and player._jump_buffer == 0.0, "pause cancels movement actions without changing aim")
	game._on_resume()
	game.horde.play_area = original_area
	fixture.queue_free()

func _press(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await lab.frames(frames)
	Input.action_release(action)
	await lab.frames(2)

func _box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func _wait_decay(player: ArenaPlayer) -> void:
	var before := player.combo_hits
	for frame in 600:
		await lab.get_tree().physics_frame
		if player.combo_hits < before:
			return
	lab.check(false, "idle combat STYLE eventually decays")
