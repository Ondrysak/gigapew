@tool
class_name ElectricFloor
extends Hazard

## Shock plate centred on its origin. Cycles off -> warning -> live; while live
## it damages and slows enemies standing on it, lightly shocks a grounded
## player on it, and crackles with arcs. Jumping over it avoids the shock.

## Plate footprint in metres: local X width, local Z depth.
@export var size := Vector2(4.0, 4.0):
	set(value):
		size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		if is_node_ready():
			_layout()

@export_group("Cycle")
@export var cycle_period := 6.0
@export var live_time := 2.0
@export var warning_time := 1.0
## Seconds added to the cycle clock so neighbouring plates can alternate.
@export var phase_offset := 0.0

@export_group("Damage")
@export var enemy_dps := 30.0
## Movement factor applied to enemies on the live plate.
@export var slow_factor := 0.4
@export var slow_duration := 0.6
@export var enemy_tick := 0.2
@export var player_dps := 6.0
@export var player_tick := 0.5
## Enemies whose centre is this far past the edge still count as on the plate.
@export var edge_margin := 0.2

@export_group("Visuals")
## Unit plane scaled to `size`; its ShaderMaterial (warning/live uniforms) is
## copied per plate at setup.
@export var plate: MeshInstance3D
## Parent of the four corner emitters, placed at the plate corners (inset by
## corner_inset) in child order: -X-Z, +X-Z, -X+Z, +X+Z.
@export var corners: Node3D
@export var corner_inset := 0.18
## Hidden unit-length beam along -Z; pooled into jagged arcs.
@export var arc_template: Node3D
## Hidden unit-size spark popped on shocked enemies.
@export var spark_template: Node3D
## Live arcs per 16 m² of plate (at least 2, at most max_arcs).
@export var arcs_per_16m2 := 3.0
@export var max_arcs := 10
@export var arc_pieces := 4
@export var arc_height := 0.45
@export var arc_jag := 0.22
@export var arc_interval := 0.05
@export var spark_size := 0.35
@export var sparks_per_tick := 3

@export_group("Sound")
@export var warning_sound: AudioStream
@export var live_sound: AudioStream

enum Phase { OFF, WARNING, LIVE }

const WARNING_PARAM := &"warning"
const LIVE_PARAM := &"live"

var _phase := Phase.OFF
var _clock := 0.0
var _enemy_timer := 0.0
var _player_timer := 0.0
var _arc_timer := 0.0
var _arcs := 2
var _segments: Array[Node3D] = []
var _sparks: AutoFxPool
var _warn_voice: AudioStreamPlayer3D
var _live_voice: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _material: ShaderMaterial

func _ready() -> void:
	super()
	_layout()

func _layout() -> void:
	if plate != null:
		plate.scale = Vector3(size.x, 1.0, size.y)
	var half := size * 0.5 - Vector2.ONE * corner_inset
	if corners == null:
		return
	for index in range(corners.get_child_count()):
		var corner := corners.get_child(index) as Node3D
		if corner != null:
			var sx := -1.0 if index % 2 == 0 else 1.0
			var sz := -1.0 if index < 2 else 1.0
			corner.position = Vector3(half.x * sx, corner.position.y, half.y * sz)

