class_name MusicComposition
extends RefCounted
## Built once per run, then shared read-only by all rendering workers.

const TEMPOS: Array[int] = [180, 186, 192, 198]
const TONIC_NAMES: Array[String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const MINOR_SCALE: Array[int] = [0, 2, 3, 5, 7, 8, 10]
# Scale degrees, not independently chosen chord roots: every phrase stays in one key.
const PROGRESSIONS: Array = [
	[0, 5, 2, 6, 0, 3, 5, 6], # i VI III VII / i iv VI VII
	[0, 3, 6, 0, 5, 3, 4, 0], # i iv VII i / VI iv v i
	[0, 6, 5, 6, 0, 2, 3, 4], # descending minor / i III iv v
	[0, 2, 6, 3, 0, 5, 3, 0],
	[0, 5, 3, 4, 0, 6, 2, 4],
	[0, 3, 0, 6, 5, 2, 4, 0],
]
const VOCAL_KEYS: Array[StringName] = [
	&"voice_fast", &"voice_hrrr", &"voice_ijee",
	&"voice_aaa", &"voice_chleba", &"voice_takhle",
]

var seed: int = 0
var genre: StringName = &"hardtek"
## Fixed, harmonically matched sample set; no mutable sample data in a score.
var techno_clips: Dictionary = {}
var loop_offsets: Dictionary = {}
var bpm: int = 186
var bars: int = 32
var step: int = 0
var key: int = 36
var roots: Array[int] = []
var pads: Array = []
var acid_pattern: PackedInt32Array = PackedInt32Array()
var hat_accents: PackedFloat32Array = PackedFloat32Array()
var sections: PackedInt32Array = PackedInt32Array()
# One fixed sound set per run; the full catalog is a selection pool, not a playlist.
var kick_clip: StringName = &""
var break_clip: StringName = &""
var acid_clip: StringName = &""
var fx_clip: StringName = &""
var ambient_clip: StringName = &""
var break_beat: float = 0.0
var acid_beat: float = 0.0
var ambient_position: float = 0.0
var fx_position: float = 0.0
var vocals: Array[StringName] = []
# Index modulo six selects vocals: each shuffled voice gets exactly two slots.
var vocal_bars: PackedInt32Array = PackedInt32Array()
var identity: String = ""

# Cancellation is the sole mutable worker-shared state.
var _cancellation_mutex: Mutex = Mutex.new()
var _cancelled: bool = false


func cancel() -> void:
	_cancellation_mutex.lock()
	_cancelled = true
	_cancellation_mutex.unlock()


func is_cancelled() -> bool:
	_cancellation_mutex.lock()
	var cancelled: bool = _cancelled
	_cancellation_mutex.unlock()
	return cancelled


static func build_hardtek(seed_value: int) -> MusicComposition:
	var result: MusicComposition = MusicComposition.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	result.seed = seed_value
	result.bpm = TEMPOS[random.randi_range(0, TEMPOS.size() - 1)]
	result.step = roundi(MusicSynth.RATE * 15.0 / float(result.bpm))

	var clips: Dictionary = MusicSamples.PACK.CLIPS
	var ids: Array = clips.keys()
	# Catalog insertion order must not influence seed reproducibility.
	ids.sort()
	var pools: Dictionary = {}
	var represented: Array[int] = []
	for value: Variant in ids:
		var id: StringName = StringName(value)
		var clip: Dictionary = clips[id]
		var role: StringName = StringName(clip["role"])
		if not pools.has(role):
			pools[role] = []
		pools[role].append(id)
		if role == &"kick":
			var tonic: int = int(clip["root"])
			if tonic >= 0 and not represented.has(tonic):
				represented.append(tonic)
	assert(not represented.is_empty(), "The pack must contain source-labelled tuned kicks")
	represented.sort()
	result.key = represented[random.randi_range(0, represented.size() - 1)]
	var tuned_kicks: Array[StringName] = []
	for id: StringName in pools[&"kick"]:
		if int(clips[id].root) == result.key:
			tuned_kicks.append(id)
	result.kick_clip = _pick(tuned_kicks, random)
	result.break_clip = _pick(pools[&"break"], random)
	result.acid_clip = _pick(pools[&"acid"], random)
	result.fx_clip = _pick(pools[&"fx"], random)
	result.ambient_clip = _pick(pools[&"ambient"], random)
	result.break_beat = random.randi_range(0, int(clips[result.break_clip].beats / 8) - 1) * 8.0
	result.acid_beat = random.randi_range(0, int(clips[result.acid_clip].beats / 8) - 1) * 8.0
	result.ambient_position = random.randf()
	result.fx_position = random.randf()

	var progression: Array = PROGRESSIONS[random.randi_range(0, PROGRESSIONS.size() - 1)]
	var pad_register: int = random.randi_range(1, 2) * 12
	for phrase: int in 8:
		var degree: int = int(progression[phrase])
		result.roots.append(result.key + MINOR_SCALE[degree])
		var pad: Array[int] = []
		# Diatonic sevenths and doubled-root triads are both minor-key compatible.
		var fourth_degree: int = degree + (6 if random.randf() < 0.5 else 7)
		var chord_degrees: Array[int] = [degree, degree + 2, degree + 4, fourth_degree]
		for chord_degree: int in chord_degrees:
			pad.append(result.key + pad_register + _scale_note(chord_degree))
		var inversion: int = random.randi_range(0, 2)
		for voice: int in inversion:
			pad[voice] += 12
		pad.sort()
		result.pads.append(pad)

	# Semitone offsets drawn from the shared tonic's minor scale.
	var acid_degrees: Array[int] = [0, 0, 0, 2, 4, 4, 6, 7]
	for sixteenth: int in 16:
		var degree: int = acid_degrees[random.randi_range(0, acid_degrees.size() - 1)]
		if sixteenth % 4 == 0:
			degree = 0 if random.randf() < 0.75 else 7
		result.acid_pattern.append(_scale_note(degree))
		var accent: float = random.randf_range(0.35, 0.68)
		if sixteenth % 4 == 2:
			accent = random.randf_range(0.82, 1.0)
		elif sixteenth % 4 == 0:
			accent = random.randf_range(0.48, 0.76)
		result.hat_accents.append(accent)

	# A shaped arrangement: opening, climb, relief and a dense final return.
	var density_shapes: Array = [
		[0, 1, 2, 3, 0, 2, 3, 3],
		[1, 1, 3, 2, 0, 1, 2, 3],
		[0, 2, 1, 3, 1, 0, 3, 2],
		[1, 2, 3, 1, 0, 2, 2, 3],
	]
	var density: Array = density_shapes[random.randi_range(0, density_shapes.size() - 1)]
	for mode: Variant in density:
		result.sections.append(int(mode))
	result.vocals.assign(VOCAL_KEYS)
	_shuffle(result.vocals, random)
	# Twelve onsets with at least two bars between them. Distribute the nine
	# spare bars among the leading, internal and trailing gaps, without retries.
	var spare: Array[int] = []
	spare.resize(13)
	spare.fill(0)
	for unused_bar: int in 9:
		var gap: int = random.randi_range(0, 12)
		spare[gap] += 1
	var vocal_bar: int = spare[0]
	for slot: int in 12:
		result.vocal_bars.append(vocal_bar)
		if slot < 11:
			vocal_bar += 2 + spare[slot + 1]

	result.identity = "%06X · %s minor · %d" % [random.randi() & 0xFFFFFF, TONIC_NAMES[result.key - 36], result.bpm]
	return result

## Techno keeps the sampled phrases in their labelled minor key. Its motion
## comes from phrase entrances, rests and percussion, not repitched chord loops.
static func build(seed_value: int) -> MusicComposition:
	var result := MusicComposition.new()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	result.seed = seed_value
	result.genre = &"techno"
	result.bpm = 125
	result.step = MusicScore.step_samples(result.bpm)
	var clips: Dictionary = MusicSamples.TECHNO.CLIPS
	var ids: Array = clips.keys()
	ids.sort()
	var keys: Array[int] = []
	for id: StringName in ids:
		if StringName(clips[id].role) == &"bass" and not keys.has(int(clips[id].root)):
			keys.append(int(clips[id].root))
	var matched: Array[int] = []
	for key_value: int in keys:
		var roles: Array[StringName] = []
		for id: StringName in ids:
			if int(clips[id].root) == key_value:
				roles.append(StringName(clips[id].role))
		if roles.has(&"synth") and roles.has(&"arp"):
			matched.append(key_value)
	assert(not matched.is_empty(), "Techno needs a matched bass/synth/arp minor-key set")
	matched.sort()
	result.key = matched[random.randi_range(0, matched.size() - 1)]
	for role: StringName in [&"kick", &"clap", &"hat", &"groove", &"bass", &"synth", &"arp", &"ambient"]:
		var pool: Array[StringName] = []
		for id: StringName in ids:
			var clip: Dictionary = clips[id]
			if StringName(clip.role) != role:
				continue
			if role in [&"bass", &"synth", &"arp", &"ambient"] and int(clip.root) != result.key:
				continue
			pool.append(id)
		assert(not pool.is_empty(), "Techno sample role missing: %s" % role)
		var selected := _pick(pool, random)
		result.techno_clips[role] = selected
		var beats := float(clips[selected].beats)
		result.loop_offsets[role] = random.randi_range(0, maxi(0, floori(beats / 4.0) - 1)) * 4.0
	var shapes: Array = [
		[0, 1, 2, 3, 0, 2, 3, 2], [1, 0, 2, 3, 1, 2, 0, 3],
		[0, 2, 1, 3, 0, 1, 3, 2], [1, 2, 0, 3, 1, 0, 2, 3],
	]
	for section: int in shapes[random.randi_range(0, shapes.size() - 1)]:
		result.sections.append(section)
	for sixteenth: int in 16:
		result.hat_accents.append(random.randf_range(0.65, 1.0))
	result.identity = "%06X · %s minor · %d" % [random.randi() & 0xFFFFFF, TONIC_NAMES[result.key - 36], result.bpm]
	result.techno_clips.make_read_only()
	result.loop_offsets.make_read_only()
	return result


static func _pick(values: Array, random: RandomNumberGenerator) -> StringName:
	return StringName(values[random.randi_range(0, values.size() - 1)])


static func _scale_note(degree: int) -> int:
	return MINOR_SCALE[posmod(degree, 7)] + floori(float(degree) / 7.0) * 12


static func _shuffle(values: Array, random: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = random.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[other]
		values[other] = previous
