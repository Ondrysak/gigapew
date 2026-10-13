class_name MusicScore
extends RefCounted
## Composition of the procedural soundtrack: tempo, harmony, patterns and the arrangement of
## every stem. All stems of a track have the same length and start on the same sample, so the
## director keeps them locked and only automates their volumes.

const STINGER_TRACK := &"stinger"
## Loop stems per track, in render priority order.
const TRACK_STEMS := {
	&"menu": [&"pad", &"motif", &"beat"],
	&"stage": [&"kick", &"clap", &"hat", &"groove", &"bass", &"synth", &"arp", &"ambient"],
	&"boss": [&"drums", &"boss_drive", &"boss_pad", &"perc", &"breaks", &"rave", &"tension", &"vocals"],
}
const STINGERS := [&"level_up", &"stage_clear", &"death", &"run_complete"]
const MENU_BPM := 90.0
const MENU_BARS := 16


# Menu (90 BPM): moody 8-bar harmony played twice, Dm Bb Gm Asus4-A.
const MENU_ROOTS := [38, 34, 31, 33]
const MENU_BAR_CHORDS := [
	[57, 62, 65, 69], [57, 62, 65, 69], [58, 62, 65, 70], [58, 62, 65, 70],
	[55, 62, 67, 70], [55, 62, 67, 70], [57, 62, 64, 69], [57, 61, 64, 69],
]
const MENU_ARP := [0, 1, 2, 3, 2, 1, 2, 1]
## Menu motif: [16th step, length, MIDI] over eight bars.
const MENU_MOTIF := [
	[0, 4, 69], [4, 4, 74], [8, 4, 77], [12, 8, 76], [20, 12, 74],
	[32, 4, 74], [36, 4, 77], [40, 4, 81], [44, 8, 79], [52, 12, 77],
	[64, 4, 74], [68, 4, 79], [72, 4, 82], [76, 8, 81], [84, 12, 79],
	[96, 6, 77], [102, 2, 76], [104, 8, 73], [112, 16, 76],
]
## Last bar of the second pass, turning back to the opening A.
const MENU_ENDING := [[112, 8, 76], [120, 8, 73]]

# Stingers.
const LEVEL_UP_NOTES := [74, 77, 81, 84, 86, 89]
const FANFARE_CHORDS := [[58, 62, 65, 70], [60, 64, 67, 72], [62, 66, 69, 74]]
const FANFARE_ROOTS := [34, 36, 38]
const FANFARE_SPARKLE := [74, 78, 81, 86, 90]
const FINALE_MOTIF := [81, 86, 90, 88, 86]
const DEATH_CHORD := [50, 53, 57, 62]

## Seconds per bar of a looping track.
static func bar_seconds(track: StringName, composition: MusicComposition = null) -> float:
	if track in [&"stage", &"boss"]:
		return composition.step * 16.0 / MusicSynth.RATE if composition != null else 0.0
	return step_samples(MENU_BPM) * 16.0 / MusicSynth.RATE

## Rounded samples per 16th; all timing, including director bar quantization, uses this grid.
static func step_samples(bpm: float) -> int:
	return roundi(MusicSynth.RATE * 15.0 / bpm)

## Renders one stem (or stinger when track is STINGER_TRACK). Returns null when cancelled.
static func render(synth: MusicSynth, track: StringName, stem: StringName, composition: MusicComposition = null) -> AudioStreamWAV:
	var random := RandomNumberGenerator.new()
	random.seed = (composition.seed if composition != null else 1337) ^ hash(track) ^ hash(stem)
	synth.noise_cursor = random.randi() & MusicSynth.NOISE_MASK
	var buf := PackedFloat32Array()
	var loop := true
	match track:
		&"menu":
			buf = _menu(synth, stem)
		&"stage":
			assert(composition != null, "Techno rendering requires a run composition")
			buf = _techno(synth, stem, composition)
		&"boss":
			assert(composition != null, "Boss rendering requires a run composition")
			buf = _hardtek(synth, stem, random, composition)
		STINGER_TRACK:
			buf = _stinger(synth, stem)
			loop = false
	if MusicSynth.cancelled or (composition != null and composition.is_cancelled()) or buf.is_empty():
		return null
	return synth.to_wav(buf, loop)