func _on_setup() -> void:
	_rng.randomize()
	_material = (plate.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	plate.material_override = _material
	_arcs = clampi(ceili(size.x * size.y / 16.0 * arcs_per_16m2), 2, max_arcs)
	while _segments.size() < _arcs * arc_pieces:
		var segment := arc_template.duplicate() as Node3D
		add_child(segment)
		segment.top_level = true
		segment.hide()
		_segments.append(segment)
	_sparks = AutoFxPool.new(self, spark_template, AutoFxPool.Style.SPARK)
	_sparks.reserve(sparks_per_tick * 2)
	_warn_voice = make_voice(warning_sound, &"zap_warn", -8.0, 1)
	_live_voice = make_voice(live_sound, &"zap_live", -9.0, 1)
	_clock = phase_offset

func _tick(delta: float) -> void:
	_clock += delta
	var t := fposmod(_clock, cycle_period)
	var next := Phase.OFF
	if t >= cycle_period - live_time:
		next = Phase.LIVE
	elif t >= cycle_period - live_time - warning_time:
		next = Phase.WARNING
	if next != _phase:
		_enter(next)
	if _phase != Phase.LIVE:
		return
	_enemy_timer -= delta
	if _enemy_timer <= 0.0:
		_enemy_timer += enemy_tick
		_shock_enemies()
	_player_timer -= delta
	if _player_timer <= 0.0:
		_player_timer += player_tick
		if player.is_on_floor() and _on_plate(player.global_position, 0.0):
			player.take_damage(maxi(1, roundi(player_dps * player_tick)))

func _enter(next: Phase) -> void:
	_phase = next
	match next:
		Phase.WARNING:
			_warn_voice.play()
		Phase.LIVE:
			_enemy_timer = 0.0
			_player_timer = 0.0
			_arc_timer = 0.0
			_live_voice.play()
		Phase.OFF:
			_live_voice.stop()
			for segment in _segments:
				segment.hide()

func _on_plate(at: Vector3, margin: float) -> bool:
	var local := to_local(at)
	return absf(local.x) <= size.x * 0.5 + margin and absf(local.z) <= size.y * 0.5 + margin

func _shock_enemies() -> void:
	var found := horde.query_radius(global_position, size.length() * 0.5 + edge_margin, _hits)
	var amount := enemy_dps * enemy_tick
	var sparks := 0
	for n in found:
		var slot := _hits[n]
		var at := horde.enemy_position(slot)
		if not _on_plate(at, edge_margin):
			continue
		horde.slow(slot, slow_factor, slow_duration)
		horde.damage(slot, amount)
		if sparks < sparks_per_tick and _rng.randf() < 0.35:
			sparks += 1
			_sparks.spawn(at, spark_size, 0.12, _rng.randf() * TAU)

func _animate(delta: float) -> void:
	_sparks.update(delta)
	var warning := 0.0
	var live := 0.0
	var t := fposmod(_clock, cycle_period)
	match _phase:
		Phase.WARNING:
			# Pulses quicken and brighten toward going live.
			var progress := clampf((t - (cycle_period - live_time - warning_time)) / warning_time, 0.0, 1.0)
			warning = (0.35 + 0.65 * progress) * (0.5 + 0.5 * sin(_clock * lerpf(10.0, 30.0, progress)))
		Phase.LIVE:
			live = 1.0
			_arc_timer -= delta
			if _arc_timer <= 0.0:
				_arc_timer = arc_interval
				_layout_arcs()
	_material.set_shader_parameter(WARNING_PARAM, warning)
	_material.set_shader_parameter(LIVE_PARAM, live)

# Re-rolls every jagged arc between random plate points so the plate crackles.
func _layout_arcs() -> void:
	var half := size * 0.5
	var used := 0
	for arc in range(_arcs):
		var from := Vector3(_rng.randf_range(-half.x, half.x), 0.03, _rng.randf_range(-half.y, half.y))
		var span := _rng.randf_range(0.8, 2.2)
		var angle := _rng.randf() * TAU
		var to := Vector3(clampf(from.x + cos(angle) * span, -half.x, half.x), 0.03, clampf(from.z + sin(angle) * span, -half.y, half.y))
		var last := to_global(from)
		for piece in range(1, arc_pieces + 1):
			var local := to
			if piece < arc_pieces:
				var k := float(piece) / float(arc_pieces)
				local = from.lerp(to, k)
				local += Vector3(_rng.randf_range(-arc_jag, arc_jag), sin(k * PI) * arc_height * _rng.randf_range(0.4, 1.0), _rng.randf_range(-arc_jag, arc_jag))
			var next := to_global(local)
			AutoWeapon.place_beam(_segments[used], last, next, _rng.randf_range(0.6, 1.2))
			used += 1
			last = next
