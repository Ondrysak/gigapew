class_name HazardHitbox
extends StaticBody3D

## Shootable collider of a hazard: player shots call take_hit on the collider
## they strike; this forwards them to the owning hazard.

signal hit(amount: float, at: Vector3)

func take_hit(amount: float, at: Vector3) -> void:
	hit.emit(amount, at)