## Sample-only 125 BPM arrangement. Intact labelled phrases remain in one
## minor key, with musical rests and density changes over eight four-bar sections.
static func _techno(synth: MusicSynth, stem: StringName, mix: MusicComposition) -> PackedFloat32Array:
	var step := mix.step
	var beat := step * 4
	var bar := step * 16
	var buf := MusicSynth.buffer(bar * mix.bars)
	var key: StringName = mix.techno_clips[stem]
	var clip: Dictionary = MusicSamples.TECHNO.CLIPS[key]
	for b in mix.bars:
		if MusicSynth.cancelled or mix.is_cancelled():
			return PackedFloat32Array()
		var at := b * bar
		var density: int = mix.sections[b / 4]
		match stem:
			&"kick":
				for q in 4:
					synth.sample_hit(buf, at + q * beat, key, 0.65 if q == 0 else 0.6, 1.0, 0, beat - 45, false, 30)
			&"clap":
				for q in [1, 3]:
					synth.sample_hit(buf, at + q * beat, key, 0.16, 1.0, 0, beat, false, 30)
			&"hat":
				for s in range(2, 16, 4):
					synth.sample_hit(buf, at + s * step, key, 0.13 * mix.hat_accents[s], 1.0, 0, step * 2, false, 30)
				if density >= 2:
					for s in [3, 7, 11, 15]:
						synth.sample_hit(buf, at + s * step, key, 0.045 * mix.hat_accents[s], 1.0, 0, step, false, 30)
			_:
				if stem == &"groove" and density == 0:
					continue
				if stem == &"synth" and (density == 0 or b % 4 == 3):
					continue
				if stem == &"arp" and (density < 2 or b % 4 == 0):
					continue
				var source_beat: float = float(mix.loop_offsets[stem]) + b * 4.0
				var source_frames := MusicSynth.RATE * 60.0 / float(clip.bpm)
				var source_at := roundi(fposmod(source_beat, float(clip.beats)) * source_frames)
				var rate := float(beat) / source_frames
				var gain := 0.2
				match stem:
					&"groove": gain = 0.12
					&"bass": gain = 0.35
					&"synth": gain = 0.17
					&"arp": gain = 0.14
					&"ambient": gain = 0.08
				synth.sample_hit(buf, at, key, gain, 1.0 / rate, source_at, bar, true, 45)
	var peak := 0.15
	match stem:
		&"kick": peak = 0.66
		&"clap": peak = 0.13
		&"hat": peak = 0.12
		&"groove": peak = 0.11
		&"bass": peak = 0.26
		&"synth": peak = 0.15
		&"arp": peak = 0.10
		&"ambient": peak = 0.07
	if stem in [&"bass", &"synth", &"arp", &"ambient"]:
		synth.pump(buf, beat, 0.45, 0.65)
	synth.normalize(buf, peak, false)
	return buf
# --- Boss hardtek ------------------------------------------------------------------------------

