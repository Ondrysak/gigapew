extends Node
## Adaptive procedural soundtrack, registered as the `Music` autoload.
## Sample-backed hardtek stems and original stingers render on worker threads.
## Stems start under the audio lock; gameplay changes gains, not sample buffers.
## Boss/extraction changes and short vocal accents land on musical boundaries.
## Spoken Luďas reactions take precedence over the chopped vocal layer.

const BUS := &"Music"
## Seconds for a full track crossfade.
const TRACK_FADE := 1.6
## Smoothing time constants (seconds) for rising and falling intensity.
const INTENSITY_ATTACK := 0.9
const INTENSITY_RELEASE := 3.0
## Seconds of the boss crossfade; it is timed to land on the next bar line.
const BOSS_FADE := 0.4
const STINGER_VOLUME_DB := -1.0
const SILENT_DB := -80.0

## Priority, original recording, playback rate. Events queue at most one accent.
const ACCENTS := {
	&"salvage": [1, preload("res://assets/voice/ludas/chleba.wav"), 1.0],
	&"combo": [2, preload("res://assets/voice/ludas/ijee_haa.wav"), 1.08],
	&"danger": [3, preload("res://assets/voice/ludas/hrrr.wav"), 0.92],
	&"extraction": [4, preload("res://assets/voice/ludas/plna_rychlost.wav"), 1.04],
}

class Track:
	var id: StringName
	var stems: Array[StringName] = []
	var players: Array[AudioStreamPlayer] = []
	var rendered := 0
	var fade := 0.0
	var fade_target := 0.0
	var fade_rate := 1.0
	var playing := false
	func is_ready() -> bool:
		return rendered == stems.size()

## Caller-owned HUD snapshot. Gains show routed layers; RMS shows actual PCM
## activity before bus effects, including track fades and bus volumes.
class MixMeter:
	var gains: Array[float] = []
	var rms: Array[float] = []
	var rendered := 0
	var playing := false
	var muted := false
	var position := 0.0
	var seed := 0
	var bpm := 0
	var bars := 0
	var bar_seconds := 0.0
	var identity := ""
	var tonic := ""
	var accent_gain := 0.0
	var accent_rms := 0.0
	var accent: StringName = &""
	var voice: StringName = &""
	var stingers: Array[StringName] = []

	func _init() -> void:
		gains.resize(MusicScore.TRACK_STEMS[&"stage"].size())
		gains.fill(0.0)
		rms.resize(gains.size())
		rms.fill(0.0)


var _tracks: Dictionary = {}
var _stingers: Dictionary = {}
var _current := &""
var _intensity := 0.0
var _target_intensity := 0.0
var _boss := false
var _boss_mix := 0.0
var _boss_switch_at := 0.0
var _clock := 0.0
var _last_ticks := 0
var _render_usec := 0
## Pending [track, stem, generation, composition] jobs, protected by _mutex.
var _jobs: Array = []
var _mutex := Mutex.new()
var _work_ready := Semaphore.new()
var _threads: Array[Thread] = []
var _sample_bank: Dictionary = {}
var _composition: MusicComposition
var _generation := 0
var _mix_identity := ""
var _mix_tonic := ""
var _mining := 0.0
var _mining_target := 0.0
var _voice_source: WeakRef
var _voice_mix := 0.0
var _accent_player: AudioStreamPlayer
var _pending_accent: StringName = &""
var _accent_at := 0.0
var _accent_expires := 0.0
var _accent_cooldown := 0.0
var _playing_accent: StringName = &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MusicSynth.cancelled = false
	_sample_bank = MusicSamples.load_bank()
	if _sample_bank.is_empty():
		return
	_accent_player = _make_player("GameplayVocal")
	_accent_player.volume_db = -4.0
	for track: StringName in MusicScore.TRACK_STEMS:
		var state := Track.new()
		state.id = track
		for stem: StringName in MusicScore.TRACK_STEMS[track]:
			state.stems.append(stem)
			state.players.append(_make_player("%s_%s" % [track, stem]))
			if track != &"stage":
				_jobs.append([track, stem, 0, null])
		_tracks[track] = state
	for stinger_name: StringName in MusicScore.STINGERS:
		var player := _make_player("stinger_%s" % stinger_name)
		player.volume_db = STINGER_VOLUME_DB
		_stingers[stinger_name] = player
		_jobs.append([MusicScore.STINGER_TRACK, stinger_name, 0, null])
	_last_ticks = Time.get_ticks_usec()
	for _worker in clampi(OS.get_processor_count() - 2, 1, 3):
		var thread := Thread.new()
		thread.start(_render_worker, Thread.PRIORITY_LOW)
		_threads.append(thread)
	for _job in _jobs.size():
		_work_ready.post()

