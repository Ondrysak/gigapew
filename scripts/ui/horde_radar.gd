class_name HordeRadar
extends Control

## Top-down threat display centred on the player, rotated so "up" is forward.
## Helps a first-person player read crowds approaching from behind.

@export var range_meters := 32.0
@export var max_dots := 350
@export var background := Color(0.07, 0.057, 0.042, 0.94)
@export var ring_color := Color(0.65, 0.54, 0.34, 0.6)
@export var dot_color := Color(0.88, 0.34, 0.25, 0.95)
@export var boss_color := Color(0.89, 0.66, 0.3, 1.0)
@export var player_color := Color(0.91, 0.85, 0.69, 1.0)
@export var wall_color := Color(0.57, 0.53, 0.4, 0.6)
@export var underground_color := Color(0.34, 0.64, 0.72, 0.8)

var _positions := PackedVector2Array()
var _heights := PackedFloat32Array()
var _underground := false
var _boss_underground := false
var _count := 0
var _player := Vector2.ZERO
var _yaw := 0.0
var _boss := Vector2.INF
var _loot: PickupField
var _vein := Vector2.INF
var _vein_ready := false
## Drop pod marker; INF when no extraction is running.
var _pod := Vector2.INF
@onready var _vein_icon := GameIcons.lookup(&"resources", &"gold")
@onready var _magnet_icon := GameIcons.lookup(&"hud", &"magnet")
@onready var _repair_icon := GameIcons.lookup(&"hud", &"health")
## World centres of rock cells bordering walkable floor, for the wall layer.
var _wall_cells := PackedVector2Array()
var _wall_cell_size := 0.0
var _wall_levels := PackedInt32Array()
var _floor_cells := PackedVector2Array()
var _floor_levels := PackedInt32Array()
var _floor_roofed := PackedByteArray()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	StreetWear.apply(self)

func set_extraction_point(at: Vector2) -> void:
	_pod = at

## Generated levels draw their nearby walls; authored arenas clear the layer.
func set_layout(world: ProceduralWorld) -> void:
	_wall_cells.clear()
	_wall_levels.clear()
	_floor_cells.clear()
	_floor_levels.clear()
	_floor_roofed.clear()
	_pod = Vector2.INF
	if world == null:
		return
	_wall_cell_size = ProceduralWorld.CELL_SIZE
	var walkable := world.layout_walkable if not world.layout_walkable.is_empty() else world.layout_open
	for z in world.layout_height:
		for x in world.layout_width:
			var key := z * world.layout_width + x
			var at := world.to_global(Vector3(world.layout_origin.x + (x + 0.5) * _wall_cell_size, 0.0, world.layout_origin.y + (z + 0.5) * _wall_cell_size))
			var center := Vector2(at.x, at.z)
			if walkable[key] == 1:
				_floor_cells.append(center)
				_floor_levels.append(world.layout_level[key] if not world.layout_level.is_empty() else 0)
				_floor_roofed.append(world.layout_roofed[key] if not world.layout_roofed.is_empty() else 0)
				continue
			var street := false
			var underground := false
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := Vector2i(x, z) + step
				if next.x < 0 or next.y < 0 or next.x >= world.layout_width or next.y >= world.layout_height:
					continue
				var neighbor := next.y * world.layout_width + next.x
				if walkable[neighbor] == 1:
					if not world.layout_level.is_empty() and world.layout_level[neighbor] < 0:
						underground = true
					else:
						street = true
			if street:
				_wall_cells.append(center)
				_wall_levels.append(0)
			if underground:
				_wall_cells.append(center)
				_wall_levels.append(-1)

func refresh(horde: Horde, player: Node3D, boss_index: int, loot: PickupField, encounter: MiningDefense) -> void:
	_count = horde.sample_positions(_positions, max_dots, _heights)
	_underground = player.global_position.y < -2.0
	_player = Vector2(player.global_position.x, player.global_position.z)
	_yaw = player.global_rotation.y
	_loot = loot
	_boss = Vector2.INF
	if boss_index >= 0 and horde.is_alive(boss_index):
		var at := horde.enemy_position(boss_index)
		_boss = Vector2(at.x, at.z)
		_boss_underground = at.y < -2.0
	_vein = Vector2.INF
	if is_instance_valid(encounter) and encounter.state != MiningDefense.State.CANCELLED and encounter.state != MiningDefense.State.CLAIMED:
		_vein = Vector2(encounter.global_position.x, encounter.global_position.z)
		_vein_ready = encounter.state == MiningDefense.State.READY
	queue_redraw()

func _map(world: Vector2) -> Vector2:
	var radius := size.x * 0.5
	# Rotate into player space: forward (-Z rotated by yaw) points up.
	var local := (world - _player).rotated(_yaw)
	var mapped := local / range_meters * radius
	return size * 0.5 + mapped.limit_length(radius - 3.0)

