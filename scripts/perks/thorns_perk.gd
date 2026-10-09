class_name ThornsPerk
extends PerkEffect

## Enemies pressing against the player are pricked every `interval` seconds
## and shoved outward. Losing health also triggers a stronger retaliation
## burst around the player on the next physics frame.
## Both pulses are non-directional area effects, so they bypass front plating.

@export var interval := 0.35
## Player capsule radius; the touch range reaches `touch_reach` beyond it.
@export var player_radius := 0.35
@export var touch_reach := 1.0
## Contact damage per level (scaled by RunState.damage_multiplier).
@export var damages := PackedFloat32Array([8.0, 14.0, 22.0])
@export var knockback := 8.0
@export var retaliate_radius := 2.5
## Retaliation damage relative to the contact damage.
@export var retaliate_scale := 2.0
@export var retaliate_knockback := 14.0
## Hidden spiky floor ring authored at radius 1 in the XZ plane.
@export var ring_template: Node3D
@export var ring_duration := 0.3
## Minimum seconds between contact rings (retaliation always shows).
@export var ring_interval := 0.3

var _damage := 0.0
var _timer := 0.0
var _last_health := 0
var _retaliate := false
var _ring_cooldown := 0.0
var _rings: AutoFxPool

func _ready() -> void:
	if ring_template != null:
		ring_template.hide()
		_rings = AutoFxPool.new(self, ring_template, AutoFxPool.Style.RING)
		_rings.inner_scale = 0.5
		_rings.reserve(4)

func _setup() -> void:
	_last_health = player.health
	_timer = interval
	player.health_changed.connect(_on_health_changed)

func _refresh() -> void:
	_damage = per_level(damages)

func _on_health_changed(current: int, _maximum: int) -> void:
	if current < _last_health and current > 0:
		_retaliate = true
	_last_health = current

func _tick(delta: float) -> void:
	_ring_cooldown -= delta
	var center := player.global_position
	var amount := _damage * run_state.damage_multiplier
	if _retaliate:
		_retaliate = false
		horde.damage_radius(center, retaliate_radius, amount * retaliate_scale, retaliate_knockback)
		_show_ring(center, retaliate_radius)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer += interval
	var reach := player_radius + touch_reach
	if horde.damage_radius(center, reach, amount, knockback) > 0 and _ring_cooldown <= 0.0:
		_show_ring(center, reach)

func _show_ring(center: Vector3, size: float) -> void:
	if _rings == null:
		return
	_ring_cooldown = ring_interval
	_rings.spawn(Vector3(center.x, center.y - 0.85, center.z), size, ring_duration, randf() * TAU)

func _process(delta: float) -> void:
	if _rings != null:
		_rings.update(delta)
