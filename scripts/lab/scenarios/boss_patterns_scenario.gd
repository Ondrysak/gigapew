extends LabScenario

var _damage_events: Array[int] = []
var _last_health := 0

func title() -> String:
	return "Yard boss patterns"

func summary() -> String:
	return "Real Yard ram/salvo, locked warnings, movement dodges, recovery body shots, stagger, cover, height, pause and cancellation"

func run() -> void:
	await _patterns()
	await _cover_and_height()
	await _cancellation()

func _fresh() -> ArenaGame:
	if is_instance_valid(lab.game):
		lab.game.free()
	var game := await lab.start_game(&"gunner", 0)
	for hazard in lab.get_tree().get_nodes_in_group(&"hazard"):
		hazard.set_physics_process(false)
	game.run_state.armor = 0.0
	game.run_state.regen_per_second = 0.0
	game.run_state.crit_chance = 0.0
	var player := game.player
	player._invulnerable = 0.0 # Undo only Lab.start_game's sandbox protection.
	player.max_health = 1000
	player.health = 1000
	_last_health = player.health
	_damage_events.clear()
	player.health_changed.connect(_record_damage)
	lab.equip_weapon("rail")
	var patch := _open_patch(game)
	player.global_position = Vector3(patch.x, 1.0, patch.y + 5.0)
	player.velocity = Vector3.ZERO
	game.director.boss_phase = true
	var slot := game.horde.spawn(game.campaign[0].schedule.boss, patch - Vector2(0, 5), 10.0)
	lab.check(slot >= 0 and is_instance_valid(game.boss_fight), "Yard boss spawn initializes the actual game.boss_fight controller")
	if is_instance_valid(game.boss_fight):
		# Shorter idle/recovery intervals; real attack speeds and damage stay intact.
		game.boss_fight.approach_time = 0.55
		game.boss_fight.recovery_time = 0.9
		game.boss_fight.ram_warning_time = 0.8
		game.boss_fight.mortar_warning_time = 0.9
	lab.aim_at(game.horde.enemy_position(slot))
	await lab.frames(3)
	return game

func _open_patch(game: ArenaGame) -> Vector2:
	for z in [-8.0, 0.0, 8.0]:
		for x in [-8.0, 0.0, 8.0]:
			var center := Vector2(x, z)
			var clear := true
			for lateral in [-6.0, 0.0, 6.0]:
				for forward in [-7.0, 0.0, 7.0, 10.0, 14.0]:
					var at := center + Vector2(lateral, forward)
					if game.horde.is_blocked(at, 2.3) or absf(game.horde.ground_height(at)) > 0.01:
						clear = false
			if clear:
				return center
	lab.check(false, "Yard provides a flat unobstructed boss test lane")
	return Vector2.ZERO

func _record_damage(current: int, _maximum: int) -> void:
	if current < _last_health:
		_damage_events.append(_last_health - current)
	_last_health = current

func _until(fight: YardBossFight, wanted: YardBossFight.State, timeout: float = 5.0) -> bool:
	var elapsed := 0.0
	while is_instance_valid(fight) and fight.state != wanted and elapsed < timeout:
		await lab.wait(0.015)
		elapsed += 0.015
	var reached := is_instance_valid(fight) and fight.state == wanted
	lab.check(reached, "natural controller transition reaches %s" % YardBossFight.State.keys()[wanted])
	return reached

func _body_shot(game: ArenaGame) -> float:
	var boss := game.horde.boss_index
	var body := game.horde.enemy_position(boss)
	body.y -= 0.6 # Below the authored 3.4m weak core: a real rail body ray.
	lab.aim_at(body)
	game.player._reset_combo()
	game.player._quickdraw_left = 0.0
	await lab.frames(2)
	var before := game.horde._hp[boss]
	game.player._shoot()
	return before - game.horde._hp[boss]

func _side_step(game: ArenaGame, seconds: float = 0.6) -> void:
	lab.aim_at(game.horde.enemy_position(game.horde.boss_index))
	Input.action_press(&"move_right")
	await lab.wait(seconds)
	Input.action_release(&"move_right")
	await lab.wait(0.08)

