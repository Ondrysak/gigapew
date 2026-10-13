class_name KickView
extends Node3D

## Cached camera-space leg and hand: strikes never build meshes or tweens.
## The foot pivot stays in front of the near plane even through a full rotation.

enum Kind { KICK, SLIDE, STOMP }

const KICK_TIME := 0.38
const PARRY_TIME := 0.30
const FLASH_TIME := 0.12
const BOOT_RADIUS := 0.60
const HAND_RADIUS := 0.41
const BOOT_REST := Vector3(0.31, -0.72, -0.80)
const BOOT_REST_ANGLE := Vector3(0.18, 0.12, -0.18)
const SLIDE_REST := Vector3(0.29, -0.39, -0.92)
const SLIDE_ANGLE := Vector3(0.30, -0.48, -0.22)
const HAND_REST := Vector3(-0.42, -0.48, -0.58)
const HAND_STRIKE := Vector3(-0.18, -0.12, -0.72)

var _boot := Node3D.new()
var _hand := Node3D.new()
var _brace_hand := Node3D.new()
var _finish_light := OmniLight3D.new()
var _sole_material := StandardMaterial3D.new()
var _palm_material := StandardMaterial3D.new()
var _kind := Kind.KICK
var _connected := false
var _kick_left := 0.0
var _parry_left := 0.0
var _finish_left := 0.0
var _finish_duration := 0.0
var _finish_contact := 0.0
var _sliding := false
var _slide_blend := 0.0
var _boot_clearance := 0.72
var _hand_clearance := 0.53

func _ready() -> void:
	var camera := get_parent() as Camera3D
	if camera != null:
		_boot_clearance = maxf(_boot_clearance, camera.near + BOOT_RADIUS + 0.02)
		_hand_clearance = maxf(_hand_clearance, camera.near + HAND_RADIUS + 0.02)
	var denim := _material(Color(0.13, 0.16, 0.24), 0.9)
	var leather := _material(Color(0.07, 0.06, 0.05), 0.45)
	var laces := _material(Color(0.36, 0.31, 0.24), 0.8)
	_sole_material.albedo_color = Color(0.66, 0.23, 0.07)
	_sole_material.roughness = 0.8
	_sole_material.emission = Color(1.0, 0.55, 0.15)
	_sole_material.emission_energy_multiplier = 0.0
	_sole_material.emission_enabled = true
	# Foot-centred pivot, with the shin reaching back toward the player. Unlike
	# the old hip pivot, no geometry begins behind the camera at windup/rest.
	_add_box(_boot, Vector3(0.16, 0.17, 0.50), Vector3(0.0, 0.08, 0.29), denim)
	_add_box(_boot, Vector3(0.22, 0.18, 0.39), Vector3(0.0, 0.0, -0.09), leather)
	_add_box(_boot, Vector3(0.20, 0.23, 0.16), Vector3(0.0, 0.055, 0.075), leather)
	_add_box(_boot, Vector3(0.24, 0.045, 0.42), Vector3(0.0, -0.115, -0.09), _sole_material)
	for ridge in 4:
		_add_box(_boot, Vector3(0.23, 0.025, 0.035), Vector3(0.0, -0.15, -0.25 + ridge * 0.10), leather)
	for lace in 3:
		_add_box(_boot, Vector3(0.15, 0.015, 0.025), Vector3(0.0, 0.098, -0.12 + lace * 0.055), laces)
	_palm_material.albedo_color = Color(0.86, 0.62, 0.48)
	_palm_material.roughness = 0.7
	_palm_material.emission = Color(0.45, 0.85, 1.0)
	_palm_material.emission_energy_multiplier = 0.0
	_palm_material.emission_enabled = true
	var sleeve := _material(Color(0.2, 0.18, 0.15), 0.85)
	_build_hand(_hand, sleeve)
	_build_hand(_brace_hand, sleeve)
	# Local fill makes the rotating toe, laces and sole readable in dark arenas.
	# Cached once and enabled only for the execution; no screen-space flash.
	_finish_light.position = Vector3(0.0, 0.25, -0.40)
	_finish_light.light_color = Color(1.0, 0.80, 0.60)
	_finish_light.light_energy = 1.2
	_finish_light.omni_range = 2.0
	_finish_light.shadow_enabled = false
	add_child(_boot)
	add_child(_hand)
	add_child(_brace_hand)
	add_child(_finish_light)
	_pose()

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _build_hand(hand: Node3D, sleeve: Material) -> void:
	_add_box(hand, Vector3(0.11, 0.11, 0.32), Vector3(0.0, 0.0, 0.22), sleeve)
	_add_box(hand, Vector3(0.13, 0.035, 0.13), Vector3.ZERO, _palm_material)
	for finger in 4:
		_add_box(hand, Vector3(0.025, 0.025, 0.09), Vector3(-0.045 + finger * 0.03, 0.0, -0.1), _palm_material)
	_add_box(hand, Vector3(0.025, 0.025, 0.07), Vector3(0.075, 0.0, -0.03), _palm_material)

func _add_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

