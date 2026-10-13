extends LabScenario

func title() -> String:
	return "Techno stages and hardtek bosses"

func summary() -> String:
	return "Real sample PCM, boss tempo switch and return, live HUD/beat clocks, no duck, mute, fresh-run cancellation and stage persistence"

func run() -> void:
	var game := await lab.start_game(&"driller", 0, true, 8721)
	game.horde.target = null
	game.voice.stop()
	var meter = Music.MixMeter.new()
	var panel: MusicLayers = game.hud.get_node("MusicLayers")
	var master := AudioServer.get_bus_index(&"Master")
	var music := AudioServer.get_bus_index(&"Music")
	var saved_master_mute := AudioServer.is_bus_mute(master)
	var saved_music_mute := AudioServer.is_bus_mute(music)
	var saved_master_db := AudioServer.get_bus_volume_db(master)
	var saved_music_db := AudioServer.get_bus_volume_db(music)
	# Dummy remains the lab's audio driver. Unmute routing to inspect real PCM
	# and gameplay timing without making debug runs audible on the host.
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_mute(music, false)
	AudioServer.set_bus_volume_db(master, 0.0)
	AudioServer.set_bus_volume_db(music, 0.0)
	if await _wait_track(meter, &"stage"):
		await lab.wait(2.0)
		Music.sample_mix(meter)
		var kick: int = meter.stems.find(&"kick")
		var synth: int = meter.stems.find(&"synth")
		var stage_pcm := _fingerprint(&"stage")
		var techno_period := Music.beat_seconds()
		lab.check(meter.genre == &"techno" and meter.bpm == 125 and absf(techno_period - 0.48) < 0.001 and Music.beat_phase() >= 0.0, "normal gameplay exposes the actual 125 BPM techno beat to DROP")
		lab.check(_matches_techno_kick() and _hud_live(panel, meter), "rendered techno retains the purchased waveform and the visible HUD follows its playback")
		var note_peak := 0.0
		var rest_min := INF
		var kick_peak := 0.0
		for sample in ceili(meter.bar_seconds * meter.bars / 0.05):
			Music.sample_mix(meter)
			note_peak = maxf(note_peak, meter.rms[synth])
			rest_min = minf(rest_min, meter.rms[synth])
			kick_peak = maxf(kick_peak, meter.rms[kick])
			if note_peak > 0.003 and rest_min < 0.0001 and kick_peak > 0.02:
				break
			await lab.wait(0.05)
		lab.check(note_peak > 0.003 and rest_min < 0.0001 and kick_peak > 0.02, "sampled techno phrases have audible notes and genuine PCM rests, not invented meter animation")
		await lab.capture("techno_samples")
		Music.sample_mix(meter)
		var full_gain: float = meter.gains[kick]
		lab.fire(true)
		await lab.wait(0.35)
		lab.fire(false)
		Music.sample_mix(meter)
		lab.check(is_equal_approx(meter.gains[kick], full_gain), "real gun effects do not duck techno backing")
		game.voice.say(&"skill")
		await lab.wait(0.2)
		Music.sample_mix(meter)
		lab.check(meter.voice == &"skill" and is_equal_approx(meter.gains[kick], full_gain), "spoken voice does not duck techno backing")
		game.voice.stop()
		game.get_tree().paused = true
		Music.sample_mix(meter)
		var position: float = meter.position
		var visible_position: float = panel._meter.position
		await lab.wait(0.3)
		Music.sample_mix(meter)
		lab.check(Music.beat_phase() < 0.0 and fposmod(meter.position - position, meter.bar_seconds * meter.bars) > 0.1 and fposmod(panel._meter.position - visible_position, meter.bar_seconds * meter.bars) > 0.1 and is_equal_approx(meter.gains[kick], full_gain), "pause keeps techno audio and HUD clocks live without ducking, while gameplay timing is unavailable")
		await lab.capture("pause_music_live")
		game.get_tree().paused = false
		for cue: StringName in MusicScore.STINGERS:
			for attempt in 100:
				Music.stinger(cue)
				await lab.wait(0.05)
				Music.sample_mix(meter)
				if meter.stingers.has(cue):
					break
			lab.check(meter.stingers.has(cue) and is_equal_approx(meter.gains[kick], full_gain), "%s plays over unchanged techno backing" % cue)
		Music.accent(&"drop")
		var heard_accent := false
		for attempt in 30:
			await lab.wait(0.05)
			Music.sample_mix(meter)
			if meter.accent == &"drop" and meter.accent_rms > 0.001:
				heard_accent = is_equal_approx(meter.gains[kick], full_gain)
				break
		lab.check(heard_accent, "beat-quantized DROP vocal plays over steady techno backing")
		for bus in [music, master]:
			AudioServer.set_bus_mute(bus, true)
			await lab.wait(0.15)
			Music.sample_mix(meter)
			lab.check(meter.muted and meter.gains.max() == 0.0 and meter.rms.max() == 0.0 and panel._bars.max() == 0.0 and Music.beat_phase() < 0.0, "%s mute clears source/HUD meters and disables DROP timing" % AudioServer.get_bus_name(bus))
			AudioServer.set_bus_mute(bus, false)
		# Real director admission emits the same signal as final crowd cleanup.
		var released := false
		for attempt in 50:
			released = game.director.release_boss()
			if released:
				break
			await lab.wait(0.05)
		lab.check(released, "real encounter director admits its stage boss")
		var boss := game.horde.boss_index
		if released and await _wait_track(meter, &"boss"):
			await lab.wait(0.6)
			Music.sample_mix(meter)
			var boss_pcm := _fingerprint(&"boss")
			var drums: int = meter.stems.find(&"drums")
			lab.check(meter.genre == &"hardtek" and meter.bpm in MusicComposition.TEMPOS and Music.beat_seconds() < techno_period * 0.75 and Music.beat_phase() >= 0.0 and _hud_live(panel, meter), "real boss replaces techno with hardtek PCM, faster DROP timing and live HUD meters")
			lab.check(_pcm_energy(&"boss", &"drums") > 0.001 and _fingerprint(&"stage") == stage_pcm, "hardtek boss is audible and the run's techno score remains intact")
			await lab.capture("hardtek_boss")
			var boss_gain: float = meter.gains[drums]
			var spoken := game.voice.say(&"skill")
			# Gate smoothing advances on render frames, not the timer's wall time.
			for sample in 20:
				await lab.wait(0.05)
				Music.sample_mix(meter)
				if meter.voice == &"skill" and meter.gains[meter.stems.find(&"vocals")] == 0.0:
					break
			lab.check(spoken and meter.voice == &"skill" and meter.gains[meter.stems.find(&"vocals")] == 0.0 and is_equal_approx(meter.gains[drums], boss_gain), "boss speech clears only vocal chops, never hardtek backing (spoken %s, voice %s, vox %.4f, backing %.4f -> %.4f)" % [spoken, meter.voice, meter.gains[meter.stems.find(&"vocals")], boss_gain, meter.gains[drums]])
			game.voice.stop()
			game.horde.damage(boss, 1.0e9)
			if await _wait_track(meter, &"stage"):
				await lab.wait(0.6)
				Music.sample_mix(meter)
				lab.check(meter.bpm == 125 and absf(Music.beat_seconds() - techno_period) < 0.0001 and _fingerprint(&"stage") == stage_pcm and _hud_live(panel, meter), "real boss death returns to the same techno PCM, slow beat clock and techno HUD")
				await lab.capture("techno_return")
			game._load_stage(1, 8722)
			game.director.set_physics_process(false)
			await lab.wait(0.2)
			lab.check(_fingerprint(&"stage") == stage_pcm and _fingerprint(&"boss") == boss_pcm, "sector load preserves both rendered run scores")
			# An actual run restart followed by rapid superseding renders must
			# publish only the latest playable score, including the boss bank.
			game._new_run()
			await lab.frames(4)
			if game.round_state == ArenaGame.RoundState.DRAFT:
				game.weapon_draft.confirm()
			game.director.set_physics_process(false)
			Music.new_run(0x404)
			Music.play(&"stage")
			await lab.frames(2)
			Music.new_run(0x505)
			Music.play(&"stage")
			if await _wait_track(meter, &"stage"):
				for attempt in 600:
					if Music._tracks[&"boss"].is_ready():
						break
					await lab.wait(0.1)
				Music.sample_mix(meter)
				lab.check(meter.seed == 0x505 and _matches_techno_kick() and _fingerprint(&"stage") != stage_pcm and _fingerprint(&"boss") != boss_pcm, "rapid new runs publish fresh playable techno/hardtek PCM, rejecting obsolete worker results")
				var fresh_pcm := _fingerprint(&"stage")
				await lab.wait(1.0)
				Music.sample_mix(meter)
				lab.check(meter.playing and _fingerprint(&"stage") == fresh_pcm and _pcm_energy(&"stage", &"bass") > 0.001, "late obsolete callbacks cannot replace the current audible techno score")
				var fresh_boss := false
				for attempt in 50:
					fresh_boss = game.director.release_boss()
					if fresh_boss:
						break
					await lab.wait(0.05)
				if fresh_boss and await _wait_track(meter, &"boss"):
					lab.check(meter.seed == (0x505 ^ 0x48415244) and _pcm_energy(&"boss", &"drums") > 0.001 and _fingerprint(&"boss") != boss_pcm, "the latest run also publishes playable fresh hardtek, not an obsolete boss render")
					game.horde.damage(game.horde.boss_index, 1.0e9)
					await _wait_track(meter, &"stage")
				else:
					lab.check(false, "fresh run admits and plays its real boss")
				await lab.capture("fresh_run")
	AudioServer.set_bus_mute(master, saved_master_mute)
	AudioServer.set_bus_mute(music, saved_music_mute)
	AudioServer.set_bus_volume_db(master, saved_master_db)
	AudioServer.set_bus_volume_db(music, saved_music_db)

