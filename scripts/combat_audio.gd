class_name CombatAudio
extends Node

const SAMPLE_RATE := 22050
const VICTORY_NOTES := [0, 4, 7, 12]

## Supply recorded sounds per cue in the Inspector to replace the default synth.
@export var sound_overrides: Dictionary[StringName, AudioStream] = {}

var _voices: Dictionary = {}

func _ready() -> void:
	# Small original synthesized cues: no downloads or runtime audio streaming.
	for cue in [&"shot", &"scatter", &"rail", &"hit", &"kill", &"hurt", &"jump", &"land", &"victory", &"death"]:
		var voice := AudioStreamPlayer.new()
		voice.stream = sound_overrides[cue] if sound_overrides.get(cue) != null else _make_cue(cue)
		voice.volume_db = -10.0 if cue in [&"shot", &"scatter", &"rail"] else -14.0
		voice.max_polyphony = 3
		add_child(voice)
		_voices[cue] = voice

func play_cue(cue: StringName) -> void:
	var voice: AudioStreamPlayer = _voices[cue]
	voice.play()

func _make_cue(cue: StringName) -> AudioStreamWAV:
	var duration := 0.16
	match cue:
		&"scatter": duration = 0.3
		&"rail": duration = 0.34
		&"hit": duration = 0.075
		&"kill": duration = 0.25
		&"hurt": duration = 0.23
		&"jump": duration = 0.13
		&"land": duration = 0.12
		&"victory": duration = 0.8
		&"death": duration = 0.7
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 481
	var phase := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var noise := random.randf_range(-1.0, 1.0)
		var sample := 0.0
		match cue:
			&"shot":
				phase += TAU * lerpf(175.0, 42.0, sqrt(progress)) / SAMPLE_RATE
				sample = sin(phase) * exp(-t * 23.0) * 0.7 + noise * exp(-t * 65.0) * 0.65
			&"scatter":
				phase += TAU * lerpf(110.0, 30.0, sqrt(progress)) / SAMPLE_RATE
				sample = sin(phase) * exp(-t * 12.0) * 0.72 + noise * exp(-t * 29.0) * 0.55
			&"rail":
				phase += TAU * lerpf(1900.0, 140.0, sqrt(progress)) / SAMPLE_RATE
				sample = (sin(phase) * 0.52 + sin(phase * 1.51) * 0.2) * exp(-t * 10.0) + noise * exp(-t * 100.0) * 0.3
			&"hit":
				sample = (sin(TAU * 1350.0 * t) * 0.55 + noise * 0.25) * exp(-t * 65.0)
			&"kill":
				phase += TAU * lerpf(650.0, 95.0, progress) / SAMPLE_RATE
				sample = (sin(phase) * 0.6 + noise * 0.22) * pow(1.0 - progress, 2.0)
			&"hurt":
				sample = (sin(TAU * 65.0 * t) * 0.7 + noise * 0.3) * exp(-t * 20.0)
			&"jump":
				phase += TAU * lerpf(120.0, 280.0, progress) / SAMPLE_RATE
				sample = sin(phase) * sin(PI * progress) * 0.3
			&"land":
				sample = (sin(TAU * 52.0 * t) * 0.65 + noise * 0.2) * exp(-t * 35.0)
			&"victory":
				var note := mini(3, int(progress * 4.0))
				var frequency := 440.0 * pow(2.0, float(VICTORY_NOTES[note]) / 12.0)
				phase += TAU * frequency / SAMPLE_RATE
				sample = (sin(phase) + sin(phase * 2.0) * 0.2) * 0.4 * sin(PI * fmod(progress * 4.0, 1.0))
			&"death":
				phase += TAU * lerpf(180.0, 38.0, progress) / SAMPLE_RATE
				sample = (sin(phase) * 0.5 + noise * 0.08) * (1.0 - progress)
		# Short fades remove discontinuities at either edge of every cue.
		sample *= minf(1.0, t * 1000.0) * minf(1.0, (duration - t) * 500.0)
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	return stream
