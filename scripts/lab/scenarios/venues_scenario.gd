extends LabScenario

## The fourteen street venues: catalog contract, storefronts in real generated
## sectors (one capture each), the venue-named stage-clear shop, and the proof
## that the dressing is visual only (same carve, mining sites, RNG state, no
## colliders) and bounded (Label3D, instances, batches, lights).

const STAGE_IDS: Array[StringName] = [&"yard", &"foundry", &"reactor"]
## id, display name, tagline: the verbatim copy of the brief.
const EXPECTED: Array = [
	[&"vecerka", "Večerka co má otevřeno do 4:00", "absint, čipsy, cigára, EZ rank up"],
	[&"bazar", "Bazar na Roháči", "gramce, vykopaný boty, kazety, mrtvolnej pach"],
	[&"potraviny", "Potraviny s Vietnamcem", "pivo za 18, ananas a instant ramen, pure value"],
	[&"secondhand", "Second hand \"Nositel\"", "kožená bunda po mrtvým dědkovi, +200 Septik"],
	[&"hospoda", "Hospoda s točeným za 32", "kde se chlastá od oběda a pije se do dna"],
	[&"zelezarstvi", "Železářství", "lopatka, hadr, igelitka, vápno. Nářadí na work, zejo"],
	[&"trafika", "Trafika s losovačkama", "gamble jako v mojí gacze, jen horší odds"],
	[&"absintherie", "Absintherie / bar s podsvícením", "zelená víla, blesky, karma"],
	[&"ppl", "Výdejna PPL", "kde se balíky ztrácej a ty tam stojíš jak NPC"],
	[&"drogerie", "Drogerie", "Savo, rukavice, mikrotenový pytle. Musím to dál rozepsat? NE."],
	[&"reznictvi", "Řeznictví", "maso, krev, klobásy. Jedinej čistej krám v celým Žižkově"],
	[&"herna", "Herna / automat", "LudasToken ekonomika reálnýho světa, skill issue"],
	[&"pekarna", "Pekárna v 6 ráno", "pro chlapy co jdou z party a ne domů spát"],
	[&"tunel", "Žižkovskej tunel", "obchod se vzpomínkama, hlínou z hrobu a tym, co se má zapomenou"],
]
const SEED := 8721
## Explicit budgets for the storefront dressing of one whole level.
const MAX_LABELS_PER_SHOP := 3
const MAX_INSTANCES := 1000
const MAX_LEVEL_LABELS := 96
const MAX_LEVEL_BATCHES := 60
const MAX_BATCHES := 3
const MAX_LIGHTS := 4
## No part of a storefront may reach further than this off its wall (metres).
const MAX_REACH := 1.0

var _sheet: Array[Image] = []

func title() -> String:
	return "Prague venues"

func summary() -> String:
	return "14 venue storefronts in generated sectors, venue-named stage-clear shop, visual-only and bounded dressing"

func run() -> void:
	ProceduralWorld.venue_override = []
	_catalog()
	await _visual_only()
	await _storefronts()
	await _shops()
	ProceduralWorld.venue_override = []

# ------------------------------------------------------------ catalog

