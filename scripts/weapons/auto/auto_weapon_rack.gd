class_name AutoWeaponRack
extends Node3D

## Owns one AutoWeapon per owned WEAPON upgrade and keeps levels and
## overclocks in sync.

var _player: ArenaPlayer
var _horde: Horde
var _run_state: RunState
var _weapons: Dictionary = {}

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
