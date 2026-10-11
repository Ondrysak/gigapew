extends LabScenario

## The invented street faces, grime and homeless crowds. Faces are painted by
## tools/vat/faces/build_faces.py; no photograph or real person is involved.

const HOMELESS: Array[String] = ["robot_grunt", "robot_runner", "robot_spitter"]
const HUMANS: Array[String] = ["robot_grunt", "robot_runner", "robot_spitter", "robot_tank", "robot_bulwark", "robot_boss"]

func title() -> String:
	return "Street people"

func summary() -> String:
	return "Per-enemy invented faces and filth on every human, homeless crowds in all three sectors"

func run() -> void:
	_atlas_contract()
	await _gallery()
	await _sectors()

func _atlas_contract() -> void:
	for id in HUMANS:
		var definition := lab.enemy(id)
		var animation_ok := definition.vertex_animation != null
		lab.check(definition.face_atlas == Vector2i(4, 4) and definition.face_count >= 1 and definition.face_first + definition.face_count <= 16, "%s shows cells inside the 4x4 face atlas" % id)
		lab.check(animation_ok and definition.grime > 0.0, "%s is dirty" % id)
	for id in HOMELESS:
		var definition := lab.enemy(id)
		lab.check(definition.face_first == 0 and definition.face_count == 12, "%s draws from the twelve homeless faces" % id)
	for id in ["alien_grunt", "alien_boss"]:
		lab.check(lab.enemy(id).face_atlas == Vector2i.ONE, "%s has no face atlas" % id)

# The same pick the vertex shader makes from the per-instance phase.
func _cell(horde: Horde, slot: int, definition: HordeEnemyDefinition) -> int:
	var pick := mini(int(floorf(fposmod(horde._phase[slot], TAU) / TAU * definition.face_count)), definition.face_count - 1)
	return definition.face_first + pick

func _face_player(game: ArenaGame, slot: int) -> void:
	var away := game.horde.enemy_position(slot) - game.player.global_position
	game.horde._yaw[slot] = atan2(away.x, away.z)

func _place(game: ArenaGame, definition: HordeEnemyDefinition, at: Vector2, cell: int) -> int:
	var slot := game.horde.spawn(definition, at, 100.0)
	if slot < 0:
		lab.check(false, "street fixture can admit %s" % definition.display_name)
		return slot
	game.horde._phase[slot] = (float(cell - definition.face_first) + 0.5) / float(definition.face_count) * TAU
	_face_player(game, slot)
	return slot

func _fresh() -> ArenaGame:
	if is_instance_valid(lab.game):
		lab.game.free()
	var game := await lab.start_game(&"scout")
	game.horde.set_physics_process(false)
	game.horde.clear()
	game.player.grant_invulnerability(1.0e9)
	return game

func _look(at: Vector2, height: float) -> void:
	lab.aim_at(Vector3(at.x, height, at.y))

func _gallery() -> void:
	var game := await _fresh()
	var horde := game.horde
	# Statistical variety of a real crowd: the random per-instance phase alone.
	var cells := {}
	var grunt := lab.enemy("robot_grunt")
	for slot in lab.spawn_pack(grunt, lab.ahead(30.0), 48, 6.0):
		cells[_cell(horde, slot, grunt)] = true
	lab.check(cells.size() >= 9, "a crowd of 48 Bezdomovci shows %d of the 12 faces" % cells.size())
	# Every homeless face once, two rows facing the player.
	game = await _fresh()
	for cell in 12:
		var row := cell / 6
		var column := cell % 6
		_place(game, grunt, lab.ahead(3.6 + row * 2.0, (float(column) - 2.5) * 1.15 + row * 0.55), cell)
	_look(lab.ahead(4.4), 1.45)
	await lab.wait(0.35)
	await lab.capture("homeless_faces")
	for id in ["robot_runner", "robot_spitter"]:
		game = await _fresh()
		var definition := lab.enemy(id)
		for cell in 12:
			var row := cell / 6
			var column := cell % 6
			_place(game, definition, lab.ahead(3.6 + row * 2.0, (float(column) - 2.5) * 1.15 + row * 0.55), cell)
		_look(lab.ahead(4.4), 1.45)
		await lab.wait(0.35)
		await lab.capture("homeless_%s" % id.trim_prefix("robot_"))
	# Three close faces for a hard look at the painting on the real models.
	game = await _fresh()
	_place(game, lab.enemy("robot_runner"), lab.ahead(2.2, 0.0), 3)
	_place(game, lab.enemy("robot_spitter"), lab.ahead(2.2, -1.1), 4)
	_place(game, grunt, lab.ahead(2.2, 1.1), 11)
	_look(lab.ahead(2.2), 1.5)
	await lab.wait(0.35)
	await lab.capture("close_faces")
	# Harder men: the dealer and the bouncer, then the boss alone.
	game = await _fresh()
	_place(game, lab.enemy("robot_tank"), lab.ahead(4.5, -2.4), 12)
	_place(game, lab.enemy("robot_tank"), lab.ahead(4.5, -0.6), 13)
	_place(game, lab.enemy("robot_bulwark"), lab.ahead(4.5, 1.4), 13)
	_place(game, lab.enemy("robot_bulwark"), lab.ahead(4.5, 3.3), 14)
	_look(lab.ahead(4.5), 1.8)
	await lab.wait(0.35)
	await lab.capture("hard_faces")
	game = await _fresh()
	var boss := _place(game, lab.enemy("robot_boss"), lab.ahead(8.0, 0.0), 15)
	if boss >= 0:
		lab.aim_at(game.horde.weak_spot_position(boss))
		await lab.wait(0.3)
		await lab.capture("boss_face")

func _sectors() -> void:
	for stage in 3:
		if is_instance_valid(lab.game):
			lab.game.free()
		var game := await lab.start_game(&"scout", stage)
		var horde := game.horde
		horde.set_physics_process(false)
		horde.clear()
		var director := game.director
		director.setup(horde, game.campaign[stage].schedule, game.player)
		director.elapsed = 0.0
		director.boss_phase = false
		director._rng.seed = 910 + stage
		for tick in 360:
			director._physics_process(0.5)
		var seen := {}
		var homeless_alive := 0
		for active in horde._active_count:
			var slot := horde._active[active]
			if horde.is_alive(slot):
				var definition := horde.get_definition(slot)
				seen[definition.display_name] = true
				if definition.resource_path.get_file().get_basename() in HOMELESS:
					homeless_alive += 1
		lab.check(homeless_alive > 0, "sector %d admits homeless in its crowd (%d of %d, kinds: %s)" % [stage + 1, homeless_alive, horde._active_count, ", ".join(seen.keys())])
		# Bring a sample close for the picture.
		var sample := 0
		for active in horde._active_count:
			var slot := horde._active[active]
			if horde.is_alive(slot) and horde.get_definition(slot).resource_path.get_file().get_basename() in HOMELESS and sample < 14:
				var near := lab.ahead(4.0 + (sample % 3) * 1.8, (float(sample / 3) - 2.0) * 1.4)
				horde._pos[slot] = near
				_face_player(game, slot)
				sample += 1
		game.player.grant_invulnerability(1.0e9)
		var target := lab.ahead(5.0)
		lab.aim_at(Vector3(target.x, 1.4, target.y))
		await lab.wait(0.3)
		await lab.capture("sector_%d" % (stage + 1))
		await lab.frames(1)
