class_name YardBossFight
extends Node3D

## Yard-only steering, telegraphs and damage. Horde remains the sole owner of
## boss movement, terrain constraints, animation and ordinary capped contact.
enum State { APPROACH, RAM_WINDUP, RAM, MORTAR_WINDUP, MORTAR, RECOVERY, CANCELLED }

@export var display_name := "Pan Herna"
@export_group("Cadence")
@export_range(0.1, 10.0) var approach_time := 1.4
@export_range(0.0, 10.0) var approach_speed := 2.6
@export_range(0.1, 10.0) var recovery_time := 2.0
@export_group("Breach Ram")
@export_range(0.1, 10.0) var ram_warning_time := 1.2
@export_range(0.1, 3.0) var ram_time := 0.8
@export_range(1.0, 30.0) var ram_speed := 18.0
@export_range(1, 100) var ram_damage := 24
@export_group("Mortar Salvo")
@export_range(0.1, 10.0) var mortar_warning_time := 1.5
@export_range(0.05, 2.0) var mortar_interval := 0.3
@export_range(0.5, 5.0) var mortar_radius := 2.4
@export_range(1, 100) var mortar_damage := 18
## Difference between player feet and the marked floor: jumping/high decks
## outside this band are safe. The marker uses the same band and cover rays.
@export_range(0.1, 3.0) var blast_height_tolerance := 1.25
@export_group("Sound")
@export var ram_warning_sound: AudioStream
@export var mortar_warning_sound: AudioStream
@export var impact_sound: AudioStream

var state := State.CANCELLED
var _horde: Horde
var _player: ArenaPlayer
var _boss := -1
var _timer := 0.0
var _duration := 1.0
var _next_ram := true
var _ram_origin := Vector3.ZERO
var _ram_direction := Vector2.UP
var _ram_previous := Vector3.ZERO
var _ram_length := 0.0
var _ram_half_width := 0.0
var _ram_hit := false
var _mortar_points := PackedVector3Array()
var _mortar_footprints: Array[PackedVector3Array] = []
var _circle_samples := PackedVector3Array()
var _circle_visible := PackedByteArray()
var _impact_count := 0
var _lane: MeshInstance3D
var _circles: Array[MeshInstance3D] = []
var _shocks: Array[MeshInstance3D] = []
var _shock_age := PackedFloat32Array()
var _core: MeshInstance3D
var _danger_material: StandardMaterial3D
var _warning_voice: AudioStreamPlayer3D
var _impact_voice: AudioStreamPlayer3D
var _cover_query: PhysicsRayQueryParameters3D
const MARK_HEIGHT := 0.065
const CIRCLE_SEGMENTS := 48
const CIRCLE_RINGS := 8
const SHOCK_TIME := 0.42

func _ready() -> void:
	# Observe the movement Horde completed this frame before swept ram checks.
	process_physics_priority = 1
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(false)
	_danger_material = _material(Color.WHITE)
	_lane = _mesh_instance(ArrayMesh.new(), _danger_material)
	_mortar_points.resize(3)
	_shock_age.resize(3)
	_mortar_footprints.resize(3)
	_circle_samples.resize((CIRCLE_RINGS + 1) * (CIRCLE_SEGMENTS + 1))
	_circle_visible.resize(_circle_samples.size())
	for n in 3:
		_circles.append(_mesh_instance(ArrayMesh.new(), _danger_material))
		_shocks.append(_mesh_instance(_circles[n].mesh, _material(Color(1.0, 0.25, 0.15, 1.0))))
		_shock_age[n] = SHOCK_TIME
	var core_mesh := TorusMesh.new()
	core_mesh.inner_radius = 0.48
	core_mesh.outer_radius = 0.65
	_core = _mesh_instance(core_mesh, _material(Color(0.04, 1.0, 0.82, 0.85)))
	_warning_voice = _voice(-5.0)
	_impact_voice = _voice(-1.0)

