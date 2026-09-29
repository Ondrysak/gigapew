class_name ArenaGame
extends Node3D

## Owns a run for the class chosen in the menu: stages in `campaign` order, a
## RunState carried between them (class + meta upgrades + level-ups), mining,
## pause and level-up flow, banking of mined currency into the Profile, and
## music intensity. Each stage is rebuilt from data under a fresh Round node.

enum RoundState { LOADING, PLAYING, LEVEL_UP, PAUSED, CLEARED, LOST }

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@export var campaign: Array[StageDefinition] = []
@export var player_scene: PackedScene
@export var horde_scene: PackedScene
@export var pickup_scene: PackedScene
@export var mining_tool_scene: PackedScene
@export var deposit_field_scene: PackedScene
@export var upgrade_pool: UpgradePool
## Every collectible resource; banked ones become Profile currency.
@export var resources: Array[ResourceDefinition] = []
@export var boss_reward: ResourceDefinition
@export var boss_reward_amount := 3
## Share of unbanked currency kept when the run ends without clearing a stage.
@export_range(0.0, 1.0) var death_bank_fraction := 0.5
@export var offers_per_level := 3
## Enemies within this radius drive the music's local intensity.
@export var music_radius := 16.0
@export var music_crowd_reference := 60

@onready var level_mount: Node3D = $Level
@onready var hud: ArenaHUD = $HUD
@onready var level_up: LevelUpScreen = $LevelUp
@onready var pause_menu: PauseMenu = $PauseMenu

var run_state: RunState
var class_definition: ClassDefinition
var stage_index := 0
var round_state := RoundState.LOADING
var kills := 0
var run_time := 0.0
var stages_cleared := 0
## Currency banked into the Profile during this run, id -> amount.
var run_banked: Dictionary = {}
var player: ArenaPlayer
var horde: Horde
var director: HordeDirector
var rack: AutoWeaponRack
var pickups: PickupField
var deposits: DepositField
var world: Node3D
var _round: Node3D
var _rng := RandomNumberGenerator.new()
var _banked_ids: Array[StringName] = []
var _nearby := PackedInt32Array()
var _music_timer := 0.0
var _run_recorded := false

func _ready() -> void:
	_rng.randomize()
	for definition in resources:
		if definition.banked:
			_banked_ids.append(definition.id)
	level_up.chosen.connect(_on_upgrade_chosen)
	pause_menu.resume_requested.connect(_on_resume)
	pause_menu.abandon_requested.connect(_on_abandon)
	hud.setup_resources(resources)
	_new_run()

func _new_run() -> void:
	get_tree().paused = false
	class_definition = Profile.roster.find(Profile.selected_class_id)
	run_state = RunState.new()
	run_state.set_permanent_modifiers(class_definition, Profile.meta_levels())
	for upgrade in class_definition.starting_upgrades:
		run_state.apply_upgrade(upgrade)
	run_state.xp_changed.connect(hud.set_xp)
	run_state.level_up_ready.connect(_on_level_up_ready)
	run_state.resources_changed.connect(hud.set_resource)
	run_state.supply_changed.connect(hud.set_supply)
	kills = 0
	run_time = 0.0
	stages_cleared = 0
	run_banked = {}
	_run_recorded = false
	hud.show_class(class_definition)
	for definition in resources:
		hud.set_resource(definition.id, 0)
	hud.set_supply(run_state.supply, run_state.supply_required)
	_load_stage(0, 0)

