class_name Horde
extends Node3D

## Data-oriented crowd of up to CAPACITY enemies. No per-enemy nodes or physics
## bodies: positions live in packed arrays on the XZ plane with a feet height
## from the world's Ground floors and Elevation decks/ramps, crowding uses a
## uniform grid, and each enemy type draws as one MultiMesh. Enemies walk up
## ramps, drop off ledges and cannot climb cliffs. Weapons query enemies
## through raycast/query_radius/nearest and damage them by index.

signal enemy_killed(definition: HordeEnemyDefinition, position: Vector3)
signal boss_spawned(definition: HordeEnemyDefinition)
signal boss_health_changed(current: float, maximum: float)
signal boss_killed
signal damage_reported(at: Vector3, amount: float, damage_type: int, critical: bool, killed: bool)
signal enemy_fused(index: int, members: int)
## One emission per intentional pinball action (kick, reflected projectile,
## explicit manual combo, prop) that killed at least one life. Ordinary primary
## damage, ambient burn/shock ticks, auto guns and external deaths never emit.
signal action_killed(members: int, position: Vector3, label: String)

const CAPACITY := 4096
const CELL := 2.0
const DEATH_TIME := 0.22
## Final fraction of an animated death spent shrinking away.
const DEATH_FADE := 0.3
## Extra distance at which melee enemies play their attack clip on the player.
const CONTACT_ANIMATION_MARGIN := 0.35
const FLASH_TIME := 0.12
const PLAYER_RADIUS := 0.4
const MAX_NEIGHBOR_CHECKS := 8
const SEPARATION := 0.45
const MAX_PROJECTILES := 512
## Enemy projectiles shrink to nothing between these camera distances (m).
const PROJECTILE_FADE_NEAR := 0.35
const PROJECTILE_FADE_FAR := 1.6
const BIG_RADIUS := 0.9
const BURN_DURATION := 2.0
const BURN_TICK := 0.5
const FROST_FACTOR := 0.55
const FROST_DURATION := 1.8
## One finite execution opportunity per surviving non-boss lifetime.
const DAZE_DURATION := 2.8
const DAZE_HEALTH_FRACTION := 0.2
const SHOCK_RADIUS := 3.5
const SHOCK_TARGETS := 3
const SHOCK_CHECKS := 96
const RADIUS_DEPTH := 8
const FUSION_MIN := 6
const FUSION_MAX := 8
const FUSION_RANGE := 2.4
const FUSION_DENSITY_TIME := 0.75
const FUSION_GROW_TIME := 0.55
const FUSION_SCALE := 1.7
const FUSION_SHOULDER := 1.2
const FUSION_SEEDS := 256
const FUSION_CHECKS := 48
const FUSION_DECK_GAP := 0.3

## combo_flags bits, read by the player before a primary hit transaction.
const FROZEN := 1
const BURNING := 2
const ELECTRIC := 4
const AIRBORNE := 8
## Frost marks follow actual FROST damage (not every slow); charge follows SHOCK.
const CHARGE_DURATION := 2.5
const AIRBORNE_CLEARANCE := 0.25
## Kick: bounded cone around the actual aim, nearest KICK_TARGETS bodies only.
const KICK_REACH := 2.4
const SLIDE_KICK_REACH := 2.9
const STOMP_RADIUS := 2.6
const KICK_COS := 0.57
const KICK_TARGETS := 6
const KICK_DAMAGE := 30.0
const SLIDE_KICK_DAMAGE := 26.0
const STOMP_DAMAGE := 40.0
const KICK_LAUNCH_SPEED := 15.0
const KICK_LIFT := 6.0
const STOMP_LIFT := 7.5
## Heavier bodies, bosses, megas and bouncers only stagger; never airborne.
const HEAVY_MASS := 2.5
const HEAVY_STAGGER := 0.9
const LAUNCH_TIME := 1.1
## Knockback decay per second while launched (ground knockback uses 7).
const LAUNCH_DECAY := 1.6
const IMPACT_MIN_SPEED := 4.0
const IMPACT_DAMAGE := 32.0
const IMPACT_CHECKS := 12
const MAX_IMPACTS := 32
const SHATTER_RADIUS := 2.6
const SHATTER_DAMAGE := 60.0
## Parried projectiles: one reflection each, swept against enemies and walls.
const REFLECT_SPEED := 26.0
const REFLECT_DAMAGE := 70.0
const REFLECT_SPLASH := 2.4
const REFLECT_LIFE := 2.0
const REFLECT_TURN := 9.0
const MAX_PARRY := 4
const BOTTLE_GRAVITY := 14.0
const BOTTLE_SPLASH := 1.8
const FLAME_BURST_RADIUS := 2.8
const FLAME_BURST_BASE := 25.0
const CONDUCTION_RADIUS := 6.0
const CONDUCTION_TARGETS := 5
const HYPE_SPEED_SCALE := 1.3
const SURGE_SPEED_SCALE := 1.6
const HYPE_DAMAGE_SCALE := 1.5
const HYPE_COOLDOWN_SCALE := 1.6
## Manual weapon combo bursts allowed per physics frame (multi-target shots).
const COMBO_BUDGET := 3
const CONDUCTION_CHECKS := 128
## Hype auras refresh every pulse and lapse BUFF_HOLD after source death/range exit.
const HYPE_PULSE := 0.2
const BUFF_HOLD := 0.3
const HYPE_TARGETS := 48
const SHOT_LOBBED := 1
const SHOT_REFLECTED := 2
const SHOT_HOMING := 4
const SHOT_SPIT_COLOR := Color(1.0, 0.55, 0.12)
const SHOT_BOTTLE_COLOR := Color(0.25, 0.85, 0.3)
const SHOT_REFLECT_COLOR := Color(0.35, 0.95, 1.0)

enum { FREE, ALIVE, DYING }
enum Mode { SEEK, WINDUP, CHARGE, RECOVER }
enum Impact { WALL, BODY }

@export var enemy_shader: Shader
## Used for definitions with a vertex_animation (see HordeVertexAnimation).
@export var animated_enemy_shader: Shader
## HordeFx scene instanced at setup for hit sparks and death bursts; optional.
@export var fx_scene: PackedScene
@export var projectile_mesh: Mesh
@export var projectile_material: Material
@export var projectile_radius := 0.22
## Crowd contact hurts in ticks: every contact_tick seconds the player takes
## the summed contact_damage of touching enemies, capped at contact_cap.
@export var contact_tick := 0.5
@export var contact_cap := 4.0
## Hitscan forgiveness above each enemy's height so level shots at eye height
## still connect with short enemies.
@export var hit_headroom := 0.6
var _largest_radius := BIG_RADIUS

var alive_count := 0
## Ordinary lives represented by live bodies; fusion never frees spawn pressure.
var population_count := 0
var target: ArenaPlayer

var _defs: Array[HordeEnemyDefinition] = []
var _type_of: Dictionary = {}
var _t_behavior := PackedInt32Array()
var _t_speed := PackedFloat32Array()
var _t_radius := PackedFloat32Array()
var _t_height := PackedFloat32Array()
var _t_mass := PackedFloat32Array()
var _t_contact := PackedFloat32Array()
var _t_scale := PackedFloat32Array()
var _t_boss := PackedByteArray()
var _t_weak_offset := PackedVector3Array()
var _t_weak_radius_squared := PackedFloat32Array()
var _t_weak_top := PackedFloat32Array()
var _t_front_scale := PackedFloat32Array()
var _t_front_cos := PackedFloat32Array()
var _t_rear_cos := PackedFloat32Array()
var _t_turn_speed := PackedFloat32Array()
var _t_armored := PackedByteArray()
var _armor_renderers: Array[MultiMeshInstance3D] = []
var _armor_buffers: Array[PackedFloat32Array] = []
var _renderers: Array[MultiMeshInstance3D] = []
var _buffers: Array[PackedFloat32Array] = []
# One bounded native appendage batch per eligible species, never per-enemy nodes.
var _anatomy_renderers: Array[MultiMeshInstance3D] = []
var _anatomy_buffers: Array[PackedFloat32Array] = []
var _anatomy_slot_instance := PackedInt32Array()
var _anatomy_intensity := 0.65
const ANATOMY_CAPACITY := CAPACITY / 6

# Rendering: per-type animation setup (clip ids index the _clip_* arrays; -1 = none).
var _t_stride := PackedInt32Array()
var _t_death_time := PackedFloat32Array()
var _t_move_ref := PackedFloat32Array()
var _t_clip_move := PackedInt32Array()
var _t_clip_idle := PackedInt32Array()
var _t_clip_attack := PackedInt32Array()
var _t_clip_death := PackedInt32Array()
var _clip_count := PackedFloat32Array()
var _clip_fps := PackedFloat32Array()
var _clip_start := PackedFloat32Array()
var _clip_loop := PackedFloat32Array()
# Rendering: per-slot animation playback.
var _anim_clip := PackedInt32Array()
var _anim_frame := PackedFloat32Array()
var _anim_speed := PackedFloat32Array()
var _anim_prev := PackedVector2Array()
var _fx: HordeFx

var _state := PackedInt32Array()
var _type := PackedInt32Array()
var _mode := PackedInt32Array()
var _pos := PackedVector2Array()
var _knock := PackedVector2Array()
var _aim := PackedVector2Array()
var _attack_target := PackedVector3Array()
var _has_lane := PackedByteArray()
var _lane_query := PhysicsRayQueryParameters3D.new()
var _lane_excluded := RID()
var _yaw := PackedFloat32Array()
var _hp := PackedFloat32Array()
var _max_hp := PackedFloat32Array()
var _flash := PackedFloat32Array()
var _timer := PackedFloat32Array()
var _cooldown := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _death := PackedFloat32Array()
## Movement factor while slowed (1 = normal) and seconds of slow remaining.
var _slow := PackedFloat32Array()
var _slow_time := PackedFloat32Array()
## Strongest burn wins; refreshes extend duration without postponing its tick.
var _burn_time := PackedFloat32Array()
var _burn_tick := PackedFloat32Array()
var _burn_damage := PackedFloat32Array()
var _exposed := PackedFloat32Array()
var _stunned := PackedFloat32Array()
var _daze_time := PackedFloat32Array()
var _daze_used := PackedByteArray()
var _life_hp := PackedFloat32Array()
var _finisher_hits := PackedInt32Array()
var _finisher_distances := PackedFloat32Array()
## Seconds of frost mark (actual FROST damage) and electric charge (SHOCK damage).
var _frost_time := PackedFloat32Array()
var _charge_time := PackedFloat32Array()
## Hype aura: remaining hold and strongest level (1 = hyped, 2 = surge).
var _buff_time := PackedFloat32Array()
var _buff_pulse := PackedInt32Array()
var _hype_pulses := 0
var _buff_level := PackedInt32Array()
var _kick_buffer := PackedInt32Array()
## Kick flight: remaining launch time and whether the body was frozen when kicked.
var _launch_time := PackedFloat32Array()
var _launch_frozen := PackedByteArray()
var _stamp := PackedInt32Array()
var _cell_of := PackedInt32Array()
var _query_id := 0

var _generation := PackedInt64Array()
var _fusion_allowed := PackedByteArray()
var _members := PackedInt32Array()
var _body := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _height := PackedFloat32Array()
var _mass := PackedFloat32Array()
var _gait := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _dense_since := PackedFloat32Array()
var _dense_last := PackedFloat32Array()
var _dense_count := PackedInt32Array()
var _dense_members := PackedInt32Array()
var _dense_generation := PackedInt64Array()
var _fusion_clock := 0.0
var _fusion_cursor := 0
var _fusion_times := PackedFloat32Array()
var _fusion_time_cursor := 0
var _fusion_events := PackedInt32Array()
var _fusion_event_generation := PackedInt64Array()
var _reserved_slots := 0
var _active := PackedInt32Array()
var _active_count := 0
var _dying := PackedInt32Array()
var _dying_count := 0
var _free := PackedInt32Array()
var _free_count := 0
var _big := PackedInt32Array()
var _boss_index := -1
## One stage-authored boss controller; the bulk horde keeps its normal simulation.
var _boss_controlled := false
var _boss_velocity := Vector2.ZERO
var _boss_facing := Vector2.ZERO
var _boss_recovering := false

var _area := Rect2()
## Walkable XZ rectangle enemies are confined to (read-only after setup).
var play_area: Rect2:
	get:
		return _area
## Slot of the living boss, or -1.
var boss_index: int:
	get:
		return _boss_index
var _grid_w := 1
var _grid_h := 1
var _cells := 1
var _cell_start := PackedInt32Array()
var _cell_cursor := PackedInt32Array()
var _cell_items := PackedInt32Array()

# Static obstacles: circles and axis-aligned boxes, bucketed per grid cell.
var _obstacle_center := PackedVector2Array()
var _obstacle_half := PackedVector2Array()
var _obstacle_circle := PackedByteArray()
var _obstacle_bottom := PackedFloat32Array()
var _obstacle_top := PackedFloat32Array()
## Local vertical interval of a pitched box follows its top/bottom planes.
## Flat obstacles use zero slope; do not stretch a stair roof's lowest corner
## across its whole footprint and accidentally close the upper stair run.
var _obstacle_height_slope := PackedVector2Array()
var _cell_obstacle_start := PackedInt32Array()
var _cell_obstacle_items := PackedInt32Array()

var _contact_timer := 0.0
## Pathfinding shared by every enemy; rebuilt every FLOW_INTERVAL seconds.
var _flow := HordeFlowField.new()
var _flow_timer := 0.0
const FLOW_INTERVAL := 0.2
## Within this distance enemies ignore the flow field and close in directly.
const DIRECT_RANGE := 5.0
## Heightfield sample spacing (m), built from Ground and Elevation box top faces.
const HEIGHT_STEP := 0.5
## Tallest step enemies walk up; higher steps are cliffs they can only drop off.
const CLIMB := 0.3
## Extra rise allowed per metre travelled, so ramps up to ~30 degrees stay walkable.
const CLIMB_SLOPE := 0.6
const FALL_GRAVITY := 22.0
## Vertical gap beyond which an enemy counts as on another level than the player.
const LEVEL_GAP := 1.0
## With the player this close below, enemies walk straight off ledges at them.
const DROP_RANGE := 14.0
var _rng := RandomNumberGenerator.new()
# Ground height per HEIGHT_STEP sample (row-major), and per-slot feet height.
var _heights := PackedFloat32Array()
var _heights_w := 1
var _heights_h := 1
## Horde cells whose ground and neighbourhood are all at floor level (fast path).
var _cell_flat := PackedByteArray()
var _y := PackedFloat32Array()
var _vy := PackedFloat32Array()
# Ground height of the last _walkable result (avoids a second lookup).
var _step_ground := 0.0
var _cell_center := PackedVector2Array()
var _layout_roofed := PackedByteArray()
var _layout_origin := Vector2.ZERO
var _layout_width := 0
var _layout_height := 0
var _layout_cell_size := ProceduralWorld.CELL_SIZE

var _shot_pos := PackedVector3Array()
var _shot_vel := PackedVector3Array()
var _shot_life := PackedFloat32Array()
var _shot_damage := PackedFloat32Array()
var _shot_count := 0
var _shot_renderer: MultiMeshInstance3D
var _shot_buffer := PackedFloat32Array()
var _shot_flags := PackedByteArray()
var _shot_splash := PackedFloat32Array()
var _shot_target := PackedInt32Array()
var _shot_target_generation := PackedInt64Array()
var _shot_query := PhysicsRayQueryParameters3D.new()
var _shot_excluded := RID()
var _sweep_hits := PackedInt32Array()
var _sweep_distances := PackedFloat32Array()
# Reflected-projectile impacts resolve after the shot list is compacted.
var _shot_impact_pos := PackedVector3Array()
var _shot_impact_origin := PackedVector3Array()
var _shot_impact_slot := PackedInt32Array()
var _shot_impact_generation := PackedInt64Array()
var _shot_impact_damage := PackedFloat32Array()
var _shot_impact_splash := PackedFloat32Array()
var _shot_impact_collider: Array[Object] = []
var _shot_impact_count := 0

var _candidate_index := PackedInt32Array()
var _candidate_t := PackedFloat32Array()
## Each synchronous splash owns its target snapshot until its callbacks return.
var _radius_buffers: Array[PackedInt32Array] = []
var _radius_depth := 0
## Shock never uses the splash/raycast/caller scratch arrays.
var _chain_index := PackedInt32Array()
var _radius_generations: Array[PackedInt64Array] = []
var _chain_distance := PackedFloat32Array()

# Action ledger: kills inside an open action scope are credited exactly once to
# the innermost scope. Signal callbacks run suspended so their deaths never count.
var _action_depth := 0
var _action_members := 0
var _action_suspend := 0
var _action_last_kill := Vector3.ZERO
var _kick_index := PackedInt32Array()
var _kick_generation := PackedInt64Array()
var _kick_flags := PackedInt32Array()
var _kick_distance := PackedFloat32Array()
var _conduct_index := PackedInt32Array()
var _conduct_distance := PackedFloat32Array()
var _conduct_generation := PackedInt64Array()
# Launch impacts found during the movement loop resolve after it, bounded per frame.
var _impact_kind := PackedInt32Array()
var _impact_slot := PackedInt32Array()
var _impact_generation := PackedInt64Array()
var _impact_other := PackedInt32Array()
var _impact_other_generation := PackedInt64Array()
var _impact_velocity := PackedVector2Array()
var _impact_count := 0
var _hype_timer := 0.0
var _combo_budget := COMBO_BUDGET
var _aura_buffer := PackedInt32Array()

