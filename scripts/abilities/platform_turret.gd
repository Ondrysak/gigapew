class_name PlatformTurret
extends ActiveAbility

## Drops a heavy stationary turret on the aimed floor point. It lands with a
## small shockwave, then hammers the nearest enemy with piercing tracers until
## it expires. Re-deploying moves it and restarts the timer.

@export var duration := 15.0
@export var deploy_range := 8.0
## Used when the aim has no floor within deploy_range.
@export var fallback_distance := 2.5
## Obstacle clearance required at the drop point.
@export var footprint_radius := 0.6
@export var target_range := 24.0
@export var fire_interval := 0.12
@export var shot_damage := 28.0
@export var shot_pierce := 3
@export var shot_knockback := 2.5
@export var turn_speed := 14.0
@export var drop_height := 6.0
@export var drop_time := 0.3
@export var landing_radius := 3.0
@export var landing_damage := 40.0
@export var landing_knockback := 14.0
## Blinking warning lights shown during the last seconds.
@export var warning_time := 2.0
## Turret body (a Node3D in this scene; switched to top_level).
@export var turret: Node3D
## Yawing head of the turret.
@export var turret_yaw: Node3D
## Pitching barrel mount under turret_yaw.
@export var turret_pitch: Node3D
## Shot origin at the barrel tip.
@export var muzzle: Node3D
## Flash under the muzzle, shown briefly per shot.
@export var muzzle_flash: Node3D
@export var flash_time := 0.05
@export var warning_lights: Node3D
## Hidden tracer authored as a unit-length beam along -Z, pooled.
@export var tracer_template: Node3D
@export var tracer_count := 8
@export var tracer_lifetime := 0.07
## Hidden flat ring authored at radius 1, expanded to landing_radius.
@export var shock_template: Node3D
@export var shock_duration := 0.4
@export_group("Sound")
@export var shot_sound: AudioStream
@export var synth_shot: StringName = &"autocannon"
@export var landing_sound: AudioStream
@export var synth_landing: StringName = &"seismic_boom"

var _remaining := 0.0
var _drop := -1.0
var _fire_timer := 0.0
var _flash := 0.0
var _target := -1
var _aim := Vector3.FORWARD
var _spot := Vector3.ZERO
var _query: PhysicsRayQueryParameters3D
var _hits := PackedInt32Array()
var _distances := PackedFloat32Array()
var _tracers: Array[Node3D] = []
var _tracer_age := PackedFloat32Array()
var _tracer_from := PackedVector3Array()
var _tracer_to := PackedVector3Array()
var _next_tracer := 0
var _shock: Node3D
var _shock_age := -1.0
var _shot_audio: AudioStreamPlayer
var _landing_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_shot_audio = make_audio(shot_sound, synth_shot, -14.0)
	_landing_audio = make_audio(landing_sound, synth_landing, -8.0)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	_hits.resize(maxi(1, shot_pierce))
	_distances.resize(maxi(1, shot_pierce))
	_tracers = make_pool(tracer_template, tracer_count)
	_tracer_age.resize(_tracers.size())
	_tracer_age.fill(-1.0)
	_tracer_from.resize(_tracers.size())
	_tracer_to.resize(_tracers.size())
	var shocks := make_pool(shock_template, 1)
	_shock = shocks[0] if not shocks.is_empty() else null
	if turret != null:
		turret.top_level = true
		turret.hide()
	if muzzle_flash != null:
		muzzle_flash.hide()
	if warning_lights != null:
		warning_lights.hide()

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState) -> void:
	super(p_player, p_horde, p_run_state)
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [p_player.get_rid()])

func is_deployed() -> bool:
	return _remaining > 0.0

func _activate() -> bool:
	if turret == null:
		return false
	var space := player.get_world_3d().direct_space_state
	_spot = _pick_spot(space)
	_remaining = duration * duration_scale()
	_drop = 0.0
	_fire_timer = 0.0
	_flash = 0.0
	_target = -1
	turret.global_position = _spot + Vector3.UP * drop_height
	turret.show()
	if turret_yaw != null:
		# Face the way the player looks so the drop reads as "placed".
		turret_yaw.rotation.y = player.global_rotation.y
	_aim = Vector3(-sin(player.global_rotation.y), 0.0, -cos(player.global_rotation.y))
	if turret_pitch != null:
		turret_pitch.rotation.x = 0.0
	if muzzle_flash != null:
		muzzle_flash.hide()
	if warning_lights != null:
		warning_lights.hide()
	return true

func _pick_spot(space: PhysicsDirectSpaceState3D) -> Vector3:
	var camera := player.camera
	var origin := camera.global_position
	_query.from = origin
	_query.to = origin - camera.global_basis.z * deploy_range
	var hit := space.intersect_ray(_query)
	var spot := Vector3.ZERO
	if not hit.is_empty() and Vector3(hit["normal"]).y > 0.6:
		spot = hit["position"]
	else:
		var forward := -player.global_basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		spot = _drop_to_floor(space, player.global_position + forward * fallback_distance, player.global_position.y)
	if horde != null:
		var area := horde.play_area
		var clamped := Vector3(clampf(spot.x, area.position.x, area.end.x), spot.y, clampf(spot.z, area.position.y, area.end.y))
		if not clamped.is_equal_approx(spot):
			spot = _drop_to_floor(space, clamped, player.global_position.y)
		if horde.is_blocked(Vector2(spot.x, spot.z), footprint_radius):
			spot = _drop_to_floor(space, player.global_position, player.global_position.y)
	return spot

