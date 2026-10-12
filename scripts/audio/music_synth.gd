class_name MusicSynth
extends RefCounted
## Band-limited wavetable voices, drums and loop-aware effects for the procedural soundtrack.
## Voices add into mono float buffers and wrap writes past the end back to the start, so tails
## of the last bar ring into the first and every stem loops seamlessly. Build one instance per
## render thread: the constructor fills its own tables, so no state is shared between threads.

## Set true to make every in-flight render return early (the game is quitting).
static var cancelled := false

const RATE := 22050
const TABLE_SIZE := 2048
const TABLE_MASK := TABLE_SIZE - 1
const NOISE_MASK := 65535
## Partial counts of the wavetable bands, richest first.
const BAND_HARMONICS := [64, 32, 16, 8, 4]
## Highest partial frequency a band may contain (Nyquist is RATE / 2).
const PARTIAL_LIMIT := 9500.0
## Cubic soft clip: x - x^3 * 4/27 reaches exactly 1.0 at x = 1.5.
const CLIP_CUBE := 0.148148

var sine := PackedFloat32Array()
var saw: Array[PackedFloat32Array] = []
var square: Array[PackedFloat32Array] = []
var noise := PackedFloat32Array()
## Read position in the noise table; moves on after every noisy voice.
var noise_cursor := 0
## Main-thread-loaded samples; renderers only read this shared bank and never duplicate a hit.
var _bank: Dictionary = {}

func _init(seed_value := 1337, bank: Dictionary = {}) -> void:
	_bank = bank
	sine.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		sine[i] = sin(TAU * i / TABLE_SIZE)
	saw = _build_bands(false)
	square = _build_bands(true)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	noise.resize(NOISE_MASK + 1)
	for i in noise.size():
		noise[i] = random.randf_range(-1.0, 1.0)

static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

static func samples(seconds: float) -> int:
	return int(seconds * RATE)

