class_name TurretConsole
extends Hazard

## Crystal-powered defence terminal. Press interact at the console (front =
## local +Z) to spend crystals; its turret then fires tracers at the nearest
## visible enemy for a while and recharges afterwards.

enum State { IDLE, ACTIVE, COOLDOWN }

@export var cost := 10
@export var resource_id: StringName = &"crystal"
@export var active_time := 20.0
@export var cooldown := 10.0
@export var interact_range := 2.5
## Minimum dot between the player's facing and the direction to the console.
@export var facing_dot := 0.5
## Turret base position relative to the console root.
@export var turret_offset := Vector3(2.0, 0.0, 0.0)

@export_group("Turret")
@export var target_range := 22.0
@export var damage := 12.0
@export var shots_per_second := 8.0
@export var knockback := 0.8
## Head yaw speed toward the target, radians per second.
@export var turn_speed := 14.0
## Extra random enemies tried when the nearest one is behind a wall.
@export var sight_retries := 3

@export_group("Visuals")
@export var turret: Node3D
## Yaw pivot of the turret head; barrels point along its -Z.
@export var head: Node3D
## Parent whose Marker3D children are the barrel tips, fired in turn.
@export var muzzle_group: Node3D
## Console point the player interacts with.
@export var interact_point: Node3D
@export var prompt: Label3D
## Parent whose GeometryInstance3D children are status lights, switched
## between the state materials below.
@export var status_lights: Node3D
@export var idle_material: Material
@export var active_material: Material
@export var cooldown_material: Material
## Floor cable stretched from the console to the turret base.
@export var cable: Node3D
@export var cable_start: Node3D
@export var console_body: CollisionObject3D
@export var turret_body: CollisionObject3D
## Hidden unit-length beam along -Z.
@export var tracer_template: Node3D
## Hidden unit-size spark (impacts and muzzle flashes).
@export var spark_template: Node3D
@export var tracer_duration := 0.06
@export var spark_size := 0.28
@export var muzzle_flash_size := 0.22
@export var prompt_color := Color(0.85, 0.95, 1.0)
@export var active_color := Color(0.45, 1.0, 0.5)
@export var denied_color := Color(1.0, 0.35, 0.3)

@export_group("Sound")
@export var power_on_sound: AudioStream
@export var power_off_sound: AudioStream
@export var denied_sound: AudioStream
@export var shot_sound: AudioStream

var _state := State.IDLE
var _timer := 0.0
var _fire_timer := 0.0
var _deny_timer := 0.0
var _target_yaw := 0.0
var _muzzle := 0
var _prompt_key := -1
var _muzzles: Array[Marker3D] = []
var _tracers: Array[Node3D] = []
var _tracer_times := PackedFloat32Array()
var _tracer_from := PackedVector3Array()
var _tracer_to := PackedVector3Array()
var _sparks: AutoFxPool
var _query: PhysicsRayQueryParameters3D
var _rng := RandomNumberGenerator.new()
var _on_voice: AudioStreamPlayer3D
var _off_voice: AudioStreamPlayer3D
var _deny_voice: AudioStreamPlayer3D
var _shot_voice: AudioStreamPlayer3D

func _ready() -> void:
	super()
	turret.position = turret_offset
	_target_yaw = head.rotation.y
	for child in muzzle_group.get_children():
		if child is Marker3D:
			_muzzles.append(child)
	_set_lights(idle_material)
	prompt.hide()
	# Lay the power cable along the floor from the console to the turret.
	var from := cable_start.global_position
	var to := turret.global_position
	from.y = 0.02
	to.y = 0.02
	AutoWeapon.place_beam(cable, from, to)

func _on_setup() -> void:
	_rng.randomize()
	for index in range(_muzzles.size()):
		var tracer := tracer_template.duplicate() as Node3D
		add_child(tracer)
		tracer.top_level = true
		tracer.hide()
		_tracers.append(tracer)
	_tracer_times.resize(_tracers.size())
	_tracer_from.resize(_tracers.size())
	_tracer_to.resize(_tracers.size())
	_sparks = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
	_sparks.reserve(6)
	var exclude: Array[RID] = [console_body.get_rid(), turret_body.get_rid(), player.get_rid()]
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, exclude)
	_on_voice = make_voice(power_on_sound, &"console_on", -4.0, 1)
	_off_voice = make_voice(power_off_sound, &"console_off", -6.0, 1)
	_deny_voice = make_voice(denied_sound, &"console_deny", -6.0, 1)
	_shot_voice = make_voice(shot_sound, &"turret_shot", -12.0, 4)

