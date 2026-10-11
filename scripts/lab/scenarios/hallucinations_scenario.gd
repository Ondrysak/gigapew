extends LabScenario

const CENTER := Vector2(0, 9)
var _megas := PackedInt32Array()

func title() -> String:
	return "Recursive hallucinations"

func summary() -> String:
	return "Self-repeating native heads and limbs, inward head zoom and ghosted vision; real paused intensity input, precision shots and frozen anatomy"

func run() -> void:
	var game := await lab.start_game()
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(0, 1, 15)
	game.player.velocity = Vector3.ZERO
	game.horde.set_physics_process(false)
	game.pickups.set_physics_process(false)
	game.horde._rng.seed = 60412
	var grunt := lab.enemy("robot_grunt")
	game.horde._t_speed[game.horde._type_of[grunt]] = 0.0
	for n in 8:
		game.horde.spawn(grunt, CENTER + Vector2.from_angle(float(n) * TAU / 8.0) * 0.3, 200.0 / grunt.max_health)
	game.horde._rebuild_grid()
	for tick in 50:
		game.horde._physics_process(0.05)
	if game.horde.query_megas(_megas) == 0:
		lab.check(false, "dense gameplay pack forms a mega for recursive anatomy review")
		return
	var mega := _megas[0]
	var mouse := lab.enemy("alien_grunt")
	game.horde.register_definition(mouse)
	game.horde.spawn(mouse, CENTER + Vector2(-2.1, 0))
	game.horde.spawn(grunt, CENTER + Vector2(2.1, 0), 200.0 / grunt.max_health)
	game.horde._rebuild_grid()
	game.horde._process(0.0)
	game.horde._fx._process(1.0)
	lab.aim_at(game.horde.enemy_position(mega))
	await lab.capture("default")
	await lab.capture_strip("recursive_anatomy", 9, 0.8)

	# Hold poses and simulation while exercising the actual settings control.
	# Only the new shader treatment may change between these snapshots.
	game.set_process(false)
	game.horde.set_process(false)
	game.horde._fx.set_process(false)
	game.player.set_process(false)
	game._open_pause()
	game.pause_menu.settings_button.pressed.emit()
	var settings = game.pause_menu.settings
	await lab.frames(3)
	settings.hallucinations_slider.grab_focus()
	await _slider_key(KEY_HOME)
	await lab.capture("settings_off")
	lab.check(settings.hallucinations_value.get_minimum_size().x <= settings.hallucinations_value.size.x, "off label fits the rendered settings row")
	game.pause_menu.hide()
	var off := await _image()
	await lab.capture("off")
	game.pause_menu.show()
	settings.hallucinations_slider.grab_focus()
	await _slider_key(KEY_END)
	await lab.capture("settings_full")
	game.pause_menu.hide()
	var full := await _image()
	await lab.capture("full")
	var anatomy := _region(game.player.camera, game.horde.enemy_position(mega), Vector2i(100, 100))
	var head := _region(game.player.camera, game.horde.weak_spot_position(mega), Vector2i(7, 7))
	lab.check(_difference(off, full, anatomy) > 0.002, "actual paused slider input visibly adds recursive native anatomy")
	lab.check(_difference(off, full, head) < 0.0005, "hallucination intensity leaves the main precision head readable")
	var periphery := Rect2i(40, 285, 130, 155)
	lab.check(_difference(off, full, periphery) > 0.01, "intensity adds strong peripheral feedback echoes and blur to the rendered world")
	# HUD panels are translucent; their opaque health bar and text must stay unchanged.
	lab.check(_difference(off, full, Rect2i(60, 638, 290, 18)) < 0.0005, "world feedback does not blur the health bar or its text")
	await lab.wait(0.4)
	var held := await _image()
	lab.check(_difference(full, held, anatomy) < 0.0005, "recursive anatomical motion remains frozen while paused")
	lab.check(_difference(full, held, periphery) < 0.0005, "feedback zoom stops flowing while paused")
	game.pause_menu.show()
	settings.hallucinations_slider.grab_focus()
	await _slider_key(KEY_HOME)
	game.pause_menu.hide()
	var restored := await _image()
	lab.check(_difference(off, restored, anatomy) < 0.0005 and _difference(off, restored, periphery) < 0.0005, "off removes recursive anatomy and the feedback pass, restoring the original scene")
	game._on_resume()
	Profile.set_setting("hallucination_intensity", 1.0)

	# Phantom anatomy cannot move the main precision target or change damage.
	game.run_state.crit_chance = 0.0
	var gun := lab.weapon("pulse").duplicate() as WeaponDefinition
	gun.damage = 10.0
	gun.pierce = 0
	game.run_state.initialize_primary(gun)
	game.player.refresh_weapon()
	var before := game.horde._hp[mega]
	lab.aim_at(game.horde.weak_spot_position(mega))
	game.player._shoot()
	var precision := game.run_state.crit_multiplier + RunState.WEAK_SPOT_CRIT_BONUS
	lab.check(is_equal_approx(before - game.horde._hp[mega], 10.0 * precision), "full hallucination intensity preserves real precision-shot damage")
	game.horde._process(0.0)
	await lab.capture("precision_flash")
	game.horde._physics_process(0.3)
	game.horde.expose(mega, 4.0)
	game.horde._process(0.0)
	await lab.capture("tagged")
	game.horde.stun(mega, 4.0)
	game.horde._process(0.0)
	await lab.capture("staggered")
	game.horde._fx.set_process(true)
	game.horde.clear()
	await lab.frames(3)
	await lab.capture("cleared")
	game.set_process(true)
	game.horde.set_process(true)
	Profile.set_setting("hallucination_intensity", 0.65)
	await _anatomy_gallery(game)

