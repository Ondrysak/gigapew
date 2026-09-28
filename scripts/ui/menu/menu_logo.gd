class_name MenuLogo
extends Control

## Neon title with chromatic ghost copies. `reveal`, `glitch` and `underline`
## are tweenable; idle glitch bursts keep a static logo alive.

@export var title_label: Label
@export var ghost_labels: Array[Label] = []
@export var underline: Control
@export var subtitle_label: Label
## Fraction of title characters shown.
@export_range(0.0, 1.0) var reveal := 1.0:
	set(value):
		reveal = value
		_apply_reveal()
## 0 = stable; 1 = heavy jitter and flicker.
@export_range(0.0, 1.0) var glitch := 0.0
## Underline width fraction.
@export_range(0.0, 1.0) var underline_ratio := 1.0:
	set(value):
		underline_ratio = value
		if underline != null:
			underline.scale.x = value
## Random seconds between idle glitch bursts; x <= 0 disables them.
@export var idle_burst_interval := Vector2(2.5, 6.0)
@export var ghost_spread := 16.0

var _ghost_bases: Array[Vector2] = []
var _burst := 0.0
var _next_burst := 0.0

func _ready() -> void:
	for ghost in ghost_labels:
		_ghost_bases.append(ghost.position)
	if underline != null:
		underline.pivot_offset = Vector2(underline.size.x * 0.5, 0.0)
		underline.scale.x = underline_ratio
	_next_burst = randf_range(idle_burst_interval.x, idle_burst_interval.y)
	_apply_reveal()

func _process(delta: float) -> void:
	if idle_burst_interval.x > 0.0:
		_next_burst -= delta
		if _next_burst <= 0.0:
			_burst = 0.35
			_next_burst = randf_range(idle_burst_interval.x, idle_burst_interval.y)
	_burst = maxf(_burst - delta, 0.0)
	var amount := maxf(glitch, _burst * 2.0)
	for index in range(ghost_labels.size()):
		var side := -1.0 if index % 2 == 0 else 1.0
		var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3)) * ghost_spread * amount
		ghost_labels[index].position = _ghost_bases[index] + Vector2(side * (2.0 + amount * 6.0), 0.0) + jitter
		ghost_labels[index].modulate.a = 0.35 + amount * 0.5
	if title_label != null:
		title_label.modulate.a = 1.0 - (0.7 if randf() < amount * 0.25 else 0.0)

func _apply_reveal() -> void:
	if title_label == null:
		return
	title_label.visible_ratio = reveal
	for ghost in ghost_labels:
		ghost.visible_ratio = minf(reveal * 1.15, 1.0)
