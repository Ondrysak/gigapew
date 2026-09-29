class_name PerkEffect
extends Node3D

## Base for passive PERK upgrades. AutoWeaponRack instances one per owned PERK
## (under the stage, recreated every stage) and keeps its level in sync.
## Subclasses override _refresh() for level changes and _tick() for per-frame
## work; world visuals are pooled template duplicates placed with top_level.

var player: ArenaPlayer
var horde: Horde
var run_state: RunState
var level := 1

func configure(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState, p_level: int) -> void:
	player = p_player
	horde = p_horde
	run_state = p_run_state
	_setup()
	set_level(p_level)

## Also called after any upgrade so run-wide stats refresh.
func set_level(p_level: int) -> void:
	level = maxi(1, p_level)
	if run_state != null:
		_refresh()

## Value for the current level from a per-level table (clamped to its ends).
func per_level(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(level - 1, 0, values.size() - 1)]

func _physics_process(delta: float) -> void:
	if run_state == null or not is_instance_valid(player) or not is_instance_valid(horde) or not player.active:
		return
	_tick(delta)

## One-time wiring after player/horde/run_state are known (connect signals).
func _setup() -> void:
	pass

## Re-read level-dependent values.
func _refresh() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

## Duplicates a hidden scene template into world-space pooled instances.
func grow_pool(template: Node3D, pool: Array[Node3D], size: int) -> void:
	if template == null:
		return
	template.hide()
	while pool.size() < size:
		var node := template.duplicate() as Node3D
		add_child(node)
		node.top_level = true
		node.hide()
		pool.append(node)