## Repeated slide state updates preserve the current strike and its clock.
## The idle extended leg stays below the crosshair, blending in/out in 0.167s.
func set_sliding(enabled: bool) -> void:
	_sliding = enabled

## Connected kicks plant at contact; misses overextend and sweep past it.
func kick(kind: Kind, connected: bool) -> void:
	if get_tree().paused:
		return
	_kind = kind
	_connected = connected
	_kick_left = KICK_TIME
	_parry_left = 0.0
	_finish_left = 0.0
	_pose()

## A fast open-palm swat, contact hold, then a heavier return below the frame.
func parry() -> void:
	if get_tree().paused:
		return
	_parry_left = PARRY_TIME
	_kick_left = 0.0
	_finish_left = 0.0
	_pose()

## Caller owns gameplay contact. Cached poses brace, tuck, orbit, snap at its
## contact clock, briefly plant, then recover over the remaining duration.
func finish(duration: float, contact: float) -> void:
	if get_tree().paused:
		return
	_finish_duration = maxf(duration, 0.001)
	_finish_contact = clampf(contact, 0.001, _finish_duration)
	_finish_left = _finish_duration
	_kick_left = 0.0
	_parry_left = 0.0
	_pose()

func cancel() -> void:
	_kick_left = 0.0
	_parry_left = 0.0
	_finish_left = 0.0
	_finish_duration = 0.0
	_finish_contact = 0.0
	_connected = false
	_sliding = false
	_slide_blend = 0.0
	_sole_material.emission_energy_multiplier = 0.0
	_palm_material.emission_energy_multiplier = 0.0
	_boot.hide()
	_hand.hide()
	_brace_hand.hide()
	_finish_light.hide()

## Persistent sliding is a pose, not an action/cooldown.
func is_animating() -> bool:
	return _kick_left > 0.0 or _parry_left > 0.0 or _finish_left > 0.0

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if not is_animating() and not _sliding and _slide_blend == 0.0:
		return
	_kick_left = maxf(0.0, _kick_left - delta)
	_parry_left = maxf(0.0, _parry_left - delta)
	_finish_left = maxf(0.0, _finish_left - delta)
	_slide_blend = move_toward(_slide_blend, 1.0 if _sliding else 0.0, delta * 6.0)
	_pose()

func _pose() -> void:
	var slide := _smooth(_slide_blend)
	var boot_rest := BOOT_REST.lerp(SLIDE_REST, slide)
	var boot_angle := BOOT_REST_ANGLE.lerp(SLIDE_ANGLE, slide)
	_boot.visible = _kick_left > 0.0 or _finish_left > 0.0 or _slide_blend > 0.0
	_hand.visible = _parry_left > 0.0 or _finish_left > 0.0
	_brace_hand.visible = _finish_left > 0.0
	_finish_light.visible = _finish_left > 0.0
	_sole_material.emission_energy_multiplier = 0.0
	_palm_material.emission_energy_multiplier = 0.0
	if _finish_left > 0.0:
		_pose_finish(boot_rest, boot_angle)
		return
	if _kick_left > 0.0:
		_pose_kick(boot_rest, boot_angle)
	else:
		_set_boot(boot_rest, boot_angle)
	if _parry_left > 0.0:
		var age := PARRY_TIME - _parry_left
		var reach := _strike_curve(age, 0.04, 0.095, PARRY_TIME)
		_set_hand(HAND_REST.lerp(HAND_STRIKE, reach), Vector3(-0.45 * reach, 0.75 - 1.5 * reach, -0.35 + 0.8 * reach))
		_palm_material.emission_energy_multiplier = _contact_glow(age, 0.04)

func _pose_kick(rest: Vector3, rest_angle: Vector3) -> void:
	var age := KICK_TIME - _kick_left
	var extension := 0.055
	var hold_end := 0.12
	var windup := rest
	var windup_angle := rest_angle
	var strike := Vector3(0.05, -0.25, -0.88)
	var strike_angle := Vector3(1.30, -0.12, -0.08)
	match _kind:
		Kind.SLIDE:
			extension = 0.045
			hold_end = 0.135
			windup = SLIDE_REST
			windup_angle = SLIDE_ANGLE
			strike = Vector3(0.13, -0.32, -1.16)
			strike_angle = Vector3(0.65, -0.40, -0.30)
		Kind.STOMP:
			extension = 0.07
			hold_end = 0.15
			windup = Vector3(-0.08, -0.04, -0.94)
			windup_angle = Vector3(0.15, 0.08, 0.15)
			strike = Vector3(0.02, -0.58, -1.02)
			strike_angle = Vector3(-0.45, 0.12, 0.08)
	if not _connected:
		hold_end = extension + 0.012
		strike.z -= 0.16
		strike.x -= 0.10
		strike_angle.y -= 0.28
		strike_angle.z -= 0.16
	var reach := _strike_curve(age, extension, hold_end, KICK_TIME)
	# A stomp starts lifted, then recovers to the normal/slide resting pose.
	var recovery := _smooth(clampf((age - hold_end) / (KICK_TIME - hold_end), 0.0, 1.0))
	_set_boot(windup.lerp(rest, recovery).lerp(strike, reach), windup_angle.lerp(rest_angle, recovery).lerp(strike_angle, reach))
	if _connected:
		_sole_material.emission_energy_multiplier = _contact_glow(age, extension)