func _catalog() -> void:
	var catalog := ShopVenueCatalog.shared()
	lab.check(catalog != null and catalog.venues.size() == 14, "the catalog holds exactly 14 venues (%d)" % catalog.venues.size())
	var ids := {}
	var texts_ok := true
	for venue in catalog.venues:
		ids[venue.id] = true
		texts_ok = texts_ok and venue != null and not String(venue.id).is_empty() and not venue.display_name.is_empty() and not venue.sign_text.is_empty() and not venue.tagline.is_empty() and not venue.goods.is_empty()
		for item in venue.goods:
			texts_ok = texts_ok and not item.is_empty()
		texts_ok = texts_ok and not venue.goods_colors.is_empty() and not venue.sectors.is_empty()
	lab.check(ids.size() == 14, "all 14 venue ids are unique")
	lab.check(texts_ok, "every venue has a name, sign text, tagline, goods, goods colours and sectors")
	var verbatim := true
	for entry: Array in EXPECTED:
		var venue := catalog.find(entry[0])
		verbatim = verbatim and venue != null and venue.display_name == entry[1] and venue.tagline == entry[2]
		lab.check(venue != null and venue.display_name == entry[1] and venue.tagline == entry[2], "%s keeps the verbatim name and tagline" % entry[0])
	var florist := false
	for venue in catalog.venues:
		var haystack := ("%s %s %s %s" % [venue.id, venue.display_name, venue.sign_text, venue.tagline]).to_lower()
		florist = florist or haystack.contains("květin") or haystack.contains("kvetin") or haystack.contains("florist")
	lab.check(not florist and catalog.find(&"florist") == null and catalog.find(&"kvetinarstvi") == null, "there is no florist")
	var yard := catalog.for_sector(&"yard")
	var foundry := catalog.for_sector(&"foundry")
	var reactor := catalog.for_sector(&"reactor")
	var shared := false
	for venue in foundry:
		shared = shared or reactor.has(venue)
	lab.check(yard.size() == 14 and not foundry.is_empty() and not reactor.is_empty() and not shared, "Žižkov carries all 14, Palmovka %d and Hlavák %d with no overlap" % [foundry.size(), reactor.size()])
	# The shop venue is a pure function of sector and seed and draws no global RNG.
	seed(4711)
	var expected_next := randi()
	seed(4711)
	var first := catalog.shop_venue(&"yard", SEED)
	var again := catalog.shop_venue(&"yard", SEED)
	var next_value := randi()
	lab.check(first == again and first == catalog.order_for(&"yard", SEED)[0], "the shop venue repeats for the same sector and seed")
	lab.check(next_value == expected_next, "choosing a venue leaves the global RNG (shop stock RNG) untouched")
	var seen := {}
	for sample in 24:
		seen[catalog.shop_venue(&"yard", 100 + sample).id] = true
	lab.check(seen.size() >= 5, "different run seeds name different shop venues (%d of 14 in 24 seeds)" % seen.size())
	randomize()

# ------------------------------------------------------------ visual only

func _bare_world(stage_id: StringName, seed_value: int, storefronts: bool) -> ProceduralWorld:
	var stage := load("res://data/stages/%s.tres" % stage_id) as StageDefinition
	var world := stage.world_scene.instantiate() as ProceduralWorld
	world.storefronts_enabled = storefronts
	world.configure(stage, seed_value)
	lab.stage_root.add_child(world)
	return world

func _snapshot(world: ProceduralWorld) -> Dictionary:
	var colliders: Array = [world.get_node("PlayerSpawn").transform]
	for root_name in ["Obstacles", "Elevation"]:
		for body: StaticBody3D in world.get_node(root_name).get_children():
			colliders.append(body.transform)
			for collider in body.get_children():
				if collider is CollisionShape3D:
					colliders.append(collider.shape.size if collider.shape is BoxShape3D else Vector2(collider.shape.radius, collider.shape.height))
	var sites: Array = []
	for site: Dictionary in world.mining_sites:
		sites.append([site.position, site.normal, site.venue_id, site.venue_kind, site.resources])
	var rooms: Array = []
	for room: Dictionary in world.rooms:
		rooms.append([room.bounds, room.kind, room.arena, room.anchor])
	var overlooks: Array = []
	for overlook: Dictionary in world.overlooks:
		overlooks.append([overlook.center, overlook.size, overlook.height])
	return {"open": world.layout_open, "width": world.layout_width, "height": world.layout_height, "colliders": colliders, "sites": sites, "rooms": rooms, "overlooks": overlooks, "rng": world._rng.state, "bodies": _count(world, "CollisionObject3D")}

func _count(node: Node, kind: String) -> int:
	var total := 1 if node.is_class(kind) else 0
	for child in node.get_children():
		total += _count(child, kind)
	return total

func _stats(world: ProceduralWorld) -> Dictionary:
	var batches := 0
	var instances := 0
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		batches += 1
		instances += (node as MultiMeshInstance3D).multimesh.instance_count
	return {"labels": _count(world, "Label3D"), "batches": batches, "instances": instances, "lights": _count(world, "OmniLight3D"), "colliders": _count(world.get_node("Architecture"), "CollisionObject3D")}

