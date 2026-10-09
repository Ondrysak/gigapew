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

var _positions := PackedVector2Array()
var _count := 0
var _player := Vector2.ZERO
var _yaw := 0.0
var _boss := Vector2.INF

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh(horde: Horde, player: Node3D, boss_index: int) -> void:
	_count = horde.sample_positions(_positions, max_dots)
	_player = Vector2(player.global_position.x, player.global_position.z)
	_yaw = player.global_rotation.y
	_boss = Vector2.INF
	if boss_index >= 0 and horde.is_alive(boss_index):
		var at := horde.enemy_position(boss_index)
		_boss = Vector2(at.x, at.z)
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
	for n in _count:
		draw_rect(Rect2(_map(_positions[n]) - Vector2.ONE, Vector2(2.5, 2.5)), dot_color)
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
