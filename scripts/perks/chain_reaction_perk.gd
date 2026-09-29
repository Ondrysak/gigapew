class_name ChainReactionPerk
extends PerkEffect

## Every enemy death may detonate: a successful roll queues a blast at the
## body that damages and shoves nearby enemies, and blast kills roll again.
## Blasts resolve from a fixed ring buffer a few per physics frame, so
## chains ripple through the crowd instead of recursing inside enemy_killed.

## Detonation chance per kill, per level.
@export var chances := PackedFloat32Array([0.15, 0.25, 0.35])
## Blast radius per level (scaled by RunState.area_multiplier).
@export var radii := PackedFloat32Array([2.5, 3.0, 3.5])
## Blast damage per level (scaled by RunState.damage_multiplier).
@export var damages := PackedFloat32Array([25.0, 35.0, 50.0])
@export var knockback := 10.0
## Blasts resolved per physics frame; the rest wait for the next frames.
@export var max_per_frame := 6
## Pending blasts kept; kills are ignored while the queue is full.
@export var queue_capacity := 64
## Hidden flash authored at radius 1, scaled to the blast radius.
@export var flash_template: Node3D
@export var flash_count := 16
@export var flash_duration := 0.35
## Flashes that would reach within this distance of the camera are skipped.
@export var min_view_clearance := 1.0

var _chance := 0.0
var _radius := 0.0
var _damage := 0.0
var _queue := PackedVector3Array()
var _head := 0
var _count := 0
var _flashes: AutoFxPool
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_queue.resize(maxi(1, queue_capacity))
	_rng.randomize()
	if flash_template != null:
		flash_template.hide()
		_flashes = AutoFxPool.new(self, flash_template, AutoFxPool.Style.BLAST)
		_flashes.reserve(flash_count)

func _setup() -> void:
	horde.enemy_killed.connect(_on_enemy_killed)

func _refresh() -> void:
	_chance = per_level(chances)
	_radius = per_level(radii)
	_damage = per_level(damages)

# Emitted synchronously from Horde.damage: only queue here, never deal damage.
func _on_enemy_killed(_definition: HordeEnemyDefinition, at: Vector3) -> void:
	if _count >= _queue.size() or _rng.randf() >= _chance:
		return
	_queue[(_head + _count) % _queue.size()] = at
	_count += 1

func _tick(_delta: float) -> void:
	# Blasts queued by this frame's own kills wait for the next frame.
	var budget := mini(_count, max_per_frame)
	if budget <= 0:
		return
	var radius := _radius * run_state.area_multiplier
	var amount := _damage * run_state.damage_multiplier
	var eye := player.camera.global_position
	for _n in budget:
		var at := _queue[_head]
		_head = (_head + 1) % _queue.size()
		_count -= 1
		horde.damage_radius(at, radius, amount, knockback)
		if _flashes != null and eye.distance_to(at) > radius + min_view_clearance:
			_flashes.spawn(at, radius, flash_duration)

func _process(delta: float) -> void:
	if _flashes != null:
		_flashes.update(delta)
