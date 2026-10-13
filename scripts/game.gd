class_name ArenaGame
extends Node3D

## A run plays one chosen Prague level with its RunConfig tuning. Finite
## encounters end only after their real survivors are cleared; optional cabinets
## and caches never gate progression. Clearing opens the shop: purchases are
## permanent, and the shop starts another round on any level, optionally one
## difficulty tier harder, or returns home.

enum RoundState { LOADING, PLAYING, LEVEL_UP, PAUSED, SHOP, LOST, ENCOUNTER_REWARD, GEAR, DRAFT, ROUTE }

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SHOP_SCENE := preload("res://scenes/ui/round_shop_screen.tscn")

## Selectable levels. RunConfig.build_stage tunes a copy; these stay authored.
var campaign: Array[StageDefinition] = RunConfig.levels()
@export var player_scene: PackedScene
@export var horde_scene: PackedScene
@export var pickup_scene: PackedScene
@export var mining_tool_scene: PackedScene
@export var deposit_field_scene: PackedScene
@export var upgrade_pool: UpgradePool
## Every collectible resource; banked ones become Profile currency.
@export var resources: Array[ResourceDefinition] = []
@export var stage_reward: ResourceDefinition
@export var stage_reward_amount := 1
## Share of unbanked currency kept when the run ends without clearing a level.
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
var run_config: RunConfig
## The tuned copy of campaign[stage_index] the current round plays.
var active_stage: StageDefinition
var round_state := RoundState.LOADING
var kills := 0
var arena_score := 0
var stage_score := 0
var run_time := 0.0
var stages_cleared := 0
var level_seed := 0
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
var round_shop: RoundShopScreen
var damage_numbers: DamageNumbers
var mining_encounter: MiningDefense
var boss_fight: YardBossFight
var _pending_encounter_rewards := 0
var _stage_clear_pending := false
var _presented_boss := Vector2i(-1, -1)
var _rng := RandomNumberGenerator.new()
var _banked_ids: Array[StringName] = []
var _nearby := PackedInt32Array()
var _music_timer := 0.0
var _music_kill_heat := 0.0
var _music_damage_heat := 0.0
var _run_recorded := false
## Luďas reacts with his own recorded voice; survives stage loads.
var voice: LudasVoice
var kara: KaraCallouts
var _arena_phase_for_voice := "ARRIVAL"
## Kills in the current short burst, for the multikill reaction.
var _burst_kills := 0
var _burst_left := 0.0
const BURST_WINDOW := 1.5
const BURST_KILLS := 12
var _last_health := 0
var gear_screen: GearScreen
var gear_loot: GearLootDirector
var _pending_gear_rewards: Array[Dictionary] = []
var _gear_offers: Array[GearDefinition] = []
var _gear_inspection := false
var weapon_draft: WeaponDraftScreen
var route_screen: RouteChoiceScreen
var _initial_draft := false

func _ready() -> void:
	_rng.randomize()
	for definition in resources:
		if definition.banked:
			_banked_ids.append(definition.id)
	level_up.chosen.connect(_on_upgrade_chosen)
	voice = LudasVoice.new()
	voice.name = "LudasVoice"
	add_child(voice)
	Music.follow_voice(voice)
	pause_menu.resume_requested.connect(_on_resume)
	pause_menu.abandon_requested.connect(_on_abandon)
	hud.setup_resources(resources)
	var shop_layer := CanvasLayer.new()
	shop_layer.name = "RoundShopLayer"
	shop_layer.layer = 20
	shop_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(shop_layer)
	round_shop = SHOP_SCENE.instantiate() as RoundShopScreen
	shop_layer.add_child(round_shop)
	round_shop.hide()
	round_shop.next_round_requested.connect(_on_shop_next_round)
	round_shop.home_requested.connect(_on_shop_home)
	gear_screen = GearScreen.new()
	add_child(gear_screen)
	gear_screen.chosen.connect(_on_gear_chosen)
	gear_screen.declined.connect(_on_gear_declined)
	hud.gear_hud.inspect_requested.connect(_inspect_gear)
	weapon_draft = WeaponDraftScreen.new()
	add_child(weapon_draft)
	weapon_draft.confirmed.connect(_on_weapon_draft_confirmed)
	weapon_draft.cancelled.connect(_on_weapon_draft_cancelled)
	route_screen = RouteChoiceScreen.new()
	add_child(route_screen)
	route_screen.chosen.connect(_on_route_chosen)
	route_screen.weapons_requested.connect(_open_weapon_draft.bind(true))
	_new_run()

