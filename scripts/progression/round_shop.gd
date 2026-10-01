class_name RoundShop
extends RefCounted

## Stage-clear stock, paid from banked minerals. All effects live in RunState.
const HAND_ITEMS := [&"projectiles", &"splash", &"fire", &"frost", &"shock", &"damage", &"cadence", &"pierce"]
const ITEM_TEXT := {
	&"projectiles": ["Projectile Splitter", "+2 projectiles on the selected hand (up to 32)."],
	&"splash": ["Blast Chamber", "+1.1 m splash radius on the selected hand (up to 8 m)."],
	&"fire": ["Cinder Conversion", "Selected hand ignites targets with fire damage."],
	&"frost": ["Cryo Conversion", "Selected hand slows targets with frost damage."],
	&"shock": ["Arc Conversion", "Selected hand chains shock damage to nearby targets."],
	&"damage": ["Hardened Rounds", "+20% base damage on the selected hand (5 ranks)."],
	&"cadence": ["Accelerated Feed", "+15% base firing speed on the selected hand (5 ranks)."],
	&"pierce": ["Penetrator", "+1 pierced enemy on the selected hand (4 ranks)."],
	&"armor": ["Field Plating", "+1 armor for the rest of this run (5 purchases)."],
	&"health": ["Reinforced Suit", "+15 maximum health for the rest of this run (5 purchases)."],
	&"power": ["Combat Calibration", "+10% global damage for the rest of this run (5 purchases)."],
}

var offers: Array[Dictionary] = []
var _state: RunState
var _stage := 0
var _rerolls := 0
var _rng := RandomNumberGenerator.new()

func setup(state: RunState, stage: int, seed: int) -> void:
	_state = state
	_stage = maxi(stage, 0)
	_rerolls = 0
	_rng.seed = seed ^ ((_stage + 1) * 104729)
	_roll_stock()

func can_buy(index: int, hand: int) -> bool:
	if _state == null or index < 0 or index >= offers.size() or hand < 0 or hand >= _state.hands.size():
		return false
	var offer := offers[index]
	if bool(offer.sold) or not _effect_available(StringName(offer.id), hand):
		return false
	return Profile.can_pay(offer.cost)

func buy(index: int, hand: int) -> bool:
	if not can_buy(index, hand):
		return false
	var offer := offers[index]
	var id := StringName(offer.id)
	# Neither effective-hand updates nor run-stat updates emit signals, so the
	# validated balance cannot change before pay; paid observers see sold stock.
	var applied := _state.hands[hand].upgrade(id) if id in HAND_ITEMS else _state.buy_shop_stat(id)
	if not applied:
		return false
	offer.sold = true
	return Profile.pay(offer.cost)

func reroll_cost() -> Dictionary:
	return {&"gold": 3 + _rerolls * 3, &"crystal": 1 + _rerolls}

func can_reroll() -> bool:
	if _state == null or not Profile.can_pay(reroll_cost()):
		return false
	for id in ITEM_TEXT:
		if _available_for_any_hand(id):
			return true
	return false

func reroll() -> bool:
	if not can_reroll():
		return false
	if not Profile.pay(reroll_cost()):
		return false
	_rerolls += 1
	_roll_stock()
	return true

func _effect_available(id: StringName, hand: int) -> bool:
	if id in HAND_ITEMS:
		return _state.hands[hand].can_upgrade(id)
	return _state.can_buy_shop_stat(id)

func _available_for_any_hand(id: StringName) -> bool:
	if _state == null:
		return false
	for hand in _state.hands.size():
		if _effect_available(id, hand):
			return true
	return false

func _roll_stock() -> void:
	offers.clear()
	var candidates: Array[StringName] = []
	var exhausted: Array[StringName] = []
	for id: StringName in ITEM_TEXT:
		if _available_for_any_hand(id):
			candidates.append(id)
		else:
			exhausted.append(id)
	# Always show four distinct cards; exhausted stock is only included when
	# fewer than four effects remain, and can_buy prevents charging for it.
	while offers.size() < 4:
		var source := candidates if not candidates.is_empty() else exhausted
		var index := _rng.randi_range(0, source.size() - 1)
		var id: StringName = source[index]
		source.remove_at(index)
		var text: Array = ITEM_TEXT[id]
		offers.append({"id": id, "name": text[0], "description": text[1], "cost": _item_cost(id), "sold": false})

func _item_cost(id: StringName) -> Dictionary:
	var gold := 6 + mini(_stage, 5) * 2
	match id:
		&"projectiles", &"splash":
			return {&"gold": gold, &"crystal": 5}
		&"fire":
			return {&"gold": gold - 2, &"crystal": 7}
		&"frost", &"shock":
			return {&"gold": gold - 2, &"crystal": 3, &"shard": 1}
		&"pierce":
			return {&"gold": gold, &"shard": 1}
		&"armor":
			return {&"gold": gold, &"crystal": 3}
		&"health":
			return {&"gold": gold - 1, &"crystal": 2}
	return {&"gold": gold, &"crystal": 2}
