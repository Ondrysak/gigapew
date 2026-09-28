extends Node
## Adaptive procedural soundtrack, registered as the `Music` autoload.
## Loop stems and stingers are synthesized on background threads (MusicScore + MusicSynth), so
## nothing heavy runs on the main thread. A track starts once all of its stems exist, with every
## stem started on the same audio mix so they stay sample-locked; gameplay then only moves
## volumes. set_intensity() fades stage layers in and out, set_boss() swaps to the boss layers
## on the next bar line, stinger() plays one-shots over the ducked music.

const BUS := &"Music"
## Seconds for a full track crossfade.
const TRACK_FADE := 1.6
## Smoothing time constants (seconds) for rising and falling intensity.
const INTENSITY_ATTACK := 0.9
const INTENSITY_RELEASE := 3.0
## Seconds of the boss crossfade; it is timed to land on the next bar line.
const BOSS_FADE := 0.4
## Stinger -> [music duck level, seconds held].
const STINGER_DUCK := {
	&"level_up": [0.7, 0.6],
	&"stage_clear": [0.35, 2.0],
	&"death": [0.3, 2.0],
	&"run_complete": [0.3, 3.6],
}
## Seconds for the music to come back after a stinger's duck.
const DUCK_RECOVER := 1.2
const STINGER_VOLUME_DB := -1.0
const SILENT_DB := -80.0

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

var _tracks: Dictionary = {}
var _stingers: Dictionary = {}
var _current := &""
var _intensity := 0.0
var _target_intensity := 0.0
var _boss := false
var _boss_mix := 0.0
var _boss_switch_at := 0.0
var _duck := 1.0
var _duck_floor := 1.0
var _duck_hold := 0.0
var _clock := 0.0
var _last_ticks := 0
var _render_usec := 0
## Pending [track, stem] render jobs, shared with the workers under _mutex.
var _jobs: Array = []
var _mutex := Mutex.new()
var _threads: Array[Thread] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MusicSynth.cancelled = false
	for track: StringName in MusicScore.TRACK_STEMS:
		var state := Track.new()
		state.id = track
		for stem: StringName in MusicScore.TRACK_STEMS[track]:
			state.stems.append(stem)
			state.players.append(_make_player("%s_%s" % [track, stem]))
			_jobs.append([track, stem])
		_tracks[track] = state
	for stinger_name: StringName in MusicScore.STINGERS:
		var player := _make_player("stinger_%s" % stinger_name)
		player.volume_db = STINGER_VOLUME_DB
		_stingers[stinger_name] = player
		_jobs.append([MusicScore.STINGER_TRACK, stinger_name])
	_last_ticks = Time.get_ticks_usec()
	for _worker in clampi(OS.get_processor_count() - 2, 1, 3):
		var thread := Thread.new()
		thread.start(_render_worker, Thread.PRIORITY_LOW)
		_threads.append(thread)

func _exit_tree() -> void:
	MusicSynth.cancelled = true
	for thread in _threads:
		thread.wait_to_finish()
	_threads.clear()

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
	_fade_out_all(1.0 / TRACK_FADE)
	_current = track
	_target_intensity = 0.0
	_boss = false
	_boss_switch_at = _clock
	if state.is_ready():
		_start(state)
	else:
		_prioritize(track)

## Combat density 0..1; stage layers follow it with seconds-scale smoothing.
func set_intensity(value: float) -> void:
	_target_intensity = clampf(value, 0.0, 1.0)

## Swaps the stage to its boss layers (and boss harmony), landing on the next bar line.
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
	if player.stream == null:
		return
	player.play()
	var duck: Array = STINGER_DUCK[stinger_name]
	_duck_floor = minf(_duck_floor, duck[0])
	_duck_hold = maxf(_duck_hold, duck[1])

## Fades out every track over `fade` seconds (0 stops at once).
func stop(fade := 1.0) -> void:
	_current = &""
	_target_intensity = 0.0
	if fade <= 0.0:
		for state: Track in _tracks.values():
			_halt(state)
	else:
		_fade_out_all(1.0 / fade)

func _process(_delta: float) -> void:
	# Real time, so fades ignore Engine.time_scale and pauses.
	var ticks := Time.get_ticks_usec()
	var dt := minf((ticks - _last_ticks) / 1000000.0, 0.1)
	_last_ticks = ticks
	_clock += dt
	var smoothing := INTENSITY_ATTACK if _target_intensity > _intensity else INTENSITY_RELEASE
	_intensity += (_target_intensity - _intensity) * (1.0 - exp(-dt / smoothing))
	if _clock >= _boss_switch_at:
		_boss_mix = move_toward(_boss_mix, 1.0 if _boss else 0.0, dt / BOSS_FADE)
	if _duck_hold > 0.0:
		_duck_hold -= dt
		_duck = move_toward(_duck, _duck_floor, dt * 6.0)
	else:
		_duck_floor = 1.0
		_duck = move_toward(_duck, 1.0, dt / DUCK_RECOVER)
	for state: Track in _tracks.values():
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
			return calm * (1.0 - 0.25 * smoothstep(0.5, 0.9, level))
		&"pulse":
			return calm * (1.0 - 0.5 * smoothstep(0.45, 0.65, level))
		&"drums":
			return maxf(smoothstep(0.18, 0.36, level), boss)
		&"drive":
			return calm * smoothstep(0.45, 0.62, level)
		&"arp":
			return calm * smoothstep(0.5, 0.68, level)
		&"lead":
			return calm * smoothstep(0.74, 0.9, level)
		&"perc":
			return maxf(smoothstep(0.7, 0.86, level), boss)
		&"tension":
			return maxf(smoothstep(0.78, 0.95, level), 0.85 * boss)
		&"boss_pad", &"boss_drive":
			return boss
	return 1.0

func _apply_volumes(state: Track) -> void:
	var level := smoothstep(0.0, 1.0, state.fade) * _duck
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
	var bar := MusicScore.bar_seconds(state.id)
	var position := state.players[0].get_playback_position() + AudioServer.get_time_since_last_mix()
	return bar - fmod(position, bar)

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

# Runs on a worker thread: renders queued stems until the queue is empty or the game quits.
func _render_worker() -> void:
	var synth := MusicSynth.new()
	while not MusicSynth.cancelled:
		_mutex.lock()
		var job: Array = [] if _jobs.is_empty() else _jobs.pop_front()
		_mutex.unlock()
		if job.is_empty():
			return
		var begin := Time.get_ticks_usec()
		var stream := MusicScore.render(synth, job[0], job[1])
		if stream == null:
			return
		_on_stem_rendered.call_deferred(job[0], job[1], stream, Time.get_ticks_usec() - begin)

func _on_stem_rendered(track: StringName, stem: StringName, stream: AudioStreamWAV, usec: int) -> void:
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
		_start(state)