## Ground supplies explicit floors; arenas without it retain the authored y=0 floor.
## Elevation adds deck and ramp top faces to that heightfield.
func setup(definitions: Array[HordeEnemyDefinition], area: Rect2, obstacles: Node, player: ArenaPlayer, elevation: Node = null, ground: Node = null) -> void:
	target = player
	_area = area
	_rng.randomize()
	# Packed arrays are values: resize each member directly, never via a temp list.
	_state.resize(CAPACITY)
	_type.resize(CAPACITY)
	_mode.resize(CAPACITY)
	_attack_target.resize(CAPACITY)
	_has_lane.resize(CAPACITY)
	_has_lane.fill(0)
	_stamp.resize(CAPACITY)
	_cell_of.resize(CAPACITY)
	_state.fill(FREE)
	_stamp.fill(0)
	_generation.resize(CAPACITY)
	_generation.fill(0)
	_reserved_slots = 0
	_fusion_allowed.resize(CAPACITY)
	_fusion_allowed.fill(0)
	_members.resize(CAPACITY)
	_members.fill(1)
	_body.resize(CAPACITY)
	_body.fill(1.0)
	_radius.resize(CAPACITY)
	_height.resize(CAPACITY)
	_mass.resize(CAPACITY)
	_gait.resize(CAPACITY)
	_grow.resize(CAPACITY)
	_dense_since.resize(CAPACITY)
	_dense_last.resize(CAPACITY)
	_dense_count.resize(CAPACITY)
	_dense_count.fill(0)
	_dense_members.resize(CAPACITY * FUSION_MAX)
	_dense_generation.resize(CAPACITY * FUSION_MAX)
	_fusion_events.resize(4)
	_fusion_event_generation.resize(4)
	_fusion_times.resize(4)
	_fusion_times.fill(-0.5)
	_fusion_clock = 0.0
	_fusion_cursor = 0
	_fusion_time_cursor = 0
	_yaw.resize(CAPACITY)
	_hp.resize(CAPACITY)
	_max_hp.resize(CAPACITY)
	_flash.resize(CAPACITY)
	_timer.resize(CAPACITY)
	_cooldown.resize(CAPACITY)
	_phase.resize(CAPACITY)
	_death.resize(CAPACITY)
	_slow.resize(CAPACITY)
	_slow.fill(1.0)
	_slow_time.resize(CAPACITY)
	_slow_time.fill(0.0)
	_burn_time.resize(CAPACITY)
	_burn_time.fill(0.0)
	_burn_tick.resize(CAPACITY)
	_burn_tick.fill(0.0)
	_burn_damage.resize(CAPACITY)
	_burn_damage.fill(0.0)
	_exposed.resize(CAPACITY)
	_exposed.fill(0.0)
	_stunned.resize(CAPACITY)
	_stunned.fill(0.0)
	_daze_time.resize(CAPACITY)
	_daze_time.fill(0.0)
	_daze_used.resize(CAPACITY)
	_daze_used.fill(0)
	_life_hp.resize(CAPACITY)
	_life_hp.fill(0.0)
	_finisher_hits.resize(1)
	_finisher_distances.resize(1)
	_frost_time.resize(CAPACITY)
	_frost_time.fill(0.0)
	_charge_time.resize(CAPACITY)
	_charge_time.fill(0.0)
	_buff_time.resize(CAPACITY)
	_buff_time.fill(0.0)
	_buff_level.resize(CAPACITY)
	_buff_level.fill(0)
	_buff_pulse.resize(CAPACITY)
	_buff_pulse.fill(-1)
	_hype_pulses = 0
	_hype_timer = 0.0
	_launch_time.resize(CAPACITY)
	_launch_time.fill(0.0)
	_launch_frozen.resize(CAPACITY)
	_launch_frozen.fill(0)
	_kick_index.resize(KICK_TARGETS)
	_kick_generation.resize(KICK_TARGETS)
	_kick_flags.resize(KICK_TARGETS)
	_kick_distance.resize(KICK_TARGETS)
	_conduct_index.resize(CONDUCTION_TARGETS)
	_conduct_distance.resize(CONDUCTION_TARGETS)
	_conduct_generation.resize(CONDUCTION_TARGETS)
	_impact_kind.resize(MAX_IMPACTS)
	_impact_slot.resize(MAX_IMPACTS)
	_impact_generation.resize(MAX_IMPACTS)
	_impact_other.resize(MAX_IMPACTS)
	_impact_other_generation.resize(MAX_IMPACTS)
	_impact_velocity.resize(MAX_IMPACTS)
	_impact_count = 0
	_aura_buffer.resize(64)
	_action_depth = 0
	_action_members = 0
	_action_suspend = 0
	_pos.resize(CAPACITY)
	_y.resize(CAPACITY)
	_y.fill(0.0)
	_vy.resize(CAPACITY)
	_vy.fill(0.0)
	_knock.resize(CAPACITY)
	_aim.resize(CAPACITY)
	_active.resize(CAPACITY)
	_dying.resize(CAPACITY)
	_cell_items.resize(CAPACITY)
	_free.resize(CAPACITY)
	for slot in CAPACITY:
		_free[slot] = CAPACITY - 1 - slot
	_free_count = CAPACITY
	_grid_w = maxi(1, ceili(_area.size.x / CELL))
	_grid_h = maxi(1, ceili(_area.size.y / CELL))
	_cells = _grid_w * _grid_h
	_cell_start.resize(_cells + 1)
	_cell_cursor.resize(_cells)
	_candidate_index.resize(64)
	_candidate_t.resize(64)
	_radius_buffers.clear()
	_radius_generations.clear()
	_radius_depth = 0
	for depth in RADIUS_DEPTH:
		var buffer := PackedInt32Array()
		buffer.resize(CAPACITY)
		_radius_buffers.append(buffer)
		var generations := PackedInt64Array()
		generations.resize(CAPACITY)
		_radius_generations.append(generations)
	_chain_index.resize(SHOCK_TARGETS)
	_chain_distance.resize(SHOCK_TARGETS)
	var bounds := AABB(Vector3(_area.position.x - 4.0, -8.0, _area.position.y - 4.0), Vector3(_area.size.x + 8.0, 18.0, _area.size.y + 8.0))
	_setup_rendering()
	for definition in definitions:
		_register(definition, bounds)
	_read_elevation(elevation, ground)
	_read_obstacles(obstacles)
	_cell_center.resize(_cells)
	var cell_heights := PackedFloat32Array()
	cell_heights.resize(_cells)
	for cell in _cells:
		_cell_center[cell] = _area.position + (Vector2(cell % _grid_w, cell / _grid_w) + Vector2(0.5, 0.5)) * CELL
		cell_heights[cell] = ground_height(_cell_center[cell])
	_flow.setup(_grid_w, _grid_h, _area.position, CELL, _rect_blocked, cell_heights)
	_flow.update(Vector2(player.global_position.x, player.global_position.z), player.global_position.y - 0.9)
	_shot_pos.resize(MAX_PROJECTILES)
	_shot_vel.resize(MAX_PROJECTILES)
	_shot_life.resize(MAX_PROJECTILES)
	_shot_damage.resize(MAX_PROJECTILES)
	_shot_flags.resize(MAX_PROJECTILES)
	_shot_splash.resize(MAX_PROJECTILES)
	_shot_target.resize(MAX_PROJECTILES)
	_shot_target_generation.resize(MAX_PROJECTILES)
	# Every live shot can impact in the same frame; none is silently dropped.
	_shot_impact_pos.resize(MAX_PROJECTILES)
	_shot_impact_origin.resize(MAX_PROJECTILES)
	_shot_impact_slot.resize(MAX_PROJECTILES)
	_shot_impact_generation.resize(MAX_PROJECTILES)
	_shot_impact_damage.resize(MAX_PROJECTILES)
	_shot_impact_splash.resize(MAX_PROJECTILES)
	_shot_impact_collider.resize(MAX_PROJECTILES)
	_shot_impact_count = 0
	_sweep_hits.resize(1)
	_sweep_distances.resize(1)
	_shot_query.collision_mask = 1
	_shot_query.collide_with_areas = false
	var shots := MultiMesh.new()
	shots.transform_format = MultiMesh.TRANSFORM_3D
	# Per-shot tint and stretched shape: spit, lobbed bottle and reflected streak.
	shots.use_colors = true
	shots.mesh = projectile_mesh
	shots.instance_count = MAX_PROJECTILES
	shots.visible_instance_count = 0
	_shot_renderer = MultiMeshInstance3D.new()
	_shot_renderer.multimesh = shots
	_shot_renderer.material_override = projectile_material
	_shot_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shot_renderer.custom_aabb = bounds
	add_child(_shot_renderer)
	_shot_buffer.resize(MAX_PROJECTILES * 16)

## Optional encounter species share the normal batched rendering/simulation.
func registered_definitions() -> Array[HordeEnemyDefinition]:
	return _defs.duplicate()

func register_definition(definition: HordeEnemyDefinition) -> void:
	if definition == null or _type_of.has(definition):
		return
	var bounds := AABB(Vector3(_area.position.x - 4.0, -2.0, _area.position.y - 4.0), Vector3(_area.size.x + 8.0, 12.0, _area.size.y + 8.0))
	_register(definition, bounds)

func _register(definition: HordeEnemyDefinition, bounds: AABB) -> void:
	if _type_of.has(definition):
		return
	_type_of[definition] = _defs.size()
	_defs.append(definition)
	_t_behavior.append(definition.behavior)
	_t_speed.append(definition.speed)
	_t_radius.append(definition.radius)
	_largest_radius = maxf(_largest_radius, definition.radius * (FUSION_SCALE * FUSION_SHOULDER if not definition.is_boss and not definition.front_armored and definition.behavior == HordeEnemyDefinition.Behavior.SWARM else 1.0))
	_t_height.append(definition.height)
	_t_mass.append(maxf(0.05, definition.mass))
	_t_contact.append(definition.contact_damage)
	_t_scale.append(definition.model_scale)
	_t_boss.append(1 if definition.is_boss else 0)
	var weak_offset := definition.weak_spot_offset * definition.model_scale
	var weak_radius := definition.weak_spot_radius * definition.model_scale
	_t_weak_offset.append(weak_offset)
	_t_weak_radius_squared.append(weak_radius * weak_radius)
	_t_weak_top.append(weak_offset.y + weak_radius if weak_radius > 0.0 else 0.0)
	_t_armored.append(1 if definition.front_armored else 0)
	_t_front_scale.append(clampf(definition.front_damage_scale, 0.0, 1.0))
	_t_front_cos.append(cos(deg_to_rad(definition.front_half_angle_degrees)))
	_t_rear_cos.append(cos(deg_to_rad(definition.rear_precision_half_angle_degrees)))
	_t_turn_speed.append(maxf(0.0, definition.turn_speed))
	_register_renderer(definition, bounds)

func _setup_rendering() -> void:
	_anim_clip.resize(CAPACITY)
	_anim_clip.fill(-1)
	_anim_frame.resize(CAPACITY)
	_anim_speed.resize(CAPACITY)
	_anim_prev.resize(CAPACITY)
	_anatomy_slot_instance.resize(CAPACITY)
	_anatomy_slot_instance.fill(-1)
	_anatomy_intensity = clampf(float(Profile.settings.get("hallucination_intensity", 0.65)), 0.0, 1.0)
	if not Profile.changed.is_connected(_sync_anatomy_setting):
		Profile.changed.connect(_sync_anatomy_setting)
	if fx_scene != null and _fx == null:
		_fx = fx_scene.instantiate() as HordeFx
		add_child(_fx)

func _register_renderer(definition: HordeEnemyDefinition, bounds: AABB) -> void:
	var animation := definition.vertex_animation
	var animated := animation != null
	var stride := 20 if animated else 16
	_t_stride.append(stride)
	_t_move_ref.append(maxf(0.1, definition.move_clip_speed * definition.model_scale))
	var move := _add_clip(animation, definition.move_clip) if animated else -1
	if animated and move < 0:
		push_warning("%s: move clip '%s' missing; using the first clip" % [definition.display_name, definition.move_clip])
		move = _add_clip(animation, animation.clips[0].name)
	_t_clip_move.append(move)
	_t_clip_idle.append(_add_clip(animation, definition.idle_clip) if animated else -1)
	_t_clip_attack.append(_add_clip(animation, definition.attack_clip) if animated else -1)
	var death := _add_clip(animation, definition.death_clip) if animated else -1
	_t_clip_death.append(death)
	_t_death_time.append(maxf(0.1, definition.death_duration) if death >= 0 else DEATH_TIME)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = animated
	multimesh.mesh = HordeMeshBaker.bake(definition, enemy_shader, animated_enemy_shader)
	multimesh.instance_count = 64
	multimesh.visible_instance_count = 0
	var renderer := MultiMeshInstance3D.new()
	renderer.name = definition.display_name
	renderer.multimesh = multimesh
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if definition.is_boss else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	renderer.custom_aabb = bounds
	add_child(renderer)
	_renderers.append(renderer)
	var buffer := PackedFloat32Array()
	buffer.resize(64 * stride)
	_buffers.append(buffer)
	var anatomy_renderer: MultiMeshInstance3D
	var anatomy_buffer := PackedFloat32Array()
	if not definition.is_boss and not definition.front_armored and definition.behavior == HordeEnemyDefinition.Behavior.SWARM:
		var anatomy := MultiMesh.new()
		anatomy.transform_format = MultiMesh.TRANSFORM_3D
		anatomy.use_custom_data = true
		anatomy.use_colors = animated
		anatomy.mesh = HordeMeshBaker.bake_anatomy(multimesh.mesh as ArrayMesh, definition)
		anatomy.instance_count = ANATOMY_CAPACITY
		anatomy.visible_instance_count = 0
		anatomy_renderer = MultiMeshInstance3D.new()
		anatomy_renderer.name = "%sRecursiveAnatomy" % definition.display_name
		anatomy_renderer.multimesh = anatomy
		anatomy_renderer.custom_aabb = bounds.grow(3.0)
		anatomy_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anatomy_renderer.visible = _anatomy_intensity > 0.0
		add_child(anatomy_renderer)
		anatomy_buffer.resize(ANATOMY_CAPACITY * stride)
	_anatomy_renderers.append(anatomy_renderer)
	_anatomy_buffers.append(anatomy_buffer)
	var armor_renderer: MultiMeshInstance3D
	var armor_buffer := PackedFloat32Array()
	if definition.front_armored:
		var armor := MultiMesh.new()
		armor.transform_format = MultiMesh.TRANSFORM_3D
		armor.use_custom_data = true
		armor.mesh = HordeArmorMesh.bake(definition.weak_spot_offset, definition.weak_spot_radius)
		armor.instance_count = CAPACITY
		armor.visible_instance_count = 0
		armor_renderer = MultiMeshInstance3D.new()
		armor_renderer.name = "%sPlateAndCore" % definition.display_name
		armor_renderer.multimesh = armor
		armor_renderer.custom_aabb = bounds
		armor_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(armor_renderer)
		armor_buffer.resize(CAPACITY * 16)
	_armor_renderers.append(armor_renderer)
	_armor_buffers.append(armor_buffer)

# Appends `clip_name` of `animation` to the clip tables; returns its id or -1.
func _add_clip(animation: HordeVertexAnimation, clip_name: StringName) -> int:
	var index := animation.find_clip(clip_name)
	if index < 0:
		return -1
	var clip := animation.clips[index]
	_clip_start.append(clip.start_frame)
	_clip_count.append(maxi(1, clip.frame_count))
	_clip_fps.append(clip.fps)
	_clip_loop.append(1.0 if clip.loop else 0.0)
	return _clip_start.size() - 1

func _read_obstacles(root: Node) -> void:
	if root != null:
		for body in root.get_children():
			if not body is StaticBody3D:
				continue
			for child in body.get_children():
				var collider := child as CollisionShape3D
				if collider == null or collider.shape == null:
					continue
				var world := (body as Node3D).global_transform * collider.transform
				var center := Vector2(world.origin.x, world.origin.z)
				var bottom := 0.0
				var top := 0.0
				var height_slope := Vector2.ZERO
				if collider.shape is CylinderShape3D:
					var radius := (collider.shape as CylinderShape3D).radius * world.basis.get_scale().x
					var vertical := (collider.shape as CylinderShape3D).height * 0.5 * absf(world.basis.y.y)
					bottom = world.origin.y - vertical
					top = world.origin.y + vertical
					_obstacle_center.append(center)
					_obstacle_half.append(Vector2(radius, radius))
					_obstacle_circle.append(1)
				elif collider.shape is BoxShape3D:
					# Yaw is a multiple of 90 degrees: project the box extents onto X/Z.
					var half := (collider.shape as BoxShape3D).size * 0.5
					var x_axis := world.basis.x * half.x
					var y_axis := world.basis.y * half.y
					var z_axis := world.basis.z * half.z
					var normal := world.basis.y.normalized()
					var vertical := absf(x_axis.y) + absf(y_axis.y) + absf(z_axis.y)
					if absf(normal.y) > 0.5:
						height_slope = -Vector2(normal.x, normal.z) / normal.y
						vertical = y_axis.length() / absf(normal.y)
					bottom = world.origin.y - vertical
					top = world.origin.y + vertical
					_obstacle_center.append(center)
					_obstacle_half.append(Vector2(absf(x_axis.x) + absf(y_axis.x) + absf(z_axis.x), absf(x_axis.z) + absf(y_axis.z) + absf(z_axis.z)))
					_obstacle_circle.append(0)
				else:
					continue
				_obstacle_bottom.append(bottom)
				_obstacle_top.append(top)
				_obstacle_height_slope.append(height_slope)
	# Bucket obstacles into every cell their footprint (plus largest enemy) touches.
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(_cells)
	var margin := maxf(2.0, _largest_radius)
	for index in _obstacle_center.size():
		var low := _obstacle_center[index] - _obstacle_half[index] - Vector2(margin, margin)
		var high := _obstacle_center[index] + _obstacle_half[index] + Vector2(margin, margin)
		for cz in range(_cell_z(low.y), _cell_z(high.y) + 1):
			for cx in range(_cell_x(low.x), _cell_x(high.x) + 1):
				buckets[cz * _grid_w + cx].append(index)
	_cell_obstacle_start.resize(_cells + 1)
	var total := 0
	for cell in _cells:
		_cell_obstacle_start[cell] = total
		total += buckets[cell].size()
		_cell_obstacle_items.append_array(buckets[cell])
	_cell_obstacle_start[_cells] = total

# Top faces of Ground and Elevation boxes. Missing samples remain impassable.
func _read_elevation(root: Node, ground: Node) -> void:
	_heights_w = maxi(2, ceili(_area.size.x / HEIGHT_STEP))
	_heights_h = maxi(2, ceili(_area.size.y / HEIGHT_STEP))
	_heights.resize(_heights_w * _heights_h)
	_heights.fill(-INF if ground != null else 0.0)
	for source: Node in [ground, root]:
		if source == null:
			continue
		for body in source.get_children():
			if not body is StaticBody3D:
				continue
			for child in body.get_children():
				var collider := child as CollisionShape3D
				if collider != null and collider.shape is BoxShape3D:
					_rasterise_box(collider.global_transform, (collider.shape as BoxShape3D).size * 0.5)
	# The common y=0 floor keeps its allocation-free lookup fast path.
	var per := roundi(CELL / HEIGHT_STEP)
	_cell_flat.resize(_cells)
	for cell in _cells:
		var cx := cell % _grid_w
		var cz := cell / _grid_w
		var flat := 1
		for sz in range(maxi(0, cz * per - 1), mini(_heights_h, (cz + 1) * per + 1)):
			for sx in range(maxi(0, cx * per - 1), mini(_heights_w, (cx + 1) * per + 1)):
				if _heights[sz * _heights_w + sx] != 0.0:
					flat = 0
		_cell_flat[cell] = flat