func _pose_finish(rest: Vector3, rest_angle: Vector3) -> void:
	var age := _finish_duration - _finish_left
	var brace_end := _finish_contact * 0.16
	var tuck_end := _finish_contact * 0.36
	var snap_start := _finish_contact * 0.86
	var plant_end := _finish_contact + (_finish_duration - _finish_contact) * 0.24
	var brace := _smooth(clampf(age / brace_end, 0.0, 1.0))
	var release := _smooth(clampf((age - brace_end) / (tuck_end - brace_end), 0.0, 1.0))
	var hand_at := HAND_REST.lerp(Vector3(-0.36, -0.15, -0.84), brace)
	hand_at = hand_at.lerp(Vector3(-0.53, -0.60, -0.76), release)
	var hand_angle := Vector3(-0.65 * brace, 0.25 * brace, -0.40 * brace)
	_set_hand(hand_at, hand_angle)
	hand_at.x = -hand_at.x
	hand_at.z = minf(hand_at.z, -_hand_clearance)
	_brace_hand.position = hand_at
	_brace_hand.rotation = Vector3(hand_angle.x, -hand_angle.y, -hand_angle.z)
	_hand.visible = age < tuck_end
	_brace_hand.visible = age < tuck_end

	var tucked := Vector3(0.396, -0.354, -0.90)
	var tucked_angle := Vector3(-0.65, 0.25, -0.35)
	var orbit_end := Vector3(-0.396, -0.354, -0.90)
	# Keep Euler angles unwrapped: this is a full forward somersault, not the
	# shortest-path interpolation back to the same orientation.
	var orbit_angle := Vector3(TAU + 0.90, -0.25, 0.15)
	var strike := Vector3(0.04, -0.20, -1.08)
	var strike_angle := Vector3(TAU + 1.45, -0.20, 0.04)
	if age < brace_end:
		_set_boot(rest.lerp(Vector3(0.38, -0.59, -0.82), brace), rest_angle.lerp(Vector3(-0.25, 0.20, -0.30), brace))
	elif age < tuck_end:
		var tuck := _smooth((age - brace_end) / (tuck_end - brace_end))
		_set_boot(Vector3(0.38, -0.59, -0.82).lerp(tucked, tuck), Vector3(-0.25, 0.20, -0.30).lerp(tucked_angle, tuck))
	elif age < snap_start:
		var flight := (age - tuck_end) / (snap_start - tuck_end)
		var arc := -PI * 0.25 + PI * 1.5 * flight
		# Orbit around the aim point rather than hiding the target throughout
		# flight. The shin rolls over the toe while the boot crosses the view.
		var at := Vector3(cos(arc) * 0.56, -0.05 + sin(arc) * 0.43, -0.90 - sin(PI * flight) * 0.15)
		var angles := tucked_angle.lerp(orbit_angle, flight)
		angles.z += sin(PI * flight) * 0.80
		_set_boot(at, angles)
	elif age < _finish_contact:
		var snap := (age - snap_start) / (_finish_contact - snap_start)
		snap = 1.0 - pow(1.0 - snap, 3.0)
		_set_boot(orbit_end.lerp(strike, snap), orbit_angle.lerp(strike_angle, snap))
	elif age < plant_end:
		_set_boot(strike, strike_angle)
	else:
		var recover := _smooth(clampf((age - plant_end) / maxf(_finish_duration - plant_end, 0.001), 0.0, 1.0))
		# Preserve the completed revolution during recovery, avoiding a reverse
		# spin. Once hidden, the next ordinary kick sets its own resting angle.
		_set_boot(strike.lerp(rest, recover), strike_angle.lerp(rest_angle + Vector3(TAU, 0.0, 0.0), recover))
	_sole_material.emission_energy_multiplier = 0.18 + _contact_glow(age, _finish_contact)

func _set_boot(at: Vector3, angles: Vector3) -> void:
	at.z = minf(at.z, -_boot_clearance)
	_boot.position = at
	_boot.rotation = angles

func _set_hand(at: Vector3, angles: Vector3) -> void:
	at.z = minf(at.z, -_hand_clearance)
	_hand.position = at
	_hand.rotation = angles

static func _contact_glow(age: float, contact: float) -> float:
	if age < contact:
		return 0.0
	return 4.0 * maxf(0.0, 1.0 - (age - contact) / FLASH_TIME)

static func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

## Cubic snap, deliberate plant, then an initially heavy, eased recovery.
static func _strike_curve(age: float, extension: float, hold_end: float, duration: float) -> float:
	if age < extension:
		var t := clampf(age / extension, 0.0, 1.0)
		return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
	if age < hold_end:
		return 1.0
	return 1.0 - _smooth(clampf((age - hold_end) / (duration - hold_end), 0.0, 1.0))
