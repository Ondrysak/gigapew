class_name MiningDefense
extends Node3D

## Optional Yard defense vein: normal mineral extraction, then one earned upgrade choice.
signal reward_ready

enum State { WAITING, MINING, DEFENDING, READY, CLAIMED, CANCELLED }

const VEIN := preload("res://data/resources/deposits/gold_vein.tres")
const GRUNT := preload("res://data/enemies/robot_grunt.tres")
const RUNNER := preload("res://data/enemies/robot_runner.tres")
const SPITTER := preload("res://data/enemies/robot_spitter.tres")
const BULWARK := preload("res://data/enemies/robot_bulwark.tres")
const RESPONSE_LIMIT := 5
const PACKS := [[GRUNT, GRUNT, GRUNT, GRUNT, GRUNT], [RUNNER, RUNNER, RUNNER, RUNNER], [BULWARK, GRUNT, GRUNT, SPITTER]]

@export var display_name := "Defense vein"
@export var support_path := NodePath("World/Obstacles/CrateStackN")
@export var vein_height := 1.4
@export var vein_health := 420.0
@export var formation_seed := 7419
@export_range(0.05, 2.0) var admission_interval := 0.25
@export_range(0.1, 8.0) var pack_interval := 2.5
@export_range(1.0, 6.0) var claim_radius := 3.5

var state := State.WAITING
var deposit: MineralDeposit
## Successful admissions only; useful for encounter HUD and behavior labs.
var spawned_count := 0
var completed_packs := 0
var pack_index := 0

var _horde: Horde
var _player: ArenaPlayer
var _deposits: DepositField
var _support: StaticBody3D
var _definition: DepositDefinition
var _slots: Dictionary[int, int] = {}
var _admitted := 0
var _reservation := 0
var _timer := 0.0
var _depleted := false
var _beacon_material: StandardMaterial3D
var _meter: MeshInstance3D
var _status: Label3D
var _spawn_box := BoxShape3D.new()
var _spawn_query := PhysicsShapeQueryParameters3D.new()
var _floor_query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_build_frame()

func setup(horde: Horde, player: ArenaPlayer, _run_state: RunState, deposits: DepositField, _pickups: PickupField) -> void:
	_horde = horde
	_player = player
	_deposits = deposits
	_support = get_parent().get_node_or_null(support_path) as StaticBody3D
	_definition = VEIN.duplicate() as DepositDefinition
	_definition.formation_size = Vector3(2.6, 2.1, 1.1)
	_definition.max_health = vein_health
	# Reserve even while waiting: a full ordinary crowd cannot starve response admission.
	_reservation = horde.reserve_slots(RESPONSE_LIMIT)
	deposits.reserve_authored_space(global_position + Vector3.UP * vein_height, 4.5)
	_spawn_query.shape = _spawn_box
	_spawn_query.collision_mask = 1
	_spawn_query.exclude = [player.get_rid()]
	_floor_query.collision_mask = 1
	_floor_query.exclude = [player.get_rid()]

func progress() -> float:
	if _depleted:
		return 1.0
	return clampf(1.0 - deposit.health / _definition.max_health, 0.0, 1.0) if is_instance_valid(deposit) else 0.0

func remaining() -> float:
	return _timer if state == State.MINING or state == State.DEFENDING else 0.0

func enemies_remaining() -> int:
	var count := 0
	if is_instance_valid(_horde):
		for slot: int in _slots:
			if _horde.is_alive(slot) and _horde.enemy_generation(slot) == _slots[slot]:
				count += 1
	return count

## Only currently live response identities, never a reused unrelated slot.
func response_slots() -> PackedInt32Array:
	var result := PackedInt32Array()
	if is_instance_valid(_horde):
		for slot: int in _slots:
			if _horde.is_alive(slot) and _horde.enemy_generation(slot) == _slots[slot]:
				result.append(slot)
	return result

