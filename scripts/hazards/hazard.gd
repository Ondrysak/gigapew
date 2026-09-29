@tool
class_name Hazard
extends Node3D

## Base for stage hazards and interactables placed under a world's Hazards
## node. Decoration only (no processing) until setup(): gameplay then ticks in
## _tick from _physics_process while the player is active, and visuals animate
## in _animate from _process.

## Flashes that would reach within this distance of the camera are skipped
## (damage still applies) so point-blank effects never white out the view.
@export var min_view_clearance := 1.0
@export var sound_bus: StringName = &"SFX"

var horde: Horde
var player: ArenaPlayer
var run_state: RunState

var _hits := PackedInt32Array()
var _can_interact := false

func _ready() -> void:
	set_physics_process(false)
	set_process(false)
	if not Engine.is_editor_hint():
		add_to_group(&"hazard")

## Arms the hazard for a stage run.
func setup(p_horde: Horde, p_player: ArenaPlayer, p_run_state: RunState) -> void:
	if Engine.is_editor_hint():
		return
	horde = p_horde
	player = p_player
	run_state = p_run_state
	_can_interact = InputMap.has_action(&"interact")
	if _hits.size() < 256:
		_hits.resize(256)
	_on_setup()
	set_physics_process(true)
	set_process(true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(horde) or not player.active:
		return
	_tick(delta)

func _process(delta: float) -> void:
	_animate(delta)

## Build pools and voices; called once from setup().
func _on_setup() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

func _animate(_delta: float) -> void:
	pass

func is_set_up() -> bool:
	return is_instance_valid(horde) and is_instance_valid(player)

## True when the player stands within `reach` (XZ) of `point` and faces it.
func player_can_reach(point: Vector3, reach: float, facing_dot: float) -> bool:
	var offset := point - player.global_position
	offset.y = 0.0
	var distance_squared := offset.length_squared()
	if distance_squared > reach * reach:
		return false
	if distance_squared < 0.01:
		return true
	var forward := -player.global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(offset / sqrt(distance_squared)) > facing_dot

## True on the physics frame the interact key went down.
func interact_pressed() -> bool:
	return _can_interact and Input.is_action_just_pressed(&"interact")

## True when a flash of `radius` at `at` would engulf the camera.
func crowds_view(at: Vector3, radius: float) -> bool:
	return player.camera.global_position.distance_to(at) < radius + min_view_clearance

## Damages enemies within `radius` of `center`: `amount` at the centre down to
## `amount * edge_fraction` at the edge, pushed outward by up to `knockback`.
func blast_horde(center: Vector3, radius: float, amount: float, edge_fraction: float, knockback: float) -> int:
	var found := horde.query_radius(center, radius, _hits)
	var c := Vector2(center.x, center.z)
	for n in found:
		var slot := _hits[n]
		var at := horde.enemy_position(slot)
		var away := Vector2(at.x, at.z) - c
		var distance := away.length()
		var falloff := clampf(distance / radius, 0.0, 1.0)
		var push := Vector3.ZERO
		if distance > 0.001:
			away *= knockback * (1.0 - falloff * 0.5) / distance
			push = Vector3(away.x, 0.0, away.y)
		horde.damage(slot, amount * lerpf(1.0, edge_fraction, falloff), push)
	return found

## Hurts the player inside `radius` with the same linear falloff and shakes
## the camera by distance. Armor applies through take_damage.
func blast_player(center: Vector3, radius: float, amount: float, edge_fraction: float, shake: float) -> void:
	var distance := player.global_position.distance_to(center)
	if shake > 0.0:
		player.add_shake(shake * clampf(1.0 - distance / (radius * 4.0), 0.0, 1.0))
	if amount <= 0.0 or distance > radius:
		return
	var falloff := clampf(distance / radius, 0.0, 1.0)
	player.take_damage(roundi(amount * lerpf(1.0, edge_fraction, falloff)))

## Child 3D voice on sound_bus: `stream` when set, else the HazardSynth cue.
func make_voice(stream: AudioStream, cue: StringName, volume_db: float, polyphony := 2) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream if stream != null else HazardSynth.make(cue)
	voice.volume_db = volume_db
	voice.max_polyphony = polyphony
	voice.unit_size = 10.0
	voice.max_distance = 80.0
	voice.bus = sound_bus
	add_child(voice)
	return voice