static func _hardtek(synth: MusicSynth, stem: StringName, random: RandomNumberGenerator, mix: MusicComposition) -> PackedFloat32Array:
	var step := mix.step
	var beat := step * 4
	var bar := step * 16
	var buf := MusicSynth.buffer(bar * mix.bars)
	for b in mix.bars:
		if MusicSynth.cancelled or mix.is_cancelled():
			return PackedFloat32Array()
		var at := b * bar
		var root: int = mix.roots[b / 4]
		var density: int = mix.sections[b / 4]
		match stem:
			&"boss_pad":
				var chord: Array = mix.pads[b / 4]
				for note: int in chord:
					synth.pad_note(buf, at, bar, note - 12, 0.022, beat, beat * 2, 8.0)
				if b % 4 == 0:
					_grain(synth, buf, at, mix.ambient_clip, 0.018, bar * 2, mix.ambient_position)
			&"drums":
				for q in 4:
					synth.sample_hit(buf, at + q * beat, mix.kick_clip, 0.56 if q == 0 else 0.52, 1.0, 0, beat - 80, false, 30)
				if b % 4 == 3:
					synth.sample_hit(buf, at + (14 if density >= 2 else 15) * step, mix.kick_clip, 0.22, 1.0, 0, step - 80, false, 30)
				for s in [4, 12]:
					synth.snare(buf, at + s * step, 0.085, 0.12, 190.0)
					synth.clap(buf, at + s * step, 0.095)
				for s in [2, 6, 10, 14]:
					synth.hat(buf, at + s * step, 0.12, 28.0, 0.12)
			&"boss_drive":
				for s in 16:
					if s % 4 == 0:
						continue
					var offset: int = mix.acid_pattern[(s + 4) % 16]
					synth.bass_note(buf, at + s * step, int(step * 0.76), mix.key + offset, 0.15, 140.0, 1900.0, 25.0, 2.1, 3.0, 0.3)
				if b % 4 == 3:
					synth.lead_note(buf, at + 10 * step, 2 * step, root + 24, 0.035, 1250.0, 10.0, 0.0, 0.4, 1.7)
			&"perc":
				for s in 16:
					if s % 4 == 0 or (density == 0 and s % 2 == 1):
						continue
					var gain: float = 0.11 * mix.hat_accents[s] * random.randf_range(0.85, 1.0)
					synth.hat(buf, at + s * step, gain, 13.0 if s in [6, 14] else 75.0, 0.18 if s in [6, 14] else 0.05)
				if b % 4 == 3:
					for s in [11, 13, 15]:
						synth.tom(buf, at + s * step, 0.07, 170.0 - s * 5.0, 75.0, 24.0, 0.12)
				if b % 8 == 0:
					synth.cymbal(buf, at, 0.065, 6.0, 0.8)
			&"tension":
				if b % 4 == 2:
					synth.bass_note(buf, at + 6 * step, beat * 2, root + 12, 0.065, 180.0, 1050.0, 3.0, 1.8, 2.0, 0.5)
				if b % 8 == 7:
					synth.riser(buf, at + 8 * step, beat * 2, 0.13, 250.0, 3900.0)
			&"breaks":
				var key: StringName = mix.break_clip
				var source_at := mix.break_beat + (b % 2) * 4.0
				if density >= 2 or b % 4 == 2:
					_grid_slice(synth, buf, at, key, 0.14, 4.0, source_at, mix)
				else:
					for s in [6, 14]:
						_grid_slice(synth, buf, at + s * step, key, 0.1, 0.5, source_at + s * 0.25, mix)
			&"rave":
				# Repeat one intact two-bar 303 phrase; no new source or random chop per bar.
				_grid_slice(synth, buf, at, mix.acid_clip, 0.07, 4.0, mix.acid_beat + (b % 2) * 4.0, mix)
				# One recurring transition sound, only at eight-bar phrase endings.
				if b % 8 == 7:
					_grain(synth, buf, at + 10 * step, mix.fx_clip, 0.075, beat * 2, mix.fx_position)
			&"vocals":
				var index := mix.vocal_bars.find(b)
				if index >= 0:
					var key: StringName = mix.vocals[index % mix.vocals.size()]
					var rate := random.randf_range(0.94, 1.08)
					synth.sample_hit(buf, at + 10 * step, key, 0.3, rate, 0, beat * 2, false, 110)
			_:
				return PackedFloat32Array()
	if mix.is_cancelled():
		return PackedFloat32Array()
	var peak := 0.16
	match stem:
		&"boss_pad":
			synth.sweep_lowpass(buf, 780.0, 300.0, 2.0)
			peak = 0.11
		&"drums":
			peak = 0.66
		&"perc":
			peak = 0.14
		&"tension":
			peak = 0.12
		&"boss_drive":
			peak = 0.19
		&"rave":
			synth.echo(buf, step * 3, 0.16, 0.14, 0.65)
			peak = 0.15
		&"vocals":
			peak = 0.22
	if stem != &"drums":
		synth.pump(buf, beat, 0.55, 0.65)
	synth.normalize(buf, peak, false)
	return buf

## The source window is chosen once per run and reused without pitch/offset randomization.
static func _grain(synth: MusicSynth, buf: PackedFloat32Array, at: int, key: StringName, gain: float, length: int, position: float) -> void:
	var source_frames := synth.sample_frames(key)
	var span := mini(source_frames, length)
	var source_start := roundi(position * maxi(0, source_frames - span))
	synth.sample_hit(buf, at, key, gain, 1.0, source_start, length, false, 220)

## Follow each recording's exact PCM beat grid, not its rounded 170 BPM label.
static func _grid_slice(synth: MusicSynth, buf: PackedFloat32Array, at: int, key: StringName, gain: float, beats: float, source_beat: float, mix: MusicComposition) -> void:
	var clip: Dictionary = MusicSamples.PACK.CLIPS[key]
	var source_beat_frames: float = MusicSynth.RATE * 60.0 / float(clip.bpm)
	var actual_bpm := MusicSynth.RATE * 60.0 / (mix.step * 4.0)
	var source_start := roundi(fposmod(source_beat, float(clip.beats)) * source_beat_frames)
	synth.sample_hit(buf, at, key, gain, actual_bpm / float(clip.bpm), source_start, roundi(beats * mix.step * 4.0), true, 45)


