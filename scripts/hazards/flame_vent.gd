class_name FlameVent
extends Hazard

## Floor fuel vent. Press interact near its valve, or shoot the valve, to
## blast a flame lane along local -Z for a few seconds: enemies in the lane
## burn and are pushed down it. The vent then refuels.

enum State { READY, PRIMING, BURNING, COOLDOWN }

@export var lane_length := 12.0
@export var lane_width := 2.5
@export var burn_time := 3.0
## Hissing delay between activation and ignition.
@export var prime_time := 0.35
@export var cooldown := 12.0
@export var enemy_dps := 60.0
@export var damage_tick := 0.2
## Push along the lane (-Z) per damage tick.
@export var knockback := 3.0
## The flame front advances this fast (m/s) after ignition.
@export var front_speed := 30.0
## Flames are the player's tool by default; raise to make them hurt.
@export var player_dps := 0.0
@export var player_tick := 0.5
@export var interact_range := 2.5
## Minimum dot between the player's facing and the direction to the valve.
@export var facing_dot := 0.5
## Any shot at least this strong on the valve opens it.
@export var valve_hit_threshold := 1.0

@export_group("Visuals")
@export var valve_hitbox: HazardHitbox
## Point the player interacts with (the valve wheel).
@export var interact_point: Node3D
@export var valve_wheel: Node3D
@export var prompt: Label3D
@export var flames: CPUParticles3D
## Unit floor plane (extends along -Z) scaled to the lane, with `heat`,
## `reach` and `primed` shader uniforms
## (ShaderMaterial copied per vent at setup).
@export var lane_marker: MeshInstance3D
## Pilot light, visible when the vent can be fired.
@export var pilot: Node3D
## Nozzle glow, flickering while priming and burning.
@export var nozzle_glow: Node3D
@export var valve_spin_speed := 9.0
@export var prompt_color := Color(1.0, 0.85, 0.6)
@export var busy_color := Color(1.0, 0.5, 0.2)

@export_group("Sound")
@export var ignite_sound: AudioStream
@export var roar_sound: AudioStream

const HEAT_PARAM := &"heat"
const REACH_PARAM := &"reach"
const PRIMED_PARAM := &"primed"

var _state := State.READY
var _timer := 0.0
var _burned := 0.0
var _damage_timer := 0.0
var _player_timer := 0.0
var _heat := 0.0
var _clock := 0.0
var _prompt_key := -1
var _material: ShaderMaterial
var _ignite_voice: AudioStreamPlayer3D
var _roar_voice: AudioStreamPlayer3D

func _ready() -> void:
	super()
	valve_hitbox.hit.connect(take_hit)
	prompt.hide()
	lane_marker.scale = Vector3(lane_width, 1.0, lane_length)
	# Particles are authored for a 12 m x 2.5 m lane.
	var stretch := lane_length / 12.0
	flames.initial_velocity_min *= stretch
	flames.initial_velocity_max *= stretch
	flames.emission_box_extents.x *= lane_width / 2.5

func _on_setup() -> void:
	_material = (lane_marker.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	lane_marker.material_override = _material
	_ignite_voice = make_voice(ignite_sound, &"flame_ignite", -2.0, 1)
	_roar_voice = make_voice(roar_sound, &"flame_roar", -4.0, 1)

## Player shot on the valve.
func take_hit(amount: float, _at: Vector3) -> void:
	if is_set_up() and amount >= valve_hit_threshold:
		activate()

## Opens the valve; ignored unless the vent is ready.
func activate() -> void:
	if not is_set_up() or _state != State.READY:
		return
	_state = State.PRIMING
	_timer = prime_time
	_ignite_voice.play()

func _tick(delta: float) -> void:
	match _state:
		State.READY:
			if interact_pressed() and player_can_reach(interact_point.global_position, interact_range, facing_dot):
				activate()
		State.PRIMING:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.BURNING
				_timer = burn_time
				_burned = 0.0
				_damage_timer = 0.0
				_player_timer = 0.0
				flames.emitting = true
				_roar_voice.play()
		State.BURNING:
			_timer -= delta
			_burned += delta
			_damage_timer -= delta
			if _damage_timer <= 0.0:
				_damage_timer += damage_tick
				_burn_lane()
			if player_dps > 0.0:
				_player_timer -= delta
				if _player_timer <= 0.0:
					_player_timer += player_tick
					if _in_lane(player.global_position, _reach()):
						player.take_damage(maxi(1, roundi(player_dps * player_tick)))
			if _timer <= 0.0:
				_state = State.COOLDOWN
				_timer = cooldown
				flames.emitting = false
				_roar_voice.stop()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.READY

func _reach() -> float:
	return minf(lane_length, _burned * front_speed)

func _in_lane(at: Vector3, reach: float) -> bool:
	var local := to_local(at)
	return absf(local.x) <= lane_width * 0.5 and local.z <= 0.3 and local.z >= -reach

func _burn_lane() -> void:
	var reach := _reach()
	if reach <= 0.0:
		return
	var half := reach * 0.5
	var center := to_global(Vector3(0.0, 0.0, -half))
	var found := horde.query_radius(center, Vector2(half, lane_width * 0.5).length() + 0.5, _hits)
	var push := -global_basis.z.normalized() * knockback
	var amount := enemy_dps * damage_tick
	for n in found:
		var slot := _hits[n]
		if _in_lane(horde.enemy_position(slot), reach):
			horde.damage(slot, amount, push)

func _animate(delta: float) -> void:
	_clock += delta
	var target_heat := 0.0
	var primed := 0.0
	match _state:
		State.READY:
			primed = 1.0
		State.PRIMING:
			target_heat = 0.3
			valve_wheel.rotate_object_local(Vector3.FORWARD, valve_spin_speed * delta)
		State.BURNING:
			target_heat = 1.0
			valve_wheel.rotate_object_local(Vector3.FORWARD, valve_spin_speed * 0.4 * delta)
	_heat = move_toward(_heat, target_heat, delta * (4.0 if target_heat > _heat else 0.5))
	pilot.visible = _state == State.READY
	nozzle_glow.visible = _heat > 0.05
	if nozzle_glow.visible:
		nozzle_glow.scale = Vector3.ONE * (0.6 + 0.4 * _heat + 0.12 * sin(_clock * 43.0))
	var reach := _reach() if _state == State.BURNING else lane_length
	_material.set_shader_parameter(HEAT_PARAM, _heat)
	_material.set_shader_parameter(REACH_PARAM, reach / lane_length)
	_material.set_shader_parameter(PRIMED_PARAM, primed)
	_update_prompt()

func _update_prompt() -> void:
	if not player.active or not player_can_reach(interact_point.global_position, interact_range, facing_dot):
		if prompt.visible:
			prompt.hide()
		return
	var seconds := ceili(maxf(_timer, 0.0)) if _state == State.COOLDOWN else 0
	var key := int(_state) * 1000 + seconds
	if key != _prompt_key:
		_prompt_key = key
		match _state:
			State.READY:
				prompt.text = "[E] OTEVŘÍT PALIVOVÝ VENTIL"
				prompt.modulate = prompt_color
			State.PRIMING, State.BURNING:
				prompt.text = "PLAMENY"
				prompt.modulate = busy_color
			State.COOLDOWN:
				prompt.text = "DOPLŇOVÁNÍ PALIVA\n%ds" % seconds
				prompt.modulate = prompt_color.darkened(0.35)
	if not prompt.visible:
		prompt.show()
