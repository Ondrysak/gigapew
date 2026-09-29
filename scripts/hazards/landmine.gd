class_name Landmine
extends Hazard

## Proximity mine. Arms shortly after setup; the first enemy inside the trigger
## radius starts a short beeping delay (so the crowd bunches up), then the
## blast shreds everything nearby. The mine redeploys after a cooldown.

enum State { ARMING, ARMED, TRIGGERED, SPENT }

@export var arm_time := 1.5
@export var trigger_radius := 1.6
## Seconds between proximity checks while armed.
@export var check_interval := 0.1
@export var trigger_delay := 0.3

@export_group("Blast")
@export var horde_damage := 120.0
@export var blast_radius := 3.0
## Share of the damage dealt at the blast edge (linear falloff).
@export var edge_fraction := 0.5
@export var knockback := 10.0
## Mines are friendly by default; raise to make them hurt the player too.
@export var player_damage := 0.0
@export var player_radius := 3.0
@export var shake := 0.45
@export var blast_height := 0.4
@export var blast_duration := 0.34
@export var shock_duration := 0.45

@export_group("Rearm")
@export var rearm_time := 20.0
@export var deploy_time := 0.5

@export_group("Visuals")
@export var model: Node3D
## Status lamp; swaps material by state and blinks.
@export var lamp: GeometryInstance3D
@export var lamp_idle_material: Material
@export var lamp_armed_material: Material
## Faint floor ring (radius 1) showing the trigger radius while armed.
@export var range_ring: Node3D
@export var blast_template: Node3D
@export var shock_template: Node3D
@export var embers: CPUParticles3D
@export var smoke: CPUParticles3D
@export var scorch: Node3D

@export_group("Sound")
@export var explosion_sound: AudioStream
@export var arm_sound: AudioStream
@export var trigger_sound: AudioStream

var _state := State.ARMING
var _timer := 0.0
var _clock := 0.0
var _blasts: AutoFxPool
var _shocks: AutoFxPool
var _boom_voice: AudioStreamPlayer3D
var _arm_voice: AudioStreamPlayer3D
var _trigger_voice: AudioStreamPlayer3D

func _on_setup() -> void:
	_blasts = AutoFxPool.new(self, blast_template, AutoFxPool.Style.BLAST)
	_shocks = AutoFxPool.new(self, shock_template, AutoFxPool.Style.RING)
	_blasts.reserve(1)
	_shocks.reserve(1)
	_boom_voice = make_voice(explosion_sound, &"mine_boom", 0.0)
	_arm_voice = make_voice(arm_sound, &"mine_arm", -10.0)
	_trigger_voice = make_voice(trigger_sound, &"mine_trigger", -4.0)
	range_ring.scale = Vector3(trigger_radius, 1.0, trigger_radius)
	_begin_arming(arm_time)

func _begin_arming(seconds: float) -> void:
	_state = State.ARMING
	_timer = seconds
	lamp.material_override = lamp_idle_material

func _tick(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	match _state:
		State.ARMING:
			_state = State.ARMED
			_timer = check_interval
			lamp.material_override = lamp_armed_material
			_arm_voice.play()
		State.ARMED:
			_timer = check_interval
			if horde.query_radius(global_position, trigger_radius, _hits) > 0:
				_state = State.TRIGGERED
				_timer = trigger_delay
				_trigger_voice.play()
		State.TRIGGERED:
			_detonate()
		State.SPENT:
			scorch.hide()
			model.scale = Vector3.ONE * 0.05
			model.show()
			_begin_arming(deploy_time + arm_time)

func _detonate() -> void:
	_state = State.SPENT
	_timer = rearm_time
	model.hide()
	range_ring.hide()
	var center := global_position + Vector3.UP * blast_height
	blast_horde(center, blast_radius, horde_damage, edge_fraction, knockback)
	blast_player(center, player_radius, player_damage, 1.0, shake)
	_shocks.spawn(global_position + Vector3.UP * 0.05, blast_radius, shock_duration)
	if not crowds_view(center, blast_radius * 0.7):
		_blasts.spawn(center, blast_radius * 0.7, blast_duration)
	embers.restart()
	smoke.restart()
	scorch.show()
	_trigger_voice.stop()
	_boom_voice.play()

func _animate(delta: float) -> void:
	_clock += delta
	_blasts.update(delta)
	_shocks.update(delta)
	match _state:
		State.ARMING:
			# Redeploy pops the tripod up, then the lamp blinks slowly while arming.
			var grow := clampf(1.0 - (_timer - arm_time) / deploy_time, 0.0, 1.0)
			model.scale = Vector3.ONE * maxf(0.05, 1.0 + 0.1 * sin(grow * PI) - pow(1.0 - grow, 3.0))
			lamp.visible = fmod(_clock, 0.5) < 0.25
			range_ring.visible = false
		State.ARMED:
			lamp.visible = fmod(_clock, 1.2) < 0.15
			range_ring.visible = true
			var pulse := 1.0 + 0.04 * sin(_clock * 3.0)
			range_ring.scale = Vector3(trigger_radius * pulse, 1.0, trigger_radius * pulse)
		State.TRIGGERED:
			lamp.visible = fmod(_clock, 0.08) < 0.05
			var swell := trigger_radius * (1.0 + 0.6 * (1.0 - _timer / trigger_delay))
			range_ring.scale = Vector3(swell, 1.0, swell)
