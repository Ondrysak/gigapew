extends LabScenario

var _approach_shape: CapsuleShape3D
var _approach_query: PhysicsShapeQueryParameters3D
var _floor_ray: PhysicsRayQueryParameters3D
var _quote_source: PackedStringArray = []

func title() -> String:
	return "Procedural levels"

func summary() -> String:
	return "Connected Prague streets, enterable roofed venues, physical cabinet approaches, WC fixtures and reachable contract loot"

func run() -> void:
	for stage in 3:
		var first_layout: Array = []
		var first_contract: Array = []
		var first_quotes: Array[String] = []
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
			var quotes: Array[String] = []
			for site: Dictionary in world.kit_sites:
				for sign: Dictionary in site.get("quote_signs", []):
					quotes.append(sign.text)
			var layout: Array = [world.get_node("PlayerSpawn").transform]
			layout.append(world.layout_open.duplicate())
			layout.append(world.layout_walkable.duplicate())
			layout.append(world.layout_level.duplicate())
			layout.append(world.layout_roofed.duplicate())
			layout.append(world.kit_sites.duplicate(true))
			for child in game.deposits.get_children():
				if child is MineralDeposit:
					layout.append([child.definition.resource.id, child.global_transform, child.total_yield])
			for root_name in ["Ground", "Obstacles", "Elevation"]:
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
				first_quotes = quotes
			elif sample == 1:
				lab.check(layout == first_layout and contract == first_contract, "stage %d repeats identical collision layout, spawn and objectives for the same seed" % stage)
			else:
				lab.check(layout != first_layout, "stage %d changes collision layout and spawn with another seed" % stage)
				lab.check(contract != first_contract, "stage %d changes its contract with another seed" % stage)
				lab.check(quotes != first_quotes, "stage %d changes its hlasky sign selections with another run seed" % stage)
			_validate_routes(game, world)
			_validate_ore(game, world)
			_validate_elevation(game, world)
			_validate_layers(game, world)
			_validate_fixture_geometry(world)
			_validate_quotes(world)
			if sample == 0:
				await _descend(game, world)
				await _collide_lining(game, world)
				await _enter_venues(game, world)
				await _capture_layers(game, world)
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

func _venue_for(world: ProceduralWorld, mounting: Dictionary) -> Dictionary:
	for venue: Dictionary in world.kit_sites:
		if venue.has("venue_id") and int(venue.venue_id) == int(mounting.get("venue_id", -1)):
			return venue
	return {}

func _mount_for(world: ProceduralWorld, deposit: MineralDeposit) -> Dictionary:
	for mounting: Dictionary in world.mining_sites:
		if deposit.global_position.distance_to(mounting.position) < 0.1 and deposit.global_basis.z.dot(mounting.normal) > 0.99:
			return mounting
	return {}

func _compatible(kind: StringName, resource: StringName) -> bool:
	match kind:
		&"herna":
			return resource in [&"gold", &"shard"]
		&"hospoda":
			return resource in [&"gold", &"crystal"]
		&"vecerka":
			return resource == &"crystal"
		&"nonstop":
			return resource in [&"crystal", &"gold"]
	return false

func _cabinet_inside(deposit: MineralDeposit, venue: Dictionary) -> bool:
	var rect: Rect2 = venue.rect
	var floor_y := float(venue.floor_y)
	var ceiling_y := float(venue.ceiling_y)
	var housing := deposit.get_node_or_null("EmptyHousing") as MeshInstance3D
	if housing == null or not housing.visible:
		return false
	var meshes: Array[MeshInstance3D] = [housing]
	for section: Dictionary in deposit._sections:
		meshes.append(section.mesh as MeshInstance3D)
	for mesh in meshes:
		var bounds := mesh.get_aabb()
		for corner in 8:
			var point := mesh.to_global(bounds.get_endpoint(corner))
			if not rect.grow(0.08).has_point(Vector2(point.x, point.z)) or point.y < floor_y - 0.05 or point.y > ceiling_y:
				return false
	return true

func _mount_backed(game: ArenaGame, world: ProceduralWorld, deposit: MineralDeposit, mounting: Dictionary) -> bool:
	var support := mounting.get("support") as StaticBody3D
	if not is_instance_valid(support):
		return false
	var normal: Vector3 = mounting.normal
	var right := Vector3.UP.cross(normal)
	var query := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1, [game.player.get_rid(), deposit.get_rid()])
	for x in [-0.46, 0.0, 0.46]:
		for y in [-0.44, 0.44]:
			var point: Vector3 = deposit.global_position + right * deposit.formation_size.x * x + Vector3.UP * deposit.formation_size.y * y
			query.from = point + normal * 0.25
			query.to = point - normal * 0.3
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.collider != support or (hit.normal as Vector3).dot(normal) < 0.95 or absf((hit.position as Vector3).distance_to(point)) > 0.15:
				return false
	return true