func _process(delta: float) -> void:
	if round_state == RoundState.LOADING:
		return
	hud.set_aiming(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	hud.set_timer(director.remaining(), director.boss_phase)
	hud.set_hostiles(horde.alive_count)
	hud.radar.refresh(horde, player, horde.boss_index)
	hud.set_ability(player.ability)
	if round_state == RoundState.PLAYING:
		run_time += delta
		_music_timer -= delta
		if _music_timer <= 0.0:
			_music_timer = 0.25
			Music.set_intensity(_crowd_intensity())

## Blend of the crowd pressing on the player and the stage-wide crowd size.
func _crowd_intensity() -> float:
	var near := horde.query_radius(player.global_position, music_radius, _nearby)
	var local := clampf(float(near) / music_crowd_reference, 0.0, 1.0)
	var global := clampf(float(horde.alive_count) / maxf(1.0, campaign[stage_index].schedule.max_alive), 0.0, 1.0)
	return clampf(0.12 + local * 0.6 + global * 0.3, 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	match round_state:
		RoundState.PLAYING:
			if event.is_action_pressed("pause"):
				_open_pause()
		RoundState.LOST:
			if event.is_action_pressed("restart"):
				_request(_new_run)
			elif event.is_action_pressed("advance"):
				_request(_to_menu)
		RoundState.CLEARED:
			var final_stage := stage_index + 1 >= campaign.size()
			if event.is_action_pressed("advance"):
				_request(_to_menu if final_stage else _load_stage.bind(stage_index + 1, player.selected_weapon))
			elif final_stage and event.is_action_pressed("restart"):
				_request(_new_run)

func _request(action: Callable) -> void:
	round_state = RoundState.LOADING
	player.active = false
	# Rebuild outside input/physics callbacks; the whole old round is freed.
	action.call_deferred()

func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _load_stage(index: int, weapon_slot: int) -> void:
	if is_instance_valid(_round):
		_round.free()
	stage_index = index
	var stage := campaign[index]
	_round = Node3D.new()
	_round.name = "Round"
	level_mount.add_child(_round)
	world = stage.world_scene.instantiate() as Node3D
	world.name = "World"
	_round.add_child(world)
	horde = horde_scene.instantiate() as Horde
	_round.add_child(horde)
	player = player_scene.instantiate() as ArenaPlayer
	player.name = "Player"
	player.run_state = run_state
	player.horde = horde
	player.weapons = class_definition.starting_weapons
	player.ability_scene = Profile.equipped_ability_scene(class_definition)
	player.transform = world.get_node("PlayerSpawn").transform
	_round.add_child(player)
	horde.setup(_stage_enemies(stage.schedule), stage.play_area, world.get_node("Obstacles"), player)
	var tool := mining_tool_scene.instantiate() as MiningTool
	player.camera.add_child(tool)
	tool.setup(player, run_state)
	deposits = deposit_field_scene.instantiate() as DepositField
	_round.add_child(deposits)
	deposits.setup(world, stage.play_area, player, run_state)
	pickups = pickup_scene.instantiate() as PickupField
	_round.add_child(pickups)
	pickups.setup(horde, player, run_state)
	rack = AutoWeaponRack.new()
	rack.name = "AutoWeapons"
	_round.add_child(rack)
	rack.setup(player, horde, run_state)
	rack.sync()
	director = HordeDirector.new()
	director.name = "Director"
	_round.add_child(director)
	director.setup(horde, stage.schedule, player)
	# Level hazards (barrels, consoles, vents...) stay inert until given the round.
	for hazard in get_tree().get_nodes_in_group(&"hazard"):
		if world.is_ancestor_of(hazard):
			hazard.setup(horde, player, run_state)

	hud.show_stage(stage, index, campaign.size())
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	player.shot_fired.connect(hud.show_shot)
	player.hit_confirmed.connect(hud.show_hit)
	player.weapon_changed.connect(hud.set_weapon)
	horde.enemy_killed.connect(_on_enemy_killed)
	horde.boss_spawned.connect(_on_boss_spawned)
	horde.boss_health_changed.connect(hud.set_boss_health)
	horde.boss_killed.connect(_on_boss_killed)
	player.select_weapon(mini(weapon_slot, player.weapons.size() - 1))
	hud.set_weapon(player.weapons[player.selected_weapon], player.selected_weapon)
	hud.set_health(player.health, player.max_health)
	hud.set_xp(run_state.xp, run_state.xp_required, run_state.level)
	hud.set_kills(kills)
	Music.play(&"stage")
	Music.set_boss(false)
	Music.set_intensity(0.12)
	round_state = RoundState.PLAYING
	# Level-ups banked while a stage was ending are offered on arrival.
	if run_state.pending_level_ups > 0:
		_present_level_up()

func _stage_enemies(schedule: SpawnSchedule) -> Array[HordeEnemyDefinition]:
	var definitions: Array[HordeEnemyDefinition] = []
	for wave in schedule.waves:
		if not definitions.has(wave.enemy):
			definitions.append(wave.enemy)
	if schedule.boss != null and not definitions.has(schedule.boss):
		definitions.append(schedule.boss)
	return definitions

func _on_enemy_killed(_definition: HordeEnemyDefinition, _position: Vector3) -> void:
	kills += 1
	hud.set_kills(kills)

func _on_boss_spawned(definition: HordeEnemyDefinition) -> void:
	hud.show_boss(definition)
	Music.set_boss(true)

# ---------------------------------------------------------------- level-ups

func _on_level_up_ready() -> void:
	if round_state == RoundState.PLAYING:
		_present_level_up()

func _present_level_up() -> void:
	if not run_state.consume_level_up():
		return
	round_state = RoundState.LEVEL_UP
	get_tree().paused = true
	Music.stinger(&"level_up")
	level_up.present(run_state.roll_offers(upgrade_pool, offers_per_level, _rng), run_state)

## Applies an upgrade to the run and refreshes everything that derives from it.
func grant_upgrade(upgrade: UpgradeDefinition) -> void:
	run_state.apply_upgrade(upgrade)
	player.refresh_stats()
	if upgrade.instant_heal > 0:
		player.heal(upgrade.instant_heal)
	rack.sync()

func _on_upgrade_chosen(upgrade: UpgradeDefinition) -> void:
	if round_state != RoundState.LEVEL_UP:
		return
	grant_upgrade(upgrade)
	if run_state.pending_level_ups > 0:
		_present_level_up()
		return
	_resume_play()

# ---------------------------------------------------------------- pause

func _open_pause() -> void:
	round_state = RoundState.PAUSED
	get_tree().paused = true
	pause_menu.open()

func _on_resume() -> void:
	if round_state != RoundState.PAUSED:
		return
	pause_menu.close()
	_resume_play()

func _resume_play() -> void:
	get_tree().paused = false
	round_state = RoundState.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.suppress_fire_until_release()

func _on_abandon() -> void:
	if round_state != RoundState.PAUSED:
		return
	pause_menu.close()
	_bank(death_bank_fraction)
	_record_run(false)
	_request(_to_menu)

# ---------------------------------------------------------------- run end

func _on_boss_killed() -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = RoundState.CLEARED
	stages_cleared += 1
	if boss_reward != null:
		run_state.add_resource(boss_reward, boss_reward_amount)
	# Loot still on the floor is swept up with the clear.
	deposits.collect_all()
	var banked := _bank(1.0)
	horde.clear()
	player.active = false
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.sound.play_cue(&"victory")
	var final_stage := stage_index == campaign.size() - 1
	Music.set_boss(false)
	Music.stinger(&"run_complete" if final_stage else &"stage_clear")
	if final_stage:
		_record_run(true)
	hud.finish_stage(true, final_stage, _summary(), _banked_text(banked))

func _on_player_died() -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = RoundState.LOST
	var banked := _bank(death_bank_fraction)
	_record_run(false)
	player.sound.play_cue(&"death")
	Music.set_boss(false)
	Music.stinger(&"death")
	hud.finish_stage(false, false, _summary(), _banked_text(banked))

## Moves collected currency into the Profile; returns what was banked now.
func _bank(fraction: float) -> Dictionary:
	var taken := run_state.take_bankable(_banked_ids, fraction)
	for id: StringName in taken:
		if int(taken[id]) > 0:
			Profile.add_currency(id, taken[id])
			run_banked[id] = int(run_banked.get(id, 0)) + int(taken[id])
	return taken

func _record_run(victory: bool) -> void:
	if _run_recorded:
		return
	_run_recorded = true
	Profile.record_run({
		"class_id": class_definition.id,
		"kills": kills,
		"time": run_time,
		"level": run_state.level,
		"stages_cleared": stages_cleared,
		"victory": victory,
		"banked": run_banked.duplicate(),
	})

func _summary() -> String:
	var whole := int(run_time)
	return "LV %d   /   %d KILLS   /   %d:%02d" % [run_state.level, kills, whole / 60, whole % 60]

func _banked_text(banked: Dictionary) -> String:
	var parts: PackedStringArray = []
	for definition in resources:
		if definition.banked and int(banked.get(definition.id, 0)) > 0:
			parts.append("+%d %s" % [banked[definition.id], definition.display_name.to_upper()])
	return "BANKED   " + "   ".join(parts) if not parts.is_empty() else "NOTHING BANKED"
