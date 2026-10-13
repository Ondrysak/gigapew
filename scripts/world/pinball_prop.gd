class_name PinballProp
extends RigidBody3D

## Finite kickable beer keg. Builds its own cached mesh and collider; the
## origin is the bottom centre on the floor. A kick arms it: it detonates on
## a hard wall hit, on reaching a live enemy or when its fuse runs out. Enough
## shot damage, or a neighbouring keg's blast, detonates it at once. It
## explodes exactly once, damaging only enemies through
## Horde.damage_radius_action ("KEG").

signal exploded(center: Vector3)

const GROUP := &"pinball_prop"
const RADIUS := 0.36
const HEIGHT := 0.9
const MAX_HEALTH := 25.0
const KICK_SPEED := 13.0
const KICK_LIFT := 3.0
const FUSE := 2.5
const WALL_IMPACT_SPEED := 4.5
const ENEMY_IMPACT_SPEED := 3.0
const BLAST_RADIUS := 4.0
const BLAST_DAMAGE := 120.0
const BLAST_IMPULSE := 14.0
const FLASH_TIME := 0.45
const FLASH_COLOR := Color(1.0, 0.62, 0.18)

static var _mesh: ArrayMesh
static var _shape: CylinderShape3D
static var _blast_mesh: SphereMesh
static var _surface: PhysicsMaterial

var _horde: Horde
var _player: ArenaPlayer
var _health := MAX_HEALTH
var _armed := false
var _spent := false
var _fuse := 0.0
var _impact := false
var _last_velocity := Vector3.ZERO
var _flash := 0.0
var _model: MeshInstance3D
var _collider: CollisionShape3D
var _blast: MeshInstance3D
var _blast_material: StandardMaterial3D
var _hits := PackedInt32Array()

func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 1
	collision_mask = 1
	mass = 30.0
	physics_material_override = _cached_surface()
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	_collider = CollisionShape3D.new()
	_collider.shape = _cached_shape()
	_collider.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(_collider)
	_model = MeshInstance3D.new()
	_model.mesh = _cached_mesh()
	add_child(_model)
	_hits.resize(4)
	sleeping = true
	set_physics_process(false)
	set_process(false)

func setup(horde: Horde, player: ArenaPlayer) -> void:
	_horde = horde
	_player = player

func is_spent() -> bool:
	return _spent

func is_armed() -> bool:
	return _armed

## Kicks the keg along `direction` (flattened) and arms it. False when spent
## or not yet bound to a horde.
func kick(direction: Vector3) -> bool:
	if _spent or not is_instance_valid(_horde):
		return false
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return false
	flat = flat.normalized()
	sleeping = false
	apply_central_impulse((flat * KICK_SPEED + Vector3.UP * KICK_LIFT) * mass)
	apply_torque_impulse(Vector3(flat.z, 0.0, -flat.x) * mass * 0.6)
	_arm(FUSE)
	return true

## Shots (and returned projectiles) on the keg body.
func take_hit(amount: float, _at: Vector3) -> void:
	if _spent or amount <= 0.0:
		return
	_health -= amount
	if _health <= 0.0:
		_explode()

func _arm(fuse: float) -> void:
	_armed = true
	_fuse = fuse
	set_physics_process(true)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _armed and not _spent:
		# Floor landings never count: only side contacts against the travel.
		for n in state.get_contact_count():
			if state.get_contact_collider_object(n) == _player:
				continue
			var normal := state.get_contact_local_normal(n)
			if absf(normal.y) < 0.5 and _last_velocity.dot(-normal) >= WALL_IMPACT_SPEED:
				_impact = true
	_last_velocity = state.linear_velocity

func _physics_process(delta: float) -> void:
	if _spent or not _armed:
		set_physics_process(false)
		return
	_fuse -= delta
	if _impact or _fuse <= 0.0:
		_explode()
		return
	if is_instance_valid(_horde) and linear_velocity.length() >= ENEMY_IMPACT_SPEED \
			and _horde.query_radius(to_global(Vector3.UP * HEIGHT * 0.5), RADIUS + 0.15, _hits) > 0:
		_explode()

