extends LabScenario

class PlacementHorde extends Horde:
	var block_all := false

	func is_blocked(xz: Vector2, radius: float, feet: float = NAN, headroom: float = 2.2) -> bool:
		return block_all or super.is_blocked(xz, radius, feet, headroom)

func title() -> String:
	return "Final stage bosses"

func summary() -> String:
	return "Every selectable level: actual final crowd, same-venue boss, real rail damage and health phase, survivors and delayed hazards, one shop, blocked safe admission and fixture release"

func run() -> void:
	for stage in 3:
		await _final_fight(stage)
	await _blocked_admission()
	await _fixture_release()
	await _death_priority()

func _fresh(stage: int, procedural: bool = true) -> ArenaGame:
	if is_instance_valid(lab.game):
		lab.game.free()
	var game := await lab.start_game(&"gunner", stage, procedural, 6800 + stage)
	game.horde.clear()
	game.horde.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.set_process(false)
	game.run_state.crit_chance = 0.0
	return game

func _final_crowd(game: ArenaGame) -> StringName:
	var director := game.director
	director.grace = 0.0
	# Earlier sets are covered end-to-end by arena/pressure; retain the actual
	# last set number and its authored allocations for this focused boss case.
	director.encounter_index = director.encounter_count - 1
	director._physics_process(0.1)
	await lab.frames(2)
	if game.round_state == ArenaGame.RoundState.ROUTE:
		game._on_route_chosen(director.route_choices[0].id)
	else:
		director.choose_route(director.route_choices[0].id)
	var venue := director.current_venue_id
	game.player.global_position = (director.current_venue().arrival as Vector3) + Vector3.UP * 0.9
	game.player.velocity = Vector3.ZERO
	director._physics_process(0.1)
	var victims := 0
	for tick in 2500:
		director._physics_process(0.5)
		if director.phase_name == "CLEANUP":
			lab.check(game.horde.population_count > 0 and not director.boss_phase and not game.round_shop.visible, "stage %d final crowd must actually die before boss admission" % game.stage_index)
			_defeat_all(game.horde)
			break
		if director.phase_name != "PEAK" or director._outstanding() > 0:
			victims += _defeat_all(game.horde)
	lab.check(victims > 0 and director.encounter_index == director.encounter_count and director.phase_name == "CLEANUP", "stage %d runs real final BUILD/PEAK allocations before its boss" % game.stage_index)
	return venue

