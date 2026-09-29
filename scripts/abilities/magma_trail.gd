class_name MagmaTrail
extends ActiveAbility

## For `duration` seconds the player leaves burning ground patches behind,
## one every `drop_spacing` metres travelled; each patch scorches enemies
## standing in it until it cools.

@export var duration := 6.0
@export var drop_spacing := 1.4
@export var patch_lifetime := 3.5
@export var patch_radius := 1.8
@export var tick_interval := 0.3
@export var tick_damage := 9.0
## Hidden patch authored at radius 1 (glowing disc + ember ring), pooled.
@export var patch_template: Node3D
@export var patch_count := 24
## Aura visuals parented under this ability (follows the player's feet).
@export var aura: Node3D
@export_group("Sound")
@export var end_sound: AudioStream
@export var synth_end: StringName = &"overdrive_end"

var _remaining := 0.0
var _travelled := 0.0
var _last_position := Vector3.ZERO
var _patches: Array[Node3D] = []
var _patch_age := PackedFloat32Array()
var _patch_tick := PackedFloat32Array()
var _patch_center := PackedVector3Array()
var _next_patch := 0
var _live := 0
var _end_audio: AudioStreamPlayer

func _ready() -> void:
	super()
	_end_audio = make_audio(end_sound, synth_end, -10.0)
	_patches = make_pool(patch_template, patch_count)
	_patch_age.resize(_patches.size())
	_patch_age.fill(-1.0)
	_patch_tick.resize(_patches.size())
	_patch_center.resize(_patches.size())
	if aura != null:
		aura.hide()

func is_burning() -> bool:
	return _remaining > 0.0

func _activate() -> bool:
	_remaining = duration
	_travelled = 0.0
	_last_position = player.global_position
	_drop_patch(_last_position)
	player.add_shake(0.15)
	if aura != null:
		aura.show()
	return true

func _ability_physics(delta: float) -> void:
	if _remaining > 0.0:
		_remaining -= delta
		if _remaining <= 0.0 or not player.active:
			_finish()
			if _end_audio.stream != null:
				_end_audio.play()
		else:
			_track_travel()
	if _live > 0:
		_burn(delta)

func _track_travel() -> void:
	var at := player.global_position
	_travelled += Vector2(at.x - _last_position.x, at.z - _last_position.z).length()
	_last_position = at
	if _travelled >= drop_spacing:
		_drop_patch(at)
		# A dash covers several spacings in one frame; keep one patch per step.
		_travelled = fmod(_travelled, drop_spacing)

func _drop_patch(at: Vector3) -> void:
	if _patches.is_empty():
		return
	var index := _next_patch
	_next_patch = (_next_patch + 1) % _patches.size()
	if _patch_age[index] < 0.0:
		_live += 1
	var center := Vector3(at.x, at.y - 0.85, at.z)
	_patch_age[index] = 0.0
	# First scorch lands on the next tick, not the drop frame.
	_patch_tick[index] = tick_interval * 0.5
	_patch_center[index] = center
	var patch := _patches[index]
	patch.global_position = center
	patch.rotation = Vector3(0.0, randf() * TAU, 0.0)
	patch.scale = Vector3(0.2, 1.0, 0.2)
	patch.show()

func _burn(delta: float) -> void:
	var amount := tick_damage * damage_scale()
	for index in range(_patches.size()):
		var age := _patch_age[index]
		if age < 0.0:
			continue
		age += delta
		if age >= patch_lifetime:
			_patch_age[index] = -1.0
			_patches[index].hide()
			_live -= 1
			continue
		_patch_age[index] = age
		var tick := _patch_tick[index] - delta
		if tick <= 0.0:
			tick += tick_interval
			if horde != null:
				horde.damage_radius(_patch_center[index], patch_radius, amount, 0.0)
		_patch_tick[index] = tick

func _finish() -> void:
	_remaining = 0.0
	if aura != null:
		aura.hide()

func _exit_tree() -> void:
	_finish()
	for index in range(_patches.size()):
		_patch_age[index] = -1.0
		_patches[index].hide()
	_live = 0

func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() * 0.001
	if aura != null and _remaining > 0.0:
		aura.rotation.y = fmod(aura.rotation.y + delta * 2.5, TAU)
		var breathe := 1.0 + sin(time * 9.0) * 0.08
		aura.scale = Vector3(breathe, 1.0, breathe)
		# Flicker through the final second as a warning.
		aura.visible = _remaining >= 1.0 or fmod(_remaining, 0.2) >= 0.08
	if _live <= 0:
		return
	for index in range(_patches.size()):
		var age := _patch_age[index]
		if age < 0.0:
			continue
		var patch := _patches[index]
		var grow := minf(1.0, age / 0.18)
		var fade := clampf((patch_lifetime - age) / (patch_lifetime * 0.35), 0.0, 1.0)
		var pulse := 1.0 + sin(time * 7.0 + float(index) * 1.7) * 0.06
		var radius := patch_radius * (0.2 + 0.8 * grow) * (0.35 + 0.65 * fade) * pulse
		patch.scale = Vector3(radius, maxf(0.05, fade), radius)
		patch.rotation.y = fmod(patch.rotation.y + delta * 0.6, TAU)
