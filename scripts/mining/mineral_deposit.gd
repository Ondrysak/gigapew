class_name MineralDeposit
extends StaticBody3D

## Seeded wall machine with exact door colliders and conserved compartment loot.
## Gold and shard deposits are banks of three fruit machines (SlotBankGeometry);
## crystal deposits are the cigarette vending machine (DepositGeometry).
signal struck(deposit: MineralDeposit)
signal fragment_mined(deposit: MineralDeposit, amount: int, position: Vector3)
signal depleted(deposit: MineralDeposit)

const FLASH_TIME := 0.14
const WEAK_MULTIPLIER := 1.75
const LAMP_SHADER := preload("res://shaders/slot_lamp.gdshader")
const LAMP_HALO_SHADER := preload("res://shaders/slot_lamp_halo.gdshader")
const CABINET_SHADER := preload("res://shaders/slot_cabinet.gdshader")
const REEL_SHADER := preload("res://shaders/slot_reels.gdshader")
const LIGHT_SHADER := preload("res://shaders/slot_lights.gdshader")
const LIGHT_HALO_SHADER := preload("res://shaders/slot_lights_halo.gdshader")
const REEL_STRIP := preload("res://assets/automat/reel_strip.png")
const GLASS := {
	&"gold": [preload("res://assets/automat/glass_gold.png"), preload("res://assets/automat/glass_gold_mask.png")],
	&"shard": [preload("res://assets/automat/glass_shard.png"), preload("res://assets/automat/glass_shard_mask.png")],
}

# Cigarette-machine bulbs and halos are shared by every cabinet; blink state is per instance.
static var _lamp_materials: Array[ShaderMaterial] = []
# Fruit machines: per theme [cabinet, lights], plus the shared reel and halo materials.
static var _slot_materials: Dictionary = {}
static var _reel_material: ShaderMaterial
static var _halo_material: ShaderMaterial

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

var _lamps: MeshInstance3D
var _dark_doors := 0
var _tampered := 0
# Every fruit-machine visual that reads the per-deposit instance uniforms.
var _slot_visuals: Array[GeometryInstance3D] = []

func configure(p_definition: DepositDefinition, seed: int, size_scale: float) -> void:
	definition = p_definition
	health = definition.max_health
	formation_size = definition.formation_size * size_scale
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	total_yield = rng.randi_range(definition.yield_min, maxi(definition.yield_min, definition.yield_max))
	var count := rng.randi_range(7, 9)
	var vending := definition.resource.id == &"crystal"
	var bank := {}
	var geometry: Array[Dictionary]
	if vending:
		geometry = DepositGeometry.build(rng, count, formation_size)
		_build_housing(count)
	else:
		bank = SlotBankGeometry.build(rng, count, formation_size)
		geometry.assign(bank["doors"])
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
		var mesh := MeshInstance3D.new()
		mesh.name = "Fragment%d" % index
		mesh.mesh = section["mesh"]
		add_child(mesh)
		if vending:
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.metallic = 0.55
			material.roughness = 0.72
			mesh.material_override = material
			section["material"] = material
			section["hinge"] = Vector3.ZERO
			section["swing"] = 0.07
			section["pull"] = 0.065
		else:
			mesh.material_override = _slot_material(definition.resource.id)[0]
			_slot_visuals.append(mesh)
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
		section["flash"] = 0.0
		_sections.append(section)
	for owner_id in get_shape_owners():
		var collider := shape_owner_get_owner(owner_id) as CollisionShape3D
		if collider != null and collider.has_meta("fragment"):
			var index := int(collider.get_meta("fragment"))
			var shape_index := shape_owner_get_shape_index(owner_id, 0)
			_shape_to_fragment[shape_index] = index
	_remaining = count
	if vending:
		_build_lamps(geometry, seed)
	else:
		_build_slot_bank(bank, seed)
	set_process(false)

