extends LabScenario

func title() -> String:
	return "Weapon draft and shop"

func summary() -> String:
	return "Two-gun draft at shared ranks, per-slot free replacement, mods, independent paid skills, capped ranks, insufficient currency and readable layout"

func run() -> void:
	var game := await lab.start_game(&"driller")
	await _draft(game)
	Profile.add_currency(&"gold", 240)
	Profile.add_currency(&"crystal", 100)
	Profile.add_currency(&"shard", 12)
	# The arena scenario exercises actual finite-combat completion separately.
	game._finish_stage_clear()
	await lab.wait(0.5)
	var screen := game.round_shop
	var shop := screen._shop
	await lab.capture("open")
	var rows: Control = screen.get_child(1).get_child(0)
	lab.check(rows.get_combined_minimum_size().y <= rows.size.y + 0.5, "shop's primary, five skills and stock fit the viewport without vertical clipping")
	for child in rows.get_children():
		if child is TabContainer:
			child.current_tab = 1
			await lab.frames(2)
			await lab.capture("suit_stock")
			child.current_tab = 0
			await lab.frames(2)
			break

	var bought := -1
	for index in shop.offers.size():
		if shop.section_of(index) == RoundShop.Section.MODS and shop.can_buy(index):
			bought = index
			break
	if bought < 0:
		lab.check(false, "funded shop supplies a purchasable primary modification")
		return
	var id := StringName(shop.offers[bought].id)
	var rank := shop.rank(id)
	var gold := Profile.currency(&"gold")
	await _click(screen._offers[bought].buy)
	lab.check(bool(shop.offers[bought].sold) and shop.rank(id) == rank + 1 and Profile.currency(&"gold") < gold, "clicking a visible stock card installs one primary rank, charges minerals and sells its stock")
	var paid_gold := Profile.currency(&"gold")
	await _click(screen._offers[bought].buy)
	lab.check(shop.rank(id) == rank + 1 and Profile.currency(&"gold") == paid_gold, "a repeated sold-card action cannot install or charge twice")
	var state := game.run_state
	var active := state.primary.source
	var partner := state.secondary_primary_source
	lab.check(partner != null and partner != active, "the shop opens with the two distinct drafted guns equipped")
	var spare: Array[WeaponDefinition] = []
	for source in state.available_weapons:
		if source != active and source != partner:
			spare.append(source)
	_pick(screen, state.available_weapons.find(active))
	lab.check(screen._replace_buttons[0].disabled and screen._replace_buttons[1].disabled, "an already equipped gun cannot be drafted into either slot twice")
	_pick(screen, state.available_weapons.find(spare[0]))
	await _click(screen._replace_buttons[1])
	lab.check(state.primary.source == active and state.secondary_primary_source == spare[0] and state.primary.rank(id) == rank + 1 and Profile.currency(&"gold") == paid_gold, "replacing slot B is free, keeps the gun in hand and its purchased modification")
	_pick(screen, state.available_weapons.find(spare[1]))
	await _click(screen._replace_buttons[0])
	lab.check(state.primary.source == spare[1] and state.secondary_primary_source == spare[0] and state.primary.rank(id) == rank + 1 and Profile.currency(&"gold") == paid_gold, "replacing slot A is free and keeps both the partner and the shared purchased rank")
	lab.check(not state.equip_pair(spare[0], spare[0]) and not state.equip_pair(spare[1], null) and state.primary.source == spare[1] and state.secondary_primary_source == spare[0], "invalid pairs are refused atomically without touching either slot")
	await lab.capture("swapped_pair")

	for slot in range(5):
		var cost := shop.ability_cost(slot)
		var before := Profile.currency(&"gold")
		screen._abilities[slot].buy.pressed.emit()
		lab.check(game.run_state.ability_rank(slot) == 1 and Profile.currency(&"gold") == before - int(cost[&"gold"]), "ability %d button upgrades its own slot with the displayed mineral price" % (slot + 1))
	await lab.capture("five_skills_upgraded")
	while shop.can_buy_ability(4):
		screen._abilities[4].buy.pressed.emit()
	var capped_gold := Profile.currency(&"gold")
	var capped_crystal := Profile.currency(&"crystal")
	screen._abilities[4].buy.pressed.emit()
	lab.check(game.run_state.ability_rank(4) == RunState.MAX_ABILITY_RANK and Profile.currency(&"gold") == capped_gold and Profile.currency(&"crystal") == capped_crystal, "maxed skill refuses further ranks without charging any mineral")
	await lab.capture("maxed_skill")
	var crystal := Profile.currency(&"crystal")
	lab.check(shop.reroll() and bool(shop.offers[bought].sold) and Profile.currency(&"crystal") < crystal, "paid reroll changes unsold stock without reselling the purchased mod")
	screen._refresh()

	for mod: StringName in RoundShop.CATALOG:
		if not RoundShop.is_weapon_mod(mod) or RoundShop.track(mod) == RoundShop.Track.ELEMENT:
			continue
		while game.run_state.primary.upgrade(mod):
			pass
	for index in RoundShop.MOD_SLOTS:
		var mod := StringName(shop.offers[index].id)
		if not bool(shop.offers[index].sold) and RoundShop.track(mod) != RoundShop.Track.ELEMENT:
			var before := Profile.currency(&"gold")
			screen._offers[index].buy.pressed.emit()
			lab.check(shop.is_maxed(mod) and Profile.currency(&"gold") == before, "capped primary modification refuses purchase without spending")
	screen._refresh()
	await lab.capture("maxed_primary")
	for mineral: StringName in [&"gold", &"crystal", &"shard"]:
		Profile.spend(mineral, Profile.currency(mineral))
	var skill_rank := game.run_state.ability_rank(0)
	screen._abilities[0].buy.pressed.emit()
	lab.check(game.run_state.ability_rank(0) == skill_rank, "insufficient currencies cannot grant a free ability rank")
	for index in shop.offers.size():
		lab.check(not shop.can_buy(index), "empty wallet cannot buy offer %d" % index)
	lab.check(not shop.can_reroll(), "empty wallet cannot reroll")
	await lab.capture("broke")
	screen._unhandled_input(_escape())
	lab.check(screen.visible, "Esc cannot silently skip the arena-clear shop")
	var levels := state.primary.upgrade_levels.duplicate()
	screen._continue.pressed.emit()
	await lab.wait(0.5)
	lab.check(game.run_state == state and state.primary.source == spare[1] and state.secondary_primary_source == spare[0] and state.primary.upgrade_levels == levels and game.player.weapon == state.primary.definition, "the next sector keeps both shop-picked guns and every shared rank on the live player")
	game.player.quick_swap()
	lab.check(state.primary.source == spare[0] and state.secondary_primary_source == spare[1] and state.primary.upgrade_levels == levels, "the carried partner is one quick toggle away with the same ranks")

