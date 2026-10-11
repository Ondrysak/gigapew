extends LabScenario

const BULWARK := preload("res://data/enemies/robot_bulwark.tres")
const SENTRY := preload("res://scenes/weapons/auto/sentry.tscn")
const DRONE := preload("res://scenes/weapons/auto/drone.tscn")
const SAW := preload("res://scenes/weapons/auto/saw.tscn")
const CENTER := Vector2(0, 9)
var _reported_total := 0.0
var _reported_events := 0

func title() -> String:
	return "Bulwark armor"

func summary() -> String:
	return "Real frontal/rear gunfire, visible precision core, independent sentry/drone/blade sources, splash and DOT counters, finite stun and slot reuse"

func run() -> void:
	var game := await lab.start_game()
	var horde := game.horde
	var player := game.player
	# Fixtures hold movement, not damage: every shot uses the real camera rays,
	# gun aggregation, alternate implementation or configured upgrade weapon.
	horde.target = null
	horde.set_physics_process(false)
	player.set_physics_process(false)
	game.run_state.crit_chance = 0.0
	horde.damage_reported.connect(_on_damage)
	_equip(game, "rail")
	var slot := _target(game)
	var base := player.weapon.damage * game.run_state.damage_multiplier
	player.global_position = Vector3(0, 1, 4)
	var removed := _shot(game, Vector3(0, 0.65, 9))
	lab.check(_close(removed, base * 0.25), "actual frontal Rail body shot loses 75% to the visible plate")
	lab.check(_reported_events == 1 and _close(_reported_total, removed), "reported damage equals actual removed HP, not pre-armor damage")
	var core := horde.weak_spot_position(slot)
	removed = _shot(game, core)
	lab.check(_close(removed, base * 0.25), "aiming through the frontal chassis at the rear core cannot earn precision")
	lab.check(not horde.weak_spot_hit(slot, player.camera.global_position, (core - player.camera.global_position).normalized(), 64.0), "front precision gate agrees with the fired shot")
	var front_origin := player.camera.global_position
	var front_direction := (core - front_origin).normalized()
	var face_z := CENTER.y + HordeArmorMesh.FRONT_CENTER.z - HordeArmorMesh.FRONT_SIZE.z * 0.5
	lab.check(_close(player._distances[0], (face_z - front_origin.z) / front_direction.z), "actual front ray impact stops on the batched visible shield face")
	await lab.capture("front_plate")
	player.global_position = Vector3(0, 1, 14)
	# The rear core protrudes: a higher "body" ray would legitimately clip it.
	removed = _shot(game, Vector3(0, 0.35, 9))
	lab.check(_close(removed, base), "actual rear body shot bypasses the front plate")
	removed = _shot(game, core)
	var precision_scale := game.run_state.crit_multiplier + RunState.WEAK_SPOT_CRIT_BONUS
	lab.check(_close(removed, base * precision_scale), "aiming at the visible teal rear core earns the real precision multiplier")
	lab.check(_close(player._distances[0], player.camera.global_position.distance_to(core) - BULWARK.weak_spot_radius), "actual rear ray impact starts on the visible core sphere, ahead of the chassis")
	await lab.capture("rear_core")
	player.global_position = Vector3(5, 1, 9)
	removed = _shot(game, Vector3(0, 0.65, 9))
	lab.check(_close(removed, base), "flank body shots deal full damage")
	# Nearby angles straddle the data-defined front boundary, not a gun ID.
	for degrees in [59.7, 60.3, -59.7, -60.3]:
		var angle := deg_to_rad(degrees)
		player.global_position = Vector3(sin(angle) * 5.0, 1, 9 - cos(angle) * 5.0)
		removed = _shot(game, Vector3(0, 0.65, 9))
		var scale := 0.25 if absf(degrees) < 60.0 else 1.0
		lab.check(_close(removed, base * scale), "fired %.1f-degree shot respects the 60-degree plate boundary" % degrees)
	for degrees in [59.7, 60.3, -59.7, -60.3]:
		var angle := deg_to_rad(degrees)
		player.global_position = Vector3(sin(angle) * 5.0, 1, 9 + cos(angle) * 5.0)
		removed = _shot(game, core)
		var scale := precision_scale if absf(degrees) < 60.0 else 1.0
		lab.check(_close(removed, base * scale), "fired %.1f-degree rear approach respects the visible precision arc" % degrees)
	# Rotation, elevation and render-instance transform all share the core origin.
	horde._yaw[slot] = PI * 0.5
	horde._y[slot] = 2.0
	core = horde.weak_spot_position(slot)
	lab.check(core.is_equal_approx(Vector3(1.35, 3.15, 9)), "rear core follows yaw and feet height")
	player.global_position = Vector3(5, 3, 9)
	removed = _shot(game, core)
	lab.check(_close(removed, base * precision_scale), "rotated elevated visible core still receives actual precision damage")
	horde._process(0.0)
	var type: int = horde._type[slot]
	var overlay := horde._armor_renderers[type].multimesh
	var rendered_core := overlay.get_instance_transform(0) * BULWARK.weak_spot_offset
	lab.check(rendered_core.is_equal_approx(core), "rendered rear marker and damage precision sphere have the same transformed center")
	await lab.capture("rotated_core")
	await _tag_and_area(game)
	await _independent_sources(game)
	await _stun_and_turn(game)
	await _reuse_and_gallery(game)
	horde.damage_reported.disconnect(_on_damage)
	player.set_physics_process(true)
	horde.set_physics_process(true)

