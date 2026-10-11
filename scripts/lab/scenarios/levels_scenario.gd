extends LabScenario

func title() -> String:
	return "Procedural levels"

func summary() -> String:
	return "Seeded arenas, overlooks, wall machines, connected walk-up routes and guaranteed contract loot"

func run() -> void:
	for stage in 3:
		var first_layout: Array = []
		var first_contract: Array = []
		for sample in 3:
			if is_instance_valid(lab.game):
				lab.game.free()
			var seed_value := 8721 + (91 if sample == 2 else 0)
			var game := await lab.start_game(&"driller", stage, true, seed_value)
			await lab.wait(0.25)
			var world := game.world as ProceduralWorld
			lab.check(world != null, "stage %d loads its real procedural world" % stage)
			if world == null:
				return
			var layout: Array = [world.get_node("PlayerSpawn").transform]
			for root_name in ["Obstacles", "Elevation"]:
				for body: StaticBody3D in world.get_node(root_name).get_children():
					layout.append(body.transform)
					for collider in body.get_children():
						if collider is CollisionShape3D:
							layout.append(collider.shape.size if collider.shape is BoxShape3D else Vector2(collider.shape.radius, collider.shape.height))
			var contract: Array = []
			for quest: Dictionary in game.quests.quests:
				contract.append([quest.kind, quest.id, quest.target])
			if sample == 0:
				first_layout = layout
				first_contract = contract
			elif sample == 1:
				lab.check(layout == first_layout and contract == first_contract, "stage %d repeats identical collision layout, spawn and objectives for the same seed" % stage)
			else:
				lab.check(layout != first_layout, "stage %d changes collision layout and spawn with another seed" % stage)
				lab.check(contract != first_contract, "stage %d changes its contract with another seed" % stage)
			_validate_routes(game, world)
			_validate_ore(game, world)
			_validate_elevation(game, world)
			if sample != 1:
				await lab.capture("%s_%d_start" % [game.campaign[stage].id, sample])
				var overview := Camera3D.new()
				overview.projection = Camera3D.PROJECTION_ORTHOGONAL
				overview.size = game.campaign[stage].play_area.size.x + 8.0
				overview.position = Vector3(0, 75, 0)
				overview.rotation.x = -PI * 0.5
				world.add_child(overview)
				overview.make_current()
				await lab.frames(2)
				await lab.capture("%s_%d_layout" % [game.campaign[stage].id, sample])
				overview.free()
				game.player.camera.make_current()
			if stage == 0 and sample == 0:
				await _climb(game, world)

func _validate_ore(game: ArenaGame, world: ProceduralWorld) -> void:
	var interior_ore := 0
	for resource: ResourceDefinition in game.quests.requirements():
		var available := 0
		var reachable := true
		for child in game.deposits.get_children():
			if child is MineralDeposit and child.definition.resource == resource and child.health > 0.0:
				available += child.total_yield - child.yield_emitted
				var at: Vector3 = child.global_position + child.global_basis.z.normalized() * 2.5
				reachable = reachable and not game.horde.is_blocked(Vector2(at.x, at.z), 0.5)
				for site: Dictionary in world.mining_sites:
					if site.get("interior", false) and Vector2(child.global_position.x - site.position.x, child.global_position.z - site.position.z).length() < 1.0:
						interior_ore += 1
		lab.check(available >= int(game.quests.requirements()[resource]) and reachable, "%s has enough real reachable initial machine loot (%d available / %d needed), without a respawn" % [resource.display_name, available, game.quests.requirements()[resource]])
	lab.check(interior_ore > 0, "contract machines occupy %d interior mounting faces, not only the perimeter" % interior_ore)

## The horde's own heightfield must read each deck as flat high ground and its
## ramp as one continuous climb from the floor.
func _validate_elevation(game: ArenaGame, world: ProceduralWorld) -> void:
	var stage := game.campaign[game.stage_index]
	lab.check(world.overlooks.size() == stage.overlook_count and world.outcrops.size() == stage.outcrop_count, "%s places all %d overlooks and %d machine mounting blocks" % [stage.id, stage.overlook_count, stage.outcrop_count])
	var continuous := true
	for overlook: Dictionary in world.overlooks:
		var top: Vector3 = overlook.center
		var direction: Vector3 = overlook.direction
		var size: Vector2 = overlook.size
		var edge := Vector3(top.x, 0.0, top.z) + direction * (size.x if absf(direction.x) > 0.5 else size.y) * 0.5
		var foot: Vector3 = overlook.foot
		var height: float = overlook.height
		var previous := 0.0
		for step in 9:
			var at := foot.lerp(edge, float(step) / 8.0)
			var ground := game.horde.ground_height(Vector2(at.x, at.z))
			continuous = continuous and ground >= previous - 0.05 and ground - previous < 0.6
			previous = ground
		continuous = continuous and absf(game.horde.ground_height(Vector2(top.x, top.z)) - height) < 0.1
		continuous = continuous and game.horde.ground_height(Vector2(foot.x, foot.z) + Vector2(direction.x, direction.z)) < 0.05
	lab.check(continuous, "every overlook reads as a flat deck with a continuous ramp from the floor")

