class_name GearStash
extends Node3D

## Visual-only loot: no collision/nav changes to the generated sector or machines.
enum Source { QUEST, CACHE, ELITE_DROP }

const PRY_SECONDS := 2.0
const REACH := 2.6

var source: Source = Source.CACHE
var title := "KEŠULKY BUDOU"
var offer_count := 1
var pry_progress := 0.0
var claimed := false
var guards_started := false
var offers: Array[GearDefinition] = []
var _lid: MeshInstance3D
var _label: Label3D

func configure(kind: Source, heading: String) -> void:
	source = kind
	title = heading
	offer_count = 3 if source == Source.QUEST else 1

func _ready() -> void:
	var iron := _material(Color(0.12, 0.15, 0.17), 0.7)
	var rust := _material(Color(0.36, 0.19, 0.10), 0.25)
	var accent := _material(Color(1.0, 0.68, 0.22) if source == Source.QUEST else Color(0.20, 0.85, 0.75), 0.35)
	var height := 0.45 if source == Source.ELITE_DROP else 0.72
	_box(Vector3(1.0, height, 0.72), Vector3(0.0, height * 0.5 + 0.05, 0.0), rust)
	_lid = _box(Vector3(1.08, 0.10, 0.80), Vector3(0.0, height + 0.09, 0.0), iron)
	_lid.rotation.z = -0.035
	for x: float in [-0.34, 0.34]:
		_box(Vector3(0.09, height + 0.15, 0.76), Vector3(x, height * 0.5 + 0.08, 0.0), iron)
	_box(Vector3(0.24, 0.18, 0.05), Vector3(0.0, height * 0.68, -0.39), accent)
	_box(Vector3(0.45, 0.04, 0.06), Vector3(0.0, height + 0.19, 0.0), accent)
	_label = Label3D.new()
	_label.name = "StashLabel"
	_label.text = title
	_label.position.y = height + 0.75
	_label.font_size = 30
	_label.pixel_size = 0.003
	_label.modulate = Color(1.0, 0.80, 0.40) if source == Source.QUEST else Color(0.50, 1.0, 0.90)
	_label.outline_modulate = Color(0.03, 0.04, 0.05)
	_label.outline_size = 6
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

func aim_point() -> Vector3:
	return global_position + Vector3.UP * (0.45 if source == Source.ELITE_DROP else 0.64)

## Caller validates live input/range/aim. Progress is conserved when interrupted.
func advance_pry(delta: float) -> bool:
	if claimed or source == Source.ELITE_DROP:
		return false
	pry_progress = minf(PRY_SECONDS, pry_progress + maxf(0.0, delta))
	return pry_progress >= PRY_SECONDS

## Mark before emitting any UI signal, so reentrant/stale calls cannot pay twice.
func consume(revealed_offers: Array[GearDefinition]) -> bool:
	if claimed:
		return false
	claimed = true
	offers.assign(revealed_offers)
	if _lid != null:
		_lid.rotation.z = -0.30
		_lid.position.y += 0.16
	if _label != null:
		_label.text = title + " · VYBRÁNO"
		_label.modulate = Color(0.55, 0.58, 0.60)
	return true

func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance

func _material(tint: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = 0.86
	return material
