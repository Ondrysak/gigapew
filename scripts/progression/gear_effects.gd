class_name GearEffects
extends Node3D

## Primary-shot records are captured before secondary damage can recycle slots.
## All meshes, target scratch and lifetime counters are allocated only at setup.
const TRAIL_SEGMENTS := 24
const TRAIL_LIFETIME := 2.0
const TRAIL_INTERVAL := 0.25
const TRAIL_RADIUS := 1.1
const TRAIL_SPACING := 0.65
const BEAM_COUNT := 24
const MIRROR_COLOR := Color(0.45, 0.88, 1.0)
const WIRE_COLOR := Color(0.88, 0.55, 1.0)
const TRAIL_COLOR := Color(0.42, 1.0, 0.55)
const SHIELD_COLOR := Color(1.0, 0.8, 0.28)
const FIRE_COLOR := Color(1.0, 0.38, 0.1)

var salvage_shield := 0.0
var _player: ArenaPlayer
var _horde: Horde
var _state: RunState
var _query: PhysicsRayQueryParameters3D
var _wire_generation := PackedInt64Array()
var _wire_hits := PackedByteArray()
var _targets := PackedInt32Array()
var _target_generation := PackedInt64Array()
var _trail_stamp := PackedInt64Array()
var _trail_generation := PackedInt64Array()
var _tick_serial := 0
var _trail_nodes: Array[MeshInstance3D] = []
var _trail_left := PackedFloat32Array()
var _trail_at := PackedVector3Array()
var _next_trail := 0
var _trail_clock := TRAIL_INTERVAL
var _dash_spacing := 0.0
var _beams: Array[MeshInstance3D] = []
var _beam_left := PackedFloat32Array()
var _beam_kind := PackedByteArray()
var _mirror_material: StandardMaterial3D
var _wire_material: StandardMaterial3D
var _shield: MeshInstance3D
var _shield_left := 0.0
var _impact: AutoFxPool
var _blast: AutoFxPool
var _blast_ring: AutoFxPool
var _lighter_kills := 0
var _lighter_gap := 0.0
var _lighter_primed := false
var _processing_shot := false
var _burst_active := false
var _has_mirror := false
var _has_wire := false
var _has_trainers := false
var _has_gloves := false
var _has_lighter := false

func setup(player: ArenaPlayer, horde: Horde, state: RunState) -> void:
	_player = player
	_horde = horde
	_state = state
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [player.get_rid()])
	_wire_generation.resize(Horde.CAPACITY)
	_wire_generation.fill(-1)
	_wire_hits.resize(Horde.CAPACITY)
	_targets.resize(Horde.CAPACITY)
	_target_generation.resize(Horde.CAPACITY)
	_trail_stamp.resize(Horde.CAPACITY)
	_trail_generation.resize(Horde.CAPACITY)
	_trail_left.resize(TRAIL_SEGMENTS)
	_trail_at.resize(TRAIL_SEGMENTS)
	_beam_left.resize(BEAM_COUNT)
	_beam_kind.resize(BEAM_COUNT)
	_make_visuals()
	if _state != null:
		_state.gear_changed.connect(_gear_changed)
	_gear_changed()

func _gear_changed() -> void:
	_has_mirror = _owns(&"mirror")
	_has_wire = _owns(&"wire")
	_has_trainers = _owns(&"trainers")
	_has_gloves = _owns(&"gloves")
	_has_lighter = _owns(&"lighter")
	if not _has_wire:
		_wire_hits.fill(0)
		_wire_generation.fill(-1)
	if not _has_lighter:
		_lighter_kills = 0
		_lighter_gap = 0.0
		_lighter_primed = false
	if not _has_gloves:
		salvage_shield = 0.0
		_shield_left = 0.0
		_shield.hide()
	if not _has_trainers:
		_clear_trail()
	for i in BEAM_COUNT:
		if (_beam_kind[i] == 0 and not _has_mirror) or (_beam_kind[i] == 1 and not _has_wire):
			_beam_left[i] = 0.0
			_beams[i].hide()
	_player.refresh_stats()

