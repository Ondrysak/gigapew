class_name AutoWeaponRack
extends Node3D

## Owns one AutoWeapon per owned WEAPON upgrade and one PerkEffect per owned
## PERK upgrade, keeping levels and overclocks in sync. Perks never use one of
## the RunState.MAX_WEAPONS slots.

var _player: ArenaPlayer
var _horde: Horde
var _run_state: RunState
var _weapons: Dictionary = {}
var _perks: Dictionary = {}

func setup(player: ArenaPlayer, horde: Horde, run_state: RunState) -> void:
	_player = player
	_horde = horde
	_run_state = run_state

func sync() -> void:
	for upgrade in _run_state.owned_weapons:
		if upgrade.weapon_scene == null:
			continue
		var level := _run_state.level_of(upgrade)
		var weapon := _weapons.get(upgrade.id) as AutoWeapon
		if weapon == null:
			weapon = upgrade.weapon_scene.instantiate() as AutoWeapon
			add_child(weapon)
			_weapons[upgrade.id] = weapon
			weapon.overclocked = _run_state.is_overclocked(upgrade)
			weapon.configure(_player, _horde, _run_state, level)
		else:
			weapon.overclocked = _run_state.is_overclocked(upgrade)
			weapon.set_level(level)
	for upgrade in _run_state.owned_perks:
		if upgrade.perk_scene == null:
			continue
		var level := _run_state.level_of(upgrade)
		var perk := _perks.get(upgrade.id) as PerkEffect
		if perk == null:
			var node := upgrade.perk_scene.instantiate()
			perk = node as PerkEffect
			if perk == null:
				push_error("perk_scene of %s must be a PerkEffect" % upgrade.id)
				node.free()
				continue
			add_child(perk)
			_perks[upgrade.id] = perk
			perk.configure(_player, _horde, _run_state, level)
		else:
			perk.set_level(level)
