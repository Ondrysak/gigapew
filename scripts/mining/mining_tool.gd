class_name MiningTool
extends Node3D

## Proximity drill: aiming at visible ore raises it automatically; held F cuts.
const FeedbackController := preload("res://scripts/mining/mining_feedback.gd")

## Node moved between the stowed and raised poses.
@export var model: Node3D
## Node spun around `spin_axis` while drilling.
@export var spinner: Node3D
@export var spin_axis := Vector3(0.0, 0.0, 1.0)
@export var spin_speed := 40.0
## Offset from the authored pose when not in use.
@export var stowed_offset := Vector3(-0.05, -0.38, 0.18)
@export var raise_speed := 7.0

@export_group("Mining")
@export var reach := 2.6
@export var mining_per_second := 45.0
@export var tick_interval := 0.15

## Same-section contact ramps to a 35% faster cut; changing sections resets it.
@export_range(0.3, 1.2) var resonance_seconds := 0.65


@export_group("Effects")
@export var spark_mesh: Mesh
## Should use vertex color as albedo.
@export var spark_material: Material
@export var rock_spark_color := Color(1.0, 0.72, 0.3)
@export var drill_sound: AudioStream
@export var rock_sound: AudioStream
@export var drill_volume_db := -17.0
@export var sound_bus: StringName = &"SFX"
## Zero disables the temporal halo without removing target information.
@export_range(0.0, 1.0) var feedback_strength := 0.65

## Public drill state for HUD integrations and targeted smoke checks.
var resonance := 0.0
var target_deposit: MineralDeposit
var target_fragment := -1
var feedback: MiningFeedback

var _player: ArenaPlayer
var _run_state: RunState
var _query: PhysicsRayQueryParameters3D
var _tick := 0.0
var _using := false
var _raise := 0.0
var _kick := 0.0
var _contact := 0.0
var _rest := Vector3.ZERO
var _sparks: Array[CPUParticles3D] = []
var _next_spark := 0
var _drill_voice: AudioStreamPlayer
var _impact_voice: AudioStreamPlayer
var _rock_stream: AudioStream
var _break_stream: AudioStream
var _fracture_progress := 0.0
var _weak_contact := false

func _ready() -> void:
	if model != null:
		_rest = model.position
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
	_drill_voice = AudioStreamPlayer.new()
	_drill_voice.stream = drill_sound if drill_sound != null else MiningSynth.drill_loop()
	_drill_voice.volume_db = drill_volume_db
	_drill_voice.bus = sound_bus
	add_child(_drill_voice)
	_rock_stream = rock_sound if rock_sound != null else MiningSynth.cue(&"clank")
	_break_stream = MiningSynth.cue(&"section")
	_impact_voice = AudioStreamPlayer.new()
	_impact_voice.volume_db = -13.0
	_impact_voice.max_polyphony = 3
	_impact_voice.bus = sound_bus
	add_child(_impact_voice)
	feedback = FeedbackController.new()
	add_child(feedback)
	feedback.strength = feedback_strength

## Call after the tool is a child of the player's camera.
func setup(player: ArenaPlayer, run_state: RunState) -> void:
	_player = player
	_run_state = run_state
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [player.get_rid()])
	feedback.setup(player)
	_player.mining_tool = self

## The first physics surface must be a live ore fragment within drill reach.
func has_target() -> bool:
	if not _enabled() or _query == null:
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
	_tick = 0.0
	_contact = 0.0
	_clear_target()
	if _drill_voice != null:
		_drill_voice.stop()
	if _impact_voice != null:
		_impact_voice.stop()
	if feedback != null:
		feedback.reset()

