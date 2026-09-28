class_name DepositDefinition
extends Resource

## A mineable vein type for DepositField: the resource it yields, how tough it
## is, how often it appears and how it looks. Reskin by swapping model_scene
## and pickup_mesh; nothing reads node names inside the model.

@export var resource: ResourceDefinition
## Visual only: a Node3D of meshes whose origin sits on the wall surface and
## which protrudes along +Z (at most ~0.8 m). The field adds the collider.
@export var model_scene: PackedScene
## Collider box; its back face sits slightly inside the surface.
@export var collision_size := Vector3(1.0, 1.1, 0.7)
@export var max_health := 150.0
@export var yield_min := 12
@export var yield_max := 20
## Relative share of placements and respawns.
@export var weight := 1.0
## Placed at every stage start before weighted picks.
@export var guaranteed := 0
## Most deposits of this kind per stage, respawns included (0 = unlimited).
@export var max_per_stage := 0
## Model scale when almost depleted; it shrinks as it is mined.
@export_range(0.1, 1.0) var depleted_scale := 0.55
## Height band above the floor for the deposit's surface point.
@export var min_height := 0.55
@export var max_height := 2.0

@export_group("Pickups")
## Mesh of the spilled nuggets (per-instance color = resource color).
@export var pickup_mesh: Mesh
@export var pickup_scale := 1.0