func _build_housing(count: int) -> void:
	var geometry := DepositGeometry.housing(formation_size, count)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.metallic = 0.6
	material.roughness = 0.82
	var housing := MeshInstance3D.new()
	housing.name = "EmptyHousing"
	housing.mesh = geometry["mesh"]
	housing.material_override = material
	add_child(housing)
	var collider := CollisionShape3D.new()
	collider.name = "HousingSurface"
	collider.shape = geometry["shape"]
	add_child(collider)
	_label(housing, "CIGARETY", Vector3(0.0, formation_size.y * 0.41, formation_size.z * 0.52 + 0.008), formation_size.x * 0.0011, Color(0.91, 0.75, 0.35))
	_label(housing, definition.resource.display_name.to_upper() + " · PÁČ ZÁMKY", Vector3(0.0, formation_size.y * 0.32, formation_size.z * 0.52 + 0.009), formation_size.x * 0.00055, Color(0.83, 0.8, 0.68))

func _build_lamps(doors: Array[Dictionary], seed: int) -> void:
	if _lamp_materials.is_empty():
		for shader in [LAMP_SHADER, LAMP_HALO_SHADER]:
			var material := ShaderMaterial.new()
			material.shader = shader
			_lamp_materials.append(material)
	var mesh := DepositGeometry.lamps(formation_size, doors)
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, _lamp_materials[surface])
	_lamps = MeshInstance3D.new()
	_lamps.name = "Lamps"
	_lamps.mesh = mesh
	_lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Derived from the seed without consuming RNG draws: layouts and loot stay identical.
	_lamps.set_instance_shader_parameter("lamp_seed", float(posmod(seed, 997)) / 997.0)
	add_child(_lamps)

## Shared per-theme materials: [cabinet (housing + doors), lights].
static func _slot_material(theme: StringName) -> Array:
	if not _slot_materials.has(theme):
		var textures: Array = GLASS[theme]
		var cabinet := ShaderMaterial.new()
		cabinet.shader = CABINET_SHADER
		cabinet.set_shader_parameter("art", textures[0])
		cabinet.set_shader_parameter("lamp_mask", textures[1])
		var lights := ShaderMaterial.new()
		lights.shader = LIGHT_SHADER
		lights.set_shader_parameter("art", textures[0])
		_slot_materials[theme] = [cabinet, lights]
	return _slot_materials[theme]

func _build_slot_bank(bank: Dictionary, seed: int) -> void:
	var materials := _slot_material(definition.resource.id)
	if _reel_material == null:
		_reel_material = ShaderMaterial.new()
		_reel_material.shader = REEL_SHADER
		_reel_material.set_shader_parameter("strip", REEL_STRIP)
		_halo_material = ShaderMaterial.new()
		_halo_material.shader = LIGHT_HALO_SHADER
	var shell: Dictionary = bank["housing"]
	var housing := MeshInstance3D.new()
	housing.name = "EmptyHousing"
	housing.mesh = shell["mesh"]
	housing.material_override = materials[0]
	add_child(housing)
	var collider := CollisionShape3D.new()
	collider.name = "HousingSurface"
	collider.shape = shell["shape"]
	add_child(collider)
	var reels := MeshInstance3D.new()
	reels.name = "Reels"
	reels.mesh = bank["reels"]
	reels.material_override = _reel_material
	reels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(reels)
	var lights := MeshInstance3D.new()
	lights.name = "Lights"
	var light_mesh: ArrayMesh = bank["lights"]
	light_mesh.surface_set_material(0, materials[1])
	light_mesh.surface_set_material(1, _halo_material)
	lights.mesh = light_mesh
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)
	_slot_visuals.append(housing)
	_slot_visuals.append(reels)
	_slot_visuals.append(lights)
	# Derived from the seed without consuming RNG draws: layouts and loot stay identical.
	_set_slot("slot_seed", float(posmod(hash(seed), 1 << 20)))

func _set_slot(parameter: StringName, value: float) -> void:
	for visual in _slot_visuals:
		visual.set_instance_shader_parameter(parameter, value)

