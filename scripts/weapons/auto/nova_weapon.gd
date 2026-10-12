class_name NovaWeapon
extends AutoWeapon

## Periodic radial pulse around the player that damages and shoves outward.
## Each extra projectile adds a weaker echo pulse shortly after. A charge ring
## gathers around the player just before each pulse. Overclocked, a second,
## wider ring collapses afterwards and drags the crowd back in.

## Hidden floor ring authored with radius 1 in the XZ plane.
@export var ring_template: Node3D
## Hidden floor ring (radius 1) shown gathering inward before a pulse.
@export var charge_template: Node3D
## Hidden floor ring (radius 1) for the overclock implosion.
@export var implode_template: Node3D
@export var base_radius := 4.5
## Fractional radius gain per level above 1.
@export var radius_per_level := 0.1
@export var knockback := 7.0
@export var ring_duration := 0.4
@export var ring_start_scale := 0.2
@export var ring_height := 0.06
@export var echo_delay := 0.3
@export var echo_damage_scale := 0.6
## Seconds the charge ring gathers before each main pulse.
@export var charge_time := 0.35

@export_group("Overclock")
@export var implode_delay := 0.5
## Implosion reach relative to the pulse radius.
@export var implode_reach := 1.35
@export var implode_damage_scale := 0.8
@export var pull_strength := 9.0
@export var implode_duration := 0.3

var _rings: AutoFxPool
var _implodes: AutoFxPool
var _charge: Node3D
var _hits := PackedInt32Array()
var _timer := 0.0
var _echoes_left := 0
var _echo_timer := 0.0
var _implode_timer := 0.0

func _ready() -> void:
	_hits.resize(512)
	_charge = charge_template.duplicate() as Node3D
	add_child(_charge)
	_charge.top_level = true
	_charge.hide()

func _refresh() -> void:
	if _rings == null:
		_rings = AutoFxPool.new(self, ring_template, AutoFxPool.Style.RING)
		_implodes = AutoFxPool.new(self, implode_template, AutoFxPool.Style.IMPLODE)
	_rings.inner_scale = ring_start_scale
	_rings.reserve(1 + extra_projectiles())
	if overclocked:
		_implodes.reserve(2)
	if _timer <= 0.0:
		_timer = cooldown_time() * 0.5

func pulse_radius() -> float:
	return base_radius * (1.0 + radius_per_level * (level - 1)) * area_scale()

func _tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer += cooldown_time()
		_pulse(1.0)
		play_cue()
		_echoes_left = extra_projectiles()
		_echo_timer = echo_delay
		_implode_timer = implode_delay if overclocked else 0.0
	elif _echoes_left > 0:
		_echo_timer -= delta
		if _echo_timer <= 0.0:
			_echoes_left -= 1
			_echo_timer = echo_delay
			_pulse(echo_damage_scale)
	if _implode_timer > 0.0:
		_implode_timer -= delta
		if _implode_timer <= 0.0:
			_implode()

func _pulse(strength: float) -> void:
	var center := player.global_position
	var radius := pulse_radius()
	horde.damage_radius(center, radius, damage_amount() * strength, knockback * strength)
	_rings.spawn(Vector3(center.x, horde.ground_height(Vector2(center.x, center.z)) + ring_height, center.z), radius, ring_duration)

func _implode() -> void:
	var center := player.global_position
	var radius := pulse_radius() * implode_reach
	var amount := damage_amount() * implode_damage_scale
	var found := horde.query_radius(center, radius, _hits)
	for n in range(found):
		var index := _hits[n]
		var offset := horde.enemy_position(index) - center
		offset.y = 0.0
		var distance := offset.length()
		var pull := Vector3.ZERO
		if distance > 0.5:
			# Farther enemies are yanked harder so the crowd bunches up.
			pull = -offset / distance * pull_strength * clampf(distance / radius, 0.35, 1.0)
		horde.damage(index, amount, pull)
	_implodes.spawn(Vector3(center.x, horde.ground_height(Vector2(center.x, center.z)) + ring_height, center.z), radius, implode_duration)
	play_cue()

func _process(delta: float) -> void:
	if _rings == null:
		return
	_rings.update(delta)
	_implodes.update(delta)
	var charging := run_state != null and is_instance_valid(player) and player.active and _timer < charge_time
	if not charging:
		_charge.hide()
		return
	# Gathers inward from the pulse radius so each blast is readable ahead of time.
	var progress := clampf(1.0 - _timer / charge_time, 0.0, 1.0)
	var size := pulse_radius() * lerpf(1.0, 0.3, progress * progress)
	var at := player.global_position
	_charge.global_position = Vector3(at.x, horde.ground_height(Vector2(at.x, at.z)) + ring_height, at.z)
	_charge.scale = Vector3(size, 0.4 + progress * 0.6, size)
	_charge.show()