func setup(horde: Horde, player: ArenaPlayer) -> void:
	cancel()
	_horde = horde
	_player = player
	_boss = horde.boss_index
	if not horde.is_alive(_boss):
		return
	_cover_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 0xFFFFFFFF, [player.get_rid()])
	if not player.died.is_connected(cancel):
		player.died.connect(cancel)
	if not horde.boss_killed.is_connected(cancel):
		horde.boss_killed.connect(cancel)
	horde.control_boss(true)
	_next_ram = true
	_enter(State.APPROACH, approach_time)
	set_physics_process(true)

func instruction() -> String:
	match state:
		State.APPROACH: return "Drž si odstup — další cíl se zamkne při varování"
		State.RAM_WINDUP: return "ROZBĚH — uhni z oranžové dráhy; směr už nezmění"
		State.RAM: return "ROZBĚH — zůstaň mimo zamčenou dráhu"
		State.MORTAR_WINDUP: return "TŘI RÁNY — opusť všechny tři vyznačené kruhy"
		State.MORTAR: return "TŘI RÁNY — dopadají postupně; pevný kryt zastaví výbuch"
		State.RECOVERY: return "KRYT DOLE — teď do něj: +50 % poškození"
	return ""

func phase_progress() -> float:
	return clampf(1.0 - _timer / maxf(_duration, 0.001), 0.0, 1.0)

func remaining() -> float:
	return maxf(0.0, _timer)

## Read-only snapshots for the lab and other encounter presentation.
func ram_origin() -> Vector3:
	return _ram_origin

func ram_direction() -> Vector2:
	return _ram_direction

func mortar_target(index: int) -> Vector3:
	return _mortar_points[clampi(index, 0, 2)]

func impacts_completed() -> int:
	return _impact_count

func cancel() -> void:
	state = State.CANCELLED
	_timer = 0.0
	set_physics_process(false)
	if is_instance_valid(_horde):
		_horde.drive_boss(Vector2.ZERO, Vector2.ZERO, Horde.Mode.SEEK)
		_horde.set_boss_recovery(false)
		_horde.control_boss(false)
	if is_instance_valid(_lane):
		_lane.hide()
		_core.hide()
		for n in 3:
			_circles[n].hide()
			_shocks[n].hide()
			_shock_age[n] = SHOCK_TIME
		_warning_voice.stop()
		_impact_voice.stop()

func _exit_tree() -> void:
	cancel()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_horde) or not is_instance_valid(_player) or not _horde.is_alive(_boss) or _player.health <= 0:
		cancel()
		return
	if get_tree().paused or not _player.active:
		_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.SEEK)
		_warning_voice.stop()
		_ram_previous = _horde.enemy_position(_boss)
		return
	if _horde.is_stunned(_boss) and (state == State.RAM_WINDUP or state == State.RAM or state == State.MORTAR_WINDUP):
		_recover()
		return
	_tick_shocks(delta)
	_timer = maxf(0.0, _timer - delta)
	var boss_at := _horde.enemy_position(_boss)
	match state:
		State.APPROACH:
			var toward := Vector2(_player.global_position.x - boss_at.x, _player.global_position.z - boss_at.z)
			var facing := toward.normalized() if toward.length_squared() > 0.01 else _ram_direction
			# Approach only; do not crowd the player during the breathing interval.
			_horde.drive_boss(facing * approach_speed if toward.length() > 7.0 else Vector2.ZERO, facing, Horde.Mode.SEEK)
			if _timer <= 0.0:
				if _next_ram: _lock_ram()
				else: _lock_mortar()
		State.RAM_WINDUP:
			_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.WINDUP, phase_progress())
			if _timer <= 0.0:
				_warning_voice.stop()
				_ram_previous = boss_at
				_enter(State.RAM, ram_time)
				_horde.drive_boss(_ram_direction * ram_speed, _ram_direction, Horde.Mode.CHARGE)
		State.RAM:
			_ram_direct_hit(_ram_previous, boss_at)
			if state != State.RAM:
				return # A lethal direct hit can synchronously cancel this node.
			var moved := Vector2(boss_at.x - _ram_previous.x, boss_at.z - _ram_previous.z)
			_ram_previous = boss_at
			var traveled := Vector2(boss_at.x - _ram_origin.x, boss_at.z - _ram_origin.z).dot(_ram_direction)
			if _timer <= 0.0 or traveled >= _ram_length or (phase_progress() > 0.05 and moved.dot(_ram_direction) < ram_speed * delta * 0.2):
				_recover()
			else:
				_horde.drive_boss(_ram_direction * ram_speed, _ram_direction, Horde.Mode.CHARGE)
		State.MORTAR_WINDUP:
			_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.WINDUP, phase_progress())
			if _timer <= 0.0:
				_warning_voice.stop()
				_enter(State.MORTAR, mortar_interval * 2.0)
				_impact(0)
		State.MORTAR:
			_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.SEEK)
			while state == State.MORTAR and _impact_count < 3 and _duration - _timer >= mortar_interval * _impact_count:
				_impact(_impact_count)
			if state == State.MORTAR and _impact_count == 3:
				_recover()
		State.RECOVERY:
			_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.SEEK)
			_core.global_position = _horde.weak_spot_position(_boss)
			if _timer <= 0.0:
				_horde.set_boss_recovery(false)
				_core.hide()
				_enter(State.APPROACH, approach_time)

