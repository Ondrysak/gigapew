class_name SawWeapon
extends AutoWeapon

## Spinning blades orbit the player, cutting every enemy they pass. Each enemy
## can only be cut again after the weapon's cooldown. Overclocked, a second,
## counter-rotating ring of blades joins and every blade widens.

## Hidden blade authored flat in XZ at its real size; `blade_size` scales it.
@export var blade_template: Node3D
## Hidden unit-size spark popped where a blade cuts.
@export var spark_template: Node3D
@export var base_blades := 2
## Each listed weapon level adds one blade.
@export var extra_blade_levels := PackedInt32Array([3, 5])
@export var max_blades := 10
@export var orbit_radius := 2.5
## Radians per second around the player.
@export var orbit_speed := 2.8
## Radians per second around each blade's own axis.
@export var spin_speed := 18.0
## Blade height above the player's feet.
@export var blade_height := 0.7
@export var blade_size := 1.0
## Cutting reach around each blade centre.
@export var hit_radius := 0.5
@export var knockback := 3.0
@export var spark_size := 0.4
## Minimum seconds between sparks from one blade.
@export var spark_interval := 0.08

@export_group("Overclock")
## Outer ring radius relative to the inner one.
@export var outer_ring_scale := 1.6
@export var overclock_width := 1.35

var _blades: Array[Node3D] = []
var _sparks: AutoFxPool
## Clock time before which each enemy index cannot be cut again.
var _next_hit := PackedFloat32Array()
var _spark_ready := PackedFloat32Array()
var _hits := PackedInt32Array()
var _per_ring := 2
var _total := 2
var _angle := 0.0
var _spin := 0.0
var _clock := 0.0

func _ready() -> void:
	_hits.resize(64)
	_next_hit.resize(Horde.CAPACITY)

func _refresh() -> void:
	_per_ring = scaled_count(base_blades, extra_blade_levels, max_blades)
	_total = _per_ring * (2 if overclocked else 1)
	_grow_pool(blade_template, _blades, _total)
	if _sparks == null:
		_sparks = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
	_sparks.reserve(_total * 2)
	_spark_ready.resize(_blades.size())
	for index in range(_total, _blades.size()):
		_blades[index].hide()

func _tick(delta: float) -> void:
	_clock += delta
	_angle = fmod(_angle + orbit_speed * delta, TAU)
	_spin = fmod(_spin + spin_speed * delta, TAU)
	var feet := player.global_position
	var radius := orbit_radius * sqrt(area_scale())
	var reach := hit_radius * sqrt(area_scale()) * (overclock_width if overclocked else 1.0)
	var width := blade_size * (overclock_width if overclocked else 1.0)
	var frame := Basis(Vector3.UP, _spin).scaled(Vector3.ONE * width)
	var amount := damage_amount()
	var rest := cooldown_time()
	var y := feet.y - 0.9 + blade_height
	for index in range(_total):
		var outer := index >= _per_ring
		var slot := index - (_per_ring if outer else 0)
		var angle := TAU * float(slot) / float(_per_ring)
		var ring_radius := radius
		if outer:
			# Counter-rotating and offset half a step so the rings interleave.
			angle += -_angle * 0.8 + PI / float(_per_ring)
			ring_radius *= outer_ring_scale
		else:
			angle += _angle
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var at := Vector3(feet.x, y, feet.z) + direction * ring_radius
		_blades[index].global_transform = Transform3D(frame, at)
		_blades[index].show()
		# Cut along the direction of travel, flinging enemies outward.
		var tangent := Vector3(-direction.z, 0.0, direction.x) * (-1.0 if outer else 1.0)
		var push := (tangent + direction).normalized() * knockback
		var found := horde.query_radius(at, reach, _hits)
		for n in range(found):
			var enemy := _hits[n]
			if _next_hit[enemy] > _clock:
				continue
			_next_hit[enemy] = _clock + rest
			horde.damage(enemy, amount, push)
			if _spark_ready[index] <= _clock:
				_spark_ready[index] = _clock + spark_interval
				_sparks.spawn(horde.enemy_position(enemy), spark_size, 0.12, _spin)

func _process(delta: float) -> void:
	if _sparks != null:
		_sparks.update(delta)
