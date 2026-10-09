class_name WeaponHand
extends RefCounted

## Effective per-hand resource; authored weapons and sibling hands stay unchanged.
## Weapon-mod names, tracks and rank caps live in RoundShop.CATALOG; this class
## applies their effects.
const MAX_PROJECTILES := 32
const MAX_SPLASH := 8.0
const MAX_PIERCE := 12

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

func rank(kind: StringName) -> int:
	return int(upgrade_levels.get(kind, 0))

## Compatibility is independent of rank: an unsupported mod is never "maxed".
func supports(kind: StringName) -> bool:
	if definition == null or not RoundShop.is_hand_mod(kind):
		return false
	return definition.kind != WeaponDefinition.Kind.MELEE or kind not in [&"projectiles", &"pierce"]

func can_upgrade(kind: StringName) -> bool:
	if not supports(kind):
		return false
	if rank(kind) >= RoundShop.max_rank(kind):
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
	var next := rank(kind) + 1
	upgrade_levels[kind] = next
	_apply(definition, kind, next)
	return true

## A copy of this hand's weapon with one more rank of `kind`; null when capped.
func preview(kind: StringName) -> WeaponDefinition:
	if not can_upgrade(kind):
		return null
	var copy := definition.duplicate(false) as WeaponDefinition
	_apply(copy, kind, rank(kind) + 1)
	return copy

func _apply(target: WeaponDefinition, kind: StringName, level: int) -> void:
	match kind:
		&"projectiles":
			target.pellet_count = mini(MAX_PROJECTILES, target.pellet_count + 2)
			target.spread_degrees = maxf(target.spread_degrees, 2.0)
		&"splash":
			target.explosion_radius = minf(MAX_SPLASH, target.explosion_radius + 1.1)
			target.explosion_damage_fraction = maxf(target.explosion_damage_fraction, 0.6)
		&"fire":
			target.damage_type = DamageType.Kind.FIRE
		&"frost":
			target.damage_type = DamageType.Kind.FROST
		&"shock":
			target.damage_type = DamageType.Kind.SHOCK
		&"damage":
			target.damage = roundi(_base_damage * (1.0 + level * 0.2))
		&"cadence":
			target.fire_interval = maxf(0.008, _base_interval / (1.0 + level * 0.15))
		&"pierce":
			target.pierce = mini(MAX_PIERCE, target.pierce + 1)