func _exit_tree() -> void:
	MusicSynth.cancelled = true
	if _composition != null:
		_composition.cancel()
	for _thread in _threads:
		_work_ready.post()
	for thread in _threads:
		thread.wait_to_finish()
	_threads.clear()

## One fresh shared score per actual new run, never per sector load.
## Cancel obsolete work and reject its deferred results after rapid restarts.
func new_run(seed_value: int = -1) -> void:
	if _composition != null:
		_composition.cancel()
	var state: Track = _tracks[&"stage"]
	_halt(state)
	state.rendered = 0
	for player in state.players:
		player.stream = null
	if _current == &"stage":
		_current = &""
	_composition = MusicComposition.build(seed_value if seed_value >= 0 else Time.get_ticks_usec())
	_mix_identity = _composition.identity.get_slice(" · ", 0)
	_mix_tonic = MusicComposition.TONIC_NAMES[_composition.key - 36]
	_intensity = 0.0
	_target_intensity = 0.12
	_boss = false
	_boss_mix = 0.0
	_boss_switch_at = _clock
	_mining = 0.0
	_mining_target = 0.0
	_pending_accent = &""
	_accent_cooldown = 0.0
	_accent_player.stop()
	for player: AudioStreamPlayer in _stingers.values():
		player.stop()
	_mutex.lock()
	_generation += 1
	for i in range(_jobs.size() - 1, -1, -1):
		if _jobs[i][0] == &"stage":
			_jobs.remove_at(i)
	for stem in state.stems:
		_jobs.append([&"stage", stem, _generation, _composition])
	_mutex.unlock()
	for _stem in state.stems:
		_work_ready.post()

## Plays a track (&"menu" or &"stage"), crossfading from whatever plays. Replaying the current
## track is a no-op; a track still rendering starts as soon as it is ready. Intensity and boss
## targets reset to calm for the new track.
func play(track: StringName) -> void:
	if track == _current:
		return
	var state: Track = _tracks.get(track)
	if state == null:
		push_warning("Music: unknown track '%s'" % track)
		return
	_current = track
	_target_intensity = 0.0
	_boss = false
	_boss_switch_at = _clock
	if state.is_ready():
		_fade_out_all(1.0 / TRACK_FADE)
		_start(state)
	else:
		_prioritize(track)

## Combat density 0..1; stage layers follow it with seconds-scale smoothing.
func set_intensity(value: float) -> void:
	_target_intensity = clampf(value, 0.0, 1.0)

## Actual held-F contact/resonance, not merely proximity to a cabinet.
func set_mining(value: float) -> void:
	_mining_target = clampf(value, 0.0, 1.0)

## A weak reference survives scene changes without retaining a departed game.
func follow_voice(source: LudasVoice) -> void:
	_voice_source = weakref(source)

## Cooldown and priority bound chatter during fused kills or rapid salvage.
func accent(kind: StringName) -> void:
	if _current != &"stage" or not ACCENTS.has(kind):
		return
	if _pending_accent != &"" and int(ACCENTS[kind][0]) < int(ACCENTS[_pending_accent][0]):
		return
	_pending_accent = kind
	_accent_at = _clock + _time_to_next_beat()
	_accent_expires = _clock + MusicScore.bar_seconds(&"stage", _composition) * 4.0

## Swaps to boss layers on the next bar, retaining the run's shared harmony.
func set_boss(active: bool) -> void:
	if active == _boss:
		return
	_boss = active
	_boss_switch_at = _clock + maxf(_time_to_next_bar() - BOSS_FADE * 0.75, 0.0)

