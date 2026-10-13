extends LabScenario

const CENTER := Vector2(0, 9)
var _megas := PackedInt32Array()

func title() -> String:
	return "CrystalDive hallucination modes"

func summary() -> String:
	return "Real paused preset input, combo-driven lens/mirrors, pivoted native head motion and warped campaign floors without collider changes"

func run() -> void:
	Profile.set_setting("hallucination_intensity", 1.0)
	var game := await lab.start_game()
	game.director.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(0, 1, 15)
	game.horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	game.horde._rng.seed = 60412
	var target := _mega(game, "robot_grunt")
	if target < 0:
		return
	await _build_combo(game, target)
	# Hold the actual camera/recoil spring as well as the source VAT pose.
	game.player.set_process(false)
	game.horde._process(0.0)
	game.horde.set_process(false)
	game.horde._fx.set_process(false)
	lab.aim_at(game.horde.weak_spot_position(target))
	game._open_pause()
	game.pause_menu.settings_button.pressed.emit()
	await lab.frames(3)
	var settings = game.pause_menu.settings
	await _select_mode(settings.hallucinations_mode, Profile.HallucinationMode.LIQUID)
	var window := lab.get_tree().root
	var original_size := window.size
	window.size = Vector2i(960, 600)
	await lab.frames(4)
	await lab.capture("compact_settings")
	lab.check(settings.back_button.get_global_rect().end.y <= float(window.size.y) and settings.back_button.get_global_rect().position.y >= 0.0, "preset and back controls remain reachable at 960x600")
	window.size = original_size
	await lab.frames(4)
	await lab.capture("paused_liquid_settings")
	game.pause_menu.hide()
	var vision := game.get_node("HallucinationVision") as HallucinationVision
	var liquid := await _image()
	await _select_mode(settings.hallucinations_mode, Profile.HallucinationMode.CRYSTAL, game)
	var crystal := await _image()
	lab.check(_difference(liquid, crystal, Rect2i(40, 285, 130, 155)) > 0.01, "actual paused preset input changes the rendered lens into crystal mirrors")
	var held_time := game.run_time
	for mode in Profile.HALLUCINATION_MODE_NAMES.size():
		Profile.set_setting("hallucination_mode", mode)
		var picture := await _image()
		lab._save(picture, "mode_%d" % mode)
		vision.hide()
		var source := await _image()
		var center := Rect2i(picture.get_size() / 2 - Vector2i(20, 20), Vector2i(40, 40))
		lab.check(_difference(source, picture, center) < 0.0005, "mode %d preserves the clear screen-space aim centre" % mode)
		lab.check(_difference(source, picture, Rect2i(60, 638, 290, 18)) < 0.0005, "mode %d leaves opaque HUD health/text crisp" % mode)
		# Reopening the saved preset also restores the correct screen visibility.
		Profile.changed.emit()
		await lab.wait(0.15)
		var held := await _image()
		lab.check(_difference(picture, held, Rect2i(40, 285, 130, 155)) < 0.0005 and game.run_time == held_time, "mode %d remains visually frozen in native pause" % mode)
	Profile.set_setting("hallucination_mode", Profile.HallucinationMode.HEADS)
	lab.check(not vision.visible and vision.effective_intensity > 0.99, "head-only mode keeps native anatomy live without a screen-copy pass")
	game._on_resume()
	game.set_process(false)
	await _head_motion(game)
	game.free()
	lab.game = null
	await lab.frames(2)
	await _campaign_floors()

func _mega(game: ArenaGame, species: String) -> int:
	game.horde.clear()
	var definition := lab.enemy(species)
	game.horde.register_definition(definition)
	game.horde._t_speed[game.horde._type_of[definition]] = 0.0
	for n in 8:
		game.horde.spawn(definition, CENTER + Vector2.from_angle(float(n) * TAU / 8.0) * 0.3, 200.0 / definition.max_health)
	game.horde._rebuild_grid()
	for tick in 50:
		game.horde._physics_process(0.05)
	if game.horde.query_megas(_megas) == 0:
		lab.check(false, "%s forms a real mega for head rotation review" % species)
		return -1
	game.horde._process(0.0)
	return _megas[0]