## Real input walks the player up a generated ramp; a real enemy then follows.
func _climb(game: ArenaGame, world: ProceduralWorld) -> void:
	if world.overlooks.is_empty():
		return
	var overlook: Dictionary = world.overlooks[0]
	var top: Vector3 = overlook.center
	var direction: Vector3 = overlook.direction
	var foot: Vector3 = overlook.foot + direction * 1.5
	var player := game.player
	game.horde.clear()
	player.velocity = Vector3.ZERO
	player.global_position = foot + Vector3.UP * 0.3
	player.rotation.y = atan2(direction.x, direction.z)
	player.head.rotation.x = 0.0
	await lab.frames(3)
	Input.action_press(&"move_forward")
	for _frame in 240:
		await lab.get_tree().physics_frame
		if Vector2(player.global_position.x - top.x, player.global_position.z - top.z).length() < 1.5:
			break
	Input.action_release(&"move_forward")
	await lab.wait(0.3)
	lab.check(player.global_position.y > top.y - 0.2, "held W walks the player up the generated ramp onto the %.1f m deck" % top.y)
	player.head.rotation.x = -0.12
	player.rotation.y = atan2(-direction.x, -direction.z)
	await lab.capture("overlook_view")
	var start := foot + direction * 2.0
	var slot := game.horde.spawn(lab.enemy("robot_grunt"), Vector2(start.x, start.z))
	game.horde._rebuild_grid()
	var reached := false
	for _frame in 600:
		await lab.get_tree().physics_frame
		if game.horde._hp[slot] > 0.0 and game.horde._y[slot] > top.y - 0.2:
			reached = true
			break
	lab.check(reached, "a real enemy routes up the ramp to reach the player on the deck")
	game.horde.clear()

func _validate_routes(game: ArenaGame, world: ProceduralWorld) -> void:
	var area := game.campaign[game.stage_index].play_area
	var width := floori(area.size.x / 2.0)
	var depth := floori(area.size.y / 2.0)
	var open := PackedByteArray()
	var visited := PackedByteArray()
	open.resize(width * depth)
	visited.resize(width * depth)
	var start := -1
	var nearest := INF
	var spawn := Vector2(game.player.global_position.x, game.player.global_position.z)
	var free_count := 0
	for z in depth:
		for x in width:
			var at := area.position + Vector2(x * 2.0 + 1.0, z * 2.0 + 1.0)
			var index := z * width + x
			if not game.horde.is_blocked(at, 0.6):
				open[index] = 1
				free_count += 1
				if at.distance_squared_to(spawn) < nearest:
					nearest = at.distance_squared_to(spawn)
					start = index
	lab.check(not game.horde.is_blocked(spawn, 0.6) and start >= 0, "generated spawn has real player/body clearance")
	if start < 0:
		return
	var queue: Array[int] = [start]
	visited[start] = 1
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		var x := index % width
		var z := index / width
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nx: int = x + offset.x
			var nz: int = z + offset.y
			if nx < 0 or nz < 0 or nx >= width or nz >= depth:
				continue
			var neighbor := nz * width + nx
			if open[neighbor] == 0 or visited[neighbor] == 1:
				continue
			var midpoint := area.position + Vector2((x + nx) + 1.0, (z + nz) + 1.0)
			if game.horde.is_blocked(midpoint, 0.6):
				continue
			visited[neighbor] = 1
			queue.append(neighbor)
	lab.check(queue.size() == free_count, "generated walkable grid is connected from spawn (%d / %d clear cells)" % [queue.size(), free_count])
	var unreachable: Array[String] = []
	for site: Dictionary in world.mining_sites:
		var stand: Vector3 = site.position + site.normal * 2.5
		var cell := Vector2i(floori((stand.x - area.position.x) / 2.0), floori((stand.z - area.position.y) / 2.0))
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= depth or visited[cell.y * width + cell.x] == 0:
			unreachable.append("%s at %s" % [(site.support as Node).name, stand])
	lab.check(unreachable.is_empty(), "all guaranteed machine support faces have a route from spawn %s" % [unreachable])
	var feet_reachable := true
	for overlook: Dictionary in world.overlooks:
		var approach: Vector3 = overlook.foot + overlook.direction * 1.5
		var cell := Vector2i(floori((approach.x - area.position.x) / 2.0), floori((approach.z - area.position.y) / 2.0))
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= depth or visited[cell.y * width + cell.x] == 0:
			feet_reachable = false
	lab.check(feet_reachable, "every overlook ramp foot has a ground route from spawn")
