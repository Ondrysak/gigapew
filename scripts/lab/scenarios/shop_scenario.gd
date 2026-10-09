extends LabScenario

func title() -> String:
	return "Shop"

func summary() -> String:
	return "Round mineral shop after a boss: stock, hand selection, purchase, maxed ranks, empty wallet"

func run() -> void:
	var game := await lab.start_game(&"driller")
	Profile.add_currency(&"gold", 140)
	Profile.add_currency(&"crystal", 60)
	Profile.add_currency(&"shard", 6)
	game._on_boss_killed()
	await lab.wait(0.5)
	var screen := game.round_shop
	var shop := screen._shop
	lab.check(screen.visible, "boss clear opens the shop")
	var mods := 0
	var suits := 0
	for offer in shop.offers:
		if int(offer.section) == RoundShop.Section.MODS and RoundShop.is_hand_mod(offer.id):
			mods += 1
		elif int(offer.section) == RoundShop.Section.SUIT and not RoundShop.is_hand_mod(offer.id):
			suits += 1
	lab.check(mods == RoundShop.MOD_SLOTS and suits == RoundShop.SUIT_SLOTS, "stock rolls %d weapon mods and %d suit systems (%d / %d)" % [RoundShop.MOD_SLOTS, RoundShop.SUIT_SLOTS, mods, suits])
	await lab.capture("open")
	var rows: Control = screen.get_child(1).get_child(0)
	var needed := rows.get_combined_minimum_size().y
	lab.check(needed <= rows.size.y + 0.5, "layout fits the screen without clipping (needs %d of %d px)" % [needed, rows.size.y])
	screen._select_hand(2)
	await lab.wait(0.2)
	await lab.capture("hand_3")
	var gold := Profile.currency(&"gold")
	var bought := -1
	for index in shop.offers.size():
		if shop.section_of(index) == RoundShop.Section.MODS and shop.can_buy(index, 2):
			bought = index
			break
	lab.check(bought >= 0, "a full wallet can afford some stock")
	if bought >= 0:
		var id := StringName(shop.offers[bought].id)
		var rank := shop.rank(id, 2)
		screen._on_buy(bought)
		await lab.wait(0.2)
		lab.check(bool(shop.offers[bought].sold), "purchased card is marked sold")
		lab.check(Profile.currency(&"gold") < gold, "purchase debited gold (%d -> %d)" % [gold, Profile.currency(&"gold")])
		lab.check(shop.rank(id, 2) == rank + 1, "%s rank on hand 3 rose to %d" % [id, shop.rank(id, 2)])
		var crystal := Profile.currency(&"crystal")
		lab.check(shop.reroll() and bool(shop.offers[bought].sold) and Profile.currency(&"crystal") < crystal, "reroll is paid and keeps the sold card")
		screen._refresh()
		await lab.wait(0.2)
		await lab.capture("bought")
	# Push hand 1 to (near) its caps: offered mods hit the cap, the rest stop one short.
	var hand := game.run_state.hands[0]
	var offered: Array[StringName] = []
	for index in RoundShop.MOD_SLOTS:
		offered.append(StringName(shop.offers[index].id))
	for id: StringName in RoundShop.CATALOG:
		if not RoundShop.is_hand_mod(id) or RoundShop.track(id) == RoundShop.Track.ELEMENT:
			continue
		var target := RoundShop.max_rank(id) - (0 if id in offered else 1)
		while hand.rank(id) < target and hand.upgrade(id):
			pass
	screen._select_hand(0)
	await lab.wait(0.2)
	var before := Profile.currency(&"gold")
	var capped := -1
	for index in RoundShop.MOD_SLOTS:
		var id := StringName(shop.offers[index].id)
		if not bool(shop.offers[index].sold) and RoundShop.track(id) != RoundShop.Track.ELEMENT:
			capped = index
			lab.check(shop.is_maxed(id, 0) and not shop.can_buy(index, 0), "%s is maxed on hand 1 and cannot be bought" % id)
	if capped >= 0:
		screen._on_buy(capped)
		lab.check(Profile.currency(&"gold") == before, "refused maxed purchase charges nothing")
	await lab.wait(0.2)
	await lab.capture("maxed")
	screen._select_hand(2)
	for id: StringName in [&"gold", &"crystal", &"shard"]:
		Profile.spend(id, Profile.currency(id))
	await lab.wait(0.2)
	await lab.capture("broke")
	for index in shop.offers.size():
		lab.check(not shop.can_buy(index, 2), "empty wallet cannot buy offer %d" % index)
	lab.check(not shop.can_reroll(), "empty wallet cannot reroll")
	screen._unhandled_input(_escape())
	lab.check(screen.visible, "Esc does not skip the shop")

func _escape() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event
