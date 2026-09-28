class_name MusicScore
extends RefCounted
## Composition of the procedural soundtrack: tempo, harmony, patterns and the arrangement of
## every stem. All stems of a track have the same length and start on the same sample, so the
## director keeps them locked and only automates their volumes.

const STINGER_TRACK := &"stinger"
## Loop stems per track, in render priority order.
const TRACK_STEMS := {
	&"menu": [&"pad", &"motif", &"beat"],
	&"stage": [&"pad", &"pulse", &"drums", &"drive", &"arp", &"lead", &"perc", &"tension", &"boss_pad", &"boss_drive"],
}
const STINGERS := [&"level_up", &"stage_clear", &"death", &"run_complete"]
const TRACK_BPM := {&"menu": 90.0, &"stage": 126.0}
const TRACK_BARS := {&"menu": 16, &"stage": 8}

# Stage harmony in D minor, one chord per two bars: i - VI - III - VII (Dm Bb F C).
const STAGE_ROOTS := [38, 34, 41, 36]
const STAGE_PADS := [[57, 62, 65, 69], [58, 62, 65, 70], [57, 60, 65, 69], [55, 60, 64, 67]]
const STAGE_ARPS := [[62, 65, 69, 74], [62, 65, 70, 74], [65, 69, 72, 77], [64, 67, 72, 76]]
## Arp tone indices per 16th; 4 is the first tone an octave up.
const ARP_PATTERN := [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 4, 3, 2, 1]
## Rolling bass per beat: root, root, octave, root.
const DRIVE_PATTERN := [0, 0, 12, 0]
## Last beat of each chord turns toward the fifth.
const DRIVE_TURN := [7, 7, 19, 10]
## Stage lead over 8 bars: [16th step, length in 16ths, midi].
const STAGE_LEAD := [
	[0, 3, 69], [3, 3, 74], [6, 2, 77], [8, 4, 76], [12, 4, 74],
	[16, 6, 81], [22, 2, 79], [24, 4, 77], [28, 2, 76], [30, 2, 77],
	[32, 6, 74], [38, 2, 77], [40, 4, 82], [44, 4, 81],
	[48, 8, 77], [56, 4, 79], [60, 4, 81],
	[64, 6, 84], [70, 2, 81], [72, 4, 79], [76, 4, 77],
	[80, 6, 81], [86, 2, 79], [88, 4, 77], [92, 4, 72],
	[96, 6, 76], [102, 2, 79], [104, 4, 84], [108, 4, 79],
	[112, 3, 76], [115, 3, 77], [118, 2, 79], [120, 8, 81],
]
## 16th-hat accents (downbeat, e, and, a).
const HAT_ACCENTS := [1.0, 0.35, 0.65, 0.4]

# Boss harmony, one chord per two bars: i - bII - VI - V (Dm Eb Bb A).
const BOSS_ROOTS := [38, 39, 34, 33]
const BOSS_PADS := [[50, 57, 62, 65], [51, 58, 63, 67], [50, 58, 62, 65], [49, 57, 61, 64]]
## Galloping 16ths per beat (0 = rest).
const BOSS_GALLOP := [1.0, 0.0, 0.8, 0.85]
## War-drum toms per bar: [16th step, gain].
const BOSS_TOMS := [[0, 1.0], [3, 0.7], [6, 0.85], [10, 0.6]]

# Menu (90 BPM): moody 8-bar harmony played twice, Dm Bb Gm Asus4-A.
const MENU_ROOTS := [38, 34, 31, 33]
const MENU_BAR_CHORDS := [
	[57, 62, 65, 69], [57, 62, 65, 69], [58, 62, 65, 70], [58, 62, 65, 70],
	[55, 62, 67, 70], [55, 62, 67, 70], [57, 62, 64, 69], [57, 61, 64, 69],
]
const MENU_ARP := [0, 1, 2, 3, 2, 1, 2, 1]
## The game's motif (the stage lead opens with it): [16th step, length, midi] over 8 bars.
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
static func bar_seconds(track: StringName) -> float:
	return 240.0 / float(TRACK_BPM.get(track, 120.0))

## Samples per 16th note at `bpm`; tempos are chosen so this is a whole number.
static func step_samples(bpm: float) -> int:
	return roundi(MusicSynth.RATE * 15.0 / bpm)

