extends LabScenario

# Mirror of shaders/slot_machine.gdshaderinc (hash, cycle and stop timing) so the
# review can scrub the gameplay clock to exact reel stops and wins.
const SLOT_SALT_CABINET := 2654435769
const SLOT_SALT_CYCLE := 2246822507
const SLOT_SALT_SALT := 3266489909

func title() -> String:
	return "Close-range machine salvage"

func summary() -> String:
	return "Fruit-machine bank reels, wins, LEDs and lamps, automatic crowbar, held F prying, gun/reach rejection, wall occlusion, pause and out of order"

func run() -> void:
	var game := await lab.start_game(&"driller")
	game.horde.target = null
	await lab.wait(0.5)
	var deposit: MineralDeposit
	for node in game.deposits.get_children():
		if node is MineralDeposit and node.global_position.y < 2.4 and (deposit == null or deposit.definition.resource.id == &"crystal"):
			deposit = node
	lab.check(deposit != null, "stage supplies an accessible wall-mounted machine")
	if deposit == null:
		return
	var slot := deposit.definition.resource.id != &"crystal"
	lab.check(slot, "the accessible machine is a bank of three fruit machines")
	var player := game.player
	lab.check(await lab.aim_deposit(deposit, 5.0), "distant camera ray hits a real machine compartment")
	# Compare lamps alone; the peripheral hallucination pass also moves over time.
	Profile.set_setting("hallucination_intensity", 0.0)
	var front_luma := 0.0
	if slot:
		await _front_view(game, deposit, "slot_bank_front")
		front_luma = await _close_view(game, deposit, "slot_cabinet_close")
		lab.check(await lab.aim_deposit(deposit, 5.0), "the bank front view leaves a real compartment in reach of the distant ray")
	await lab.capture_strip("blinking_lamps", 6, 0.3)
	var lamps := _region(player.camera, deposit.global_position + deposit.global_basis.y * deposit.formation_size.y * 0.39)
	var first: Image
	if slot:
		# Scrub into a spin of the middle cabinet: its Turbo ladder and hold lamps step.
		lab.aim_at(deposit.to_global(_glass_point(deposit, 1, 0.5, 0.5)))
		await lab.frames(2)
		lamps = _glass_rect(player.camera, deposit, 1, Vector4(0.0, 0.0, 1.0, 1.0))
		var spin := _next_spin(deposit, 1, game.run_time + 1.0)
		first = await _image_at(game, spin + 0.35)
		lab.check(_difference(first, await _image_at(game, spin + 0.8), lamps) > 0.002, "marquee lamps visibly chase and blink during play")
		game.set_process(true)
	else:
		first = await _image()
		await lab.wait(0.45)
		lab.check(_difference(first, await _image(), lamps) > 0.002, "marquee lamps visibly chase and blink during play")
	game.get_tree().paused = true
	first = await _image()
	await lab.wait(0.45)
	lab.check(_difference(first, await _image(), lamps) < 0.0005, "cabinet lamps freeze with the paused gameplay clock")
	game.get_tree().paused = false
	if slot:
		await _reel_review(game, deposit)
		lab.check(await lab.aim_deposit(deposit, 5.0), "the reel review leaves a real compartment in reach of the distant ray")
	Profile.set_setting("hallucination_intensity", 0.65)
	var before := deposit.health
	for id in ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]:
		lab.equip_weapon(id)
		lab.fire(true)
		await lab.wait(0.25)
		lab.fire(false)
	lab.check(is_equal_approx(deposit.health, before) and deposit.yield_emitted == 0, "no primary firearm or explosion can break machine compartments at range")
	Input.action_press(&"mine")
	await lab.wait(0.35)
	Input.action_release(&"mine")
	lab.check(not player.mining_ready() and is_equal_approx(deposit.health, before), "F cannot pry beyond melee reach")
	await lab.capture("out_of_reach")

	lab.check(await lab.aim_deposit(deposit, 2.2), "close camera ray hits a real machine compartment")
	await lab.wait(0.15)
	lab.check(player.mining_ready() and not player.drilling(), "visible close compartment raises the idle crowbar before F is held")
	await lab.capture("automatic_crowbar")
	lab.fire(true)
	await lab.wait(0.2)
	lab.fire(false)
	lab.check(is_equal_approx(deposit.health, before), "left click cannot pry or damage a compartment while the crowbar is raised")
	Input.action_press(&"mine")
	await lab.capture_strip("crowbar_leverage", 6, 0.03)
	await lab.wait(0.2)
	Input.action_release(&"mine")
	lab.check(deposit.health < before and deposit.yield_emitted > 0, "held F breaks a real close compartment and releases its conserved currency")
	lab.check(deposit._dark_doors != 0, "the pried door's lamps go dark and the service candle starts calling")
	await lab.capture("f_prying")
	if slot:
		await _tamper_review(game, deposit)

	lab.check(await lab.aim_deposit(deposit, 2.2), "a remaining physical compartment can be aimed at after one door breaks")
	before = deposit.health
	game.get_tree().paused = true
	Input.action_press(&"mine")
	await lab.wait(0.3)
	Input.action_release(&"mine")
	lab.check(is_equal_approx(deposit.health, before), "paused F input cannot damage a machine")
	game.get_tree().paused = false
	player.suppress_fire_until_release()

	var blocker := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 0.2)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	blocker.add_child(collider)
	game._round.add_child(blocker)
	blocker.global_position = player.camera.global_position - player.head.global_basis.z * 0.5
	blocker.global_basis = player.head.global_basis
	await lab.wait(0.1)
	Input.action_press(&"mine")
	await lab.wait(0.3)
	Input.action_release(&"mine")
	lab.check(not player.mining_ready() and is_equal_approx(deposit.health, before), "a machine behind real solid geometry never raises the crowbar or permits prying through a wall")
	blocker.free()
	player.rotation.y += PI
	await lab.wait(0.15)
	lab.check(not player.mining_ready(), "looking away from a machine returns to the primary firearm")
	await lab.capture("return_to_gun")

	for attempt in 30:
		if deposit.health <= 0.0:
			break
		if not await lab.aim_deposit(deposit, 2.2):
			lab.check(false, "every unopened compartment remains reachable by the real crowbar ray")
			return
		Input.action_press(&"mine")
		await lab.wait(0.85)
		Input.action_release(&"mine")
	await lab.frames(2)
	lab.check(deposit.health == 0.0 and deposit.yield_emitted == deposit.total_yield, "emptying the real machine emits its complete conserved currency budget")
	var removed := true
	for section: Dictionary in deposit._sections:
		removed = removed and (section["collider"] as CollisionShape3D).disabled and not (section["mesh"] as MeshInstance3D).visible
	lab.check(removed and not player.mining_ready(), "broken compartment surfaces disappear and the remaining housing cannot be harvested")
	await lab.capture("empty_housing")
	if slot:
		Profile.set_setting("hallucination_intensity", 0.0)
		# Let loot popups fade so only the cabinet is measured.
		await lab.wait(2.5)
		await _front_view(game, deposit, "slot_bank_out_of_order")
		var dead := await _close_view(game, deposit, "slot_cabinet_close_out_of_order")
		lab.check(dead < front_luma * 0.5, "an emptied bank goes out of order: its credit LEDs go dark (%.3f vs %.3f)" % [dead, front_luma])
		Profile.set_setting("hallucination_intensity", 0.65)
	# Step back to see the whole emptied cabinet with its dead lamps.
	var stand := deposit.global_position + deposit.global_basis.z.normalized() * 4.5
	player.global_position = Vector3(stand.x, game.horde.ground_height(Vector2(stand.x, stand.z)) + 1.0, stand.z)
	lab.aim_at(deposit.global_position)
	await lab.capture_strip("out_of_order", 4, 0.3)

