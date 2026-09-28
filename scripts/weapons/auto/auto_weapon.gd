class_name AutoWeapon
extends Node3D

## Base for self-firing upgrade weapons. Lives under the stage (not the
## player); visuals are pooled duplicates of scene templates placed with
## top_level so they are positioned in world space.

@export var base_damage := 10.0
## Fractional damage gain per level above 1.
@export var damage_per_level := 0.25
@export var base_cooldown := 1.0
## Fractional cooldown reduction per level above 1.
@export var cooldown_per_level := 0.07
@export var min_cooldown := 0.1
## CombatAudio cue played by play_cue() (empty = silent).
@export var cue: StringName = &""
## Minimum seconds between two plays of `cue`.
@export var cue_interval := 0.25
## Flashes that would reach within this distance of the camera are skipped
## (damage still applies) so point-blank effects never white out the view.
@export var min_view_clearance := 1.0

var player: ArenaPlayer
var horde: Horde
var run_state: RunState
var level := 1
## Set by AutoWeaponRack once this weapon's OVERCLOCK upgrade is owned.
var overclocked := false

var _cue_ready_msec := 0

func configure(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState, p_level: int) -> void:
	player = p_player
	horde = p_horde
	run_state = p_run_state
	set_level(p_level)

## Also called after any upgrade so run-wide stats (projectiles, area) refresh.
func set_level(p_level: int) -> void:
	level = maxi(1, p_level)
	if run_state != null:
		_refresh()

func damage_amount() -> float:
	return base_damage * (1.0 + damage_per_level * (level - 1)) * run_state.damage_multiplier

func cooldown_time() -> float:
	var scale_by_level := maxf(0.2, 1.0 - cooldown_per_level * (level - 1))
	return maxf(min_cooldown, base_cooldown * scale_by_level * run_state.cooldown_multiplier * run_state.cooldown_boost)

func area_scale() -> float:
	return run_state.area_multiplier

func extra_projectiles() -> int:
	return run_state.projectile_bonus

## Plays `cue`, rate-limited by `cue_interval`.
func play_cue() -> void:
	if cue.is_empty() or not is_instance_valid(player) or player.sound == null:
		return
	var now := Time.get_ticks_msec()
	if now < _cue_ready_msec:
		return
	_cue_ready_msec = now + int(cue_interval * 1000.0)
	player.sound.play_cue(cue)

## True when a flash of `radius` at `at` would engulf the camera.
func crowds_view(at: Vector3, radius: float) -> bool:
	return player.camera.global_position.distance_to(at) < radius + min_view_clearance

## Base count plus one per reached unlock level plus the run's projectile bonus.
func scaled_count(base: int, unlock_levels: PackedInt32Array, maximum: int) -> int:
	var count := base + extra_projectiles()
	for unlock in unlock_levels:
		if level >= unlock:
			count += 1
	return clampi(count, 1, maximum)

func _physics_process(delta: float) -> void:
	if run_state == null or not is_instance_valid(player) or not is_instance_valid(horde) or not player.active:
		return
	_tick(delta)

## Rebuild pools/counts for the current level, run stats and overclock.
func _refresh() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

## Duplicates a hidden scene template into world-space pooled instances.
func _grow_pool(template: Node3D, pool: Array[Node3D], size: int) -> void:
	while pool.size() < size:
		var node := template.duplicate() as Node3D
		add_child(node)
		node.top_level = true
		node.hide()
		pool.append(node)

## Places a template authored as a unit-length beam along -Z between points.
static func place_beam(beam: Node3D, from: Vector3, to: Vector3, width_scale := 1.0) -> void:
	var offset := to - from
	var length := offset.length()
	if length < 0.001 or width_scale <= 0.0:
		beam.hide()
		return
	var direction := offset / length
	var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	var frame := Basis.looking_at(direction, up)
	beam.global_transform = Transform3D(Basis(frame.x * width_scale, frame.y * width_scale, frame.z * length), (from + to) * 0.5)
	beam.show()
