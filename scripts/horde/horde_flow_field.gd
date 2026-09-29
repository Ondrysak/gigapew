class_name HordeFlowField
extends RefCounted

## Shared pathfinding for the whole horde: a breadth-first distance map from
## the target over the horde grid, turned into one "downhill" direction per
## cell. Thousands of enemies route around walls and through doorways for the
## cost of one grid pass per update.

var _width := 0
var _height := 0
var _origin := Vector2.ZERO
var _cell_size := 2.0
var _passable := PackedByteArray()
var _distance := PackedInt32Array()
var _direction := PackedVector2Array()
var _queue := PackedInt32Array()
var _target_cell := -1

## `is_blocked(cell_rect: Rect2) -> bool` decides which cells are walls; it is
## given each cell's square (slightly shrunk) so thin walls anywhere in a cell,
## including on cell borders, still block.
func setup(width: int, height: int, origin: Vector2, cell_size: float, is_blocked: Callable) -> void:
	_width = width
	_height = height
	_origin = origin
	_cell_size = cell_size
	var cells := width * height
	_passable.resize(cells)
	_distance.resize(cells)
	_direction.resize(cells)
	_queue.resize(cells)
	var inset := Vector2(0.15, 0.15)
	for cell in cells:
		var corner := _origin + Vector2(cell % width, cell / width) * cell_size
		var square := Rect2(corner + inset, Vector2(cell_size, cell_size) - inset * 2.0)
		_passable[cell] = 0 if is_blocked.call(square) else 1

func is_passable(cell: int) -> bool:
	return cell >= 0 and cell < _passable.size() and _passable[cell] == 1

## Unit direction toward the target from `cell`; zero at the target cell or
## where the target is unreachable (callers then steer straight at it).
func direction_at(cell: int) -> Vector2:
	return _direction[cell]

func update(target: Vector2) -> void:
	var start := _nearest_passable(_cell_of(target))
	if start < 0:
		_direction.fill(Vector2.ZERO)
		return
	_target_cell = start
	_distance.fill(-1)
	_distance[start] = 0
	_queue[0] = start
	var head := 0
	var tail := 1
	while head < tail:
		var cell := _queue[head]
		head += 1
		var x := cell % _width
		var z := cell / _width
		var next := _distance[cell] + 1
		if x > 0:
			tail = _visit(cell - 1, next, tail)
		if x < _width - 1:
			tail = _visit(cell + 1, next, tail)
		if z > 0:
			tail = _visit(cell - _width, next, tail)
		if z < _height - 1:
			tail = _visit(cell + _width, next, tail)
	for cell in _passable.size():
		_direction[cell] = _downhill(cell) if _passable[cell] == 1 else _escape(cell)

func _visit(cell: int, next: int, tail: int) -> int:
	if _passable[cell] == 1 and _distance[cell] < 0:
		_distance[cell] = next
		_queue[tail] = cell
		return tail + 1
	return tail

# Steepest descent over the 8 neighbours; diagonals only when both
# orthogonal cells are open so paths never cut wall corners.
func _downhill(cell: int) -> Vector2:
	var own := _distance[cell]
	if own <= 0:
		return Vector2.ZERO
	var x := cell % _width
	var z := cell / _width
	var best := own
	var best_step := Vector2i.ZERO
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= _width or nz >= _height:
				continue
			if dx != 0 and dz != 0 and (_passable[z * _width + nx] == 0 or _passable[nz * _width + x] == 0):
				continue
			var d := _distance[nz * _width + nx]
			# Diagonal ties win so crowds flow on smooth 45 degree lines.
			if d >= 0 and (d < best or (d == best and d < own and dx != 0 and dz != 0)):
				best = d
				best_step = Vector2i(dx, dz)
	return Vector2(best_step).normalized()

# Bodies pressed against walls sit in blocked cells: steer them toward the
# best open neighbour so they slide along the wall instead of into it.
func _escape(cell: int) -> Vector2:
	var x := cell % _width
	var z := cell / _width
	var best := -1
	var best_step := Vector2i.ZERO
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if (dx == 0 and dz == 0) or nx < 0 or nz < 0 or nx >= _width or nz >= _height:
				continue
			var d := _distance[nz * _width + nx]
			if d >= 0 and (best < 0 or d < best):
				best = d
				best_step = Vector2i(dx, dz)
	return Vector2(best_step).normalized()

func _cell_of(point: Vector2) -> int:
	var x := clampi(int((point.x - _origin.x) / _cell_size), 0, _width - 1)
	var z := clampi(int((point.y - _origin.y) / _cell_size), 0, _height - 1)
	return z * _width + x

func _nearest_passable(cell: int) -> int:
	if _passable[cell] == 1:
		return cell
	var x := cell % _width
	var z := cell / _width
	for ring in range(1, 4):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var nx := x + dx
				var nz := z + dz
				if nx >= 0 and nz >= 0 and nx < _width and nz < _height and _passable[nz * _width + nx] == 1:
					return nz * _width + nx
	return -1