func _enter(next: State, duration: float) -> void:
	state = next
	_duration = maxf(0.001, duration)
	_timer = _duration

func _lock_ram() -> void:
	_next_ram = false
	_ram_hit = false
	_ram_origin = _horde.enemy_position(_boss)
	var to := Vector2(_player.global_position.x - _ram_origin.x, _player.global_position.z - _ram_origin.z)
	_ram_direction = to.normalized() if to.length_squared() > 0.01 else Vector2.UP
	var radius := _horde.get_definition(_boss).radius
	_ram_half_width = radius + Horde.PLAYER_RADIUS
	_ram_length = ram_speed * ram_time
	var origin := Vector2(_ram_origin.x, _ram_origin.z)
	var previous_height := _horde.ground_height(origin)
	# End the warning lane where the body can no longer travel. Horde still
	# performs the actual constraint; it may stop sooner, never tunnel through.
	for n in range(1, ceili(_ram_length / 0.2) + 1):
		var distance := minf(n * 0.2, _ram_length)
		var point := origin + _ram_direction * distance
		var height := _horde.ground_height(point)
		if _horde.is_blocked(point, radius) or height > previous_height + 0.45:
			_ram_length = maxf(0.0, distance - 0.2)
			break
		previous_height = height
	_build_lane()
	_lane.show()
	_enter(State.RAM_WINDUP, ram_warning_time)
	_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.WINDUP)
	_warn(ram_warning_sound, &"zap_warn", _ram_origin)

func _lock_mortar() -> void:
	_next_ram = true
	_impact_count = 0
	var boss_at := _horde.enemy_position(_boss)
	var target := _player.global_position
	var to := Vector2(target.x - boss_at.x, target.z - boss_at.z)
	_ram_direction = to.normalized() if to.length_squared() > 0.01 else Vector2.UP
	var side := Vector2(-_ram_direction.y, _ram_direction.x)
	for n in 3:
		var offset := side * (float(n - 1) * mortar_radius * 1.55)
		var point := Vector2(target.x, target.z) + offset
		_mortar_points[n] = Vector3(point.x, _horde.ground_height(point), point.y)
		_mortar_footprints[n] = _build_circle(_circles[n].mesh as ArrayMesh, _mortar_points[n])
		_circles[n].show()
	_enter(State.MORTAR_WINDUP, mortar_warning_time)
	_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.WINDUP)
	_warn(mortar_warning_sound, &"mine_trigger", target)

func _recover() -> void:
	_lane.hide()
	for circle in _circles:
		circle.hide()
	_warning_voice.stop()
	_horde.drive_boss(Vector2.ZERO, _ram_direction, Horde.Mode.SEEK)
	_horde.set_boss_recovery(true)
	_core.global_position = _horde.weak_spot_position(_boss)
	_core.show()
	_enter(State.RECOVERY, recovery_time)