func _build_combo(game: ArenaGame, target: int) -> void:
	var gun := lab.weapon("pulse").duplicate() as WeaponDefinition
	gun.damage = 25
	gun.jitter_degrees = 0.0
	gun.pierce = 0
	game.run_state.initialize_primary(gun)
	game.player.refresh_weapon()
	var definition := lab.enemy("robot_grunt")
	for kill in 20:
		if game.player.combo_hits >= 100:
			break
		var victim := game.horde.spawn(definition, Vector2(game.player.global_position.x, game.player.global_position.z - 2.0), 1.0 / definition.max_health)
		game.horde._rebuild_grid()
		lab.aim_at(game.horde.enemy_position(victim) + Vector3.UP * 0.4)
		game.player._shoot(false)
		lab.check(not game.horde.is_alive(victim), "mode drive fixture dies to an actual primary shot")
	# Let real kill confirmations and damage numbers expire before pose comparisons.
	await lab.wait(1.5)
	lab.aim_at(game.horde.weak_spot_position(target))
	var vision := game.get_node("HallucinationVision") as HallucinationVision
	for frame in 240:
		if vision.effective_intensity > 0.99:
			break
		await lab.get_tree().process_frame
	lab.check(game.player.combo_hits >= 100 and vision.effective_intensity > 0.99, "real primary kills raise selected effects to the saved full STYLE ceiling")

func _head_motion(game: ArenaGame) -> void:
	var vision := game.get_node("HallucinationVision") as HallucinationVision
	# Only SWARM roles fuse: human and mouse silhouettes provide real mega heads.
	for species in ["robot_grunt", "alien_grunt"]:
		var target := _mega(game, species)
		if target < 0:
			continue
		lab.aim_at(game.horde.weak_spot_position(target))
		var point := Vector2i(game.player.camera.unproject_position(game.horde.weak_spot_position(target)))
		var anatomy := Rect2i(point - Vector2i(180, 70), Vector2i(360, 140))
		Profile.set_setting("hallucination_mode", Profile.HallucinationMode.HEADS)
		var shots: Array[Image] = []
		for t in [0.0, 6.0, 12.0, 18.0]:
			game.run_time = t
			RenderingServer.global_shader_parameter_set("hallucination_time", t)
			shots.append(await _image())
		var cell := anatomy.size
		var sheet := Image.create_empty(cell.x * 4, cell.y, false, shots[0].get_format())
		for n in shots.size():
			sheet.blit_rect(shots[n], anatomy, Vector2i(cell.x * n, 0))
		lab._save(sheet, species + "_head_turns")
		# Compare mode/off at the same source pose; legacy fused-body movement
		# is allowed to follow its own clock even with appendages disabled.
		Profile.set_setting("hallucination_intensity", 0.0)
		Profile.set_setting("hallucination_mode", Profile.HallucinationMode.FEEDBACK)
		var off := await _image()
		Profile.set_setting("hallucination_mode", Profile.HallucinationMode.HEADS)
		var restored := await _image()
		lab.check(_difference(off, restored, anatomy) < 0.0005 and not vision.visible, "%s zero intensity restores the exact original pose without rotating copies" % species)
		Profile.set_setting("hallucination_intensity", 1.0)
		game.run_state.crit_chance = 0.0
		var before := game.horde._hp[target]
		game.player._shoot()
		var expected := game.run_state.primary.definition.damage * (1.0 + game.player._combo_bonus()) * (game.run_state.crit_multiplier + RunState.WEAK_SPOT_CRIT_BONUS)
		lab.check(is_equal_approx(before - game.horde._hp[target], expected), "%s rotating anatomy preserves real precision-shot damage" % species)
		await lab.wait(1.5) # Expire the real hit marker and damage number before the next pose pair.

func _campaign_floors() -> void:
	var game := await lab.start_game(&"scout", 0, true, 60412)
	for stage in 3:
		if stage > 0:
			game._load_stage(stage, 60412)
			await lab.frames(3)
		game.director.set_physics_process(false)
		game.horde.set_physics_process(false)
		game.player.set_physics_process(false)
		game.pickups.set_physics_process(false) # Fixture kills must not open level-up menus over the floor.
		var target := game.horde.spawn(lab.enemy("robot_grunt"), lab.ahead(2.6), 20.0)
		game.horde._rebuild_grid()
		await _build_combo(game, target)
		game._open_pause()
		game.pause_menu.hide()
		game.hud.hide()
		game.player.hide()
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8.0
		camera.make_current()
		var stand := game.player.global_position
		await _floor_view(game, camera, Vector3(stand.x, 0.0, stand.z), "street_%d" % stage)
		var seen: Dictionary = {}
		for site: Dictionary in (game.world as ProceduralWorld).kit_sites:
			var kind: StringName = site.kind
			if seen.has(kind) or (stage == 0 and kind not in [&"hospoda", &"herna", &"nonstop", &"metro", &"wc"]) or (stage != 0 and (stage != 1 or kind != &"vecerka")):
				continue
			seen[kind] = true
			var centre: Vector2 = (site.rect as Rect2).get_center()
			var floor_point := Vector3(centre.x, float(site.floor_y), centre.y)
			camera.position = floor_point + Vector3.UP * (float(site.ceiling_y) - float(site.floor_y) - 0.15)
			await _floor_view(game, camera, floor_point, String(kind), false)
		camera.free()
		game.player.camera.make_current()
		game.player.show()
		game.hud.show()
		game._on_resume()

