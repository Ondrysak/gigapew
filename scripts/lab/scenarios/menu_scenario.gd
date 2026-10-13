extends LabScenario

const WORKSHOP_TABS: Array[String] = ["armor", "weapons", "gadgets", "perks", "talents", "armory"]

func title() -> String:
	return "Menus"

func summary() -> String:
	return "Intro, main menu, all operators, run setup with presets, records/settings, workshop tabs and in-run pause screens"

func run() -> void:
	Profile.add_currency(&"gold", 124)
	Profile.add_currency(&"crystal", 70)
	Profile.add_currency(&"shard", 12)
	# Crafted gear so the loadout panel shows armor, a swapped gun and a gadget.
	for id: StringName in [&"scout_suit", &"weapon_scatter", &"fire_converter"]:
		lab.check(Profile.craft(id), "crafted %s" % id)
	lab.check(Profile.equip_craft(&"scout_suit"), "equipped scout suit")
	lab.check(Profile.equip_craft(&"weapon_scatter"), "equipped the main shotgun")
	lab.check(Profile.equip_craft(&"fire_converter"), "equipped primary cinder conversion")
	await _intro()
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	lab.stage_root = menu
	lab.add_child(menu)
	await lab.wait(1.0)
	await lab.capture("home")
	await _class_select(menu)
	await _run_setup(menu)
	menu._show_home()
	await _workshop(menu)
	await _utility_pages(menu)
	menu.free()
	lab.stage_root = null
	await lab.frames(2)
	await _pause_pages()

func _class_select(menu: Node) -> void:
	var screen: ClassSelectScreen = menu.class_select
	menu._open(screen, menu.play_button)
	await lab.wait(0.6)
	await lab.capture("class_select")
	await _class_details(screen)
	# Preview locked operators and the freely available producer through focus.
	for card in screen._cards.slice(1):
		card.grab_focus()
		await lab.wait(0.4)
		lab.check(screen._selected == card.definition, "focusing %s previews it" % card.definition.id)
		if not Profile.is_class_unlocked(card.definition):
			lab.check(card.lock_icon.visible, "locked %s card shows the lock icon" % card.definition.id)
		await lab.capture("class_select_%s" % card.definition.id)
		await _class_details(screen)

## Operator select continues into run setup; every control saves the config.
func _run_setup(menu: Node) -> void:
	var screen: ClassSelectScreen = menu.class_select
	screen.card_row.get_child(0).grab_focus()
	await lab.wait(0.2)
	screen.action_button.pressed.emit()
	await lab.wait(0.4)
	var setup: RunSetupScreen = menu.run_setup
	lab.check(setup.visible and not screen.visible, "operator select continues into run setup instead of launching immediately")
	await lab.capture("run_setup")
	setup._level_buttons[1].pressed.emit()
	setup._preset_buttons[&"horda"].pressed.emit()
	await lab.wait(0.2)
	var saved := Profile.load_run_config()
	var foundry := setup._levels[1]
	lab.check(saved.level == foundry.id and saved.preset == &"horda" and saved.fights == foundry.arena_encounters and is_equal_approx(saved.density, 2.5), "level and preset buttons save Palmovka with the Horda tuning")
	await lab.capture("run_setup_horda")
	var density: Range = setup._sliders["density"].slider
	density.value = 1.0
	var tier: Range = setup._sliders["difficulty"].slider
	tier.value = 3
	await lab.wait(0.2)
	saved = Profile.load_run_config()
	lab.check(saved.preset == RunConfig.CUSTOM and is_equal_approx(saved.density, 1.0) and saved.difficulty == 3 and setup._blurb.text.begins_with("Vlastní"), "moving a tuning slider turns the preset custom and saves it; difficulty saves alongside")
	lab.check(setup._summary.text.contains("OBTÍŽNOST 3") and setup._summary.text.contains("%d těl" % saved.estimated_enemies(foundry)), "the summary states the real admitted-body estimate and the tier")
	setup._specialists.toggled.emit(false)
	await lab.wait(0.1)
	lab.check(not Profile.load_run_config().specialists, "the specialists switch saves")
	await lab.capture("run_setup_custom")
	setup.back_requested.emit()
	await lab.wait(0.3)
	lab.check(screen.visible and not setup.visible, "back from run setup returns to operator select")
	# Restore the default experience for the remaining in-run pages.
	var reset := RunConfig.new()
	Profile.set_run_config(reset)

