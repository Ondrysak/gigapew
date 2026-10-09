class_name WeaponDefinition
extends Resource

enum Kind { FIREARM, MELEE }
@export var kind := Kind.FIREARM

@export var display_name := "Pulse"
@export var description := "Rapid precision fire"
@export var damage := 25
@export_enum("Kinetic", "Fire", "Frost", "Shock") var damage_type: int = 0
## Small, temporary camera kick; player look rotation is never modified.
@export_range(0.04, 0.3, 0.01) var recoil_degrees := 0.12
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
## Pixel-art icon for HUD, shop and workshop listings.
@export var icon: Texture2D
## A finite magazine encourages rotation; holstered guns refill automatically.
@export_range(1, 200) var magazine_size := 24
@export var reload_time := 1.6
@export var secondary_scene: PackedScene

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

@export_group("Melee")
## Real forward sweep; guns retain their ray/pellet behavior.
@export_range(10.0, 180.0) var melee_arc_degrees := 100.0
@export_range(0.0, 0.5) var melee_windup := 0.06
@export_range(0.0, 2.0) var melee_stun := 0.0
