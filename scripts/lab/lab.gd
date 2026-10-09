class_name Lab
extends Node

## Visual test lab. Runs isolated scenarios (combat, boss, level-up, shop...)
## through the real game scenes with a sandboxed Profile, and captures
## screenshots of each step.
##
## Batch:       godot --path . res://scenes/lab/lab.tscn -- --scenario=shop,boss --out=/abs/dir
##              (`--scenario=all` runs everything; the process quits when done and
##              writes lab_report.txt next to the PNGs; see tools/lab.py.)
## Interactive: godot --path . res://scenes/lab/lab.tscn
##              Pick a scenario, then play on from its final state.
##              F1 returns to the scenario list, F12 saves a screenshot.

const GAME_SCENE := preload("res://scenes/game.tscn")
const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const SCENARIOS := {
	&"combat": preload("res://scripts/lab/scenarios/combat_scenario.gd"),
	&"weapons": preload("res://scripts/lab/scenarios/weapons_scenario.gd"),
	&"recoil": preload("res://scripts/lab/scenarios/recoil_scenario.gd"),
	&"boss": preload("res://scripts/lab/scenarios/boss_scenario.gd"),
	&"levelup": preload("res://scripts/lab/scenarios/level_up_scenario.gd"),
	&"shop": preload("res://scripts/lab/scenarios/shop_scenario.gd"),
	&"hud": preload("res://scripts/lab/scenarios/hud_scenario.gd"),
	&"mining": preload("res://scripts/lab/scenarios/mining_scenario.gd"),
	&"menu": preload("res://scripts/lab/scenarios/menu_scenario.gd"),
	&"icons": preload("res://scripts/lab/scenarios/icons_scenario.gd"),
}
## Batch runs never hang: the whole process quits after this many seconds.
const BATCH_TIMEOUT := 240.0
const REPORT_FILE := "lab_report.txt"

var game: ArenaGame
## Root of the scenario's own non-game content (menus, galleries).
var stage_root: Node
var out_dir := "user://lab"
var batch := false
var current := &""