func _clear_floor(game: ArenaGame, at: Vector3, floor_y: float) -> bool:
	var xz := Vector2(at.x, at.z)
	if game.horde.is_blocked(xz, 0.6) or absf(game.horde.ground_height(xz) - floor_y) > 0.1:
		return false
	if _approach_shape == null:
		_approach_shape = CapsuleShape3D.new()
		_approach_shape.radius = 0.4
		_approach_shape.height = 1.8
		_approach_query = PhysicsShapeQueryParameters3D.new()
		_approach_query.shape = _approach_shape
		_approach_query.collision_mask = 1
		_floor_ray = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)
	_approach_query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, floor_y + 0.95, at.z))
	_approach_query.exclude = [game.player.get_rid()]
	var space := game.player.get_world_3d().direct_space_state
	if not space.intersect_shape(_approach_query, 1).is_empty():
		return false
	_floor_ray.from = Vector3(at.x, floor_y + 0.2, at.z)
	_floor_ray.to = Vector3(at.x, floor_y - 0.2, at.z)
	_floor_ray.exclude = [game.player.get_rid()]
	var hit := space.intersect_ray(_floor_ray)
	return not hit.is_empty() and absf((hit.position as Vector3).y - floor_y) < 0.1 and (hit.normal as Vector3).y > 0.95

func _section_approach(deposit: MineralDeposit, section: Dictionary, floor_y: float) -> Vector3:
	var mesh := section.mesh as MeshInstance3D
	var latch := mesh.to_global(section.weak_position as Vector3)
	var normal := deposit.global_basis.z.normalized()
	var right := deposit.global_basis.x.normalized()
	var stand := deposit.global_position + right * (latch - deposit.global_position).dot(right) + normal * 2.2
	stand.y = floor_y
	return stand

func _segment_clear(game: ArenaGame, from: Vector3, to: Vector3, floor_y: float) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / 0.25))
	for step in steps + 1:
		if not _clear_floor(game, from.lerp(to, float(step) / steps), floor_y):
			return false
	return true

func _validate_ore(game: ArenaGame, world: ProceduralWorld) -> void:
	var available: Dictionary = {}
	var count := 0
	var occupied_venues: Dictionary = {}
	for child in game.deposits.get_children():
		var deposit := child as MineralDeposit
		if deposit == null:
			continue
		count += 1
		var mounting := _mount_for(world, deposit)
		var venue := _venue_for(world, mounting)
		var owned := not mounting.is_empty() and not venue.is_empty()
		lab.check(owned, "%s at %s belongs to a real venue mounting face" % [deposit.name, deposit.global_position])
		if not owned:
			continue
		var resource: StringName = deposit.definition.resource.id
		var semantic: bool = venue.kind == mounting.get("venue_kind") and _compatible(venue.kind, resource) and resource in mounting.get("resources", [])
		var physical := absf(float(mounting.floor_y) - float(venue.floor_y)) < 0.1
		physical = physical and _cabinet_inside(deposit, venue) and _mount_backed(game, world, deposit, mounting)
		lab.check(semantic and physical, "%s physically occupies its compatible %s room, backed by the actual inward wall" % [deposit.name, venue.kind])
		var reachable := true
		var section_yield := 0
		var center: Vector3 = mounting.position + mounting.normal * 2.5
		center.y = float(venue.floor_y)
		var query := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1, [game.player.get_rid()])
		for section_index in deposit._sections.size():
			var section: Dictionary = deposit._sections[section_index]
			if float(section.health) <= 0.0:
				continue
			var stand := _section_approach(deposit, section, float(venue.floor_y))
			var mesh := section.mesh as MeshInstance3D
			var latch := mesh.to_global(section.weak_position as Vector3)
			query.from = stand + Vector3.UP * 1.6
			query.to = latch + (latch - query.from).normalized() * 0.04
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			var accessible := (venue.rect as Rect2).has_point(Vector2(stand.x, stand.z)) and _segment_clear(game, center, stand, float(venue.floor_y))
			accessible = accessible and query.from.distance_to(latch) <= game.player.mining_tool.reach and not hit.is_empty() and hit.collider == deposit
			if accessible:
				var feedback := deposit.feedback_at(hit.position, int(hit.shape))
				accessible = not feedback.is_empty() and int(feedback.get("fragment", -1)) == section_index
			reachable = reachable and accessible
			if accessible and semantic and physical:
				section_yield += int(section.yield)
		lab.check(reachable and section_yield == deposit.total_yield - deposit.yield_emitted, "%s has unobstructed on-floor player approaches and real in-reach compartment rays for all initial loot" % deposit.name)
		available[deposit.definition.resource] = int(available.get(deposit.definition.resource, 0)) + section_yield
		if semantic and physical and section_yield > 0:
			occupied_venues[int(venue.venue_id)] = true
	lab.check(count > 0, "the generated rooms contain actual mineable cabinets")
	var requirements := game.quests.requirements()
	for resource: ResourceDefinition in requirements:
		var stock := int(available.get(resource, 0))
		lab.check(stock >= int(requirements[resource]), "%s has enough physically reachable initial venue loot (%d available / %d needed), without a respawn" % [resource.display_name, stock, requirements[resource]])
	for venue: Dictionary in world.kit_sites:
		if venue.kind in [&"herna", &"hospoda", &"nonstop"]:
			lab.check(occupied_venues.has(int(venue.venue_id)), "%s venue %d starts with compatible, physically reachable mineable loot" % [venue.kind, venue.venue_id])