func _explode() -> void:
	if _spent:
		return
	_spent = true
	_armed = false
	set_physics_process(false)
	# The rolling body's centre follows its rotation, not world UP. Remove
	# its shootable layer before synchronous blast lane queries: disabling the
	# shape is deferred and the spent keg must not shield enemies from itself.
	var center := to_global(Vector3.UP * HEIGHT * 0.5)
	collision_layer = 0
	_model.hide()
	_collider.set_deferred(&"disabled", true)
	set_deferred(&"freeze", true)
	_show_blast(center)
	if is_instance_valid(_player) and _player.global_position.distance_to(center) < BLAST_RADIUS * 2.5:
		_player.add_shake(0.35)
	exploded.emit(center)
	if is_instance_valid(_horde):
		_horde.damage_radius_action(center, BLAST_RADIUS, BLAST_DAMAGE, "KEG", BLAST_IMPULSE)
	# Neighbouring kegs detonate synchronously in the same transaction, so the
	# originating action (e.g. a DROP shot) owns every chained kill. Each keg is
	# spent before recursing: the chain is finite and never repeats a keg.
	var reach := BLAST_RADIUS * 0.75
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as PinballProp
		if other != null and other != self and not other.is_spent() and other.global_position.distance_to(global_position) <= reach:
			other._explode()

func _show_blast(center: Vector3) -> void:
	if _blast == null:
		_blast_material = StandardMaterial3D.new()
		_blast_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blast_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blast_material.albedo_color = FLASH_COLOR
		_blast = MeshInstance3D.new()
		_blast.mesh = _cached_blast_mesh()
		_blast.material_override = _blast_material
		_blast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blast.top_level = true
		add_child(_blast)
	_blast.global_position = center
	_blast.show()
	_flash = FLASH_TIME
	set_process(true)

func _process(delta: float) -> void:
	_flash -= delta
	if _flash <= 0.0:
		_blast.hide()
		set_process(false)
		return
	var t := 1.0 - _flash / FLASH_TIME
	_blast.scale = Vector3.ONE * lerpf(0.4, BLAST_RADIUS * 0.6, sqrt(t))
	_blast_material.albedo_color.a = 1.0 - t

static func _cached_surface() -> PhysicsMaterial:
	if _surface == null:
		_surface = PhysicsMaterial.new()
		_surface.bounce = 0.35
		_surface.friction = 0.6
	return _surface

static func _cached_shape() -> CylinderShape3D:
	if _shape == null:
		_shape = CylinderShape3D.new()
		_shape.radius = RADIUS
		_shape.height = HEIGHT
	return _shape

static func _cached_blast_mesh() -> SphereMesh:
	if _blast_mesh == null:
		_blast_mesh = SphereMesh.new()
		_blast_mesh.radius = 1.0
		_blast_mesh.height = 2.0
		_blast_mesh.radial_segments = 16
		_blast_mesh.rings = 8
	return _blast_mesh

## Steel keg with a bulged waist, red warning bands and a tap: two surfaces.
static func _cached_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78)
	steel.metallic = 0.85
	steel.roughness = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.85, 0.12, 0.08)
	trim.roughness = 0.5
	var shell := CylinderMesh.new()
	shell.top_radius = 0.31
	shell.bottom_radius = 0.31
	shell.height = 0.86
	shell.radial_segments = 18
	var waist := CylinderMesh.new()
	waist.top_radius = 0.34
	waist.bottom_radius = 0.34
	waist.height = 0.3
	waist.radial_segments = 18
	var band := CylinderMesh.new()
	band.top_radius = RADIUS - 0.005
	band.bottom_radius = RADIUS - 0.005
	band.height = 0.07
	band.radial_segments = 18
	var tap := CylinderMesh.new()
	tap.top_radius = 0.05
	tap.bottom_radius = 0.06
	tap.height = 0.08
	tap.radial_segments = 8
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(shell, 0, Transform3D(Basis(), Vector3(0.0, 0.43, 0.0)))
	tool.append_from(waist, 0, Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)))
	_mesh = tool.commit()
	_mesh.surface_set_material(0, steel)
	tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(band, 0, Transform3D(Basis(), Vector3(0.0, 0.12, 0.0)))
	tool.append_from(band, 0, Transform3D(Basis(), Vector3(0.0, 0.78, 0.0)))
	tool.append_from(tap, 0, Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)))
	tool.commit(_mesh)
	_mesh.surface_set_material(1, trim)
	return _mesh
