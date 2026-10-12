class_name MusicScore
extends RefCounted
## Composition of the procedural soundtrack: tempo, harmony, patterns and the arrangement of
## every stem. All stems of a track have the same length and start on the same sample, so the
## director keeps them locked and only automates their volumes.

const STINGER_TRACK := &"stinger"
## Loop stems per track, in render priority order.
const TRACK_STEMS := {
	&"menu": [&"pad", &"motif", &"beat"],
	&"stage": [&"pad", &"pulse", &"drums", &"drive", &"arp", &"lead", &"perc", &"tension", &"boss_pad", &"boss_drive", &"breaks", &"rave", &"vocals"],
}
const STINGERS := [&"level_up", &"stage_clear", &"death", &"run_complete"]
const TRACK_BPM := {&"menu": 90.0, &"stage": 186.0}
const TRACK_BARS := {&"menu": 16, &"stage": 16}

# Sixteen-bar D-minor phrase, one harmony per four bars: i - VI - III - VII.
const STAGE_ROOTS := [38, 34, 41, 36]
const STAGE_PADS := [[57, 62, 65, 69], [58, 62, 65, 70], [57, 60, 65, 69], [55, 60, 64, 67]]
const STAGE_ARPS := [[62, 65, 69, 74], [62, 65, 70, 74], [65, 69, 72, 77], [64, 67, 72, 76]]
const ACID_PATTERN := [0, 12, 0, 7, 0, 0, 10, 12, 0, 7, 12, 0, 3, 0, 7, 10]
## Short, spacious version of the menu's A-D-F-E-D motif.
const STAGE_MOTIF := [[0, 2, 69], [3, 2, 74], [6, 2, 77], [10, 2, 76], [13, 2, 74]]
const HAT_ACCENTS := [0.45, 0.7, 1.0, 0.6]
## D-minor-compatible boss bed: darker voicings, not a competing key over the main rhythm.
const BOSS_PADS := [[50, 57, 62, 65], [50, 58, 62, 65], [53, 57, 60, 65], [48, 55, 60, 64]]
## Eight-beat source-loop sixteenths containing useful snare/hat transients.
const BREAK_CHOPS := [4, 6, 10, 12, 16, 22, 26, 28]
const VOCAL_KEYS := [&"voice_fast", &"voice_hrrr", &"voice_ijee", &"voice_aaa", &"voice_chleba", &"voice_takhle"]
const VOCAL_BARS := [1, 3, 5, 9, 11, 13]

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
	return step_samples(float(TRACK_BPM.get(track, 120.0))) * 16.0 / MusicSynth.RATE

## Rounded samples per 16th; all timing, including director bar quantization, uses this grid.
static func step_samples(bpm: float) -> int:
	return roundi(MusicSynth.RATE * 15.0 / bpm)

## Renders one stem (or stinger when track is STINGER_TRACK). Returns null when cancelled.
static func render(synth: MusicSynth, track: StringName, stem: StringName, composition_seed: int = 1337) -> AudioStreamWAV:
	var random := RandomNumberGenerator.new()
	random.seed = composition_seed ^ hash(track) ^ hash(stem)
	synth.noise_cursor = random.randi() & MusicSynth.NOISE_MASK
	var buf := PackedFloat32Array()
	var loop := true
	match track:
		&"menu":
			buf = _menu(synth, stem)
		&"stage":
			buf = _stage(synth, stem, random)
		STINGER_TRACK:
			buf = _stinger(synth, stem)
			loop = false
	if MusicSynth.cancelled or buf.is_empty():
		return null
	return synth.to_wav(buf, loop)

# --- Stage -------------------------------------------------------------------------------------