## The horde's own heightfield must read each deck as flat high ground and its
## ramp as one continuous climb from the floor.
func _validate_elevation(game: ArenaGame, world: ProceduralWorld) -> void:
	var stage := game.campaign[game.stage_index]
	lab.check(world.overlooks.size() == stage.overlook_count and world.outcrops.size() == stage.outcrop_count, "%s places all %d overlooks and %d outdoor outcrops" % [stage.id, stage.overlook_count, stage.outcrop_count])
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
	player.global_position = foot + Vector3.UP * 1.0
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
			var from := area.position + Vector2(x * 2.0 + 1.0, z * 2.0 + 1.0)
			var to := area.position + Vector2(nx * 2.0 + 1.0, nz * 2.0 + 1.0)
			if absf(game.horde.ground_height(from) - game.horde.ground_height(to)) > 1.25:
				continue
			visited[neighbor] = 1
			queue.append(neighbor)
	lab.check(queue.size() == free_count, "generated walkable grid is connected from spawn (%d / %d clear cells)" % [queue.size(), free_count])
	var unreachable: Array[String] = []
	for site: Dictionary in world.mining_sites:
		var stand: Vector3 = site.position + site.normal * 2.5
		stand.y = float(site.floor_y)
		var cell := Vector2i(floori((stand.x - area.position.x) / 2.0), floori((stand.z - area.position.y) / 2.0))
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= depth or visited[cell.y * width + cell.x] == 0:
			unreachable.append("%s at %s" % [(site.support as Node).name, stand])
			continue
		var cell_center := Vector3(area.position.x + cell.x * 2.0 + 1.0, stand.y, area.position.y + cell.y * 2.0 + 1.0)
		if not _segment_clear(game, cell_center, stand, stand.y):
			unreachable.append("%s has no physical connection from its route cell to %s" % [(site.support as Node).name, stand])
	lab.check(unreachable.is_empty(), "all guaranteed machine support faces have a route from spawn %s" % [unreachable])
	var doors_reachable := true
	for venue: Dictionary in world.kit_sites:
		if venue.kind not in [&"wc", &"hospoda", &"herna", &"vecerka", &"nonstop"]:
			continue
		var facing: Vector2 = venue.facing
		var approach: Vector3 = venue.door + Vector3(facing.x, 0.0, facing.y) * 1.3
		var cell := Vector2i(floori((approach.x - area.position.x) / 2.0), floori((approach.z - area.position.y) / 2.0))
		var reachable := cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < depth
		if reachable:
			reachable = visited[cell.y * width + cell.x] != 0 and _clear_floor(game, approach, float(venue.floor_y))
		doors_reachable = doors_reachable and reachable
	lab.check(doors_reachable, "every public WC and indoor venue main entrance connects to the seeded spawn route")
	var feet_reachable := true
	for overlook: Dictionary in world.overlooks:
		var approach: Vector3 = overlook.foot + overlook.direction * 1.5
		var cell := Vector2i(floori((approach.x - area.position.x) / 2.0), floori((approach.z - area.position.y) / 2.0))
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= depth or visited[cell.y * width + cell.x] == 0:
			feet_reachable = false
	lab.check(feet_reachable, "every overlook ramp foot has a ground route from spawn")
	var stairs_reachable := world.stairs.size() >= 2
	for stair in world.stairs:
		for point: Vector3 in [stair.top, stair.foot]:
			var cell := Vector2i(floori((point.x - area.position.x) / 2.0), floori((point.z - area.position.y) / 2.0))
			stairs_reachable = stairs_reachable and cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < depth and visited[cell.y * width + cell.x] != 0
	lab.check(stairs_reachable, "both tops and feet of the underground shortcut are reachable from the real street spawn")