func _drop_to_floor(space: PhysicsDirectSpaceState3D, at: Vector3, top: float) -> Vector3:
	_query.from = Vector3(at.x, maxf(at.y, top) + 1.0, at.z)
	_query.to = Vector3(at.x, -20.0, at.z)
	var floor_hit := space.intersect_ray(_query)
	if floor_hit.is_empty():
		return Vector3(at.x, 0.0, at.z)
	return floor_hit["position"]

func _ability_physics(delta: float) -> void:
	if _remaining <= 0.0:
		return
	if not player.active:
		_finish()
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_finish()
		return
	if _drop >= 0.0:
		_drop += delta
		if _drop >= drop_time:
			_drop = -1.0
			_land()
		return
	_fire_timer -= delta
	if _fire_timer > 0.0 or horde == null or muzzle == null:
		return
	var origin := muzzle.global_position
	_target = horde.nearest(origin, target_range)
	if _target < 0:
		_fire_timer = 0.0
		return
	_fire_timer += fire_interval
	var target := horde.enemy_position(_target)
	var offset := target - origin
	var reach := offset.length()
	if reach < 0.01:
		return
	var direction := offset / reach
	_aim = direction
	var count := horde.raycast(origin, direction, target_range, shot_pierce, _hits, _distances)
	var amount := shot_damage * damage_scale()
	var push := Vector3(direction.x, 0.0, direction.z).normalized() * shot_knockback
	var end_distance := reach
	for n in count:
		horde.damage_direct(_hits[n], amount, origin, push)
		end_distance = maxf(end_distance, _distances[n])
	_fire_tracer(origin, origin + direction * end_distance)
	_flash = flash_time
	if _shot_audio.stream != null:
		_shot_audio.play()

func _land() -> void:
	turret.global_position = _spot
	if horde != null:
		blast(_spot, landing_radius, landing_damage * damage_scale(), landing_knockback)
	var distance := player.global_position.distance_to(_spot)
	player.add_shake(clampf(0.5 - distance / 30.0, 0.08, 0.4))
	if _landing_audio.stream != null:
		_landing_audio.play()
	if _shock != null:
		_shock_age = 0.0
		_shock.global_position = _spot + Vector3.UP * 0.05
		_shock.scale = Vector3.ONE * 0.3
		_shock.show()

func _fire_tracer(from: Vector3, to: Vector3) -> void:
	if _tracers.is_empty():
		return
	var index := _next_tracer
	_next_tracer = (_next_tracer + 1) % _tracers.size()
	_tracer_age[index] = 0.0
	_tracer_from[index] = from
	_tracer_to[index] = to
	_place_beam(_tracers[index], from, to, 1.0)

## Places a template authored as a unit-length beam along -Z between points.
static func _place_beam(beam: Node3D, from: Vector3, to: Vector3, width_scale: float) -> void:
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

func _finish() -> void:
	_remaining = 0.0
	_drop = -1.0
	_target = -1
	if turret != null:
		turret.hide()

func _exit_tree() -> void:
	_finish()

func _cancel_effects() -> void:
	_finish()
	_tracer_age.fill(-1.0)
	_shock_age = -1.0

func _process(delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	if _remaining > 0.0 and turret != null:
		if _drop >= 0.0:
			var t := minf(_drop / drop_time, 1.0)
			turret.global_position = _spot + Vector3.UP * drop_height * (1.0 - t * t)
		else:
			_aim_head(delta)
		if muzzle_flash != null:
			_flash -= delta
			muzzle_flash.visible = _flash > 0.0
			if _flash > 0.0:
				muzzle_flash.rotation.z = randf() * TAU
		if warning_lights != null:
			warning_lights.visible = _remaining < warning_time and fmod(_remaining, 0.3) >= 0.15
	for index in range(_tracers.size()):
		var age := _tracer_age[index]
		if age < 0.0:
			continue
		age += delta
		if age >= tracer_lifetime:
			_tracer_age[index] = -1.0
			_tracers[index].hide()
			continue
		_tracer_age[index] = age
		_place_beam(_tracers[index], _tracer_from[index], _tracer_to[index], 1.0 - age / tracer_lifetime)
	if _shock == null or _shock_age < 0.0:
		return
	_shock_age += delta
	if _shock_age >= shock_duration:
		_shock_age = -1.0
		_shock.hide()
		return
	var p := _shock_age / shock_duration
	var radius := lerpf(0.3, landing_radius, 1.0 - (1.0 - p) * (1.0 - p) * (1.0 - p))
	_shock.scale = Vector3(radius, maxf(0.05, 1.0 - p), radius)

func _aim_head(delta: float) -> void:
	if turret_yaw == null:
		return
	# Track the live target between shots; hold the last aim otherwise.
	if _target >= 0 and horde != null and horde.is_alive(_target) and muzzle != null:
		var offset := horde.enemy_position(_target) - muzzle.global_position
		if offset.length_squared() > 0.0001:
			_aim = offset.normalized()
	var weight := 1.0 - exp(-turn_speed * delta)
	var yaw := atan2(-_aim.x, -_aim.z)
	turret_yaw.rotation.y = lerp_angle(turret_yaw.rotation.y, yaw, weight)
	if turret_pitch != null:
		var pitch := asin(clampf(_aim.y, -1.0, 1.0))
		turret_pitch.rotation.x = lerpf(turret_pitch.rotation.x, clampf(pitch, -0.6, 0.8), weight)
