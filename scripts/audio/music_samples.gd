class_name MusicSamples
extends RefCounted

## PCM is decoded once on the main thread before music render workers start.
## The dictionary is read-only; its packed buffers are immutable by convention:
## synths may read them but must never modify samples or duplicate the bank.
const RATE := 22050
## Entire original eight-beat loop, 62259 output frames. See tools/music_samples.py
## for source checksums, measured beat grid, conversion and uncertain licensing.
const BREAK_BPM := 480.0 / (62259.0 / float(RATE))

## Explicit dependencies preserve the imported PCM resources in exported games.
const STREAMS := {
	&"kick": preload("res://assets/audio/protokseed/kick.wav"),
	&"kick_heavy": preload("res://assets/audio/protokseed/kick_heavy.wav"),
	&"break": preload("res://assets/audio/protokseed/break.wav"),
	&"stab": preload("res://assets/audio/protokseed/stab.wav"),
	&"fx": preload("res://assets/audio/protokseed/fx.wav"),
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
	for key: StringName in STREAMS:
		var stream := STREAMS[key] as AudioStreamWAV
		if stream == null:
			push_error("Missing music sample resource: %s" % key)
			return {}
		if stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo or stream.mix_rate != RATE:
			push_error("Music sample %s must import as uncompressed mono PCM16 at %d Hz." % [key, RATE])
			return {}
		var bytes := stream.data
		if bytes.is_empty() or bytes.size() % 2 != 0:
			push_error("Music sample %s has empty or incomplete PCM16 data." % key)
			return {}
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
			return {}
		decoded[key] = samples
	decoded.make_read_only()
	_bank = decoded
	return _bank