func _wait_track(meter, track: StringName) -> bool:
	for attempt in 600:
		Music.sample_mix(meter)
		if meter.playing and meter.track == track:
			return true
		await lab.wait(0.1)
	lab.check(false, "%s becomes playable through the real director" % track)
	return false

func _fingerprint(track: StringName) -> Array[int]:
	var result: Array[int] = []
	for player: AudioStreamPlayer in Music._tracks[track].players:
		result.append(hash(player.stream.data) if player.stream != null else 0)
	return result

func _pcm_energy(track: StringName, stem: StringName) -> float:
	var state = Music._tracks[track]
	var data: PackedByteArray = state.players[state.stems.find(stem)].stream.data
	var energy := 0.0
	var count := 0
	for frame in range(0, data.size() / 2, 43):
		var value := data.decode_s16(frame * 2) / 32768.0
		energy += value * value
		count += 1
	return sqrt(energy / maxi(1, count))

func _matches_techno_kick() -> bool:
	var key: StringName = Music._composition.techno_clips[&"kick"]
	var original: PackedByteArray = MusicSamples.TECHNO.CLIPS[key].stream.data
	var state = Music._tracks[&"stage"]
	var rendered: PackedByteArray = state.players[state.stems.find(&"kick")].stream.data
	var cross := 0.0
	var source_energy := 0.0
	var rendered_energy := 0.0
	# Exclude the render's edge envelope; compare the actual downbeat waveform.
	for frame in range(40, mini(original.size() / 2 - 40, Music._composition.step * 4 - 100), 3):
		var source := original.decode_s16(frame * 2) / 32768.0
		var target := rendered.decode_s16(frame * 2) / 32768.0
		cross += source * target
		source_energy += source * source
		rendered_energy += target * target
	return source_energy > 0.0 and rendered_energy > 0.0 and cross / sqrt(source_energy * rendered_energy) > 0.995

func _hud_live(panel: MusicLayers, meter) -> bool:
	return panel._timing.contains("%d BPM" % meter.bpm) and panel._bars.max() > 0.0
