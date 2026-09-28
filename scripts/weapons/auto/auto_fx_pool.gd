class_name AutoFxPool
extends RefCounted

## Pooled one-shot world-space effects (blasts, rings, sparks) duplicated from
## a hidden template authored at unit size. When every instance is busy the one
## closest to finishing is reused, so the pool never grows during play.

enum Style {
	## Uniform: snaps out to full size, then collapses as it fades.
	BLAST,
	## Flat ring in XZ: eases out from `inner_scale` to full size, thinning in Y.
	RING,
	## Uniform: pops at full size and shrinks to nothing.
	SPARK,
	## Flat ring in XZ: collapses from full size to `inner_scale`.
	IMPLODE,
}

## Starting (RING) or final (IMPLODE) fraction of the full size.
var inner_scale := 0.2

var _host: Node3D
var _template: Node3D
var _style := Style.BLAST
var _nodes: Array[Node3D] = []
var _times := PackedFloat32Array()
var _durations := PackedFloat32Array()
var _sizes := PackedFloat32Array()

func _init(host: Node3D, template: Node3D, style: Style) -> void:
	_host = host
	_template = template
	_style = style

## Grows the pool to at least `count` instances (never shrinks).
func reserve(count: int) -> void:
	while _nodes.size() < count:
		var node := _template.duplicate() as Node3D
		_host.add_child(node)
		node.top_level = true
		node.hide()
		_nodes.append(node)
	_times.resize(_nodes.size())
	_durations.resize(_nodes.size())
	_sizes.resize(_nodes.size())

## Starts one effect of `size` (world units per template unit) at `at`.
func spawn(at: Vector3, size: float, duration: float, yaw := 0.0) -> void:
	if _nodes.is_empty():
		reserve(1)
	var slot := 0
	for index in range(_times.size()):
		if _times[index] <= 0.0:
			slot = index
			break
		if _times[index] < _times[slot]:
			slot = index
	var node := _nodes[slot]
	node.global_position = at
	node.rotation = Vector3(0.0, yaw, 0.0)
	_times[slot] = maxf(duration, 0.01)
	_durations[slot] = _times[slot]
	_sizes[slot] = size
	_apply(slot, 0.0)
	node.show()

## Advances every live effect; call from the host's _process.
func update(delta: float) -> void:
	for index in range(_times.size()):
		if _times[index] <= 0.0:
			continue
		_times[index] -= delta
		if _times[index] <= 0.0:
			_nodes[index].hide()
			continue
		_apply(index, 1.0 - _times[index] / _durations[index])

func _apply(index: int, progress: float) -> void:
	var node := _nodes[index]
	var size := _sizes[index]
	match _style:
		Style.BLAST:
			var amount := sin(minf(progress * 1.6, 1.0) * PI * 0.5) * (1.0 - progress * progress * 0.7)
			node.scale = Vector3.ONE * maxf(amount * size, 0.01)
		Style.RING:
			var grow := lerpf(inner_scale, 1.0, 1.0 - pow(1.0 - progress, 3.0)) * size
			node.scale = Vector3(grow, maxf(1.0 - progress * progress, 0.05), grow)
		Style.SPARK:
			node.scale = Vector3.ONE * maxf(size * (1.0 - progress), 0.01)
		Style.IMPLODE:
			var shrink := lerpf(1.0, inner_scale, progress * progress) * size
			node.scale = Vector3(shrink, maxf(1.0 - progress * 0.6, 0.05), shrink)