func _class_details(screen: ClassSelectScreen) -> void:
	var scroll := screen.get_node("Margin") as ScrollContainer
	scroll.scroll_vertical = ceili(scroll.get_v_scroll_bar().max_value)
	await lab.wait(0.2)
	await lab.capture("class_details_%s" % screen._selected.id)

func _workshop(menu: Node) -> void:
	var base: BaseScreen = menu.base
	menu._open(base, menu.base_button)
	await lab.wait(0.6)
	for index in range(WORKSHOP_TABS.size()):
		base._tabs.current_tab = index
		await lab.wait(0.4)
		await lab.capture("base_%s" % WORKSHOP_TABS[index])
	# A saved single gadget carries across crafted-primary swaps.
	lab.check(Profile.craft(&"splitter") and Profile.equip_craft(&"splitter"), "crafted splitter equips on the saved main shotgun")
	lab.check(Profile.craft(&"weapon_rail"), "crafted a different main firearm")
	base._equip(&"weapon_rail")
	var preview := RunState.new()
	preview.initialize_primary(Profile.primary_loadout(Profile.selected_class()))
	Profile.apply_primary_gadget(preview.primary)
	lab.check(preview.primary.definition.pellet_count == lab.weapon("rail").pellet_count + 2 and Profile.is_craft_equipped(&"splitter"), "a saved crafted-primary swap retains and applies its single gadget")
	base._tabs.current_tab = 1
	await lab.wait(0.2)
	await lab.capture("base_primary_swap")
	base._equip(&"weapon_scatter")
	preview.initialize_primary(Profile.primary_loadout(Profile.selected_class()))
	Profile.apply_primary_gadget(preview.primary)
	lab.check(preview.primary.rank(&"projectiles") == 1 and preview.primary.definition.pellet_count == lab.weapon("scatter").pellet_count + 2, "returning to the shotgun reapplies the gadget once without compounding")

func _intro() -> void:
	var intro := (load("res://scenes/ui/intro.tscn") as PackedScene).instantiate()
	lab.stage_root = intro
	lab.add_child(intro)
	await lab.wait(3.4)
	await lab.capture("intro")
	intro.free()
	lab.stage_root = null
	await lab.frames(2)

func _utility_pages(menu: Node) -> void:
	Profile.record_run({
		"class_id": &"scout", "kills": 125, "time": 91.0, "level": 7,
		"stages_cleared": 2, "victory": true, "level_id": &"foundry", "difficulty": 3,
		"banked": {&"gold": 12, &"crystal": 8, &"shard": 1},
	})
	menu._open(menu.records, menu.records_button)
	await lab.wait(0.3)
	await lab.capture("records")
	var last := (menu.records as Node).get("last_run_label") as Label
	lab.check(last.text.contains("PALMOVKA · OBTÍŽNOST 3") and last.text.contains("2 KOL VYČIŠTĚNO"), "records name the last run's level, tier and cleared rounds")
	menu._open(menu.settings, menu.settings_button)
	await lab.wait(0.3)
	await lab.capture("settings")

func _pause_pages() -> void:
	var game := await lab.start_game()
	game._open_pause()
	await lab.wait(0.3)
	await lab.capture("pause")
	game.pause_menu.settings_button.pressed.emit()
	await lab.wait(0.3)
	await lab.capture("pause_settings")
	game.pause_menu.settings.back_requested.emit()
	game.pause_menu.abandon_button.pressed.emit()
	await lab.wait(0.3)
	await lab.capture("pause_abandon")
	game.pause_menu.cancel_abandon_button.pressed.emit()
	game.pause_menu.resume_button.pressed.emit()