func _floor_view(game: ArenaGame, camera: Camera3D, point: Vector3, label: String, outdoor: bool = true) -> void:
	game.horde.hide() # Floor motion must not be supplied by animated enemy anatomy.
	if outdoor:
		camera.position = point + Vector3.UP * 5.0
	camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	var vision := game.get_node("HallucinationVision") as HallucinationVision
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, 0xFFFFFFFF)
	var before := game.get_world_3d().direct_space_state.intersect_ray(query)
	Profile.set_setting("hallucination_intensity", 0.0)
	var original := await _image()
	lab._save(original, label + "_off")
	Profile.set_setting("hallucination_intensity", 1.0)
	for mode in [Profile.HallucinationMode.VORTEX, Profile.HallucinationMode.LIQUID, Profile.HallucinationMode.MIX]:
		Profile.set_setting("hallucination_mode", mode)
		vision.hide() # Isolate real spatial floor patterns, not screen lensing.
		var warped := await _image()
		lab._save(warped, "%s_floor_%d" % [label, mode])
		lab.check(_difference(original, warped, Rect2i(220, 160, 800, 400)) > 0.001, "%s mode %d changes real floor patterns without relying on the screen pass" % [label, mode])
		var after := game.get_world_3d().direct_space_state.intersect_ray(query)
		lab.check(not before.is_empty() and not after.is_empty() and before.position.is_equal_approx(after.position) and before.collider == after.collider, "%s mode %d leaves its actual physical floor unchanged" % [label, mode])
		await lab.wait(0.1)
		var held := await _image()
		lab.check(_difference(warped, held, Rect2i(220, 160, 800, 400)) < 0.0005, "%s mode %d floor motion freezes in gameplay pause" % [label, mode])
		var motion := 0.0
		for advance in [6.0, 12.0]:
			RenderingServer.global_shader_parameter_set("hallucination_time", game.run_time + advance)
			var moving := await _image()
			motion = maxf(motion, _visible_change_fraction(warped, moving, Rect2i(220, 160, 800, 400)))
			if label == "nonstop" and advance == 12.0:
				lab._save(moving, "nonstop_floor_%d_motion" % mode)
		lab.check(motion > 0.005, "%s mode %d visibly moves floor pixels with gameplay-clock advance (%.2f%%)" % [label, mode, motion * 100.0])
		RenderingServer.global_shader_parameter_set("hallucination_time", game.run_time)
	Profile.set_setting("hallucination_intensity", 0.0)
	var restored := await _image()
	lab.check(_difference(original, restored, Rect2i(220, 160, 800, 400)) < 0.0005, "%s off restores the exact original spatial floor" % label)
	Profile.set_setting("hallucination_intensity", 1.0)

func _select_mode(option: OptionButton, mode: int, game: ArenaGame = null) -> void:
	if game != null:
		game.pause_menu.show()
	option.grab_focus()
	await _key(KEY_SPACE)
	var focused := option.get_popup().get_focused_item()
	if focused < 0:
		await _key(KEY_DOWN)
		focused = 0
	for n in absi(mode - focused):
		await _key(KEY_DOWN if focused < mode else KEY_UP)
	await _key(KEY_ENTER)
	lab.check(int(Profile.settings.hallucination_mode) == mode, "real keyboard preset selection saves the requested mode %d" % mode)
	if game != null:
		game.pause_menu.hide()

func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await lab.frames(2)

func _image() -> Image:
	await lab.frames(2)
	await RenderingServer.frame_post_draw
	return lab.get_viewport().get_texture().get_image()

func _difference(a: Image, b: Image, region: Rect2i) -> float:
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var total := 0.0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
	return total / maxf(float(clipped.get_area()) * 3.0, 1.0)

func _visible_change_fraction(a: Image, b: Image, region: Rect2i) -> float:
	# Sparse seams on dark industrial plates must visibly move too. Whole-frame
	# mean RGB dilutes these into otherwise unchanged solid-colour plate faces.
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var changed := 0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			var contrast := maxf(absf(first.r - second.r), maxf(absf(first.g - second.g), absf(first.b - second.b)))
			if contrast > 0.01:
				changed += 1
	return float(changed) / maxf(float(clipped.get_area()), 1.0)