func _patterns() -> void:
	var game := await _fresh()
	var fight := game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.RAM_WINDUP):
		return
	var health := game.player.health
	var lock := fight.ram_direction()
	var origin := fight.ram_origin()
	var normal := await _body_shot(game)
	lab.check(normal > 0.0, "ordinary window takes a real noncritical rail body shot")
	await lab.wait(0.18)
	lab.check(game.player.health == health and fight.ram_direction() == lock and fight.ram_origin() == origin, "ram windup is harmless and its lane remains locked")
	await lab.capture("ram_windup")
	if not await _until(fight, YardBossFight.State.RAM):
		return
	await lab.wait(0.08)
	await lab.capture("ram_rush")
	if not await _until(fight, YardBossFight.State.RECOVERY):
		return
	lab.check(_damage_events.count(fight.ram_damage) == 1, "standing in the warned lane takes exactly one real direct ram hit (ordinary contact remains separate)")
	var recovery := await _body_shot(game)
	lab.check(is_equal_approx(recovery, normal * 1.5), "recovery multiplies an actual rail body-shot HP loss by exactly 1.5")
	health = game.player.health
	await lab.capture("ram_recovery")
	await lab.wait(0.2)
	lab.check(game.player.health == health, "recovery creates no encounter attack damage")
	if not await _until(fight, YardBossFight.State.APPROACH):
		return
	var closed := await _body_shot(game)
	lab.check(is_equal_approx(closed, normal), "recovery expiry restores ordinary body-shot damage")
	if not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	var targets := PackedVector3Array([fight.mortar_target(0), fight.mortar_target(1), fight.mortar_target(2)])
	health = game.player.health
	var timer := fight.remaining()
	lab.get_tree().paused = true
	await lab.wait(0.3)
	lab.check(is_equal_approx(fight.remaining(), timer) and game.player.health == health, "pause stops attack timers and damage")
	lab.get_tree().paused = false
	game.player.active = false
	timer = fight.remaining()
	await lab.wait(0.25)
	lab.check(is_equal_approx(fight.remaining(), timer) and game.player.health == health, "inactive/menu player freezes attack clocks without delayed damage")
	game.player.active = true
	await lab.wait(0.15)
	lab.check(game.player.health == health, "mortar warning deals no damage")
	for n in 3:
		lab.check(fight.mortar_target(n) == targets[n], "mortar target %d is stable throughout the warning" % (n + 1))
	await lab.capture("mortar_windup")
	if not await _until(fight, YardBossFight.State.MORTAR):
		return
	lab.check(fight.impacts_completed() == 1, "salvo first impact occurs only after warning finishes")
	await lab.wait(fight.mortar_interval + 0.04)
	lab.check(fight.impacts_completed() == 2 and health - game.player.health == fight.mortar_damage, "second staggered impact hurts the player inside the actual warned centre circle")
	await lab.capture("mortar_impacts")
	if not await _until(fight, YardBossFight.State.RECOVERY):
		return
	lab.check(fight.impacts_completed() == 3, "salvo finishes three actual staggered impacts before recovery")
	await lab.capture("mortar_recovery")
	if not await _until(fight, YardBossFight.State.RAM_WINDUP):
		return
	lock = fight.ram_direction()
	health = game.player.health
	await _side_step(game)
	lab.check(fight.ram_direction() == lock, "movement does not retarget the locked ram")
	if not await _until(fight, YardBossFight.State.RAM):
		return
	var rush_start := game.horde.enemy_position(game.horde.boss_index)
	if not await _until(fight, YardBossFight.State.RECOVERY):
		return
	var rush_end := game.horde.enemy_position(game.horde.boss_index)
	var travel := Vector2(rush_end.x - rush_start.x, rush_end.z - rush_start.z)
	lab.check(game.player.health == health, "normal input movement dodges the ram without invulnerability")
	lab.check(travel.dot(lock) > 1.0 and absf(travel.cross(lock)) < 0.7, "actual rush follows the locked direction, not the dodging player")
	if not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	targets = PackedVector3Array([fight.mortar_target(0), fight.mortar_target(1), fight.mortar_target(2)])
	health = game.player.health
	# All circles lie across the boss's facing. Backward input exits that row.
	lab.aim_at(game.horde.enemy_position(game.horde.boss_index))
	Input.action_press(&"move_back")
	await lab.wait(0.65)
	Input.action_release(&"move_back")
	for n in 3:
		lab.check(fight.mortar_target(n) == targets[n], "dodging keeps mortar circle %d at its original floor target" % (n + 1))
	if not await _until(fight, YardBossFight.State.RECOVERY):
		return
	lab.check(game.player.health == health, "normal input movement dodges all mortar impacts")
	if not await _until(fight, YardBossFight.State.RAM_WINDUP):
		return
	health = game.player.health
	game.horde.stun(game.horde.boss_index, 1.0)
	if not await _until(fight, YardBossFight.State.RECOVERY, 0.4):
		return
	lab.check(game.player.health == health and fight._core.visible and not fight._lane.visible, "real stagger interrupts ram windup, removes its warning and exposes the core")
	await _until(fight, YardBossFight.State.MORTAR_WINDUP)
	game.horde.stun(game.horde.boss_index, 1.0)
	await _until(fight, YardBossFight.State.RECOVERY, 0.4)
	lab.check(fight.impacts_completed() == 0, "stagger interrupts mortar windup before any blast")
	if not await _until(fight, YardBossFight.State.RAM_WINDUP):
		return
	await _side_step(game)
	if not await _until(fight, YardBossFight.State.RAM):
		return
	health = game.player.health
	game.horde.stun(game.horde.boss_index, 1.0)
	await _until(fight, YardBossFight.State.RECOVERY, 0.4)
	await lab.wait(0.15)
	lab.check(game.player.health == health and game.horde._boss_velocity == Vector2.ZERO, "real stagger also interrupts an active rush with no trailing hit or velocity")
	await _until(fight, YardBossFight.State.APPROACH)
	lab.check(not game.horde._boss_recovering and not fight._core.visible, "stagger-opened recovery expires and closes its damage/visual flags")

