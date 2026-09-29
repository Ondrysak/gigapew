class_name HazardSynth
extends RefCounted

## Small original synthesized sounds for stage hazards, built on first use and
## cached. Each hazard scene exports AudioStream overrides that replace them.

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
		&"barrel_boom": duration = 1.3
		&"barrel_fuse": duration = 0.3
		&"mine_arm": duration = 0.22
		&"mine_trigger": duration = 0.3
		&"mine_boom": duration = 0.9
		&"zap_warn": duration = 1.0
		&"zap_live":
			duration = 0.5
			looped = true
		&"console_on": duration = 0.55
		&"console_off": duration = 0.45
		&"console_deny": duration = 0.28
		&"turret_shot": duration = 0.08
		&"flame_ignite": duration = 0.45
		&"flame_roar":
			duration = 0.6
			looped = true
		_:
			push_warning("HazardSynth: unknown cue %s" % cue)
			return null
	var count := int(duration * SAMPLE_RATE)
	# Loops render a little past their end and crossfade that tail into the
	# head, so filtered noise wraps without a click.
	var fade := int(0.05 * SAMPLE_RATE) if looped else 0
	var samples := PackedFloat32Array()
	samples.resize(count + fade)
	var random := RandomNumberGenerator.new()
	random.seed = 2417
	var phase := 0.0
	var low := 0.0
	var low2 := 0.0
	var crackle := 0.0
	for i in count + fade:
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var noise := random.randf_range(-1.0, 1.0)
		var sample := 0.0
		match cue:
			&"barrel_boom":
				phase += TAU * lerpf(70.0, 18.0, sqrt(progress)) / SAMPLE_RATE
				low += 0.09 * (noise - low)
				low2 += 0.018 * (noise - low2)
				sample = sin(phase) * exp(-t * 3.2) * 0.9 + noise * exp(-t * 22.0) * 0.7 \
						+ (low * 1.5 + low2 * 2.8) * exp(-t * 2.4)
			&"barrel_fuse":
				low += 0.4 * (noise - low)
				sample = (noise - low) * 0.5 * minf(1.0, t * 20.0)
			&"mine_arm":
				var note := 880.0 if progress < 0.45 else 1320.0
				phase += TAU * note / SAMPLE_RATE
				sample = sin(phase) * 0.3 * sin(PI * fmod(progress / 0.45, 1.0))
			&"mine_trigger":
				phase += TAU * 1760.0 / SAMPLE_RATE
				sample = sin(phase) * 0.35 * (1.0 if fmod(t, 0.075) < 0.04 else 0.0)
			&"mine_boom":
				phase += TAU * lerpf(95.0, 28.0, sqrt(progress)) / SAMPLE_RATE
				low += 0.12 * (noise - low)
				sample = sin(phase) * exp(-t * 5.0) * 0.8 + noise * exp(-t * 34.0) * 0.65 + low * exp(-t * 4.0) * 1.5
			&"zap_warn":
				# Rising mains hum that pulses faster as the floor charges.
				phase += TAU * lerpf(90.0, 180.0, progress) / SAMPLE_RATE
				var pulse := 0.5 + 0.5 * sin(TAU * lerpf(4.0, 14.0, progress) * t)
				sample = (sin(phase) + sin(phase * 3.0) * 0.3) * 0.22 * pulse * minf(1.0, t * 8.0)
			&"zap_live":
				# 100 Hz buzz (whole cycles over 0.5 s loop) plus random crackles.
				if random.randf() < 0.004:
					crackle = 1.0
				crackle *= 0.995
				var buzz := sin(TAU * 100.0 * t)
				var square := 1.0 if buzz >= 0.0 else -1.0
				sample = square * 0.12 + buzz * 0.1 + noise * crackle * 0.55
			&"console_on":
				phase += TAU * lerpf(180.0, 720.0, progress * progress) / SAMPLE_RATE
				sample = (sin(phase) * 0.35 + sin(phase * 1.5) * 0.15) * sin(PI * progress)
			&"console_off":
				phase += TAU * lerpf(600.0, 110.0, sqrt(progress)) / SAMPLE_RATE
				sample = sin(phase) * 0.32 * (1.0 - progress)
			&"console_deny":
				phase += TAU * 140.0 / SAMPLE_RATE
				var square := 1.0 if sin(phase) >= 0.0 else -1.0
				sample = square * 0.2 * (1.0 if fmod(progress, 0.5) < 0.38 else 0.0)
			&"turret_shot":
				phase += TAU * lerpf(900.0, 160.0, sqrt(progress)) / SAMPLE_RATE
				sample = sin(phase) * exp(-t * 55.0) * 0.5 + noise * exp(-t * 90.0) * 0.5
			&"flame_ignite":
				low += 0.2 * (noise - low)
				low2 += 0.04 * (noise - low2)
				phase += TAU * lerpf(60.0, 35.0, progress) / SAMPLE_RATE
				sample = (low * 1.1 + low2 * 2.0) * minf(1.0, t * 12.0) * (1.0 - progress * 0.6) + sin(phase) * exp(-t * 6.0) * 0.4
			&"flame_roar":
				low += 0.14 * (noise - low)
				low2 += 0.03 * (noise - low2)
				sample = low * 0.9 + low2 * 1.9
		if not looped:
			# Short fades remove discontinuities at either edge of every cue.
			sample *= minf(1.0, t * 1000.0) * minf(1.0, (duration - t) * 400.0)
		samples[i] = sample
	for i in fade:
		var blend := float(i) / float(fade)
		samples[i] = samples[i] * blend + samples[count + i] * (1.0 - blend)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream
