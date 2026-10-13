class_name MusicSamples
extends RefCounted

## Decode once before render workers start. Buffers are shared read-only by convention.
const RATE := 22050
## Explicit preloads in the generated catalog also preserve every WAV in exports.
const PACK := preload("res://assets/audio/protokseed/catalog.gd")
const TECHNO := preload("res://assets/audio/techno/catalog.gd")
const VOICES := {
	&"voice_fast": preload("res://assets/voice/ludas/plna_rychlost.wav"),
	&"voice_hrrr": preload("res://assets/voice/ludas/hrrr.wav"),
	&"voice_ijee": preload("res://assets/voice/ludas/ijee_haa.wav"),
	&"voice_aaa": preload("res://assets/voice/ludas/aaa.wav"),
	&"voice_chleba": preload("res://assets/voice/ludas/chleba.wav"),
	&"voice_takhle": preload("res://assets/voice/ludas/takhle.wav"),
}

static var _bank: Dictionary = {}

static func load_bank() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		push_error("MusicSamples.load_bank must run on the main thread before render workers.")
		return {}
	if not _bank.is_empty():
		return _bank
	var decoded: Dictionary = {}
	for key: StringName in PACK.CLIPS.keys() + TECHNO.CLIPS.keys():
		var catalog: Dictionary = TECHNO.CLIPS if TECHNO.CLIPS.has(key) else PACK.CLIPS
		var samples := _decode(catalog[key].stream, key)
		if samples.is_empty():
			return {}
		decoded[key] = samples
	for key: StringName in VOICES:
		var samples := _decode(VOICES[key], key)
		if samples.is_empty():
			return {}
		decoded[key] = samples
	decoded.make_read_only()
	_bank = decoded
	return _bank

static func _decode(stream: AudioStreamWAV, key: StringName) -> PackedFloat32Array:
	if stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo or stream.mix_rate != RATE:
		push_error("Music sample %s must import as uncompressed mono PCM16 at %d Hz." % [key, RATE])
		return PackedFloat32Array()
	var bytes := stream.data
	if bytes.is_empty() or bytes.size() % 2 != 0:
		push_error("Music sample %s has empty or incomplete PCM16 data." % key)
		return PackedFloat32Array()
	var samples := PackedFloat32Array()
	samples.resize(bytes.size() / 2)
	var audible := false
	for frame in samples.size():
		var value := bytes.decode_s16(frame * 2)
		samples[frame] = float(value) / 32768.0
		if value != 0:
			audible = true
	if not audible:
		push_error("Music sample %s contains no audible PCM data." % key)
		return PackedFloat32Array()
	return samples
