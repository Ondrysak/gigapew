extends LabScenario

func title() -> String:
	return "Real producer skill boundaries"

func summary() -> String:
	return "Directional guarded flurry, alternating impulses, remote frost speaker, real walls/decks, pause, rank scaling and cancellation"

func run() -> void:
	var game := await lab.start_game(&"producer")
	game.horde.target = null
	game.horde.set_physics_process(false)
	var deck_root := Node3D.new()
	game.add_child(deck_root)
	var deck := _box(deck_root, Vector3(-2, 1.95, 9.5), Vector3(1.5, 0.1, 1.5))
	var wall := _box(game, Vector3(1, 1.5, 10.5), Vector3(0.7, 3, 0.35))
	game.horde._read_elevation(deck_root, null)
	await _flurry(game)
	await _fader(game)
	deck.position.z = 5.0
	wall.position = Vector3(1.3, 1.5, 5)
	wall.get_child(0).shape.size = Vector3(0.35, 3, 1.8)
	game.horde._read_elevation(deck_root, null)
	await lab.frames(3)
	await _party(game)

func _box(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	body.add_child(mesh)
	parent.add_child(body)
	body.position = at
	return body

func _reset(game: ArenaGame) -> void:
	for skill in game.player.abilities:
		skill.cancel()
		skill._cooldown = 0.0
	game.horde.clear()
	game.player.active = true
	game.player._invulnerable = 0.0
	game.player.health = game.player.max_health
	game.player.global_position = Vector3(0, 1, 12)
	game.player.velocity = Vector3.ZERO
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO

func _spawn(game: ArenaGame, at: Vector2) -> int:
	return game.horde.spawn(lab.enemy("robot_grunt"), at, 1000.0)

func _key(slot: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_1 + slot
	event.keycode = KEY_1 + slot
	event.pressed = true
	Input.parse_input_event(event)
	await lab.get_tree().physics_frame
	await lab.get_tree().physics_frame
	event.pressed = false
	Input.parse_input_event(event)
	await lab.get_tree().process_frame

func _pause(skill: ActiveAbility) -> void:
	var left: float = skill.get("_remaining")
	var cooldown := skill.cooldown_remaining()
	lab.get_tree().paused = true
	await lab.wait(0.2)
	lab.check(is_equal_approx(float(skill.get("_remaining")), left) and is_equal_approx(skill.cooldown_remaining(), cooldown), "%s freezes effect and recharge during pause" % skill.display_name)
	lab.get_tree().paused = false

func _flurry(game: ArenaGame) -> void:
	_reset(game)
	var front := _spawn(game, Vector2(0, 9.5))
	var rear := _spawn(game, Vector2(0, 14.5))
	var blocked := _spawn(game, Vector2(1.8, 9))
	var raised := _spawn(game, Vector2(-2, 9.5))
	game.horde._rebuild_grid()
	await lab.frames(3)
	lab.aim_at(game.horde.enemy_position(front))
	var skill := game.player.abilities[0] as Brucelee
	var hp: float = game.horde._hp[front]
	var other_hp: float = game.horde._hp[rear]
	await _key(0)
	var health: int = game.player.health
	game.player.take_damage(9)
	lab.check(game.player.health == health and skill.is_shielded(), "Brucelee blocks real incoming damage with its own guard")
	await _pause(skill)
	await lab.capture("brucelee_guard")
	await lab.wait(skill.duration + 0.1)
	lab.check(skill.strikes_emitted == skill.strike_count and is_equal_approx(hp - game.horde._hp[front], skill.strike_damage * skill.damage_scale() * skill.strike_count), "Brucelee lands its timed directional flurry rather than a radial bubble")
	lab.check(game.horde._hp[rear] == other_hp and game.horde._hp[blocked] == other_hp and game.horde._hp[raised] == other_hp, "flurry excludes rear, solid-wall and actual raised-floor victims")
	game.player.take_damage(9)
	lab.check(game.player.health == health - 9 and not skill.is_shielded(), "expired Brucelee guard releases real damage")
	game.grant_upgrade(game.run_state.ability_upgrade_offer(0))
	skill._cooldown = 0.0
	var rank_hp: float = game.horde._hp[front]
	await _key(0)
	await lab.wait(skill.duration * skill.duration_scale() + 0.1)
	lab.check(skill.strikes_emitted == skill.strike_count + 1 and is_equal_approx(rank_hp - game.horde._hp[front], skill.strike_damage * skill.damage_scale() * (skill.strike_count + 1)), "Brucelee mastery adds a real strike and scales actual damage")
	skill._cooldown = 0.0
	await _key(0)
	await _key(4)
	var barrier := game.player.abilities[4] as PulseBarrier
	skill.cancel()
	var protected_health: int = game.player.health
	game.player.take_damage(9)
	lab.check(not skill.is_shielded() and barrier._remaining > 0.0 and game.player.health == protected_health, "cancelling Brucelee preserves another source's active shield")
	barrier.cancel()
	game.player.take_damage(9)
	lab.check(game.player.health == protected_health - 9, "the last owned shield ending restores incoming damage")
	var removable := (load("res://scenes/abilities/brucelee.tscn") as PackedScene).instantiate() as Brucelee
	game.player.add_child(removable)
	removable.setup(game.player, game.horde, game.run_state)
	removable.activate()
	removable.free()
	var unguarded_health: int = game.player.health
	game.player.take_damage(9)
	lab.check(game.player.health == unguarded_health - 9, "removing an active Brucelee node cannot leave permanent immunity")

func _fader(game: ArenaGame) -> void:
	_reset(game)
	var front := _spawn(game, Vector2(0, 9.5))
	var blocked := _spawn(game, Vector2(1.8, 9))
	var raised := _spawn(game, Vector2(-2, 9.5))
	game.horde._rebuild_grid()
	await lab.frames(3)
	var skill := game.player.abilities[1] as Crossfader
	var hp: float = game.horde._hp[front]
	await _key(1)
	var radial := game.horde._pos[front] - Vector2(skill._center.x, skill._center.z)
	lab.check(skill.inward_hits > 0 and game.horde._knock[front].dot(radial) < 0.0, "Crossfader first pulse applies a real inward native impulse")
	await _pause(skill)
	await lab.capture("crossfader_pull")
	while skill.pulses_emitted == 1 and skill._remaining > 0.0:
		await lab.get_tree().physics_frame
	lab.check(skill.outward_hits > 0 and game.horde._knock[front].dot(radial) > 0.0, "Crossfader next pulse reverses the crowd impulse outward")
	var distance_before := game.horde._pos[front].distance_to(Vector2(skill._center.x, skill._center.z))
	game.horde.target = game.player
	game.horde.set_physics_process(true)
	game.player.grant_invulnerability(1.0e9)
	await lab.wait(0.08)
	lab.check(game.horde._pos[front].distance_to(Vector2(skill._center.x, skill._center.z)) > distance_before, "outward Crossfader pulse moves a living enemy away through actual horde physics")
	game.horde.set_physics_process(false)
	game.horde.target = null
	await lab.capture("crossfader_push")
	await lab.wait(skill.duration + 0.1)
	lab.check(skill.pulses_emitted == skill.pulse_count and is_equal_approx(hp - game.horde._hp[front], skill.pulse_count * skill.pulse_damage * skill.damage_scale()), "Crossfader completes exactly its damaging alternating pulse sequence")
	lab.check(game.horde._hp[blocked] == hp and game.horde._hp[raised] == hp, "Crossfader cannot reach through a wall or onto another deck")

func _party(game: ArenaGame) -> void:
	_reset(game)
	var near := _spawn(game, Vector2(0, 5))
	var blocked := _spawn(game, Vector2(2.5, 5))
	var raised := _spawn(game, Vector2(-2, 5))
	game.horde._rebuild_grid()
	await lab.frames(3)
	lab.aim_at(Vector3(0, 0, 5))
	var skill := game.player.abilities[2] as PartyWithoutMe
	var hp: float = game.horde._hp[near]
	await _key(2)
	lab.check(skill.placement_valid and skill.is_deployed() and game.horde._hp[near] < hp and game.horde._slow[near] < 1.0, "physical3 deploys a valid remote speaker with real frost damage and slow")
	var center := skill.deployment_position()
	await _pause(skill)
	game.player.global_position = Vector3(0, 1, 18)
	await lab.wait(skill.pulse_interval + 0.1)
	lab.check(skill.deployment_position().is_equal_approx(center) and skill.pulses_emitted >= 2 and game.horde._hp[near] < hp - skill.pulse_damage * skill.damage_scale(), "speaker stays at its floor position and keeps damaging while its owner leaves")
	lab.check(game.horde._hp[blocked] == hp and game.horde._hp[raised] == hp, "remote speaker excludes wall-hidden and other-deck enemies")
	lab.aim_at(center + Vector3.UP * 0.6)
	await lab.capture("party_remote")
	skill.cancel()
	var stopped_hp: float = game.horde._hp[near]
	await lab.wait(skill.pulse_interval + 0.1)
	lab.check(not skill.is_deployed() and not skill._speaker.visible and game.horde._hp[near] == stopped_hp, "cancelling the speaker hides its pool and stops subsequent damage")
	skill._cooldown = 0.0
	game.player.global_position = Vector3(70, 1, 70)
	lab.aim_at(Vector3(70, 0, 63))
	lab.check(not skill.activate() and skill.cooldown_remaining() == 0.0 and not skill.is_deployed(), "missing-floor deployment fails without consuming recharge")
	game.player.global_position = Vector3(0, 1, 12)
	lab.aim_at(Vector3(0, 0, 5))
	lab.check(skill.activate(), "cancelled speaker can be redeployed from the same startup pool")
	game.player.active = false
	await lab.frames(3)
	lab.check(not skill.is_deployed() and not skill._speaker.visible, "inactive player cancels its live remote speaker")