func _ram_direct_hit(from: Vector3, to: Vector3) -> void:
	if _ram_hit:
		return
	var player_at := _player.global_position
	var point := Vector2(player_at.x, player_at.z)
	var start := Vector2(from.x, from.z)
	var end := Vector2(to.x, to.z)
	var step := end - start
	var nearest := start + step * clampf((point - start).dot(step) / maxf(step.length_squared(), 0.0001), 0.0, 1.0)
	var lock_offset := point - Vector2(_ram_origin.x, _ram_origin.z)
	var forward := lock_offset.dot(_ram_direction)
	var side := absf(lock_offset.cross(_ram_direction))
	if forward < 0.0 or forward > _ram_length + _ram_half_width or side > _ram_half_width or point.distance_to(nearest) > _ram_half_width:
		return
	var definition := _horde.get_definition(_boss)
	var boss_feet := to.y - definition.height * 0.5
	var player_feet := player_at.y - 0.9
	if player_feet > boss_feet + definition.height or player_feet < boss_feet - 1.0 or not _clear_cover(Vector3(nearest.x, boss_feet + 0.9, nearest.y), player_at):
		return
	_ram_hit = true
	_player.take_damage(ram_damage)
	_player.add_shake(0.35)
	_impact_voice.global_position = to
	_impact_voice.stream = impact_sound if impact_sound != null else HazardSynth.make(&"mine_boom")
	_impact_voice.play()

func _impact(index: int) -> void:
	if state != State.MORTAR or not _player.active:
		return
	_impact_count = index + 1
	var center := _mortar_points[index]
	_circles[index].hide()
	# Reuse the exact warned footprint, a low floor shock (not a camera sphere).
	_shocks[index].show()
	_shock_age[index] = 0.0
	(_shocks[index].material_override as StandardMaterial3D).albedo_color.a = 1.0
	_impact_voice.global_position = center
	_impact_voice.stream = impact_sound if impact_sound != null else HazardSynth.make(&"mine_boom")
	_impact_voice.play()
	var at := _player.global_position
	if _inside_footprint(index, Vector2(at.x, at.z)) and absf(at.y - 0.9 - center.y) <= blast_height_tolerance and _clear_cover(center + Vector3.UP * 0.9, at):
		_player.take_damage(mortar_damage)
		_player.add_shake(0.3)