func _pick(screen: RoundShopScreen, index: int) -> void:
	screen._selector.select(index)
	screen._selector.item_selected.emit(index)

func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await lab.frames(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.global_position = at
	click.pressed = true
	Input.parse_input_event(click)
	await lab.frames(1)
	click = click.duplicate() as InputEventMouseButton
	click.pressed = false
	Input.parse_input_event(click)
	await lab.frames(2)

func _escape() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

## The draft layer only picks: it previews both guns at the shared ranks, never
## holds a duplicate, and cancelling or confirming never equips by itself.
func _draft(game: ArenaGame) -> void:
	var state := game.run_state
	var active := state.primary.source
	var partner := state.secondary_primary_source
	lab.check(partner != null and partner != active and state.available_weapons.has(partner), "the run starts with two distinct available drafted guns")
	state.primary.upgrade(&"damage")
	game.player.refresh_weapon()
	var damage_rank := state.primary.rank(&"damage")
	var draft := WeaponDraftScreen.new()
	game.add_child(draft)
	var picked: Array = []
	var cancels := [0]
	draft.confirmed.connect(func(first: WeaponDefinition, second: WeaponDefinition): picked.assign([first, second]))
	draft.cancelled.connect(func(): cancels[0] += 1)
	draft.open(state, false)
	await lab.wait(0.4)
	await lab.capture("draft_start")
	var view := draft._grid.get_viewport_rect()
	var controls: Array[Control] = [draft.slot_buttons[0], draft.slot_buttons[1], draft.confirm_button]
	controls.append_array(draft.source_buttons)
	var fits := true
	for index in controls.size():
		var rect := controls[index].get_global_rect()
		fits = fits and view.encloses(rect) and rect.size.x > 0.0
		for other in range(index + 1, controls.size()):
			fits = fits and not rect.intersects(controls[other].get_global_rect())
	lab.check(fits and draft.source_buttons.size() == state.available_weapons.size(), "every drafted gun, both slots and confirm fit 960×600 without overlapping")
	var first_cell: Label = draft._cells[0][0]
	var second_cell: Label = draft._cells[0][1]
	lab.check(damage_rank > 0 and first_cell.text == str(state.primary.definition.damage) and second_cell.text == str(roundi(draft.pending_second.damage * (1.0 + damage_rank * 0.2))), "both draft slots compare effective damage at the run's shared rank")
	draft._input(_key(KEY_ESCAPE))
	lab.check(draft.visible and cancels[0] == 0, "the starting draft cannot be skipped with Esc")
	var held := draft.pending_first
	draft.select_slot(1)
	await _click(draft.source_buttons[state.available_weapons.find(held)])
	lab.check(draft.pending_second == held and draft.pending_first != held and draft.pending_first != null, "picking the other slot's gun swaps slots instead of duplicating it")
	lab.check(not draft.select_pair(held, held) and not draft.select_pair(held, null) and draft.pending_second == held, "duplicate or missing pairs are refused and leave the selection intact")
	await _click(draft.confirm_button)
	lab.check(picked.size() == 2 and picked[0] != picked[1] and not draft.visible and state.primary.source == active and state.secondary_primary_source == partner, "confirming emits the distinct pair without equipping it behind the consumer")
	draft.open(state, true)
	await lab.wait(0.4)
	draft.select_slot(0)
	var spare := active
	for source in state.available_weapons:
		if source != active and source != partner:
			spare = source
	await _click(draft.source_buttons[state.available_weapons.find(spare)])
	lab.check(draft.pending_first == spare and draft.pending_second == partner, "a break replacement edits only the chosen slot")
	await _click(draft.cancel_button)
	lab.check(cancels[0] == 1 and picked.size() == 2 and state.primary.source == active and state.secondary_primary_source == partner and state.primary.rank(&"damage") == damage_rank, "cancelling a break replacement keeps both equipped guns and the shared rank")
	draft.queue_free()

func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key