# --- Menu --------------------------------------------------------------------------------------

static func _menu(synth: MusicSynth, stem: StringName) -> PackedFloat32Array:
	var step := step_samples(MENU_BPM)
	var bar := step * 16
	var bars: int = MENU_BARS
	match stem:
		&"pad":
			# Pad, sub and arp repeat every 8 bars: render once, then double.
			var half := MusicSynth.buffer(bar * MENU_BAR_CHORDS.size())
			_pad_voices(synth, half, MENU_BAR_CHORDS, bar, 0.22, MusicSynth.samples(1.1), MusicSynth.samples(1.6), 11.0)
			for c in MENU_ROOTS.size():
				synth.sine_note(half, c * 2 * bar, 2 * bar, MusicSynth.hz(MENU_ROOTS[c]), 0.45, MusicSynth.samples(0.4), MusicSynth.samples(0.8))
			synth.sweep_lowpass(half, 900.0, 450.0, 2.0)
			synth.pump(half, step * 8, 0.25, 0.8)
			var arp := MusicSynth.buffer(half.size())
			for e in MENU_BAR_CHORDS.size() * 8:
				var chord: Array = MENU_BAR_CHORDS[floori(e / 8.0)]
				synth.pluck(arp, e * 2 * step, step * 4, chord[MENU_ARP[e % 8]], 1.0 if e % 2 == 0 else 0.7, 5.0, 4.0, 0.2)
			synth.echo(arp, step * 6, 0.45, 0.6, 0.5)
			synth.mix(half, arp, 0.3)
			var buf := half.duplicate()
			buf.append_array(half)
			synth.normalize(buf, 0.36)
			return buf
		&"motif":
			var buf := MusicSynth.buffer(bar * bars)
			var second_pass := bar * 8
			for pass_index in 2:
				for note in MENU_MOTIF:
					if pass_index == 1 and note[0] >= 112:
						continue
					_motif_note(synth, buf, pass_index * second_pass + note[0] * step, note[1] * step, note[2], pass_index == 1)
			for note in MENU_ENDING:
				_motif_note(synth, buf, second_pass + note[0] * step, note[1] * step, note[2], true)
			synth.echo(buf, step * 3, 0.42, 0.5, 0.3)
			synth.normalize(buf, 0.3)
			return buf
		&"beat":
			var buf := MusicSynth.buffer(bar * bars)
			var swing := int(step * 0.1)
			for b in range(8, bars):
				var at := b * bar
				synth.kick(buf, at, 0.9, 0.6, 44.0, 5.5)
				if b % 2 == 1:
					synth.kick(buf, at + 10 * step, 0.55, 0.5, 44.0, 6.0)
				synth.snare(buf, at + 8 * step, 0.55, 1.0, 175.0)
				for s in range(0, 16, 2):
					var offbeat := s % 4 == 2
					synth.hat(buf, at + s * step + (swing if offbeat else 0), 0.22 if offbeat else 0.12, 60.0, 0.06)
			synth.riser(buf, 7 * bar, bar, 0.5)
			synth.cymbal(buf, 8 * bar, 0.5, 1.8, 2.5)
			synth.normalize(buf, 0.34)
			return buf
	return PackedFloat32Array()

## Bell carries the motif; on the second pass a soft saw lead doubles it an octave below.
static func _motif_note(synth: MusicSynth, buf: PackedFloat32Array, start: int, length: int, midi: int, doubled: bool) -> void:
	synth.bell(buf, start, length + MusicSynth.samples(0.9), midi, 0.8, 3.0, 2.0, 2.0)
	if doubled:
		synth.lead_note(buf, start, length - 200, midi - 12, 0.3, 1300.0, 6.0, 0.004)

# --- Stingers ----------------------------------------------------------------------------------