func _clear_cover(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.0001:
		return true
	_cover_query.from = from
	_cover_query.to = to
	return _player.get_world_3d().direct_space_state.intersect_ray(_cover_query).is_empty()

func _build_lane() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var start := Vector2(_ram_origin.x, _ram_origin.z)
	var side := Vector2(-_ram_direction.y, _ram_direction.x)
	var segments := maxi(1, ceili((_ram_length + _ram_half_width) / 0.35))
	for n in segments:
		var a := start + _ram_direction * (float(n) / segments * (_ram_length + _ram_half_width))
		var b := start + _ram_direction * (float(n + 1) / segments * (_ram_length + _ram_half_width))
		_quad(vertices, colors, _floor(a - side * _ram_half_width), _floor(a + side * _ram_half_width), _floor(b + side * _ram_half_width), _floor(b - side * _ram_half_width), Color(1, 0.4, 0.045, 0.28))
		# Solid borders distinguish the locked forward lane.
		for edge_index in 2:
			var sign_value := -1.0 if edge_index == 0 else 1.0
			var edge := side * _ram_half_width * sign_value
			_quad(vertices, colors, _floor(a + edge), _floor(a + edge - side * 0.09 * sign_value), _floor(b + edge - side * 0.09 * sign_value), _floor(b + edge), Color(1, 0.12, 0.02, 0.95))
	for n in range(1, ceili(_ram_length / 3.0)):
		var arrow := start + _ram_direction * (n * 3.0)
		vertices.append(_floor(arrow - side * 0.65))
		vertices.append(_floor(arrow + side * 0.65))
		vertices.append(_floor(arrow + _ram_direction * 0.75))
		for vertex in 3:
			colors.append(Color(1.0, 0.68, 0.12, 0.95))
	_write_mesh(_lane.mesh as ArrayMesh, vertices, colors)

func _build_circle(mesh: ArrayMesh, center: Vector3) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var origin := Vector2(center.x, center.z)
	# Adjacent cells share corners: query each cover/height sample only once.
	var stride := CIRCLE_SEGMENTS + 1
	var center_point := _floor(origin)
	var center_visible := int(_marked_point(center, center_point))
	for ring in CIRCLE_RINGS + 1:
		var distance := mortar_radius * float(ring) / CIRCLE_RINGS
		for segment in stride:
			var index := ring * stride + segment
			var point := center_point if ring == 0 else _floor(origin + Vector2.from_angle(float(segment) / CIRCLE_SEGMENTS * TAU) * distance)
			_circle_samples[index] = point
			_circle_visible[index] = center_visible if ring == 0 else int(_marked_point(center, point))
	for ring in CIRCLE_RINGS:
		for segment in CIRCLE_SEGMENTS:
			var inner := ring * stride + segment
			var outer := inner + stride
			var a := _circle_samples[inner]
			var b := _circle_samples[inner + 1]
			var c := _circle_samples[outer + 1]
			var d := _circle_samples[outer]
			# Conservatively clip cells to cover and deck boundaries. Damage is
			# also restricted to the retained triangles, never an invisible gap.
			if _circle_visible[inner] == 0 or _circle_visible[inner + 1] == 0 or _circle_visible[outer + 1] == 0 or _circle_visible[outer] == 0:
				continue
			_quad(vertices, colors, a, b, c, d, Color(1, 0.24, 0.015, 0.85 if ring == CIRCLE_RINGS - 1 else 0.25))
	_write_mesh(mesh, vertices, colors)
	return vertices

func _marked_point(center: Vector3, point: Vector3) -> bool:
	return absf(point.y - MARK_HEIGHT - center.y) <= blast_height_tolerance and _clear_cover(center + Vector3.UP * 0.9, point + Vector3.UP * (0.9 - MARK_HEIGHT))

func _inside_footprint(index: int, point: Vector2) -> bool:
	var vertices := _mortar_footprints[index]
	for n in range(0, vertices.size(), 3):
		var a := Vector2(vertices[n].x, vertices[n].z)
		var b := Vector2(vertices[n + 1].x, vertices[n + 1].z)
		var c := Vector2(vertices[n + 2].x, vertices[n + 2].z)
		if absf((b - a).cross(c - a)) < 0.00001:
			continue
		var ab := (b - a).cross(point - a)
		var bc := (c - b).cross(point - b)
		var ca := (a - c).cross(point - c)
		if (ab >= -0.00001 and bc >= -0.00001 and ca >= -0.00001) or (ab <= 0.00001 and bc <= 0.00001 and ca <= 0.00001):
			return true
	return false

func _floor(point: Vector2) -> Vector3:
	return Vector3(point.x, _horde.ground_height(point) + MARK_HEIGHT, point.y)

func _quad(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	vertices.append(a)
	vertices.append(c)
	vertices.append(d)
	for n in 6:
		colors.append(color)

func _write_mesh(mesh: ArrayMesh, vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	mesh.clear_surfaces()
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _tick_shocks(delta: float) -> void:
	for n in 3:
		if _shock_age[n] >= SHOCK_TIME:
			continue
		_shock_age[n] += delta
		var material := _shocks[n].material_override as StandardMaterial3D
		material.albedo_color.a = maxf(0.0, 1.0 - _shock_age[n] / SHOCK_TIME)
		if _shock_age[n] >= SHOCK_TIME:
			_shocks[n].hide()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.no_depth_test = false
	return material

func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	instance.hide()
	return instance

func _voice(volume: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.bus = &"SFX"
	voice.volume_db = volume
	voice.unit_size = 12.0
	voice.max_distance = 80.0
	voice.max_polyphony = 3
	add_child(voice)
	return voice

func _warn(stream: AudioStream, fallback: StringName, at: Vector3) -> void:
	_warning_voice.global_position = at
	_warning_voice.stream = stream if stream != null else HazardSynth.make(fallback)
	_warning_voice.play()
