extends LabScenario

## Skill combos through physical number keys and real horde damage: CRUSH,
## COLLAPSE and SHIELD RAM, their HUD callouts, and controls proving that the
## same skills alone never trigger them.

func title() -> String:
	return "Skill combos"

func summary() -> String:
	return "Gravity Well crush and collapse, shield ram, callouts and no false triggers"

func run() -> void:
	var game := await lab.start_game(&"driller")
	game.horde.target = null
	game.horde.set_physics_process(false)
	await _crush(game)
	await _collapse(game)
	game.free()
	game = await lab.start_game(&"scout")
	game.horde.target = null
	game.horde.set_physics_process(false)
	await _ram(game)

func _crush(game: ArenaGame) -> void:
	_prepare(game)
	var slots := _pack(game, Vector2(0, 4))
	var horde := game.horde
	var seismic := game.player.abilities[0]
	var slot := slots[0]
	var hp := horde._hp[slot]
	seismic.blast(horde.enemy_position(slot), 3.0, 100.0, 0.0)
	var plain := hp - horde._hp[slot]
	lab.check(plain > 0.0 and _count(game, &"crush") == 0, "a skill blast without a well deals plain damage and no combo")
	lab.aim_at(Vector3(0, 0.8, 4))
	await _key(3)
	var well := game.player.abilities[3] as GravityWell
	lab.check(well.is_active(), "physical 4 opens a real Gravity Well on the pack")
	hp = horde._hp[slot]
	seismic.blast(horde.enemy_position(slot), 3.0, 100.0, 0.0)
	var crushed := hp - horde._hp[slot]
	lab.check(is_equal_approx(crushed, plain * ActiveAbility.CRUSH_MULTIPLIER) and _count(game, &"crush") == 1, "a skill blast inside the well CRUSHES for exactly +60%% (%.0f to %.0f)" % [plain, crushed])
	# End to end: a real thrown Seismic Charge landing in the field.
	var before := _count(game, &"crush")
	lab.aim_at(Vector3(0, 0.0, 4))
	await _key(0)
	for _frame in 180:
		await lab.get_tree().physics_frame
		if _count(game, &"crush") > before:
			break
	lab.check(_count(game, &"crush") > before, "a real Seismic Charge thrown into the well triggers CRUSH")
	await lab.capture("crush")

func _collapse(game: ArenaGame) -> void:
	var well := game.player.abilities[3] as GravityWell
	var barrier := game.player.abilities[4] as PulseBarrier
	# Control: a well beyond collapse reach survives the barrier.
	_prepare(game)
	lab.aim_at(Vector3(0, 0.0, -3))
	await _key(3)
	var far := Vector2(well._center.x - game.player.global_position.x, well._center.z - game.player.global_position.z).length()
	await _key(4)
	lab.check(well.is_active() and _count(game, &"collapse") == 0, "a barrier %.0fm from the well leaves it running" % far)
	_prepare(game)
	var slots := _pack(game, Vector2(0, 8))
	lab.aim_at(Vector3(0, 0.8, 8))
	await _key(3)
	await lab.wait(0.3)
	var buffer := PackedInt32Array()
	buffer.resize(64)
	var held := game.horde.query_radius(well._center, well.radius, buffer)
	var slot := slots[0]
	var hp := game.horde._hp[slot]
	var expected := well.collapse_damage * well.damage_scale() * (1.0 + minf(1.5, held * 0.1))
	await _key(4)
	var dealt := hp - game.horde._hp[slot]
	lab.check(not well.is_active() and _count(game, &"collapse") == 1, "Pulse Barrier near the active well COLLAPSES it")
	lab.check(dealt >= expected * 0.99, "the collapse burst scales with %d held enemies (%.0f dealt, %.0f expected)" % [held, dealt, expected])
	await lab.wait(0.1)
	await lab.capture("collapse")
	barrier.cancel()

func _ram(game: ArenaGame) -> void:
	# Control: the same dash without a shield.
	_prepare(game)
	var slots := _pack(game, Vector2(0, 2))
	var hp := _total(game, slots)
	await _key(0)
	await lab.wait(0.5)
	var dash_only := hp - _total(game, slots)
	lab.check(_count(game, &"ram") == 0, "a dash under its own invulnerability is no shield ram")
	_prepare(game)
	slots = _pack(game, Vector2(0, 2))
	hp = _total(game, slots)
	await _key(4)
	await _key(0)
	await lab.wait(0.5)
	var rammed := hp - _total(game, slots)
	var ram := ActiveAbility.RAM_DAMAGE * game.player.abilities[0].damage_scale()
	lab.check(_count(game, &"ram") == 1 and rammed >= dash_only + ram * 0.9, "dashing inside Pulse Barrier SHIELD RAMs on arrival (%.0f vs %.0f)" % [rammed, dash_only])
	await lab.capture("shield_ram")

func _prepare(game: ArenaGame) -> void:
	Input.action_release(&"fire")
	for skill in game.player.abilities:
		skill.cancel()
		skill._cooldown = 0.0
	game.horde.clear()
	game.player.combo_counts.clear()
	game.player._combo_quiet.clear()
	game.player.active = true
	game.player._dash_time = 0.0
	game.player._invulnerable = 0.0
	game.player.velocity = Vector3.ZERO
	game.player.global_position = Vector3(0, 1, 12)
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO

func _pack(game: ArenaGame, center: Vector2) -> PackedInt32Array:
	var slots := PackedInt32Array()
	for offset in [Vector2.ZERO, Vector2(-1.5, 0.5), Vector2(1.5, 0.5), Vector2(0, -1.5)]:
		slots.append(game.horde.spawn(lab.enemy("robot_tank"), center + offset, 1000.0))
	game.horde._rebuild_grid()
	return slots

func _total(game: ArenaGame, slots: PackedInt32Array) -> float:
	var total := 0.0
	for slot in slots:
		total += game.horde._hp[slot]
	return total

func _count(game: ArenaGame, id: StringName) -> int:
	return int(game.player.combo_counts.get(id, 0))

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