func _new_run() -> void:
	get_tree().paused = false
	weapon_draft.close()
	route_screen.close()
	_initial_draft = true
	Music.new_run()
	_cancel_gear()
	class_definition = Profile.roster.find(Profile.selected_class_id)
	run_config = Profile.load_run_config()
	run_state = RunState.new()
	var permanent := Profile.meta_levels()
	permanent.merge(Profile.crafting_modifiers())
	run_state.set_permanent_modifiers(class_definition, permanent)
	run_state.initialize_primary(Profile.primary_loadout(class_definition))
	run_state.available_weapons = Profile.available_primary_weapons(class_definition)
	run_state.ability_scenes = class_definition.ability_scenes
	run_state.start_guided(bool(Profile.settings.get("guided_start", true)))
	run_state.ability_unlocked.connect(_on_ability_unlocked)
	Profile.apply_primary_gadget(run_state.primary)
	for upgrade in class_definition.starting_upgrades:
		run_state.apply_upgrade(upgrade)
	for upgrade in Profile.starting_craft_upgrades():
		run_state.apply_upgrade(upgrade)
	Profile.apply_shop_build(run_state, class_definition.id)
	run_state.xp_changed.connect(hud.set_xp)
	run_state.level_up_ready.connect(_on_level_up_ready)
	run_state.resources_changed.connect(hud.set_resource)
	run_state.supply_changed.connect(hud.set_supply)
	kills = 0
	arena_score = 0
	stage_score = 0
	hud.gear_hud.setup(run_state)
	run_time = 0.0
	RenderingServer.global_shader_parameter_set("hallucination_time", run_time)
	stages_cleared = 0
	run_banked = {}
	_run_recorded = false
	hud.show_class(class_definition)
	for definition in resources:
		hud.set_resource(definition.id, 0)
	hud.set_supply(run_state.supply, run_state.supply_required)
	_load_stage(run_config.level_index(campaign))

