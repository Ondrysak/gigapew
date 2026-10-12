class_name Crossfader
extends ActiveAbility

## hlasky.txt:98 — "Delaj mam vytazeny gramce uplne bych vam ukazal co je crossfader"
@export var duration := 3.0
@export var pulse_count := 6
@export var pulse_interval := 0.48
@export var radius := 6.0
@export var pulse_damage := 12.0
@export var pull_strength := 10.0
@export var push_strength := 14.0
@export var stage: Node3D
@export var wave: Node3D
@export var boundary: Node3D
@export var platter_left: Node3D
@export var platter_right: Node3D
@export var fader: Node3D

var _remaining := 0.0
var _pulse_timer := 0.0
var _pulses_left := 0
var _wave_age := 0.0
var _center := Vector3.ZERO
var _inward := true
var _targets := PackedInt32Array()
var _query: PhysicsRayQueryParameters3D
var _pulse_audio: AudioStreamPlayer
var pulses_emitted := 0
var inward_hits := 0
var outward_hits := 0

func _ready() -> void:
	super()
	_targets.resize(Horde.CAPACITY)
	_pulse_audio = make_audio(null, &"bulwark_end", -12.0)
	if stage != null:
		stage.top_level = true
		stage.hide()

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	super(p_player, p_horde, p_run_state)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [p_player.get_rid()])

func is_ready() -> bool:
	return super() and _remaining <= 0.0

func _activate() -> bool:
	if horde == null or stage == null:
		return false
	_query.from = player.global_position
	_query.to = player.global_position - Vector3.UP * 2.0
	var floor_hit := player.get_world_3d().direct_space_state.intersect_ray(_query)
	if floor_hit.is_empty() or Vector3(floor_hit["normal"]).y < 0.6:
		return false
	_center = floor_hit["position"]
	_remaining = duration * duration_scale()
	_pulses_left = pulse_count + rank()
	_pulse_timer = pulse_interval
	pulses_emitted = 0
	inward_hits = 0
	outward_hits = 0
	stage.global_position = _center + Vector3.UP * 0.06
	stage.global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)
	stage.show()
	_pulse()
	return true

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_finish()
		return
	_pulse_timer -= delta
	while _pulse_timer <= 0.0 and _pulses_left > 0:
		_pulse_timer += pulse_interval
		_pulse()

func _pulse() -> void:
	_inward = pulses_emitted % 2 == 0
	pulses_emitted += 1
	_pulses_left -= 1
	_wave_age = 0.0
	var reach := radius * (run_state.area_multiplier if run_state != null else 1.0)
	var amount := combo_blast_damage(_center, reach, pulse_damage * damage_scale())
	var count := horde.query_radius(_center, reach, _targets)
	var space := player.get_world_3d().direct_space_state
	for n in count:
		var index := _targets[n]
		var at := horde.enemy_position(index)
		if absf(horde.ground_height(Vector2(at.x, at.z)) - _center.y) > Horde.LEVEL_GAP:
			continue
		_query.from = _center + Vector3.UP * 0.8
		_query.to = at
		if not space.intersect_ray(_query).is_empty():
			continue
		var outward := at - _center
		outward.y = 0.0
		var distance := outward.length()
		var direction := outward / maxf(distance, 0.001)
		var impulse := direction * (-minf(pull_strength, distance / pulse_interval) if _inward else push_strength)
		var health_before := horde.enemy_health_fraction(index)
		horde.damage_direct(index, amount, _center, impulse)
		if horde.enemy_health_fraction(index) < health_before:
			if _inward:
				inward_hits += 1
			else:
				outward_hits += 1
	player.add_shake(0.09)
	if _pulse_audio.stream != null:
		_pulse_audio.play()

func _process(delta: float) -> void:
	if get_tree().paused or not effects_allowed() or _remaining <= 0.0:
		return
	_wave_age += delta
	if wave != null:
		var t := minf(1.0, _wave_age / pulse_interval)
		var reach := radius * (run_state.area_multiplier if run_state != null else 1.0)
		var sweep := lerpf(reach, 0.25, t) if _inward else lerpf(0.25, reach, t)
		wave.scale = Vector3(sweep, 1.0, sweep)
		wave.visible = _pulses_left > 0 or t < 1.0
	if boundary != null:
		var reach := radius * (run_state.area_multiplier if run_state != null else 1.0)
		boundary.scale = Vector3(reach, 1.0, reach)
	if platter_left != null:
		platter_left.rotation.y = fmod(platter_left.rotation.y + delta * (8.0 if _inward else -8.0), TAU)
	if platter_right != null:
		platter_right.rotation.y = fmod(platter_right.rotation.y - delta * (8.0 if _inward else -8.0), TAU)
	if fader != null:
		fader.position.x = lerpf(fader.position.x, -0.24 if _inward else 0.24, minf(1.0, delta * 18.0))

func _finish() -> void:
	_remaining = 0.0
	_pulses_left = 0
	if stage != null:
		stage.hide()
	if _pulse_audio != null:
		_pulse_audio.stop()

func _cancel_effects() -> void:
	_finish()