## Renders one stem (or stinger when track is STINGER_TRACK). Returns null when cancelled.
static func render(synth: MusicSynth, track: StringName, stem: StringName) -> AudioStreamWAV:
	synth.noise_cursor = hash(stem) & MusicSynth.NOISE_MASK
	var buf := PackedFloat32Array()
	var loop := true
	match track:
		&"menu":
			buf = _menu(synth, stem)
		&"stage":
			buf = _stage(synth, stem)
		STINGER_TRACK:
			buf = _stinger(synth, stem)
			loop = false
	if MusicSynth.cancelled or buf.is_empty():
		return null
	return synth.to_wav(buf, loop)

# --- Stage -------------------------------------------------------------------------------------

static func _stage(synth: MusicSynth, stem: StringName) -> PackedFloat32Array:
	var step := step_samples(TRACK_BPM[&"stage"])
	var beat := step * 4
	var bar := step * 16
	var bars: int = TRACK_BARS[&"stage"]
	var steps := bars * 16
	var buf := MusicSynth.buffer(bar * bars)
	match stem:
		&"pad":
			_pad_voices(synth, buf, _two_bar_chords(STAGE_PADS), bar, 0.25, MusicSynth.samples(0.25), MusicSynth.samples(0.45), 9.0)
			synth.sweep_lowpass(buf, 1500.0, 700.0, 1.0)
			synth.pump(buf, beat, 0.6, 0.55)
			synth.normalize(buf, 0.22)
		&"pulse":
			for s in range(0, steps, 2):
				var root: int = STAGE_ROOTS[floori(s / 32.0)]
				var accent := 1.0 if s % 4 == 0 else 0.72
				synth.bass_note(buf, s * step, int(step * 1.3), root, accent, 110.0, 620.0, 16.0, 1.1, 1.0, 0.2)
			synth.pump(buf, beat, 0.35, 0.4)
			synth.normalize(buf, 0.28)
		&"drums":
			for b in bars:
				var at := b * bar
				for q in 4:
					synth.kick(buf, at + q * beat, 1.0)
				if b == 3:
					synth.kick(buf, at + 14 * step, 0.65, 0.7)
				synth.snare(buf, at + 4 * step, 0.8, 1.0)
				if b == bars - 1:
					for k in 4:
						synth.snare(buf, at + (12 + k) * step, 0.45 + 0.15 * k, 0.3 * k)
				else:
					synth.snare(buf, at + 12 * step, 0.8, 1.0)
				for s in [2, 6, 10, 14]:
					synth.hat(buf, at + s * step, 0.42, 38.0, 0.1)
			synth.normalize(buf, 0.5)
		&"drive":
			for s in steps:
				var root: int = STAGE_ROOTS[floori(s / 32.0)]
				var offset: int = DRIVE_TURN[s % 4] if s % 32 >= 28 else DRIVE_PATTERN[s % 4]
				var downbeat := s % 4 == 0
				synth.bass_note(buf, s * step, int(step * 0.82), root + offset, 1.0 if downbeat else 0.78, 160.0, 1500.0 if downbeat else 1100.0, 14.0, 2.4, 1.6, 0.25)
			synth.pump(buf, beat, 0.4, 0.35)
			synth.normalize(buf, 0.3)
		&"arp":
			for s in steps:
				var tones: Array = STAGE_ARPS[floori(s / 32.0)]
				var index: int = ARP_PATTERN[s % 16]
				var note: int = tones[index % 4] + (12 if index >= 4 else 0)
				synth.pluck(buf, s * step, step * 2, note, 1.0 if s % 4 == 0 else 0.7, 14.0, 7.0, 0.35)
			synth.echo(buf, step * 3, 0.38, 0.45, 0.35)
			synth.normalize(buf, 0.18)
		&"lead":
			for note in STAGE_LEAD:
				synth.lead_note(buf, note[0] * step, note[1] * step - 120, note[2], 1.0, 2400.0, 8.0, 0.005)
			synth.echo(buf, step * 3, 0.32, 0.3, 0.4)
			synth.normalize(buf, 0.22)
		&"perc":
			var swing := int(step * 0.12)
			for b in bars:
				var at := b * bar
				for s in 16:
					var hit_at := at + s * step + (swing if s % 2 == 1 else 0)
					if s == 6 or s == 14:
						synth.hat(buf, hit_at, 0.5, 9.0, 0.3)
					else:
						var humanize := 0.9 + 0.1 * synth.noise[((b * 16 + s) * 131) & MusicSynth.NOISE_MASK]
						synth.hat(buf, hit_at, 0.5 * HAT_ACCENTS[s % 4] * humanize, 70.0, 0.06)
				synth.clap(buf, at + beat, 0.6)
				synth.clap(buf, at + 3 * beat, 0.6)
				if b == bars - 1:
					synth.tom(buf, at + 8 * step, 0.7, 190.0, 130.0)
					synth.tom(buf, at + 10 * step, 0.75, 150.0, 100.0)
					synth.tom(buf, at + 11 * step, 0.8, 120.0, 80.0)
			synth.cymbal(buf, 0, 0.9)
			synth.cymbal(buf, 4 * bar, 0.5)
			synth.normalize(buf, 0.22)
		&"tension":
			synth.drone(buf, 74, 0.5, 9.0)
			synth.drone(buf, 81, 0.35, 11.0)
			synth.drone(buf, 86, 0.18, 13.0)
			synth.sweep_lowpass(buf, 2000.0, 1200.0, 2.0)
			synth.pump(buf, step, 0.75, 0.85)
			synth.riser(buf, (bars - 2) * bar, 2 * bar, 0.9)
			synth.tom(buf, 0, 1.0, 95.0, 30.0, 2.2, 1.4)
			synth.normalize(buf, 0.18)
		&"boss_pad":
			_pad_voices(synth, buf, _two_bar_chords(BOSS_PADS), bar, 0.25, MusicSynth.samples(0.15), MusicSynth.samples(0.4), 15.0)
			for c in BOSS_ROOTS.size():
				synth.sine_note(buf, c * 2 * bar, 2 * bar, MusicSynth.hz(BOSS_ROOTS[c]), 0.6, 800, MusicSynth.samples(0.15))
			synth.sweep_lowpass(buf, 1000.0, 400.0, 2.0)
			synth.pump(buf, beat, 0.5, 0.5)
			synth.normalize(buf, 0.24)
		&"boss_drive":
			for s in steps:
				var weight: float = BOSS_GALLOP[s % 4]
				if weight > 0.0:
					synth.bass_note(buf, s * step, int(step * 0.9), BOSS_ROOTS[floori(s / 32.0)], weight, 120.0, 1300.0, 22.0, 3.2, 3.5, 0.5)
			for b in bars:
				for hit in BOSS_TOMS:
					synth.tom(buf, b * bar + hit[0] * step, hit[1], 110.0, 60.0, 7.0)
			# Half-step siren on the second bar of every chord.
			for c in BOSS_ROOTS.size():
				var top: int = BOSS_ROOTS[c] + 36
				var at := (c * 2 + 1) * bar
				synth.lead_note(buf, at, 3 * step - 150, top, 0.5, 1800.0, 12.0, 0.0, 0.5, 1.8)
				synth.lead_note(buf, at + 3 * step, 3 * step - 150, top + 1, 0.5, 1800.0, 12.0, 0.0, 0.5, 1.8)
				synth.lead_note(buf, at + 6 * step, 2 * step - 150, top, 0.5, 1800.0, 12.0, 0.0, 0.5, 1.8)
				synth.lead_note(buf, at + 8 * step, 8 * step - 150, top - 5, 0.5, 1800.0, 12.0, 0.008, 0.5, 1.8)
			synth.normalize(buf, 0.34)
	return buf

# --- Menu --------------------------------------------------------------------------------------

static func _menu(synth: MusicSynth, stem: StringName) -> PackedFloat32Array:
	var step := step_samples(TRACK_BPM[&"menu"])
	var bar := step * 16
	var bars: int = TRACK_BARS[&"menu"]
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

## Expands one chord per two bars into one chord per bar.
static func _two_bar_chords(chords: Array) -> Array:
	var result := []
	for chord in chords:
		result.append(chord)
		result.append(chord)
	return result

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
