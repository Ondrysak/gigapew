class_name PragueLayout
extends RefCounted
## One traversable height per XZ cell: a reserved building mass contains the
## passage; stairs are its only links to the surrounding street.
var width: int
var height: int
var reserved := PackedByteArray()
var underground := PackedByteArray()
var stair_cells := PackedByteArray()
var hall: Rect2i
var passage: Rect2i
var wc: Rect2i
var stairs: Array[Dictionary] = []
var bounds: Rect2i

func plan(w: int, h: int, theme: StringName) -> void:
	width = w
	height = h
	reserved.resize(w * h)
	underground.resize(w * h)
	stair_cells.resize(w * h)
	var hall_width := 10 if theme == &"reactor" else 8
	var hall_depth := 12 if theme == &"reactor" else 9
	hall = Rect2i((w - hall_width) / 2, 2, hall_width, hall_depth)
	passage = Rect2i(hall.position.x + 1, hall.end.y, 3, 2)
	wc = Rect2i(hall.position.x + 4, hall.end.y, 4, 4)
	for rect in [hall, passage, wc]:
		mark(underground, rect)
		mark(reserved, rect.grow(1))
	var z := hall.position.y + 2
	var left := Rect2i(hall.position.x - 8, z, 8, 3)
	var right := Rect2i(hall.end.x, z, 8, 3)
	for rect in [left, right]:
		mark(stair_cells, rect)
		mark(reserved, rect.grow(1))
	stairs = [
		{"cells": left, "top_cell": Vector2i(left.position.x - 1, z + 1), "foot_cell": Vector2i(hall.position.x, z + 1), "direction": Vector2.RIGHT},
		{"cells": right, "top_cell": Vector2i(right.end.x, z + 1), "foot_cell": Vector2i(hall.end.x - 1, z + 1), "direction": Vector2.LEFT},
	]
	bounds = hall.merge(left).merge(right).merge(wc).grow(1)
	# The two street approaches are the only breaks in the reservation ring.
	for stair in stairs:
		var top: Vector2i = stair.top_cell
		for dz in range(-1, 2):
			reserved[(top.y + dz) * width + top.x] = 0

func mark(mask: PackedByteArray, rect: Rect2i) -> void:
	for z in range(maxi(0, rect.position.y), mini(height, rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(width, rect.end.x)):
			mask[z * width + x] = 1

func is_reserved(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height and reserved[cell.y * width + cell.x] != 0

func intersects(rect: Rect2i) -> bool:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if is_reserved(Vector2i(x, z)):
				return true
	return false

## Connect the carved street components around (never through) the reservation.
## A multi-source breadth-first search carves the shortest solid bridge each time.
func connect_street(open: PackedByteArray, start: Vector2i) -> void:
	while true:
		var seen := PackedByteArray()
		seen.resize(open.size())
		var queue: Array[int] = [start.y * width + start.x]
		seen[queue[0]] = 1
		var cursor := 0
		while cursor < queue.size():
			var index := queue[cursor]
			cursor += 1
			for neighbor in neighbors(index):
				if open[neighbor] != 0 and seen[neighbor] == 0:
					seen[neighbor] = 1
					queue.append(neighbor)
		var missing := -1
		for index in open.size():
			if open[index] != 0 and seen[index] == 0:
				missing = index
				break
		if missing < 0:
			return
		var previous := PackedInt32Array()
		previous.resize(open.size())
		previous.fill(-1)
		for index in queue:
			previous[index] = index
		cursor = 0
		var found := -1
		while cursor < queue.size() and found < 0:
			var index := queue[cursor]
			cursor += 1
			for neighbor in neighbors(index):
				if previous[neighbor] != -1 or reserved[neighbor] != 0:
					continue
				previous[neighbor] = index
				queue.append(neighbor)
				if open[neighbor] != 0 and seen[neighbor] == 0:
					found = neighbor
					break
		assert(found >= 0, "Reserved passage must leave a street route around its mass")
		while previous[found] != found:
			var cell := Vector2i(found % width, found / width)
			for z in range(cell.y - 1, cell.y + 2):
				for x in range(cell.x - 1, cell.x + 2):
					var at := Vector2i(x, z)
					if x > 0 and z > 0 and x < width - 1 and z < height - 1 and not is_reserved(at):
						open[z * width + x] = 1
			found = previous[found]

func neighbors(index: int) -> Array[int]:
	var result: Array[int] = []
	var cell := Vector2i(index % width, index / width)
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next: Vector2i = cell + step
		if next.x > 0 and next.y > 0 and next.x < width - 1 and next.y < height - 1:
			result.append(next.y * width + next.x)
	return result

## Exact greedy rectangles for floors/ceilings; never spans a hole.
func rectangles(mask: PackedByteArray) -> Array[Rect2i]:
	var used := PackedByteArray()
	used.resize(mask.size())
	var result: Array[Rect2i] = []
	for z in height:
		for x in width:
			var index := z * width + x
			if mask[index] == 0 or used[index] != 0:
				continue
			var run := 1
			while x + run < width and mask[index + run] != 0 and used[index + run] == 0:
				run += 1
			var depth := 1
			while z + depth < height:
				var free := true
				for dx in run:
					var other := (z + depth) * width + x + dx
					if mask[other] == 0 or used[other] != 0:
						free = false
						break
				if not free:
					break
				depth += 1
			mark(used, Rect2i(x, z, run, depth))
			result.append(Rect2i(x, z, run, depth))
	return result
