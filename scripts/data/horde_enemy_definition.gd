class_name HordeEnemyDefinition
extends Resource

## Gameplay data for one horde enemy type. Enemies are simulated in bulk by
## Horde; `model_scene` is baked once into a shared mesh for batched drawing.

## THROWER lobs a parryable bottle at the spot the player stood; BOUNCER is a
## heavy body that physically blocks the player and shoves after a windup;
## HYPE hangs back and speeds up allies in its aura until it dies or they leave.
enum Behavior { SWARM, RANGED, CHARGER, RUNNER, CARRIER, THROWER, BOUNCER, HYPE }
enum Faction { MACHINE, FLESH }

@export var display_name := "Grunt"
@export var behavior := Behavior.SWARM
@export var max_health := 20.0
@export var speed := 4.0
## Horizontal body radius for crowding and hits.
@export var radius := 0.4
## Vertical hit extent above the floor.
@export var height := 1.4
## Knockback is divided by mass.
@export var mass := 1.0
## Damage contributed per contact tick while touching the player.
@export var contact_damage := 2.0
@export var xp_value := 1
@export var is_boss := false

@export_group("Weak Spot")
## Head or exposed core in model-space metres, before model_scale and yaw.
@export var weak_spot_offset := Vector3(0.0, 1.15, 0.0)
## A forgiving sphere around the visible feature; zero disables precision hits.
@export_range(0.0, 2.0) var weak_spot_radius := 0.22

@export_group("Front Plate")
## Direct bullets, beams, blades and contact attacks only. Splash, conduction
## secondary effects, environmental areas and burn ticks bypass this plate.
@export var front_armored := false
@export_range(0.0, 1.0) var front_damage_scale := 0.25
## Half-angle of the protected front arc; flanks take full damage.
@export_range(0.0, 89.0) var front_half_angle_degrees := 60.0
## Hard yaw speed limit in radians/sec; zero retains ordinary crowd turning.
@export_range(0.0, 8.0) var turn_speed := 0.0
## Precision on plated roles requires approaching the visible rear core.
@export_range(0.0, 89.0) var rear_precision_half_angle_degrees := 60.0

@export_group("Ranged")
@export var preferred_range := 12.0
@export var attack_range := 22.0
@export var attack_cooldown := 3.0
@export var telegraph_duration := 0.6
@export var projectile_damage := 4.0
@export var projectile_speed := 9.0

@export_group("Charger")
@export var charge_range := 10.0
@export var charge_speed := 14.0
@export var charge_duration := 0.6
## Committed attacks leave a real stationary punish window.
@export var recovery_duration := 0.9

@export_group("Bouncer")
## Horizontal velocity given to the player by a landed shove (m/s).
@export var shove_impulse := 13.0

@export_group("Hype")
## Allies within this radius of a living hype man move and attack faster.
@export var aura_radius := 7.0


@export_group("Faction")
## Selects hit/death effects: machines burst into sparks and debris, flesh into splatter.
@export var faction := Faction.MACHINE
## Tints the faction's hit/death effects.
@export var fx_color := Color(1.0, 0.7, 0.25)

@export_group("Presentation")
## Node3D whose MeshInstance3D descendants carry StandardMaterial3D materials
## (flat colours or albedo/normal/ORM textures). Faces -Z; floor at y=0. Baked
## into one multi-surface mesh at stage start. For animated enemies this is the
## rest mesh exported by tools/vat/bake_vat.py (its UV2 addresses the VAT columns).
@export var model_scene: PackedScene
@export var model_scale := 1.0
@export var bob_amplitude := 0.05
@export var bob_speed := 6.0
## Procedural side-to-side lean (radians) at bob_speed; for creatures whose
## baked clips barely move.
@export var sway_amplitude := 0.0
@export var flash_color := Color(1.0, 0.92, 0.8)
@export var telegraph_color := Color(1.0, 0.3, 0.05)
## Multiplies the model's albedo (faction palette / boss tint).
@export var tint := Color.WHITE
## Fresnel rim glow that keeps silhouettes readable in dark arenas; alpha is strength.
@export var rim_color := Color(0.0, 0.0, 0.0, 0.0)

@export_group("Street Wear")
## Layout (columns, rows) of a face atlas on the surface that has an albedo texture;
## Vector2i.ONE means the texture is not an atlas. Each enemy shows one of `face_count`
## cells starting at `face_first`, chosen from its random per-instance phase.
@export var face_atlas := Vector2i.ONE
@export var face_first := 0
@export var face_count := 1
## 0..1 dirt: mud up the legs, stains and darkening, in the model's own space.
@export_range(0.0, 1.0) var grime := 0.0

@export_group("Animation")
## Baked skeletal clips; null draws `model_scene` statically.
@export var vertex_animation: HordeVertexAnimation
@export var move_clip: StringName = &"move"
## Played instead of the move clip while (nearly) standing still; optional.
@export var idle_clip: StringName = &""
## Played during attack windups and charges; optional.
@export var attack_clip: StringName = &""
## Played while dying; without it the body collapses procedurally.
@export var death_clip: StringName = &""
## Ground speed (m/s, after model_scale) at which the move clip plays at its
## baked rate; gait playback follows actual speed relative to this.
@export var move_clip_speed := 4.0
## Seconds the death clip is compressed into (mass kills stay readable).
@export var death_duration := 0.6