func _process(delta: float) -> void:
	if round_state == RoundState.LOADING:
		return
	# Optional encounter nodes can be removed independently of the round.
	if not is_instance_valid(mining_encounter):
		mining_encounter = null
	if not is_instance_valid(boss_fight):
		boss_fight = null
	hud.set_aiming(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	hud.set_hostiles(horde.alive_count)
	hud.radar.refresh(horde, player, horde.boss_index, pickups, mining_encounter)
	hud.set_abilities(player.abilities)
	hud.set_gunplay(player)
	hud.set_objectives(mining_encounter, player)
	hud.set_arena_progress(director, player)
	hud.set_boss_fight(boss_fight)
	hud.set_gear_loot(gear_loot, round_state == RoundState.PLAYING)
	if round_state == RoundState.PLAYING:
		if player.mining_ready():
			hud.tutor.offer(&"mining")
		run_time += delta
		RenderingServer.global_shader_parameter_set("hallucination_time", run_time)
		_burst_left -= delta
		if _burst_left <= 0.0:
			_burst_kills = 0
		_music_kill_heat = move_toward(_music_kill_heat, 0.0, delta * 0.28)
		_music_damage_heat = move_toward(_music_damage_heat, 0.0, delta * 0.5)
		var tool := player.mining_tool
		Music.set_mining(1.0 if tool != null and tool.is_smashing() else 0.0)
		_music_timer -= delta
		if _music_timer <= 0.0:
			_music_timer = 0.25
			Music.set_intensity(_crowd_intensity())

## Hit-chain drive or crowd/danger pressure, whichever is stronger.
func _crowd_intensity() -> float:
	var near := horde.query_radius(player.global_position, music_radius, _nearby)
	var represented := 0
	for n in near:
		represented += horde.fusion_members(_nearby[n])
	var local := clampf(float(represented) / music_crowd_reference, 0.0, 1.0)
	var global := clampf(float(horde.population_count) / maxf(1.0, active_stage.schedule.max_alive), 0.0, 1.0)
	var health_ratio := float(player.health) / maxi(player.max_health, 1)
	var danger := 1.0 - smoothstep(0.15, 0.5, health_ratio)
	var pressure := clampf(0.12 + local * 0.6 + global * 0.3 + danger * 0.18 + _music_kill_heat * 0.2 + _music_damage_heat * 0.15, 0.0, 1.0)
	return maxf(pressure, lerpf(0.12, 1.0, player.combo_intensity))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	match round_state:
		RoundState.PLAYING:
			if event.is_action_pressed("pause"):
				_open_pause()
			elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
				if director.phase_name in ["RECOVERY", "ROUTE"]:
					get_viewport().set_input_as_handled()
					_open_weapon_draft(true)
			elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_G:
				get_viewport().set_input_as_handled()
				_inspect_gear()
		RoundState.LOST:
			if event.is_action_pressed("restart"):
				_request(_new_run)
			elif event.is_action_pressed("advance"):
				_request(_to_menu)
		RoundState.SHOP:
			# Shop input belongs to its focused controls; Enter cannot skip stock.
			return

func _request(action: Callable) -> void:
	round_state = RoundState.LOADING
	weapon_draft.close()
	route_screen.close()
	_cancel_encounters()
	_cancel_gear()
	player.active = false
	player.cancel_actions()
	# Rebuild outside input/physics callbacks; the whole old round is freed.
	action.call_deferred()

func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _to_base() -> void:
	get_tree().set_meta(&"open_base", true)
	_to_menu()

func _on_shop_next_round(level: int, harder: bool) -> void:
	if round_state != RoundState.SHOP or level < 0 or level >= campaign.size():
		return
	round_shop.hide()
	get_tree().paused = false
	if harder:
		run_config.set_value("difficulty", run_config.difficulty + 1)
	_request(_load_stage.bind(level))

func _on_shop_home() -> void:
	if round_state != RoundState.SHOP:
		return
	round_shop.hide()
	get_tree().paused = false
	_record_run(true)
	_request(_to_base)

func _load_stage(index: int, seed_value: int = -1) -> void:
	get_tree().paused = false
	round_shop.hide()
	_cancel_encounters()
	_cancel_gear()
	mining_encounter = null
	boss_fight = null
	gear_loot = null
	_pending_encounter_rewards = 0
	_stage_clear_pending = false
	_presented_boss = Vector2i(-1, -1)
	if is_instance_valid(_round):
		_round.free()
	stage_index = index
	stage_score = 0
	run_config.select_level(campaign[index])
	active_stage = run_config.build_stage(campaign[index])
	var stage := active_stage
	level_seed = _rng.randi() if seed_value < 0 else seed_value
	_round = Node3D.new()
	_round.name = "Round"
	level_mount.add_child(_round)
	world = stage.world_scene.instantiate() as Node3D
	world.name = "World"
	if world is ProceduralWorld:
		(world as ProceduralWorld).configure(stage, level_seed)
	_round.add_child(world)
	horde = horde_scene.instantiate() as Horde
	_round.add_child(horde)
	player = player_scene.instantiate() as ArenaPlayer
	player.name = "Player"
	player.run_state = run_state
	player.horde = horde
	player.weapon = run_state.primary.definition
	player.ability_scenes = run_state.ability_scenes
	player.transform = world.get_node("PlayerSpawn").transform
	_round.add_child(player)
	player.incoming_damage_scale = run_config.damage_scale()
	horde.setup(_stage_enemies(stage.schedule), stage.play_area, world.get_node("Obstacles"), player, world.get_node_or_null("Elevation"), world.get_node_or_null("Ground"))
	horde.set_layout(world as ProceduralWorld)
	kara = KaraCallouts.new()
	kara.name = "KaraCallouts"
	_round.add_child(kara)
	kara.setup(horde, player, hud)
	_arena_phase_for_voice = "ARRIVAL"
	hud.radar.set_layout(world as ProceduralWorld)
	damage_numbers = DamageNumbers.new()
	_round.add_child(damage_numbers)
	damage_numbers.setup(player.camera, horde)
	var tool := mining_tool_scene.instantiate() as MiningTool
	player.camera.add_child(tool)
	tool.setup(player, run_state)
	deposits = deposit_field_scene.instantiate() as DepositField
	deposits.configure_level(level_seed)
	_round.add_child(deposits)
	deposits.setup(world, stage.play_area, player, run_state)
	deposits.compartment_opened.connect(player.gear_effects.grant_salvage_shield)
	deposits.compartment_opened.connect(_on_salvage_music)
	pickups = pickup_scene.instantiate() as PickupField
	_round.add_child(pickups)
	pickups.setup(horde, player, run_state)
	pickups.collected.connect(hud.show_pickup)
	rack = AutoWeaponRack.new()
	rack.name = "AutoWeapons"
	_round.add_child(rack)
	rack.setup(player, horde, run_state)
	rack.sync()
	director = HordeDirector.new()
	director.name = "Director"
	_round.add_child(director)
	director.setup(horde, stage.schedule, player, level_seed, stage.arena_encounters)
	director.arena_completed.connect(_on_arena_completed.bind(director.get_instance_id()), CONNECT_DEFERRED)
	director.phase_changed.connect(_on_arena_phase_changed.bind(director.get_instance_id()))
	director.grace = stage.spawn_grace
	director.route_choices_changed.connect(_on_route_choices_changed.bind(director.get_instance_id()), CONNECT_DEFERRED)
	if world is ProceduralWorld:
		director.configure_routes(world as ProceduralWorld)
	var props := world.get_node_or_null("PinballProps")
	if props != null:
		for prop in props.get_children():
			prop.setup(horde, player)
	# Level hazards (barrels, consoles, vents...) stay inert until given the round.
	for hazard in get_tree().get_nodes_in_group(&"hazard"):
		if world.is_ancestor_of(hazard):
			hazard.setup(horde, player, run_state)

	hud.show_stage(stage, stages_cleared + 1, run_config.label())
	hud.setup_arena(level_seed)
	hud.set_arena_score(arena_score, int(Profile.records.get("best_score", 0)))
	player.health_changed.connect(hud.set_health)
	player.health_changed.connect(_on_health_for_tips)
	player.died.connect(_on_player_died)
	player.shot_fired.connect(hud.show_shot)
	player.hit_confirmed.connect(hud.show_hit)
	player.combo_changed.connect(hud.show_combo)
	player.arena_scored.connect(_on_arena_scored.bind(player.get_instance_id()))
	player.drop_fired.connect(_on_drop_fired)
	player.ability_combo.connect(hud.show_ability_combo)
	player.action_feedback.connect(hud.show_action)
	player.ability_combo.connect(func(_id: StringName): voice.say(&"combo"))
	player.ability_combo.connect(func(_id: StringName): Music.accent(&"combo"))
	horde.enemy_killed.connect(_on_enemy_killed)
	horde.boss_spawned.connect(_on_boss_spawned.bind(horde.get_instance_id()))
	horde.boss_health_changed.connect(hud.set_boss_health)
	horde.boss_killed.connect(_on_boss_killed.bind(horde.get_instance_id()))
	if stage.mining_encounter_scene != null:
		mining_encounter = stage.mining_encounter_scene.instantiate() as MiningDefense
		_round.add_child(mining_encounter)
		mining_encounter.reward_ready.connect(_on_encounter_reward_ready)
		mining_encounter.setup(horde, player, run_state, deposits, pickups)
	hud.set_primary(run_state)
	hud.set_weapon_mods(run_state)
	hud.gear_hud.bind_player(player)
	if world is ProceduralWorld:
		gear_loot = GearLootDirector.new()
		gear_loot.name = "GearLoot"
		_round.add_child(gear_loot)
		gear_loot.setup(world as ProceduralWorld, horde, player, run_state, level_seed, stage_index)
		gear_loot.reward_ready.connect(_on_gear_reward_ready.bind(gear_loot.get_instance_id()), CONNECT_DEFERRED)
	player.weapon_changed.connect(func(_definition: WeaponDefinition): hud.set_primary(run_state))
	hud.set_health(player.health, player.max_health)
	hud.set_xp(run_state.xp, run_state.xp_required, run_state.level)
	hud.set_kills(kills)
	Music.play(&"stage")
	Music.set_boss(false)
	Music.set_intensity(0.12)
	Music.set_mining(0.0)
	_music_kill_heat = 0.0
	_music_damage_heat = 0.0
	round_state = RoundState.PLAYING
	# Level-ups banked while a stage was ending are offered on arrival.
	if run_state.pending_level_ups > 0:
		_present_level_up()
	hud.tutor.clear()
	voice.stop()
	_last_health = player.health
	_burst_kills = 0
	voice.say(&"arrive")
	if index == 0:
		hud.tutor.offer(&"basics")
		hud.tutor.offer(&"arena")
		hud.tutor.offer(&"drop")
		hud.tutor.offer(&"pinball")
		if run_state.guided and not player.abilities.is_empty():
			_offer_skill_tip(player.abilities[0])

	if _initial_draft:
		_open_weapon_draft(false)
## Guided start: a level reveals a new skill slot.
func _on_ability_unlocked(slot: int) -> void:
	if not is_instance_valid(player) or slot >= player.abilities.size():
		return
	hud.show_skill_unlocked(player.abilities[slot])
	voice.say(&"skill")
	_offer_skill_tip(player.abilities[slot])
	if run_state.is_ability_unlocked(3) and run_state.is_ability_unlocked(4):
		hud.tutor.offer(&"combos")

func _offer_skill_tip(skill: ActiveAbility) -> void:
	hud.tutor.offer(StringName("skill_" + skill.display_name.to_snake_case()), "NOVÝ TRIK · KLÁVESA %d · %s" % [skill.slot + 1, skill.display_name.to_upper()], skill.description)

## Low health prompts the repair tip and Luďas's growl; healing gets a gulp.
func _on_health_for_tips(current: int, maximum: int) -> void:
	if current < _last_health and current > 0:
		_music_damage_heat = 1.0
		if current < maximum * 0.4:
			Music.accent(&"danger")
	if current > 0 and current < maximum * 0.4:
		hud.tutor.offer(&"repair")
		if current < _last_health:
			voice.say(&"hurt")
	if current > _last_health and _last_health > 0:
		voice.say(&"heal")
	_last_health = current

func _stage_enemies(schedule: SpawnSchedule) -> Array[HordeEnemyDefinition]:
	var definitions: Array[HordeEnemyDefinition] = []
	for wave in schedule.waves:
		if not definitions.has(wave.enemy):
			definitions.append(wave.enemy)
	if schedule.boss != null and not definitions.has(schedule.boss):
		definitions.append(schedule.boss)
	return definitions

func _on_enemy_killed(_definition: HordeEnemyDefinition, _position: Vector3) -> void:
	if round_state in [RoundState.LOADING, RoundState.SHOP, RoundState.LOST]:
		return
	kills += 1
	_music_kill_heat = minf(1.0, _music_kill_heat + 0.16)
	hud.set_kills(kills)
	_burst_kills += 1
	_burst_left = BURST_WINDOW
	if _burst_kills >= BURST_KILLS:
		_burst_kills = 0
		voice.say(&"multikill")
		Music.accent(&"combo")

func _on_arena_phase_changed(source_id: int) -> void:
	if is_instance_valid(director) and director.get_instance_id() == source_id and is_instance_valid(player):
		player.set_arena_recovery(director.recovering)
		var previous := _arena_phase_for_voice
		_arena_phase_for_voice = director.phase_name
		if previous == "CLEANUP" and director.phase_name in ["RECOVERY", "CLEAR"] and is_instance_valid(kara):
			kara.encounter_cleared()

func _on_route_choices_changed(source_id: int) -> void:
	if not is_instance_valid(director) or director.get_instance_id() != source_id \
			or director.phase_name != "ROUTE" or round_state != RoundState.PLAYING:
		return
	_present_routes()

func _present_routes() -> void:
	if director.route_choices.is_empty() or horde.alive_count > 0 or horde.population_count > 0:
		return
	round_state = RoundState.ROUTE
	player.cancel_actions()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	route_screen.present(director.route_choices, player.global_position, director.encounter_index + 1, director.encounter_count)

func _on_route_chosen(id: StringName) -> void:
	if round_state != RoundState.ROUTE or not director.choose_route(id):
		return
	route_screen.close()
	_resume_play()

func _open_weapon_draft(allow_cancel: bool = false) -> void:
	if not is_instance_valid(player) or round_state not in [RoundState.PLAYING, RoundState.ROUTE]:
		return
	if allow_cancel and (director.phase_name not in ["RECOVERY", "ROUTE"] \
			or horde.alive_count > 0 or horde.population_count > 0):
		return
	route_screen.close()
	player.cancel_actions()
	round_state = RoundState.DRAFT
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon_draft.open(run_state, allow_cancel)

func _on_weapon_draft_confirmed(first: WeaponDefinition, second: WeaponDefinition) -> void:
	if round_state != RoundState.DRAFT or not run_state.equip_pair(first, second):
		return
	_initial_draft = false
	weapon_draft.close()
	player.refresh_weapon()
	hud.set_primary(run_state)
	_resume_play()

func _on_weapon_draft_cancelled() -> void:
	if round_state != RoundState.DRAFT or _initial_draft:
		return
	weapon_draft.close()
	_resume_play()

func _on_arena_scored(points: int, _label: String, source_id: int) -> void:
	if not is_instance_valid(player) or player.get_instance_id() != source_id or points <= 0 \
			or round_state in [RoundState.LOADING, RoundState.SHOP, RoundState.LOST]:
		return
	arena_score += points
	stage_score += points
	hud.set_arena_score(arena_score, int(Profile.records.get("best_score", 0)))

func _on_drop_fired(_weapon_id: StringName) -> void:
	if round_state in [RoundState.LOADING, RoundState.SHOP, RoundState.LOST]:
		return
	_music_kill_heat = 1.0
	Music.accent(&"drop")
	voice.say(&"drop")

func _on_salvage_music() -> void:
	if round_state == RoundState.PLAYING:
		Music.accent(&"salvage")

func _on_boss_spawned(definition: HordeEnemyDefinition, source_id: int) -> void:
	if not is_instance_valid(horde) or horde.get_instance_id() != source_id \
			or not horde.is_alive(horde.boss_index) or round_state in [RoundState.SHOP, RoundState.LOST]:
		return
	var identity := Vector2i(horde.boss_index, horde.enemy_generation(horde.boss_index))
	if identity == _presented_boss:
		return
	_presented_boss = identity
	hud.show_boss(definition)
	Music.set_boss(true)
	var scene := active_stage.boss_fight_scene
	if scene != null:
		if is_instance_valid(boss_fight):
			boss_fight.cancel()
			boss_fight.queue_free()
		boss_fight = scene.instantiate() as YardBossFight
		_round.add_child(boss_fight)
		boss_fight.setup(horde, player)

func _cancel_encounters() -> void:
	if is_instance_valid(mining_encounter):
		mining_encounter.cancel()
	if is_instance_valid(boss_fight):
		boss_fight.cancel()

func _on_encounter_reward_ready() -> void:
	_pending_encounter_rewards += 1
	if round_state == RoundState.PLAYING:
		_present_encounter_reward()

func _present_encounter_reward() -> void:
	_pending_encounter_rewards -= 1
	round_state = RoundState.ENCOUNTER_REWARD
	get_tree().paused = true
	player.cancel_actions()
	Music.stinger(&"level_up")
	level_up.present(run_state.roll_offers(upgrade_pool, offers_per_level, _rng), run_state, "AUTOMAT VYBRÁN", "ODMĚNA ZA OBRANU  ·  VYBER JEDNO VYLEPŠENÍ")

# ---------------------------------------------------------------- passive gear

func _cancel_gear() -> void:
	if is_instance_valid(gear_loot):
		gear_loot.cancel()
	if is_instance_valid(gear_screen):
		gear_screen.close()
	_pending_gear_rewards.clear()
	_gear_offers.clear()
	_gear_inspection = false

func _on_gear_reward_ready(offers: Array[GearDefinition], title: String, source_id: int) -> void:
	if not is_instance_valid(gear_loot) or gear_loot.get_instance_id() != source_id \
			or round_state in [RoundState.LOADING, RoundState.SHOP, RoundState.LOST]:
		return
	if offers.is_empty():
		return
	_pending_gear_rewards.append({"offers": offers, "title": title})
	if round_state == RoundState.PLAYING:
		_present_gear_reward()

func _present_gear_reward() -> void:
	var reward: Dictionary = _pending_gear_rewards.pop_front()
	_gear_offers.assign(reward.offers)
	for item in _gear_offers:
		item.set_meta(&"newly_discovered", Profile.discover_gear(item.id))
	_gear_inspection = false
	round_state = RoundState.GEAR
	player.cancel_actions()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	gear_screen.present(_gear_offers, run_state, reward.title)
	Music.stinger(&"level_up")

func _inspect_gear() -> void:
	if round_state != RoundState.PLAYING:
		return
	_gear_inspection = true
	_gear_offers.clear()
	round_state = RoundState.GEAR
	player.cancel_actions()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	gear_screen.present_inventory(run_state)

func _on_gear_chosen(item: GearDefinition, replace_slot: int) -> void:
	if round_state != RoundState.GEAR or _gear_inspection or not _gear_offers.has(item):
		return
	if not run_state.equip_gear(item, replace_slot):
		return
	gear_screen.close()
	_gear_offers.clear()
	_resume_play()

func _on_gear_declined() -> void:
	if round_state != RoundState.GEAR:
		return
	gear_screen.close()
	_gear_offers.clear()
	_gear_inspection = false
	_resume_play()

# ---------------------------------------------------------------- level-ups

func _on_level_up_ready() -> void:
	if round_state == RoundState.PLAYING:
		_present_level_up()

func _present_level_up() -> void:
	if not run_state.consume_level_up():
		return
	round_state = RoundState.LEVEL_UP
	get_tree().paused = true
	player.cancel_actions()
	Music.stinger(&"level_up")
	level_up.present(run_state.roll_offers(upgrade_pool, offers_per_level, _rng), run_state)

## Applies an upgrade to the run and refreshes everything that derives from it.
func grant_upgrade(upgrade: UpgradeDefinition) -> void:
	run_state.apply_upgrade(upgrade)
	player.refresh_stats()
	player.refresh_weapon()
	hud.set_primary(run_state)
	if upgrade.instant_heal > 0:
		player.heal(upgrade.instant_heal)
	rack.sync()
	hud.set_weapon_mods(run_state)

func _on_upgrade_chosen(upgrade: UpgradeDefinition) -> void:
	if round_state != RoundState.LEVEL_UP and round_state != RoundState.ENCOUNTER_REWARD:
		return
	grant_upgrade(upgrade)
	_resume_play()

# ---------------------------------------------------------------- pause

func _open_pause() -> void:
	round_state = RoundState.PAUSED
	get_tree().paused = true
	player.cancel_actions()
	pause_menu.open()

func _on_resume() -> void:
	if round_state != RoundState.PAUSED:
		return
	pause_menu.close()
	_resume_play()

func _resume_play() -> void:
	if not _pending_gear_rewards.is_empty():
		_present_gear_reward()
		return
	# Preserve earned choices when the final arena kill happens during a picker.
	if _pending_encounter_rewards > 0:
		_present_encounter_reward()
		return
	if _stage_clear_pending:
		_finish_stage_clear()
		return
	if run_state.pending_level_ups > 0:
		_present_level_up()
		return
	if director.phase_name == "ROUTE" and not director.route_choices.is_empty():
		_present_routes()
		return
	get_tree().paused = false
	round_state = RoundState.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.suppress_fire_until_release()

func _on_abandon() -> void:
	if round_state != RoundState.PAUSED:
		return
	pause_menu.close()
	_bank(death_bank_fraction)
	_record_run(stages_cleared > 0)
	_request(_to_base)

# ---------------------------------------------------------------- run end

func _on_boss_killed(source_id: int) -> void:
	if not is_instance_valid(horde) or horde.get_instance_id() != source_id \
			or horde.is_alive(horde.boss_index):
		return
	Music.set_boss(false)
	hud.boss_panel.hide()
	hud.arena_round_box.visible = hud.arena_panel.visible and not hud.death.visible

## Deferred until the final damage transaction finishes. Stale arena signals
## cannot clear a new round, and simultaneous player death takes precedence.
func _on_arena_completed(source_id: int) -> void:
	if not is_instance_valid(director) or source_id != director.get_instance_id() \
			or not director.finished or _stage_clear_pending or player.health <= 0 \
			or not director._combat_empty(true) \
			or (active_stage.schedule.boss != null and not director.boss_defeated):
		return
	if round_state in [RoundState.SHOP, RoundState.LOST, RoundState.LOADING]:
		return
	_stage_clear_pending = true
	player.active = false
	player.cancel_actions()
	if round_state == RoundState.PLAYING:
		_resume_play()

func _finish_stage_clear() -> void:
	if not _stage_clear_pending or not is_instance_valid(director) or not director.finished \
			or player.health <= 0 or round_state in [RoundState.SHOP, RoundState.LOST, RoundState.LOADING]:
		return
	_stage_clear_pending = false
	round_state = RoundState.SHOP
	_cancel_gear()
	stages_cleared += 1
	if stage_reward != null:
		run_state.add_resource(stage_reward, stage_reward_amount)
	var bonus := run_config.reward_scale()
	for definition in resources:
		var reward := 0
		match definition.id:
			&"gold": reward = 10 + stage_index * 6 + mini(30, floori(float(stage_score) / 300.0))
			&"crystal": reward = 3 + stage_index * 2
		if reward > 0:
			run_state.add_resource(definition, roundi(reward * bonus))
	# Loot still on the floor is swept up with the clear.
	deposits.collect_all()
	var banked := _bank(1.0)
	horde.clear()
	player.active = false
	player.cancel_actions()
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.sound.play_cue(&"victory")
	voice.say(&"clear")
	Music.set_boss(false)
	Music.set_intensity(0.0)
	Music.stinger(&"stage_clear")
	hud.feedback.reset()
	damage_numbers.hide()
	get_tree().paused = true
	round_shop.open(run_state, stages_cleared - 1, class_definition.id, _summary() + "\n" + _banked_text(banked), \
			ShopVenueCatalog.shared().shop_venue(active_stage.layout_theme, level_seed), campaign, stage_index, run_config)

func _on_player_died() -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = RoundState.LOST
	hud.tutor.clear()
	_cancel_encounters()
	weapon_draft.close()
	route_screen.close()
	_cancel_gear()
	var banked := _bank(death_bank_fraction)
	_record_run(false)
	player.sound.play_cue(&"death")
	voice.say(&"death")
	Music.set_boss(false)
	Music.set_intensity(0.0)
	Music.set_mining(0.0)
	Music.stinger(&"death")
	hud.finish_run(run_state.level, kills, arena_score, run_time, stages_cleared, banked)

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
		"score": arena_score,
		"time": run_time,
		"level": run_state.level,
		"stages_cleared": stages_cleared,
		"victory": victory,
		"level_id": String(campaign[stage_index].id),
		"difficulty": run_config.difficulty,
		"banked": run_banked.duplicate(),
	})

func _summary() -> String:
	var whole := int(run_time)
	return "%d BODŮ   /   ÚR %d   /   %d ROZPRÁŠENO   /   %d:%02d" % [arena_score, run_state.level, kills, whole / 60, whole % 60]

func _banked_text(banked: Dictionary) -> String:
	var parts: PackedStringArray = []
	for definition in resources:
		if definition.banked and int(banked.get(definition.id, 0)) > 0:
			parts.append("+%d %s" % [banked[definition.id], definition.display_name.to_upper()])
	return "SCHOVÁNO   " + "   ".join(parts) if not parts.is_empty() else "DO KAPSY NEZŮSTALO NIC"