static func _stinger(synth: MusicSynth, stem: StringName) -> PackedFloat32Array:
	match stem:
		&"level_up":
			var buf := MusicSynth.buffer(MusicSynth.samples(1.6))
			var gap := MusicSynth.samples(0.055)
			var last := LEVEL_UP_NOTES.size() - 1
			for k in LEVEL_UP_NOTES.size():
				var note: int = LEVEL_UP_NOTES[k]
				synth.bell(buf, k * gap, MusicSynth.samples(1.2 if k == last else 0.45), note, 0.7, 3.5 if k == last else 8.0, 2.0, 1.6)
				synth.pluck(buf, k * gap, MusicSynth.samples(0.3), note - 12, 0.4, 10.0, 6.0)
			synth.pad_note(buf, last * gap, MusicSynth.samples(0.45), 81, 0.12, 300, MusicSynth.samples(0.6), 14.0)
			synth.pad_note(buf, last * gap, MusicSynth.samples(0.45), 86, 0.1, 300, MusicSynth.samples(0.6), 14.0)
			synth.riser(buf, 0, last * gap, 0.3, 1500.0, 9000.0)
			synth.normalize(buf, 0.55)
			return buf
		&"stage_clear":
			var buf := MusicSynth.buffer(MusicSynth.samples(3.0))
			var hit := MusicSynth.samples(0.2)
			_fanfare(synth, buf, hit, MusicSynth.samples(1.5))
			synth.normalize(buf, 0.6)
			return buf
		&"run_complete":
			var buf := MusicSynth.buffer(MusicSynth.samples(4.6))
			var hit := MusicSynth.samples(0.3)
			synth.tom(buf, int(hit * 1.5), 0.6, 160.0, 110.0)
			synth.tom(buf, int(hit * 1.75), 0.7, 120.0, 80.0)
			_fanfare(synth, buf, hit, MusicSynth.samples(2.8))
			var gap := MusicSynth.samples(0.18)
			var begin := MusicSynth.samples(1.0)
			for k in FINALE_MOTIF.size():
				var ring := 1.6 if k == FINALE_MOTIF.size() - 1 else 0.5
				synth.bell(buf, begin + k * gap, MusicSynth.samples(ring), FINALE_MOTIF[k], 0.6, 2.5, 2.0, 1.8)
			synth.normalize(buf, 0.62)
			return buf
		&"death":
			var buf := MusicSynth.buffer(MusicSynth.samples(2.8))
			var hold := MusicSynth.samples(1.7)
			for note in DEATH_CHORD:
				synth.pad_note(buf, 0, hold, note, 0.25, 120, MusicSynth.samples(0.6), 16.0, 0.62)
			synth.pad_note(buf, 0, hold, 38, 0.3, 120, MusicSynth.samples(0.6), 6.0, 0.62)
			synth.tom(buf, 0, 1.0, 110.0, 30.0, 1.8, 2.0)
			synth.snare(buf, 0, 0.4, 1.0, 150.0)
			synth.sweep_lowpass(buf, 1700.0, -1400.0, 0.25)
			synth.normalize(buf, 0.55)
			return buf
	return PackedFloat32Array()

## Bb - C - D major brass hits `hit` apart; the D chord holds for `hold` with a sparkle run.
static func _fanfare(synth: MusicSynth, buf: PackedFloat32Array, hit: int, hold: int) -> void:
	var last := FANFARE_CHORDS.size() - 1
	for c in FANFARE_CHORDS.size():
		var at := c * hit
		var chord: Array = FANFARE_CHORDS[c]
		var length := hold if c == last else hit
		var release := MusicSynth.samples(0.7 if c == last else 0.08)
		for note in chord:
			synth.pad_note(buf, at, length, note, 0.22, 250, release, 12.0)
		synth.lead_note(buf, at, length, chord[3] + 12, 0.5, 3000.0, 8.0, 0.006 if c == last else 0.0)
		synth.bass_note(buf, at, length, FANFARE_ROOTS[c], 0.7, 120.0, 900.0, 8.0, 1.2, 1.4, 0.3)
		synth.kick(buf, at, 0.9)
	var peak := last * hit
	synth.snare(buf, peak, 0.6, 1.0)
	synth.cymbal(buf, peak, 0.6, 1.8, 2.2)
	for k in FANFARE_SPARKLE.size():
		synth.pluck(buf, peak + k * MusicSynth.samples(0.08), MusicSynth.samples(0.5), FANFARE_SPARKLE[k], 0.45, 7.0, 8.0)

# --- Helpers -----------------------------------------------------------------------------------


## Renders each chord voice as a legato line: repeated pitches across bars merge into one note,
## and every note releases over the next one's attack.
static func _pad_voices(synth: MusicSynth, buf: PackedFloat32Array, bar_chords: Array, bar: int, gain: float, attack: int, release: int, detune: float) -> void:
	var bars := bar_chords.size()
	for voice in (bar_chords[0] as Array).size():
		var b := 0
		while b < bars:
			var pitch: int = bar_chords[b][voice]
			var end := b + 1
			while end < bars and bar_chords[end][voice] == pitch:
				end += 1
			synth.pad_note(buf, b * bar, (end - b) * bar, pitch, gain, attack, release, detune)
			b = end