func _mortar_game() -> ArenaGame:
	var game := await _fresh()
	var fight := game.boss_fight
	if is_instance_valid(fight) and await _until(fight, YardBossFight.State.RAM_WINDUP):
		game.horde.stun(game.horde.boss_index, 1.0)
		await _until(fight, YardBossFight.State.RECOVERY, 0.4)
	return game

func _cover_and_height() -> void:
	var game := await _mortar_game()
	var fight := game.boss_fight
	if not is_instance_valid(fight):
		return
	# A real solid wall is present before target lock, so both the footprint
	# mesh and the impact ray see it. Only fixture positioning teleports.
	var stand := game.player.global_position
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12.0, 3.0, 0.25)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	wall.add_child(collision)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	visual.mesh = box
	wall.add_child(visual)
	game.world.add_child(wall)
	wall.global_position = Vector3(stand.x, 1.5, stand.z + 1.0)
	if not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	var center := fight.mortar_target(1)
	game.player.global_position = center + Vector3(0, 0.9, 1.8)
	game.player.velocity = Vector3.ZERO
	var health := game.player.health
	lab.check(not fight._inside_footprint(1, Vector2(game.player.global_position.x, game.player.global_position.z)), "solid cover clips the warned blast footprint, not just its damage")
	await lab.capture("mortar_cover")
	await _until(fight, YardBossFight.State.RECOVERY)
	lab.check(game.player.health == health, "a real solid wall blocks all nearby mortar explosions")
	game = await _mortar_game()
	fight = game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	health = game.player.health
	# Actual player dash movement rises out of the marked floor's height band.
	game.player.dash(Vector3.UP * 6.0, 1.6)
	await _until(fight, YardBossFight.State.RECOVERY)
	lab.check(game.player.health == health, "real vertical movement above the marked floor's height band avoids mortar damage")
	game = await _mortar_game()
	fight = game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	center = fight.mortar_target(1)
	game.player.global_position = center + Vector3(0, 0.9, fight.mortar_radius + 0.08)
	game.player.velocity = Vector3.ZERO
	health = game.player.health
	await _until(fight, YardBossFight.State.RECOVERY)
	lab.check(game.player.health == health, "just outside the marked radius is safe: no oversized invisible explosion")

func _cancellation() -> void:
	var game := await _fresh()
	var fight := game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.RAM_WINDUP):
		return
	var health := game.player.health
	fight.cancel()
	game.player.active = false # The real menu/inactive boundary after cancel.
	await lab.wait(fight.ram_warning_time + fight.ram_time + 0.15)
	lab.check(game.player.health == health and fight.state == YardBossFight.State.CANCELLED and not fight._lane.visible and not game.horde._boss_recovering and game.horde._boss_velocity == Vector2.ZERO, "explicit cancellation removes warning, scripted velocity and exposure with no queued ram hit")
	game = await _fresh()
	fight = game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.RAM_WINDUP):
		return
	health = game.player.health
	fight.queue_free()
	await lab.wait(1.2)
	lab.check(not is_instance_valid(fight) and game.player.health == health and not game.horde._boss_controlled and not game.horde._boss_recovering, "freeing the controller cancels its pool and releases scripted control without delayed damage")
	lab.check(game.boss_fight == null and not game.hud.boss_cue.visible, "removed controller clears its owner reference and encounter HUD")
	game = await _mortar_game()
	fight = game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	game.horde.damage(game.horde.boss_index, 1.0e9)
	health = game.player.health
	await lab.wait(1.8)
	lab.check(game.player.health == health and (not is_instance_valid(fight) or fight.state == YardBossFight.State.CANCELLED), "actual boss death cancels pending mortar impacts without late damage")
	game = await _mortar_game()
	fight = game.boss_fight
	if not is_instance_valid(fight) or not await _until(fight, YardBossFight.State.MORTAR_WINDUP):
		return
	game.player.take_damage(game.player.health + 100)
	await lab.wait(1.8)
	lab.check(game.player.health == 0 and (not is_instance_valid(fight) or (fight.state == YardBossFight.State.CANCELLED and fight.impacts_completed() == 0)), "actual player death cancels the entire salvo with no late explosion")