func _equip(_game: ArenaGame, id: String) -> void:
	lab.equip_weapon(id)

func _target(game: ArenaGame) -> int:
	game.horde.target = null
	game.horde.clear()
	var slot := game.horde.spawn(BULWARK, CENTER, 100.0)
	game.horde._yaw[slot] = 0.0
	game.horde._rebuild_grid()
	return slot

func _shot(game: ArenaGame, point: Vector3) -> float:
	var slot := game.horde.nearest(Vector3(CENTER.x, 1, CENTER.y), 4.0)
	var before := game.horde._hp[slot]
	game.player._process(1.0)
	game.player._reset_combo()
	game.player._quickdraw_left = 0.0
	_reported_total = 0.0
	_reported_events = 0
	lab.aim_at(point)
	game.player._shoot()
	return before - game.horde._hp[slot]

func _tag_and_area(game: ArenaGame) -> void:
	var horde := game.horde
	var player := game.player
	var slot := _target(game)
	player.global_position = Vector3(0, 1, 4)
	# Exposure is now an ability effect, independent of the gun being carried.
	horde.expose(slot, 4.0)
	_equip(game, "rail")
	var base := player.weapon.damage * game.run_state.damage_multiplier
	lab.check(_close(_shot(game, Vector3(0, 0.65, 9)), base * 0.25 * 1.35), "exposed frontal shot retains the armor-then-exposure order")
	horde._knock[slot] = Vector2.ZERO
	horde._physics_process(4.1)
	lab.check(not horde.is_exposed(slot), "exposure expires independently of permanent front armor")
	var before := horde._hp[slot]
	_equip(game, "autocannon")
	var gun := player.weapon
	before = horde._hp[slot]
	var removed := _shot(game, Vector3(0, 0.65, 9))
	lab.check(_close(removed, gun.damage * game.run_state.damage_multiplier * (0.25 + gun.explosion_damage_fraction)), "actual Autocannon combines plated direct damage with unplated splash in one transaction")
	lab.check(_reported_events == 1 and _close(_reported_total, before - horde._hp[slot]), "mixed direct/splash reports one accurate stored HP delta")
	before = horde._hp[slot]
	horde.damage_radius(Vector3(0, 1, 8), 2.0, 20.0)
	lab.check(_close(before - horde._hp[slot], 20.0), "environmental and explosion radius damage bypass frontal armor")
	# An actual FIRE ray installs a burn with unplated potency. Tick execution
	# goes through the horde's real status updater, not a manually subtracted HP.
	_equip(game, "pulse")
	game.run_state.primary.upgrade(&"fire")
	player.refresh_weapon()
	var fire_amount := player.weapon.damage * game.run_state.damage_multiplier
	before = horde._hp[slot]
	_shot(game, Vector3(0, 0.65, 9))
	lab.check(_close(before - horde._hp[slot], fire_amount * 0.25), "a direct FIRE ray remains blocked by the front plate")
	before = horde._hp[slot]
	horde._update_burns(Horde.BURN_TICK + 0.001)
	lab.check(_close(before - horde._hp[slot], fire_amount * 0.15), "burn DOT bypasses armor with full pre-plate status potency")
	await lab.capture("splash_and_burn")