## Same seed with and without storefronts: identical layout, ore, bodies and RNG.
func _visual_only() -> void:
	lab.stage_root = Node3D.new()
	lab.add_child(lab.stage_root)
	for stage_id in STAGE_IDS:
		for seed_value in [SEED, 5309]:
			var with_shops := _bare_world(stage_id, seed_value, true)
			var without := _bare_world(stage_id, seed_value, false)
			for _frame in 150:
				if not with_shops.is_physics_processing() and not without.is_physics_processing():
					break
				await lab.frames(1)
			await lab.frames(2)
			var a := _snapshot(with_shops)
			var b := _snapshot(without)
			lab.check(a.open == b.open and a.width == b.width and a.height == b.height and a.rooms == b.rooms, "%s seed %d: storefronts leave the walkable grid and rooms identical (%d open cells)" % [stage_id, seed_value, _open_cells(a.open)])
			lab.check(a.sites == b.sites and not (a.sites as Array).is_empty(), "%s seed %d: mining sites identical (%d)" % [stage_id, seed_value, (a.sites as Array).size()])
			lab.check(a.colliders == b.colliders and a.overlooks == b.overlooks and a.bodies == b.bodies, "%s seed %d: every collider, overlook and physics body is identical (%d bodies)" % [stage_id, seed_value, a.bodies])
			lab.check(a.rng == b.rng, "%s seed %d: the gameplay RNG ends in the same state" % [stage_id, seed_value])
			var sa := _stats(with_shops)
			var sb := _stats(without)
			var sites := with_shops.venue_sites.size()
			var venue_labels := 0
			for site: Dictionary in with_shops.venue_sites:
				venue_labels += (site.labels as Array).size()
			lab.log_line("%s seed %d: %d storefronts, +%d Label3D, +%d instances, +%d batches, +%d lights (level total %d Label3D, %d instances, %d batches)" % [stage_id, seed_value, sites, sa.labels - sb.labels, sa.instances - sb.instances, sa.batches - sb.batches, sa.lights - sb.lights, sa.labels, sa.instances, sa.batches])
			lab.check(sites >= 3 and without.venue_sites.is_empty(), "%s seed %d dresses %d storefronts, none when disabled" % [stage_id, seed_value, sites])
			lab.check(sa.labels - sb.labels == venue_labels and venue_labels <= MAX_LABELS_PER_SHOP * sites, "%s seed %d: storefront Label3D count is %d (<= %d), nothing else adds text" % [stage_id, seed_value, venue_labels, MAX_LABELS_PER_SHOP * sites])
			lab.check(sa.instances - sb.instances <= MAX_INSTANCES and sa.batches - sb.batches <= MAX_BATCHES and sa.lights - sb.lights <= MAX_LIGHTS, "%s seed %d: storefronts add %d instances (<= %d), %d batches (<= %d), %d lights (<= %d)" % [stage_id, seed_value, sa.instances - sb.instances, MAX_INSTANCES, sa.batches - sb.batches, MAX_BATCHES, sa.lights - sb.lights, MAX_LIGHTS])
			lab.check(sa.colliders == 0 and sa.colliders == sb.colliders, "%s seed %d: the dressing adds no collider" % [stage_id, seed_value])
			var lineup := ShopVenueCatalog.shared().order_for(stage_id, seed_value)
			var ids: Array[StringName] = []
			var subset := true
			for site: Dictionary in with_shops.venue_sites:
				ids.append(site.venue.id)
				subset = subset and (site.venue as ShopVenue).sectors.has(stage_id)
			lab.check(ids.has(lineup[0].id), "%s seed %d: the shop venue (%s) has a storefront on the street" % [stage_id, seed_value, lineup[0].id])
			lab.check(subset and ids.size() == _unique(ids), "%s seed %d: storefronts are distinct venues of the sector (%s)" % [stage_id, seed_value, ids])
			with_shops.free()
			without.free()
			await lab.frames(1)
	lab.stage_root.free()
	lab.stage_root = null

func _open_cells(grid: PackedByteArray) -> int:
	var total := 0
	for cell in grid:
		total += cell
	return total

func _unique(values: Array[StringName]) -> int:
	var seen := {}
	for value in values:
		seen[value] = true
	return seen.size()

# ------------------------------------------------------------ storefronts