func _draw() -> void:
	var center := size * 0.5
	var radius := size.x * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), background)
	# A worn street-map inset, not a luminous scanner bezel.
	draw_line(Vector2(9, 3), Vector2(size.x - 15, 3), ring_color, 2.0)
	draw_line(Vector2(3, 11), Vector2(3, size.y - 7), ring_color, 1.0)
	draw_line(Vector2(12, size.y - 3), Vector2(size.x - 4, size.y - 3), ring_color, 2.0)
	draw_line(Vector2(size.x - 3, 7), Vector2(size.x - 3, size.y - 18), ring_color, 1.0)
	draw_arc(center, radius * 0.5, 0.1, PI - 0.2, 24, Color(ring_color, ring_color.a * 0.4), 1.0, true)
	if not _floor_cells.is_empty() or not _wall_cells.is_empty():
		# Map both floors, dimming the inactive layer rather than hiding its exits.
		draw_set_transform(center, _yaw, Vector2.ONE * radius / range_meters)
		var limit := (range_meters - _wall_cell_size) * (range_meters - _wall_cell_size)
		var half := Vector2.ONE * _wall_cell_size * 0.5
		for index in _floor_cells.size():
			var local := _floor_cells[index] - _player
			if local.length_squared() > limit:
				continue
			var below := _floor_levels[index] < 0
			var ink := underground_color if below else wall_color
			ink.a = (0.32 if below else (0.18 if _floor_roofed[index] != 0 else 0.07)) * (1.0 if below == _underground else 0.25)
			draw_rect(Rect2(local - half, half * 2.0), ink)
		for index in _wall_cells.size():
			var local := _wall_cells[index] - _player
			if local.length_squared() <= limit:
				var below := _wall_levels[index] < 0
				var ink := underground_color if below else wall_color
				ink.a *= 1.0 if below == _underground else 0.2
				draw_rect(Rect2(local - half, half * 2.0), ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _underground:
		draw_string(get_theme_default_font(), Vector2(8.0, size.y - 8.0), "PODZEMÍ · −1", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, underground_color)
	for n in _count:
		var below := _heights[n] < -2.0
		var ink := underground_color if below else dot_color
		ink.a *= 1.0 if below == _underground else 0.25
		var dot_size := 3.0 if below == _underground else 2.0
		draw_rect(Rect2(_map(_positions[n]) - Vector2.ONE, Vector2.ONE * dot_size), ink)
	if is_instance_valid(_loot):
		_draw_pickups(_loot._magnets, _magnet_icon)
		_draw_pickups(_loot._repairs, _repair_icon)
		_draw_pickups(_loot._supplies, _repair_icon)
	if _pod != Vector2.INF:
		# Clamped to the rim when out of range, so it always points the way.
		var at := _map(_pod)
		var ink := Color(0.73, 0.75, 0.43)
		draw_circle(at, 9.0, Color(ink, 0.25))
		draw_arc(at, 9.0, 0.0, TAU, 16, ink, 2.0, true)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(4, 0), at + Vector2(0, 5), at + Vector2(-4, 0)]), ink)
	if _vein != Vector2.INF:
		var point := _map(_vein)
		var color := Color(0.73, 0.75, 0.43) if _vein_ready else Color(0.83, 0.61, 0.3)
		draw_circle(point, 10.0, Color(color, 0.3))
		draw_arc(point, 10.0, 0.0, TAU, 16, color, 1.5, true)
		if _vein_icon != null:
			draw_texture_rect(_vein_icon, Rect2(point - Vector2(7, 7), Vector2(14, 14)), false)
	if _boss != Vector2.INF:
		var at := _map(_boss)
		var skull := GameIcons.lookup(&"hud", &"boss")
		var ink := underground_color if _boss_underground else boss_color
		ink.a *= 1.0 if _boss_underground == _underground else 0.3
		draw_circle(at, 9.0, Color(ink, ink.a * 0.35))
		if skull != null:
			draw_texture_rect(skull, Rect2(at - Vector2(8, 8), Vector2(16, 16)), false, ink)
		else:
			draw_circle(at, 5.0, ink)
	# Player marker: a small forward-pointing wedge.
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -7), center + Vector2(5, 5), center + Vector2(-5, 5)]), player_color)

func _draw_pickups(pool: PickupField.PickupSet, icon: Texture2D) -> void:
	if icon == null:
		return
	var range_squared := range_meters * range_meters
	for index in pool.count:
		var point := Vector2(pool.positions[index].x, pool.positions[index].z)
		if point.distance_squared_to(_player) <= range_squared:
			var below := pool.positions[index].y < -2.0
			var ink := underground_color if below else Color.WHITE
			ink.a *= 1.0 if below == _underground else 0.3
			draw_texture_rect(icon, Rect2(_map(point) - Vector2(5, 5), Vector2(10, 10)), false, ink)