var _failures: Array[String] = []
var _captures: Array[String] = []
var _menu: Control
var _overlay: Label
var _running := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Profile.enter_sandbox()
	var args := _arguments()
	if args.has("out"):
		out_dir = String(args["out"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_build_overlay()
	if args.has("scenario"):
		batch = not args.has("stay")
		if batch:
			AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
			get_tree().create_timer(BATCH_TIMEOUT, true, false, true).timeout.connect(_on_watchdog)
		var names := _requested(String(args["scenario"]))
		_run_all.call_deferred(names)
	else:
		_build_menu()

# ------------------------------------------------------------ helpers for scenarios

## Starts a run for `class_id` on campaign stage `stage`. The spawn director is
## halted, level-ups are only presented by the scenario and the player cannot
## be hurt, so the scenario controls everything on screen.
func start_game(class_id: StringName = &"scout", stage: int = 0) -> ArenaGame:
	Profile.selected_class_id = class_id
	game = GAME_SCENE.instantiate() as ArenaGame
	add_child(game)
	await frames(2)
	if stage != 0:
		game._load_stage(stage, 0)
		await frames(2)
	game.run_state.level_up_ready.disconnect(game._on_level_up_ready)
	game.director.set_physics_process(false)
	game.player.grant_invulnerability(1.0e9)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(2)
	return game

func enemy(id: String) -> HordeEnemyDefinition:
	return load("res://data/enemies/%s.tres" % id) as HordeEnemyDefinition

func weapon(id: String) -> WeaponDefinition:
	return load("res://data/weapons/%s.tres" % id) as WeaponDefinition

## Floor point `distance` m ahead of the player, `lateral` m to its right.
func ahead(distance: float, lateral: float = 0.0) -> Vector2:
	var player := game.player
	var forward := -player.global_basis.z
	var right := player.global_basis.x
	var at := player.global_position + forward * distance + right * lateral
	return Vector2(at.x, at.z)

## Spawns `count` enemies in a disc; returns their slots.
func spawn_pack(definition: HordeEnemyDefinition, center: Vector2, count: int, spread: float, health_multiplier: float = 1.0) -> PackedInt32Array:
	var slots := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(center) ^ count
	for n in count:
		var offset := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spread
		var slot := game.horde.spawn(definition, center + offset, health_multiplier)
		if slot >= 0:
			slots.append(slot)
	return slots

## Turns the player's body and head so the camera looks at `point`.
func aim_at(point: Vector3) -> void:
	var player := game.player
	var from := player.camera.global_position
	var direction := point - from
	player.rotation.y = atan2(-direction.x, -direction.z)
	var flat := Vector2(direction.x, direction.z).length()
	player.head.rotation.x = clampf(atan2(direction.y, flat), deg_to_rad(-85.0), deg_to_rad(85.0))

func fire(held: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if held:
		Input.action_press(&"fire")
	else:
		Input.action_release(&"fire")

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func frames(count: int) -> void:
	for n in count:
		await get_tree().process_frame

## Saves the next rendered frame as <scenario>_<label>.png.
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_save(image, label)

## Composites `count` consecutive captures, `interval` s apart, into a grid of
## half-size frames (left to right, top to bottom) for motion review.
func capture_strip(label: String, count: int, interval: float, columns: int = 3) -> void:
	var shots: Array[Image] = []
	for n in count:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		shots.append(image)
		if n < count - 1:
			await wait(interval)
	var cell := shots[0].get_size()
	var rows := ceili(float(count) / columns)
	var sheet := Image.create_empty(cell.x * columns, cell.y * rows, false, shots[0].get_format())
	for n in count:
		sheet.blit_rect(shots[n], Rect2i(Vector2i.ZERO, cell), Vector2i(n % columns * cell.x, n / columns * cell.y))
	_save(sheet, label)

func check(condition: bool, message: String) -> void:
	var line := "%s %s: %s" % ["PASS" if condition else "FAIL", current, message]
	print("LAB ", line)
	if not condition:
		_failures.append(line)

func log_line(text: String) -> void:
	print("LAB %s: %s" % [current, text])

# ------------------------------------------------------------ running

func _run_all(names: Array[StringName]) -> void:
	for scenario_name in names:
		await _run_one(scenario_name)
	if batch:
		_finish()

func _run_one(scenario_name: StringName) -> void:
	_running = true
	_teardown()
	await frames(1)
	current = scenario_name
	_overlay.text = "LAB  ·  %s  ·  F1 scenarios  ·  F12 capture" % String(scenario_name).to_upper()
	var scenario := (SCENARIOS[scenario_name] as GDScript).new() as LabScenario
	scenario.lab = self
	print("LAB run %s" % scenario_name)
	await scenario.run()
	fire(false)
	_running = false

func _teardown() -> void:
	fire(false)
	get_tree().paused = false
	Engine.time_scale = 1.0
	if is_instance_valid(game):
		game.free()
	game = null
	if is_instance_valid(stage_root):
		stage_root.free()
	stage_root = null
	Profile.enter_sandbox()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _finish() -> void:
	var lines := PackedStringArray()
	lines.append("captures=%d failures=%d" % [_captures.size(), _failures.size()])
	for path in _captures:
		lines.append("IMAGE " + path)
	lines.append_array(_failures)
	var file := FileAccess.open(out_dir.path_join(REPORT_FILE), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	print("LAB done: %d captures, %d failures" % [_captures.size(), _failures.size()])
	_teardown()
	get_tree().quit(1 if not _failures.is_empty() else 0)

func _on_watchdog() -> void:
	_failures.append("FAIL %s: batch timeout after %.0f s" % [current, BATCH_TIMEOUT])
	_finish()

func _save(image: Image, label: String) -> void:
	var path := out_dir.path_join("%s_%s.png" % [current, label])
	var error := image.save_png(path)
	if error != OK:
		check(false, "could not save %s (%s)" % [path, error_string(error)])
		return
	var absolute := ProjectSettings.globalize_path(path)
	_captures.append(absolute)
	print("LAB capture %s" % absolute)

func _requested(text: String) -> Array[StringName]:
	var names: Array[StringName] = []
	if text == "all":
		names.assign(SCENARIOS.keys())
		return names
	for part in text.split(",", false):
		var key := StringName(part.strip_edges())
		if SCENARIOS.has(key):
			names.append(key)
		else:
			_failures.append("FAIL lab: unknown scenario '%s' (known: %s)" % [part, ", ".join(SCENARIOS.keys())])
	return names

func _arguments() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var pair := argument.trim_prefix("--").split("=", true, 1)
		parsed[pair[0]] = pair[1] if pair.size() > 1 else ""
	return parsed

# ------------------------------------------------------------ interactive shell

func _unhandled_input(event: InputEvent) -> void:
	if batch or not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			if not _running:
				_teardown()
				_menu.show()
				get_viewport().set_input_as_handled()
		KEY_F12:
			capture("manual_%d" % Time.get_ticks_msec())
			get_viewport().set_input_as_handled()

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_overlay = Label.new()
	_overlay.position = Vector2(8, 4)
	_overlay.add_theme_font_size_override(&"font_size", 12)
	_overlay.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3, 0.8))
	_overlay.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = not OS.get_cmdline_user_args().has("--clean")
	layer.add_child(_overlay)

func _build_menu() -> void:
	_overlay.text = "LAB"
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_menu = PanelContainer.new()
	_menu.theme = MENU_THEME
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_menu)
	var center := CenterContainer.new()
	_menu.add_child(center)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	center.add_child(rows)
	var heading := Label.new()
	heading.text = "VISUAL TEST LAB"
	heading.add_theme_font_size_override(&"font_size", 34)
	rows.add_child(heading)
	var note := Label.new()
	note.text = "Sandboxed profile: nothing here touches your save.  F1 returns here, F12 captures."
	note.add_theme_font_size_override(&"font_size", 14)
	rows.add_child(note)
	for scenario_name: StringName in SCENARIOS:
		var scenario := (SCENARIOS[scenario_name] as GDScript).new() as LabScenario
		var button := Button.new()
		button.text = "%s  ·  %s" % [scenario.title().to_upper(), scenario.summary()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_menu_pick.bind(scenario_name))
		rows.add_child(button)
	(rows.get_child(2) as Button).grab_focus.call_deferred()

func _on_menu_pick(scenario_name: StringName) -> void:
	_menu.hide()
	await _run_one(scenario_name)
	if not is_instance_valid(game) and not is_instance_valid(stage_root):
		_menu.show()