func _label(parent: Node3D, text: String, at: Vector3, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = pixel_size
	label.font_size = 48
	label.outline_size = 0
	label.modulate = color
	parent.add_child(label)

func feedback_at(hit_position: Vector3, shape_index: int) -> Dictionary:
	var index := _fragment_at(shape_index)
	if index < 0:
		return {}
	var section := _sections[index]
	var local := to_local(hit_position)
	var mesh: MeshInstance3D = section["mesh"]
	var weak_position: Vector3 = mesh.transform * (section["weak_position"] as Vector3)
	var weak_radius: float = section["weak_radius"]
	return {
		"fragment": index,
		"name": ("Výherní automat" if definition.resource.id == &"gold" else ("Cigaretový automat" if definition.resource.id == &"crystal" else "Jackpot")) + " · " + definition.resource.display_name,
		"color": definition.resource.color,
		"progress": clampf(1.0 - float(section["health"]) / float(section["maximum"]), 0.0, 1.0),
		"weak": local.distance_squared_to(weak_position) <= weak_radius * weak_radius,
		"weak_position": to_global(weak_position),
		"weak_radius": weak_radius * global_basis.get_scale().x,
		"remaining": _remaining,
		"total": _sections.size(),
		"yield_remaining": total_yield - yield_emitted,
	}

## One physical crowbar contact opens exactly the hit compartment.
func smash_compartment(hit_position: Vector3, shape_index: int) -> void:
	var index := _fragment_at(shape_index)
	if index < 0:
		return
	take_mining_damage(float(_sections[index]["maximum"]), hit_position, shape_index)

func take_mining_damage(amount: float, hit_position: Vector3, shape_index: int) -> void:
	last_chunk_broken = false
	last_hit_weak = false
	if get_tree().paused or health <= 0.0 or amount <= 0.0:
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
	var damage := 1.0 - float(section["health"]) / float(section["maximum"])
	var mesh: MeshInstance3D = section["mesh"]
	# The latch side swings out on its hinge before the door tears off.
	var hinge: Vector3 = section["hinge"]
	var swing := Basis(Vector3.UP, damage * float(section["swing"]))
	mesh.transform = Transform3D(swing, hinge - swing * hinge + Vector3(0.0, 0.0, damage * float(section["pull"])))
	var surface: CollisionShape3D = section["collider"]
	surface.transform = mesh.transform
	section["flash"] = FLASH_TIME
	_flash(section, 1.0)
	if (_dark_doors & (1 << index)) == 0:
		# A pried door loses its lamps and the service candle starts calling.
		_dark_doors |= 1 << index
		if _lamps != null:
			_lamps.set_instance_shader_parameter("dark_doors", float(_dark_doors))
			_lamps.set_instance_shader_parameter("tilt", 1.0)
		else:
			# The door switch halts that cabinet's game.
			_tampered |= 1 << int(section["cabinet"])
			_set_slot("dark_doors", float(_dark_doors))
			_set_slot("tampered", float(_tampered))
	if not _active.has(index):
		_active.append(index)
	set_process(true)
	if float(section["health"]) <= 0.0:
		last_chunk_broken = true
		_remaining -= 1
		mesh.hide()
		var collider: CollisionShape3D = section["collider"]
		collider.set_deferred("disabled", true)
		# Book the payout before signals: re-entrant hits cannot pay twice.
		yield_emitted += int(section["yield"])
	var opened := last_chunk_broken
	var emptied := opened and _remaining == 0
	if emptied:
		if _lamps != null:
			_lamps.set_instance_shader_parameter("out_of_order", 1.0)
		else:
			_set_slot("out_of_order", 1.0)
		health = 0.0
	struck.emit(self)
	if opened:
		fragment_mined.emit(self, int(section["yield"]), hit_position)
	if emptied:
		depleted.emit(self)

## Struck-door highlight: albedo on the vending doors, an instance uniform on fruit machines.
func _flash(section: Dictionary, amount: float) -> void:
	var material: StandardMaterial3D = section.get("material")
	if material != null:
		material.albedo_color = Color.WHITE.lerp(Color(1.25, 1.15, 0.95), amount)
	else:
		(section["mesh"] as MeshInstance3D).set_instance_shader_parameter("hit_flash", amount)

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
		_flash(section, flash / FLASH_TIME)
		if flash <= 0.0:
			_active.remove_at(active_index)
	if _active.is_empty():
		set_process(false)
