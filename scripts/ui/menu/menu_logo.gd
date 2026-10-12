class_name MenuLogo
extends Control

## A misregistered two-ink street poster. Reveal remains tweenable for the
## intro; the printed copies stay fixed rather than flashing like a display.

@export var title_label: Label
@export var ghost_labels: Array[Label] = []
@export var underline: Control
@export var subtitle_label: Label
## Fraction of title characters shown.
@export_range(0.0, 1.0) var reveal := 1.0:
	set(value):
		reveal = value
		_apply_reveal()
## Underline width fraction.
@export_range(0.0, 1.0) var underline_ratio := 1.0:
	set(value):
		underline_ratio = value
		if underline != null:
			underline.scale.x = value
@export var ghost_spread := 2.0

var _ghost_bases: Array[Vector2] = []

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.045, 0.032, 0.96))

func _ready() -> void:
	for ghost in ghost_labels:
		_ghost_bases.append(ghost.position)
	if underline != null:
		underline.pivot_offset = Vector2(underline.size.x * 0.5, 0.0)
		underline.scale.x = underline_ratio
	_apply_reveal()
	StreetWear.apply(self, true)
	StreetWear.apply_tree(self)
	_apply_print()

func _apply_print() -> void:
	for index in range(ghost_labels.size()):
		var side := -1.0 if index % 2 == 0 else 1.0
		ghost_labels[index].position = _ghost_bases[index] + Vector2(side * ghost_spread, side)
		ghost_labels[index].modulate.a = 0.42
	if title_label != null:
		title_label.modulate.a = 1.0

func _apply_reveal() -> void:
	if title_label == null:
		return
	title_label.visible_ratio = reveal
	for ghost in ghost_labels:
		ghost.visible_ratio = minf(reveal * 1.15, 1.0)
