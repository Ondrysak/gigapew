class_name MiningSynth
extends RefCounted

## Default procedural mining sounds. Scenes export AudioStream overrides;
## these only fill the gaps so the project stays asset-free.

const SAMPLE_RATE := 22050

## Seamless drill hum: every partial completes whole cycles per loop.
static func drill_loop() -> AudioStreamWAV:
	var duration := 0.4
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 7331
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var saw := fmod(t * 95.0, 1.0) * 2.0 - 1.0
		var grind := random.randf_range(-1.0, 1.0) * (0.55 + 0.45 * sin(TAU * 30.0 * t))
		var sample := saw * 0.32 + sin(TAU * 190.0 * t) * 0.18 + grind * 0.16
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := _stream(bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

## One-shot cues: &"clank" (bit on rock), &"thud" (bit on enemy),
## &"crunch" (deposit breaks), &"tink" (nugget collected).
## &"section" adds a short rising crystal beat to a drill section break.
static func cue(name: StringName) -> AudioStreamWAV:
	var duration := 0.12
	match name:
		&"clank": duration = 0.13
		&"crunch": duration = 0.5
		&"tink": duration = 0.1
		&"section": duration = 0.24
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 913
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var noise := random.randf_range(-1.0, 1.0)
		var sample := 0.0
		match name:
			&"clank":
				sample = (sin(TAU * 1760.0 * t) * 0.35 + sin(TAU * 2630.0 * t) * 0.22) * exp(-t * 38.0) + noise * exp(-t * 80.0) * 0.5
			&"thud":
				sample = sin(TAU * lerpf(140.0, 60.0, progress) * t) * exp(-t * 30.0) * 0.8 + noise * exp(-t * 60.0) * 0.3
			&"crunch":
				var rumble := sin(TAU * lerpf(120.0, 45.0, progress) * t) * 0.5
				sample = (rumble + noise * 0.55) * exp(-t * 7.0) + sin(TAU * 2200.0 * t) * 0.18 * exp(-t * 18.0)
			&"tink":
				var frequency := lerpf(1320.0, 1760.0, minf(1.0, progress * 3.0))
				sample = (sin(TAU * frequency * t) * 0.5 + sin(TAU * frequency * 2.0 * t) * 0.15) * exp(-t * 32.0)
			&"section":
				var frequency := lerpf(720.0, 1080.0, minf(1.0, progress * 4.0))
				sample = (sin(TAU * frequency * t) * 0.42 + sin(TAU * frequency * 1.5 * t) * 0.2) * exp(-t * 16.0) + noise * exp(-t * 45.0) * 0.15
		# Short fades remove clicks at both edges.
		sample *= minf(1.0, t * 1000.0) * minf(1.0, (duration - t) * 400.0)
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _stream(bytes)

static func _stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	return stream