## Whole bank from 4.5 m at a fixed gameplay time.
func _front_view(game: ArenaGame, deposit: MineralDeposit, label: String) -> void:
	var player := game.player
	var stand := deposit.global_position + deposit.global_basis.z.normalized() * 4.5
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(stand.x, game.horde.ground_height(Vector2(stand.x, stand.z)) + 1.0, stand.z)
	await lab.frames(3)
	lab.aim_at(deposit.global_position)
	var clock := game.run_time
	var image := await _image_at(game, 600.0)
	lab._save(image, label)
	game.run_time = clock
	RenderingServer.global_shader_parameter_set("hallucination_time", clock)
	game.set_process(true)

## The middle cabinet from 2 m with the HUD hidden: settled and mid-spin.
## Returns the mean luminance of the left cabinet's three LED displays.
func _close_view(game: ArenaGame, deposit: MineralDeposit, label: String) -> float:
	var player := game.player
	var stand := deposit.global_position + deposit.global_basis.z.normalized() * 2.0
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(stand.x, game.horde.ground_height(Vector2(stand.x, stand.z)) + 1.0, stand.z)
	await lab.frames(3)
	lab.aim_at(deposit.global_position + deposit.global_basis.y * deposit.formation_size.y * 0.12)
	game.hud.hide()
	var clock := game.run_time
	var spin := _next_spin(deposit, 1, 600.0)
	var shots: Array[Image] = [await _image_at(game, 600.0), await _image_at(game, spin + 0.9)]
	lab._save(shots[0], label)
	lab._save(shots[1], label + "_spinning")
	game.hud.show()
	game.run_time = clock
	RenderingServer.global_shader_parameter_set("hallucination_time", clock)
	game.set_process(true)
	var total := 0.0
	for led in SlotBankGeometry.TOP_LEDS:
		total += _luminance(shots[0], _glass_rect(player.camera, deposit, 0, led))
	return total / float(SlotBankGeometry.TOP_LEDS.size())

