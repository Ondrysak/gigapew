class_name VampiricRoundsPerk
extends PerkEffect

## Counts enemy kills from every source; each full batch of kills restores a
## little health, marked by a green pulse at the player's feet.

## Kills needed per heal, per level.
@export var kills_per_heal := PackedFloat32Array([25.0, 18.0, 12.0])
## Health restored per batch, per level.
@export var heal_amounts := PackedFloat32Array([2.0, 2.0, 3.0])
## Hidden flat ring authored at radius 1 in the XZ plane.
@export var pulse_template: Node3D
@export var pulse_size := 1.2
@export var pulse_duration := 0.45

var _kills := 0
var _threshold := 25
var _pending_heal := 0
var _pulses: AutoFxPool

func _ready() -> void:
	if pulse_template != null:
		pulse_template.hide()
		_pulses = AutoFxPool.new(self, pulse_template, AutoFxPool.Style.RING)
		_pulses.inner_scale = 0.3
		_pulses.reserve(2)

func _setup() -> void:
	horde.enemy_killed.connect(_on_enemy_killed)

func _refresh() -> void:
	_threshold = maxi(1, int(per_level(kills_per_heal)))

func _on_enemy_killed(_definition: HordeEnemyDefinition, _at: Vector3) -> void:
	_kills += 1
	if _kills >= _threshold:
		_kills -= _threshold
		_pending_heal += int(per_level(heal_amounts))

func _tick(_delta: float) -> void:
	if _pending_heal <= 0:
		return
	var amount := _pending_heal
	_pending_heal = 0
	if player.health >= player.max_health:
		return
	player.heal(amount)
	if _pulses != null:
		var at := player.global_position
		_pulses.spawn(Vector3(at.x, at.y - 0.85, at.z), pulse_size, pulse_duration)

func _process(delta: float) -> void:
	if _pulses != null:
		_pulses.update(delta)
