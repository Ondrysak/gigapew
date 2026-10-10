extends LabScenario

func title() -> String:
	return "Procedural levels"

func summary() -> String:
	return "Seeded themed arenas, connected walk-up routes and guaranteed contract ore"

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
			for body: StaticBody3D in world.get_node("Obstacles").get_children():
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
			_validate_ore(game)
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

func _validate_ore(game: ArenaGame) -> void:
	for resource: ResourceDefinition in game.quests.requirements():
		var available := 0
		var reachable := true
		for child in game.deposits.get_children():
			if child is MineralDeposit and child.definition.resource == resource and child.health > 0.0:
				available += child.total_yield - child.yield_emitted
				var at: Vector3 = child.global_position + child.global_basis.z.normalized() * 2.5
				reachable = reachable and not game.horde.is_blocked(Vector2(at.x, at.z), 0.5)
		lab.check(available >= int(game.quests.requirements()[resource]) and reachable, "%s has enough real reachable initial ore (%d available / %d needed), without a respawn" % [resource.display_name, available, game.quests.requirements()[resource]])

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
	var sites_reachable := true
	for site: Dictionary in world.mining_sites:
		var stand: Vector3 = site.position + site.normal * 2.5
		var cell := Vector2i(floori((stand.x - area.position.x) / 2.0), floori((stand.z - area.position.y) / 2.0))
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= depth or visited[cell.y * width + cell.x] == 0:
			sites_reachable = false
	lab.check(sites_reachable, "all guaranteed mineral support faces have a route from spawn")