## One-shot over the music: &"level_up", &"stage_clear", &"death" or &"run_complete".
## Ignored while it is still rendering.
func stinger(stinger_name: StringName) -> void:
	var player: AudioStreamPlayer = _stingers.get(stinger_name)
	if player == null:
		push_warning("Music: unknown stinger '%s'" % stinger_name)
		return
	if stinger_name in [&"stage_clear", &"death", &"run_complete"]:
		_pending_accent = &""
		_accent_player.stop()
		_mining = 0.0
		_mining_target = 0.0
	if player.stream == null:
		return
	player.play()

## Fades out every track over `fade` seconds (0 stops at once).
func stop(fade := 1.0) -> void:
	_current = &""
	_target_intensity = 0.0
	_mining = 0.0
	_mining_target = 0.0
	_pending_accent = &""
	_accent_player.stop()
	if fade <= 0.0:
		for state: Track in _tracks.values():
			_halt(state)
	else:
		_fade_out_all(1.0 / fade)

## Read-only, bounded sampling of the native mono PCM16 players; call at 20 Hz.
## Does not add audio buses/effects, alter playback or allocate per-stem buffers.
func sample_mix(meter: MixMeter) -> void:
	var state: Track = _tracks[&"stage"]
	var bus_gain := _meter_bus_gain(BUS)
	var clock_offset := AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	meter.rendered = state.rendered
	meter.playing = state.playing
	meter.muted = bus_gain <= 0.0001
	meter.position = 0.0
	meter.seed = _composition.seed if _composition != null else 0
	meter.bpm = _composition.bpm if _composition != null else 0
	meter.bars = _composition.bars if _composition != null else 0
	meter.bar_seconds = MusicScore.bar_seconds(&"stage", _composition)
	meter.identity = _mix_identity
	meter.tonic = _mix_tonic
	if state.playing:
		var loop_seconds := meter.bar_seconds * meter.bars
		meter.position = fposmod(state.players[0].get_playback_position() + clock_offset, loop_seconds)
	for i in state.players.size():
		var player := state.players[i]
		var gain := db_to_linear(player.volume_db) * bus_gain if player.playing and player.volume_db > SILENT_DB else 0.0
		meter.gains[i] = gain
		meter.rms[i] = _meter_pcm(player, gain, clock_offset) if gain > 0.0001 else 0.0
	meter.accent_gain = db_to_linear(_accent_player.volume_db) * bus_gain if _accent_player.playing else 0.0
	meter.accent_rms = _meter_pcm(_accent_player, meter.accent_gain, clock_offset) if meter.accent_gain > 0.0001 else 0.0
	meter.accent = _playing_accent if _accent_player.playing else &""
	var source: LudasVoice = _voice_source.get_ref() as LudasVoice if _voice_source != null else null
	meter.voice = source.speaking if source != null else &""
	meter.stingers.clear()
	if not meter.muted:
		for id: StringName in _stingers:
			var player: AudioStreamPlayer = _stingers[id]
			if player.playing:
				meter.stingers.append(id)


func _meter_bus_gain(bus_name: StringName) -> float:
	var gain := 1.0
	var bus := AudioServer.get_bus_index(bus_name)
	while bus >= 0:
		if AudioServer.is_bus_mute(bus):
			return 0.0
		gain *= db_to_linear(AudioServer.get_bus_volume_db(bus))
		if bus == 0:
			break
		bus = AudioServer.get_bus_index(AudioServer.get_bus_send(bus))
	return gain


