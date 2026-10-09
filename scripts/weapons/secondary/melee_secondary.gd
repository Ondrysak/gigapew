extends SecondaryFire

## Charging is free; only the actor completing its actual impact spends meter.
enum Mode { SHOCK, CLEAVE }
@export var mode := Mode.SHOCK
@export var charge_time := 0.45
var _holding := false
var _charge := 0.0
var _pending := false
var _pulse: MeshInstance3D
var _pulse_left := 0.0
var _discharge_audio: AudioStreamPlayer

func setup(p_player: ArenaPlayer, p_horde: Horde, p_run_state: RunState, p_hand: int, p_view: WeaponView, p_definition: WeaponDefinition) -> void:
	super.setup(p_player, p_horde, p_run_state, p_hand, p_view, p_definition)
	if mode == Mode.SHOCK:
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.9
		mesh.outer_radius = 1.0
		mesh.rings = 24
		mesh.ring_segments = 6
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.12, 0.85, 1.0, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission = Color(0.12, 0.85, 1.0)
		_pulse = MeshInstance3D.new()
		_pulse.mesh = mesh
		_pulse.material_override = material
		_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_pulse)
		_pulse.top_level = true
		_pulse.hide()
		_discharge_audio = AudioStreamPlayer.new()
		_discharge_audio.stream = SynthCue.make(&"shock_discharge")
		_discharge_audio.bus = &"SFX"
		_discharge_audio.volume_db = -13.0
		add_child(_discharge_audio)

func is_active() -> bool:
	return _holding or _pending

func charge_progress() -> float:
	return clampf(_charge / charge_time, 0.0, 1.0) if _holding else 0.0

func press() -> bool:
	if not is_ready() or is_active() or player.melee_busy():
		return false
	_holding = true
	_charge = 0.0
	return true

func release() -> void:
	if not _holding:
		return
	_holding = false
	view.melee_charge(0.0)
	if _charge < charge_time or player.secondary_charge[hand] < charge_cost:
		_charge = 0.0
		return
	if mode == Mode.SHOCK:
		_pending = player.begin_melee_secondary(hand, 0.12, 5.0, 110.0, 2.2, 3.5, 1.2, DamageType.Kind.SHOCK)
	else:
		_pending = player.begin_melee_secondary(hand, 0.22, definition.range_meters + 1.0, minf(180.0, definition.melee_arc_degrees + 35.0), 3.0, 3.0, 0.35, definition.damage_type)
	_charge = 0.0

## Called by ArenaPlayer when the collected sweep contacts are ready to land.
func commit_swing() -> void:
	_release_shot()
	if _pulse != null:
		_pulse_left = 0.2
		_pulse.global_position = player.camera.global_position - player.head.global_basis.z * 2.5
		_pulse.global_basis = player.head.global_basis * Basis(Vector3.RIGHT, PI * 0.5)
		_pulse.show()
		_discharge_audio.play()

func finish_swing() -> void:
	_pending = false

func cancel() -> void:
	_holding = false
	_pending = false
	_charge = 0.0
	_pulse_left = 0.0
	if view != null:
		view.cancel_melee()
	if _pulse != null:
		_pulse.hide()

func _physics_process(delta: float) -> void:
	if player == null or not player.active or player.selected_weapon != hand or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		cancel()
		return
	if _holding:
		_charge = minf(charge_time, _charge + delta)
		view.melee_charge(charge_progress())
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
		_pulse.scale = Vector3.ONE * lerpf(0.2, 2.0, 1.0 - _pulse_left / 0.2)
		_pulse.visible = _pulse_left > 0.0
