extends LabScenario

## Every gun family's draw, idle inspect, DROP showpiece and airborne float on
## the real player view. Presentation only: aim and firing must stay untouched.
const GUNS := ["pulse", "scatter", "rail", "minigun", "flamethrower", "autocannon", "maschine", "cihlomet", "tvarohomet"]
## The muzzle may never sweep closer than this to the lens during a flourish.
const LENS_CLEARANCE := 0.2

func title() -> String:
	return "Gun flourishes"

func summary() -> String:
	return "Per-gun draw, idle inspect, DROP showpiece and airborne float; aim, firing and pause stay untouched"

func run() -> void:
	var game := await lab.start_game(&"scout")
	game.director.set_physics_process(false)
	var player := game.player
	var pitch := player.head.rotation.x
	var yaw := player.rotation.y
	var first := true
	for id: String in GUNS:
		lab.equip_weapon(id)
		# process_frame fires before Node._process; wait for the view's first update.
		await lab.frames(2)
		var view := player._view
		lab.check(view._draw < 1.0, "%s plays a draw when it appears" % id)
		var near := await _strip(view, player, id + "_draw", view.draw_duration)
		await lab.wait(0.15)
		lab.check(_settled(view), "%s draw settles exactly at its rest pose" % id)
		if first:
			# The real idle path, once; later guns start their inspect directly.
			await lab.wait(view.inspect_delay + 0.1)
			lab.check(view._inspecting, "standing still for %.0f s starts an automatic inspect" % view.inspect_delay)
		else:
			view._idle = view.inspect_delay
			await lab.frames(2)
		near = minf(near, await _strip(view, player, id + "_inspect", view.inspect_duration * 0.95, 9))
		# Capture stalls stretch real frames; wait on the inspect itself.
		for frame in 240:
			if not view._inspecting and view._inspect_weight <= 0.0:
				break
			await lab.get_tree().process_frame
		await lab.wait(0.3)
		lab.check(not view._inspecting and _settled(view), "%s inspect finishes back at rest (%s)" % [id, _state(view)])
		var tossed := view._hand != null and view.flourish in [WeaponView.Flourish.TWIRL, WeaponView.Flourish.RACK, WeaponView.Flourish.SNAP]
		var hand_rest := _in_camera(player, view._hand) if tossed else Vector3.ZERO
		# The muzzle sits near the roll axis, so measure how far the gun's own up
		# axis turns in camera space while the hand holds still.
		var up_rest := _up_in_camera(player, view)
		var travel := [0.0, 0.0]
		var follow := func() -> void:
			travel[0] = maxf(travel[0], _up_in_camera(player, view).angle_to(up_rest))
			if tossed:
				travel[1] = maxf(travel[1], _in_camera(player, view._hand).distance_to(hand_rest))
		lab.get_tree().process_frame.connect(follow)
		view.drop_flourish()
		near = minf(near, await _strip(view, player, id + "_drop", view.drop_flourish_duration))
		lab.get_tree().process_frame.disconnect(follow)
		if tossed:
			lab.check(travel[0] > 2.5 and travel[1] < 0.05, "%s DROP tosses the gun through %.1f rad while the hand stays to catch it (%.3f m)" % [id, travel[0], travel[1]])
		await lab.wait(0.2)
		lab.check(_settled(view), "%s DROP showpiece returns to rest" % id)
		lab.check(near >= LENS_CLEARANCE, "%s muzzle stays %.2f m from the lens through every flourish" % [id, near])
		lab.check(is_equal_approx(player.head.rotation.x, pitch) and is_equal_approx(player.rotation.y, yaw), "%s flourishes never move the player's aim" % id)
		if first:
			first = false
			await _interrupts(game, view)
	await _airborne(player)

## Strip of `count` frames across `seconds`; returns the closest muzzle-to-lens distance.
func _strip(view: WeaponView, player: ArenaPlayer, label: String, seconds: float, count := 6) -> float:
	var near := [INF]
	var sample := func() -> void:
		near[0] = minf(near[0], view.muzzle.global_position.distance_to(player.camera.global_position))
	lab.get_tree().process_frame.connect(sample)
	await lab.capture_strip(label, count, seconds / float(count))
	lab.get_tree().process_frame.disconnect(sample)
	return near[0]

func _in_camera(player: ArenaPlayer, node: Node3D) -> Vector3:
	return player.camera.global_transform.affine_inverse() * node.global_position

func _up_in_camera(player: ArenaPlayer, view: WeaponView) -> Vector3:
	return player.camera.global_basis.inverse() * view.global_basis.y

func _settled(view: WeaponView) -> bool:
	return view._flourish_angle.length() < 0.01 and view._flourish_offset.length() < 0.003 \
			and view._toss_angle == Vector3.ZERO and view._toss_lift == 0.0 \
			and (view._hand == null or view._hand.transform.is_equal_approx(view._hand_rest)) \
			and view.rotation.distance_to(view._rest_rotation) < 0.03

func _state(view: WeaponView) -> String:
	return "inspecting=%s t=%.2f weight=%.2f draw=%.2f drop=%.2f angle=%s offset=%s rot=%.3f" % [view._inspecting, view._inspect, view._inspect_weight, view._draw, view._drop, view._flourish_angle, view._flourish_offset, view.rotation.distance_to(view._rest_rotation)]

func _interrupts(game: ArenaGame, view: WeaponView) -> void:
	view._idle = view.inspect_delay
	await lab.frames(3)
	var inspecting := view._inspecting
	var shots := [0]
	var count := func() -> void: shots[0] += 1
	game.player.shot_fired.connect(count)
	lab.fire(true)
	await lab.frames(2)
	lab.fire(false)
	game.player.shot_fired.disconnect(count)
	lab.check(inspecting and not view._inspecting, "a real shot interrupts the inspect immediately (shots=%d)" % shots[0])
	await lab.wait(0.6)
	view._idle = view.inspect_delay
	await lab.frames(4)
	game.get_tree().paused = true
	var frozen := view.transform
	await lab.wait(0.25)
	lab.check(view.transform.is_equal_approx(frozen), "pause freezes the inspect mid-pose")
	game.get_tree().paused = false
	view.brace(1.0)
	await lab.frames(2)
	lab.check(not view._inspecting, "a kick brace cancels the inspect")
	await lab.wait(0.8)

func _airborne(player: ArenaPlayer) -> void:
	var view := player._view
	# Sample the whole jump: deepest rising dip and highest falling float.
	var extremes := [0.0, 0.0]
	var sample := func() -> void:
		extremes[0] = minf(extremes[0], view._air_pitch)
		extremes[1] = maxf(extremes[1], view._air_lift)
	lab.get_tree().process_frame.connect(sample)
	Input.action_press(&"jump")
	await lab.wait(0.12)
	Input.action_release(&"jump")
	await lab.capture("air_rising")
	await lab.wait(0.4)
	await lab.capture("air_falling")
	await lab.wait(0.4)
	lab.get_tree().process_frame.disconnect(sample)
	lab.check(extremes[0] < -0.02 and extremes[1] > 0.004, "the gun dips on the way up (%.3f rad) and floats while falling (%.3f m)" % [extremes[0], extremes[1]])
	await lab.wait(0.8)
	lab.check(absf(view._air_lift) < 0.004 and absf(view._air_pitch) < 0.01, "landing settles the airborne float")
