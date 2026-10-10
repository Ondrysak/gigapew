class_name PulseBarrier
extends ActiveAbility

## Source-owned temporary immunity plus an immediate close-range repelling pulse.
## Removing this barrier never clears protection granted by another skill.
@export var duration := 1.6
@export var pulse_radius := 4.5
@export var pulse_damage := 28.0
@export var pulse_knockback := 20.0
@export var shield: Node3D
@export var pulse: Node3D
@export var pulse_duration := 0.45

var _remaining := 0.0
var _pulse_age := -1.0

func _ready() -> void:
	super()
	if shield != null:
		shield.hide()
	if pulse != null:
		pulse.top_level = true
		pulse.hide()

func is_ready() -> bool:
	return super() and _remaining <= 0.0

func _activate() -> bool:
	_remaining = duration * duration_scale()
	player.set_ability_protection(self, true)
	if horde != null:
		# Combo COLLAPSE: the barrier's pulse detonates the player's nearby well.
		var well := player.active_gravity_well()
		if well != null and well.in_collapse_reach(player.global_position):
			well.collapse()
			player.announce_combo(&"collapse")
		blast(player.global_position, pulse_radius, pulse_damage * damage_scale(), pulse_knockback)
	if shield != null:
		shield.show()
	if pulse != null:
		pulse.global_position = player.global_position - Vector3.UP * 0.8
		pulse.scale = Vector3.ONE * 0.3
		pulse.show()
	_pulse_age = 0.0
	player.add_shake(0.2)
	return true

func _ability_physics(delta: float) -> void:
	if _remaining > 0.0:
		_remaining -= delta
		if _remaining <= 0.0:
			_finish()

func _process(delta: float) -> void:
	if not effects_allowed() or get_tree().paused:
		return
	if shield != null and _remaining > 0.0:
		var fade := minf(1.0, _remaining / 0.25)
		shield.scale = Vector3.ONE * fade * (1.0 + sin(effect_time() * 12.0) * 0.04)
		shield.rotation.y = fmod(shield.rotation.y + delta * 1.2, TAU)
	if _pulse_age < 0.0 or pulse == null:
		return
	_pulse_age += delta
	if _pulse_age >= pulse_duration:
		_pulse_age = -1.0
		pulse.hide()
		return
	var t := _pulse_age / pulse_duration
	var radius := lerpf(0.3, pulse_radius, 1.0 - pow(1.0 - t, 3.0))
	pulse.scale = Vector3(radius, maxf(0.05, 1.0 - t), radius)

func _finish() -> void:
	_remaining = 0.0
	if is_instance_valid(player):
		player.set_ability_protection(self, false)
	if shield != null:
		shield.hide()

func _cancel_effects() -> void:
	_finish()
	_pulse_age = -1.0

func _exit_tree() -> void:
	_finish()