func _validate_layers(game: ArenaGame, world: ProceduralWorld) -> void:
	var wc_count := 0
	var portable_count := 0
	var venue_counts: Dictionary = {}
	var kinds: Array[StringName] = []
	var budgets := true
	for site in world.kit_sites:
		kinds.append(site.kind)
		if site.kind == &"wc":
			wc_count += 1
			lab.check(site.floor_y < -4.0, "the public WC occupies the actual underground floor")
		elif site.kind == &"toitoi":
			portable_count += 1
			lab.check(is_zero_approx(site.floor_y), "portable WC cabins stay on the street")
		elif site.kind in [&"hospoda", &"herna", &"vecerka", &"nonstop"]:
			venue_counts[site.kind] = int(venue_counts.get(site.kind, 0)) + 1
		budgets = budgets and int(site.get("colliders", 0)) <= 40
	lab.check(wc_count >= 1 and portable_count >= 2, "each Prague sector retains underground and portable public toilets")
	for kind: StringName in [&"herna", &"hospoda", &"nonstop"]:
		lab.check(int(venue_counts.get(kind, 0)) >= 2, "each Prague sector contains multiple separate enterable %s venues (%d)" % [kind, int(venue_counts.get(kind, 0))])
	if game.campaign[game.stage_index].layout_theme == &"foundry":
		lab.check(int(venue_counts.get(&"vecerka", 0)) >= 1, "Palmovka retains its playable vecerka")
	lab.check(&"construction" in kinds and &"park" in kinds, "construction and park dressing occupy reserved outdoor sites")
	lab.check(budgets and world._kit_lights <= 4 and world._kit_labels <= 64, "kit colliders, local lights and labels stay inside their budgets")
	var metadata := world.layout_walkable.size() == world.layout_open.size() and world.layout_level.size() == world.layout_open.size() and world.layout_roofed.size() == world.layout_open.size()
	var underground_count := 0
	for index in world.layout_level.size():
		if world.layout_level[index] < 0 and world.layout_walkable[index] != 0:
			underground_count += 1
			metadata = metadata and world.layout_open[index] == 0 and world.layout_roofed[index] != 0
	lab.check(metadata and underground_count > 0, "layer metadata reserves underground XZ without an overlapping street floor")
	var spawn := world.get_node("PlayerSpawn").position as Vector3
	var extraction := world.extraction_point(spawn)
	for anchor in [spawn, extraction]:
		var cell := Vector2i(floori((anchor.x - world.layout_origin.x) / world.CELL_SIZE), floori((anchor.z - world.layout_origin.y) / world.CELL_SIZE))
		var index := cell.y * world.layout_width + cell.x
		lab.check(world.layout_level[index] == 0 and world.layout_roofed[index] == 0, "spawn and extraction remain outdoors on street level")
	var connected := world.stairs.size() >= 2
	for stair in world.stairs:
		var top: Vector3 = stair.top
		var foot: Vector3 = stair.foot
		var direction: Vector3 = stair.direction
		connected = connected and not game.horde.is_blocked(Vector2(top.x, top.z), 0.6) and not game.horde.is_blocked(Vector2(foot.x, foot.z), 0.6)
		var previous := 0.0
		for step in 17:
			var at := top.lerp(foot, float(step) / 16.0)
			var ground := game.horde.ground_height(Vector2(at.x, at.z))
			connected = connected and ground <= previous + 0.2 and previous - ground < 0.85
			previous = ground
		connected = connected and game.horde.ground_height(Vector2(foot.x + direction.x, foot.z + direction.z)) < -4.0
		var middle := top.lerp(foot, 0.5)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(middle.x, 0.8, middle.z), Vector3(middle.x, -4.6, middle.z), 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
		lab.check(not hit.is_empty() and (hit.collider as Node).get_meta("stair", false) and absf((hit.position as Vector3).y - middle.y) < 0.1, "the street floor has a real physical hole over each stair ramp")
	lab.check(connected, "both stair tops and feet have clearance and a continuous real descent to -4.5 m")

func _validate_quotes(world: ProceduralWorld) -> void:
	if _quote_source.is_empty():
		for line: String in FileAccess.get_file_as_string("res://hlasky.txt").split("\n"):
			var text := line.strip_edges()
			if not text.is_empty():
				_quote_source.append(text)
	var labels := world.find_children("*", "Label3D", true, false)
	for site: Dictionary in world.kit_sites:
		var indoor := false
		var outdoor := false
		var valid := true
		for sign: Dictionary in site.get("quote_signs", []):
			var actual: Label3D = null
			for node: Label3D in labels:
				if node.global_position.distance_to(sign.position) < 0.01 and node.text == sign.rendered_text:
					actual = node
					break
			if actual == null:
				valid = false
				continue
			var bounds := actual.get_aabb()
			var size: Vector2 = sign.size
			var entire_line := _flat_quote(actual.text) == _flat_quote(sign.text)
			var fits := bounds.size.x <= size.x + 0.03 and bounds.size.y <= size.y + 0.03
			var faces := actual.global_basis.z.normalized().dot(sign.normal) > 0.99
			var ray := PhysicsRayQueryParameters3D.create(sign.position + sign.normal * 0.8, sign.position + sign.normal * 0.03, 1)
			ray.hit_from_inside = true
			var visible := world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			valid = valid and sign.text in _quote_source and entire_line and fits and faces and visible
			indoor = indoor or not bool(sign.outdoor)
			outdoor = outdoor or bool(sign.outdoor)
		if site.kind in [&"herna", &"hospoda", &"nonstop", &"vecerka"]:
			lab.check(valid and indoor and outdoor, "%s venue %d renders whole hlasky source lines on fitted, unobstructed indoor and outdoor signs" % [site.kind, site.venue_id])
		elif site.kind in [&"metro", &"wc"]:
			lab.check(valid and indoor, "%s renders real fitted hlasky notices indoors" % site.kind)
		elif site.kind in [&"park", &"construction", &"toitoi"]:
			lab.check(valid and outdoor, "%s renders real fitted hlasky boards outdoors" % site.kind)

