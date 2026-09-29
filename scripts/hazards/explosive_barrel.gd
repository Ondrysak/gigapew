class_name ExplosiveBarrel
extends Hazard

## Shootable fuel barrel. Enough shot damage lights a short fuse; the blast
## hurts enemies (falling off toward the edge) and the player, sets off other
## barrels in range after a staggered delay, and the barrel respawns later.

const GROUP := &"explosive_barrel"

enum State { READY, FUSING, SPENT, GROWING }

@export var max_health := 20.0
## Fuse after being shot to zero.
@export var fuse_time := 0.12
## Fuse range (seconds) when set off by another barrel's blast.
@export var chain_fuse := Vector2(0.18, 0.34)
## Other barrels whose centres are this close are set off.
@export var chain_radius := 5.5

@export_group("Blast")
@export var horde_damage := 150.0
@export var horde_radius := 5.0
## Share of the damage dealt at the blast edge (linear falloff).
@export var edge_fraction := 0.3
@export var knockback := 12.0
@export var player_damage := 20.0
@export var player_radius := 4.0
@export var player_edge_fraction := 0.25
@export var shake := 0.7
@export var blast_height := 0.6
@export var blast_duration := 0.42
@export var shock_duration := 0.5

@export_group("Respawn")
@export var respawn_time := 25.0
## Respawn waits while the player stands this close.
@export var respawn_clearance := 1.4
@export var respawn_grow_time := 0.6

@export_group("Visuals")
@export var model: Node3D
@export var hitbox: HazardHitbox
@export var hitbox_shape: CollisionShape3D
## Emissive band (StandardMaterial3D override, copied per barrel at setup)
## that flickers when hit or fusing.
@export var glow: GeometryInstance3D
@export var glow_energy := 1.6
## Hidden blast flash authored with radius 1.
@export var blast_template: Node3D
## Hidden floor ring authored with radius 1.
@export var shock_template: Node3D
@export var embers: CPUParticles3D
@export var smoke: CPUParticles3D
## Floor scorch mark shown until the barrel respawns.
@export var scorch: Node3D

@export_group("Sound")
@export var explosion_sound: AudioStream
@export var fuse_sound: AudioStream

var _state := State.READY
var _health := 0.0
var _timer := 0.0
var _flash := 0.0
var _clock := 0.0
var _blasts: AutoFxPool
var _shocks: AutoFxPool
var _boom_voice: AudioStreamPlayer3D
var _fuse_voice: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _glow_material: StandardMaterial3D

func _ready() -> void:
	super()
	add_to_group(GROUP)
	_health = max_health
	hitbox.hit.connect(take_hit)

func _on_setup() -> void:
	_rng.randomize()
	_glow_material = (glow.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	glow.material_override = _glow_material
	_blasts = AutoFxPool.new(self, blast_template, AutoFxPool.Style.BLAST)
	_shocks = AutoFxPool.new(self, shock_template, AutoFxPool.Style.RING)
	_blasts.reserve(1)
	_shocks.reserve(1)
	_boom_voice = make_voice(explosion_sound, &"barrel_boom", 2.0)
	_fuse_voice = make_voice(fuse_sound, &"barrel_fuse", -6.0)

## Player shot on the barrel body.
func take_hit(amount: float, _at: Vector3) -> void:
	if not is_set_up() or _state != State.READY:
		return
	_health -= amount
	_flash = 1.0
	if _health <= 0.0:
		ignite(fuse_time)

## Lights the fuse; the barrel explodes after `delay` seconds.
func ignite(delay: float) -> void:
	if not is_set_up() or _state != State.READY:
		return
	_state = State.FUSING
	_timer = delay
	_fuse_voice.play()

func _tick(delta: float) -> void:
	match _state:
		State.FUSING:
			_timer -= delta
			if _timer <= 0.0:
				_explode()
		State.SPENT:
			_timer -= delta
			if _timer <= 0.0 and player.global_position.distance_squared_to(global_position) > respawn_clearance * respawn_clearance:
				_respawn()

func _explode() -> void:
	_state = State.SPENT
	_timer = respawn_time
	model.hide()
	hitbox_shape.set_deferred(&"disabled", true)
	var center := global_position + Vector3.UP * blast_height
	blast_horde(center, horde_radius, horde_damage, edge_fraction, knockback)
	blast_player(center, player_radius, player_damage, player_edge_fraction, shake)
	_shocks.spawn(global_position + Vector3.UP * 0.05, horde_radius, shock_duration)
	if not crowds_view(center, horde_radius * 0.6):
		_blasts.spawn(center, horde_radius * 0.6, blast_duration)
	embers.restart()
	smoke.restart()
	scorch.show()
	_fuse_voice.stop()
	_boom_voice.play()
	var reach := chain_radius * chain_radius
	for node in get_tree().get_nodes_in_group(GROUP):
		var barrel := node as ExplosiveBarrel
		if barrel != null and barrel != self and barrel.global_position.distance_squared_to(global_position) <= reach:
			barrel.ignite(_rng.randf_range(chain_fuse.x, chain_fuse.y))

func _respawn() -> void:
	_state = State.GROWING
	_timer = respawn_grow_time
	_health = max_health
	scorch.hide()
	model.scale = Vector3.ONE * 0.05
	model.show()
	hitbox_shape.set_deferred(&"disabled", false)

func _animate(delta: float) -> void:
	_clock += delta
	_blasts.update(delta)
	_shocks.update(delta)
	var energy := glow_energy
	var jitter := Vector3.ZERO
	match _state:
		State.FUSING:
			energy = glow_energy * (2.5 + 3.5 * absf(sin(_clock * 38.0)))
			jitter = Vector3(sin(_clock * 91.0), 0.0, cos(_clock * 77.0)) * 0.018
		State.GROWING:
			_timer -= delta
			var grow := clampf(1.0 - _timer / respawn_grow_time, 0.0, 1.0)
			# Ease out with a small overshoot.
			model.scale = Vector3.ONE * maxf(0.05, 1.0 + 0.12 * sin(grow * PI) - pow(1.0 - grow, 3.0))
			if grow >= 1.0:
				model.scale = Vector3.ONE
				_state = State.READY
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		energy += glow_energy * 3.0 * _flash
	model.position = jitter
	_glow_material.emission_energy_multiplier = energy
