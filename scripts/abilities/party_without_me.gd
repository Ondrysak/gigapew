class_name PartyWithoutMe
extends ActiveAbility

## hlasky.txt:207 — "Zase krasne party without me"
## One pooled speaker; failed floor/clearance checks never spend the cooldown.
@export var duration := 8.0
@export var deploy_range := 14.0
@export var fallback_distance := 7.0
@export var footprint_radius := 0.65
@export var radius := 4.5
@export var pulse_interval := 0.8
@export var pulse_damage := 14.0
@export var speaker_template: Node3D
@export var speaker_cone_path := NodePath("Cabinet/Woofer")
@export var wave_path := NodePath("Wave")

var _remaining := 0.0
var _pulse_timer := 0.0
var _pulses_left := 0
var _wave_age := 0.0
var _center := Vector3.ZERO
var _speaker: Node3D
var _woofer: Node3D
var _wave: Node3D
var _query: PhysicsRayQueryParameters3D
var _targets := PackedInt32Array()
var _pulse_audio: AudioStreamPlayer
var pulses_emitted := 0
var hits_landed := 0
var placement_valid := false

func _ready() -> void:
	super()
	_targets.resize(Horde.CAPACITY)
	_pulse_audio = make_audio(null, &"autocannon", -17.0)
	var pool := make_pool(speaker_template, 1)
	_speaker = pool[0] if not pool.is_empty() else null
	if _speaker != null:
		_woofer = _speaker.get_node_or_null(speaker_cone_path) as Node3D
		_wave = _speaker.get_node_or_null(wave_path) as Node3D

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	super(p_player, p_horde, p_run_state)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [p_player.get_rid()])

func is_ready() -> bool:
	return super() and _remaining <= 0.0

func is_deployed() -> bool:
	return _remaining > 0.0

func deployment_position() -> Vector3:
	return _center

func _activate() -> bool:
	if horde == null or _speaker == null:
		return false
	placement_valid = _pick_spot()
	if not placement_valid:
		return false
	_remaining = duration * duration_scale()
	_pulses_left = ceili(_remaining / pulse_interval)
	_pulse_timer = pulse_interval
	pulses_emitted = 0
	hits_landed = 0
	_speaker.global_position = _center
	_speaker.global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)
	_speaker.show()
	_pulse()
	return true

func _pick_spot() -> bool:
	var space := player.get_world_3d().direct_space_state
	var origin := player.camera.global_position
	var forward := -player.camera.global_basis.z
	_query.from = origin
	_query.to = origin + forward * deploy_range
	var aimed := space.intersect_ray(_query)
	var candidate: Vector3
	if not aimed.is_empty():
		candidate = aimed["position"]
		if Vector3(aimed["normal"]).y < 0.6:
			var back := origin - candidate
			back.y = 0.0
			candidate += back.normalized() * (footprint_radius + 0.1)
	else:
		forward.y = 0.0
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		candidate = player.global_position + forward * fallback_distance
	_query.from = Vector3(candidate.x, maxf(candidate.y, player.global_position.y) + 0.4, candidate.z)
	_query.to = _query.from - Vector3.UP * (deploy_range + 3.0)
	var floor_hit := space.intersect_ray(_query)
	if floor_hit.is_empty() or Vector3(floor_hit["normal"]).y < 0.6:
		return false
	var spot: Vector3 = floor_hit["position"]
	if origin.distance_to(spot) > deploy_range:
		return false
	var xz := Vector2(spot.x, spot.z)
	if absf(horde.ground_height(xz) - spot.y) > Horde.LEVEL_GAP or horde.is_blocked(xz, footprint_radius, spot.y, 1.5):
		return false
	_query.from = origin
	_query.to = spot + Vector3.UP * 0.65
	if not space.intersect_ray(_query).is_empty():
		return false
	_center = spot
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
		var health_before := horde.enemy_health_fraction(index)
		horde.damage_direct(index, amount, _center, Vector3.ZERO, DamageType.Kind.FROST)
		if horde.enemy_health_fraction(index) < health_before:
			hits_landed += 1
	if _pulse_audio.stream != null:
		_pulse_audio.play()

func _process(delta: float) -> void:
	if get_tree().paused or not effects_allowed() or _remaining <= 0.0:
		return
	_wave_age += delta
	var t := minf(1.0, _wave_age / pulse_interval)
	if _woofer != null:
		_woofer.scale = Vector3.ONE * (1.0 + sin(t * PI) * 0.13)
	if _wave != null:
		var reach := radius * (run_state.area_multiplier if run_state != null else 1.0)
		var sweep := lerpf(0.35, reach, t)
		_wave.scale = Vector3(sweep, maxf(0.05, 1.0 - t), sweep)
		_wave.visible = t < 0.95

func _finish() -> void:
	_remaining = 0.0
	_pulses_left = 0
	if _speaker != null:
		_speaker.hide()
	if _pulse_audio != null:
		_pulse_audio.stop()

func _cancel_effects() -> void:
	_finish()
