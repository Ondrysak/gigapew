class_name ShopVenueCatalog
extends Resource

## Every venue, loaded by id. `order_for` is the single deterministic venue
## order of a sector and seed: the world lines storefronts up in this order and
## the stage-clear shop names the first, so the shop is a venue from the street
## the player just cleared. It has its own RNG and never touches gameplay RNG.

const DEFAULT_PATH := "res://data/venues/catalog.tres"
const ORDER_SALT := 0x56454E55

@export var venues: Array[ShopVenue] = []

static var _default: ShopVenueCatalog

static func shared() -> ShopVenueCatalog:
	if _default == null:
		_default = load(DEFAULT_PATH) as ShopVenueCatalog
	return _default

func find(id: StringName) -> ShopVenue:
	for venue in venues:
		if venue.id == id:
			return venue
	return null

func for_sector(sector: StringName) -> Array[ShopVenue]:
	var found: Array[ShopVenue] = []
	for venue in venues:
		if venue.sectors.has(sector):
			found.append(venue)
	return found

## The sector's venues in a seeded order (Fisher-Yates on a private RNG).
func order_for(sector: StringName, seed_value: int) -> Array[ShopVenue]:
	var order := for_sector(sector)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, ORDER_SALT, String(sector)])
	for index in range(order.size() - 1, 0, -1):
		var pick := rng.randi_range(0, index)
		var swap := order[index]
		order[index] = order[pick]
		order[pick] = swap
	return order

## The venue the stage-clear shop of this sector and level seed is held in.
func shop_venue(sector: StringName, seed_value: int) -> ShopVenue:
	var order := order_for(sector, seed_value)
	return order[0] if not order.is_empty() else null
