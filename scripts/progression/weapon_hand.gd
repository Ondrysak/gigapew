class_name WeaponHand
extends RefCounted

## Effective per-hand resource; authored weapons and sibling hands stay unchanged.
const MAX_PROJECTILES := 32
const MAX_SPLASH := 8.0
const MAX_PIERCE := 12
const CAPS := {
	&"projectiles": 6, &"splash": 4, &"fire": 1, &"frost": 1,
	&"shock": 1, &"damage": 5, &"cadence": 5, &"pierce": 4,
}

var definition: WeaponDefinition
var upgrade_levels: Dictionary = {}
var _base_damage := 0
var _base_interval := 0.0

func setup(source: WeaponDefinition) -> void:
	upgrade_levels.clear()
	definition = source.duplicate(false) as WeaponDefinition if source != null else null
	if definition != null:
		definition.pellet_count = clampi(definition.pellet_count, 1, MAX_PROJECTILES)
		_base_damage = definition.damage
		_base_interval = definition.fire_interval

func can_upgrade(kind: StringName) -> bool:
	if definition == null or not CAPS.has(kind):
		return false
	if int(upgrade_levels.get(kind, 0)) >= int(CAPS[kind]):
		return false
	match kind:
		&"projectiles":
			return definition.pellet_count < MAX_PROJECTILES
		&"splash":
			return definition.explosion_radius < MAX_SPLASH
		&"pierce":
			return definition.pierce < MAX_PIERCE
		&"fire":
			return definition.damage_type != DamageType.Kind.FIRE
		&"frost":
			return definition.damage_type != DamageType.Kind.FROST
		&"shock":
			return definition.damage_type != DamageType.Kind.SHOCK
	return true

func upgrade(kind: StringName) -> bool:
	if not can_upgrade(kind):
		return false
	var rank := int(upgrade_levels.get(kind, 0)) + 1
	upgrade_levels[kind] = rank
	match kind:
		&"projectiles":
			definition.pellet_count = mini(MAX_PROJECTILES, definition.pellet_count + 2)
			definition.spread_degrees = maxf(definition.spread_degrees, 2.0)
		&"splash":
			definition.explosion_radius = minf(MAX_SPLASH, definition.explosion_radius + 1.1)
			definition.explosion_damage_fraction = maxf(definition.explosion_damage_fraction, 0.6)
		&"fire":
			definition.damage_type = DamageType.Kind.FIRE
		&"frost":
			definition.damage_type = DamageType.Kind.FROST
		&"shock":
			definition.damage_type = DamageType.Kind.SHOCK
		&"damage":
			definition.damage = roundi(_base_damage * (1.0 + rank * 0.2))
		&"cadence":
			definition.fire_interval = maxf(0.025, _base_interval / (1.0 + rank * 0.15))
		&"pierce":
			definition.pierce = mini(MAX_PIERCE, definition.pierce + 1)
	return true
