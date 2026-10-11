class_name GearCatalog
extends RefCounted

const STARTERS: Array[StringName] = [&"mirror", &"trainers", &"gloves"]
static var _items: Array[GearDefinition] = []

static func all() -> Array[GearDefinition]:
	if _items.is_empty():
		for path in ["mirror", "trainers", "wire", "gloves", "lighter", "glass"]:
			_items.append(load("res://data/gear/%s.tres" % path) as GearDefinition)
	return _items

static func find(id: StringName) -> GearDefinition:
	for item in all():
		if item.id == id:
			return item
	return null

## Uniform sampling without replacement; only the caller's RNG is consumed.
static func roll(rng: RandomNumberGenerator, count: int, owned: Array[GearDefinition], include_locked: bool = true) -> Array[GearDefinition]:
	var offers: Array[GearDefinition] = []
	var remaining: Array[GearDefinition] = []
	for item in all():
		if not include_locked and not STARTERS.has(item.id) and not Profile.has_discovered_gear(item.id):
			continue
		var equipped := false
		for existing in owned:
			if existing != null and existing.id == item.id:
				equipped = true
				break
		if not equipped:
			remaining.append(item)
	while offers.size() < count and not remaining.is_empty():
		var index := rng.randi_range(0, remaining.size() - 1)
		offers.append(remaining[index])
		remaining.remove_at(index)
	return offers