func _flat_quote(text: String) -> String:
	return " ".join(text.replace("\n", " ").replace("\t", " ").split(" ", false))

func _enter_venues(game: ArenaGame, world: ProceduralWorld) -> void:
	var player := game.player
	var saved_transform := player.global_transform
	var saved_head := player.head.transform
	var saved_velocity := player.velocity
	var saved_mouse := Input.mouse_mode
	var saved_forward := Input.is_action_pressed(&"move_forward")
	var saved_mine := Input.is_action_pressed(&"mine")
	Input.action_release(&"move_forward")
	Input.action_release(&"mine")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for venue: Dictionary in world.kit_sites:
		if venue.kind not in [&"wc", &"hospoda", &"herna", &"vecerka", &"nonstop"]:
			continue
		game.horde.clear()
		var rect: Rect2 = venue.rect
		var floor_y := float(venue.floor_y)
		var door: Vector3 = venue.door
		var facing: Vector2 = venue.facing
		var outward := Vector3(facing.x, 0.0, facing.y).normalized()
		var center := Vector3(rect.get_center().x, floor_y, rect.get_center().y)
		var outside := door + outward * 1.3
		var inside := door - outward * 2.0
		var main_door := not rect.has_point(Vector2(outside.x, outside.z)) and rect.has_point(Vector2(inside.x, inside.z)) and (door - center).dot(outward) > 0.0
		lab.check(main_door and absf(door.y - floor_y) < 0.1 and _clear_floor(game, outside, floor_y), "%s main doorway has a real clear outside approach at its own floor height" % venue.kind)
		player.global_position = outside + Vector3.UP * 0.95
		player.velocity = Vector3.ZERO
		player.rotation.y = atan2(outward.x, outward.z)
		player.head.rotation.x = 0.0
		for frame in 12:
			await lab.get_tree().physics_frame
		var crossed := false
		var stayed_on_floor := player.is_on_floor() and absf(player.global_position.y - 0.9 - floor_y) < 0.1
		Input.action_press(&"move_forward")
		for frame in 180:
			await lab.get_tree().physics_frame
			stayed_on_floor = stayed_on_floor and player.is_on_floor() and absf(player.global_position.y - 0.9 - floor_y) < 0.1
			var position := player.global_position
			if rect.grow(-0.45).has_point(Vector2(position.x, position.z)) and (position - door).dot(-outward) > 1.6:
				crossed = true
				break
		Input.action_release(&"move_forward")
		for frame in 18:
			await lab.get_tree().physics_frame
			stayed_on_floor = stayed_on_floor and player.is_on_floor() and absf(player.global_position.y - 0.9 - floor_y) < 0.1
		var remains_inside := rect.grow(-0.4).has_point(Vector2(player.global_position.x, player.global_position.z))
		lab.check(crossed and remains_inside and stayed_on_floor, "held W crosses the actual %s main doorway and remains inside on its %.1f m floor" % [venue.kind, floor_y])
		await lab.capture("%s_%s_%d_held_w_entrance" % [game.campaign[game.stage_index].id, venue.kind, int(venue.get("venue_id", -1))])
		if crossed and remains_inside and stayed_on_floor and venue.kind == &"herna":
			await _pry_from_room(game, world, venue)
	Input.action_release(&"move_forward")
	Input.action_release(&"mine")
	game.horde.clear()
	player.cancel_actions()
	player.global_transform = saved_transform
	player.head.transform = saved_head
	player.velocity = saved_velocity
	Input.mouse_mode = saved_mouse
	if saved_forward:
		Input.action_press(&"move_forward")
	if saved_mine:
		Input.action_press(&"mine")

