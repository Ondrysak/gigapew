class_name MiningTool
extends Node3D

## Páčidlo: one fresh F press opens one visible, reachable compartment.
const FeedbackController := preload("res://scripts/mining/mining_feedback.gd")

## Node moved between the stowed and raised poses.
@export var model: Node3D
## Offset from the authored pose when not in use.
@export var stowed_offset := Vector3(-0.05, -0.38, 0.18)
@export var raise_speed := 7.0

@export_group("Mining")
@export var reach := 2.6

@export_group("Effects")
@export var spark_mesh: Mesh
## Should use vertex color as albedo.
@export var spark_material: Material
@export var rock_spark_color := Color(1.0, 0.72, 0.3)
@export var rock_sound: AudioStream
@export var sound_bus: StringName = &"SFX"

## Public salvage state for HUD integrations and targeted smoke checks.
var target_deposit: MineralDeposit
var target_fragment := -1
var feedback: MiningFeedback

var _player: ArenaPlayer
var _query: PhysicsRayQueryParameters3D
var _using := false
var _mine_held := false
var _press_blocked := false
var _swing_remaining := 0.0
var _raise := 0.0
var _kick := 0.0
var _contact := 0.0
var _rest := Vector3.ZERO
var _rest_rotation := Vector3.ZERO
var _sparks: Array[CPUParticles3D] = []
var _next_spark := 0
var _impact_voice: AudioStreamPlayer
var _rock_stream: AudioStream
var _break_stream: AudioStream

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if model != null:
		_rest = model.position
		_rest_rotation = model.rotation
		model.visible = false
	for _index in 3:
		var emitter := CPUParticles3D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.amount = 10
		emitter.lifetime = 0.3
		emitter.explosiveness = 1.0
		emitter.local_coords = false
		emitter.mesh = spark_mesh
		emitter.material_override = spark_material
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.direction = Vector3(0.0, 0.0, 1.0)
		emitter.spread = 65.0
		emitter.initial_velocity_min = 2.0
		emitter.initial_velocity_max = 5.5
		emitter.gravity = Vector3(0.0, -12.0, 0.0)
		emitter.scale_amount_min = 0.5
		emitter.scale_amount_max = 1.0
		add_child(emitter)
		emitter.top_level = true
		_sparks.append(emitter)
	_rock_stream = rock_sound if rock_sound != null else MiningSynth.cue(&"clank")
	_break_stream = MiningSynth.cue(&"section")
	_impact_voice = AudioStreamPlayer.new()
	_impact_voice.volume_db = -13.0
	_impact_voice.max_polyphony = 3
	_impact_voice.bus = sound_bus
	add_child(_impact_voice)
	feedback = FeedbackController.new()
	add_child(feedback)

## Call after the tool is a child of the player's camera.
func setup(player: ArenaPlayer, _run_state: RunState) -> void:
	_player = player
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [player.get_rid()])
	feedback.setup(player)
	_player.mining_tool = self

## The first physics surface must be a live machine compartment within reach.
func has_target() -> bool:
	if not _enabled() or _query == null or _player.is_finishing() or _player.finisher_ready():
		return false
	var hit := _target_hit()
	if hit.is_empty() or not hit["collider"] is MineralDeposit:
		return false
	return not (hit["collider"] as MineralDeposit).feedback_at(hit["position"], int(hit["shape"])).is_empty()

func _enabled() -> bool:
	return _player != null and is_instance_valid(_player) and _player.active \
			and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _target_hit() -> Dictionary:
	_query.from = _player.camera.global_position
	_query.to = _query.from - _player.head.global_basis.z * reach
	return get_world_3d().direct_space_state.intersect_ray(_query)

func cancel() -> void:
	_using = false
	_swing_remaining = 0.0
	_mine_held = Input.is_action_pressed(&"mine")
	_press_blocked = _mine_held
	_contact = 0.0
	_clear_target()
	if _impact_voice != null:
		_impact_voice.stop()
	if feedback != null:
		feedback.reset()

func is_smashing() -> bool:
	return _using

## One cached ownership decision for both viewmodels, including swing recovery
## after the struck compartment disappears. Target physics refreshes each tick.
func is_presented() -> bool:
	return _enabled() and not _player.is_finishing() and not _player.finisher_ready() \
			and (_using or (is_instance_valid(target_deposit) and target_fragment >= 0))