func _final_fight(stage: int) -> void:
	var game := await _fresh(stage)
	var director := game.director
	var horde := game.horde
	var venue := await _final_crowd(game)
	var completions := [0]
	var arrivals := [0]
	director.arena_completed.connect(func() -> void: completions[0] += 1)
	horde.boss_spawned.connect(func(_definition: HordeEnemyDefinition) -> void: arrivals[0] += 1)
	# A real surviving projectile must resolve before the final boss enters.
	horde._add_shot(game.player.global_position + Vector3.UP * 8.0, Vector3.ZERO, 1.0, 0, 0.0, 0.3)
	director._physics_process(600.0)
	lab.check(horde.combat_hazards_pending() and director.phase_name == "CLEANUP" and not director.boss_phase and director.current_venue_id == venue, "stage %d waits for actual delayed projectile cleanup before its boss" % stage)
	horde._physics_process(0.4)
	for tick in 80:
		director._physics_process(0.5)
		if director.phase_name == "BOSS":
			break
	var boss := horde.boss_index
	lab.check(horde.is_alive(boss) and director.phase_name == "BOSS" and arrivals[0] == 1 and director.current_venue_id == venue and not director.completed_venues.has(venue), "stage %d safely admits exactly one boss without closing its final venue" % stage)
	if not horde.is_alive(boss):
		return
	var at := horde.enemy_position(boss)
	var point := Vector2(at.x, at.z)
	lab.check(not horde.is_blocked(point, game.active_stage.schedule.boss.radius) and horde.is_reachable(point) and (director.current_venue().admission_area as Rect2).has_point(point), "stage %d boss admission uses reachable unobstructed local venue lanes" % stage)
	lab.check(is_equal_approx(horde._max_hp[boss], game.active_stage.schedule.boss.max_health * game.active_stage.schedule.boss_health_multiplier), "stage %d boss retains the schedule's tuned health multiplier" % stage)
	if is_instance_valid(game.boss_fight):
		game.boss_fight.set_physics_process(false)
		lab.check(game.boss_fight.state == YardBossFight.State.APPROACH, "generated Yard venue initializes its authored boss controller without fixture coordinates")
	var fight_id := game.boss_fight.get_instance_id() if is_instance_valid(game.boss_fight) else 0
	horde.boss_spawned.emit(game.active_stage.schedule.boss)
	horde.boss_killed.emit()
	director._physics_process(600.0)
	lab.check(not director.boss_defeated and not director.finished and completions[0] == 0 and not game.round_shop.visible and game.hud.boss_panel.visible, "stage %d duplicate/nonlethal boss signals cannot grant a clear or hide the live boss" % stage)
	lab.check(not director.release_boss() and horde.population_count == 1 and (fight_id == 0 or game.boss_fight.get_instance_id() == fight_id), "stage %d repeated boss release/arrival cannot duplicate bodies or controllers" % stage)
	_place_for_shot(game, boss)
	lab.equip_weapon("rail")
	lab.aim_at(horde.enemy_position(boss))
	horde._rebuild_grid()
	var before := horde._hp[boss]
	game.player._shoot(false)
	lab.check(horde.is_alive(boss) and horde._hp[boss] < before, "stage %d final boss takes an actual noncritical primary rail hit" % stage)
	await lab.frames(2)
	lab.check(game.hud.boss_panel.visible and game.hud.boss_percent.text != "100%", "stage %d arrival and health frame follow real boss damage" % stage)
	await lab.capture("stage_%d_arrival" % stage)
	horde.damage(boss, horde._hp[boss] - horde._max_hp[boss] * 0.12)
	await lab.frames(2)
	lab.check(game.hud.boss_phase.visible and not game.round_shop.visible, "stage %d real low-health damage exposes the boss phase while the shop remains locked" % stage)
	await lab.capture("stage_%d_low" % stage)
	var survivor := horde.spawn(game.active_stage.schedule.waves[0].enemy, point)
	horde.damage(boss, horde._max_hp[boss])
	director._physics_process(0.1)
	director._physics_process(600.0)
	lab.check(director.boss_defeated and horde.is_alive(survivor) and not director.finished and director.current_venue_id == venue and not game.round_shop.visible, "stage %d real boss death still waits for an actual surviving enemy in that venue" % stage)
	if survivor >= 0:
		horde.damage(survivor, 1.0e6)
	horde._add_shot(game.player.global_position + Vector3.UP * 8.0, Vector3.ZERO, 1.0, 0, 0.0, 0.3)
	director._physics_process(600.0)
	lab.check(not director.finished and completions[0] == 0 and director.current_venue_id == venue, "stage %d surviving hazards block clear even after every real enemy is dead" % stage)
	horde._physics_process(0.4)
	director._physics_process(0.1)
	await lab.frames(3)
	var cleared := game.stages_cleared
	lab.check(director.finished and completions[0] == 1 and game.round_state == ArenaGame.RoundState.SHOP and game.round_shop.visible and cleared == 1 and director.completed_venues.has(venue), "stage %d boss defeat plus actual cleanup closes the venue and opens exactly one shop" % stage)
	game._on_arena_completed(director.get_instance_id())
	game._finish_stage_clear()
	horde.boss_killed.emit()
	director._physics_process(600.0)
	lab.check(game.stages_cleared == cleared and completions[0] == 1 and not director.release_boss(), "stage %d duplicate completion/death cannot grant another reward, clear or boss" % stage)
	await lab.capture("stage_%d_shop" % stage)
	var old_director := director.get_instance_id()
	var old_horde := horde.get_instance_id()
	game._load_stage((stage + 1) % 3, 6900 + stage)
	game.director.set_physics_process(false)
	game._on_arena_completed(old_director)
	game._on_boss_killed(old_horde)
	game._finish_stage_clear()
	lab.check(game.stages_cleared == cleared and game.round_state == ArenaGame.RoundState.PLAYING and not game.director.finished, "stage %d stale previous-round callbacks cannot clear the new stage" % stage)

func _place_for_shot(game: ArenaGame, boss: int) -> void:
	var at := game.horde.enemy_position(boss)
	for index in 16:
		var offset := Vector2.from_angle(TAU * float(index) / 16.0) * 5.0
		var point := Vector2(at.x, at.z) + offset
		var floor_y := game.horde.ground_height(point)
		var stand := Vector3(point.x, floor_y + 0.9, point.y)
		if game.horde.is_blocked(point, Horde.PLAYER_RADIUS) or not game.horde.is_reachable(point) or absf(floor_y - game.horde.ground_height(Vector2(at.x, at.z))) > 0.5:
			continue
		if game.horde._lane_clear(stand + Vector3.UP * 0.6, at):
			game.player.global_position = stand
			game.player.velocity = Vector3.ZERO
			return
	lab.check(false, "boss venue supplies a reachable clear actual rail-shot position")

