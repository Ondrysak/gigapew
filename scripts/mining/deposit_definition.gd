class_name DepositDefinition
extends Resource

## One resource's procedural formation, extraction budget and placement rules.
@export var resource: ResourceDefinition
## Conservative local bounds: width, height and outward depth from the wall.
@export var formation_size := Vector3(4.4, 2.6, 1.35)
@export var max_health := 320.0
@export var yield_min := 24
@export var yield_max := 36
## Relative share of placements and respawns.
@export var weight := 1.0
## Placed at every stage start before weighted picks.
@export var guaranteed := 0
## Most deposits of this kind per stage, respawns included (0 = unlimited).
@export var max_per_stage := 0
## Height band for the formation's centre; clearance also checks its full bounds.
@export var min_height := 1.5
@export var max_height := 1.8

@export_group("Pickups")
@export var pickup_mesh: Mesh
@export var pickup_scale := 1.0
