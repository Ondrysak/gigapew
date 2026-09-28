class_name MineralDeposit
extends StaticBody3D

## One placed vein, created by DepositField. Anything with
## take_mining_damage is mineable: the main gun and the MiningTool call it.
## The model shrinks, shakes and flashes as it is mined.

signal struck(deposit: MineralDeposit)
signal depleted(deposit: MineralDeposit)

const FLASH_TIME := 0.08
const SHAKE_TIME := 0.16

var definition: DepositDefinition
var health := 0.0

var _model: Node3D
var _model_scale := Vector3.ONE
var _model_position := Vector3.ZERO
var _meshes: Array[GeometryInstance3D] = []
var _flash_material: Material
var _flash := 0.0
var _shake := 0.0

## Builds collider and model; `roll` turns the model around its outward axis.
func configure(p_definition: DepositDefinition, shape: Shape3D, flash_material: Material, roll: float, size_scale: float) -> void:
	definition = p_definition
	health = definition.max_health
	_flash_material = flash_material
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, 0.0, definition.collision_size.z * 0.5 - 0.1)
	add_child(collider)
	if definition.model_scene != null:
		_model = definition.model_scene.instantiate() as Node3D
		_model.rotation.z += roll
		_model.scale *= size_scale
		_model_scale = _model.scale
		_model_position = _model.position
		add_child(_model)
		_collect_meshes(_model)
	set_process(false)

func _collect_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)

func take_mining_damage(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health -= amount
	_flash = FLASH_TIME
	_shake = SHAKE_TIME
	if _model != null:
		var remaining := clampf(health / maxf(1.0, definition.max_health), 0.0, 1.0)
		_model.scale = _model_scale * lerpf(definition.depleted_scale, 1.0, remaining)
	_set_overlay(_flash_material)
	set_process(true)
	struck.emit(self)
	if health <= 0.0:
		# Stop rays at once; the field frees the node after spilling pickups.
		collision_layer = 0
		depleted.emit(self)

func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_shake = maxf(0.0, _shake - delta)
	if _flash == 0.0:
		_set_overlay(null)
	if _model != null:
		var strength := _shake / SHAKE_TIME * 0.045
		_model.position = _model_position + Vector3(randf_range(-strength, strength), randf_range(-strength, strength), 0.0)
	if _flash == 0.0 and _shake == 0.0:
		set_process(false)

func _set_overlay(material: Material) -> void:
	for mesh in _meshes:
		if mesh.material_overlay != material:
			mesh.material_overlay = material