func _blocked_admission() -> void:
	var game := await _fresh(0)
	var horde := PlacementHorde.new()
	game._round.add_child(horde)
	var schedule := SpawnSchedule.new()
	schedule.boss = game.active_stage.schedule.boss
	schedule.boss_health_multiplier = game.active_stage.schedule.boss_health_multiplier
	schedule.build_duration = 0.0
	schedule.peak_duration = 0.0
	horde.setup([schedule.boss], game.active_stage.play_area, game.world.get_node("Obstacles"), game.player, game.world.get_node_or_null("Elevation"), game.world.get_node_or_null("Ground"))
	horde.set_layout(game.world as ProceduralWorld)
	horde.set_physics_process(false)
	var director := HordeDirector.new()
	game._round.add_child(director)
	director.setup(horde, schedule, game.player, 9127, 1)
	director.configure_routes(game.world as ProceduralWorld)
	director.set_physics_process(false)
	director._physics_process(0.1)
	director.choose_route(director.route_choices[0].id)
	var venue := director.current_venue_id
	game.player.global_position = (director.current_venue().arrival as Vector3) + Vector3.UP * 0.9
	for tick in 4:
		director._physics_process(0.1)
	horde.block_all = true
	for tick in 40:
		director._physics_process(1000.0)
	lab.check(director.phase_name == "BOSS_PENDING" and horde.population_count == 0 and not director.boss_phase and not director.finished and director.current_venue_id == venue and director.completed_venues.is_empty(), "fully blocked final boss placement retries bounded searches without consuming the boss, closing the venue or clearing")
	var elapsed := director.elapsed
	game.player.active = false
	director._physics_process(1000.0)
	game.player.active = true
	game.get_tree().paused = true
	director._physics_process(1000.0)
	game.get_tree().paused = false
	lab.check(director.elapsed == elapsed and not director.boss_phase, "inactive player and pause freeze pending boss admission")
	horde.block_all = false
	var completions := [0]
	director.arena_completed.connect(func() -> void: completions[0] += 1)
	for tick in 40:
		director._physics_process(0.5)
		if horde.is_alive(horde.boss_index):
			break
	lab.check(horde.is_alive(horde.boss_index) and director.current_venue_id == venue and not director.release_boss(), "reopening actual safe geometry admits the same pending boss exactly once in the retained venue")
	horde.damage(horde.boss_index, 1.0e6)
	for tick in 3:
		director._physics_process(0.1)
	lab.check(director.boss_defeated and director.finished and completions[0] == 1, "reopened blocked final boss requires a real lethal hit before its one completion")

func _fixture_release() -> void:
	var game := await _fresh(0, false)
	var admitted := game.director.release_boss()
	lab.check(admitted and game.horde.is_alive(game.horde.boss_index) and not game.director.release_boss(), "authored fixture release_boss remains usable and admits only one real boss")
	game.horde.damage(game.horde.boss_index, 1.0e6)
	game.director._physics_process(0.1)
	lab.check(game.director.boss_defeated and not game.director.finished and not game.round_shop.visible, "an explicit early fixture boss's actual death does not bypass unfinished crowd encounters")

func _death_priority() -> void:
	var game := await _fresh(2)
	await _final_crowd(game)
	for tick in 80:
		game.director._physics_process(0.5)
		if game.horde.is_alive(game.horde.boss_index):
			break
	lab.check(game.horde.is_alive(game.horde.boss_index), "simultaneous-death case reaches a real final boss")
	game.horde.damage(game.horde.boss_index, 1.0e6)
	game.director._physics_process(0.1)
	game.director._physics_process(0.1)
	game.player._invulnerable = 0.0
	game.player.take_damage(1000000)
	await lab.frames(3)
	lab.check(game.player.health == 0 and game.round_state == ArenaGame.RoundState.LOST and game.stages_cleared == 0 and not game.round_shop.visible, "actual simultaneous player death beats the deferred final boss clear and never opens the shop")

func _defeat_all(horde: Horde) -> int:
	var victims := 0
	for active in horde._active_count:
		var slot := horde._active[active]
		if horde.is_alive(slot):
			horde.damage(slot, 1.0e6)
			victims += 1
	return victims
