class_name HordeFlowField
extends RefCounted

## Shared pathfinding for the whole horde: a breadth-first distance map from
## the target over the horde grid, turned into one "downhill" direction per
## cell. Thousands of enemies route around walls and through doorways for the
## cost of one grid pass per update. Cliff edges are blocked cells, so paths
## between levels run over ramps; cell heights pick the target's level.

## Height difference beyond which a cell is on another level.
const LEVEL_GAP := 1.0

var _width := 0
var _height := 0
var _origin := Vector2.ZERO
var _cell_size := 2.0
var _passable := PackedByteArray()
var _distance := PackedInt32Array()
var _direction := PackedVector2Array()
var _queue := PackedInt32Array()
var _heights := PackedFloat32Array()
var _target_cell := -1

## `is_blocked(cell_rect: Rect2) -> bool` decides which cells are walls; it is
## given each cell's square (slightly shrunk) so thin walls anywhere in a cell,
## including on cell borders, still block. `cell_heights` is the ground height
## at each cell centre.
func setup(width: int, height: int, origin: Vector2, cell_size: float, is_blocked: Callable, cell_heights: PackedFloat32Array) -> void:
	_width = width
	_height = height
	_origin = origin
	_cell_size = cell_size
	_heights = cell_heights
	var cells := width * height
	_passable.resize(cells)
	_distance.resize(cells)
	_direction.resize(cells)
	_distance.fill(-1)
	_queue.resize(cells)
	var inset := Vector2(0.15, 0.15)
	for cell in cells:
		var corner := _origin + Vector2(cell % width, cell / width) * cell_size
		var square := Rect2(corner + inset, Vector2(cell_size, cell_size) - inset * 2.0)
		_passable[cell] = 0 if is_blocked.call(square) else 1

func is_passable(cell: int) -> bool:
	return cell >= 0 and cell < _passable.size() and _passable[cell] == 1

func is_reachable(cell: int) -> bool:
	return is_passable(cell) and _distance[cell] >= 0

## Unit direction toward the target from `cell` for a body with feet at `y`;
## zero at the target cell or where it is unreachable (callers then steer
## straight at it). Bodies in blocked cells (against walls or at cliff edges)
## slide toward the best open neighbour on their own level.
func direction_at(cell: int, y: float) -> Vector2:
	if _passable[cell] == 1:
		return _direction[cell]
	return _escape(cell, y)

## `target_y` is the target's feet height: the start cell is the nearest open
## cell on that level, so a player at a deck edge is not approached from below.
func update(target: Vector2, target_y: float) -> void:
	var start := _nearest_passable(_cell_of(target), target_y)
	if start < 0:
		_direction.fill(Vector2.ZERO)
		_distance.fill(-1)
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
		_direction[cell] = _downhill(cell) if _passable[cell] == 1 else Vector2.ZERO

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

# Bodies pressed against walls or cliff edges sit in blocked cells: steer them
# toward the best open neighbour on their level so they slide along the edge
# instead of into it (or up a cliff).
func _escape(cell: int, y: float) -> Vector2:
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
			var neighbor := nz * _width + nx
			if absf(_heights[neighbor] - y) > LEVEL_GAP:
				continue
			var d := _distance[neighbor]
			if d >= 0 and (best < 0 or d < best):
				best = d
				best_step = Vector2i(dx, dz)
	return Vector2(best_step).normalized()

func _cell_of(point: Vector2) -> int:
	var x := clampi(int((point.x - _origin.x) / _cell_size), 0, _width - 1)
	var z := clampi(int((point.y - _origin.y) / _cell_size), 0, _height - 1)
	return z * _width + x

# Nearest open cell to `cell`, preferring one on the target's level.
func _nearest_passable(cell: int, y: float) -> int:
	if _passable[cell] == 1 and absf(_heights[cell] - y) <= LEVEL_GAP:
		return cell
	var fallback := -1
	var x := cell % _width
	var z := cell / _width
	for ring in range(1, 4):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var nx := x + dx
				var nz := z + dz
				if nx < 0 or nz < 0 or nx >= _width or nz >= _height:
					continue
				var n := nz * _width + nx
				if _passable[n] != 1:
					continue
				if absf(_heights[n] - y) <= LEVEL_GAP:
					return n
				if fallback < 0:
					fallback = n
	if fallback < 0 and _passable[cell] == 1:
		return cell
	return fallback