## Reels spin, stop with a bounce, win, and freeze under pause.
func _reel_review(game: ArenaGame, deposit: MineralDeposit) -> void:
	var player := game.player
	var seed := _slot_seed(deposit)
	var cabinet := 1
	var centre := deposit.to_global(SlotBankGeometry.reel_center(deposit.formation_size, cabinet, 1))
	var stand := centre + deposit.global_basis.z.normalized() * 1.7
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(stand.x, game.horde.ground_height(Vector2(stand.x, stand.z)) + 1.0, stand.z)
	await lab.frames(3)
	lab.aim_at(centre)
	await lab.frames(2)
	var reels := _reel_rect(player.camera, deposit, cabinet)
	# Close-up strip across the middle reel's stop on a losing game: blur, hard stop, bounce, rest.
	var spin := _next_spin(deposit, cabinet, game.run_time + 1.0)
	var cycle := _cycle(seed, cabinet, spin + 0.01)
	while _rand(seed, cabinet, cycle.x, 3) < 0.15 + 0.1 * _rand(seed, cabinet, 0.0, 4) + 0.002:
		cycle.x += 1.0
	spin = _cycle_start(seed, cabinet, cycle.x)
	var stop := spin + _stop_time(seed, cabinet, cycle.x, 1)
	var shots: Array[Image] = []
	for n in 9:
		shots.append((await _image_at(game, stop - 0.3 + float(n) * 0.07)).get_region(reels))
	_sheet(shots, "reel_stop_strip")
	var spinning := await _image_at(game, stop - 0.3)
	lab.check(_difference(spinning, await _image_at(game, stop - 0.22), reels) > 0.004, "reels visibly spin with motion blur during play")
	var settled := await _image_at(game, stop + 0.8)
	lab.check(_difference(settled, await _image_at(game, stop + 1.0), reels) < 0.002, "a stopped reel rests exactly on its symbol after the bounce")
	# A winning game: the line lamps flash, the paytable row lights and the credit counts up.
	var win := _next_win(seed, cabinet, cycle.x + 1.0)
	var won := _cycle_start(seed, cabinet, win) + _stop_time(seed, cabinet, win, 2)
	var glass := deposit.to_global(_glass_point(deposit, cabinet, 0.5, 0.6))
	stand = glass + deposit.global_basis.z.normalized() * 2.4
	player.global_position = Vector3(stand.x, game.horde.ground_height(Vector2(stand.x, stand.z)) + 1.0, stand.z)
	await lab.frames(3)
	lab.aim_at(glass)
	shots.clear()
	for n in 3:
		shots.append(await _image_at(game, won + 0.5 + float(n) * 0.6))
	_sheet(shots, "slot_win")
	var credit := _glass_rect(player.camera, deposit, cabinet, SlotBankGeometry.TOP_LEDS[0])
	lab.check(_difference(shots[0], shots[2], credit) > 0.002, "a win counts the MULTIWIN credit LED up")
	game.set_process(true)
	# Pause in the middle of a spin: the blurred reels hold still.
	lab.aim_at(centre)
	spin = _next_spin(deposit, cabinet, game.run_time + 1.0)
	await _image_at(game, spin + 0.6)
	game.set_process(true)
	game.get_tree().paused = true
	var held := await _image()
	await lab.wait(0.45)
	var later := await _image()
	lab._save(later, "slot_pause")
	reels = _reel_rect(player.camera, deposit, cabinet)
	lab.check(_difference(held, later, reels) < 0.0005, "spinning reels freeze with the paused gameplay clock")
	game.get_tree().paused = false