func _anatomy_gallery(game: ArenaGame) -> void:
	for species in ["robot_grunt", "alien_grunt", "alien_runner"]:
		game.horde.clear()
		game.player.global_position = Vector3(0, 1, 15)
		var definition := lab.enemy(species)
		game.horde.register_definition(definition)
		game.horde._t_speed[game.horde._type_of[definition]] = 0.0
		for n in 8:
			game.horde.spawn(definition, CENTER + Vector2.from_angle(float(n) * TAU / 8.0) * 0.3, 200.0 / definition.max_health)
		game.horde._rebuild_grid()
		for tick in 50:
			game.horde._physics_process(0.05)
		if game.horde.query_megas(_megas) == 0:
			lab.check(false, "%s forms a mega for its native anatomy gallery" % species)
			continue
		var mega := _megas[0]
		game.horde._process(0.0)
		lab.aim_at(game.horde.enemy_position(mega))
		await lab.capture(species + "_anatomy")
		game.player.global_position = Vector3(0, 1, 12)
		lab.aim_at(game.horde.weak_spot_position(mega))
		await lab.capture_strip(species + "_head_zoom", 9, 0.8)
		await _head_cycle_boundary(game, mega, species)

func _head_cycle_boundary(game: ArenaGame, mega: int, species: String) -> void:
	# Exercise an actual depth-layer recycle while holding the source VAT pose.
	game.set_process(false)
	game.horde.set_process(false)
	game.horde._fx.set_process(false)
	var boundary := (1.0 - game.horde._phase[mega] * 0.08) * 10.0
	while boundary < game.run_time + 1.0:
		boundary += 10.0
	var crop := _region(game.player.camera, game.horde.weak_spot_position(mega), Vector2i(200, 130))
	var shots: Array[Image] = []
	for n in 9:
		game.run_time = boundary + float(n - 4) * 0.05
		RenderingServer.global_shader_parameter_set("hallucination_time", game.run_time)
		var image := await _image()
		shots.append(image.get_region(crop.intersection(Rect2i(Vector2i.ZERO, image.get_size()))))
	var cell := shots[0].get_size()
	var sheet := Image.create_empty(cell.x * 3, cell.y * 3, false, shots[0].get_format())
	for n in shots.size():
		sheet.blit_rect(shots[n], Rect2i(Vector2i.ZERO, cell), Vector2i(n % 3 * cell.x, n / 3 * cell.y))
	lab._save(sheet, species + "_head_cycle_boundary")
	game.set_process(true)
	game.horde.set_process(true)
	game.horde._fx.set_process(true)


func _slider_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await lab.frames(2)
	event = InputEventKey.new()
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await lab.frames(2)

func _image() -> Image:
	await lab.frames(2)
	await RenderingServer.frame_post_draw
	return lab.get_viewport().get_texture().get_image()

func _region(camera: Camera3D, point: Vector3, half_size: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(camera.unproject_position(point)) - half_size, half_size * 2)

func _difference(a: Image, b: Image, region: Rect2i) -> float:
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var total := 0.0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
	return total / maxf(float(clipped.get_area()) * 3.0, 1.0)
