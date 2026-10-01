class_name MineralDeposit
extends StaticBody3D

## Seeded formation with exact surface colliders and persistent local fractures.
signal struck(deposit: MineralDeposit)
signal fragment_mined(deposit: MineralDeposit, amount: int, position: Vector3)
signal depleted(deposit: MineralDeposit)

const CRYSTAL_SHADER := preload("res://shaders/deposit_crystal.gdshader")
const FLASH_TIME := 0.14
const WEAK_MULTIPLIER := 1.75

var definition: DepositDefinition
var health := 0.0
var total_yield := 0
var yield_emitted := 0
var last_hit_position := Vector3.ZERO
var last_hit_weak := false
var last_chunk_broken := false
var formation_size := Vector3.ZERO

var _sections: Array[Dictionary] = []
var _active: Array[int] = []
var _shape_to_fragment: Dictionary[int, int] = {}
var _remaining := 0

func configure(p_definition: DepositDefinition, seed: int, size_scale: float) -> void:
	definition = p_definition
	health = definition.max_health
	formation_size = definition.formation_size * size_scale
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	total_yield = rng.randi_range(definition.yield_min, maxi(definition.yield_min, definition.yield_max))
	var count := rng.randi_range(7, 9)
	var geometry := DepositGeometry.build(rng, count, formation_size)
	var order: Array[int] = []
	var weights := PackedFloat32Array()
	var weight_sum := 0.0
	for index in count:
		order.append(index)
		var weight := rng.randf_range(0.85, 1.15)
		weights.append(weight)
		weight_sum += weight
	for index in range(count - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := order[index]
		order[index] = order[other]
		order[other] = swap
	var allocations := PackedInt32Array()
	allocations.resize(count)
	for rank in count:
		allocations[order[rank]] = floori(float(total_yield) / float(count)) + (1 if rank < total_yield % count else 0)
	for index in count:
		var section: Dictionary = geometry[index]
		var material := ShaderMaterial.new()
		material.shader = CRYSTAL_SHADER
		material.set_shader_parameter("mineral_color", definition.resource.color)
		material.set_shader_parameter("weak_position", section["weak_position"])
		material.set_shader_parameter("weak_radius", section["weak_radius"])
		material.set_shader_parameter("formation_seed", rng.randf_range(0.0, 50.0))
		var mesh := MeshInstance3D.new()
		mesh.name = "Fragment%d" % index
		mesh.mesh = section["mesh"]
		mesh.material_override = material
		add_child(mesh)
		var collider := CollisionShape3D.new()
		collider.name = "FragmentSurface%d" % index
		collider.shape = section["shape"]
		collider.set_meta("fragment", index)
		add_child(collider)
		var maximum := definition.max_health * weights[index] / weight_sum
		section["maximum"] = maximum
		section["health"] = maximum
		section["yield"] = allocations[index]
		section["mesh"] = mesh
		section["collider"] = collider
		section["material"] = material
		section["flash"] = 0.0
		_sections.append(section)
	for owner_id in get_shape_owners():
		var collider := shape_owner_get_owner(owner_id) as CollisionShape3D
		if collider != null and collider.has_meta("fragment"):
			var index := int(collider.get_meta("fragment"))
			var shape_index := shape_owner_get_shape_index(owner_id, 0)
			_shape_to_fragment[shape_index] = index
	_remaining = count
	set_process(false)

func feedback_at(hit_position: Vector3, shape_index: int) -> Dictionary:
	var index := _fragment_at(shape_index)
	if index < 0:
		return {}
	var section := _sections[index]
	var local := to_local(hit_position)
	var weak_position: Vector3 = section["weak_position"]
	var weak_radius: float = section["weak_radius"]
	return {
		"fragment": index,
		"name": definition.resource.display_name,
		"color": definition.resource.color,
		"progress": clampf(1.0 - float(section["health"]) / float(section["maximum"]), 0.0, 1.0),
		"weak": local.distance_squared_to(weak_position) <= weak_radius * weak_radius,
		"weak_position": to_global(weak_position),
		"weak_radius": weak_radius * global_basis.get_scale().x,
		"remaining": _remaining,
		"total": _sections.size(),
		"yield_remaining": total_yield - yield_emitted,
	}

func take_mining_damage(amount: float, hit_position: Vector3, shape_index: int) -> void:
	last_chunk_broken = false
	last_hit_weak = false
	if health <= 0.0 or amount <= 0.0:
		return
	var feedback := feedback_at(hit_position, shape_index)
	if feedback.is_empty():
		return
	var index: int = feedback["fragment"]
	var section := _sections[index]
	last_hit_position = hit_position
	last_hit_weak = feedback["weak"]
	var dealt := minf(float(section["health"]), amount * (WEAK_MULTIPLIER if last_hit_weak else 1.0))
	section["health"] = maxf(0.0, float(section["health"]) - dealt)
	health = maxf(0.0, health - dealt)
	var material: ShaderMaterial = section["material"]
	material.set_shader_parameter("damage", 1.0 - float(section["health"]) / float(section["maximum"]))
	section["flash"] = FLASH_TIME
	material.set_shader_parameter("flash", 1.0)
	if not _active.has(index):
		_active.append(index)
	set_process(true)
	if float(section["health"]) <= 0.0:
		last_chunk_broken = true
		_remaining -= 1
		var mesh: MeshInstance3D = section["mesh"]
		mesh.hide()
		var collider: CollisionShape3D = section["collider"]
		collider.set_deferred("disabled", true)
		# Book the payout before signals: re-entrant hits cannot pay twice.
		yield_emitted += int(section["yield"])
	struck.emit(self)
	if last_chunk_broken:
		fragment_mined.emit(self, int(section["yield"]), hit_position)
	if _remaining == 0:
		health = 0.0
		collision_layer = 0
		depleted.emit(self)

func _fragment_at(shape_index: int) -> int:
	if _remaining <= 0:
		return -1
	# Disabled owners are retained, so physics shape indices never shift.
	var index := int(_shape_to_fragment.get(shape_index, -1))
	if index < 0:
		return -1
	return index if float(_sections[index]["health"]) > 0.0 else -1

func _process(delta: float) -> void:
	for active_index in range(_active.size() - 1, -1, -1):
		var section := _sections[_active[active_index]]
		var flash := maxf(0.0, float(section["flash"]) - delta)
		section["flash"] = flash
		var material: ShaderMaterial = section["material"]
		material.set_shader_parameter("flash", flash / FLASH_TIME)
		if flash <= 0.0:
			_active.remove_at(active_index)
	if _active.is_empty():
		set_process(false)
