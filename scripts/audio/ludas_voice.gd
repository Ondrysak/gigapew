class_name LudasVoice
extends Node

## Luďas's own recorded voice reacting to the run. One line at a time: a more
## important reaction interrupts a lesser one, each reaction waits out its own
## cooldown so frequent events cannot spam, and sequences chain clip by clip
## ("Jaj… krajíc… chleba"). Keeps playing through pauses and the shop.

## priority: higher interrupts lower; cooldown: seconds before the same
## reaction may speak again; clips: one is picked; sequence: played in order.
const LINES := {
	&"arrive": {"priority": 2, "cooldown": 0.0, "clips": [&"ijee_haa"]},
	&"multikill": {"priority": 1, "cooldown": 9.0, "clips": [&"ijee_1", &"ijee_2"]},
	&"combo": {"priority": 2, "cooldown": 5.0, "clips": [&"aaa", &"uuu"]},
	&"skill": {"priority": 3, "cooldown": 0.0, "sequence": [&"jaj", &"krajic", &"chleba"]},
	&"hurt": {"priority": 2, "cooldown": 12.0, "clips": [&"hrrr"]},
	&"heal": {"priority": 1, "cooldown": 15.0, "clips": [&"blp"]},
	&"extraction": {"priority": 3, "cooldown": 0.0, "clips": [&"howl_1", &"howl_2"]},
	&"clear": {"priority": 3, "cooldown": 0.0, "clips": [&"hehehe"]},
	&"death": {"priority": 4, "cooldown": 0.0, "clips": [&"nee_old"]},
}
const CLIP_PATH := "res://assets/voice/ludas/%s.wav"

## Reaction currently speaking, or empty.
var speaking: StringName = &""
## Clip names in the order they started playing; read by checks and tools.
var history: Array[StringName] = []
var _player: AudioStreamPlayer
var _priority := -1
var _queue: Array[StringName] = []
var _cooldowns: Dictionary = {}
var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.bus = &"SFX"
	_player.finished.connect(_play_next)
	add_child(_player)
	for line: Dictionary in LINES.values():
		for clip: StringName in line.get("clips", []) + line.get("sequence", []):
			_streams[clip] = load(CLIP_PATH % clip)

## Speaks a reaction; returns false when it is cooling down or a more
## important line is already playing.
func say(reaction: StringName) -> bool:
	var line: Dictionary = LINES.get(reaction, {})
	if line.is_empty() or float(_cooldowns.get(reaction, 0.0)) > 0.0:
		return false
	if _player.playing and int(line.priority) <= _priority:
		return false
	_cooldowns[reaction] = float(line.cooldown)
	_priority = int(line.priority)
	speaking = reaction
	_queue.clear()
	if line.has("sequence"):
		_queue.assign(line.sequence)
	else:
		var clips: Array = line.clips
		_queue.append(clips[_rng.randi() % clips.size()])
	_player.stop()
	_play_next()
	return true

## Silences the current line, e.g. when a new stage loads.
func stop() -> void:
	_queue.clear()
	_player.stop()
	_priority = -1
	speaking = &""

func _play_next() -> void:
	if _queue.is_empty():
		_priority = -1
		speaking = &""
		return
	var clip: StringName = _queue.pop_front()
	history.append(clip)
	_player.stream = _streams[clip]
	_player.play()

func _process(delta: float) -> void:
	for reaction: StringName in _cooldowns:
		_cooldowns[reaction] = maxf(0.0, float(_cooldowns[reaction]) - delta)