func _physics_process(delta: float) -> void:
	var held := Input.is_action_pressed(&"mine")
	var fresh_press := held and not _mine_held and not _press_blocked
	_mine_held = held
	if not held:
		_press_blocked = false
	var enabled := _enabled()
	if not enabled or _query == null:
		_press_blocked = held
		_using = false
		_swing_remaining = 0.0
		_clear_target()
		feedback.reset()
		return
	# A fresh F press has exactly one owner. Finishers consume it before any
	# compartment or wall contact, and recovery never buffers another strike.
	if _player.is_finishing() or (fresh_press and _player.try_finisher()) or _player.finisher_ready():
		_using = false
		_swing_remaining = 0.0
		_clear_target()
		feedback.reset()
		return
	_swing_remaining = maxf(0.0, _swing_remaining - delta)
	_using = _swing_remaining > 0.0
	_contact = maxf(0.0, _contact - delta)
	var hit := _target_hit()
	var data: Dictionary = {}
	var deposit: MineralDeposit
	if not hit.is_empty():
		deposit = hit["collider"] as MineralDeposit
		if deposit != null:
			data = deposit.feedback_at(hit["position"], int(hit["shape"]))
	target_deposit = deposit if not data.is_empty() else null
	target_fragment = int(data.get("fragment", -1))
	feedback.set_target(data)
	if not fresh_press:
		return
	_swing_remaining = 0.18
	_using = true
	_strike(hit, data)
	if deposit != null and is_instance_valid(deposit):
		var after := deposit.feedback_at(hit["position"], int(hit["shape"]))
		feedback.set_target(after)
		if after.is_empty():
			_clear_target()

func _clear_target() -> void:
	target_deposit = null
	target_fragment = -1

func _strike(hit: Dictionary, data: Dictionary) -> void:
	var struck := false
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var point: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if collider is MineralDeposit and not data.is_empty():
			var deposit := collider as MineralDeposit
			deposit.smash_compartment(point, int(hit["shape"]))
			var color := Color(0.95, 0.65, 0.27)
			var broken := deposit.last_chunk_broken
			var weak := deposit.last_hit_weak
			_play(_break_stream if broken else _rock_stream)
			_impact_voice.pitch_scale = 1.1
			_spark(point, normal, color.lightened(0.3) if weak else color, broken, weak)
			_kick = 1.8 if broken else 0.65
			struck = true
		elif _contact == 0.0:
			# Scraping plain walls: sparks, no damage.
			_spark(point, normal, rock_spark_color)
	if struck:
		_contact = 0.18


func _play(stream: AudioStream) -> void:
	_impact_voice.stream = stream
	_impact_voice.pitch_scale = randf_range(0.9, 1.1)
	_impact_voice.play()

func _spark(at: Vector3, normal: Vector3, color: Color, broken := false, weak := false) -> void:
	var emitter := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	var up := Vector3.RIGHT if absf(normal.y) > 0.9 else Vector3.UP
	emitter.global_transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.03)
	emitter.color = color
	emitter.amount = 24 if broken else (14 if weak else 10)
	emitter.lifetime = 0.45 if broken else 0.3
	emitter.initial_velocity_max = 7.0 if broken else 5.5
	emitter.restart()

func _process(delta: float) -> void:
	if model == null:
		return
	if not _enabled():
		model.visible = false
		return
	var ready := is_presented()
	_raise = move_toward(_raise, 1.0 if ready else 0.0, delta * raise_speed)
	_kick = move_toward(_kick, 0.0, delta * 9.0)
	model.visible = ready
	if not model.visible:
		return
	var eased := _raise * _raise * (3.0 - 2.0 * _raise)
	# A short impact-and-pull motion, never a held-input drilling loop.
	var leverage := sin((1.0 - _swing_remaining / 0.18) * PI) if _using else 0.0
	model.position = _rest + stowed_offset * (1.0 - eased) + Vector3(-0.018 * leverage, -0.035 * leverage, -0.035 * leverage + 0.025 * _kick)
	model.rotation = _rest_rotation + Vector3(0.24 * leverage - 0.07 * _kick, 0.035 * leverage, -0.06 * leverage)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		cancel()