## After the first pry: that cabinet's reels halt and its candle calls.
func _tamper_review(game: ArenaGame, deposit: MineralDeposit) -> void:
	lab.check(deposit._tampered != 0, "prying a door marks its cabinet as tampered")
	var cabinet := 0
	while cabinet < 2 and (deposit._tampered & (1 << cabinet)) == 0:
		cabinet += 1
	var player := game.player
	var saved := player.global_position
	var centre := deposit.to_global(SlotBankGeometry.reel_center(deposit.formation_size, cabinet, 1))
	var stand := centre + deposit.global_basis.z.normalized() * 2.4
	player.global_position = Vector3(stand.x, game.horde.ground_height(Vector2(stand.x, stand.z)) + 1.0, stand.z)
	await lab.frames(3)
	lab.aim_at(centre + deposit.global_basis.y * 0.25)
	await lab.capture("tampered_cabinet")
	lab.aim_at(centre)
	await lab.frames(2)
	var reels := _reel_rect(player.camera, deposit, cabinet)
	# Scrub through where its game would be spinning: the halted reels stay put.
	# Hold the guard wave and the vision pass so only the cabinet can change.
	var intensity: float = Profile.settings.hallucination_intensity
	Profile.set_setting("hallucination_intensity", 0.0)
	game.horde.set_physics_process(false)
	game.horde.set_process(false)
	var spin := _next_spin(deposit, cabinet, game.run_time + 1.0)
	var first := await _image_at(game, spin + 0.5)
	lab.check(_difference(first, await _image_at(game, spin + 0.9), reels) < 0.002, "a tampered cabinet's reels and game stop")
	game.horde.set_physics_process(true)
	game.horde.set_process(true)
	Profile.set_setting("hallucination_intensity", intensity)
	game.set_process(true)
	player.global_position = saved

# ------------------------------------------------------------------ slot clock mirror

func _slot_seed(deposit: MineralDeposit) -> int:
	return int((deposit.get_node("Reels") as GeometryInstance3D).get_instance_shader_parameter("slot_seed"))