static func _stage(synth: MusicSynth, stem: StringName, random: RandomNumberGenerator) -> PackedFloat32Array:
	var step := step_samples(TRACK_BPM[&"stage"])
	var beat := step * 4
	var bar := step * 16
	var bars: int = TRACK_BARS[&"stage"]
	var buf := MusicSynth.buffer(bar * bars)
	# Per-stem peaks are ceilings, never loudness boosts: sparse accents stay sparse and the
	# actual D-series kick remains far louder than any individual melodic layer.
	var peak := 0.16
	match stem:
		&"pad":
			_pad_voices(synth, buf, _four_bar_chords(STAGE_PADS), bar, 0.022, beat, beat * 2, 8.0)
			synth.sweep_lowpass(buf, 780.0, 300.0, 2.0)
			synth.pump(buf, beat, 0.55, 0.65)
			peak = 0.10
		&"pulse":
			# The quiet-pressure mix still has a deep offbeat pulse under the hard kick.
			for b in bars:
				var root: int = STAGE_ROOTS[b / 4] - 12
				for q in 4:
					var at := b * bar + q * beat + 2 * step
					synth.sine_note(buf, at, step, MusicSynth.hz(root), 0.10, 64, step / 2)
					synth.bass_note(buf, at, step, root + 12, 0.035, 90.0, 360.0, 24.0, 0.9, 1.7, 0.35)
			synth.pump(buf, beat, 0.65, 0.7)
			peak = 0.13
		&"drums":
			for b in bars:
				var at := b * bar
				var heavy := b >= 8 or b % 4 == 0
				for q in 4:
					var key: StringName = &"kick_heavy" if heavy and q % 2 == 0 else &"kick"
					synth.sample_hit(buf, at + q * beat, key, 0.56 if q == 0 else 0.52, 1.0, 0, beat - 80, false, 30)
				# Fourth-bar pickup rolls are seeded; the core four-on-floor never disappears.
				if b % 4 == 3:
					var pickup := 14 if random.randf() < 0.5 else 15
					synth.sample_hit(buf, at + pickup * step, &"kick", 0.24, 1.08, 0, step - 80, false, 30)
				for s in [4, 12]:
					synth.snare(buf, at + s * step, 0.085, 0.12, 190.0)
					synth.clap(buf, at + s * step, 0.095)
				for s in [2, 6, 10, 14]:
					synth.hat(buf, at + s * step, 0.12, 28.0, 0.12)
				if b % 4 == 3:
					synth.snare(buf, at + 15 * step, 0.05, 0.0, 230.0)
			peak = 0.66
		&"drive":
			# Rolling, clipped acid attacks sit between kick transients instead of masking them.
			for b in bars:
				var root: int = STAGE_ROOTS[b / 4]
				var rotation := random.randi_range(0, 3) * 4
				for s in 16:
					if s % 4 == 0 or (b % 4 == 0 and s == 15):
						continue
					var offset: int = ACID_PATTERN[(s + rotation) % 16]
					var accent := s % 4 == 2
					var cutoff := 1600.0 if accent else 850.0
					if b % 4 == 3:
						cutoff += s * 65.0
					synth.bass_note(buf, b * bar + s * step, int(step * 0.72), root + offset, 0.13 if accent else 0.085, 140.0, cutoff, 25.0, 2.1, 3.0, 0.3)
			synth.pump(buf, beat, 0.75, 0.65)
			peak = 0.15
		&"arp":
			for b in bars:
				var chord: Array = STAGE_ARPS[b / 4]
				var rotation := random.randi_range(0, 3)
				for s in range(2, 16, 2):
					if b % 4 < 2 and s in [6, 10]:
						continue
					var note: int = chord[(s / 2 + rotation) % 4]
					synth.pluck(buf, b * bar + s * step, step * 2, note, 0.065, 24.0, 5.0, 0.2)
			synth.echo(buf, step * 3, 0.25, 0.22, 0.55)
			synth.pump(buf, beat, 0.5, 0.6)
			peak = 0.085
		&"lead":
			# Calls only at phrase openings, with a short answer two bars later: no wall of lead.
			for phrase in 4:
				var at := phrase * 4 * bar
				var transpose := -2 if phrase == 3 else 0
				for note in STAGE_MOTIF:
					synth.lead_note(buf, at + note[0] * step, note[1] * step - 100, note[2] + transpose, 0.085, 1650.0, 5.0, 0.002, 0.1, 1.2)
				synth.pluck(buf, at + 2 * bar + 10 * step, step * 3, 77 + transpose, 0.055, 15.0, 5.0)
				synth.pluck(buf, at + 2 * bar + 14 * step, step * 2, 74 + transpose, 0.06, 18.0, 5.0)
			synth.echo(buf, step * 3, 0.22, 0.20, 0.6)
			synth.pump(buf, beat, 0.4, 0.5)
			peak = 0.115
		&"perc":
			for b in bars:
				for s in 16:
					if s % 4 == 0:
						continue
					var hit_at := b * bar + s * step
					var gain: float = 0.11 * HAT_ACCENTS[s % 4] * random.randf_range(0.85, 1.0)
					if s == 6 or s == 14:
						synth.hat(buf, hit_at, gain, 13.0, 0.18)
					else:
						synth.hat(buf, hit_at, gain, 75.0, 0.05)
				if b % 4 == 3:
					for s in [11, 13, 15]:
						synth.tom(buf, b * bar + s * step, 0.07, 170.0 - s * 5.0, 75.0, 24.0, 0.12)
					if random.randf() < 0.65:
						synth.hat(buf, b * bar + 15 * step + step / 2, 0.07, 90.0, 0.035)
			for b in [0, 8]:
				synth.cymbal(buf, b * bar, 0.065, 6.0, 0.8)
			peak = 0.14
		&"tension":
			# Low, gated tension and two finite rises; no continuous high-frequency siren.
			for b in range(2, bars, 4):
				synth.bass_note(buf, b * bar + 6 * step, beat * 2, STAGE_ROOTS[b / 4] + 12, 0.065, 180.0, 1050.0, 3.0, 1.8, 2.0, 0.5)
			for b in [7, 15]:
				synth.riser(buf, b * bar + 8 * step, beat * 2, 0.13, 250.0, 3900.0)
			synth.pump(buf, beat, 0.65, 0.7)
			peak = 0.12
		&"boss_pad":
			_pad_voices(synth, buf, _four_bar_chords(BOSS_PADS), bar, 0.025, beat / 2, beat, 12.0)
			synth.sweep_lowpass(buf, 650.0, 230.0, 4.0)
			synth.pump(buf, beat, 0.7, 0.6)
			peak = 0.11
		&"boss_drive":
			for b in bars:
				var root: int = STAGE_ROOTS[b / 4]
				for s in 16:
					if s % 4 == 0:
						continue
					var offset := 12 if s % 4 == 3 else 0
					if b % 4 == 3 and s >= 12:
						offset += 7
					synth.bass_note(buf, b * bar + s * step, int(step * 0.83), root + offset, 0.15 if s % 4 == 2 else 0.10, 130.0, 1900.0 if b % 2 == 1 else 1150.0, 32.0, 2.7, 4.0, 0.45)
				if b % 4 == 3:
					for s in [10, 12, 14, 15]:
						synth.sample_hit(buf, b * bar + s * step, &"kick_heavy", 0.11, 1.15, 0, step - 60, false, 30)
				if b % 4 == 2:
					synth.lead_note(buf, b * bar + 10 * step, 2 * step, root + 24, 0.035, 1250.0, 10.0, 0.0, 0.4, 1.7)
			synth.pump(buf, beat, 0.8, 0.65)
			peak = 0.19
		&"breaks":
			# Measured eight-beat source follows the rounded destination grid, not nominal BPM.
			var bpm := MusicSynth.RATE * 60.0 / beat
			var rate := bpm / MusicSamples.BREAK_BPM
			var source_step := MusicSynth.RATE * 15.0 / MusicSamples.BREAK_BPM
			for b in bars:
				var at := b * bar
				if b % 4 == 2:
					synth.sample_hit(buf, at, &"break", 0.14, rate, roundi((b % 2) * 16 * source_step), bar, true, 40)
				elif b % 4 == 3:
					for s in 16:
						if s % 4 == 0:
							continue
						var chop: int = BREAK_CHOPS[random.randi_range(0, BREAK_CHOPS.size() - 1)]
						synth.sample_hit(buf, at + s * step, &"break", 0.14 if s % 4 == 2 else 0.09, rate, roundi(chop * source_step), step, true, 45)
				else:
					for s in [6, 14]:
						synth.sample_hit(buf, at + s * step, &"break", 0.085, rate, roundi(10 * source_step), step * 2, true, 45)
			synth.pump(buf, beat, 0.6, 0.6)
			peak = 0.16
		&"rave":
			for b in bars:
				if b % 4 != 1 and b % 4 != 3:
					continue
				var at := b * bar
				var rate := random.randf_range(0.88, 1.05)
				for s in [2, 10]:
					synth.sample_hit(buf, at + s * step, &"stab", 0.11, rate, 0, step * 2, false, 90)
				if b % 4 == 3:
					synth.sample_hit(buf, at + 14 * step, &"stab", 0.075, rate * 1.12, 0, step, false, 90)
			for b in [7, 15]:
				synth.sample_hit(buf, b * bar + 12 * step, &"fx", 0.075, 0.9, 0, beat, false, 120)
			synth.echo(buf, step * 3, 0.16, 0.14, 0.65)
			synth.pump(buf, beat, 0.7, 0.6)
			peak = 0.15
		&"vocals":
			# Six short callouts per 16-bar loop leave space for full gameplay speech.
			for k in VOCAL_KEYS.size():
				var at: int = VOCAL_BARS[k] * bar + 10 * step
				var key: StringName = VOCAL_KEYS[k]
				var rate := random.randf_range(0.94, 1.08)
				var length := beat * 3 if k == 0 or k == 2 else beat * 2
				synth.sample_hit(buf, at, key, 0.3, rate, 0, length, false, 110)
				if k == 1 or k == 3:
					synth.sample_hit(buf, at + 4 * step, key, 0.1, rate * 1.07, 0, step, false, 110)
			synth.pump(buf, beat, 0.3, 0.5)
			peak = 0.22
		_:
			return PackedFloat32Array()
	synth.normalize(buf, peak, false)
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

## Expands one chord per four bars into the full sixteen-bar phrase.
static func _four_bar_chords(chords: Array) -> Array:
	var result := []
	for chord in chords:
		for _bar in 4:
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
