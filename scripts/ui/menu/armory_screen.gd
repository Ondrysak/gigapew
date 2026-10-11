extends MenuScreen

## Permanent upgrade shop: one MetaCard per Profile.meta_pool entry.

@export var card_scene: PackedScene
@export var grid: Container
@export var currency_bar: CurrencyBar
@export var status_label: Label

var _cards: Array[MetaCard] = []

func _ready() -> void:
	super()
	for _index in range(Profile.meta_pool.upgrades.size()):
		var card := card_scene.instantiate() as MetaCard
		grid.add_child(card)
		card.purchase_requested.connect(_on_purchase_requested)
		_cards.append(card)
	if not _cards.is_empty():
		default_focus = _cards[0].buy_button
	StreetWear.apply_tree(self)

func refresh() -> void:
	var upgrades := Profile.meta_pool.upgrades
	for index in range(_cards.size()):
		var upgrade := upgrades[index]
		var cost := Profile.next_meta_cost(upgrade)
		var price := "%d %s" % [cost, currency_bar.label_for(upgrade.currency)] if cost >= 0 else ""
		var affordable := cost >= 0 and Profile.currency(upgrade.currency) >= cost
		_cards[index].show_upgrade(upgrade, Profile.meta_level(upgrade), price, affordable)
	if status_label.text.is_empty():
		status_label.text = "Vylepšení platí pro všechny postavy od začátku každého běhu."

func _on_purchase_requested(definition: MetaUpgradeDefinition) -> void:
	var level := Profile.meta_level(definition)
	if Profile.buy_meta(definition):
		status_label.text = "%s: úroveň %d." % [definition.display_name, level + 1]
	else:
		status_label.text = "Chybí platidlo: %s." % currency_bar.label_for(definition.currency)
	refresh()
