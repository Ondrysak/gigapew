class_name MomentumPerk
extends PerkEffect

## All weapons deal bonus damage while the player keeps moving fast. Speed is
## sampled every `sample_interval`; the bonus lingers for `grace` seconds after
## slowing down. One temporary RunState modifier is toggled on state changes.

## Damage bonus per level while moving (0.35 = +35%).
@export var bonuses := PackedFloat32Array([0.15, 0.25, 0.35])
## Horizontal speed (m/s) that counts as moving fast.
@export var speed_threshold := 7.5
@export var sample_interval := 0.1
@export var grace := 0.4
## Foot ring visuals parented under this perk, shown while the bonus holds.
@export var aura: Node3D
@export var spin_speed := 7.0

var _modifier: StatModifier
var _charged := false
var _sample := 0.0
var _grace_left := 0.0
var _pop := 0.0

func _ready() -> void:
	if aura != null:
		aura.hide()

func _setup() -> void:
	_modifier = StatModifier.new()
	run_state.add_temporary_modifier(_modifier)

func _refresh() -> void:
	if _charged:
		_modifier.damage_multiplier = per_level(bonuses)
		run_state.refresh_modifiers()

func _tick(delta: float) -> void:
	_sample -= delta
	if _sample > 0.0:
		return
	_sample += sample_interval
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed >= speed_threshold:
		_grace_left = grace
		if not _charged:
			_set_charged(true)
	elif _charged:
		_grace_left -= sample_interval
		if _grace_left <= 0.0:
			_set_charged(false)

func _set_charged(charged: bool) -> void:
	_charged = charged
	_modifier.damage_multiplier = per_level(bonuses) if charged else 0.0
	run_state.refresh_modifiers()
	if charged:
		_pop = 1.0

func _process(delta: float) -> void:
	if aura == null:
		return
	var shown := _charged and is_instance_valid(player) and player.active
	aura.visible = shown
	if not shown:
		return
	# The perk root rides with the player so the aura stays at its feet.
	global_position = player.global_position
	_pop = maxf(0.0, _pop - delta * 4.0)
	aura.scale = Vector3.ONE * (1.0 + _pop * 0.4)
	aura.rotation.y = fmod(aura.rotation.y + spin_speed * delta, TAU)

func _exit_tree() -> void:
	# The RunState outlives the stage; never leave it boosted.
	if _modifier != null and run_state != null:
		run_state.remove_temporary_modifier(_modifier)
