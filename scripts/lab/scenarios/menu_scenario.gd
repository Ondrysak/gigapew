extends LabScenario

const WORKSHOP_TABS: Array[String] = ["armor", "weapons", "gadgets", "perks", "talents", "armory"]

func title() -> String:
	return "Menus"

func summary() -> String:
	return "Main menu, class select (selected and locked operator) and every base workshop tab with a funded sandbox profile"

func run() -> void:
	Profile.add_currency(&"gold", 124)
	Profile.add_currency(&"crystal", 70)
	Profile.add_currency(&"shard", 12)
	# Crafted gear so the loadout panel shows armor, a swapped gun and a gadget.
	for id: StringName in [&"scout_suit", &"weapon_scatter", &"fire_converter"]:
		lab.check(Profile.craft(id), "crafted %s" % id)
	lab.check(Profile.equip_craft(&"scout_suit", 0), "equipped scout suit")
	lab.check(Profile.equip_craft(&"weapon_scatter", 1), "equipped scatter on hand 2")
	lab.check(Profile.equip_craft(&"fire_converter", 0), "equipped cinder converter on hand 1")
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	lab.stage_root = menu
	lab.add_child(menu)
	await lab.wait(1.0)
	await lab.capture("home")
	await _class_select(menu)
	menu._show_home()
	await _workshop(menu)

func _class_select(menu: Node) -> void:
	var screen: ClassSelectScreen = menu.class_select
	menu._open(screen, menu.play_button)
	await lab.wait(0.6)
	for card in screen._cards:
		lab.check(card.badge.visible and card.icon_rect.texture != null, "%s card shows its class icon" % card.definition.id)
		lab.check(card.icon_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "%s card icon is nearest-filtered" % card.definition.id)
	_check_ability_tiles(screen)
	await lab.capture("class_select")
	# Every other operator through keyboard focus; the sandbox roster starts
	# with only the first one unlocked, so these are the locked looks.
	var locked_seen := 0
	for card in screen._cards.slice(1):
		card.grab_focus()
		await lab.wait(0.4)
		lab.check(screen._selected == card.definition, "focusing %s previews it" % card.definition.id)
		if not Profile.is_class_unlocked(card.definition):
			locked_seen += 1
			lab.check(card.lock_icon.visible, "locked %s card shows the lock icon" % card.definition.id)
		_check_ability_tiles(screen)
		await lab.capture("class_select_%s" % card.definition.id)
	lab.check(locked_seen > 0, "class select captured a locked operator")

func _check_ability_tiles(screen: ClassSelectScreen) -> void:
	for option in screen._options:
		if option.visible:
			lab.check(option.icon_rect.texture != null, "ability tile %s shows an icon" % option.name_label.text)

func _workshop(menu: Node) -> void:
	var base: BaseScreen = menu.base
	menu._open(base, menu.base_button)
	await lab.wait(0.6)
	for card in base._cards:
		lab.check(card.badge.icon_rect.texture != null, "recipe %s shows an icon" % card.recipe.id)
	for hand in base._hands:
		lab.check(hand.badge.icon_rect.texture != null, "loadout %s shows a weapon icon" % hand.name.text)
	for index in range(WORKSHOP_TABS.size()):
		base._tabs.current_tab = index
		await lab.wait(0.4)
		await lab.capture("base_%s" % WORKSHOP_TABS[index])
	for card in base._legacy._cards:
		lab.check(card.badge.visible and card.icon_rect.texture != null, "armory %s shows its icon" % card.definition.id)
	# Hand 2 carries the crafted Scatter: select it and let the loadout
	# panel scroll it into view.
	base._tabs.current_tab = 1
	base._select_hand(1)
	base._hands[1].button.grab_focus()
	await lab.wait(0.2)
	var loadout_scroll := base._hands[1].button.get_parent().get_parent() as ScrollContainer
	loadout_scroll.ensure_control_visible(base._hands[1].stats)
	await lab.wait(0.2)
	await lab.capture("base_hand_2")
	# Replace a crafted gun carrying a real saved splitter, then restore it:
	# incompatible gadgets stay owned/saved without pretending to work.
	lab.check(Profile.craft(&"splitter") and Profile.equip_craft(&"splitter", 1), "crafted splitter equips on the saved shotgun")
	var gold := Profile.currency(&"gold")
	lab.check(Profile.craft(&"weapon_baton") and Profile.currency(&"gold") == gold, "free baton blueprint is reachable without spending scarce minerals")
	base._equip(&"weapon_baton")
	var preview := RunState.new()
	preview.initialize_hands(Profile.hand_loadout(Profile.selected_class()))
	Profile.apply_hand_gadgets(preview.hands)
	lab.check(preview.hands[1].definition.kind == WeaponDefinition.Kind.MELEE and preview.hands[1].rank(&"projectiles") == 0 and Profile.is_craft_equipped(&"splitter", 1), "equipping melee preserves the saved splitter but does not apply unsupported projectiles")
	base._tabs.current_tab = 2
	await lab.wait(0.2)
	await lab.capture("base_melee_inactive_gadget")
	base._equip(&"weapon_scatter")
	preview.initialize_hands(Profile.hand_loadout(Profile.selected_class()))
	Profile.apply_hand_gadgets(preview.hands)
	lab.check(preview.hands[1].rank(&"projectiles") == 1 and preview.hands[1].definition.pellet_count == lab.weapon("scatter").pellet_count + 2, "returning to the saved shotgun restores the same crafted splitter")
