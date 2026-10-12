class_name Brucelee
extends ActiveAbility

## hlasky.txt:10 — "Brucelee imuni vuci vsemu"
## Source-owned guard and individually aimed, timed cone strikes; no bubble hit.
@export var duration := 1.1
@export var strike_count := 4
@export var strike_interval := 0.22
@export var reach := 4.2
@export var half_angle_degrees := 40.0
@export var strike_damage := 18.0
@export var knockback := 3.0
@export var martial_visual: Node3D
@export var left_fist: Node3D
@export var right_fist: Node3D
@export var kick: Node3D
@export var impact_cone: Node3D

var _remaining := 0.0
var _strike_timer := 0.0
var _strikes_left := 0
var strikes_emitted := 0
var hits_landed := 0
var _impact_age := -1.0
var _pose := 0
var _targets := PackedInt32Array()
var _query: PhysicsRayQueryParameters3D
var _hit_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_targets.resize(Horde.CAPACITY)
	_hit_audio = make_audio(null, &"seismic_throw", -13.0)
	if martial_visual != null:
		martial_visual.top_level = true
		martial_visual.hide()

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	super(p_player, p_horde, p_run_state)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [p_player.get_rid()])

func is_ready() -> bool:
	return super() and _remaining <= 0.0

func is_shielded() -> bool:
	return _remaining > 0.0

func _activate() -> bool:
	if horde == null or martial_visual == null:
		return false
	_remaining = duration * duration_scale()
	_strikes_left = strike_count + rank()
	_strike_timer = strike_interval
	strikes_emitted = 0
	hits_landed = 0
	player.set_ability_protection(self, true)
	martial_visual.show()
	_strike()
	return true

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_finish()
		return
	_strike_timer -= delta
	while _strike_timer <= 0.0 and _strikes_left > 0:
		_strike_timer += strike_interval
		_strike()

func _strike() -> void:
	_strikes_left -= 1
	_pose = strikes_emitted % 3
	strikes_emitted += 1
	_impact_age = 0.0
	var center := player.global_position
	var forward := -player.camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else -player.global_basis.z
	var radius := reach * (run_state.area_multiplier if run_state != null else 1.0)
	var floor_y := horde.ground_height(Vector2(center.x, center.z))
	var count := horde.query_radius(center, radius, _targets)
	var amount := combo_blast_damage(center, radius, strike_damage * damage_scale())
	var cone_cos := cos(deg_to_rad(half_angle_degrees))
	for n in count:
		var index := _targets[n]
		var at := horde.enemy_position(index)
		if absf(horde.ground_height(Vector2(at.x, at.z)) - floor_y) > Horde.LEVEL_GAP:
			continue
		var offset := at - center
		offset.y = 0.0
		if offset.length_squared() > 0.0001 and offset.normalized().dot(forward) < cone_cos:
			continue
		_query.from = center + Vector3.UP * 0.2
		_query.to = at
		if not player.get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
			continue
		var health_before := horde.enemy_health_fraction(index)
		horde.damage_direct(index, amount, center, forward * knockback)
		if horde.enemy_health_fraction(index) < health_before:
			hits_landed += 1
	player.add_shake(0.07 if _pose != 2 else 0.12)
	if _hit_audio.stream != null:
		_hit_audio.play()

func _process(delta: float) -> void:
	if get_tree().paused or not effects_allowed() or _remaining <= 0.0:
		return
	martial_visual.global_position = player.global_position + Vector3.UP * 0.25
	martial_visual.global_rotation = Vector3(0.0, player.camera.global_rotation.y, 0.0)
	_impact_age += delta
	var punch := maxf(0.0, sin(minf(1.0, _impact_age / strike_interval) * PI))
	if left_fist != null:
		left_fist.position.z = -0.65 - (punch * 0.65 if _pose == 0 else 0.0)
	if right_fist != null:
		right_fist.position.z = -0.65 - (punch * 0.65 if _pose == 1 else 0.0)
	if kick != null:
		kick.visible = _pose == 2
		kick.rotation.x = -0.8 + punch * 0.65
	if impact_cone != null:
		impact_cone.visible = _impact_age < strike_interval * 0.8
		var radius := reach * (run_state.area_multiplier if run_state != null else 1.0)
		impact_cone.scale = Vector3(radius, maxf(0.05, 1.0 - punch), radius)

func _finish() -> void:
	_remaining = 0.0
	_strikes_left = 0
	_impact_age = -1.0
	if is_instance_valid(player):
		player.set_ability_protection(self, false)
	if martial_visual != null:
		martial_visual.hide()
	if _hit_audio != null:
		_hit_audio.stop()

func _cancel_effects() -> void:
	_finish()