func _storefronts() -> void:
	# Žižkov: ask for every venue; faces that cannot take one are retried on
	# another seed until all 14 have stood in a real generated yard.
	var remaining: Array[StringName] = []
	for entry: Array in EXPECTED:
		remaining.append(entry[0])
	var shown := {}
	var seed_value := SEED
	for attempt in 8:
		if remaining.is_empty():
			break
		ProceduralWorld.venue_override = remaining.duplicate()
		var game := await _fresh_game(0, seed_value + attempt * 17)
		ProceduralWorld.venue_override = []
		var world := game.world as ProceduralWorld
		lab.log_line("yard seed %d placed %d storefronts for %d requested" % [seed_value + attempt * 17, world.venue_sites.size(), remaining.size()])
		for site: Dictionary in world.venue_sites:
			var venue: ShopVenue = site.venue
			if shown.has(venue.id):
				continue
			shown[venue.id] = true
			remaining.erase(venue.id)
			await _show_site(game, site, "yard_%s" % venue.id)
	lab.check(remaining.is_empty() and shown.size() == 14, "all 14 storefronts stood in a generated Žižkov (missing: %s)" % [remaining])
	_save_sheet("yard_sheet")
	# Palmovka and Hlavák: their own seeded subsets, naturally chosen.
	for stage in [0, 1, 2]:
		var game := await _fresh_game(stage, SEED)
		var world := game.world as ProceduralWorld
		var theme := game.campaign[stage].layout_theme
		var catalog := ShopVenueCatalog.shared()
		var ids: Array[StringName] = []
		var subset := true
		for site: Dictionary in world.venue_sites:
			ids.append(site.venue.id)
			subset = subset and (site.venue as ShopVenue).sectors.has(theme)
		lab.check(subset and not ids.is_empty(), "%s dresses its own venues %s" % [theme, ids])
		_sheet.clear()
		for site: Dictionary in world.venue_sites:
			await _show_site(game, site, "natural_%s_%s" % [theme, site.venue.id])
		_save_sheet("natural_%s_sheet" % theme)
		var street_stats := _stats(world)
		var storefront_instances := 0
		for node in world.find_children("Storefronts*", "MultiMeshInstance3D", true, false):
			storefront_instances += (node as MultiMeshInstance3D).multimesh.instance_count
		lab.log_line("%s natural level: %d storefronts, %d Label3D, %d instances (%d storefront), %d batches, %d lights" % [theme, world.venue_sites.size(), street_stats.labels, street_stats.instances, storefront_instances, street_stats.batches, street_stats.lights])
		lab.check(world.venue_sites.size() >= 4 and street_stats.labels <= MAX_LEVEL_LABELS and storefront_instances <= MAX_INSTANCES and street_stats.batches <= MAX_LEVEL_BATCHES, "%s natural level stays inside its budget (%d storefronts, %d Label3D <= %d, %d storefront instances <= %d, %d batches <= %d)" % [theme, world.venue_sites.size(), street_stats.labels, MAX_LEVEL_LABELS, storefront_instances, MAX_INSTANCES, street_stats.batches, MAX_LEVEL_BATCHES])
		lab.check(catalog.shop_venue(theme, game.level_seed) != null, "%s has a shop venue" % theme)

func _fresh_game(stage: int, seed_value: int) -> ArenaGame:
	lab.get_tree().paused = false
	if is_instance_valid(lab.game):
		lab.game.free()
	var game := await lab.start_game(&"scout", stage, true, seed_value)
	game.director.set_physics_process(false)
	game.horde.clear()
	game.hud.visible = false
	await lab.wait(0.3)
	return game

## Camera on the pavement in front of a storefront; checks its text, reach and clear strip.
func _show_site(game: ArenaGame, site: Dictionary, label: String) -> void:
	var world := game.world as ProceduralWorld
	var venue: ShopVenue = site.venue
	var normal: Vector3 = site.normal
	var tangent: Vector3 = site.tangent
	var width: float = site.width
	var origin: Vector3 = site.position
	var from := origin + Vector3.UP * 1.6 + normal * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, from + normal * 4.2)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	var room := 4.2 if hit.is_empty() else from.distance_to(hit["position"])
	var distance := clampf(room - 0.5, 2.2, 3.9)
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = clampf(rad_to_deg(2.0 * atan(2.15 / distance)), 40.0, 92.0)
	camera.position = origin + normal * (distance + 0.3) + Vector3.UP * 1.7
	camera.look_at_from_position(camera.position, origin + Vector3.UP * 1.95, Vector3.UP)
	world.add_child(camera)
	camera.make_current()
	await lab.frames(3)
	await lab.wait(0.15)
	var fits := true
	var worst := ""
	for text: Label3D in site.labels:
		var box := text.get_aabb()
		var fit: Vector2 = text.get_meta(&"fit")
		var ok := box.size.x <= fit.x + 0.02 and box.size.y <= fit.y + 0.02
		fits = fits and ok
		if not ok:
			worst = "'%s' %.2fx%.2f in %.2fx%.2f" % [text.text.left(24), box.size.x, box.size.y, fit.x, fit.y]
	lab.check(fits, "%s: sign and tagline text fit their boards %s" % [label, worst])
	lab.check(float(site.reach) <= MAX_REACH, "%s: parts reach %.2f m off the wall (<= %.2f)" % [label, float(site.reach), MAX_REACH])
	# Real physics: a solid wall just behind the sign line, nothing at all in the
	# strip the dressing reaches into (rays from head height down to the pavement).
	var space := world.get_world_3d().direct_space_state
	var behind := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.5 + normal * 0.4, origin + Vector3.UP * 1.5 - normal * 0.4)
	var wall := not space.intersect_ray(behind).is_empty()
	var clear := true
	var blocked_at := ""
	for step in 12:
		var u := -width * 0.5 + width * step / 11.0
		for out in [0.2, 0.6, 0.95]:
			var point: Vector3 = origin + tangent * u + normal * out
			var down := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.UP * 0.08)
			var found := space.intersect_ray(down)
			if not found.is_empty():
				clear = false
				blocked_at = "u %.1f out %.2f hits %s" % [u, out, (found["collider"] as Node).get_path()]
	lab.check(wall and clear, "%s: a solid wall behind it and open floor in front, so nothing floats or blocks a route %s" % [label, blocked_at])
	await lab.capture(label)
	var image := lab.get_viewport().get_texture().get_image()
	image.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	_sheet.append(image)
	camera.free()
	game.player.camera.make_current()

