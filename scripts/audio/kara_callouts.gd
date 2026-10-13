class_name KaraCallouts
extends Node

## Event-driven enemy dialogue. One cached positional voice, short cooldowns,
## no network access and no music-side gain/ducking changes.
const EVENTS := {
	&"warning": {"clip": &"delej", "stream": preload("res://assets/audio/kara/delej.mp3"), "quote": "Děléj!", "priority": 1, "cooldown": 8.0},
	&"rush": {"clip": &"delej", "stream": preload("res://assets/audio/kara/delej.mp3"), "quote": "Děléj!", "priority": 1, "cooldown": 8.0},
	&"fire": {"clip": &"ohen", "stream": preload("res://assets/audio/kara/ohen.mp3"), "quote": "Nemáte voheň voe do píči?", "priority": 1, "cooldown": 9.0},
	&"reversed": {"clip": &"co_se_deje", "stream": preload("res://assets/audio/kara/co_se_deje.mp3"), "quote": "Do prdele co se děje?!", "priority": 2, "cooldown": 5.0},
	&"calm": {"clip": &"cas_klidu", "stream": preload("res://assets/audio/kara/cas_klidu.mp3"), "quote": "Je čas klidu.", "priority": 2, "cooldown": 12.0},
}
const AUDIBLE_RANGE := 18.0
const GLOBAL_GAP := 2.5

var speaking: StringName = &""
var last_clip: StringName = &""
var played_count := 0
var _horde: Horde
var _target: ArenaPlayer
var _hud: ArenaHUD
var _voice: AudioStreamPlayer3D
var _ray := PhysicsRayQueryParameters3D.new()
var _cooldowns: Dictionary = {}
var _gap := 0.0
var _priority := -1

func setup(horde: Horde, player: ArenaPlayer, hud: ArenaHUD) -> void:
	_horde = horde
	_target = player
	_hud = hud
	_ray.collision_mask = 1
	_ray.exclude = [player.get_rid()]
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"SFX"
	_voice.volume_db = -8.0
	_voice.unit_size = 6.0
	_voice.max_distance = AUDIBLE_RANGE + 4.0
	_voice.max_polyphony = 1
	_voice.finished.connect(_finished)
	add_child(_voice)
	for event: StringName in EVENTS:
		_cooldowns[event] = 0.0
	horde.enemy_callout.connect(_on_callout)

func _on_callout(index: int, text: String, event: StringName) -> void:
	if not is_instance_valid(_target) or not _target.active or get_tree().paused \
			or index < 0 or index >= Horde.CAPACITY or not EVENTS.has(event):
		return
	var at := _horde.enemy_position(index)
	var origin := _target.camera.global_position
	if origin.distance_squared_to(at) > AUDIBLE_RANGE * AUDIBLE_RANGE:
		return
	_ray.from = origin
	_ray.to = at
	if not _target.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
		return
	var definition := _horde.get_definition(index)
	var played := _play(event, at)
	var quote: String = EVENTS[event].quote if played else ""
	_hud.show_enemy_callout(definition.display_name, text, quote, definition.fx_color)
	match definition.behavior:
		HordeEnemyDefinition.Behavior.BOMBER: _hud.tutor.offer(&"masta_blasta")
		HordeEnemyDefinition.Behavior.AMBUSHER: _hud.tutor.offer(&"tarzan")
		HordeEnemyDefinition.Behavior.SPRAYER: _hud.tutor.offer(&"polejvac")

## Called only on a real completed encounter, never arrival/travel/route menus.
func encounter_cleared() -> void:
	if not is_instance_valid(_target) or not _target.active:
		return
	var at := _target.camera.global_position
	if _play(&"calm", at):
		_hud.show_enemy_callout("", "JE ČAS KLIDU", "", Color(0.78, 0.8, 0.53))

func _play(event: StringName, at: Vector3) -> bool:
	var entry: Dictionary = EVENTS[event]
	var priority := int(entry.priority)
	if float(_cooldowns[event]) > 0.0 or (_gap > 0.0 and priority <= _priority) \
			or (_voice.playing and priority <= _priority):
		return false
	_voice.stop()
	_voice.global_position = at
	_voice.stream = entry.stream
	_voice.play()
	_priority = priority
	_gap = GLOBAL_GAP
	_cooldowns[event] = float(entry.cooldown)
	# Warning and rush share one recording; do not echo it on adjacent transitions.
	if event == &"warning" or event == &"rush":
		_cooldowns[&"warning"] = 8.0
		_cooldowns[&"rush"] = 8.0
	speaking = event
	last_clip = entry.clip
	played_count += 1
	return true

func _finished() -> void:
	speaking = &""

func _process(delta: float) -> void:
	_gap = maxf(0.0, _gap - delta)
	for event: StringName in _cooldowns:
		_cooldowns[event] = maxf(0.0, float(_cooldowns[event]) - delta)
	if is_instance_valid(_target) and not _target.active and _voice.playing:
		_voice.stop()
		_finished()

	if _gap <= 0.0 and not _voice.playing:
		_priority = -1