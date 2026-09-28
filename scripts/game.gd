class_name ArenaGame
extends Node3D

## Owns a run: stages in `campaign` order, a RunState carried between them,
## level-up pauses, and win/lose flow. Each stage is rebuilt from data under
## a fresh Round node and freed wholesale on transition.

enum RoundState { LOADING, PLAYING, LEVEL_UP, CLEARED, LOST }

@export var campaign: Array[StageDefinition] = []
@export var player_scene: PackedScene
@export var horde_scene: PackedScene
@export var pickup_scene: PackedScene
@export var upgrade_pool: UpgradePool
@export var offers_per_level := 3

@onready var level_mount: Node3D = $Level
@onready var hud: ArenaHUD = $HUD
@onready var level_up: LevelUpScreen = $LevelUp

var run_state: RunState
var stage_index := 0
var round_state := RoundState.LOADING
var kills := 0
var run_time := 0.0
var player: ArenaPlayer
var horde: Horde
var director: HordeDirector
var rack: AutoWeaponRack
var pickups: PickupField
var world: Node3D
var _round: Node3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	level_up.chosen.connect(_on_upgrade_chosen)
	_new_run()

func _new_run() -> void:
	run_state = RunState.new()
	run_state.xp_changed.connect(hud.set_xp)
	run_state.level_up_ready.connect(_on_level_up_ready)
	kills = 0
	run_time = 0.0
	_load_stage(0, 0)

func _process(delta: float) -> void:
	if round_state == RoundState.LOADING:
		return
	hud.set_aiming(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	hud.set_timer(director.remaining(), director.boss_phase)
	hud.set_hostiles(horde.alive_count)
	hud.radar.refresh(horde, player, horde.boss_index)
	if round_state == RoundState.PLAYING:
		run_time += delta

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if round_state == RoundState.LOST and event.is_action_pressed("restart"):
		_request(_new_run)
	elif round_state == RoundState.CLEARED and event.is_action_pressed("advance"):
		if stage_index + 1 < campaign.size():
			_request(_load_stage.bind(stage_index + 1, player.selected_weapon))
		else:
			_request(_new_run)

func _request(action: Callable) -> void:
	round_state = RoundState.LOADING
	player.active = false
	# Rebuild outside input/physics callbacks; the whole old round is freed.
	action.call_deferred()

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
	player.transform = world.get_node("PlayerSpawn").transform
	_round.add_child(player)
	horde.setup(_stage_enemies(stage.schedule), stage.play_area, world.get_node("Obstacles"), player)
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

	hud.show_stage(stage, index, campaign.size())
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	player.shot_fired.connect(hud.show_shot)
	player.hit_confirmed.connect(hud.show_hit)
	player.weapon_changed.connect(hud.set_weapon)
	horde.enemy_killed.connect(_on_enemy_killed)
	horde.boss_spawned.connect(hud.show_boss)
	horde.boss_health_changed.connect(hud.set_boss_health)
	horde.boss_killed.connect(_on_boss_killed)
	player.select_weapon(weapon_slot)
	hud.set_weapon(player.weapons[player.selected_weapon], player.selected_weapon)
	hud.set_health(player.health, player.max_health)
	hud.set_xp(run_state.xp, run_state.xp_required, run_state.level)
	hud.set_kills(kills)
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

func _on_level_up_ready() -> void:
	if round_state == RoundState.PLAYING:
		_present_level_up()

func _present_level_up() -> void:
	if not run_state.consume_level_up():
		return
	round_state = RoundState.LEVEL_UP
	get_tree().paused = true
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
	get_tree().paused = false
	round_state = RoundState.PLAYING
	player.suppress_fire_until_release()

func _on_boss_killed() -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = RoundState.CLEARED
	horde.clear()
	player.active = false
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.sound.play_cue(&"victory")
	hud.finish_stage(true, stage_index == campaign.size() - 1, _summary())

func _on_player_died() -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = RoundState.LOST
	player.sound.play_cue(&"death")
	hud.finish_stage(false, false, _summary())

func _summary() -> String:
	var whole := int(run_time)
	return "LV %d   /   %d KILLS   /   %d:%02d" % [run_state.level, kills, whole / 60, whole % 60]
