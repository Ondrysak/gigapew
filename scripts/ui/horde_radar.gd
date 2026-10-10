class_name HordeRadar
extends Control

## Top-down threat display centred on the player, rotated so "up" is forward.
## Helps a first-person player read crowds approaching from behind.

@export var range_meters := 32.0
@export var max_dots := 350
@export var background := Color(0.01, 0.03, 0.045, 0.78)
@export var ring_color := Color(0.1, 0.75, 0.8, 0.45)
@export var dot_color := Color(1.0, 0.25, 0.45, 0.9)
@export var boss_color := Color(1.0, 0.75, 0.2, 1.0)
@export var player_color := Color(0.7, 1.0, 0.95, 1.0)
@export var wall_color := Color(0.4, 0.62, 0.7, 0.5)

var _positions := PackedVector2Array()
var _count := 0
var _player := Vector2.ZERO
var _yaw := 0.0
var _boss := Vector2.INF
var _loot: PickupField
var _vein := Vector2.INF
var _vein_ready := false
@onready var _vein_icon := GameIcons.lookup(&"resources", &"gold")
@onready var _magnet_icon := GameIcons.lookup(&"hud", &"magnet")
@onready var _repair_icon := GameIcons.lookup(&"hud", &"health")
## World centres of rock cells bordering walkable floor, for the wall layer.
var _wall_cells := PackedVector2Array()
var _wall_cell_size := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Generated levels draw their nearby walls; authored arenas clear the layer.
func set_layout(world: ProceduralWorld) -> void:
	_wall_cells.clear()
	if world == null:
		return
	_wall_cell_size = ProceduralWorld.CELL_SIZE
	for z in world.layout_height:
		for x in world.layout_width:
			if world.layout_open[z * world.layout_width + x] == 1:
				continue
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := Vector2i(x, z) + step
				if next.x >= 0 and next.y >= 0 and next.x < world.layout_width and next.y < world.layout_height and world.layout_open[next.y * world.layout_width + next.x] == 1:
					_wall_cells.append(world.layout_origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * _wall_cell_size)
					break

func refresh(horde: Horde, player: Node3D, boss_index: int, loot: PickupField, encounter: MiningDefense) -> void:
	_count = horde.sample_positions(_positions, max_dots)
	_player = Vector2(player.global_position.x, player.global_position.z)
	_yaw = player.global_rotation.y
	_loot = loot
	_boss = Vector2.INF
	if boss_index >= 0 and horde.is_alive(boss_index):
		var at := horde.enemy_position(boss_index)
		_boss = Vector2(at.x, at.z)
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
	draw_circle(center, radius, background)
	draw_arc(center, radius - 1.0, 0.0, TAU, 48, ring_color, 2.0, true)
	draw_arc(center, radius * 0.5, 0.0, TAU, 32, Color(ring_color, ring_color.a * 0.5), 1.0, true)
	if not _wall_cells.is_empty():
		# Same mapping as _map, applied to whole cells so walls keep their shape.
		draw_set_transform(center, _yaw, Vector2.ONE * radius / range_meters)
		var limit := (range_meters - _wall_cell_size) * (range_meters - _wall_cell_size)
		var half := Vector2.ONE * _wall_cell_size * 0.5
		for cell in _wall_cells:
			var local := cell - _player
			if local.length_squared() <= limit:
				draw_rect(Rect2(local - half, half * 2.0), wall_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for n in _count:
		draw_rect(Rect2(_map(_positions[n]) - Vector2.ONE, Vector2(2.5, 2.5)), dot_color)
	if is_instance_valid(_loot):
		_draw_pickups(_loot._magnets, _magnet_icon)
		_draw_pickups(_loot._repairs, _repair_icon)
		_draw_pickups(_loot._supplies, _repair_icon)
	if _vein != Vector2.INF:
		var point := _map(_vein)
		var color := Color(0.35, 1.0, 0.78) if _vein_ready else Color(1.0, 0.7, 0.24)
		draw_circle(point, 10.0, Color(color, 0.3))
		draw_arc(point, 10.0, 0.0, TAU, 16, color, 1.5, true)
		if _vein_icon != null:
			draw_texture_rect(_vein_icon, Rect2(point - Vector2(7, 7), Vector2(14, 14)), false)
	if _boss != Vector2.INF:
		var at := _map(_boss)
		var skull := GameIcons.lookup(&"hud", &"boss")
		draw_circle(at, 9.0, Color(boss_color, 0.35))
		if skull != null:
			draw_texture_rect(skull, Rect2(at - Vector2(8, 8), Vector2(16, 16)), false)
		else:
			draw_circle(at, 5.0, boss_color)
	# Player marker: a small forward-pointing wedge.
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -7), center + Vector2(5, 5), center + Vector2(-5, 5)]), player_color)

func _draw_pickups(pool: PickupField.PickupSet, icon: Texture2D) -> void:
	if icon == null:
		return
	var range_squared := range_meters * range_meters
	for index in pool.count:
		var point := Vector2(pool.positions[index].x, pool.positions[index].z)
		if point.distance_squared_to(_player) <= range_squared:
			draw_texture_rect(icon, Rect2(_map(point) - Vector2(5, 5), Vector2(10, 10)), false)