## Public claim also serves stage-clear escrow; proximity belongs to the E input path.
func claim_reward() -> bool:
	if state != State.READY:
		return false
	state = State.CLAIMED
	_update_frame()
	reward_ready.emit()
	return true

func cancel() -> void:
	if state == State.CANCELLED:
		return
	_release_reservation()
	state = State.CANCELLED
	if is_instance_valid(deposit):
		# An ended encounter cannot keep mining or pay late fragment signals.
		deposit.collision_layer = 0
		deposit.health = 0.0
		deposit.hide()
	set_physics_process(false)
	hide()

func _exit_tree() -> void:
	_release_reservation()

func _release_reservation() -> void:
	if _reservation > 0 and is_instance_valid(_horde):
		_horde.release_reserved(_reservation)
	_reservation = 0

func _physics_process(delta: float) -> void:
	if _horde == null or state == State.CANCELLED:
		return
	if not is_instance_valid(_player) or not _player.active:
		cancel()
		return
	if deposit == null:
		deposit = _deposits.create_authored_deposit(_definition, global_position + Vector3.UP * vein_height, global_basis.z.normalized(), _support, formation_seed)
		if deposit != null:
			deposit.struck.connect(_on_struck)
			deposit.depleted.connect(_on_depleted)
		return
	if state == State.MINING or state == State.DEFENDING:
		_prune_response()
		_timer = maxf(0.0, _timer - delta)
		if pack_index < PACKS.size():
			var pack: Array = PACKS[pack_index]
			if _admitted < pack.size() and _timer <= 0.0:
				_admit(pack[_admitted] as HordeEnemyDefinition)
				_timer = admission_interval
			if _admitted == pack.size() and _slots.is_empty():
				completed_packs += 1
				pack_index += 1
				_admitted = 0
				_timer = pack_interval
		if _depleted and completed_packs == PACKS.size():
			state = State.READY
			_release_reservation()
	_update_frame()
	if state == State.READY and Input.is_action_just_pressed(&"interact") and _player.global_position.distance_squared_to(global_position + Vector3.UP) <= claim_radius * claim_radius:
		claim_reward()

func _on_struck(_deposit: MineralDeposit) -> void:
	if state != State.WAITING or deposit.health >= _definition.max_health:
		return
	state = State.MINING
	_timer = 0.0

func _on_depleted(_deposit: MineralDeposit) -> void:
	if state == State.CANCELLED or state == State.CLAIMED:
		return
	_depleted = true
	state = State.DEFENDING

func _prune_response() -> void:
	# Five entries maximum; remove without mutating a live dictionary iterator.
	for slot: int in _slots.keys():
		if not _horde.is_alive(slot) or _horde.enemy_generation(slot) != _slots[slot]:
			_slots.erase(slot)

func _admit(definition: HordeEnemyDefinition) -> void:
	if _slots.size() >= RESPONSE_LIMIT:
		return
	if _reservation < RESPONSE_LIMIT:
		_reservation += _horde.reserve_slots(RESPONSE_LIMIT - _reservation)
	if _reservation == 0:
		return
	# All candidates are on the spawn-facing half of the vein, connected by a flat lane.
	for attempt in 15:
		var angle := -1.05 + float((spawned_count * 3 + attempt) % 15) * 0.15
		var distance := 7.0 + float(attempt % 3)
		var local := Vector3(sin(angle) * distance, 0.0, cos(angle) * distance)
		var at := to_global(local)
		var xz := Vector2(at.x, at.z)
		if not _reachable_spawn(xz, definition):
			continue
		var slot := _horde.spawn_reserved(definition, xz)
		if slot < 0:
			return
		_slots[slot] = _horde.enemy_generation(slot)
		_admitted += 1
		spawned_count += 1
		return