func _owns(id: StringName) -> bool:
	return _state != null and _state.has_gear(id)

func status_text() -> String:
	var result := ""
	if salvage_shield > 0.0:
		result = "Štít z vraku: %d · %.1f s" % [ceili(salvage_shield), _shield_left]
	if _has_lighter:
		var fire := "Zapalovač: další zabití vybuchne!" if _lighter_primed else "Zapalovač: %d/8 zabití" % _lighter_kills
		result += ("  ·  " if not result.is_empty() else "") + fire
	return result

## Opening another compartment refreshes both points and duration, never stacks.
func grant_salvage_shield() -> void:
	if not _has_gloves or not _player.active:
		return
	salvage_shield = 20.0
	_shield_left = 5.0
	_shield.show()
	_impact.spawn(_player.global_position, 0.8, 0.3)

## Called only after player armor has reduced the incoming damage.
func absorb_damage(amount: int) -> int:
	if amount <= 0 or not _has_gloves or salvage_shield <= 0.0:
		return amount
	var absorbed := mini(amount, floori(salvage_shield))
	salvage_shield -= float(absorbed)
	_impact.spawn(_player.global_position, 1.0, 0.25)
	_player.add_shake(0.06)
	if salvage_shield <= 0.0:
		_shield.hide()
	return amount - absorbed

## One entry per enemy per main shot, already aggregated over shotgun pellets.
## `killed` counts defeated constituent lives; a mega remains one primary hit.
func process_primary_shot(count: int, slots: PackedInt32Array, generations: PackedInt64Array,
		positions: PackedVector3Array, amounts: PackedFloat32Array, killed: PackedByteArray,
		applied: PackedByteArray) -> void:
	if _horde == null or _processing_shot or _burst_active or not _player.active:
		return
	_processing_shot = true
	var mirrored := false
	for n in count:
		if applied[n] == 0 or amounts[n] <= 0.0:
			continue
		var slot := slots[n]
		var generation := generations[n]
		var at := positions[n]
		if _has_lighter and killed[n] != 0:
			if _lighter_primed:
				# Consume before emitting any death callbacks; explosions cannot charge it.
				_lighter_primed = false
				_lighter_kills = 0
				_lighter_gap = 0.0
				_blast.spawn(at, 3.0, 0.45)
				_blast_ring.spawn(at, 3.0, 0.5)
				_burst(at, 3.0, 50.0, slot, generation, Horde.CAPACITY, DamageType.Kind.FIRE)
			else:
				_lighter_kills += killed[n]
				_lighter_gap = 2.5
				if _lighter_kills >= 8:
					_lighter_primed = true
		if _has_wire:
			if _wire_generation[slot] != generation:
				_wire_generation[slot] = generation
				_wire_hits[slot] = 0
			_wire_hits[slot] += 1
			if _wire_hits[slot] >= 4:
				_wire_hits[slot] = 0
				_burst(at, 5.0, 25.0, slot, generation, 3, DamageType.Kind.SHOCK)
		if _has_mirror and not mirrored:
			var target := _mirror_target(at, count, slots, generations, slot, generation)
			if target >= 0:
				var target_generation := _horde.enemy_generation(target)
				var end := _horde.enemy_position(target)
				mirrored = true
				_show_beam(at, end, false)
				if _same_life(target, target_generation) and _has_mirror:
					_horde.damage_direct(target, amounts[n] * 0.4, at)
	_processing_shot = false

func _mirror_target(at: Vector3, count: int, slots: PackedInt32Array,
		generations: PackedInt64Array, source: int, source_generation: int) -> int:
	var found := _horde.query_radius(at, 6.0, _targets)
	var best := -1
	var distance := 36.0
	for i in found:
		var slot := _targets[i]
		if not _horde.is_alive(slot):
			continue
		var generation := _horde.enemy_generation(slot)
		if slot == source and generation == source_generation:
			continue
		var already_hit := false
		for n in count:
			if slots[n] == slot and generations[n] == generation:
				already_hit = true
				break
		if already_hit:
			continue
		var end := _horde.enemy_position(slot)
		var d2 := at.distance_squared_to(end)
		if d2 <= distance and _clear_path(at, end):
			best = slot
			distance = d2
	return best