func _save_sheet(label: String) -> void:
	if _sheet.is_empty():
		return
	var columns := 3
	var rows := ceili(float(_sheet.size()) / columns)
	var sheet := Image.create_empty(640 * columns, 360 * rows, false, _sheet[0].get_format())
	for index in _sheet.size():
		sheet.blit_rect(_sheet[index], Rect2i(0, 0, 640, 360), Vector2i(index % columns * 640, index / columns * 360))
	lab._save(sheet, label)
	_sheet.clear()

# ------------------------------------------------------------ stage-clear shop

func _shops() -> void:
	var catalog := ShopVenueCatalog.shared()
	# Pick seeds that name different venues in each sector.
	var picks: Array = []
	var named := {}
	for stage in 3:
		var theme := STAGE_IDS[stage]
		var wanted := 2 if stage == 0 else 1
		var count := 0
		for sample in 60:
			var venue := catalog.shop_venue(theme, 2000 + sample)
			if not named.has(venue.id) and count < wanted:
				named[venue.id] = true
				picks.append([stage, 2000 + sample, venue])
				count += 1
	lab.check(picks.size() >= 4, "%d sector/seed pairs name four different shop venues" % picks.size())
	for pick: Array in picks:
		var stage: int = pick[0]
		var venue: ShopVenue = pick[2]
		var game := await _fresh_game(stage, pick[1])
		game.hud.visible = true
		Profile.add_currency(&"gold", 120)
		Profile.add_currency(&"crystal", 40)
		# Isolated earned-clear fixture for venue presentation.
		game.director.boss_defeated = true
		game.director.finished = true
		game._stage_clear_pending = true
		game._finish_stage_clear()
		await lab.wait(0.5)
		var screen := game.round_shop
		lab.check(screen.venue == venue and screen._title.text.contains(venue.display_name.to_upper()) and screen._venue_line.text == venue.tagline, "stage %d seed %d: the shop header names %s and its tagline" % [stage + 1, pick[1], venue.id])
		_check_header(screen)
		await lab.capture("shop_%s_%s" % [STAGE_IDS[stage], venue.id])
	# Every venue's header and tagline must fit the shop layout.
	var last := await _fresh_game(0, SEED)
	last.director.boss_defeated = true
	last.director.finished = true
	last._stage_clear_pending = true
	last._finish_stage_clear()
	await lab.wait(0.3)
	var screen := last.round_shop
	var all_fit := true
	var longest := ""
	for venue in catalog.venues:
		screen.open(last.run_state, 0, &"scout", "Souhrn", venue, last.campaign, 0, last.run_config)
		await lab.frames(2)
		var fits := _header_fits(screen)
		all_fit = all_fit and fits
		if not fits:
			longest = venue.id
	lab.check(all_fit, "every venue's shop header and tagline fit without clipping or growing the layout %s" % longest)

func _header_fits(screen: RoundShopScreen) -> bool:
	var rows: Control = screen.get_child(1).get_child(0)
	var heading: Control = screen._title.get_parent()
	var title_font := screen._title.get_theme_font(&"font")
	var title_width := title_font.get_string_size(screen._title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var line_font := screen._venue_line.get_theme_font(&"font")
	var line_width := line_font.get_string_size(screen._venue_line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	return rows.get_combined_minimum_size().y <= rows.size.y + 0.5 and title_width <= heading.size.x and line_width <= heading.size.x

func _check_header(screen: RoundShopScreen) -> void:
	lab.check(_header_fits(screen), "the venue header (%s) fits beside the wallet without clipping, and the shop layout stays within the viewport" % screen._title.text)