func _reachable_spawn(xz: Vector2, definition: HordeEnemyDefinition) -> bool:
	if _horde.is_blocked(xz, definition.radius + 0.25):
		return false
	var start := global_position + global_basis.z * 3.2
	var from := Vector2(start.x, start.z)
	# Reject cliffs/blocked lanes as well as bad endpoints; no enemies on remote decks.
	for sample in 9:
		var point := from.lerp(xz, float(sample) / 8.0)
		if _horde.is_blocked(point, definition.radius + 0.15) or absf(_horde.ground_height(point) - global_position.y) > 0.25:
			return false
	var space := get_world_3d().direct_space_state
	_floor_query.from = Vector3(xz.x, global_position.y + 0.8, xz.y)
	_floor_query.to = Vector3(xz.x, global_position.y - 0.4, xz.y)
	var floor_hit := space.intersect_ray(_floor_query)
	if floor_hit.is_empty() or (floor_hit["normal"] as Vector3).dot(Vector3.UP) < 0.9:
		return false
	var floor_position: Vector3 = floor_hit["position"]
	_spawn_box.size = Vector3(definition.radius * 2.0 + 0.2, definition.height, definition.radius * 2.0 + 0.2)
	_spawn_query.transform = Transform3D(Basis.IDENTITY, floor_position + Vector3.UP * (definition.height * 0.5 + 0.08))
	return space.intersect_shape(_spawn_query, 1).is_empty()

func _build_frame() -> void:
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.065, 0.095, 0.13)
	frame_material.metallic = 0.7
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.albedo_color = Color(0.25, 0.85, 0.95)
	_box("LeftRail", Vector3(-1.65, 1.65, 0.08), Vector3(0.18, 3.3, 0.24), frame_material)
	_box("RightRail", Vector3(1.65, 1.65, 0.08), Vector3(0.18, 3.3, 0.24), frame_material)
	_box("Header", Vector3(0.0, 3.15, 0.08), Vector3(3.5, 0.35, 0.24), frame_material)
	_box("BeaconMast", Vector3(-1.65, 4.0, 0.0), Vector3(0.09, 1.7, 0.09), frame_material)
	_box("Beacon", Vector3(-1.65, 4.85, 0.0), Vector3(0.32, 0.32, 0.32), _beacon_material)
	_box("MeterBack", Vector3(0.0, 2.84, 0.24), Vector3(2.8, 0.12, 0.05), frame_material)
	_meter = _box("ExtractionMeter", Vector3(-1.39, 2.84, 0.28), Vector3(1.0, 0.065, 0.03), _beacon_material)
	for index in 3:
		_box("ResponseLamp%d" % index, Vector3(-0.55 + index * 0.55, 3.43, 0.16), Vector3(0.25, 0.12, 0.08), _beacon_material)
	_status = Label3D.new()
	_status.name = "Status"
	_status.position = Vector3(0.0, 3.15, 0.22)
	_status.font_size = 40
	_status.pixel_size = 0.004
	_status.outline_size = 4
	add_child(_status)
	_update_frame()

func _box(node_name: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	add_child(mesh)
	return mesh

func _update_frame() -> void:
	if _status == null:
		return
	var value := progress()
	_meter.scale.x = maxf(0.01, value * 2.78)
	_meter.position.x = -1.39 + value * 1.39
	var color := Color(0.25, 0.85, 0.95)
	match state:
		State.WAITING:
			_status.text = "DEFENSE VEIN  /  MINE TO START"
		State.MINING, State.DEFENDING:
			color = Color(1.0, 0.48, 0.16)
			_status.text = "%d%% CUT  /  RESPONSE %d/3  /  %d HOSTILES" % [roundi(value * 100.0), mini(pack_index + 1, 3), enemies_remaining()]
		State.READY:
			color = Color(0.3, 1.0, 0.65)
			_status.text = "SECURED  /  [E] CHOOSE UPGRADE"
		State.CLAIMED:
			color = Color(0.25, 0.4, 0.45)
			_status.text = "SECURED  /  REWARD CLAIMED"
		State.CANCELLED:
			_status.text = "OFFLINE"
	_beacon_material.albedo_color = color
	for index in 3:
		get_node("ResponseLamp%d" % index).visible = index >= completed_packs
