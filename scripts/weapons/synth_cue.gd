class_name SynthCue
extends RefCounted

## Small original synthesized sounds for main guns and class abilities, so the
## project ships without audio files. Streams are built once and cached; assign
## an AudioStream in the owning scene to replace any of them.

const SAMPLE_RATE := 22050

static var _cache: Dictionary = {}

## Returns the cached stream for `cue`, or null for an unknown cue.
static func make(cue: StringName) -> AudioStreamWAV:
	if cue == &"":
		return null
	if _cache.has(cue):
		return _cache[cue]
	var stream := _build(cue)
	_cache[cue] = stream
	return stream

static func _build(cue: StringName) -> AudioStreamWAV:
	var duration := 0.0
	var looped := false
	match cue:
		&"minigun": duration = 0.075
		&"autocannon": duration = 0.46
		&"flame": duration = 0.16
		&"spin":
			duration = 0.5
			looped = true
		&"blink": duration = 0.32
		&"bulwark": duration = 0.8
		&"bulwark_end": duration = 0.3
		&"seismic_throw": duration = 0.22
		&"seismic_boom": duration = 1.1
		&"overdrive": duration = 0.65
		&"overdrive_end": duration = 0.35
		_:
			push_warning("SynthCue: unknown cue %s" % cue)
			return null
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 913
	var phase := 0.0
	var low := 0.0
	var low2 := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var noise := random.randf_range(-1.0, 1.0)
		var sample := 0.0
		match cue:
			&"minigun":
				phase += TAU * lerpf(260.0, 80.0, sqrt(progress)) / SAMPLE_RATE
				sample = sin(phase) * exp(-t * 45.0) * 0.55 + noise * exp(-t * 110.0) * 0.6
			&"autocannon":
				phase += TAU * lerpf(95.0, 26.0, sqrt(progress)) / SAMPLE_RATE
				low += 0.12 * (noise - low)
				sample = sin(phase) * exp(-t * 7.5) * 0.85 + noise * exp(-t * 42.0) * 0.5 + low * exp(-t * 6.0) * 1.4
			&"flame":
				low += 0.18 * (noise - low)
				low2 += 0.05 * (noise - low2)
				sample = (low * 1.3 + low2 * 1.8) * sin(PI * progress) * 0.55
			&"spin":
				# Whole cycles of every partial over 0.5 s keep the loop seamless.
				var hum := sin(TAU * 110.0 * t) + sin(TAU * 220.0 * t) * 0.35 + sin(TAU * 440.0 * t) * 0.12
				low += 0.08 * (noise - low)
				sample = hum * 0.3 + low * 0.35
			&"blink":
				phase += TAU * lerpf(260.0, 1900.0, progress * progress) / SAMPLE_RATE
				low += 0.3 * (noise - low)
				sample = (sin(phase) * 0.45 + low * 0.5) * pow(1.0 - progress, 1.5)
			&"bulwark":
				phase += TAU * 72.0 / SAMPLE_RATE
				var swell := minf(1.0, t * 12.0) * pow(1.0 - progress, 1.2)
				sample = (sin(phase) * 0.6 + sin(phase * 2.01) * 0.3 + sin(phase * 3.02) * 0.12) * swell \
						+ noise * exp(-t * 30.0) * 0.5
			&"bulwark_end":
				phase += TAU * lerpf(420.0, 140.0, progress) / SAMPLE_RATE
				sample = sin(phase) * 0.35 * (1.0 - progress)
			&"seismic_throw":
				low += 0.1 * (noise - low)
				phase += TAU * lerpf(180.0, 420.0, progress) / SAMPLE_RATE
				sample = (low * 1.6 + sin(phase) * 0.15) * sin(PI * progress)
			&"seismic_boom":
				phase += TAU * lerpf(62.0, 20.0, sqrt(progress)) / SAMPLE_RATE
				low += 0.07 * (noise - low)
				low2 += 0.02 * (noise - low2)
				sample = sin(phase) * exp(-t * 3.6) * 0.9 + noise * exp(-t * 28.0) * 0.55 \
						+ (low * 1.4 + low2 * 2.4) * exp(-t * 3.0)
			&"overdrive":
				phase += TAU * lerpf(160.0, 880.0, progress) / SAMPLE_RATE
				var square := 1.0 if sin(phase) >= 0.0 else -1.0
				sample = (square * 0.18 + sin(phase * 2.0) * 0.2) * (0.6 + 0.4 * sin(TAU * 24.0 * t)) * (1.0 - progress * 0.7)
			&"overdrive_end":
				phase += TAU * lerpf(700.0, 160.0, progress) / SAMPLE_RATE
				sample = sin(phase) * 0.3 * (1.0 - progress)
		if not looped:
			# Short fades remove discontinuities at either edge of every cue.
			sample *= minf(1.0, t * 1000.0) * minf(1.0, (duration - t) * 400.0)
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream
