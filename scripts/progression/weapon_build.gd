class_name WeaponBuild
extends RefCounted

## A run's primary firearm. Rebuild from an immutable snapshot, never from the
## already upgraded effective resource; swaps retain purchased ranks.
const MAX_PROJECTILES := 32
const MAX_SPLASH := 8.0
const MAX_PIERCE := 12

var definition: WeaponDefinition
var source: WeaponDefinition
var upgrade_levels: Dictionary = {}
var _base: WeaponDefinition

func setup(authored: WeaponDefinition) -> void:
	upgrade_levels.clear()
	swap(authored)

func swap(authored: WeaponDefinition) -> void:
	source = authored
	_base = authored.duplicate(false) as WeaponDefinition if authored != null else null
	definition = _build(upgrade_levels)

func rank(kind: StringName) -> int:
	return int(upgrade_levels.get(kind, 0))

func supports(kind: StringName) -> bool:
	return definition != null and RoundShop.is_weapon_mod(kind)

func can_upgrade(kind: StringName) -> bool:
	if not supports(kind) or rank(kind) >= RoundShop.max_rank(kind):
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
	# Keep the most recently purchased element conversion last.
	var next := rank(kind) + 1
	upgrade_levels.erase(kind)
	upgrade_levels[kind] = next
	definition = _build(upgrade_levels)
	return true

func preview(kind: StringName) -> WeaponDefinition:
	if not can_upgrade(kind):
		return null
	var levels := upgrade_levels.duplicate()
	var next := rank(kind) + 1
	levels.erase(kind)
	levels[kind] = next
	return _build(levels)

func _build(levels: Dictionary) -> WeaponDefinition:
	if _base == null:
		return null
	var result := _base.duplicate(false) as WeaponDefinition
	result.pellet_count = clampi(result.pellet_count, 1, MAX_PROJECTILES)
	for kind: StringName in levels:
		var level := int(levels[kind])
		match kind:
			&"projectiles":
				result.pellet_count = mini(MAX_PROJECTILES, result.pellet_count + 2 * level)
				result.spread_degrees = maxf(result.spread_degrees, 2.0)
			&"splash":
				result.explosion_radius = minf(MAX_SPLASH, result.explosion_radius + 1.1 * level)
				result.explosion_damage_fraction = maxf(result.explosion_damage_fraction, 0.6)
			&"fire":
				result.damage_type = DamageType.Kind.FIRE
			&"frost":
				result.damage_type = DamageType.Kind.FROST
			&"shock":
				result.damage_type = DamageType.Kind.SHOCK
			&"damage":
				result.damage = roundi(_base.damage * (1.0 + level * 0.2))
			&"cadence":
				result.fire_interval = maxf(0.008, _base.fire_interval / (1.0 + level * 0.15))
			&"pierce":
				result.pierce = mini(MAX_PIERCE, result.pierce + level)
	return result
