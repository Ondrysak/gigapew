extends LabScenario

func title() -> String:
	return "Primary and ability shop"

func summary() -> String:
	return "Weapon swap/mods, independent paid skills, capped ranks, insufficient currency and readable layout"

func run() -> void:
	var game := await lab.start_game(&"driller")
	Profile.add_currency(&"gold", 240)
	Profile.add_currency(&"crystal", 100)
	Profile.add_currency(&"shard", 12)
	# The quests scenario separately exercises actual contract extraction.
	game._finish_stage_clear()
	await lab.wait(0.5)
	var screen := game.round_shop
	var shop := screen._shop
	await lab.capture("open")
	var rows: Control = screen.get_child(1).get_child(0)
	lab.check(rows.get_combined_minimum_size().y <= rows.size.y + 0.5, "shop's primary, five skills and stock fit the viewport without vertical clipping")

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
	screen._offers[bought].buy.pressed.emit()
	lab.check(bool(shop.offers[bought].sold) and shop.rank(id) == rank + 1 and Profile.currency(&"gold") < gold, "a real mod button installs one primary rank, charges minerals and sells its stock")
	var paid_gold := Profile.currency(&"gold")
	screen._offers[bought].buy.pressed.emit()
	lab.check(shop.rank(id) == rank + 1 and Profile.currency(&"gold") == paid_gold, "a repeated sold-card action cannot install or charge twice")
	var rail_index := game.run_state.available_weapons.find(lab.weapon("rail"))
	screen._selector.select(rail_index)
	screen._selector.item_selected.emit(rail_index)
	screen._swap.pressed.emit()
	lab.check(game.run_state.primary.source == lab.weapon("rail") and game.run_state.primary.rank(id) == rank + 1 and Profile.currency(&"gold") == paid_gold, "shop swaps the single primary free without losing its purchased modification")
	await lab.capture("swapped_primary")

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
	lab.check(screen.visible, "Esc cannot silently skip the extraction shop")

func _escape() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event
