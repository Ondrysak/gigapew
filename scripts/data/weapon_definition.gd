class_name WeaponDefinition
extends Resource

@export var display_name := "Pulse"
@export var description := "Rapid precision fire"
@export var damage := 25
@export var fire_interval := 0.16
@export var range_meters := 40.0
@export_range(1, 32, 1) var pellet_count := 1
## Angle of the outer pellet ring (extra pellets form an even cone).
@export_range(0.0, 30.0) var spread_degrees := 0.0
## Random per-shot deviation of every pellet; the ring also rolls randomly.
@export_range(0.0, 10.0) var jitter_degrees := 0.0
@export var knockback := 6.5
## Extra enemies a single ray passes through (0 = stops at the first).
@export var pierce := 0
## Camera shake added per shot (0..1 trauma).
@export_range(0.0, 1.0) var screen_shake := 0.0
@export var view_scene: PackedScene

@export_group("Explosive")
## Blast radius at the end of every ray; 0 disables the blast.
@export var explosion_radius := 0.0
## Blast damage as a fraction of the shot damage.
@export var explosion_damage_fraction := 0.6
## Outward shove applied by the blast.
@export var explosion_knockback := 10.0

@export_group("Spin Up")
## Seconds of held fire to reach full cadence; 0 fires at full cadence at once.
@export var spin_up_time := 0.0
## Shot interval multiplier at zero spin; eases to 1x at full spin.
@export var spin_up_start_multiplier := 4.0
## Seconds to spin down fully after releasing fire.
@export var spin_down_time := 0.5