## Snapshot every lifetime before the first synchronous enemy_killed callback.
## The status-free transaction prevents Horde's built-in FIRE/SHOCK extra procs.
func _burst(at: Vector3, radius: float, amount: float, source: int, generation: int,
		limit: int, kind: int, trail := false) -> void:
	if _horde == null or _burst_active:
		return
	_burst_active = true
	var count := _horde.query_radius(at, radius, _targets)
	for n in count:
		_target_generation[n] = _horde.enemy_generation(_targets[n])
	var hit := 0
	for n in count:
		if not _player.active or (trail and not _has_trainers) or (kind == DamageType.Kind.SHOCK and not _has_wire) or (kind == DamageType.Kind.FIRE and not _has_lighter):
			break
		var slot := _targets[n]
		var life := _target_generation[n]
		if not _same_life(slot, life) or (slot == source and life == generation):
			continue
		var end := _horde.enemy_position(slot)
		if at.distance_squared_to(end) > radius * radius or not _clear_path(at, end):
			continue
		if trail:
			if absf(end.y - at.y) > 1.2:
				continue
			if _trail_stamp[slot] == _tick_serial and _trail_generation[slot] == life:
				continue
			_trail_stamp[slot] = _tick_serial
			_trail_generation[slot] = life
		if kind == DamageType.Kind.SHOCK:
			_show_beam(at, end, true)
		_horde._deal_damage(slot, amount, Vector3.ZERO, kind, false)
		hit += 1
		if hit >= limit:
			break
	_burst_active = false

func _same_life(slot: int, generation: int) -> bool:
	return _horde.is_alive(slot) and _horde.enemy_generation(slot) == generation