func _independent_sources(game: ArenaGame) -> void:
	var horde := game.horde
	var player := game.player
	var slot := _target(game)
	var sentry := SENTRY.instantiate() as SentryWeapon
	game.add_child(sentry)
	sentry.configure(player, horde, game.run_state, 1)
	sentry.set_physics_process(false)
	sentry.knockback = 0.0
	sentry._timer = 1.0e6
	player.global_position = Vector3(0, 1, 14)
	sentry._deploy()
	player.global_position = Vector3(0, 1, 4)
	sentry._fire_timers[0] = 0.0
	var before := horde._hp[slot]
	sentry._tick(0.0)
	lab.check(_close(before - horde._hp[slot], sentry.damage_amount()), "rear-positioned sentry deals full damage although its player stands in front")
	sentry._turrets[0].global_position = Vector3(0, 0, 4)
	player.global_position = Vector3(0, 1, 14)
	sentry._fire_timers[0] = 0.0
	before = horde._hp[slot]
	sentry._tick(0.0)
	lab.check(_close(before - horde._hp[slot], sentry.damage_amount() * 0.25), "front-positioned sentry is blocked although its player stands behind")
	await lab.capture("independent_sentry")
	sentry.free()
	var drone := DRONE.instantiate() as DroneWeapon
	game.add_child(drone)
	drone.configure(player, horde, game.run_state, 1)
	drone.set_physics_process(false)
	drone.orbit_speed = 0.0
	drone.orbit_radius = 7.0
	drone.knockback = 0.0
	player.global_position = Vector3(0, 1, 4)
	drone._angle = PI * 0.5
	drone._timers[0] = 0.0
	before = horde._hp[slot]
	drone._tick(0.0)
	lab.check(_close(before - horde._hp[slot], drone.damage_amount()), "orbiting drone uses its actual rear firing position, not the player's front position")
	drone._angle = -PI * 0.5
	drone._timers[0] = 0.0
	before = horde._hp[slot]
	drone._tick(0.0)
	lab.check(_close(before - horde._hp[slot], drone.damage_amount() * 0.25), "orbiting drone's frontal shot is actually plated")
	# Two aligned plated targets face opposite directions. A single piercing
	# drone beam must keep its muzzle origin for both intersections.
	var second := horde.spawn(BULWARK, Vector2(0, 6), 100.0)
	horde._yaw[second] = PI
	horde._rebuild_grid()
	var first_hp := horde._hp[slot]
	var second_hp := horde._hp[second]
	drone._fire_beam(Vector3(0, 1, 14), Vector3.FORWARD)
	lab.check(_close(first_hp - horde._hp[slot], drone.damage_amount()) and _close(second_hp - horde._hp[second], drone.damage_amount() * 0.25), "piercing drone beam resolves each victim from the original beam source")
	await lab.capture("independent_drone")
	drone.free()
	slot = _target(game)
	var saw := SAW.instantiate() as SawWeapon
	game.add_child(saw)
	saw.base_blades = 1
	saw.configure(player, horde, game.run_state, 1)
	saw.set_physics_process(false)
	saw.orbit_speed = 0.0
	saw.orbit_radius = 3.0
	saw.knockback = 0.0
	player.global_position = Vector3(0, 1, 7)
	saw._angle = PI * 0.5
	before = horde._hp[slot]
	saw._tick(0.0)
	lab.check(_close(before - horde._hp[slot], saw.damage_amount()), "rear-contacting orbit blade uses its contact position while player is in front")
	player.global_position = Vector3(0, 1, 11)
	saw._angle = -PI * 0.5
	saw._next_hit[slot] = 0.0
	before = horde._hp[slot]
	saw._tick(0.0)
	lab.check(_close(before - horde._hp[slot], saw.damage_amount() * 0.25), "returning front-contact blade cannot borrow the player's rear position")
	saw.free()