func _tick(delta: float) -> void:
	_deny_timer = maxf(0.0, _deny_timer - delta)
	match _state:
		State.IDLE:
			if interact_pressed() and player_can_reach(interact_point.global_position, interact_range, facing_dot):
				if run_state.spend_resource(resource_id, cost):
					_state = State.ACTIVE
					_timer = active_time
					_fire_timer = 0.3
					_set_lights(active_material)
					_on_voice.play()
				else:
					_deny_timer = 0.8
					_deny_voice.play()
		State.ACTIVE:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.COOLDOWN
				_timer = cooldown
				_set_lights(cooldown_material)
				_off_voice.play()
				return
			_fire_timer -= delta
			if _fire_timer <= 0.0:
				_fire_timer += 1.0 / shots_per_second
				if not _fire():
					_fire_timer = maxf(_fire_timer, 0.1)
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE
				_set_lights(idle_material)

func _fire() -> bool:
	var muzzle := _muzzles[_muzzle]
	var origin := muzzle.global_position
	var target := horde.nearest(origin, target_range)
	if target < 0:
		return false
	var hit_at := horde.enemy_position(target)
	if not _can_see(origin, hit_at):
		target = -1
		var found := horde.query_radius(origin, target_range, _hits)
		for attempt in range(mini(sight_retries, found)):
			var candidate := _hits[_rng.randi_range(0, found - 1)]
			var at := horde.enemy_position(candidate)
			if _can_see(origin, at):
				target = candidate
				hit_at = at
				break
		if target < 0:
			return false
	var flat := Vector3(hit_at.x - origin.x, 0.0, hit_at.z - origin.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		_target_yaw = atan2(-flat.x, -flat.z) - turret.global_rotation.y
	horde.damage_direct(target, damage, origin, flat * knockback)
	_tracer_from[_muzzle] = origin
	_tracer_to[_muzzle] = hit_at
	_tracer_times[_muzzle] = tracer_duration
	_sparks.spawn(hit_at, spark_size, 0.12, _rng.randf() * TAU)
	_sparks.spawn(origin, muzzle_flash_size, 0.05)
	_shot_voice.play()
	_muzzle = (_muzzle + 1) % _muzzles.size()
	return true

func _can_see(from: Vector3, to: Vector3) -> bool:
	_query.from = from
	_query.to = to
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()

func _set_lights(material: Material) -> void:
	for light in status_lights.get_children():
		(light as GeometryInstance3D).material_override = material

func _animate(delta: float) -> void:
	_sparks.update(delta)
	var turn := wrapf(_target_yaw - head.rotation.y, -PI, PI)
	head.rotation.y += clampf(turn, -turn_speed * delta, turn_speed * delta)
	for index in range(_tracers.size()):
		if _tracer_times[index] <= 0.0:
			continue
		_tracer_times[index] -= delta
		if _tracer_times[index] <= 0.0:
			_tracers[index].hide()
		else:
			AutoWeapon.place_beam(_tracers[index], _tracer_from[index], _tracer_to[index], _tracer_times[index] / tracer_duration)
	_update_prompt()

func _update_prompt() -> void:
	if not player.active or not player_can_reach(interact_point.global_position, interact_range, facing_dot):
		if prompt.visible:
			prompt.hide()
		return
	var held := int(run_state.resources.get(resource_id, 0))
	var affordable := held >= cost
	var seconds := ceili(maxf(_timer, 0.0))
	# Rebuild the text only when what it shows changes.
	var key := int(_state) * 100000 + seconds * 10 + (1 if affordable else 0) + (5 if _deny_timer > 0.0 else 0)
	if key != _prompt_key:
		_prompt_key = key
		match _state:
			State.IDLE:
				if affordable:
					prompt.text = "[E] ZAPNOUT VĚŽ\n%d CIGÁR" % cost
					prompt.modulate = prompt_color
				else:
					prompt.text = "VĚŽ: %d CIGÁR\nMÁŠ %d" % [cost, held]
					prompt.modulate = denied_color if _deny_timer > 0.0 else prompt_color.darkened(0.3)
			State.ACTIVE:
				prompt.text = "VĚŽ BĚŽÍ\n%ds" % seconds
				prompt.modulate = active_color
			State.COOLDOWN:
				prompt.text = "PAUZA\n%ds" % seconds
				prompt.modulate = prompt_color.darkened(0.35)
	if not prompt.visible:
		prompt.show()