func _clear_path(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.0001:
		return true
	_query.from = from
	_query.to = to
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()

## This API is reached by every class dash, not inferred from movement speed.
func begin_dash() -> void:
	_dash_spacing = 0.0
	if _has_trainers:
		_drop_trail(_player.global_position)

func record_dash_step(from: Vector3, to: Vector3) -> void:
	if not _has_trainers or not _player.active or not _clear_path(from, to):
		return
	var length := from.distance_to(to)
	if length < 0.001:
		return
	var offset := TRAIL_SPACING - _dash_spacing
	var dropped := 0
	while offset <= length and dropped < 8:
		_drop_trail(from.lerp(to, offset / length))
		offset += TRAIL_SPACING
		dropped += 1
	_dash_spacing = fmod(_dash_spacing + length, TRAIL_SPACING)

func _drop_trail(at: Vector3) -> void:
	# Ground-only: airborne vaults never burn enemies on the floor below them.
	_query.from = at
	_query.to = at - Vector3.UP * 1.2
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if floor_hit.is_empty():
		return
	var normal: Vector3 = floor_hit["normal"]
	if normal.y < 0.65:
		return
	var center: Vector3 = floor_hit["position"] + Vector3.UP * 0.035
	var index := _next_trail
	_next_trail = (_next_trail + 1) % TRAIL_SEGMENTS
	_trail_left[index] = TRAIL_LIFETIME
	_trail_at[index] = center + Vector3.UP * 0.65
	_trail_nodes[index].global_position = center
	_trail_nodes[index].scale = Vector3(TRAIL_RADIUS, 1.0, TRAIL_RADIUS)
	_trail_nodes[index].show()

func _clear_trail() -> void:
	_trail_left.fill(0.0)
	for node in _trail_nodes:
		node.hide()
	_trail_clock = TRAIL_INTERVAL
	_dash_spacing = 0.0

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if not _player.active:
		_clear_trail()
		salvage_shield = 0.0
		_shield.hide()
		return
	if _shield_left > 0.0:
		_shield_left = maxf(0.0, _shield_left - delta)
		if _shield_left <= 0.0:
			salvage_shield = 0.0
			_shield.hide()
	if _lighter_gap > 0.0 and not _lighter_primed:
		_lighter_gap -= delta
		if _lighter_gap <= 0.0:
			_lighter_kills = 0
	_trail_clock -= delta
	if _has_trainers and _trail_clock <= 0.0:
		_trail_clock = TRAIL_INTERVAL
		_tick_serial += 1
		for i in TRAIL_SEGMENTS:
			if _trail_left[i] > 0.0:
				_burst(_trail_at[i], TRAIL_RADIUS, 10.0, -1, -1, Horde.CAPACITY, DamageType.Kind.KINETIC, true)
	for i in TRAIL_SEGMENTS:
		if _trail_left[i] <= 0.0:
			continue
		_trail_left[i] = maxf(0.0, _trail_left[i] - delta)
		if _trail_left[i] <= 0.0:
			_trail_nodes[i].hide()
		else:
			var fade := minf(1.0, _trail_left[i] / 0.5)
			_trail_nodes[i].scale = Vector3(TRAIL_RADIUS * fade, maxf(0.05, fade), TRAIL_RADIUS * fade)

func _process(delta: float) -> void:
	if _impact == null:
		return
	_impact.update(delta)
	_blast.update(delta)
	_blast_ring.update(delta)
	for i in BEAM_COUNT:
		if _beam_left[i] <= 0.0:
			continue
		_beam_left[i] = maxf(0.0, _beam_left[i] - delta)
		if _beam_left[i] <= 0.0:
			_beams[i].hide()
	if salvage_shield > 0.0:
		_shield.rotation.y += delta * 1.8
		_shield.visible = _shield_left >= 1.0 or fmod(_shield_left, 0.2) > 0.08

func _show_beam(from: Vector3, to: Vector3, shock: bool) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var slot := 0
	for i in BEAM_COUNT:
		if _beam_left[i] <= 0.0:
			slot = i
			break
		if _beam_left[i] < _beam_left[slot]:
			slot = i
	var node := _beams[slot]
	node.global_position = from.lerp(to, 0.5)
	var direction := (to - from) / length
	node.global_basis = Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP)
	node.scale = Vector3(0.07 if shock else 0.045, 0.07 if shock else 0.045, length)
	node.material_override = _wire_material if shock else _mirror_material
	_beam_left[slot] = 0.22 if shock else 0.16
	_beam_kind[slot] = 1 if shock else 0
	node.show()

func _material(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _mesh_node(mesh: Mesh, material: Material, world_space := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = world_space
	node.hide()
	return node

func _make_visuals() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.84
	ring.outer_radius = 1.0
	ring.rings = 20
	ring.ring_segments = 6
	var trail_material := _material(TRAIL_COLOR, 0.7)
	for i in TRAIL_SEGMENTS:
		_trail_nodes.append(_mesh_node(ring, trail_material))
	_mirror_material = _material(MIRROR_COLOR)
	_wire_material = _material(WIRE_COLOR)
	var beam := BoxMesh.new()
	beam.size = Vector3.ONE
	for i in BEAM_COUNT:
		_beams.append(_mesh_node(beam, _mirror_material))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_shield = _mesh_node(ring, _material(SHIELD_COLOR, 0.8), false)
	_shield.position.y = -0.6
	_shield.scale = Vector3(0.8, 1.0, 0.8)
	var spark_template := _mesh_node(sphere, _material(SHIELD_COLOR, 0.35))
	_impact = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
	_impact.reserve(6)
	var blast_template := _mesh_node(sphere, _material(FIRE_COLOR, 0.18))
	_blast = AutoFxPool.new(self, blast_template, AutoFxPool.Style.BLAST)
	_blast.reserve(4)
	var ring_template := _mesh_node(ring, _material(FIRE_COLOR, 0.8))
	_blast_ring = AutoFxPool.new(self, ring_template, AutoFxPool.Style.RING)
	_blast_ring.reserve(4)