func _meter_pcm(player: AudioStreamPlayer, gain: float, clock_offset: float) -> float:
	var stream := player.stream as AudioStreamWAV
	# All synthesized stems/stingers and selected accent imports are mono PCM16.
	var data := stream.data
	var frames := data.size() / 2
	var cursor := floori((player.get_playback_position() + clock_offset * player.pitch_scale) * stream.mix_rate)
	var stride := maxi(1, roundi(stream.mix_rate * player.pitch_scale * 0.046 / 128.0))
	var energy := 0.0
	# 46 ms trailing window, decimated to 128 readings. Silence between notes
	# stays silence; loops wrap, whereas one-shots never borrow their end tail.
	for sample in 128:
		var frame := cursor - sample * stride
		if stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			frame = posmod(frame, frames)
		elif frame < 0 or frame >= frames:
			continue
		var value := data.decode_s16(frame * 2) / 32768.0
		energy += value * value
	return sqrt(energy / 128.0) * gain

func _process(_delta: float) -> void:
	# Real time, so fades ignore Engine.time_scale and pauses.
	var ticks := Time.get_ticks_usec()
	var dt := minf((ticks - _last_ticks) / 1000000.0, 0.1)
	_last_ticks = ticks
	_clock += dt
	var smoothing := INTENSITY_ATTACK if _target_intensity > _intensity else INTENSITY_RELEASE
	_mining = move_toward(_mining, _mining_target, dt * 4.0)
	_intensity += (_target_intensity - _intensity) * (1.0 - exp(-dt / smoothing))
	if _clock >= _boss_switch_at:
		_boss_mix = move_toward(_boss_mix, 1.0 if _boss else 0.0, dt / BOSS_FADE)
	var source: LudasVoice = _voice_source.get_ref() as LudasVoice if _voice_source != null else null
	var speaking := source != null and source.speaking != &""
	_voice_mix = move_toward(_voice_mix, 1.0 if speaking else 0.0, dt * 8.0)
	_update_accent(speaking)
	for track: StringName in _tracks:
		var state: Track = _tracks[track]
		if not state.playing:
			continue
		state.fade = move_toward(state.fade, state.fade_target, dt * state.fade_rate)
		if state.fade <= 0.0 and state.fade_target <= 0.0:
			_halt(state)
		else:
			_apply_volumes(state)

## Stage layer automation by smoothed intensity and boss blend.
func _stem_gain(track: StringName, stem: StringName) -> float:
	if track != &"stage":
		return 1.0
	var level := _intensity
	var boss := _boss_mix
	var calm := 1.0 - boss
	match stem:
		&"pad":
			return calm * lerpf(0.5, 0.25, level)
		&"pulse":
			return calm * (1.0 - 0.6 * smoothstep(0.25, 0.65, level))
		&"drums":
			return maxf(0.45 + 0.55 * smoothstep(0.12, 0.55, level), maxf(boss, _mining * 0.8))
		&"drive":
			return calm * maxf(smoothstep(0.2, 0.65, level), _mining * 0.75)
		&"arp":
			return calm * smoothstep(0.38, 0.75, level) * 0.75
		&"lead":
			return calm * smoothstep(0.72, 0.92, level) * 0.75
		&"perc":
			return maxf(smoothstep(0.3, 0.72, level), boss * 0.85)
		&"tension":
			return maxf(smoothstep(0.8, 0.98, level), 0.6 * boss)
		&"boss_pad":
			return boss * 0.65
		&"boss_drive":
			return boss
		&"breaks":
			return maxf(smoothstep(0.45, 0.88, level), boss) * 0.65
		&"rave":
			return maxf(smoothstep(0.58, 0.9, level), boss * 0.9) * 0.7
		&"vocals":
			return maxf(maxf(smoothstep(0.25, 0.65, level), _mining * 0.75), boss * 0.75) * (1.0 - _voice_mix)
	return 1.0

func _apply_volumes(state: Track) -> void:
	var level := smoothstep(0.0, 1.0, state.fade)
	if state.id == &"stage":
		# Keep backing gain steady through speech, effects, cues and pause.
		level *= 0.8
	for i in state.players.size():
		var gain := level * _stem_gain(state.id, state.stems[i])
		state.players[i].volume_db = linear_to_db(gain) if gain > 0.0001 else SILENT_DB

func _start(state: Track) -> void:
	state.fade_target = 1.0
	state.fade_rate = 1.0 / TRACK_FADE
	if state.playing:
		return
	state.fade = 0.0
	_apply_volumes(state)
	# Holding the audio lock makes every stem begin on the same mix, sample-aligned.
	AudioServer.lock()
	for player in state.players:
		player.play()
	AudioServer.unlock()
	state.playing = true