## Zeroed buffer of `length` samples.
static func buffer(length: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(length)
	result.fill(0.0)
	return result

# --- Pitched voices -----------------------------------------------------------------------------

## Two detuned saws with a linear attack/release. `glide` multiplies the pitch every second.
func pad_note(buf: PackedFloat32Array, start: int, length: int, midi: float, gain: float, attack: int, release: int, detune_cents := 10.0, glide := 1.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var freq := hz(midi)
	var table: PackedFloat32Array = saw[_band(freq * 1.03)]
	var spread := pow(2.0, detune_cents / 1200.0)
	var inc_a := freq * spread * TABLE_SIZE / RATE
	var inc_b := freq / spread * TABLE_SIZE / RATE
	var glide_step := pow(glide, 1.0 / RATE)
	var size := float(TABLE_SIZE)
	var phase_a := float((start * 7) & TABLE_MASK)
	var phase_b := float((start * 13 + 700) & TABLE_MASK)
	var attack_inv := 1.0 / maxi(attack, 1)
	var release_inv := 1.0 / maxi(release, 1)
	var total := mini(length + release, n)
	var j := start % n
	for i in total:
		var env := gain
		if i < attack:
			env = gain * i * attack_inv
		elif i >= length:
			env = gain * (1.0 - (i - length) * release_inv)
		phase_a += inc_a
		if phase_a >= size:
			phase_a -= size
		phase_b += inc_b
		if phase_b >= size:
			phase_b -= size
		buf[j] += (table[int(phase_a)] + table[int(phase_b)]) * env
		inc_a *= glide_step
		inc_b *= glide_step
		j += 1
		if j == n:
			j = 0

## Detuned saw pair covering the whole buffer, tuned to whole cycles per loop so it has no seam.
func drone(buf: PackedFloat32Array, midi: float, gain: float, detune_cents := 8.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var freq := hz(midi)
	var table: PackedFloat32Array = saw[_band(freq * 1.03)]
	var spread := pow(2.0, detune_cents / 1200.0)
	var inc_a := roundf(freq * spread * n / RATE) * TABLE_SIZE / n
	var inc_b := roundf(freq / spread * n / RATE) * TABLE_SIZE / n
	var size := float(TABLE_SIZE)
	var phase_a := 0.0
	var phase_b := 900.0
	for i in n:
		phase_a += inc_a
		if phase_a >= size:
			phase_a -= size
		phase_b += inc_b
		if phase_b >= size:
			phase_b -= size
		buf[i] += (table[int(phase_a)] + table[int(phase_b)]) * gain

## Pure sine with a linear attack/release (sub bass, swells).
func sine_note(buf: PackedFloat32Array, start: int, length: int, freq: float, gain: float, attack: int, release: int) -> void:
	if cancelled:
		return
	var n := buf.size()
	var inc := freq * TABLE_SIZE / RATE
	var size := float(TABLE_SIZE)
	var phase := 0.0
	var attack_inv := 1.0 / maxi(attack, 1)
	var release_inv := 1.0 / maxi(release, 1)
	var total := mini(length + release, n)
	var j := start % n
	for i in total:
		var env := gain
		if i < attack:
			env = gain * i * attack_inv
		elif i >= length:
			env = gain * (1.0 - (i - length) * release_inv)
		phase += inc
		if phase >= size:
			phase -= size
		buf[j] += sine[int(phase)] * env
		j += 1
		if j == n:
			j = 0

## Saw/square bass through a resonant low-pass whose cutoff falls from cutoff_high toward
## cutoff_low at `cutoff_decay` per second, then soft-clipped by `drive`.
func bass_note(buf: PackedFloat32Array, start: int, length: int, midi: float, gain: float, cutoff_low: float, cutoff_high: float, cutoff_decay: float, resonance: float, drive: float, square_mix: float) -> void:
	if cancelled:
		return
	var n := buf.size()
	var freq := hz(midi)
	var band := _band(freq)
	var saw_table: PackedFloat32Array = saw[band]
	var square_table: PackedFloat32Array = square[band]
	var inc := freq * TABLE_SIZE / RATE
	var size := float(TABLE_SIZE)
	var saw_mix := 1.0 - square_mix
	var damping := 1.0 / maxf(resonance, 0.5)
	var sweep := 1.0
	var sweep_step := exp(-cutoff_decay * 16.0 / RATE)
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	var ic1 := 0.0
	var ic2 := 0.0
	var phase := 0.0
	var release := 90
	var total := mini(length + release, n)
	var j := start % n
	for i in total:
		if (i & 15) == 0:
			var g := tan(PI * minf(cutoff_low + (cutoff_high - cutoff_low) * sweep, 8000.0) / RATE)
			a1 = 1.0 / (1.0 + g * (g + damping))
			a2 = g * a1
			a3 = g * a2
			sweep *= sweep_step
		phase += inc
		if phase >= size:
			phase -= size
		var index := int(phase)
		var v3 := saw_table[index] * saw_mix + square_table[index] * square_mix - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		var y := v2 * drive
		if y > 1.5:
			y = 1.0
		elif y < -1.5:
			y = -1.0
		else:
			y -= y * y * y * CLIP_CUBE
		var env := gain
		if i < 40:
			env = gain * i * 0.025
		elif i >= length:
			env = gain * (1.0 - float(i - length) / release)
		buf[j] += y * env
		j += 1
		if j == n:
			j = 0

## Plucked saw/square blend: exponential decay through a closing one-pole low-pass that starts
## at `brightness` times the fundamental above it.
func pluck(buf: PackedFloat32Array, start: int, length: int, midi: float, gain: float, decay: float, brightness: float, square_mix := 0.3) -> void:
	if cancelled:
		return
	var n := buf.size()
	var freq := hz(midi)
	var band := _band(freq)
	var saw_table: PackedFloat32Array = saw[band]
	var square_table: PackedFloat32Array = square[band]
	var saw_mix := 1.0 - square_mix
	var inc := freq * TABLE_SIZE / RATE
	var size := float(TABLE_SIZE)
	var amp := gain
	var amp_step := exp(-decay / RATE)
	var tone := 1.0
	var tone_step := exp(-decay * 1.6 * 16.0 / RATE)
	var coef := 0.0
	var low := 0.0
	var phase := float((start * 5) & TABLE_MASK)
	var total := mini(length, n)
	var j := start % n
	for i in total:
		if (i & 15) == 0:
			coef = 1.0 - exp(-TAU * minf(freq * (1.0 + brightness * tone), 9000.0) / RATE)
			tone *= tone_step
		phase += inc
		if phase >= size:
			phase -= size
		var index := int(phase)
		low += (saw_table[index] * saw_mix + square_table[index] * square_mix - low) * coef
		var env := amp
		if i < 24:
			env *= i / 24.0
		var remaining := total - i
		if remaining < 160:
			env *= remaining / 160.0
		buf[j] += low * env
		amp *= amp_step
		j += 1
		if j == n:
			j = 0

## Two detuned saws (optionally blended with square) through a resonant low-pass with delayed
## vibrato; `drive` > 1 adds grit.
func lead_note(buf: PackedFloat32Array, start: int, length: int, midi: float, gain: float, cutoff: float, detune_cents := 7.0, vibrato := 0.004, square_mix := 0.0, drive := 1.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var freq := hz(midi)
	var band := _band(freq * 1.02)
	var saw_table: PackedFloat32Array = saw[band]
	var square_table: PackedFloat32Array = square[band]
	var saw_mix := 1.0 - square_mix
	var spread := pow(2.0, detune_cents / 1200.0)
	var inc_a := freq * spread * TABLE_SIZE / RATE
	var inc_b := freq / spread * TABLE_SIZE / RATE
	var size := float(TABLE_SIZE)
	var g := tan(PI * minf(cutoff, 8000.0) / RATE)
	var damping := 0.7
	var a1 := 1.0 / (1.0 + g * (g + damping))
	var a2 := g * a1
	var a3 := g * a2
	var ic1 := 0.0
	var ic2 := 0.0
	var lfo := 0.0
	var lfo_inc := 5.6 * 16.0 * TABLE_SIZE / RATE
	var vibrato_delay := samples(0.16)
	var vibrato_ramp := 1.0 / samples(0.3)
	var mod := 1.0
	var phase_a := 0.0
	var phase_b := 600.0
	var attack := 180
	var release := samples(0.09)
	var total := mini(length + release, n)
	var j := start % n
	for i in total:
		if (i & 15) == 0 and i > vibrato_delay:
			lfo += lfo_inc
			if lfo >= size:
				lfo -= size
			mod = 1.0 + vibrato * minf(1.0, (i - vibrato_delay) * vibrato_ramp) * sine[int(lfo)]
		phase_a += inc_a * mod
		if phase_a >= size:
			phase_a -= size
		phase_b += inc_b * mod
		if phase_b >= size:
			phase_b -= size
		var index_a := int(phase_a)
		var index_b := int(phase_b)
		var x := (saw_table[index_a] + saw_table[index_b]) * saw_mix + (square_table[index_a] + square_table[index_b]) * square_mix
		var v3 := x * 0.5 - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		var y := v2 * drive
		if y > 1.5:
			y = 1.0
		elif y < -1.5:
			y = -1.0
		else:
			y -= y * y * y * CLIP_CUBE
		var env := gain
		if i < attack:
			env = gain * i / float(attack)
		elif i >= length:
			env = gain * (1.0 - float(i - length) / release)
		buf[j] += y * env
		j += 1
		if j == n:
			j = 0

## Two-operator FM bell: a bright strike that mellows as the modulation index decays.
func bell(buf: PackedFloat32Array, start: int, length: int, midi: float, gain: float, decay: float, ratio := 2.0, index := 2.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var freq := hz(midi)
	var inc := freq * TABLE_SIZE / RATE
	var mod_inc := inc * ratio
	var size := float(TABLE_SIZE)
	var depth := index * TABLE_SIZE / TAU
	var depth_step := exp(-decay * 2.4 / RATE)
	var amp := gain
	var amp_step := exp(-decay / RATE)
	var carrier := 0.0
	var modulator := 0.0
	var total := mini(length, n)
	var j := start % n
	for i in total:
		carrier += inc
		if carrier >= size:
			carrier -= size
		modulator += mod_inc
		if modulator >= size:
			modulator -= size
		var s := sine[int(carrier + depth * sine[int(modulator)]) & TABLE_MASK]
		var env := amp
		if i < 30:
			env *= i / 30.0
		var remaining := total - i
		if remaining < 200:
			env *= remaining / 200.0
		buf[j] += s * env
		amp *= amp_step
		depth *= depth_step
		j += 1
		if j == n:
			j = 0

# --- Sample voices -----------------------------------------------------------------------------

func sample_frames(key: StringName) -> int:
	var source: PackedFloat32Array = _bank[key]
	return source.size()

## Linearly interpolated mono sample, with destination tails wrapping through the loop seam.
## `source_start` is in source samples; `length` is in destination samples (0 = remaining source).
## Source wrapping is for tempo-locked break chops, not one-shots. Edges fade in/out independently
## of either loop boundary, so cut vocals and chopped drums cannot introduce discontinuities.
func sample_hit(buf: PackedFloat32Array, start: int, key: StringName, gain: float, rate := 1.0, source_start := 0, length := 0, loop_source := false, edge := 66) -> void:
	var n := buf.size()
	if cancelled or n == 0 or rate <= 0.0:
		return
	var source: PackedFloat32Array = _bank[key]
	var source_size := source.size()
	if source_size < 2:
		return
	var position := float(posmod(source_start, source_size)) if loop_source else float(maxi(source_start, 0))
	var available := maxi(0, ceili((source_size - position) / rate))
	var total := length if length > 0 else available
	if not loop_source:
		total = mini(total, available)
	total = mini(total, n)
	if total <= 0:
		return
	var fade := mini(maxi(edge, 1), maxi(total / 2, 1))
	var fade_inv := 1.0 / fade
	var j := posmod(start, n)
	for i in total:
		var index := int(position)
		var following := index + 1
		if following == source_size:
			following = 0 if loop_source else index
		var value := lerpf(source[index], source[following], position - index)
		var envelope := minf(1.0, minf(i, total - 1 - i) * fade_inv)
		buf[j] += value * gain * envelope
		position += rate
		if position >= source_size:
			if loop_source:
				position = fmod(position, source_size)
			else:
				break
		j += 1
		if j == n:
			j = 0

# --- Drums -------------------------------------------------------------------------------------

## Sine kick sweeping down to `low_hz` with a noise click; `punch` scales sweep and click.
func kick(buf: PackedFloat32Array, start: int, gain: float, punch := 1.0, low_hz := 46.0, decay := 7.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var total := mini(samples(0.45), n)
	var sweep := 125.0 * punch
	var pitch := 1.0
	var pitch_step := exp(-32.0 / RATE)
	var amp := 1.4
	var amp_step := exp(-decay / RATE)
	var to_table := float(TABLE_SIZE) / RATE
	var phase := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		phase += (low_hz + sweep * pitch) * to_table
		pitch *= pitch_step
		var s := sine[int(phase) & TABLE_MASK] * amp
		if i < 90:
			s += noise[(cursor + i) & NOISE_MASK] * (1.0 - i / 90.0) * 0.4 * punch
		if s > 1.5:
			s = 1.0
		elif s < -1.5:
			s = -1.0
		else:
			s -= s * s * s * CLIP_CUBE
		var remaining := total - i
		if remaining < 400:
			s *= remaining / 400.0
		buf[j] += s * gain
		amp *= amp_step
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

## Tuned body plus filtered noise; `tail` adds the hard-gated 80s reverb tail.
func snare(buf: PackedFloat32Array, start: int, gain: float, tail := 0.0, tone_hz := 185.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var gate := samples(0.12 + tail * 0.2)
	var gate_fade := 500
	var total := mini(gate + gate_fade, n)
	var to_table := float(TABLE_SIZE) / RATE
	var body_a := 0.0
	var body_b := 0.0
	var body_amp := 0.8
	var body_step := exp(-30.0 / RATE)
	var noise_amp := 0.9
	var noise_step := exp(-18.0 / RATE)
	var tail_amp := 0.45 * tail
	var tail_step := exp(-4.0 / RATE)
	var high_cut := 1.0 - exp(-TAU * 900.0 / RATE)
	var top_cut := 1.0 - exp(-TAU * 7000.0 / RATE)
	var low := 0.0
	var top := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		body_a += tone_hz * to_table
		body_b += tone_hz * 1.78 * to_table
		var x := noise[(cursor + i) & NOISE_MASK]
		low += (x - low) * high_cut
		top += (x - low - top) * top_cut
		var s := (sine[int(body_a) & TABLE_MASK] + sine[int(body_b) & TABLE_MASK] * 0.5) * body_amp
		s += top * (noise_amp + tail_amp)
		if i >= gate:
			s *= 1.0 - float(i - gate) / gate_fade
		buf[j] += s * gain
		body_amp *= body_step
		noise_amp *= noise_step
		tail_amp *= tail_step
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

## High-passed noise hat; low `decay` with a longer `length_s` makes an open hat.
func hat(buf: PackedFloat32Array, start: int, gain: float, decay := 60.0, length_s := 0.07) -> void:
	if cancelled:
		return
	var n := buf.size()
	var total := mini(samples(length_s), n)
	var amp := gain
	var amp_step := exp(-decay / RATE)
	var cut := 1.0 - exp(-TAU * 6500.0 / RATE)
	var low := 0.0
	var low2 := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		var x := noise[(cursor + i) & NOISE_MASK]
		low += (x - low) * cut
		var high := x - low
		low2 += (high - low2) * cut
		var s := (high - low2 * 0.5) * amp
		var remaining := total - i
		if remaining < 100:
			s *= remaining / 100.0
		buf[j] += s
		amp *= amp_step
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

## Three quick band-passed noise bursts and a short tail.
func clap(buf: PackedFloat32Array, start: int, gain: float) -> void:
	if cancelled:
		return
	var n := buf.size()
	var total := mini(samples(0.3), n)
	var spacing := 220
	var burst := 1.0
	var burst_step := exp(-190.0 / RATE)
	var tail := 0.7
	var tail_step := exp(-15.0 / RATE)
	var g := tan(PI * 1200.0 / RATE)
	var damping := 0.8
	var a1 := 1.0 / (1.0 + g * (g + damping))
	var a2 := g * a1
	var a3 := g * a2
	var ic1 := 0.0
	var ic2 := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		var env := 0.0
		if i < spacing * 3:
			if i % spacing == 0:
				burst = 1.0
			env = burst
			burst *= burst_step
		else:
			env = tail
			tail *= tail_step
		var v3 := noise[(cursor + i) & NOISE_MASK] * env - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		var s := v1 * 2.0
		var remaining := total - i
		if remaining < 200:
			s *= remaining / 200.0
		buf[j] += s * gain
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

## Sine tom sweeping from hz_start to hz_end; long, low settings make a sub boom.
func tom(buf: PackedFloat32Array, start: int, gain: float, hz_start := 140.0, hz_end := 80.0, decay := 9.0, length_s := 0.5) -> void:
	if cancelled:
		return
	var n := buf.size()
	var total := mini(samples(length_s), n)
	var pitch := 1.0
	var pitch_step := exp(-18.0 / RATE)
	var amp := 1.3
	var amp_step := exp(-decay / RATE)
	var to_table := float(TABLE_SIZE) / RATE
	var phase := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		phase += (hz_end + (hz_start - hz_end) * pitch) * to_table
		pitch *= pitch_step
		var s := sine[int(phase) & TABLE_MASK] * amp
		if i < 150:
			s += noise[(cursor + i) & NOISE_MASK] * (1.0 - i / 150.0) * 0.3
		if s > 1.5:
			s = 1.0
		elif s < -1.5:
			s = -1.0
		else:
			s -= s * s * s * CLIP_CUBE
		var remaining := total - i
		if remaining < 400:
			s *= remaining / 400.0
		buf[j] += s * gain
		amp *= amp_step
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

## Long high-passed noise wash (crash/ride).
func cymbal(buf: PackedFloat32Array, start: int, gain: float, decay := 2.5, length_s := 1.6) -> void:
	if cancelled:
		return
	var n := buf.size()
	var total := mini(samples(length_s), n)
	var amp := gain
	var amp_step := exp(-decay / RATE)
	var cut := 1.0 - exp(-TAU * 4200.0 / RATE)
	var low := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		var x := noise[(cursor + i) & NOISE_MASK]
		low += (x - low) * cut
		var s := (x - low) * amp
		if i < 60:
			s *= i / 60.0
		var remaining := total - i
		if remaining < 2000:
			s *= remaining / 2000.0
		buf[j] += s
		amp *= amp_step
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

## Noise swell whose low-pass opens from low_hz to high_hz as it grows, ending at start + length.
func riser(buf: PackedFloat32Array, start: int, length: int, gain: float, low_hz := 250.0, high_hz := 7000.0) -> void:
	if cancelled:
		return
	var n := buf.size()
	var total := mini(length, n)
	var ratio := high_hz / low_hz
	var coef := 0.0
	var low := 0.0
	var low2 := 0.0
	var cursor := noise_cursor
	var j := start % n
	for i in total:
		var progress := float(i) / total
		if (i & 31) == 0:
			coef = 1.0 - exp(-TAU * low_hz * pow(ratio, progress) / RATE)
		low += (noise[(cursor + i) & NOISE_MASK] - low) * coef
		low2 += (low - low2) * coef
		var s := low2 * progress * progress * gain * 2.0
		var remaining := total - i
		if remaining < 150:
			s *= remaining / 150.0
		buf[j] += s
		j += 1
		if j == n:
			j = 0
	noise_cursor += total

# --- Whole-buffer processing -------------------------------------------------------------------

## Two-pole low-pass whose cutoff swings by `swing` Hz over `cycles` sine periods per buffer.
## Whole cycles keep the loop seamless; the filter is primed on the buffer tail.
func sweep_lowpass(buf: PackedFloat32Array, cutoff: float, swing: float, cycles: float) -> void:
	if cancelled:
		return
	var n := buf.size()
	var coef := 1.0 - exp(-TAU * maxf(cutoff + swing * sin(TAU * cycles * (n - 1) / n), 40.0) / RATE)
	var low := 0.0
	var low2 := 0.0
	for i in range(maxi(n - 4096, 0), n):
		low += (buf[i] - low) * coef
		low2 += (low - low2) * coef
	for i in n:
		if (i & 31) == 0:
			coef = 1.0 - exp(-TAU * maxf(cutoff + swing * sin(TAU * cycles * i / n), 40.0) / RATE)
		low += (buf[i] - low) * coef
		low2 += (low - low2) * coef
		buf[i] = low2

## Sidechain-style ducking: gain dips to 1 - depth at the start of every `period` samples and
## recovers over `recover` of the period.
func pump(buf: PackedFloat32Array, period: int, depth: float, recover := 0.6) -> void:
	if cancelled:
		return
	var curve := PackedFloat32Array()
	curve.resize(period)
	var span := maxf(recover * period, 1.0)
	for k in period:
		var x := minf(k / span, 1.0)
		var duck := depth * (1.0 - x) * (1.0 - x)
		if k < 60:
			duck *= k / 60.0
		curve[k] = 1.0 - duck
	var phase := 0
	for i in buf.size():
		buf[i] *= curve[phase]
		phase += 1
		if phase == period:
			phase = 0

## Damped feedback echo that wraps around the loop, so repeats of the last bar land in the first.
func echo(buf: PackedFloat32Array, delay: int, feedback: float, wet_gain: float, damp := 0.4) -> void:
	if cancelled:
		return
	var n := buf.size()
	var wet := buffer(n)
	var low := 0.0
	var smooth := 1.0 - damp
	for _pass in 2:
		for i in n:
			var source := i - delay
			if source < 0:
				source += n
			low += (buf[source] + wet[source] * feedback - low) * smooth
			wet[i] = low
	for i in n:
		buf[i] += wet[i] * wet_gain

## Adds `src` scaled by `gain` into `dst` (same length).
func mix(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float) -> void:
	for i in mini(dst.size(), src.size()):
		dst[i] += src[i] * gain

## Keeps the loudest sample at `peak`; disable amplification to preserve stage mixing headroom.
func normalize(buf: PackedFloat32Array, peak: float, amplify := true) -> void:
	var top := 0.0
	for i in buf.size():
		top = maxf(top, absf(buf[i]))
	if top <= 0.0 or (not amplify and top <= peak):
		return
	var scale := peak / top if amplify else minf(1.0, peak / top)
	for i in buf.size():
		buf[i] *= scale

## 16-bit mono stream; looping streams loop the whole buffer.
func to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	return stream

# --- Tables ------------------------------------------------------------------------------------

## Index of the richest band whose partials stay under PARTIAL_LIMIT at `freq`.
func _band(freq: float) -> int:
	var allowed := PARTIAL_LIMIT / maxf(freq, 1.0)
	for band in BAND_HARMONICS.size():
		if BAND_HARMONICS[band] <= allowed:
			return band
	return BAND_HARMONICS.size() - 1

## Additive saw (every partial) or square (odd partials) tables, one per band.
func _build_bands(odd_only: bool) -> Array[PackedFloat32Array]:
	var bands: Array[PackedFloat32Array] = []
	bands.resize(BAND_HARMONICS.size())
	var sum := buffer(TABLE_SIZE)
	var scale := 4.0 / PI if odd_only else 2.0 / PI
	for k in range(1, BAND_HARMONICS[0] + 1):
		if not odd_only or k % 2 == 1:
			var amp := scale / k
			for i in TABLE_SIZE:
				sum[i] += amp * sine[(k * i) & TABLE_MASK]
		var band := BAND_HARMONICS.find(k)
		if band >= 0:
			bands[band] = sum.duplicate()
	return bands