func _stun_and_turn(game: ArenaGame) -> void:
	var horde := game.horde
	var player := game.player
	var slot := _target(game)
	horde.stun(slot, 1.2)
	player.global_position = Vector3(0, 1, 4)
	horde._knock[slot] = Vector2.ZERO
	var feet := horde._pos[slot]
	var yaw := horde._yaw[slot]
	player.global_position = Vector3(0, 1, 14)
	horde.target = player
	horde._physics_process(0.4)
	lab.check(horde._pos[slot].is_equal_approx(feet) and is_equal_approx(horde._yaw[slot], yaw), "stun freezes pursuit and plate rotation while player repositions")
	_equip(game, "rail")
	var base := player.weapon.damage * game.run_state.damage_multiplier
	lab.check(_close(_shot(game, horde.weak_spot_position(slot)), base * (game.run_state.crit_multiplier + RunState.WEAK_SPOT_CRIT_BONUS)), "repositioning during stun earns real rear-core precision")
	player.global_position = Vector3(0, 1, 4)
	lab.check(_close(_shot(game, Vector3(0, 0.65, 9)), base * 0.25), "stun never creates a fake unlocked frontal weakness")
	horde._knock[slot] = Vector2.ZERO
	horde._physics_process(0.9)
	lab.check(not horde.is_stunned(slot), "normal Bulwark stun expires instead of remaining permanently open")
	player.global_position = Vector3(0, 1, 14)
	yaw = horde._yaw[slot]
	horde._physics_process(0.1)
	var turn := absf(angle_difference(yaw, horde._yaw[slot]))
	lab.check(turn > 0.0 and turn <= BULWARK.turn_speed * 0.1 + 0.0001, "post-stun turn is capped at the configured 0.8 radians/sec")
	for tick in 12:
		horde._physics_process(0.1)
	lab.check(absf(angle_difference(0.0, horde._yaw[slot])) <= BULWARK.turn_speed * 1.3 + 0.0001, "a rear flank stays exploitable for more than a second of actual steering")
	horde.target = null
	await lab.capture("stun_reposition")

func _reuse_and_gallery(game: ArenaGame) -> void:
	var horde := game.horde
	var slot := _target(game)
	horde.expose(slot, 4.0)
	horde.stun(slot, 1.2)
	horde.damage(slot, 1.0e6)
	horde._update_dying(1.0)
	horde._rebuild_grid()
	var plain := lab.enemy("robot_grunt")
	var reused := horde.spawn(plain, CENTER, 100.0)
	lab.check(not horde.is_exposed(reused) and not horde.is_stunned(reused), "recycled unarmored enemy does not inherit exposure or stun")
	horde._yaw[reused] = 0.0
	horde._rebuild_grid()
	_equip(game, "rail")
	game.player.global_position = Vector3(0, 1, 4)
	var base := game.player.weapon.damage * game.run_state.damage_multiplier
	lab.check(_close(_shot(game, Vector3(0, 0.4, 9)), base), "actual frontal gun damage on recycled unarmored slot has no armor leak")
	horde.clear()
	horde._update_dying(1.0)
	var front := horde.spawn(BULWARK, Vector2(-1.6, 9), 100.0)
	var rear := horde.spawn(BULWARK, Vector2(1.6, 9), 100.0)
	horde._yaw[front] = 0.0
	horde._yaw[rear] = PI
	horde._rebuild_grid()
	game.player.global_position = Vector3(0, 1, 4)
	lab.aim_at(Vector3(0, 1.15, 9))
	game.damage_numbers.hide()
	game.hud.feedback.reset()
	await lab.wait(0.5)
	await lab.capture("plate_core_gallery")
	# Admission is behavior, not a schedule-text check. No actual bulk cap changes.
	var free_before := horde._free_count
	lab.check(horde.reserve_slots(5) == 5, "bounded encounter obtains a retained five-slot reservation")
	var admitted := 0
	while horde.spawn(plain, Vector2(-12, 12), 100.0) >= 0:
		admitted += 1
	lab.check(admitted == free_before - 5 and horde._free_count == 5, "real ordinary spawns fill capacity only up to the five reserved vacancies")
	lab.check(horde.spawn(plain, Vector2(0, 14)) == -1, "ordinary spawning cannot consume an encounter's last reserved vacancies")
	var reserved := horde.spawn_reserved(plain, Vector2(0, 14))
	lab.check(reserved >= 0 and horde._reserved_slots == 5 and horde._free_count == 4, "reserved spawning retains admission across later response deaths")
	horde.release_reserved(5)
	lab.check(horde._reserved_slots == 0 and horde._free_count == 4, "reservation release leaves live/free slot accounting unchanged")
	lab.check(horde.spawn(plain, Vector2(0, 14)) >= 0, "ordinary spawning resumes when reservation is released")
	horde.clear()
	horde._update_dying(1.0)
	front = horde.spawn(BULWARK, Vector2(-1.6, 9), 100.0)
	rear = horde.spawn(BULWARK, Vector2(1.6, 9), 100.0)
	horde._yaw[front] = 0.0
	horde._yaw[rear] = PI
	horde._rebuild_grid()

func _on_damage(_at: Vector3, amount: float, _kind: int, _critical: bool, _killed: bool) -> void:
	_reported_total += amount
	_reported_events += 1

func _close(actual: float, expected: float) -> bool:
	# Packed float HP at 36k can round by a few millihitpoints.
	return absf(actual - expected) <= 0.02