func _rasterise_box(box: Transform3D, half: Vector3) -> void:
	var bounds := box * AABB(-half, half * 2.0)
	var x0 := clampi(floori((bounds.position.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var x1 := clampi(floori((bounds.end.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var z0 := clampi(floori((bounds.position.z - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	var z1 := clampi(floori((bounds.end.z - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	var inverse := box.affine_inverse()
	var down := inverse.basis * Vector3.DOWN
	var top := bounds.end.y + 1.0
	for sz in range(z0, z1 + 1):
		for sx in range(x0, x1 + 1):
			var start := inverse * Vector3(_area.position.x + (sx + 0.5) * HEIGHT_STEP, top, _area.position.y + (sz + 0.5) * HEIGHT_STEP)
			# Slab test in box space; the parameter stays in world metres.
			var enter := 0.0
			var leave := INF
			for axis in 3:
				var d := down[axis]
				if absf(d) < 0.000001:
					if absf(start[axis]) > half[axis]:
						leave = -1.0
				else:
					var t0 := (-half[axis] - start[axis]) / d
					var t1 := (half[axis] - start[axis]) / d
					enter = maxf(enter, minf(t0, t1))
					leave = minf(leave, maxf(t0, t1))
			if enter <= leave:
				var index := sz * _heights_w + sx
				_heights[index] = maxf(_heights[index], top - enter)

## Walkable ground height at `xz`: interpolated along ramps, exact at cliffs.
func ground_height(xz: Vector2) -> float:
	if _cell_flat.is_empty():
		return 0.0
	var local := xz - _area.position
	if _cell_flat[clampi(int(local.y / CELL), 0, _grid_h - 1) * _grid_w + clampi(int(local.x / CELL), 0, _grid_w - 1)] == 1:
		return 0.0
	var fx := local.x / HEIGHT_STEP - 0.5
	var fz := local.y / HEIGHT_STEP - 0.5
	var ix := clampi(floori(fx), 0, _heights_w - 2)
	var iz := clampi(floori(fz), 0, _heights_h - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var k := iz * _heights_w + ix
	var a := _heights[k]
	var b := _heights[k + 1]
	var c := _heights[k + _heights_w]
	var d := _heights[k + _heights_w + 1]
	if not is_finite(a) or not is_finite(b) or not is_finite(c) or not is_finite(d) \
			or maxf(maxf(a, b), maxf(c, d)) - minf(minf(a, b), minf(c, d)) > CLIMB:
		if tz >= 0.5:
			return d if tx >= 0.5 else c
		return b if tx >= 0.5 else a
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

# True when the ground inside `rect` contains a cliff enemies cannot walk up.
func _rect_rough(rect: Rect2) -> bool:
	var x0 := clampi(floori((rect.position.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var x1 := clampi(floori((rect.end.x - _area.position.x) / HEIGHT_STEP), 0, _heights_w - 1)
	var z0 := clampi(floori((rect.position.y - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	var z1 := clampi(floori((rect.end.y - _area.position.y) / HEIGHT_STEP), 0, _heights_h - 1)
	for sz in range(z0, z1 + 1):
		for sx in range(x0, x1 + 1):
			var k := sz * _heights_w + sx
			var h := _heights[k]
			if not is_finite(h):
				return true
			if (sx > 0 and _height_jump(_heights[k - 1], h)) \
					or (sx < _heights_w - 1 and _height_jump(_heights[k + 1], h)) \
					or (sz > 0 and _height_jump(_heights[k - _heights_w], h)) \
					or (sz < _heights_h - 1 and _height_jump(_heights[k + _heights_w], h)):
				return true
	return false

func _height_jump(neighbor: float, height: float) -> bool:
	# Missing floor outside the rectangle is a boundary, not a cliff inside it.
	return is_finite(neighbor) and absf(neighbor - height) > maxf(CLIMB, HEIGHT_STEP * CLIMB_SLOPE) + 0.001

func _cell_x(x: float) -> int:
	return clampi(int((x - _area.position.x) / CELL), 0, _grid_w - 1)

func _cell_z(z: float) -> int:
	return clampi(int((z - _area.position.y) / CELL), 0, _grid_h - 1)

# ---------------------------------------------------------------- spawning

## Reserves vacancies for a bounded encounter; reservation persists across its
## spawns/deaths until released. The caller owns the returned reservation count.
func reserve_slots(count: int) -> int:
	var granted := clampi(count, 0, maxi(0, _free_count - _reserved_slots))
	_reserved_slots += granted
	return granted

func release_reserved(count: int) -> void:
	_reserved_slots = maxi(0, _reserved_slots - maxi(0, count))

func spawn_reserved(definition: HordeEnemyDefinition, xz: Vector2, health_multiplier := 1.0) -> int:
	if _reserved_slots <= 0 or _free_count == 0:
		return -1
	return _spawn(definition, xz, health_multiplier, false)

## Slot generation identifies a particular life, not a recycled enemy index.
func enemy_generation(index: int) -> int:
	return _generation[index] if index >= 0 and index < CAPACITY else -1

func spawn(definition: HordeEnemyDefinition, xz: Vector2, health_multiplier := 1.0) -> int:
	if _free_count <= _reserved_slots:
		return -1
	return _spawn(definition, xz, health_multiplier, true)

func _spawn(definition: HordeEnemyDefinition, xz: Vector2, health_multiplier: float, ordinary: bool) -> int:
	if is_blocked(xz, definition.radius):
		return -1
	var type: int = _type_of[definition]
	_free_count -= 1
	var slot := _free[_free_count]
	_generation[slot] += 1
	var radius := _t_radius[type]
	_fusion_allowed[slot] = 1 if ordinary and not definition.is_boss and not definition.front_armored and definition.behavior == HordeEnemyDefinition.Behavior.SWARM else 0
	_members[slot] = 1
	_body[slot] = 1.0
	_radius[slot] = radius
	_height[slot] = _t_height[type]
	_mass[slot] = _t_mass[type]
	_gait[slot] = 0.9 + float((slot * 73 + int(_generation[slot]) * 19) % 101) * 0.002
	_grow[slot] = 0.0
	_dense_count[slot] = 0
	_stamp[slot] = 0
	_timer[slot] = 0.0
	_death[slot] = 0.0
	_aim[slot] = Vector2.ZERO
	_attack_target[slot] = Vector3.ZERO
	_has_lane[slot] = 0
	xz.x = clampf(xz.x, _area.position.x + radius, _area.end.x - radius)
	xz.y = clampf(xz.y, _area.position.y + radius, _area.end.y - radius)
	_state[slot] = ALIVE
	_type[slot] = type
	_mode[slot] = Mode.SEEK
	_pos[slot] = xz
	_y[slot] = ground_height(xz)
	_vy[slot] = 0.0
	_knock[slot] = Vector2.ZERO
	_hp[slot] = definition.max_health * health_multiplier
	_max_hp[slot] = _hp[slot]
	_life_hp[slot] = _hp[slot]
	_daze_time[slot] = 0.0
	_daze_used[slot] = 0
	_flash[slot] = 0.0
	_cooldown[slot] = _rng.randf_range(0.5, definition.attack_cooldown)
	_slow[slot] = 1.0
	_slow_time[slot] = 0.0
	_burn_time[slot] = 0.0
	_burn_tick[slot] = 0.0
	_burn_damage[slot] = 0.0
	_exposed[slot] = 0.0
	_stunned[slot] = 0.0
	_clear_pinball_state(slot)
	# Stay away from encoding boundaries after MultiMesh float32 rounding.
	_phase[slot] = _rng.randf_range(0.0001, TAU - 0.0001)
	_yaw[slot] = _rng.randf() * TAU
	if _t_armored[type] != 0 and is_instance_valid(target):
		var toward := Vector2(target.global_position.x, target.global_position.z) - xz
		_yaw[slot] = atan2(-toward.x, -toward.y)
	_active[_active_count] = slot
	_active_count += 1
	alive_count += 1
	population_count += 1
	if radius > BIG_RADIUS:
		_big.append(slot)
	_reset_animation(slot)
	if definition.is_boss:
		_boss_index = slot
		control_boss(false)
		var generation := _generation[slot]
		boss_spawned.emit(definition)
		if is_alive(slot) and _generation[slot] == generation:
			boss_health_changed.emit(_hp[slot], _max_hp[slot])
	return slot

## Transfers the current boss's steering to its stage encounter controller.
func control_boss(enabled: bool) -> void:
	_boss_controlled = enabled
	_boss_velocity = Vector2.ZERO
	_boss_facing = Vector2.ZERO
	_boss_recovering = false
	if is_alive(_boss_index):
		_mode[_boss_index] = Mode.SEEK
		_cooldown[_boss_index] = _defs[_type[_boss_index]].attack_cooldown

## Movement still goes through Horde's obstacle/heightfield constraints.
## Progress drives the existing windup animation rather than an independent pose.
func drive_boss(velocity: Vector2, facing: Vector2, pose: int, progress: float = 0.0) -> void:
	if not _boss_controlled or not is_alive(_boss_index):
		return
	_boss_velocity = velocity
	_boss_facing = facing
	_aim[_boss_index] = facing
	_mode[_boss_index] = pose
	_timer[_boss_index] = _defs[_type[_boss_index]].telegraph_duration * (1.0 - clampf(progress, 0.0, 1.0))

func set_boss_recovery(recovering: bool) -> void:
	_boss_recovering = _boss_controlled and recovering

## True when a disc at xz would overlap an obstacle or leave the play area.
func is_blocked(xz: Vector2, radius: float, feet: float = NAN, headroom: float = 2.2) -> bool:
	if not _area.grow(-radius).has_point(xz):
		return true
	var ground := ground_height(xz)
	if not is_finite(ground):
		return true
	if is_nan(feet):
		feet = ground
	if radius > 0.0 and (not is_finite(ground_height(xz + Vector2(radius, 0.0))) \
			or not is_finite(ground_height(xz - Vector2(radius, 0.0))) \
			or not is_finite(ground_height(xz + Vector2(0.0, radius))) \
			or not is_finite(ground_height(xz - Vector2(0.0, radius)))):
		return true
	var cell := _cell_z(xz.y) * _grid_w + _cell_x(xz.x)
	for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
		var o := _cell_obstacle_items[k]
		if not _obstacle_overlaps_height(o, feet, headroom, xz):
			continue
		var delta := xz - _obstacle_center[o]
		var half := _obstacle_half[o]
		if _obstacle_circle[o] == 1:
			if delta.length() < half.x + radius:
				return true
		elif absf(delta.x) < half.x + radius and absf(delta.y) < half.y + radius:
			return true
	return false

# True when any obstacle or cliff overlaps `rect` (used to rasterise the flow field).
func _rect_blocked(rect: Rect2) -> bool:
	if _rect_rough(rect):
		return true
	var center := rect.get_center()
	var cell := _cell_z(center.y) * _grid_w + _cell_x(center.x)
	for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
		var o := _cell_obstacle_items[k]
		if not _obstacle_overlaps_height(o, ground_height(center), 2.2, center):
			continue
		var c := _obstacle_center[o]
		var half := _obstacle_half[o]
		if _obstacle_circle[o] == 1:
			var closest := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
			if closest.distance_squared_to(c) < half.x * half.x:
				return true
		elif Rect2(c - half, half * 2.0).intersects(rect):
			return true
	return false

func _obstacle_overlaps_height(index: int, feet: float, headroom: float, xz: Vector2) -> bool:
	var rise := _obstacle_height_slope[index].dot(xz - _obstacle_center[index])
	return _obstacle_top[index] + rise > feet + 0.02 and _obstacle_bottom[index] + rise < feet + headroom

func set_layout(world: ProceduralWorld) -> void:
	_layout_roofed = PackedByteArray() if world == null else world.layout_roofed
	_layout_width = 0 if world == null else world.layout_width
	_layout_height = 0 if world == null else world.layout_height
	_layout_origin = Vector2.ZERO if world == null else world.layout_origin
	_layout_cell_size = ProceduralWorld.CELL_SIZE

func is_roofed(xz: Vector2) -> bool:
	if _layout_roofed.is_empty():
		return false
	var cell := Vector2i(floori((xz.x - _layout_origin.x) / _layout_cell_size), floori((xz.y - _layout_origin.y) / _layout_cell_size))
	if cell.x < 0 or cell.y < 0 or cell.x >= _layout_width or cell.y >= _layout_height:
		return false
	return _layout_roofed[cell.y * _layout_width + cell.x] != 0

## Spawn sites must have a route to the player, including covered rooms.
func is_reachable(xz: Vector2) -> bool:
	return _flow.is_reachable(_cell_z(xz.y) * _grid_w + _cell_x(xz.x))

## Removes every enemy without rewards (stage clear).
func clear() -> void:
	control_boss(false)
	_boss_index = -1
	_reserved_slots = 0
	for a in _active_count:
		var slot := _active[a]
		if _state[slot] == ALIVE:
			_begin_death(slot)
	_active_count = 0
	alive_count = 0
	population_count = 0
	_big.clear()
	_dense_count.fill(0)
	_fusion_cursor = 0
	_rebuild_grid()
	_shot_count = 0
	_shot_impact_count = 0
	_impact_count = 0

# ---------------------------------------------------------------- queries

## Slows an enemy's movement (including charges) to `factor` for `duration`
## seconds. The strongest active slow wins; the longest duration is kept.
func slow(index: int, factor: float, duration: float) -> void:
	if not is_alive(index):
		return
	if _slow_time[index] <= 0.0:
		_slow[index] = 1.0
	_slow[index] = minf(_slow[index], clampf(factor, 0.0, 1.0))
	_slow_time[index] = maxf(_slow_time[index], duration)

## Tag Burst creates a cross-gun damage window, never a permanent multiplier.
func expose(index: int, duration: float) -> void:
	if is_alive(index):
		_exposed[index] = maxf(_exposed[index], duration)

func is_exposed(index: int) -> bool:
	return is_alive(index) and _exposed[index] > 0.0

## Bosses get a short stagger; regular enemies stop attacks as well as movement.
func stun(index: int, duration: float) -> void:
	if is_alive(index):
		var boss := _t_boss[_type[index]] != 0
		_stunned[index] = maxf(_stunned[index], duration * (0.25 if boss else 1.0))
		if not boss:
			_mode[index] = Mode.SEEK
			_timer[index] = 0.0
			_cooldown[index] = _defs[_type[index]].attack_cooldown

## One bounded non-damage pass: displacement and attack interruption are not hits.
func blast_react(center: Vector3, radius: float, impulse: float) -> void:
	if radius <= 0.0 or impulse <= 0.0:
		return
	for a in _active_count:
		var i := _active[a]
		if not is_alive(i):
			continue
		var offset := enemy_position(i) - center
		var reach := radius + _radius[i]
		if offset.length_squared() > reach * reach or not _lane_clear(center, enemy_position(i)):
			continue
		var falloff := clampf(1.0 - offset.length() / reach, 0.2, 1.0)
		var away := Vector2(offset.x, offset.z).normalized()
		if away == Vector2.ZERO:
			away = Vector2.from_angle(_phase[i])
		_knock[i] += away * minf(16.0, impulse * falloff / _mass[i])
		stun(i, 0.25 + 0.3 * falloff)
		if _mass[i] < 2.0:
			_vy[i] = maxf(_vy[i], minf(4.5, impulse * falloff * 0.24 / _mass[i]))

func _clear_pinball_state(slot: int) -> void:
	_frost_time[slot] = 0.0
	_charge_time[slot] = 0.0
	_buff_time[slot] = 0.0
	_buff_level[slot] = 0
	_launch_time[slot] = 0.0
	_launch_frozen[slot] = 0

# ---------------------------------------------------------------- pinball

## Status bits of a live body. Callers read them before their hit transaction.
func combo_flags(index: int) -> int:
	if not is_alive(index):
		return 0
	var flags := 0
	if _frost_time[index] > 0.0:
		flags |= FROZEN
	if _burn_time[index] > 0.0:
		flags |= BURNING
	if _charge_time[index] > 0.0:
		flags |= ELECTRIC
	# Height alone is not flight: raised floors and static elevated poses must
	# retain ordinary rail damage. Kick/blast ascent and genuine falling qualify.
	if _vy[index] > 0.0 or ((_launch_time[index] > 0.0 or _vy[index] < 0.0) and _y[index] - ground_height(_pos[index]) > AIRBORNE_CLEARANCE):
		flags |= AIRBORNE
	return flags

## True while a kicked light body is still in its pinball flight.
func is_launched(index: int) -> bool:
	return is_alive(index) and _launch_time[index] > 0.0

## 0 = not hyped, 1 = inside a living hype man's aura, 2 = during its surge.
func hype_level(index: int) -> int:
	return _buff_level[index] if is_alive(index) and _buff_time[index] > 0.0 else 0

## Living hype sources for the aura marker; returns the count written.
func query_hype_sources(out: PackedInt32Array) -> int:
	var count := 0
	for a in _active_count:
		var slot := _active[a]
		if is_alive(slot) and _t_behavior[_type[slot]] == HordeEnemyDefinition.Behavior.HYPE:
			if count >= out.size():
				out.resize(maxi(8, out.size() * 2))
			out[count] = slot
			count += 1
	return count

func _is_heavy(slot: int) -> bool:
	var type := _type[slot]
	return _mass[slot] >= HEAVY_MASS or _t_boss[type] != 0 or _members[slot] > 1 \
		or _t_behavior[type] == HordeEnemyDefinition.Behavior.BOUNCER

func _build_rank(id: StringName) -> int:
	if not is_instance_valid(target) or target.run_state == null:
		return 0
	return int(target.run_state.upgrade_levels.get(id, 0))

func _action_open() -> int:
	var outer := _action_members
	_action_members = 0
	_action_depth += 1
	return outer

## Emits once for this scope's own kills; nested scopes already emitted theirs.
func _action_close(outer: int, fallback: Vector3, label: String) -> int:
	var members := _action_members
	var at := _action_last_kill if members > 0 else fallback
	_action_members = outer
	_action_depth -= 1
	if members > 0:
		_action_suspend += 1
		action_killed.emit(members, at, label)
		_action_suspend -= 1
	return members

## Leg strike from the camera `origin` along the aim. Light bodies launch into a
## pinball flight; heavy bodies, bosses, megas and bouncers only stagger. A
## frozen body that dies here or later hits a wall/body shatters once.
func kick(origin: Vector3, forward: Vector3, sliding: bool, slam: bool) -> bool:
	if _state.is_empty() or _active_count == 0:
		return false
	var flat := Vector2(forward.x, forward.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector2.ZERO
	if flat == Vector2.ZERO and not slam:
		return false
	var eye := Vector2(origin.x, origin.z)
	var reach := STOMP_RADIUS if slam else (SLIDE_KICK_REACH if sliding else KICK_REACH)
	var center: Vector3
	if slam:
		var below := eye + flat * 0.8
		var floor_y := ground_height(below)
		if not is_finite(floor_y):
			floor_y = origin.y - 1.6
		# The stomp lands on the floor beneath an airborne player, at most 3.5 m down.
		floor_y = maxf(floor_y, origin.y - 3.5)
		center = Vector3(below.x, floor_y + 0.9, below.y)
	else:
		center = Vector3(origin.x + flat.x * reach * 0.5, origin.y - 0.8, origin.z + flat.y * reach * 0.5)
	var count := query_radius(center, reach + 0.6, _kick_buffer)
	var chosen := 0
	for n in count:
		var slot := _kick_buffer[n]
		var offset := _pos[slot] - (Vector2(center.x, center.z) if slam else eye)
		var d := offset.length()
		if d - _radius[slot] > reach:
			continue
		if not slam:
			if d > _radius[slot] + 0.6 and offset.dot(flat) < KICK_COS * d:
				continue
			# The leg reaches bodies overlapping the band below the camera.
			if _y[slot] > origin.y - 0.1 or _y[slot] + _height[slot] < origin.y - 2.1:
				continue
		chosen = _rank_insert(_kick_index, _kick_distance, chosen, KICK_TARGETS, slot, d)
	# Identities and statuses are captured before any damage callbacks run.
	var lane_from := Vector3(origin.x, origin.y - 0.6, origin.z)
	for k in chosen:
		var slot := _kick_index[k]
		_kick_generation[k] = _generation[slot]
		_kick_flags[k] = combo_flags(slot)
		if not _lane_clear(lane_from, enemy_position(slot)):
			_kick_generation[k] = -1
	var label := "STOMP" if slam else ("SLIDE KICK" if sliding else "KICK")
	var amount := STOMP_DAMAGE if slam else (SLIDE_KICK_DAMAGE if sliding else KICK_DAMAGE)
	var touched := false
	var outer := _action_open()
	for k in chosen:
		var slot := _kick_index[k]
		var generation := _kick_generation[k]
		if not is_alive(slot) or _generation[slot] != generation:
			continue
		touched = true
		var away := _pos[slot] - Vector2(center.x, center.z)
		var direction := flat
		if slam:
			direction = away.normalized() if away.length_squared() > 0.0001 else (flat if flat != Vector2.ZERO else Vector2.from_angle(_phase[slot]))
		elif away.length_squared() > 0.0001:
			direction = (flat + away.normalized() * 0.35).normalized()
		var heavy := _is_heavy(slot)
		var frozen := _kick_flags[k] & FROZEN != 0
		var at := enemy_position(slot)
		if damage_combined(slot, amount, origin, 0.0, Vector3.ZERO, DamageType.Kind.KINETIC, false):
			if frozen:
				_shatter(at)
			continue
		if not is_alive(slot) or _generation[slot] != generation:
			continue
		if heavy:
			stun(slot, HEAVY_STAGGER)
			_knock[slot] += direction * minf(6.0, 18.0 / _mass[slot])
		else:
			stun(slot, LAUNCH_TIME)
			_knock[slot] = direction * KICK_LAUNCH_SPEED * (1.2 if sliding else 1.0)
			_vy[slot] = STOMP_LIFT if slam else (KICK_LIFT * 0.7 if sliding else KICK_LIFT)
			_launch_time[slot] = LAUNCH_TIME
			_launch_frozen[slot] = 1 if frozen else 0
	_action_close(outer, center, label)
	if touched and is_instance_valid(_fx):
		_fx.burst_kick(center, slam)
	return touched

# Keeps the `limit` nearest candidates sorted by distance; returns the new count.
func _rank_insert(indices: PackedInt32Array, distances: PackedFloat32Array, count: int, limit: int, slot: int, distance: float) -> int:
	var at := count
	while at > 0 and distances[at - 1] > distance:
		at -= 1
	if at >= limit:
		return count
	var last := mini(count, limit - 1)
	for shift in range(last, at, -1):
		indices[shift] = indices[shift - 1]
		distances[shift] = distances[shift - 1]
	indices[at] = slot
	distances[at] = distance
	return mini(count + 1, limit)

## Reflects up to MAX_PARRY live enemy projectiles near `origin` in front of the
## aim. Each reflects once, never hurts the player again and is swept against
## enemies and real world geometry. build_return multiplies damage and homes.
func parry_projectile(origin: Vector3, forward: Vector3, reach: float) -> bool:
	if _shot_count == 0 or forward.length_squared() < 0.0001:
		return false
	var aim := forward.normalized()
	var rank := _build_rank(&"build_return")
	var parried := 0
	for s in _shot_count:
		if parried >= MAX_PARRY:
			break
		if _shot_flags[s] & SHOT_REFLECTED != 0:
			continue
		var offset := _shot_pos[s] - origin
		var d := offset.length()
		if d > reach + projectile_radius or (d > 0.9 and offset.dot(aim) < 0.35 * d):
			continue
		var lobbed := _shot_flags[s] & SHOT_LOBBED != 0
		_shot_flags[s] = SHOT_REFLECTED | (SHOT_LOBBED if lobbed else 0)
		_shot_vel[s] = aim * REFLECT_SPEED
		_shot_life[s] = REFLECT_LIFE
		_shot_damage[s] = maxf(REFLECT_DAMAGE, _shot_damage[s] * 12.0) * (1.0 + rank)
		_shot_splash[s] = REFLECT_SPLASH if lobbed else 0.0
		_shot_target[s] = -1
		if rank >= 1:
			var homing := nearest(_shot_pos[s] + aim * 6.0, 24.0)
			if homing >= 0:
				_shot_flags[s] |= SHOT_HOMING
				_shot_target[s] = homing
				_shot_target_generation[s] = _generation[homing]
		parried += 1
	if parried > 0 and is_instance_valid(_fx):
		_fx.burst_return(origin + aim * minf(reach, 1.2))
	return parried > 0

## Manual weapon combos after the player's captured primary transaction.
## Each is one bounded, nonrecursive burst credited through the action ledger.
## Rail AIRBORNE is the player's own damage bonus and adds nothing here.
func trigger_weapon_combo(index: int, flags: int, weapon_id: StringName, _origin: Vector3, amount: float) -> void:
	if flags == 0 or index < 0 or index >= CAPACITY or _state.is_empty() or _state[index] == FREE or _combo_budget <= 0:
		return
	# Bursts center on the struck body (dying bodies keep their position).
	var at := enemy_position(index)
	match weapon_id:
		&"scatter", &"cihlomet":
			if flags & BURNING == 0:
				return
			_combo_budget -= 1
			# The blast consumes the target's fire; re-arming it takes a new ignition.
			if is_alive(index):
				_burn_time[index] = 0.0
				_burn_tick[index] = 0.0
				_burn_damage[index] = 0.0
			if is_instance_valid(_fx):
				_fx.burst_flame(at, FLAME_BURST_RADIUS)
			_action_radius(at, FLAME_BURST_RADIUS, FLAME_BURST_BASE + amount * 0.6, "FLAME BURST", 7.0, DamageType.Kind.KINETIC, false)
		&"autocannon", &"tvarohomet":
			if flags & ELECTRIC == 0:
				return
			_combo_budget -= 1
			if is_alive(index):
				_charge_time[index] = 0.0
			_conduct(index, at, 30.0 + amount * 0.5)

## Explosive conduction: arcs from the charged target to its CONDUCTION_TARGETS
## nearest neighbours (bounded scan) with a clear lane. Charged neighbours take
## double, but arcs never chain onward.
func _conduct(source: int, center: Vector3, amount: float) -> void:
	var c := Vector2(center.x, center.z)
	_query_id += 1
	if source >= 0 and source < CAPACITY:
		_stamp[source] = _query_id
	var chosen := 0
	var checks := 0
	for slot in _big:
		if checks >= CONDUCTION_CHECKS:
			break
		checks += 1
		chosen = _conduct_consider(slot, center, chosen)
	var reach := CONDUCTION_RADIUS + BIG_RADIUS
	for cz in range(_cell_z(c.y - reach), _cell_z(c.y + reach) + 1):
		for cx in range(_cell_x(c.x - reach), _cell_x(c.x + reach) + 1):
			var cell := cz * _grid_w + cx
			for k in range(_cell_start[cell], _cell_start[cell + 1]):
				if checks >= CONDUCTION_CHECKS:
					break
				checks += 1
				chosen = _conduct_consider(_cell_items[k], center, chosen)
	var doubled := 0
	for k in chosen:
		var slot := _conduct_index[k]
		_conduct_generation[k] = _generation[slot] if _lane_clear(center, enemy_position(slot)) else -1
		if _charge_time[slot] > 0.0:
			doubled |= 1 << k
	var outer := _action_open()
	for k in chosen:
		var slot := _conduct_index[k]
		if not is_alive(slot) or _generation[slot] != _conduct_generation[k]:
			continue
		if is_instance_valid(_fx):
			_fx.arc(center, enemy_position(slot))
		_deal_damage(slot, amount * (2.0 if doubled & (1 << k) != 0 else 1.0), Vector3.ZERO, DamageType.Kind.SHOCK, false)
		if is_alive(slot) and _generation[slot] == _conduct_generation[k]:
			_charge_time[slot] = 0.0
			stun(slot, 0.35)
	_action_close(outer, center, "CONDUCTION")

func _conduct_consider(slot: int, center: Vector3, chosen: int) -> int:
	if not is_alive(slot) or _stamp[slot] == _query_id:
		return chosen
	_stamp[slot] = _query_id
	var d2 := _body_distance_squared(slot, center)
	if d2 > CONDUCTION_RADIUS * CONDUCTION_RADIUS:
		return chosen
	return _rank_insert(_conduct_index, _conduct_distance, chosen, CONDUCTION_TARGETS, slot, d2)

## Explicit manual/prop area hit with real wall lanes and generation snapshots;
## one action_killed emission aggregates every life it kills.
func damage_radius_action(center: Vector3, radius: float, amount: float, label: String, impulse: float = 0.0) -> int:
	return _action_radius(center, radius, amount, label, impulse, DamageType.Kind.KINETIC, false)

func _action_radius(center: Vector3, radius: float, amount: float, label: String, impulse: float, damage_type: int, refreeze: bool) -> int:
	if amount <= 0.0 or radius <= 0.0 or _state.is_empty():
		return 0
	var outer := _action_open()
	var damaged := _radius_core(center, radius, amount, impulse, damage_type, refreeze)
	_action_close(outer, center, label)
	return damaged

# Bounded by the per-depth snapshot buffers; deeper nesting is refused, not scanned.
func _radius_core(center: Vector3, radius: float, amount: float, impulse: float, damage_type: int, refreeze: bool) -> int:
	if _radius_depth >= RADIUS_DEPTH:
		return 0
	var depth := _radius_depth
	_radius_depth += 1
	var buffer := _radius_buffers[depth]
	_radius_buffers[depth] = PackedInt32Array()
	var generations := _radius_generations[depth]
	_radius_generations[depth] = PackedInt64Array()
	var count := query_radius(center, radius, buffer)
	for n in count:
		generations[n] = _generation[buffer[n]]
	# Lanes are resolved before damage so callbacks cannot alter the snapshot.
	for n in count:
		if not _lane_clear(center, enemy_position(buffer[n])):
			generations[n] = -1
	var c := Vector2(center.x, center.z)
	var damaged := 0
	for n in count:
		var slot := buffer[n]
		if not is_alive(slot) or _generation[slot] != generations[n]:
			continue
		var away := _pos[slot] - c
		var falloff := clampf(1.0 - maxf(0.0, away.length() - _radius[slot]) / radius, 0.35, 1.0)
		var push := Vector3.ZERO
		if impulse > 0.0 and away.length_squared() > 0.0001:
			var shove := away.normalized() * impulse * falloff
			push = Vector3(shove.x, 0.0, shove.y)
		var before := _hp[slot]
		damage(slot, amount * falloff, push, damage_type, false)
		if _generation[slot] != generations[n] or _hp[slot] < before:
			damaged += 1
		if is_alive(slot) and _generation[slot] == generations[n]:
			if impulse > 0.0 and not _is_heavy(slot):
				_vy[slot] = maxf(_vy[slot], minf(4.5, impulse * falloff * 0.24 / _mass[slot]))
			if refreeze:
				_freeze(slot)
	_radius_buffers[depth] = buffer
	_radius_generations[depth] = generations
	_radius_depth -= 1
	return damaged

func _freeze(slot: int) -> void:
	slow(slot, FROST_FACTOR, FROST_DURATION)
	_frost_time[slot] = maxf(_frost_time[slot], FROST_DURATION)

## Frozen kicked body breaks into an ice burst: `body` (if still that life)
## dies, and its kill plus the burst's are one SHATTER emission. Survivors are
## only re-frozen (build_shatter rank >= 1), never launched or shattered again.
func _shatter(at: Vector3, body: int = -1, body_generation: int = -1) -> int:
	var rank := _build_rank(&"build_shatter")
	var radius := SHATTER_RADIUS + 1.5 * rank
	if is_instance_valid(_fx):
		_fx.burst_shatter(at, radius)
	var outer := _action_open()
	if is_alive(body) and _generation[body] == body_generation:
		_deal_damage(body, _hp[body], Vector3.ZERO, DamageType.Kind.FROST, false)
	var damaged := _radius_core(at, radius, SHATTER_DAMAGE * (1.0 + 0.5 * rank), 8.0, DamageType.Kind.KINETIC, rank >= 1)
	_action_close(outer, at, "SHATTER")
	return damaged

## Launched body movement result: walls and other bodies turn speed into impacts.
func _track_launch(i: int, intended: Vector2, moved: Vector2, delta: float) -> void:
	_launch_time[i] = maxf(0.0, _launch_time[i] - delta)
	var velocity := _knock[i]
	if velocity.length() < IMPACT_MIN_SPEED or _impact_count >= MAX_IMPACTS:
		return
	var other := -1
	var kind := Impact.WALL
	if moved.distance_squared_to(intended) <= 0.0025:
		other = _launch_contact(i, moved)
		if other < 0:
			return
		kind = Impact.BODY
	_impact_kind[_impact_count] = kind
	_impact_slot[_impact_count] = i
	_impact_generation[_impact_count] = _generation[i]
	_impact_other[_impact_count] = other
	_impact_other_generation[_impact_count] = _generation[other] if other >= 0 else -1
	_impact_velocity[_impact_count] = velocity
	_impact_count += 1
	# One impact per flight; the body rebounds weakly off a wall.
	_launch_time[i] = 0.0
	_knock[i] = -velocity * 0.2 if kind == Impact.WALL else velocity * 0.3

## Nearest overlapping live body on the same level, IMPACT_CHECKS grid entries at most.
func _launch_contact(i: int, p: Vector2) -> int:
	var cell := _cell_z(p.y) * _grid_w + _cell_x(p.x)
	var cx := cell % _grid_w
	var cz := cell / _grid_w
	var checks := 0
	for nz in range(maxi(0, cz - 1), mini(_grid_h, cz + 2)):
		for nx in range(maxi(0, cx - 1), mini(_grid_w, cx + 2)):
			var neighbor := nz * _grid_w + nx
			for k in range(_cell_start[neighbor], _cell_start[neighbor + 1]):
				if checks >= IMPACT_CHECKS:
					return -1
				checks += 1
				var j := _cell_items[k]
				if j == i or not is_alive(j):
					continue
				var reach := _radius[i] + _radius[j]
				if _pos[j].distance_squared_to(p) < reach * reach \
						and _y[i] < _y[j] + _height[j] and _y[j] < _y[i] + _height[i]:
					return j
	for j in _big:
		if j != i and is_alive(j):
			var reach := _radius[i] + _radius[j]
			if _pos[j].distance_squared_to(p) < reach * reach \
					and _y[i] < _y[j] + _height[j] and _y[j] < _y[i] + _height[i]:
				return j
	return -1

## Wall splats and body hits found during movement, after the loop finished.
func _resolve_impacts() -> void:
	var count := _impact_count
	_impact_count = 0
	for n in count:
		var slot := _impact_slot[n]
		var generation := _impact_generation[n]
		var velocity := _impact_velocity[n]
		var speed := velocity.length()
		var frozen := _launch_frozen[slot] != 0
		var alive := is_alive(slot) and _generation[slot] == generation
		var at := enemy_position(slot) if _state[slot] != FREE else Vector3(_pos[slot].x, _y[slot], _pos[slot].y)
		var amount := IMPACT_DAMAGE + speed * 1.5
		if alive:
			_launch_frozen[slot] = 0
		if frozen and alive:
			# Ice shatters on contact: the body breaks and bursts once.
			_shatter(at, slot, generation)
			continue
		var outer := _action_open()
		var push := Vector3(velocity.x, 0.0, velocity.y)
		if _impact_kind[n] == Impact.WALL:
			if alive:
				damage(slot, amount, Vector3.ZERO, DamageType.Kind.KINETIC, false)
			_action_close(outer, at, "WALL SPLAT")
		else:
			var other := _impact_other[n]
			if alive:
				damage(slot, amount * 0.6, Vector3.ZERO, DamageType.Kind.KINETIC, false)
			if is_alive(other) and _generation[other] == _impact_other_generation[n]:
				var other_generation := _generation[other]
				damage(other, amount, Vector3.ZERO, DamageType.Kind.KINETIC, false)
				# The struck body is shoved, never launched: impacts do not chain.
				if is_alive(other) and _generation[other] == other_generation:
					if _is_heavy(other):
						stun(other, 0.4)
					else:
						_knock[other] += Vector2(push.x, push.z) * 0.5 / _mass[other]
						_vy[other] = maxf(_vy[other], 2.5)
						stun(other, 0.5)
			_action_close(outer, at, "PINBALL")
		if is_instance_valid(_fx):
			_fx.burst_kick(at, false)

## Hype aura pulse: refreshes allies in range; level drops/expires with the source.
func _hype_aura(source: int, pulse: int) -> void:
	var definition := _defs[_type[source]]
	var level := 2 if _mode[source] == Mode.RECOVER else 1
	var count := query_radius(enemy_position(source), definition.aura_radius, _aura_buffer)
	var applied := 0
	for n in count:
		if applied >= HYPE_TARGETS:
			break
		var slot := _aura_buffer[n]
		var type := _type[slot]
		if slot == source or _t_boss[type] != 0 or _t_behavior[type] == HordeEnemyDefinition.Behavior.HYPE:
			continue
		# A fresh pulse resets the level; overlapping auras keep the strongest.
		_buff_level[slot] = level if _buff_pulse[slot] != pulse else maxi(_buff_level[slot], level)
		_buff_pulse[slot] = pulse
		_buff_time[slot] = BUFF_HOLD
		applied += 1

func _buff_speed(slot: int) -> float:
	if _buff_time[slot] <= 0.0:
		return 1.0
	return SURGE_SPEED_SCALE if _buff_level[slot] >= 2 else HYPE_SPEED_SCALE

func _buff_damage(slot: int) -> float:
	return HYPE_DAMAGE_SCALE if _buff_time[slot] > 0.0 else 1.0

## Bouncer shove: only a player still in front of the committed aim is thrown.
func _shove(i: int, type: int) -> void:
	if not is_instance_valid(target) or not target.active:
		return
	var definition := _defs[type]
	var to := Vector2(target.global_position.x, target.global_position.z) - _pos[i]
	var d := to.length()
	if d > definition.attack_range + 0.5 or absf(target.global_position.y - 0.9 - _y[i]) > LEVEL_GAP:
		return
	if d > 0.01 and to.dot(_aim[i]) < 0.3 * d:
		return
	var away := to / d if d > 0.01 else _aim[i]
	target.velocity += Vector3(away.x * definition.shove_impulse, 3.5, away.y * definition.shove_impulse)
	target.take_damage(ceili(definition.contact_damage * 2.0 * _buff_damage(i)))

## Bouncers hold space: an overlapping player is pushed out along the floor
## through move_and_collide (walls still stop it) and loses the velocity
## component driving into the body. No collider or extra physics layer.
func _block_player(i: int) -> void:
	var center := target.global_position
	var feet := center.y - 0.9
	if feet >= _y[i] + _height[i] or feet + 1.8 <= _y[i]:
		return
	var offset := Vector2(center.x, center.z) - _pos[i]
	var reach := _radius[i] + PLAYER_RADIUS
	var d := offset.length()
	if d >= reach:
		return
	var away := offset / d if d > 0.001 else Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	var depth := reach - d
	target.move_and_collide(Vector3(away.x * depth, 0.0, away.y * depth))
	var into := -(target.velocity.x * away.x + target.velocity.z * away.y)
	if into > 0.0:
		target.velocity.x += away.x * into
		target.velocity.z += away.y * into

## Hype man still in its stationary surge (RECOVER) window.
func is_surging(index: int) -> bool:
	return is_alive(index) and _t_behavior[_type[index]] == HordeEnemyDefinition.Behavior.HYPE and _mode[index] == Mode.RECOVER

## Public enemy projectile: `lobbed` arcs under gravity and splashes on landing.
func launch_projectile(from: Vector3, velocity: Vector3, damage_amount: float, lobbed: bool = false) -> bool:
	if _shot_flags.is_empty():
		return false
	var life := 4.0 if lobbed else 30.0 / maxf(1.0, velocity.length()) + 1.0
	return _add_shot(from, velocity, damage_amount, SHOT_LOBBED if lobbed else 0, BOTTLE_SPLASH if lobbed else 0.0, life)

func _add_shot(from: Vector3, velocity: Vector3, damage_amount: float, flags: int, splash: float, life: float) -> bool:
	if _shot_count >= MAX_PROJECTILES:
		return false
	_shot_pos[_shot_count] = from
	_shot_vel[_shot_count] = velocity
	_shot_life[_shot_count] = life
	_shot_damage[_shot_count] = damage_amount
	_shot_flags[_shot_count] = flags
	_shot_splash[_shot_count] = splash
	_shot_target[_shot_count] = -1
	_shot_target_generation[_shot_count] = -1
	_shot_count += 1
	return true

func is_stunned(index: int) -> bool:
	return is_alive(index) and _stunned[index] > 0.0

func is_dazed(index: int) -> bool:
	return is_alive(index) and _daze_time[index] > 0.0

## The first actual aimed body blocks selection, even if it is not dazed.
## Uses the ordinary shot bodies, never enlarged highlight geometry.
func finisher_target(origin: Vector3, forward: Vector3, reach: float = 3.2) -> int:
	if _active_count == 0 or not origin.is_finite() or not forward.is_finite() \
			or forward.length_squared() < 0.000001 or not is_finite(reach) or reach <= 0.0:
		return -1
	var direction := forward.normalized()
	if raycast(origin, direction, reach, 1, _finisher_hits, _finisher_distances) == 0:
		return -1
	var slot := _finisher_hits[0]
	if not is_dazed(slot) or not _finisher_same_floor(slot, origin) \
			or not _lane_clear(origin, origin + direction * _finisher_distances[0]):
		return -1
	return slot

## Contact-time validation of the recorded lifetime; no delayed kill or aim snap.
## Callback reentrancy cannot turn automatic/callback deaths into manual credit.
func finish(index: int, generation: int, origin: Vector3, reach: float = 3.2) -> bool:
	if _action_suspend > 0 or not is_dazed(index) or _generation[index] != generation \
			or _t_boss[_type[index]] != 0 or not origin.is_finite() \
			or not is_finite(reach) or reach <= 0.0 or not _finisher_same_floor(index, origin):
		return false
	var offset := enemy_position(index) - origin
	var direction := offset.normalized()
	if direction == Vector3.ZERO \
			or raycast(origin, direction, reach, 1, _finisher_hits, _finisher_distances) == 0 \
			or _finisher_hits[0] != index \
			or not _lane_clear(origin, origin + direction * _finisher_distances[0]):
		return false
	var at := enemy_position(index)
	var outer := _action_open()
	var killed := _deal_damage(index, _hp[index], direction * 14.0, DamageType.Kind.KINETIC, false)
	_action_close(outer, at, "FINISHER")
	if killed and is_instance_valid(_fx):
		_fx.burst_finisher(at, direction)
	return killed

func _finisher_same_floor(index: int, origin: Vector3) -> bool:
	var floor_y := ground_height(Vector2(origin.x, origin.z))
	return is_finite(floor_y) and absf(_y[index] - floor_y) <= LEVEL_GAP \
		and origin.y >= _y[index] - 0.2 and origin.y <= _y[index] + 2.2

func _enter_daze(index: int) -> void:
	_daze_used[index] = 1
	_daze_time[index] = DAZE_DURATION
	_dense_count[index] = 0
	_mode[index] = Mode.SEEK
	_timer[index] = 0.0
	_cooldown[index] = _defs[_type[index]].attack_cooldown
	_aim[index] = Vector2.ZERO
	_attack_target[index] = Vector3.ZERO
	_has_lane[index] = 0
	_anim_clip[index] = _t_clip_idle[_type[index]] if _t_clip_idle[_type[index]] >= 0 else _t_clip_move[_type[index]]
	_anim_frame[index] = 0.0
	_anim_speed[index] = 0.0

func is_alive(index: int) -> bool:
	return index >= 0 and index < CAPACITY and _state[index] == ALIVE

func fusion_members(index: int) -> int:
	return _members[index] if index >= 0 and index < CAPACITY and _state[index] != FREE else 1

func enemy_body_scale(index: int) -> float:
	return _body[index] if index >= 0 and index < CAPACITY and _state[index] != FREE else 1.0

func enemy_radius(index: int) -> float:
	return _radius[index] if index >= 0 and index < CAPACITY and _state[index] != FREE else 0.0

func query_megas(out: PackedInt32Array) -> int:
	var count := 0
	for a in _active_count:
		var slot := _active[a]
		if is_alive(slot) and _members[slot] > 1:
			if count >= out.size():
				out.resize(maxi(16, out.size() * 2))
			out[count] = slot
			count += 1
	return count

## Fraction of current health for a live slot, for precise finishing effects.
func enemy_health_fraction(index: int) -> float:
	if not is_alive(index):
		return 0.0
	return _hp[index] / maxf(1.0, _max_hp[index])

func enemy_position(index: int) -> Vector3:
	var p := _pos[index]
	return Vector3(p.x, _y[index] + _height[index] * 0.5, p.y)

func get_definition(index: int) -> HordeEnemyDefinition:
	return _defs[_type[index]]

## Uses the same feet position, scale and yaw as the rendered enemy.
func weak_spot_position(index: int) -> Vector3:
	var offset := _t_weak_offset[_type[index]] * _body[index]
	var yaw := _yaw[index]
	var c := cos(yaw)
	var s := sin(yaw)
	var p := _pos[index]
	return Vector3(p.x + offset.x * c + offset.z * s, _y[index] + offset.y, p.y - offset.x * s + offset.z * c)

## A normalized gun ray must intersect the head/core before the world blocker.
func weak_spot_hit(index: int, origin: Vector3, direction: Vector3, max_distance: float) -> bool:
	if not is_alive(index):
		return false
	var radius_squared := _t_weak_radius_squared[_type[index]] * _body[index] * _body[index]
	if radius_squared <= 0.0:
		return false
	# A ray from the front cannot claim a core behind the intervening chassis.
	# Stun freezes rotation; it never disables the plate or opens this gate.
	if _t_armored[_type[index]] != 0 and _source_facing_dot(index, origin) > -_t_rear_cos[_type[index]]:
		return false
	var offset := weak_spot_position(index) - origin
	var distance := clampf(offset.dot(direction), 0.0, max_distance)
	return (offset - direction * distance).length_squared() <= radius_squared

func query_radius(center: Vector3, radius: float, out: PackedInt32Array) -> int:
	_query_id += 1
	var c := Vector2(center.x, center.z)
	var count := 0
	var reach := radius + 1.0
	for cz in range(_cell_z(c.y - reach), _cell_z(c.y + reach) + 1):
		for cx in range(_cell_x(c.x - reach), _cell_x(c.x + reach) + 1):
			var cell := cz * _grid_w + cx
			for k in range(_cell_start[cell], _cell_start[cell + 1]):
				count = _collect_in_radius(_cell_items[k], c, center.y, radius, out, count)
	for slot in _big:
		count = _collect_in_radius(slot, c, center.y, radius, out, count)
	return count

# Discs in XZ, skipping bodies on a clearly different level than `cy`.
func _collect_in_radius(slot: int, c: Vector2, cy: float, radius: float, out: PackedInt32Array, count: int) -> int:
	if _state[slot] != ALIVE or _stamp[slot] == _query_id:
		return count
	_stamp[slot] = _query_id
	var r := radius + _radius[slot]
	if (_pos[slot] - c).length_squared() > r * r:
		return count
	var half := _height[slot] * 0.5
	if absf(_y[slot] + half - cy) > radius + half + LEVEL_GAP:
		return count
	if count >= out.size():
		out.resize(maxi(16, out.size() * 2))
	out[count] = slot
	return count + 1

func nearest(center: Vector3, max_radius: float) -> int:
	var c := Vector2(center.x, center.z)
	var best := -1
	var best_d2 := max_radius * max_radius
	var cx0 := _cell_x(c.x)
	var cz0 := _cell_z(c.y)
	var rings := ceili((max_radius + _largest_radius) / CELL) + 1
	for ring in rings:
		# A body's surface may reach across multiple cells.
		if best >= 0 and pow(maxf(0.0, (ring - 1) * CELL - _largest_radius), 2.0) > best_d2:
			break
		for cz in range(cz0 - ring, cz0 + ring + 1):
			if cz < 0 or cz >= _grid_h:
				continue
			var edge := cz == cz0 - ring or cz == cz0 + ring
			var step := 1 if edge else ring * 2
			var cx := cx0 - ring
			while cx <= cx0 + ring:
				if cx >= 0 and cx < _grid_w:
					var cell := cz * _grid_w + cx
					for k in range(_cell_start[cell], _cell_start[cell + 1]):
						var slot := _cell_items[k]
						if _state[slot] != ALIVE:
							continue
						var d2 := _body_distance_squared(slot, center)
						if d2 < best_d2:
							best_d2 = d2
							best = slot
				cx += maxi(1, step)
	for slot in _big:
		if _state[slot] != ALIVE:
			continue
		var d2 := _body_distance_squared(slot, center)
		if d2 < best_d2:
			best_d2 = d2
			best = slot
	return best

func _body_distance_squared(slot: int, center: Vector3) -> float:
	# Ordinary targeting retains its existing XZ-center semantics.
	if _members[slot] == 1:
		return _pos[slot].distance_squared_to(Vector2(center.x, center.z))
	var horizontal := maxf(0.0, _pos[slot].distance_to(Vector2(center.x, center.z)) - _radius[slot])
	var vertical := center.y - clampf(center.y, _y[slot], _y[slot] + _height[slot])
	return horizontal * horizontal + vertical * vertical

## Ray against enemy cylinders; writes up to max_hits nearest hits.
func raycast(origin: Vector3, direction: Vector3, max_distance: float, max_hits: int, out_hits: PackedInt32Array, out_distances: PackedFloat32Array) -> int:
	_query_id += 1
	var candidates := 0
	var h := Vector2(direction.x, direction.z)
	var o := Vector2(origin.x, origin.z)
	for slot in _big:
		candidates = _ray_test(slot, origin, direction, o, h, max_distance, candidates)
	var cx := _cell_x(o.x)
	var cz := _cell_z(o.y)
	var step_x := 1 if h.x > 0.0 else -1
	var step_z := 1 if h.y > 0.0 else -1
	var local := o - _area.position
	var next_x := INF if absf(h.x) < 0.00001 else ((cx + (1 if step_x > 0 else 0)) * CELL - local.x) / h.x
	var next_z := INF if absf(h.y) < 0.00001 else ((cz + (1 if step_z > 0 else 0)) * CELL - local.y) / h.y
	var delta_x := INF if absf(h.x) < 0.00001 else CELL / absf(h.x)
	var delta_z := INF if absf(h.y) < 0.00001 else CELL / absf(h.y)
	var entered := 0.0
	# Neighbor cells are included so bodies overlapping a cell edge still hit.
	while entered <= max_distance:
		for nz in range(maxi(0, cz - 1), mini(_grid_h, cz + 2)):
			for nx in range(maxi(0, cx - 1), mini(_grid_w, cx + 2)):
				var cell := nz * _grid_w + nx
				for k in range(_cell_start[cell], _cell_start[cell + 1]):
					candidates = _ray_test(_cell_items[k], origin, direction, o, h, max_distance, candidates)
		if candidates >= max_hits and _kth_smallest(candidates, max_hits) < entered - CELL:
			break
		if next_x < next_z:
			cx += step_x
			entered = next_x
			next_x += delta_x
		else:
			cz += step_z
			entered = next_z
			next_z += delta_z
		if cx < 0 or cz < 0 or cx >= _grid_w or cz >= _grid_h or (next_x == INF and next_z == INF):
			break
	# Selection-sort the nearest max_hits candidates into the outputs.
	var hits := mini(candidates, max_hits)
	if out_hits.size() < hits:
		out_hits.resize(hits)
	if out_distances.size() < hits:
		out_distances.resize(hits)
	for n in hits:
		var best := n
		for m in range(n + 1, candidates):
			if _candidate_t[m] < _candidate_t[best]:
				best = m
		var t := _candidate_t[best]
		var slot := _candidate_index[best]
		_candidate_t[best] = _candidate_t[n]
		_candidate_index[best] = _candidate_index[n]
		_candidate_t[n] = t
		_candidate_index[n] = slot
		out_hits[n] = slot
		out_distances[n] = t
	return hits

func _kth_smallest(count: int, k: int) -> float:
	# Upper bound of the k nearest: the largest of the first k after partial scan.
	var worst := 0.0
	var taken := 0
	var threshold := -INF
	while taken < k:
		var best := INF
		for m in count:
			if _candidate_t[m] > threshold and _candidate_t[m] < best:
				best = _candidate_t[m]
		threshold = best
		worst = best
		taken += 1
	return worst

func _ray_test(slot: int, origin: Vector3, direction: Vector3, o: Vector2, h: Vector2, max_distance: float, candidates: int) -> int:
	if _state[slot] != ALIVE or _stamp[slot] == _query_id:
		return candidates
	_stamp[slot] = _query_id
	var type := _type[slot]
	var t := _cylinder_ray_distance(slot, type, origin, direction, o, h, max_distance)
	# Plated roles have a real protruding static core. Its visible geometry is
	# hittable even on a grazing ray that misses the underlying chassis cylinder.
	# Precision separately requires the rear approach; front rays stop at the
	# nearer chassis instead of pretending to pass through it to the core.
	if _t_armored[type] != 0:
		t = minf(t, _core_ray_distance(slot, origin, direction, max_distance))
		t = minf(t, _plate_ray_distance(slot, origin, direction, max_distance))
	if t == INF:
		return candidates
	if candidates >= _candidate_t.size():
		_candidate_t.resize(candidates * 2)
		_candidate_index.resize(candidates * 2)
	_candidate_index[candidates] = slot
	_candidate_t[candidates] = t
	return candidates + 1

func _core_ray_distance(slot: int, origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var radius_squared := _t_weak_radius_squared[_type[slot]] * _body[slot] * _body[slot]
	if radius_squared <= 0.0:
		return INF
	var offset := weak_spot_position(slot) - origin
	var projection := offset.dot(direction)
	var discriminant := radius_squared - (offset.length_squared() - projection * projection)
	if discriminant < 0.0:
		return INF
	var root := sqrt(discriminant)
	if projection + root < 0.0:
		return INF
	var t := maxf(0.0, projection - root)
	return t if t <= max_distance else INF

func _plate_ray_distance(slot: int, origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var c := cos(_yaw[slot])
	var s := sin(_yaw[slot])
	var scale := _t_scale[_type[slot]] * _body[slot]
	var offset := origin - Vector3(_pos[slot].x, _y[slot], _pos[slot].y)
	var local := Vector3(offset.x * c - offset.z * s, offset.y, offset.x * s + offset.z * c) / scale - HordeArmorMesh.FRONT_CENTER
	var ray := Vector3(direction.x * c - direction.z * s, direction.y, direction.x * s + direction.z * c) / scale
	var half := HordeArmorMesh.FRONT_SIZE * 0.5
	var near := 0.0
	var far := max_distance
	for axis in 3:
		if absf(ray[axis]) < 0.000001:
			if absf(local[axis]) > half[axis]:
				return INF
			continue
		var a := (-half[axis] - local[axis]) / ray[axis]
		var b := (half[axis] - local[axis]) / ray[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
		if near > far:
			return INF
	return near

func _cylinder_ray_distance(slot: int, type: int, origin: Vector3, direction: Vector3, o: Vector2, h: Vector2, max_distance: float) -> float:
	var radius := _radius[slot] + 0.08
	var m := o - _pos[slot]
	var a := h.length_squared()
	var c := m.length_squared() - radius * radius
	var t := 0.0
	var t_exit := max_distance
	if a < 0.000001:
		if c > 0.0:
			return INF
	else:
		var b := m.dot(h)
		var disc := b * b - a * c
		if disc < 0.0:
			return INF
		var root := sqrt(disc)
		t = (-b - root) / a
		t_exit = (-b + root) / a
		if t_exit < 0.0:
			return INF
		t = maxf(t, 0.0)
	if t > max_distance:
		return INF
	var y_enter := origin.y + direction.y * t
	var y_exit := origin.y + direction.y * minf(t_exit, max_distance)
	var base := _y[slot]
	var top := base + maxf(_height[slot] + hit_headroom * _body[slot], _t_weak_top[type] * _body[slot])
	if minf(y_enter, y_exit) > top or maxf(y_enter, y_exit) < base:
		return INF
	if y_enter > top and direction.y < 0.0:
		t = (top - origin.y) / direction.y
	elif y_enter < base and direction.y > 0.0:
		t = (base - origin.y) / direction.y
	return t

## Positions for radar display, sampled evenly across the living crowd.
func sample_positions(out: PackedVector2Array, max_count: int, heights: PackedFloat32Array) -> int:
	var stride := maxi(1, ceili(float(_active_count) / max_count))
	var count := 0
	var a := 0
	while a < _active_count and count < max_count:
		var slot := _active[a]
		if _state[slot] == ALIVE:
			if count >= out.size():
				out.resize(max_count)
			if count >= heights.size():
				heights.resize(max_count)
			out[count] = _pos[slot]
			heights[count] = _y[slot]
			count += 1
		a += stride
	return count

# ---------------------------------------------------------------- damage

## Direct sources must pass the actual muzzle/blade/contact origin, never the
## player's current position. Piercing keeps the original origin for every hit.
func damage_direct(index: int, amount: float, origin: Vector3, knockback := Vector3.ZERO, damage_type: int = 0, critical: bool = false) -> bool:
	return damage_combined(index, amount, origin, 0.0, knockback, damage_type, critical)

## One health/event transaction for aggregated direct damage + splash.
## Only direct damage sees the plate; status conduction retains its normal radius.
func damage_combined(index: int, direct_amount: float, origin: Vector3, area_amount: float, knockback := Vector3.ZERO, damage_type: int = 0, critical: bool = false) -> bool:
	if not is_alive(index):
		return false
	var type := _type[index]
	var effect_amount := direct_amount + area_amount
	if _t_armored[type] != 0 and _source_facing_dot(index, origin) >= _t_front_cos[type]:
		direct_amount *= _t_front_scale[type]
	return _damage_effects(index, direct_amount + area_amount, effect_amount, knockback, damage_type, critical)

func _source_facing_dot(index: int, origin: Vector3) -> float:
	var offset := Vector2(origin.x, origin.z) - _pos[index]
	if offset.length_squared() <= 0.000001:
		return 0.0
	return offset.normalized().dot(Vector2(-sin(_yaw[index]), -cos(_yaw[index])))

## Non-directional damage only: splash, area hazards, burn/conduction effects.
## No attacker-position fallback; all direct-hit consumers use damage_direct or
## damage_combined. FIRE's later burn ticks bypass armor even after a plated hit.
func damage(index: int, amount: float, knockback := Vector3.ZERO, damage_type: int = 0, critical: bool = false) -> bool:
	return _damage_effects(index, amount, amount, knockback, damage_type, critical)

## Status potency derives from the unplated hit. Fire DOT and secondary shock
## conduction bypass front plating; only the original direct HP hit is blocked.
func _damage_effects(index: int, amount: float, effect_amount: float, knockback: Vector3, damage_type: int, critical: bool) -> bool:
	if not is_alive(index) or amount <= 0.0:
		return false
	var at := enemy_position(index)
	var generation := _generation[index]
	# Establish exclusion before damage signals can synchronously run a fusion.
	match damage_type:
		DamageType.Kind.FIRE:
			if _burn_time[index] <= 0.0:
				_burn_tick[index] = BURN_TICK
			_burn_time[index] = BURN_DURATION
			_burn_damage[index] = maxf(_burn_damage[index], effect_amount * 0.15)
		DamageType.Kind.FROST:
			slow(index, FROST_FACTOR, FROST_DURATION)
			_frost_time[index] = maxf(_frost_time[index], FROST_DURATION)
		DamageType.Kind.SHOCK:
			_charge_time[index] = CHARGE_DURATION
	var killed := _deal_damage(index, amount, knockback, damage_type, critical)
	if damage_type == DamageType.Kind.SHOCK and _generation[index] == generation:
		_chain_shock(index, at, effect_amount * 0.4, critical)
	return killed

## Shared health/reward path, deliberately without secondary type effects.
func _deal_damage(index: int, amount: float, knockback: Vector3, damage_type: int, critical: bool) -> bool:
	if not is_alive(index) or amount <= 0.0:
		return false
	var before := _hp[index]
	if index == _boss_index and _boss_recovering:
		amount *= 1.5
	if _exposed[index] > 0.0:
		amount *= 1.35
	_hp[index] = maxf(0.0, before - minf(amount, before))
	# Report the stored HP delta, including packed-float rounding.
	var removed := before - _hp[index]
	if removed <= 0.0:
		return false
	var at := enemy_position(index)
	var definition := _defs[_type[index]]
	var was_boss := index == _boss_index
	var members := _members[index]
	var health_after := _hp[index]
	var maximum := _max_hp[index]
	_flash[index] = 1.0
	_knock[index] += Vector2(knockback.x, knockback.z) / _mass[index]
	var killed := _hp[index] <= 0.0
	if not killed and _t_boss[_type[index]] == 0 and _daze_used[index] == 0 \
			and _hp[index] <= _life_hp[index] * DAZE_HEALTH_FRACTION:
		_enter_daze(index)
	if killed:
		_begin_death(index)
		alive_count -= 1
		population_count -= members
		if was_boss:
			_boss_index = -1
			control_boss(false)
		# Visual death belongs to the body, not each credited constituent life.
		if is_instance_valid(_fx):
			_fx.burst_death(definition, at, _body[index], Vector3(_knock[index].x, knockback.y, _knock[index].y))
		# Only an open action scope earns credit, and never from inside callbacks.
		if _action_depth > 0 and _action_suspend == 0:
			_action_members += members
			_action_last_kill = at
	_action_suspend += 1
	if was_boss:
		boss_health_changed.emit(health_after, maximum)
	damage_reported.emit(at, removed, damage_type, critical, killed)
	if killed:
		for member in members:
			enemy_killed.emit(definition, at)
		if was_boss:
			boss_killed.emit()
	_action_suspend -= 1
	if not killed and is_instance_valid(_fx):
		_fx.burst_hit(definition, at)
	return killed

## One-hop conduction to three closest bodies among at most 96 entries.
## Big bodies participate first; grid candidates share the same work budget.
func _chain_shock(source: int, center: Vector3, amount: float, critical: bool) -> void:
	var c := Vector2(center.x, center.z)
	_chain_index.fill(-1)
	_chain_distance.fill(INF)
	_query_id += 1
	var checks := 0
	for slot in _big:
		if checks >= SHOCK_CHECKS:
			break
		checks += 1
		_chain_consider(slot, source, center)
	var reach := SHOCK_RADIUS + BIG_RADIUS
	for cz in range(_cell_z(c.y - reach), _cell_z(c.y + reach) + 1):
		for cx in range(_cell_x(c.x - reach), _cell_x(c.x + reach) + 1):
			var cell := cz * _grid_w + cx
			for k in range(_cell_start[cell], _cell_start[cell + 1]):
				if checks >= SHOCK_CHECKS:
					break
				checks += 1
				_chain_consider(_cell_items[k], source, center)
			if checks >= SHOCK_CHECKS:
				break
		if checks >= SHOCK_CHECKS:
			break
	# Snapshot identities as well as indices before synchronous callbacks.
	var first := _chain_index[0]
	var second := _chain_index[1]
	var third := _chain_index[2]
	var first_generation := enemy_generation(first)
	var second_generation := enemy_generation(second)
	var third_generation := enemy_generation(third)
	if first >= 0 and enemy_generation(first) == first_generation:
		_deal_damage(first, amount, Vector3.ZERO, DamageType.Kind.SHOCK, critical)
	if second >= 0 and enemy_generation(second) == second_generation:
		_deal_damage(second, amount, Vector3.ZERO, DamageType.Kind.SHOCK, critical)
	if third >= 0 and enemy_generation(third) == third_generation:
		_deal_damage(third, amount, Vector3.ZERO, DamageType.Kind.SHOCK, critical)

func _chain_consider(slot: int, source: int, center: Vector3) -> void:
	if slot == source or not is_alive(slot) or _stamp[slot] == _query_id:
		return
	_stamp[slot] = _query_id
	var d2 := _body_distance_squared(slot, center)
	if d2 > SHOCK_RADIUS * SHOCK_RADIUS:
		return
	for rank in SHOCK_TARGETS:
		if d2 < _chain_distance[rank]:
			for shift in range(SHOCK_TARGETS - 1, rank, -1):
				_chain_index[shift] = _chain_index[shift - 1]
				_chain_distance[shift] = _chain_distance[shift - 1]
			_chain_index[rank] = slot
			_chain_distance[rank] = d2
			break

func _update_burns(delta: float) -> void:
	# Death only marks slots here; compacting stays in _rebuild_grid afterward.
	# Thus a DOT kill cannot swap a survivor past this iteration.
	for a in _active_count:
		var slot := _active[a]
		if not is_alive(slot) or _burn_time[slot] <= 0.0:
			continue
		var generation := _generation[slot]
		var elapsed := minf(delta, _burn_time[slot])
		_burn_time[slot] = maxf(0.0, _burn_time[slot] - delta)
		_burn_tick[slot] -= elapsed
		while _burn_tick[slot] <= 0.00001 and is_alive(slot) and _generation[slot] == generation:
			_burn_tick[slot] += BURN_TICK
			_deal_damage(slot, _burn_damage[slot], Vector3.ZERO, DamageType.Kind.FIRE, false)
		if _generation[slot] == generation and _burn_time[slot] <= 0.0:
			_burn_damage[slot] = 0.0
			_burn_tick[slot] = 0.0

func damage_radius(center: Vector3, radius: float, amount: float, knockback_strength := 0.0, damage_type: int = 0, critical: bool = false) -> int:
	if amount <= 0.0:
		return 0
	if _radius_depth >= RADIUS_DEPTH:
		# Exceptional deeper callback nesting scans slots directly. It remains
		# bounded by CAPACITY and cannot overwrite an ancestor's target list.
		return _damage_radius_scan(center, radius, amount, knockback_strength, damage_type, critical)
	var depth := _radius_depth
	_radius_depth += 1
	var buffer := _radius_buffers[depth]
	# Packed arrays use copy-on-write; detach while this invocation owns it.
	_radius_buffers[depth] = PackedInt32Array()
	var count := query_radius(center, radius, buffer)
	var generations := _radius_generations[depth]
	_radius_generations[depth] = PackedInt64Array()
	for n in count:
		generations[n] = _generation[buffer[n]]
	var damaged := 0
	var c := Vector2(center.x, center.z)
	for n in count:
		if _generation[buffer[n]] == generations[n]:
			damaged += _damage_radius_slot(buffer[n], c, amount, knockback_strength, damage_type, critical)
	_radius_buffers[depth] = buffer
	_radius_generations[depth] = generations
	_radius_depth -= 1
	return damaged

func _damage_radius_slot(slot: int, center: Vector2, amount: float, knockback_strength: float, damage_type: int, critical: bool) -> int:
	if not is_alive(slot):
		return 0
	var away := _pos[slot] - center
	var push := Vector3.ZERO
	if knockback_strength > 0.0 and away.length_squared() > 0.0001:
		away = away.normalized() * knockback_strength
		push = Vector3(away.x, 0.0, away.y)
	var before := _hp[slot]
	var generation := _generation[slot]
	damage(slot, amount, push, damage_type, critical)
	return 1 if _generation[slot] != generation or _hp[slot] < before else 0

func _damage_radius_scan(center: Vector3, radius: float, amount: float, knockback_strength: float, damage_type: int, critical: bool) -> int:
	var c := Vector2(center.x, center.z)
	var damaged := 0
	for slot in CAPACITY:
		if not is_alive(slot):
			continue
		var reach := radius + _radius[slot]
		if _pos[slot].distance_squared_to(c) > reach * reach:
			continue
		var half := _height[slot] * 0.5
		if absf(_y[slot] + half - center.y) > radius + half + LEVEL_GAP:
			continue
		damaged += _damage_radius_slot(slot, c, amount, knockback_strength, damage_type, critical)
	return damaged

func _begin_death(slot: int) -> void:
	_hide_anatomy_slot(slot)
	_state[slot] = DYING
	_slow[slot] = 1.0
	_slow_time[slot] = 0.0
	_burn_time[slot] = 0.0
	_burn_tick[slot] = 0.0
	_burn_damage[slot] = 0.0
	_death[slot] = _t_death_time[_type[slot]]
	_flash[slot] = 1.0
	_dying[_dying_count] = slot
	_dying_count += 1
	_fusion_allowed[slot] = 0
	_dense_count[slot] = 0
	_exposed[slot] = 0.0
	_stunned[slot] = 0.0
	_daze_time[slot] = 0.0
	_daze_used[slot] = 0
	_life_hp[slot] = 0.0
	_clear_pinball_state(slot)
	var at := _big.find(slot)
	if at >= 0:
		_big.remove_at(at)

## Cached physical dimensions are also the rendered grow-in dimensions.
func _set_body(slot: int, factor: float) -> void:
	var type := _type[slot]
	_body[slot] = factor
	_radius[slot] = _t_radius[type] * factor * (FUSION_SHOULDER if _members[slot] > 1 else 1.0)
	_height[slot] = _t_height[type] * factor
	_mass[slot] = _t_mass[type] * float(_members[slot])

func _fusion_eligible(slot: int, player: Vector2) -> bool:
	return is_alive(slot) and _fusion_allowed[slot] != 0 and _members[slot] == 1 \
		and _mode[slot] == Mode.SEEK and _burn_time[slot] <= 0.0 \
		and _slow_time[slot] <= 0.0 and _stunned[slot] <= 0.0 and _exposed[slot] <= 0.0 \
		and _daze_time[slot] <= 0.0 \
		and _charge_time[slot] <= 0.0 and _launch_time[slot] <= 0.0 \
		and absf(_vy[slot]) < 0.001 and _knock[slot].length_squared() < 0.01 \
		and _pos[slot].distance_squared_to(player) >= 16.0

## Exact segment/obstacle tests: even a thin wall cannot join two crowds.
func _fusion_path_clear(from: Vector2, to: Vector2, radius: float) -> bool:
	var low := from.min(to) - Vector2.ONE * radius
	var high := from.max(to) + Vector2.ONE * radius
	var ray := to - from
	var ground := ground_height(from)
	var steps := maxi(1, ceili(ray.length() / (HEIGHT_STEP * 0.5)))
	for step in range(1, steps + 1):
		if absf(ground_height(from + ray * (float(step) / steps)) - ground) > FUSION_DECK_GAP:
			return false
	for cz in range(_cell_z(low.y), _cell_z(high.y) + 1):
		for cx in range(_cell_x(low.x), _cell_x(high.x) + 1):
			var cell := cz * _grid_w + cx
			for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
				var obstacle := _cell_obstacle_items[k]
				if not _obstacle_overlaps_height(obstacle, ground, 2.2, (from + to) * 0.5):
					continue
				var center := _obstacle_center[obstacle]
				var half := _obstacle_half[obstacle] + Vector2.ONE * radius
				if _obstacle_circle[obstacle] != 0:
					var t := clampf((center - from).dot(ray) / maxf(0.000001, ray.length_squared()), 0.0, 1.0)
					if (from + ray * t).distance_squared_to(center) <= half.x * half.x:
						return false
				else:
					var near := 0.0
					var far := 1.0
					for axis in 2:
						if absf(ray[axis]) < 0.000001:
							if absf(from[axis] - center[axis]) > half[axis]:
								far = -1.0
						else:
							var a := (center[axis] - half[axis] - from[axis]) / ray[axis]
							var b := (center[axis] + half[axis] - from[axis]) / ray[axis]
							near = maxf(near, minf(a, b))
							far = minf(far, maxf(a, b))
					if near <= far:
						return false
	return true

func _dense_group_valid(seed: int, player: Vector2) -> bool:
	var offset := seed * FUSION_MAX
	for n in _dense_count[seed]:
		var slot := _dense_members[offset + n]
		if not _fusion_eligible(slot, player) or _generation[slot] != _dense_generation[offset + n] \
				or _type[slot] != _type[seed] or absf(_y[slot] - _y[seed]) > FUSION_DECK_GAP \
				or _pos[slot].distance_squared_to(_pos[seed]) > FUSION_RANGE * FUSION_RANGE:
			return false
	return true

## At most 256 seeds and 48 local grid entries per seed, never all-pairs.
## Stored constituent identities must stay together across repeated observations.
func _update_fusions(delta: float) -> void:
	_fusion_clock += delta
	if _active_count < FUSION_MIN or not is_instance_valid(target) or not target.active:
		_dense_count.fill(0)
		return
	var player := Vector2(target.global_position.x, target.global_position.z)
	var events := 0
	var seeds := mini(FUSION_SEEDS, _active_count)
	var observation_gap := maxf(0.35, delta * ceili(float(_active_count) / FUSION_SEEDS) * 1.5)
	for attempt in seeds:
		if _fusion_cursor >= _active_count:
			_fusion_cursor = 0
		var seed := _active[_fusion_cursor]
		_fusion_cursor += 1
		if not _fusion_eligible(seed, player):
			_dense_count[seed] = 0
			continue
		if _dense_count[seed] >= FUSION_MIN:
			if _fusion_clock - _dense_last[seed] > observation_gap or not _dense_group_valid(seed, player):
				_dense_count[seed] = 0
			else:
				_dense_last[seed] = _fusion_clock
				if _fusion_clock - _dense_since[seed] >= FUSION_DENSITY_TIME and _fusion_clock - _fusion_times[_fusion_time_cursor] >= 0.5:
					if _fuse_group(seed, player):
						_fusion_events[events] = seed
						_fusion_event_generation[events] = _generation[seed]
						events += 1
						_fusion_times[_fusion_time_cursor] = _fusion_clock
						_fusion_time_cursor = (_fusion_time_cursor + 1) % 4
					else:
						_dense_count[seed] = 0
				continue
		var offset := seed * FUSION_MAX
		_dense_members[offset] = seed
		_dense_generation[offset] = _generation[seed]
		var count := 1
		var checks := 0
		var p := _pos[seed]
		for cz in range(_cell_z(p.y - FUSION_RANGE), _cell_z(p.y + FUSION_RANGE) + 1):
			for cx in range(_cell_x(p.x - FUSION_RANGE), _cell_x(p.x + FUSION_RANGE) + 1):
				var cell := cz * _grid_w + cx
				for k in range(_cell_start[cell], _cell_start[cell + 1]):
					if checks >= FUSION_CHECKS or count >= FUSION_MAX:
						break
					checks += 1
					var slot := _cell_items[k]
					if slot == seed or _type[slot] != _type[seed] or not _fusion_eligible(slot, player):
						continue
					if absf(_y[slot] - _y[seed]) > FUSION_DECK_GAP or _pos[slot].distance_squared_to(p) > FUSION_RANGE * FUSION_RANGE:
						continue
					_dense_members[offset + count] = slot
					_dense_generation[offset + count] = _generation[slot]
					count += 1
		_dense_count[seed] = count if count >= FUSION_MIN else 0
		_dense_since[seed] = _fusion_clock
		_dense_last[seed] = _fusion_clock
	if events == 0:
		return
	# Finish transactions and remove all stale active/grid entries before callbacks.
	_rebuild_grid()
	for n in events:
		var slot := _fusion_events[n]
		if is_alive(slot) and _generation[slot] == _fusion_event_generation[n]:
			enemy_fused.emit(slot, _members[slot])

func _fuse_group(seed: int, player: Vector2) -> bool:
	if not _dense_group_valid(seed, player):
		return false
	var count := _dense_count[seed]
	var offset := seed * FUSION_MAX
	var center := Vector2.ZERO
	var health := 0.0
	var maximum := 0.0
	for n in count:
		var slot := _dense_members[offset + n]
		center += _pos[slot]
		health += _hp[slot]
		maximum += _max_hp[slot]
	center /= float(count)
	var final_radius := _t_radius[_type[seed]] * FUSION_SCALE * FUSION_SHOULDER
	if center.distance_squared_to(player) < 16.0 or is_blocked(center, final_radius) \
			or _rect_rough(Rect2(center - Vector2.ONE * final_radius, Vector2.ONE * final_radius * 2.0)) \
			or absf(ground_height(center) - _y[seed]) > FUSION_DECK_GAP:
		return false
	for n in count:
		var slot := _dense_members[offset + n]
		if not _fusion_path_clear(_pos[slot], center, _radius[slot]):
			return false
	# No callbacks during mutation; absorption is neither a death nor a reward.
	for n in range(1, count):
		_recycle(_dense_members[offset + n])
	_generation[seed] += 1
	_members[seed] = count
	_fusion_allowed[seed] = 0
	_dense_count[seed] = 0
	_hp[seed] = health
	_max_hp[seed] = maximum
	_life_hp[seed] = health
	_daze_time[seed] = 0.0
	_daze_used[seed] = 0
	_pos[seed] = center
	_y[seed] = ground_height(center)
	_knock[seed] = Vector2.ZERO
	_grow[seed] = 0.0
	_set_body(seed, 1.0)
	if final_radius > BIG_RADIUS and not _big.has(seed):
		_big.append(seed)
	_largest_radius = maxf(_largest_radius, final_radius)
	alive_count -= count - 1
	_reset_animation(seed)
	return true

func _recycle(slot: int) -> void:
	_hide_anatomy_slot(slot)
	var big_at := _big.find(slot)
	if big_at >= 0:
		_big.remove_at(big_at)
	_state[slot] = FREE
	_generation[slot] += 1
	_fusion_allowed[slot] = 0
	_members[slot] = 1
	_body[slot] = 1.0
	_radius[slot] = 0.0
	_height[slot] = 0.0
	_mass[slot] = 0.0
	_grow[slot] = 0.0
	_dense_count[slot] = 0
	_hp[slot] = 0.0
	_max_hp[slot] = 0.0
	_knock[slot] = Vector2.ZERO
	_aim[slot] = Vector2.ZERO
	_attack_target[slot] = Vector3.ZERO
	_has_lane[slot] = 0
	_timer[slot] = 0.0
	_cooldown[slot] = 0.0
	_flash[slot] = 0.0
	_death[slot] = 0.0
	_slow[slot] = 1.0
	_slow_time[slot] = 0.0
	_burn_time[slot] = 0.0
	_burn_tick[slot] = 0.0
	_burn_damage[slot] = 0.0
	_exposed[slot] = 0.0
	_stunned[slot] = 0.0
	_daze_time[slot] = 0.0
	_daze_used[slot] = 0
	_life_hp[slot] = 0.0
	_clear_pinball_state(slot)
	_anim_clip[slot] = -1
	_anim_frame[slot] = 0.0
	_anim_speed[slot] = 0.0
	_stamp[slot] = 0
	_cell_of[slot] = -1
	_free[_free_count] = slot
	_free_count += 1

# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	_update_burns(delta)
	_rebuild_grid()
	_update_fusions(delta)
	_flow_timer -= delta
	if _flow_timer <= 0.0 and is_instance_valid(target):
		_flow_timer = FLOW_INTERVAL
		_flow.update(Vector2(target.global_position.x, target.global_position.z), target.global_position.y - 0.9)
	var chasing := is_instance_valid(target) and target.active
	var player := Vector2.ZERO
	var player_y := 0.0
	if is_instance_valid(target):
		player = Vector2(target.global_position.x, target.global_position.z)
		player_y = target.global_position.y - 0.9
	var contact := 0.0
	var knock_decay := minf(1.0, 7.0 * delta)
	var turn := minf(1.0, 10.0 * delta)
	var origin := _area.position
	var inverse_cell := 1.0 / CELL
	var last_x := _grid_w - 1
	var last_z := _grid_h - 1
	_combo_budget = COMBO_BUDGET
	_hype_timer -= delta
	var hype_pulse := _hype_timer <= 0.0
	if hype_pulse:
		_hype_timer = HYPE_PULSE
		_hype_pulses += 1
	for a in _active_count:
		var i := _active[a]
		if not is_alive(i):
			continue
		if _members[i] > 1 and _grow[i] < FUSION_GROW_TIME:
			_grow[i] = minf(FUSION_GROW_TIME, _grow[i] + delta)
			var progress := _grow[i] / FUSION_GROW_TIME
			_set_body(i, lerpf(1.0, FUSION_SCALE, progress * progress * (3.0 - 2.0 * progress)))
		_exposed[i] = maxf(0.0, _exposed[i] - delta)
		var dazed := _daze_time[i] > 0.0
		var stunned := _stunned[i] > 0.0 or dazed
		_daze_time[i] = maxf(0.0, _daze_time[i] - delta)
		_stunned[i] = maxf(0.0, _stunned[i] - delta)
		_frost_time[i] = maxf(0.0, _frost_time[i] - delta)
		_charge_time[i] = maxf(0.0, _charge_time[i] - delta)
		if _buff_time[i] > 0.0:
			_buff_time[i] -= delta
			if _buff_time[i] <= 0.0:
				_buff_time[i] = 0.0
				_buff_level[i] = 0
		var type := _type[i]
		if hype_pulse and not stunned and chasing and _t_behavior[type] == HordeEnemyDefinition.Behavior.HYPE:
			_hype_aura(i, _hype_pulses)
		var p := _pos[i]
		var to := player - p
		var distance := to.length()
		var direction := to / distance if distance > 0.001 else Vector2.ZERO
		var radius := _radius[i]
		var reach := radius + PLAYER_RADIUS
		var move := Vector2.ZERO
		var rise := player_y - _y[i]
		# Follow the flow field (around walls, up ramps) unless close on the same
		# level, or with the player below within DROP_RANGE: then go straight in,
		# walking off ledges and falling.
		var route := direction
		var straight := (distance <= DIRECT_RANGE and rise <= LEVEL_GAP) or (rise < -LEVEL_GAP and distance <= DROP_RANGE)
		if not straight:
			var cell := _cell_of[i]
			var flow := _flow.direction_at(cell, _y[i])
			if flow != Vector2.ZERO:
				# Drift toward the cell's centre line (sideways only): obstacles can
				# poke into a cell's edge, and a body there would push straight into
				# the face. A slight pull toward the player smooths crowds on one
				# level; with the player up on a deck it drags bodies into corners.
				var offset := _cell_center[cell] - p
				var side := Vector2(-flow.y, flow.x)
				var steer := flow + side * (side.dot(offset) * 0.5)
				if rise <= LEVEL_GAP:
					steer += direction * 0.25
				route = steer.normalized()
		var face := route
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta / FLASH_TIME)
		if chasing and not stunned:
			if i == _boss_index and _boss_controlled:
				move = _boss_velocity
				face = _boss_facing
			else:
				# Flank only on open same-level floor: on ramps/decks the side push
				# would shove bodies off the route into cliffs and stall the climb.
				var flank := absf(rise) <= LEVEL_GAP and _cell_flat[_cell_of[i]] != 0 and absf(_y[i] - player_y) <= LEVEL_GAP
				move = _steer(i, type, route, direction, distance, delta, flank) * _buff_speed(i)
			if _mode[i] == Mode.CHARGE or _mode[i] == Mode.WINDUP or _mode[i] == Mode.RECOVER:
				face = _aim[i]
			var touching := distance < reach + 0.15 and rise < _height[i] and rise > -1.9
			if touching and _mode[i] != Mode.RECOVER:
				contact += _t_contact[type] * _buff_damage(i) * (minf(2.0, 1.0 + float(_members[i] - 1) * 0.15) if _members[i] > 1 else 1.0)
				if _mode[i] == Mode.CHARGE and not (i == _boss_index and _boss_controlled):
					target.take_damage(ceili(_t_contact[type] * 2.0))
					_end_charge(i, type)
			if distance < reach and _mode[i] != Mode.CHARGE:
				move = Vector2.ZERO
		if _slow_time[i] > 0.0:
			_slow_time[i] -= delta
			move *= _slow[i]
		var separation := Vector2.ZERO if dazed else _separation(i, p, radius)
		p += (move + _knock[i]) * delta + separation
		var launched := _launch_time[i] > 0.0
		_knock[i] -= _knock[i] * (minf(1.0, LAUNCH_DECAY * delta) if launched else knock_decay)
		var clamped := _sweep_move(i, p)
		var feet := _y[i]
		var landing := clampi(int((clamped.y - origin.y) * inverse_cell), 0, last_z) * _grid_w \
				+ clampi(int((clamped.x - origin.x) * inverse_cell), 0, last_x)
		# Floor to plain floor (most of the crowd) needs no height work.
		if feet != 0.0 or _cell_flat[landing] == 0 or _vy[i] > 0.0:
			clamped = _walkable(i, _pos[i], clamped)
			# Walk up ramps at once; fall off ledges under gravity.
			if feet > _step_ground + 0.001 or _vy[i] > 0.0:
				_vy[i] -= FALL_GRAVITY * delta
				var next_y := maxf(_step_ground, feet + _vy[i] * delta)
				if _vy[i] > 0.0:
					# Deck undersides/ceilings stop launch at the actual body height.
					for k in range(_cell_obstacle_start[landing], _cell_obstacle_start[landing + 1]):
						var o := _cell_obstacle_items[k]
						var half := _obstacle_half[o] + Vector2.ONE * radius
						if absf(clamped.x - _obstacle_center[o].x) > half.x or absf(clamped.y - _obstacle_center[o].y) > half.y:
							continue
						var bottom := _obstacle_bottom[o] + _obstacle_height_slope[o].dot(clamped - _obstacle_center[o])
						if bottom >= feet + _height[i] - 0.02 and next_y + _height[i] > bottom:
							next_y = maxf(feet, bottom - _height[i])
							_vy[i] = 0.0
				_y[i] = next_y
			else:
				_y[i] = _step_ground
				_vy[i] = 0.0
		if launched:
			_track_launch(i, p, clamped, delta)
		if _mode[i] == Mode.CHARGE and not clamped.is_equal_approx(p):
			_end_charge(i, type)
		_pos[i] = clamped
		if chasing and _t_behavior[type] == HordeEnemyDefinition.Behavior.BOUNCER:
			_block_player(i)
		if face != Vector2.ZERO and chasing and not stunned:
			var desired := atan2(-face.x, -face.y)
			if _t_turn_speed[type] > 0.0:
				_yaw[i] = rotate_toward(_yaw[i], desired, _t_turn_speed[type] * delta)
			else:
				_yaw[i] = lerp_angle(_yaw[i], desired, turn)
	_resolve_impacts()
	_update_dying(delta)
	_update_projectiles(delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if chasing and contact > 0.0 and _contact_timer <= 0.0:
		_contact_timer = contact_tick
		target.take_damage(ceili(minf(contact, contact_cap)))

## Accepts a move unless it climbs a cliff; then slides along one axis or stays.
func _walkable(i: int, from: Vector2, to: Vector2) -> Vector2:
	var limit := _y[i] + CLIMB + from.distance_to(to) * CLIMB_SLOPE
	_step_ground = ground_height(to)
	if is_finite(_step_ground) and _step_ground <= limit:
		return to
	var slide := Vector2(to.x, from.y)
	_step_ground = ground_height(slide)
	if is_finite(_step_ground) and _step_ground <= limit:
		return slide
	slide = Vector2(from.x, to.y)
	_step_ground = ground_height(slide)
	if is_finite(_step_ground) and _step_ground <= limit:
		return slide
	_step_ground = ground_height(from)
	return from

## `route` is the path direction (flow field); `direct` points straight at the
## player and is used for aiming attacks and backing off.
func _steer(i: int, type: int, route: Vector2, direct: Vector2, distance: float, delta: float, flank: bool = false) -> Vector2:
	var definition := _defs[type]
	var behavior := _t_behavior[type]
	# Hype quickens every committed attack cycle, never health.
	_cooldown[i] = maxf(0.0, _cooldown[i] - delta * (HYPE_COOLDOWN_SCALE if _buff_time[i] > 0.0 else 1.0))
	match _mode[i]:
		Mode.WINDUP:
			_timer[i] -= delta
			if _timer[i] <= 0.0:
				_cooldown[i] = definition.attack_cooldown
				match behavior:
					HordeEnemyDefinition.Behavior.RANGED, HordeEnemyDefinition.Behavior.THROWER:
						_fire(i, type)
						_end_charge(i, type)
					HordeEnemyDefinition.Behavior.BOUNCER:
						_shove(i, type)
						_end_charge(i, type)
					HordeEnemyDefinition.Behavior.HYPE:
						# RECOVER is the surge: a stationary, louder aura and punish window.
						_end_charge(i, type)
					_:
						_mode[i] = Mode.CHARGE
						_timer[i] = definition.charge_duration
			return Vector2.ZERO
		Mode.CHARGE:
			_timer[i] -= delta
			if _timer[i] <= 0.0:
				_end_charge(i, type)
				return Vector2.ZERO
			return _aim[i] * definition.charge_speed
		Mode.RECOVER:
			_timer[i] -= delta
			if _timer[i] <= 0.0:
				_mode[i] = Mode.SEEK
			return Vector2.ZERO
	var move := route * _t_speed[type] * (0.68 if _members[i] > 1 else 1.0)
	if behavior == HordeEnemyDefinition.Behavior.SWARM and flank and _members[i] == 1 and distance > 2.5 and distance < 14.0 and route.dot(direct) > 0.8:
		# Stable left/right lanes make the crowd surround instead of forming a line.
		var side := Vector2(-direct.y, direct.x) * (1.0 if sin(_phase[i]) >= 0.0 else -1.0)
		move = (route + side * 0.75).normalized() * _t_speed[type]
	elif behavior == HordeEnemyDefinition.Behavior.RANGED:
		if _has_lane[i] != 0:
			if distance < definition.preferred_range - 1.5:
				move = -direct * _t_speed[type] * 0.7
			elif distance < definition.preferred_range + 1.5:
				move = Vector2.ZERO
		if _cooldown[i] <= 0.0 and distance <= definition.attack_range:
			var from := Vector3(_pos[i].x, _y[i] + _height[i] * 0.7, _pos[i].y)
			_has_lane[i] = 1 if _lane_clear(from, target.global_position) else 0
			if _has_lane[i] != 0:
				_begin_windup(i, definition, direct)
			else:
				_cooldown[i] = 0.3
	elif behavior == HordeEnemyDefinition.Behavior.CHARGER or behavior == HordeEnemyDefinition.Behavior.RUNNER or behavior == HordeEnemyDefinition.Behavior.CARRIER:
		if _cooldown[i] <= 0.0 and distance <= definition.charge_range and distance > 1.3:
			var from := enemy_position(i)
			if _lane_clear(from, target.global_position):
				_begin_windup(i, definition, direct)
				return Vector2.ZERO
			_cooldown[i] = 0.3
	elif behavior == HordeEnemyDefinition.Behavior.THROWER:
		# Holds range like a spitter but lobs over the crowd at a committed spot.
		if distance < definition.preferred_range - 1.5:
			move = -direct * _t_speed[type] * 0.7
		elif distance < definition.preferred_range + 1.5:
			move = Vector2.ZERO
		if _cooldown[i] <= 0.0 and distance <= definition.attack_range:
			var release := Vector3(_pos[i].x, _y[i] + _height[i] + 1.2, _pos[i].y)
			if _lane_clear(release, target.global_position + Vector3.UP * 0.6):
				_begin_windup(i, definition, direct)
				return Vector2.ZERO
			_cooldown[i] = 0.3
	elif behavior == HordeEnemyDefinition.Behavior.BOUNCER:
		# Plants a body's width away, physically holding the space in front.
		if distance < definition.preferred_range:
			move = Vector2.ZERO
		var level := absf(target.global_position.y - 0.9 - _y[i]) <= LEVEL_GAP
		if _cooldown[i] <= 0.0 and level and distance <= definition.attack_range:
			_begin_windup(i, definition, direct)
			return Vector2.ZERO
	elif behavior == HordeEnemyDefinition.Behavior.HYPE:
		# Hangs back behind the crowd and backs off when approached.
		if distance < definition.preferred_range - 1.5:
			move = -direct * _t_speed[type]
		elif distance < definition.preferred_range + 1.5:
			move = Vector2.ZERO
		if _cooldown[i] <= 0.0 and distance <= definition.attack_range:
			_begin_windup(i, definition, direct)
			return Vector2.ZERO
	return move

func _begin_windup(i: int, definition: HordeEnemyDefinition, direct: Vector2) -> void:
	_mode[i] = Mode.WINDUP
	_timer[i] = definition.telegraph_duration
	_aim[i] = Vector2(-sin(_yaw[i]), -cos(_yaw[i])) if definition.behavior == HordeEnemyDefinition.Behavior.CARRIER else direct
	_attack_target[i] = target.global_position

func _end_charge(i: int, type: int) -> void:
	_mode[i] = Mode.RECOVER
	_timer[i] = _defs[type].recovery_duration
	_cooldown[i] = _defs[type].attack_cooldown

## Shared query object: no dictionary/query allocation per enemy attack.
func _lane_clear(from: Vector3, to: Vector3) -> bool:
	if from.is_equal_approx(to):
		return true
	_lane_query.from = from
	_lane_query.to = to
	_lane_query.collision_mask = 1
	_lane_query.collide_with_areas = false
	var body := target.get_rid() if is_instance_valid(target) else RID()
	if body != _lane_excluded:
		_lane_excluded = body
		var excluded: Array[RID] = []
		if body.is_valid():
			excluded.append(body)
		_lane_query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(_lane_query).is_empty()

## Substeps prevent fast charges and explosions tunnelling through thin walls.
func _sweep_move(i: int, to: Vector2) -> Vector2:
	var from := _pos[i]
	var steps := maxi(1, ceili(from.distance_to(to) / maxf(0.12, _radius[i] * 0.6)))
	var step := (to - from) / float(steps)
	var p := from
	for n in steps:
		p = _walkable(i, p, _constrain(p + step, _radius[i], _y[i]))
	return p

func _separation(i: int, p: Vector2, radius: float) -> Vector2:
	var push := Vector2.ZERO
	var checks := 0
	var feet := _y[i]
	var cell := _cell_of[i]
	var cx := cell % _grid_w
	var cz := cell / _grid_w
	var rings := maxi(1, ceili((radius + _largest_radius) / CELL))
	# Visit near cells first; enlarged broadphase must not spend the entire
	# neighbor budget on distant bodies before reaching the local crowd.
	for ring in range(rings + 1):
		for nz in range(cz - ring, cz + ring + 1):
			if nz < 0 or nz >= _grid_h:
				continue
			for nx in range(cx - ring, cx + ring + 1):
				if nx < 0 or nx >= _grid_w or (ring > 0 and abs(nx - cx) != ring and abs(nz - cz) != ring):
					continue
				var neighbor := nz * _grid_w + nx
				for k in range(_cell_start[neighbor], _cell_start[neighbor + 1]):
					var j := _cell_items[k]
					if j == i or not is_alive(j):
						continue
					var away := p - _pos[j]
					var d2 := away.length_squared()
					var reach := radius + _radius[j]
					# Bodies on another level never shove.
					if d2 < reach * reach and absf(feet - _y[j]) <= LEVEL_GAP:
						if d2 < 0.000001:
							away = Vector2.from_angle(float((i * 37 + j * 17) % 256) * TAU / 256.0) * 0.001
							d2 = 0.000001
						var d := sqrt(d2)
						push += away * ((reach - d) / d) * minf(2.0, _mass[j] / _mass[i])
					checks += 1
					if checks >= MAX_NEIGHBOR_CHECKS:
						return (push * SEPARATION).limit_length(0.25)
	return (push * SEPARATION).limit_length(0.25)

func _constrain(p: Vector2, radius: float, feet: float = NAN) -> Vector2:
	p.x = clampf(p.x, _area.position.x + radius, _area.end.x - radius)
	p.y = clampf(p.y, _area.position.y + radius, _area.end.y - radius)
	var cell := _cell_z(p.y) * _grid_w + _cell_x(p.x)
	if is_nan(feet):
		feet = ground_height(p)
	for k in range(_cell_obstacle_start[cell], _cell_obstacle_start[cell + 1]):
		var o := _cell_obstacle_items[k]
		if not _obstacle_overlaps_height(o, feet, 2.2, p):
			continue
		var center := _obstacle_center[o]
		var half := _obstacle_half[o]
		var delta := p - center
		if _obstacle_circle[o] == 1:
			var reach := half.x + radius
			var d2 := delta.length_squared()
			if d2 < reach * reach:
				p = center + (delta / sqrt(d2) if d2 > 0.000001 else Vector2.RIGHT) * reach
		else:
			var gap_x := half.x + radius - absf(delta.x)
			var gap_z := half.y + radius - absf(delta.y)
			if gap_x > 0.0 and gap_z > 0.0:
				if gap_x < gap_z:
					p.x += gap_x * signf(delta.x if delta.x != 0.0 else 1.0)
				else:
					p.y += gap_z * signf(delta.y if delta.y != 0.0 else 1.0)
	return p

func _rebuild_grid() -> void:
	_cell_cursor.fill(0)
	var n := 0
	for a in _active_count:
		var slot := _active[a]
		if _state[slot] != ALIVE:
			continue
		_active[n] = slot
		n += 1
		var p := _pos[slot]
		var cell := _cell_z(p.y) * _grid_w + _cell_x(p.x)
		_cell_of[slot] = cell
		_cell_cursor[cell] += 1
	_active_count = n
	var total := 0
	for cell in _cells:
		_cell_start[cell] = total
		var count := _cell_cursor[cell]
		_cell_cursor[cell] = total
		total += count
	_cell_start[_cells] = total
	for a in n:
		var slot := _active[a]
		var cell := _cell_of[slot]
		_cell_items[_cell_cursor[cell]] = slot
		_cell_cursor[cell] += 1

func _update_dying(delta: float) -> void:
	var n := 0
	for d in _dying_count:
		var slot := _dying[d]
		_death[slot] -= delta
		if _death[slot] > 0.0:
			var motion := _pos[slot] + _knock[slot] * delta
			_pos[slot] = _sweep_move(slot, motion)
			_knock[slot] *= maxf(0.0, 1.0 - delta * 3.0)
			var floor_y := ground_height(_pos[slot])
			_vy[slot] -= FALL_GRAVITY * delta
			_y[slot] = maxf(floor_y, _y[slot] + _vy[slot] * delta)
			_dying[n] = slot
			n += 1
		else:
			_recycle(slot)
	_dying_count = n

# ---------------------------------------------------------------- projectiles

func _fire(i: int, type: int) -> void:
	if not is_instance_valid(target):
		return
	var definition := _defs[type]
	var damage_amount := definition.projectile_damage * _buff_damage(i)
	if _t_behavior[type] == HordeEnemyDefinition.Behavior.THROWER:
		_lob(i, damage_amount)
		return
	var from := Vector3(_pos[i].x, _y[i] + _height[i] * 0.7, _pos[i].y)
	var aim := _attack_target[i] - from
	if not _lane_clear(from, _attack_target[i]):
		return
	# A readable committed three-lane fan denies space, not a tracking hit.
	for lane in 3:
		_add_shot(from, aim.normalized().rotated(Vector3.UP, float(lane - 1) * 0.14) * definition.projectile_speed,
			damage_amount, 0, 0.0, 30.0 / maxf(1.0, definition.projectile_speed) + 1.0)

## One ballistic bottle at the spot the player stood when the windup began:
## moving off it is the counterplay, parrying returns it as a line drive.
func _lob(i: int, damage_amount: float) -> void:
	var start := Vector3(_pos[i].x, _y[i] + _height[i] * 0.95, _pos[i].y)
	var land := _attack_target[i]
	var floor_y := ground_height(Vector2(land.x, land.z))
	land.y = floor_y if is_finite(floor_y) else land.y - 0.9
	var apex := maxf(start.y, land.y) + clampf(1.2 + start.distance_to(land) * 0.08, 1.2, 2.6)
	var up := sqrt(2.0 * BOTTLE_GRAVITY * (apex - start.y))
	var down := sqrt(2.0 * BOTTLE_GRAVITY * (apex - land.y))
	var flight := (up + down) / BOTTLE_GRAVITY
	var horizontal := Vector2(land.x - start.x, land.z - start.z) / flight
	_add_shot(start, Vector3(horizontal.x, up, horizontal.y), damage_amount, SHOT_LOBBED, BOTTLE_SPLASH, flight + 1.0)

func _update_projectiles(delta: float) -> void:
	if not is_instance_valid(target) or not target.active:
		_shot_count = 0
		return
	var center := target.global_position
	var hit_reach := projectile_radius + PLAYER_RADIUS
	var player_body := target.get_rid()
	if player_body != _shot_excluded:
		_shot_excluded = player_body
		var excluded: Array[RID] = [player_body]
		_shot_query.exclude = excluded
	_shot_impact_count = 0
	var n := 0
	for s in _shot_count:
		var flags := _shot_flags[s]
		var velocity := _shot_vel[s]
		var life := _shot_life[s] - delta
		var p := _shot_pos[s]
		if flags & SHOT_REFLECTED != 0:
			if flags & SHOT_HOMING != 0:
				velocity = _home(s, p, velocity, delta)
				flags = _shot_flags[s]
			# Returned shots never touch the player; enemies and walls are swept.
			if _sweep_reflected(s, p, velocity, delta) or life <= 0.0:
				continue
			p += velocity * delta
		else:
			if flags & SHOT_LOBBED != 0:
				velocity.y -= BOTTLE_GRAVITY * delta
			p += velocity * delta
			var closest := Vector3(center.x, clampf(p.y, center.y - 0.9, center.y + 0.9), center.z)
			if p.distance_squared_to(closest) < hit_reach * hit_reach:
				if flags & SHOT_LOBBED != 0:
					_bottle_splash(p, _shot_damage[s], _shot_splash[s])
				else:
					target.take_damage(ceili(_shot_damage[s]))
				continue
			if life <= 0.0 or p.y < ground_height(Vector2(p.x, p.z)) or is_blocked(Vector2(p.x, p.z), 0.0, p.y - projectile_radius, projectile_radius * 2.0):
				if flags & SHOT_LOBBED != 0:
					_bottle_splash(p, _shot_damage[s], _shot_splash[s])
				continue
		_shot_pos[n] = p
		_shot_vel[n] = velocity
		_shot_life[n] = life
		_shot_damage[n] = _shot_damage[s]
		_shot_flags[n] = flags
		_shot_splash[n] = _shot_splash[s]
		_shot_target[n] = _shot_target[s]
		_shot_target_generation[n] = _shot_target_generation[s]
		n += 1
	_shot_count = n
	_resolve_shot_impacts()

func _home(s: int, p: Vector3, velocity: Vector3, delta: float) -> Vector3:
	var slot := _shot_target[s]
	if not is_alive(slot) or _generation[slot] != _shot_target_generation[s]:
		_shot_flags[s] &= ~SHOT_HOMING
		return velocity
	var desired := (enemy_position(slot) - p).normalized() * velocity.length()
	return velocity.move_toward(desired, REFLECT_TURN * velocity.length() * delta)

## The splash of a landed/struck bottle hurts the player only within its radius.
func _bottle_splash(at: Vector3, damage_amount: float, radius: float) -> void:
	if is_instance_valid(_fx):
		_fx.burst_bottle(at)
	var center := target.global_position
	var closest := Vector3(center.x, clampf(at.y, center.y - 0.9, center.y + 0.9), center.z)
	if at.distance_squared_to(closest) <= radius * radius and _lane_clear(at + Vector3.UP * 0.2, center):
		target.take_damage(ceili(damage_amount))

## Sweeps this frame's segment: nearest enemy body vs world collider vs floor.
func _sweep_reflected(s: int, p: Vector3, velocity: Vector3, delta: float) -> bool:
	var step := velocity * delta
	var length := step.length()
	if length <= 0.00001:
		return false
	var direction := step / length
	var reach := length + projectile_radius
	var enemy := -1
	var enemy_t := INF
	if raycast(p, direction, reach, 1, _sweep_hits, _sweep_distances) > 0:
		enemy = _sweep_hits[0]
		enemy_t = _sweep_distances[0]
	_shot_query.from = p
	_shot_query.to = p + direction * reach
	var hit := get_world_3d().direct_space_state.intersect_ray(_shot_query)
	var wall_t := INF
	var collider: Object = null
	if not hit.is_empty():
		wall_t = p.distance_to(hit["position"])
		collider = hit["collider"]
	var end := p + step
	var floor_y := ground_height(Vector2(end.x, end.z))
	if wall_t == INF and (not is_finite(floor_y) or end.y < floor_y or not _area.has_point(Vector2(end.x, end.z))):
		wall_t = length
	if enemy >= 0 and enemy_t <= wall_t:
		_queue_shot_impact(s, p, p + direction * enemy_t, enemy, null)
		return true
	if wall_t < INF:
		_queue_shot_impact(s, p, p + direction * maxf(0.0, wall_t - projectile_radius), -1, collider)
		return true
	return false

func _queue_shot_impact(s: int, from: Vector3, at: Vector3, slot: int, collider: Object) -> void:
	if _shot_impact_count >= _shot_impact_pos.size():
		return
	var k := _shot_impact_count
	_shot_impact_pos[k] = at
	_shot_impact_origin[k] = from
	_shot_impact_slot[k] = slot
	_shot_impact_generation[k] = _generation[slot] if slot >= 0 else -1
	_shot_impact_damage[k] = _shot_damage[s]
	_shot_impact_splash[k] = _shot_splash[s]
	_shot_impact_collider[k] = collider
	_shot_impact_count += 1

## Returned projectile hits as one RETURN action: direct body hit, shootable
## world object and (bottles) a walled splash, all in the same scope.
func _resolve_shot_impacts() -> void:
	var count := _shot_impact_count
	_shot_impact_count = 0
	for k in count:
		var at := _shot_impact_pos[k]
		var from := _shot_impact_origin[k]
		var amount := _shot_impact_damage[k]
		var slot := _shot_impact_slot[k]
		var collider := _shot_impact_collider[k]
		_shot_impact_collider[k] = null
		var outer := _action_open()
		if slot >= 0 and is_alive(slot) and _generation[slot] == _shot_impact_generation[k]:
			var push := (at - from).normalized() * 8.0
			damage_combined(slot, amount, from, 0.0, Vector3(push.x, 0.0, push.z), DamageType.Kind.KINETIC, false)
		if is_instance_valid(collider) and collider.has_method(&"take_hit"):
			collider.take_hit(amount, at)
		if _shot_impact_splash[k] > 0.0:
			var back := (from - at).normalized() * 0.3
			_radius_core(at + back, _shot_impact_splash[k], amount * 0.6, 8.0, DamageType.Kind.KINETIC, false)
		_action_close(outer, at, "RETURN")
		if is_instance_valid(_fx):
			_fx.burst_return(at)

# ---------------------------------------------------------------- rendering

func _process(delta: float) -> void:
	var player := Vector2(INF, INF)
	if is_instance_valid(target):
		player = Vector2(target.global_position.x, target.global_position.z)
	for type in _defs.size():
		_draw_type(type, delta, player)
	_draw_projectiles()

func _draw_type(type: int, delta: float, player: Vector2) -> void:
	var renderer := _renderers[type]
	var multimesh := renderer.multimesh
	var buffer := _buffers[type]
	# Detach from the array so writes do not copy-on-write the shared data.
	_buffers[type] = PackedFloat32Array()
	var stride := _t_stride[type]
	var animated := stride == 20
	var needed := 0
	for a in _active_count:
		if _type[_active[a]] == type and _state[_active[a]] == ALIVE:
			needed += 1
	for d in _dying_count:
		if _type[_dying[d]] == type:
			needed += 1
	if needed > multimesh.instance_count:
		var capacity := multimesh.instance_count
		while capacity < needed:
			capacity *= 2
		multimesh.instance_count = mini(capacity, CAPACITY)
		buffer.resize(multimesh.instance_count * stride)
	var scale := _t_scale[type]
	var reach := 0.0
	var k := 0
	for a in _active_count:
		var slot := _active[a]
		if _type[slot] == type and _state[slot] == ALIVE:
			var body_scale := scale * _body[slot]
			k = _write_instance(buffer, k, slot, body_scale, body_scale, _flash[slot], stride)
			if animated:
				reach = _radius[slot] + PLAYER_RADIUS + CONTACT_ANIMATION_MARGIN
				_animate(buffer, k - 8, slot, type, delta, _pos[slot].distance_squared_to(player) < reach * reach)
	var death_clip := _t_clip_death[type]
	var duration := _t_death_time[type]
	for d in _dying_count:
		var slot := _dying[d]
		if _type[slot] != type:
			continue
		var left := _death[slot] / duration
		var death_scale := scale * _body[slot]
		if death_clip >= 0:
			# Play the death clip over most of the time, then shrink away quickly.
			var fade := clampf(left / DEATH_FADE, 0.02, 1.0)
			k = _write_instance(buffer, k, slot, death_scale * fade, death_scale * fade, 0.35 * left * left, stride)
			var progress := minf(1.0, (1.0 - left) / (1.0 - DEATH_FADE))
			_write_clip(buffer, k - 8, death_clip, progress * (_clip_count[death_clip] - 1.0), 0.0)
			continue
		# Collapse inward: slight widen on impact, then shrink away to nothing.
		var widen := 1.0 + 0.15 * sin(left * PI)
		# Dying bodies glow faintly and fade with their collapse; mass kills
		# must not paint the view white.
		k = _write_instance(buffer, k, slot, death_scale * maxf(0.02, left) * widen, death_scale * maxf(0.02, left * left), 0.35 * left, stride)
		if animated:
			# Freeze the pose the enemy died in.
			var clip := _anim_clip[slot] if _anim_clip[slot] >= 0 else _t_clip_move[type]
			_write_clip(buffer, k - 8, clip, _anim_frame[slot], _clip_loop[clip])
	if multimesh.instance_count > 0:
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)
	multimesh.visible_instance_count = k / stride
	_buffers[type] = buffer
	_draw_armor(type)
	_draw_anatomy(type)

func _sync_anatomy_setting() -> void:
	_anatomy_intensity = clampf(float(Profile.settings.get("hallucination_intensity", 0.65)), 0.0, 1.0)
	for type in _anatomy_renderers.size():
		var renderer := _anatomy_renderers[type]
		if renderer != null:
			renderer.visible = _anatomy_intensity > 0.0
			_draw_anatomy(type)

func _hide_anatomy_slot(slot: int) -> void:
	if slot >= _anatomy_slot_instance.size():
		return
	var instance := _anatomy_slot_instance[slot]
	if instance < 0:
		return
	var renderer := _anatomy_renderers[_type[slot]]
	if renderer != null:
		# Immediate invalidation also works during pause/reward menu callbacks.
		renderer.multimesh.set_instance_transform(instance, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))
	_anatomy_slot_instance[slot] = -1

func _draw_anatomy(type: int) -> void:
	var renderer := _anatomy_renderers[type]
	if renderer == null:
		return
	if _anatomy_intensity <= 0.0:
		renderer.multimesh.visible_instance_count = 0
		return
	var stride := _t_stride[type]
	var buffer := _anatomy_buffers[type]
	_anatomy_buffers[type] = PackedFloat32Array()
	var k := 0
	for a in _active_count:
		var slot := _active[a]
		if _type[slot] != type or not is_alive(slot) or _members[slot] <= 1:
			continue
		if k / stride >= ANATOMY_CAPACITY:
			break
		_anatomy_slot_instance[slot] = k / stride
		var scale := _t_scale[type] * _body[slot]
		k = _write_instance(buffer, k, slot, scale, scale, _flash[slot], stride)
		if stride == 20:
			var clip := _anim_clip[slot] if _anim_clip[slot] >= 0 else _t_clip_move[type]
			var loop := 0.0 if _stunned[slot] > 0.0 or _daze_time[slot] > 0.0 or _mode[slot] == Mode.WINDUP else 1.0
			_write_clip(buffer, k - 8, clip, _anim_frame[slot], loop)
	RenderingServer.multimesh_set_buffer(renderer.multimesh.get_rid(), buffer)
	renderer.multimesh.visible_instance_count = k / stride
	_anatomy_buffers[type] = buffer

func _draw_armor(type: int) -> void:
	var renderer := _armor_renderers[type]
	if renderer == null:
		return
	var buffer := _armor_buffers[type]
	_armor_buffers[type] = PackedFloat32Array()
	var k := 0
	var scale := _t_scale[type]
	for a in _active_count:
		var slot := _active[a]
		if _type[slot] == type and _state[slot] == ALIVE:
			k = _write_instance(buffer, k, slot, scale * _body[slot], scale * _body[slot], 0.0, 16)
	RenderingServer.multimesh_set_buffer(renderer.multimesh.get_rid(), buffer)
	renderer.multimesh.visible_instance_count = k / 16
	_armor_buffers[type] = buffer

# Writes transform and INSTANCE_CUSTOM; for stride 20 the caller fills COLOR at k + 12.
func _write_instance(buffer: PackedFloat32Array, k: int, slot: int, scale_xz: float, scale_y: float, flash: float, stride: int) -> int:
	var yaw := _yaw[slot]
	var c := cos(yaw)
	var s := sin(yaw)
	var p := _pos[slot]
	var telegraph := 0.0
	if _mode[slot] == Mode.WINDUP and _state[slot] == ALIVE:
		var duration := _defs[_type[slot]].telegraph_duration
		telegraph = clampf(1.0 - _timer[slot] / maxf(0.001, duration), 0.01, 1.0)
	elif _mode[slot] == Mode.CHARGE and _state[slot] == ALIVE:
		telegraph = 1.0
	buffer[k] = c * scale_xz
	buffer[k + 1] = 0.0
	buffer[k + 2] = s * scale_xz
	buffer[k + 3] = p.x
	buffer[k + 4] = 0.0
	buffer[k + 5] = scale_y
	buffer[k + 6] = 0.0
	buffer[k + 7] = _y[slot]
	buffer[k + 8] = -s * scale_xz
	buffer[k + 9] = 0.0
	buffer[k + 10] = c * scale_xz
	buffer[k + 11] = p.y
	var custom := k + stride - 4
	# Integer part carries readable statuses (1 burning, 2 charged, 4 hyped,
	# 8 hype source, 16 dazed); the fraction stays the hit flash.
	var status := 0
	if _state[slot] == ALIVE:
		if _burn_time[slot] > 0.0:
			status |= 1
		if _charge_time[slot] > 0.0:
			status |= 2
		if _buff_time[slot] > 0.0:
			status |= 4
		if _t_behavior[_type[slot]] == HordeEnemyDefinition.Behavior.HYPE:
			status |= 8
		if _daze_time[slot] > 0.0:
			status |= 16
	buffer[custom] = float(status) + minf(flash, 0.99)
	buffer[custom + 1] = -1.0 if _stunned[slot] > 0.0 else telegraph
	buffer[custom + 2] = _phase[slot] + TAU * float(_members[slot] - 1)
	buffer[custom + 3] = -1.0 if _exposed[slot] > 0.0 or (_mode[slot] == Mode.RECOVER and _t_armored[_type[slot]] != 0) or (slot == _boss_index and _boss_recovering) else (1.0 - _slow[slot]) if _slow_time[slot] > 0.0 else 0.0
	return k + stride

func _reset_animation(slot: int) -> void:
	_anim_clip[slot] = -1
	_anim_prev[slot] = _pos[slot]
	_anim_speed[slot] = _t_speed[_type[slot]]

# Picks and advances the clip of a living animated enemy and writes its COLOR.
# Gait playback follows the measured ground speed; windups play the attack clip
# timed to the telegraph, charges and melee contact loop it.
func _animate(buffer: PackedFloat32Array, at: int, slot: int, type: int, delta: float, touching: bool) -> void:
	var p := _pos[slot]
	var moved := minf(p.distance_to(_anim_prev[slot]) / maxf(delta, 0.0001), 40.0)
	_anim_prev[slot] = p
	if (_stunned[slot] > 0.0 or _daze_time[slot] > 0.0) and _anim_clip[slot] >= 0:
		_write_clip(buffer, at, _anim_clip[slot], _anim_frame[slot], 0.0)
		return
	var speed := _anim_speed[slot] + (moved - _anim_speed[slot]) * minf(1.0, delta * 6.0)
	_anim_speed[slot] = speed
	var attack := _t_clip_attack[type]
	var mode := _mode[slot]
	if attack >= 0 and mode == Mode.WINDUP:
		var progress := clampf(1.0 - _timer[slot] / maxf(0.001, _defs[type].telegraph_duration), 0.0, 1.0)
		_anim_clip[slot] = attack
		_anim_frame[slot] = progress * (_clip_count[attack] - 1.0)
		_write_clip(buffer, at, attack, _anim_frame[slot], 0.0)
		return
	var clip := _t_clip_move[type]
	var rate := 1.0
	if attack >= 0 and (mode == Mode.CHARGE or touching):
		clip = attack
	else:
		var reference := _t_move_ref[type] * _body[slot]
		rate = clampf(speed / reference, 0.5, 3.0)
		var idle := _t_clip_idle[type]
		if idle >= 0 and speed < reference * 0.15:
			clip = idle
			rate = 1.0
	rate *= _gait[slot] * (0.55 if _members[slot] > 1 else 1.0)
	var count := _clip_count[clip]
	if clip != _anim_clip[slot]:
		_anim_clip[slot] = clip
		# Gait clips start at a per-enemy offset so crowds do not march in step.
		_anim_frame[slot] = 0.0 if clip == attack else _phase[slot] / TAU * count
	_anim_frame[slot] = fmod(_anim_frame[slot] + delta * _clip_fps[clip] * rate, count)
	_write_clip(buffer, at, clip, _anim_frame[slot], 1.0)

func _write_clip(buffer: PackedFloat32Array, at: int, clip: int, frame: float, loop: float) -> void:
	buffer[at] = frame
	buffer[at + 1] = _clip_start[clip]
	buffer[at + 2] = _clip_count[clip]
	buffer[at + 3] = loop

func _draw_projectiles() -> void:
	var buffer := _shot_buffer
	_shot_buffer = PackedFloat32Array()
	# A spit only counts as a hit within a body width of the player's axis, so
	# it would otherwise fill the view for its last frame; it shrinks away instead.
	var eye := target.camera.global_position if is_instance_valid(target) else Vector3.INF
	for s in _shot_count:
		var k := s * 16
		var p := _shot_pos[s]
		var size := clampf((p.distance_to(eye) - PROJECTILE_FADE_NEAR) / (PROJECTILE_FADE_FAR - PROJECTILE_FADE_NEAR), 0.0, 1.0)
		var flags := _shot_flags[s]
		# Spit is a round orange blob, a bottle a tumbling green capsule and a
		# returned shot a long cyan streak along its flight.
		var color := SHOT_SPIT_COLOR
		var stretch := 1.0
		var thin := 1.0
		if flags & SHOT_REFLECTED != 0:
			color = SHOT_REFLECT_COLOR
			stretch = 2.8
			thin = 0.7
		elif flags & SHOT_LOBBED != 0:
			color = SHOT_BOTTLE_COLOR
			stretch = 1.6
			thin = 0.55
		var forward := _shot_vel[s]
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		var side := forward.cross(Vector3.UP)
		side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
		var up := side.cross(forward)
		if flags & (SHOT_LOBBED | SHOT_REFLECTED) == SHOT_LOBBED:
			var spin := _shot_life[s] * 14.0
			var turned := forward * cos(spin) + up * sin(spin)
			up = up * cos(spin) - forward * sin(spin)
			forward = turned
		var x := side * (thin * size)
		var y := up * (thin * size)
		var z := forward * (stretch * size)
		buffer[k] = x.x
		buffer[k + 1] = y.x
		buffer[k + 2] = z.x
		buffer[k + 3] = p.x
		buffer[k + 4] = x.y
		buffer[k + 5] = y.y
		buffer[k + 6] = z.y
		buffer[k + 7] = p.y
		buffer[k + 8] = x.z
		buffer[k + 9] = y.z
		buffer[k + 10] = z.z
		buffer[k + 11] = p.z
		buffer[k + 12] = color.r
		buffer[k + 13] = color.g
		buffer[k + 14] = color.b
		buffer[k + 15] = 1.0
	RenderingServer.multimesh_set_buffer(_shot_renderer.multimesh.get_rid(), buffer)
	_shot_renderer.multimesh.visible_instance_count = _shot_count
	_shot_buffer = buffer