func _mul(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF

func _hash(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x ^= x >> 16
	x = _mul(x, 2146121005)
	x ^= x >> 15
	x = _mul(x, 2221713035)
	x ^= x >> 16
	return x

func _rand(seed: int, cabinet: int, cycle: float, salt: int) -> float:
	var h := _hash(seed ^ _mul(cabinet, SLOT_SALT_CABINET))
	h = _hash(h ^ _mul(int(cycle) + 4096, SLOT_SALT_CYCLE))
	h = _hash(h ^ _mul(salt, SLOT_SALT_SALT))
	return float(h >> 8) / 16777216.0

func _length(seed: int, cabinet: int) -> float:
	return 8.0 + 6.0 * _rand(seed, cabinet, 0.0, 1)

## x: cycle index, y: seconds into it.
func _cycle(seed: int, cabinet: int, t: float) -> Vector2:
	var length := _length(seed, cabinet)
	var x := t + _rand(seed, cabinet, 0.0, 2) * length
	var k := floorf(x / length)
	return Vector2(k, x - k * length)

func _cycle_start(seed: int, cabinet: int, k: float) -> float:
	var length := _length(seed, cabinet)
	return k * length - _rand(seed, cabinet, 0.0, 2) * length

func _stop_time(seed: int, cabinet: int, k: float, reel: int) -> float:
	var t := 1.3 + 0.5 * _rand(seed, cabinet, k, 10)
	for r in range(1, reel + 1):
		t += 0.35 + 0.15 * _rand(seed, cabinet, k, 10 + r)
	return t

## First cycle from `k` that wins with a clear margin (float32 shader agrees).
func _next_win(seed: int, cabinet: int, k: float) -> float:
	var chance := 0.15 + 0.1 * _rand(seed, cabinet, 0.0, 4)
	while _rand(seed, cabinet, k, 3) > chance - 0.002:
		k += 1.0
	return k

## Gameplay time when the cabinet's next spin after `after` begins.
func _next_spin(deposit: MineralDeposit, cabinet: int, after: float) -> float:
	var seed := _slot_seed(deposit)
	var cycle := _cycle(seed, cabinet, after)
	return _cycle_start(seed, cabinet, cycle.x + 1.0)

## Local point at normalized top-glass coordinates (u right, v down) of a cabinet.
func _glass_point(deposit: MineralDeposit, cabinet: int, u: float, v: float) -> Vector3:
	var reels := SlotBankGeometry.TOP_REELS
	var left := SlotBankGeometry.reel_center(deposit.formation_size, cabinet, 0)
	var mid := SlotBankGeometry.reel_center(deposit.formation_size, cabinet, 1)
	var right := SlotBankGeometry.reel_center(deposit.formation_size, cabinet, 2)
	var width := (right.x - left.x) / (reels[2].x - reels[0].x)
	var payline := reels[1].y + reels[1].w * 0.5
	return Vector3(mid.x + (u - reels[1].x) * width, mid.y - (v - payline) * width / SlotBankGeometry.TOP_ASPECT, mid.z)

## Screen rectangle over a (u0, v0, u1, v1) window of a cabinet's top glass.
func _glass_rect(camera: Camera3D, deposit: MineralDeposit, cabinet: int, window: Vector4) -> Rect2i:
	var screen := Rect2(camera.unproject_position(deposit.to_global(_glass_point(deposit, cabinet, window.x, window.y))), Vector2.ZERO)
	screen = screen.expand(camera.unproject_position(deposit.to_global(_glass_point(deposit, cabinet, window.z, window.w))))
	return Rect2i(screen).intersection(Rect2i(Vector2i.ZERO, Vector2i(lab.get_viewport().get_visible_rect().size)))

## Screen rectangle over a cabinet's three top reel windows (inside their bezels).
func _reel_rect(camera: Camera3D, deposit: MineralDeposit, cabinet: int) -> Rect2i:
	var first := SlotBankGeometry.TOP_REELS[0]
	var last := SlotBankGeometry.TOP_REELS[2]
	return _glass_rect(camera, deposit, cabinet, Vector4(first.x - first.z * 0.45, first.y + first.w * 0.05, last.x + last.z * 0.45, first.y + first.w * 0.95))

# ------------------------------------------------------------------ captures

## Renders a frame at an exact gameplay time (game clock held; caller restores processing).
func _image_at(game: ArenaGame, t: float) -> Image:
	game.set_process(false)
	game.run_time = t
	RenderingServer.global_shader_parameter_set("hallucination_time", t)
	return await _image()

func _sheet(shots: Array[Image], label: String) -> void:
	var cell := shots[0].get_size()
	var columns := mini(3, shots.size())
	var rows := ceili(float(shots.size()) / float(columns))
	var sheet := Image.create_empty(cell.x * columns, cell.y * rows, false, shots[0].get_format())
	for n in shots.size():
		sheet.blit_rect(shots[n], Rect2i(Vector2i.ZERO, cell), Vector2i(n % columns * cell.x, n / columns * cell.y))
	lab._save(sheet, label)

func _image() -> Image:
	await lab.frames(2)
	await RenderingServer.frame_post_draw
	return lab.get_viewport().get_texture().get_image()

func _region(camera: Camera3D, point: Vector3, half := Vector2i(160, 60)) -> Rect2i:
	return Rect2i(Vector2i(camera.unproject_position(point)) - half, half * 2)

func _difference(a: Image, b: Image, region: Rect2i) -> float:
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var total := 0.0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
	return total / maxf(float(clipped.get_area()) * 3.0, 1.0)

func _luminance(image: Image, region: Rect2i) -> float:
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var total := 0.0
	for y in range(clipped.position.y, clipped.end.y, 2):
		for x in range(clipped.position.x, clipped.end.x, 2):
			total += image.get_pixel(x, y).get_luminance()
	return total / maxf(float(clipped.get_area()) * 0.25, 1.0)