## Find a clearance-tested room route, then actually walk it: no teleport from
## the entered doorway to the machine and no forwarded mining damage.
func _room_route(game: ArenaGame, venue: Dictionary, from: Vector3, to: Vector3) -> Array[Vector3]:
	var rect: Rect2 = venue.rect
	var floor_y := float(venue.floor_y)
	from.y = floor_y
	to.y = floor_y
	var width := floori(rect.size.x)
	var depth := floori(rect.size.y)
	var previous := PackedInt32Array()
	previous.resize(width * depth)
	previous.fill(-2)
	var points: Array[Vector3] = []
	var start := -1
	var end := -1
	var start_distance := INF
	var end_distance := INF
	for z in depth:
		for x in width:
			var point := Vector3(rect.position.x + x + 0.5, floor_y, rect.position.y + z + 0.5)
			points.append(point)
			if not _clear_floor(game, point, floor_y):
				continue
			var index := z * width + x
			previous[index] = -3
			var distance := point.distance_squared_to(from)
			if distance < start_distance and distance < 2.25 and _segment_clear(game, from, point, floor_y):
				start = index
				start_distance = distance
			distance = point.distance_squared_to(to)
			if distance < end_distance and distance < 2.25 and _segment_clear(game, point, to, floor_y):
				end = index
				end_distance = distance
	if start < 0 or end < 0:
		return []
	var queue: Array[int] = [start]
	previous[start] = -1
	var cursor := 0
	while cursor < queue.size() and previous[end] == -3:
		var index := queue[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var x := index % width + offset.x
			var z := index / width + offset.y
			if x < 0 or z < 0 or x >= width or z >= depth:
				continue
			var neighbor := z * width + x
			if previous[neighbor] != -3 or not _segment_clear(game, points[index], points[neighbor], floor_y):
				continue
			previous[neighbor] = index
			queue.append(neighbor)
	if previous[end] == -3:
		return []
	var path: Array[Vector3] = [to]
	var index := end
	while index >= 0:
		path.push_front(points[index])
		index = previous[index]
	return path

func _walk_room_path(game: ArenaGame, path: Array[Vector3], floor_y: float) -> bool:
	var player := game.player
	player.head.rotation.x = 0.0
	for point in path:
		var arrived := false
		Input.action_press(&"move_forward")
		for frame in 180:
			var delta := point - player.global_position
			if Vector2(delta.x, delta.z).length() < 0.25:
				arrived = true
				break
			player.rotation.y = atan2(-delta.x, -delta.z)
			await lab.get_tree().physics_frame
			if not player.is_on_floor() or absf(player.global_position.y - 0.9 - floor_y) > 0.1:
				break
		Input.action_release(&"move_forward")
		for frame in 6:
			await lab.get_tree().physics_frame
		if not arrived:
			return false
	return true

func _pry_from_room(game: ArenaGame, world: ProceduralWorld, venue: Dictionary) -> void:
	var deposit: MineralDeposit
	for child in game.deposits.get_children():
		var candidate := child as MineralDeposit
		if candidate == null or candidate.definition.resource.id not in [&"gold", &"shard"]:
			continue
		var mounting := _mount_for(world, candidate)
		if int(mounting.get("venue_id", -1)) == int(venue.venue_id):
			deposit = candidate
			break
	lab.check(deposit != null, "the entered herna contains a real mineable fruit-machine bank")
	if deposit == null:
		return
	var route: Array[Vector3] = []
	var latch := Vector3.ZERO
	for section: Dictionary in deposit._sections:
		if float(section.health) <= 0.0 or int(section.yield) <= 0:
			continue
		var approach := _section_approach(deposit, section, float(venue.floor_y))
		route = _room_route(game, venue, game.player.global_position, approach)
		if not route.is_empty():
			latch = (section.mesh as MeshInstance3D).to_global(section.weak_position as Vector3)
			break
	var walked := not route.is_empty()
	if walked:
		walked = await _walk_room_path(game, route, float(venue.floor_y))
	lab.check(walked, "real held W walks from the entered herna doorway to a cabinet's clear room approach")
	if not walked:
		return
	lab.aim_at(latch)
	for frame in 3:
		await lab.get_tree().physics_frame
	var ready := game.player.mining_ready() and game.player.mining_tool.target_deposit == deposit
	lab.check(ready, "the room approach raises the actual crowbar on a real in-reach compartment")
	if not ready:
		return
	var health := deposit.health
	var emitted := deposit.yield_emitted
	Input.action_press(&"mine")
	for frame in ceili(Engine.physics_ticks_per_second * (health / game.player.mining_tool.mining_per_second + game.player.mining_tool.resonance_seconds + game.player.mining_tool.tick_interval)):
		await lab.get_tree().physics_frame
		if deposit.yield_emitted > emitted:
			break
	Input.action_release(&"mine")
	lab.check(deposit.health < health and deposit.yield_emitted > emitted, "held F physically pries the indoor cabinet and emits its conserved loot")
	await lab.capture("%s_herna_%d_real_cabinet_prying" % [game.campaign[game.stage_index].id, int(venue.venue_id)])
	game.horde.clear()

func _descend(game: ArenaGame, world: ProceduralWorld) -> void:
	if world.stairs.is_empty():
		return
	var stair: Dictionary = world.stairs[0]
	var top: Vector3 = stair.top
	var foot: Vector3 = stair.foot
	var direction: Vector3 = stair.direction
	var player := game.player
	var landing := foot + direction * 1.5
	game.horde.clear()
	player.velocity = Vector3.ZERO
	player.global_position = top - direction * 1.5 + Vector3.UP * 1.0
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = 0.1
	await lab.frames(3)
	Input.action_press(&"move_forward")
	for _frame in 360:
		await lab.get_tree().physics_frame
		if Vector2(player.global_position.x - landing.x, player.global_position.z - landing.z).length() < 0.5:
			break
	Input.action_release(&"move_forward")
	await lab.wait(0.25)
	var feet_y := player.global_position.y - 0.9
	lab.check(absf(feet_y - foot.y) < 0.1 and player.is_on_floor(), "held W physically descends the generated stair onto the -4.5 m underground floor")
	var start := top - direction * 2.0
	var slot := game.horde.spawn(lab.enemy("robot_grunt"), Vector2(start.x, start.z))
	game.horde._rebuild_grid()
	var reached := false
	if slot >= 0:
		for _frame in 720:
			await lab.get_tree().physics_frame
			if game.horde._hp[slot] > 0.0 and game.horde._y[slot] < -4.0:
				reached = true
				break
	lab.check(reached, "a real street enemy follows the player down the connected stair into the underground")
	game.horde.clear()

func _capture_layers(game: ArenaGame, world: ProceduralWorld) -> void:
	var intensity: float = Profile.settings.hallucination_intensity
	Profile.set_setting("hallucination_intensity", 0.0)
	game.hud.hide()
	game.player.hide()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var prefix: String = game.campaign[game.stage_index].id
	for index in world.stairs.size():
		var stair: Dictionary = world.stairs[index]
		var top: Vector3 = stair.top
		var foot: Vector3 = stair.foot
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 18.0
		camera.position = (top + foot) * 0.5 + Vector3.UP * 3.0
		camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		await lab.frames(2)
		await lab.capture("%s_stair_%d_overhead" % [prefix, index])
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = top.lerp(foot, 0.35) + Vector3.UP * 1.65
		camera.look_at(foot + Vector3.UP * 1.0)
		await lab.frames(2)
		await lab.capture("%s_stair_%d_first_person" % [prefix, index])
	var index := 0
	for site in world.kit_sites:
		if site.kind not in [&"metro", &"wc", &"hospoda", &"herna", &"vecerka", &"nonstop", &"toitoi", &"construction", &"park"]:
			continue
		var rect: Rect2 = site.rect
		var center := rect.get_center()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(rect.size.x, rect.size.y) + 1.0
		camera.position = Vector3(center.x, float(site.ceiling_y) - 0.15, center.y)
		camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		await lab.frames(2)
		await lab.capture("%s_%s_%d_overhead" % [prefix, site.kind, index])
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		var outward: Vector2 = site.facing
		var distance := -3.0 if site.kind == &"toitoi" else 1.5
		camera.position = (site.door as Vector3) - Vector3(outward.x, 0.0, outward.y) * distance + Vector3.UP * 1.65
		camera.look_at(Vector3(center.x, float(site.floor_y) + 1.4, center.y))
		await lab.frames(2)
		await lab.capture("%s_%s_%d_first_person" % [prefix, site.kind, index])
		if site.kind == &"wc":
			var bowl: Vector3 = site.toilet_points[0]
			var facing: Vector3 = site.toilet_facing
			camera.position = bowl + facing * 1.3
			camera.position.y = float(site.floor_y) + 1.55
			camera.look_at(bowl + Vector3.UP * 0.08)
			await lab.frames(2)
			await lab.capture("%s_wc_toilet_detail" % prefix)
		if site.has("countertop_point"):
			var counter: Vector3 = site.countertop_point
			camera.position = counter + (site.countertop_facing as Vector3) * 1.8 + Vector3.UP * 0.75
			camera.look_at(counter + Vector3.UP * 0.15)
			await lab.frames(2)
			await lab.capture("%s_%s_%d_counter_detail" % [prefix, site.kind, int(site.get("venue_id", -1))])
		var machine_index := 0
		for child in game.deposits.get_children():
			var deposit := child as MineralDeposit
			if deposit == null or not site.has("venue_id"):
				continue
			var mounting := _mount_for(world, deposit)
			if int(mounting.get("venue_id", -1)) != int(site.venue_id):
				continue
			var stand := deposit.global_position + deposit.global_basis.z.normalized() * 2.2
			camera.position = Vector3(stand.x, float(site.floor_y) + 1.6, stand.z)
			camera.look_at(deposit.global_position)
			await lab.frames(2)
			await lab.capture("%s_%s_%d_indoor_%s_machine_%d" % [prefix, site.kind, int(site.venue_id), deposit.definition.resource.id, machine_index])
			machine_index += 1
		index += 1
	var domains: Dictionary = {}
	for site: Dictionary in world.kit_sites:
		if site.kind not in [&"herna", &"hospoda", &"nonstop"]:
			continue
		for sign: Dictionary in site.get("quote_signs", []):
			var domain := "outdoor" if bool(sign.outdoor) else "indoor"
			if domains.has(domain):
				continue
			domains[domain] = true
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.position = sign.position + sign.normal * 1.6
			camera.look_at(sign.position)
			await lab.frames(2)
			await lab.capture("%s_hlasky_%s_detail" % [prefix, domain])
	camera.free()
	game.player.show()
	game.player.camera.make_current()
	game.hud.show()
	Profile.set_setting("hallucination_intensity", intensity)

func _validate_fixture_geometry(world: ProceduralWorld) -> void:
	for site in world.kit_sites:
		if site.kind == &"toitoi":
			lab.check(int(site.get("colliders", 0)) >= 2, "both street WC cabins retain real collision geometry")
		elif site.kind in [&"wc", &"hospoda", &"herna", &"vecerka", &"nonstop"]:
			lab.check(int(site.get("colliders", 0)) > 0, "%s contains real fixture geometry, not only a site record" % site.kind)

## Exercise the actual rendered wall strips, not just the outer terrain hull:
## adjoining underground rooms can share floor without sharing an outer wall.
func _collide_lining(game: ArenaGame, world: ProceduralWorld) -> void:
	var space := world.get_world_3d().direct_space_state
	var probes: Dictionary = {}
	var walls := 0
	var solid := true
	var query := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1, [game.player.get_rid()])
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		var mesh := batch.multimesh.mesh
		var material := ((mesh as PrimitiveMesh).material if mesh is PrimitiveMesh else mesh.surface_get_material(0)) as ShaderMaterial
		if material == null or material.shader not in [PragueKits.METRO, PragueKits.TILE]:
			continue
		var kind := &"metro" if material.shader == PragueKits.METRO else &"wc"
		var site: Dictionary = {}
		for candidate: Dictionary in world.kit_sites:
			if candidate.kind == kind:
				site = candidate
				break
		if site.is_empty():
			continue
		var rect: Rect2 = site.rect
		var source := batch.get_parent() as Node3D
		var placements: Array[Transform3D] = source.get("transforms")
		for index in placements.size():
			var transform := source.global_transform * placements[index]
			if transform.basis.y.length() < 2.0:
				continue # The floor uses the same material.
			var normal := (transform.basis.x if transform.basis.x.length() < transform.basis.z.length() else transform.basis.z).normalized()
			var point := Vector3(transform.origin.x, float(site.floor_y) + 1.1, transform.origin.z)
			var inward := Vector3(rect.get_center().x, point.y, rect.get_center().y) - point
			if normal.dot(inward) < 0.0:
				normal = -normal
			query.from = point + normal * 0.18
			query.to = point - normal * 0.18
			var hit := space.intersect_ray(query)
			var backed := not hit.is_empty() and (hit.position as Vector3).distance_to(point) < 0.18
			solid = solid and backed
			walls += 1
			var stand := point + normal * 0.95
			var xz := Vector2(stand.x, stand.z)
			if backed and not probes.has(kind) and not game.horde.is_blocked(xz, 0.4) and absf(game.horde.ground_height(xz) - float(site.floor_y)) < 0.1:
				probes[kind] = {"point": point, "normal": normal, "floor": float(site.floor_y)}
	lab.check(walls > 0 and solid, "rendered metro and WC wall strips stop real physics rays across shared underground floors")
	var player := game.player
	var saved := player.global_transform
	game.horde.clear()
	for kind in [&"metro", &"wc"]:
		if not probes.has(kind):
			lab.check(false, "%s has a clear approach for the real wall collision check" % kind)
			continue
		var probe: Dictionary = probes[kind]
		var normal: Vector3 = probe.normal
		var point: Vector3 = probe.point
		player.global_position = point + normal * 0.95
		player.global_position.y = float(probe.floor) + 0.95
		player.velocity = Vector3.ZERO
		player.rotation.y = atan2(normal.x, normal.z)
		await lab.frames(3)
		Input.action_press(&"move_forward")
		for frame in 40:
			await lab.get_tree().physics_frame
		Input.action_release(&"move_forward")
		var separation := (player.global_position - point).dot(normal)
		lab.check(separation >= 0.3 and separation < 0.65 and player.is_on_floor(), "held W stops the player capsule at the actual %s wall without crossing it" % kind)
	player.global_transform = saved
	player.velocity = Vector3.ZERO