func _physics_process(delta: float) -> void:
	var enabled := _enabled()
	var using := enabled and _player.drilling()
	if using != _using:
		_using = using
		if using:
			_drill_voice.play()
		else:
			_drill_voice.stop()
	_contact = maxf(0.0, _contact - delta)
	if not enabled or _query == null:
		_clear_target()
		feedback.reset()
		_tick = 0.0
		return
	var hit := _target_hit()
	var data: Dictionary = {}
	var deposit: MineralDeposit
	if not hit.is_empty():
		deposit = hit["collider"] as MineralDeposit
		if deposit != null:
			data = deposit.feedback_at(hit["position"], int(hit["shape"]))
	var fragment := int(data.get("fragment", -1))
	if deposit != target_deposit or fragment != target_fragment:
		resonance = 0.0
	target_deposit = deposit if not data.is_empty() else null
	target_fragment = fragment
	if using and not data.is_empty():
		resonance = minf(1.0, resonance + delta / maxf(resonance_seconds, 0.01))
	else:
		resonance = 0.0
	_fracture_progress = float(data.get("progress", 0.0))
	_weak_contact = bool(data.get("weak", false)) and using
	feedback.set_target(data, using, resonance)
	if not using:
		# The first tick of the next press lands immediately.
		_tick = 0.0
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = maxf(_tick + tick_interval, 0.0)
	_strike(hit, data)
	if deposit != null and is_instance_valid(deposit):
		var after := deposit.feedback_at(hit["position"], int(hit["shape"]))
		feedback.set_target(after, using, resonance)
		if after.is_empty():
			_clear_target()

func _clear_target() -> void:
	target_deposit = null
	target_fragment = -1
	resonance = 0.0
	_fracture_progress = 0.0
	_weak_contact = false

func _strike(hit: Dictionary, data: Dictionary) -> void:
	var struck := false
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var point: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if collider is MineralDeposit and not data.is_empty():
			var deposit := collider as MineralDeposit
			var multiplier := _run_state.mining_multiplier if _run_state != null else 1.0
			var cut_rate := mining_per_second * (1.0 + resonance * 0.35)
			deposit.take_mining_damage(cut_rate * tick_interval * multiplier, point, int(hit["shape"]))
			var color: Color = data["color"]
			var broken := deposit.last_chunk_broken
			var weak := deposit.last_hit_weak
			_play(_break_stream if broken else _rock_stream)
			_impact_voice.pitch_scale = 0.95 + _fracture_progress * 0.2 + resonance * 0.15 + (0.15 if weak else 0.0)
			_spark(point, normal, color.lightened(0.3) if weak else color, broken, weak)
			if broken:
				feedback.fragment_beat()
			_kick = 1.8 if broken else (1.05 if weak else 0.65) + _fracture_progress * 0.25
			struck = true
		elif _contact == 0.0:
			# Scraping plain walls: sparks, no damage.
			_spark(point, normal, rock_spark_color)
	if struck:
		_contact = tick_interval * 1.5


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
	emitter.initial_velocity_max = 7.0 if broken else 5.5 + resonance + _fracture_progress
	emitter.restart()

func _process(delta: float) -> void:
	feedback.strength = feedback_strength
	if model == null:
		return
	var ready := _player != null and _player.mining_ready()
	_raise = move_toward(_raise, 1.0 if ready else 0.0, delta * raise_speed)
	_kick = move_toward(_kick, 0.0, delta * 9.0)
	model.visible = ready
	if not model.visible:
		return
	var eased := _raise * _raise * (3.0 - 2.0 * _raise)
	var jitter := Vector3.ZERO
	if _using:
		var strength := 0.004 + (0.006 + resonance * 0.003 + _fracture_progress * 0.002 if _contact > 0.0 else 0.0)
		jitter = Vector3(randf_range(-strength, strength), randf_range(-strength, strength), 0.0)
	model.position = _rest + stowed_offset * (1.0 - eased) + jitter + Vector3(0.0, 0.0, -0.06 * _kick)
	if spinner != null and _using:
		spinner.rotate_object_local(spin_axis.normalized(), spin_speed * delta * (1.3 + resonance * 0.2 if _contact > 0.0 else 1.0))
	if _using:
		var contact_pitch := 1.1 + resonance * 0.25 + _fracture_progress * 0.1 + (0.08 if _weak_contact else 0.0)
		_drill_voice.pitch_scale = lerpf(_drill_voice.pitch_scale, contact_pitch if _contact > 0.0 else 1.0, 1.0 - exp(-10.0 * delta))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		cancel()