func _halt(state: Track) -> void:
	for player in state.players:
		player.stop()
	state.playing = false
	state.fade = 0.0
	state.fade_target = 0.0

func _fade_out_all(rate: float) -> void:
	for state: Track in _tracks.values():
		if state.playing:
			state.fade_target = 0.0
			state.fade_rate = rate

func _time_to_next_bar() -> float:
	var state: Track = _tracks.get(_current)
	if state == null or not state.playing:
		return 0.0
	var bar := MusicScore.bar_seconds(state.id, _composition)
	var position := state.players[0].get_playback_position() + AudioServer.get_time_since_last_mix()
	return bar - fmod(position, bar)


func _time_to_next_beat() -> float:
	var state: Track = _tracks.get(_current)
	if state == null or not state.playing:
		return 0.0
	var beat := MusicScore.bar_seconds(state.id, _composition) * 0.25
	var position := state.players[0].get_playback_position() + AudioServer.get_time_since_last_mix()
	return beat - fmod(position, beat)

func _update_accent(speaking: bool) -> void:
	if get_tree().paused:
		_pending_accent = &""
		if _accent_player.playing:
			_accent_player.stop()
		return
	if _pending_accent == &"":
		return
	if _clock > _accent_expires or _current != &"stage":
		_pending_accent = &""
		return
	var state: Track = _tracks[&"stage"]
	if not state.playing or speaking or _accent_player.playing or _clock < _accent_cooldown:
		return
	if _clock < _accent_at:
		return
	# Requantize after speech/cooldown instead of firing halfway through a beat.
	if _clock - _accent_at > 0.08:
		_accent_at = _clock + _time_to_next_beat()
		return
	var definition: Array = ACCENTS[_pending_accent]
	_accent_player.stream = definition[1]
	_playing_accent = _pending_accent
	_accent_player.pitch_scale = float(definition[2])
	_accent_player.play()
	_accent_cooldown = _clock + MusicScore.bar_seconds(&"stage", _composition) * 2.0
	_pending_accent = &""

func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = BUS
	player.volume_db = SILENT_DB
	add_child(player)
	return player

## Moves the jobs of `track` to the front of the render queue.
func _prioritize(track: StringName) -> void:
	_mutex.lock()
	var first: Array = []
	var rest: Array = []
	for job: Array in _jobs:
		if job[0] == track:
			first.append(job)
		else:
			rest.append(job)
	_jobs = first + rest
	_mutex.unlock()

# Persistent worker: waits for jobs and exits only when the game quits.
func _render_worker() -> void:
	var synth := MusicSynth.new(1337, _sample_bank)
	while true:
		_work_ready.wait()
		if MusicSynth.cancelled:
			return
		_mutex.lock()
		var job: Array = [] if _jobs.is_empty() else _jobs.pop_front()
		_mutex.unlock()
		if job.is_empty():
			continue
		var composition: MusicComposition = job[3]
		if composition != null and composition.is_cancelled():
			continue
		var begin := Time.get_ticks_usec()
		var stream := MusicScore.render(synth, job[0], job[1], composition)
		if stream != null:
			_on_stem_rendered.call_deferred(job[0], job[1], stream, Time.get_ticks_usec() - begin, job[2])

func _on_stem_rendered(track: StringName, stem: StringName, stream: AudioStreamWAV, usec: int, generation: int) -> void:
	if track == &"stage" and generation != _generation:
		return
	_render_usec += usec
	if track == MusicScore.STINGER_TRACK:
		(_stingers[stem] as AudioStreamPlayer).stream = stream
		return
	var state: Track = _tracks[track]
	state.players[state.stems.find(stem)].stream = stream
	state.rendered += 1
	if not state.is_ready():
		return
	print_verbose("Music: '%s' ready (render CPU so far %.2f s)" % [track, _render_usec / 1000000.0])
	if track == _current:
		_fade_out_all(1.0 / TRACK_FADE)
		_start(state)
