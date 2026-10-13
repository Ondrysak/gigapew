extends LabScenario

func title() -> String:
	return "Reactive soundtrack layers"

func summary() -> String:
	return "Actual PCM notes/rests, steady backing through FX/voice/cues/pause, mute, real fracture and fresh per-run compositions"

func run() -> void:
	var game := await lab.start_game(&"driller", 0, true, 8721)
	game.horde.target = null
	var meter = Music.MixMeter.new()
	var panel: MusicLayers = game.hud.get_node("MusicLayers")
	var master := AudioServer.get_bus_index(&"Master")
	var music := AudioServer.get_bus_index(&"Music")
	var saved_master_mute := AudioServer.is_bus_mute(master)
	var saved_music_mute := AudioServer.is_bus_mute(music)
	var saved_master_db := AudioServer.get_bus_volume_db(master)
	var saved_music_db := AudioServer.get_bus_volume_db(music)
	# This one scenario needs audible routing; restore the batch's mute afterwards.
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_mute(music, false)
	AudioServer.set_bus_volume_db(master, 0.0)
	AudioServer.set_bus_volume_db(music, 0.0)
	for attempt in 600:
		Music.sample_mix(meter)
		if meter.playing:
			break
		await lab.wait(0.1)
	lab.check(meter.playing, "generated stage score is ready for audio-boundary checks")
	if meter.playing:
		var drums: AudioStreamWAV = Music._tracks[&"stage"].players[2].stream
		lab.check(_consistent_kick(drums, Music._composition.step, meter.bars), "the actual kick waveform repeats throughout the run instead of changing sample each bar")
		game.voice.stop()
		await lab.wait(2.0)
		lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(0.0), 150, 0.0)
		await lab.wait(2.5)
		var vocal_min := 1.0
		var vocal_max := 0.0
		var kick_max := 0.0
		for sample in ceili(meter.bar_seconds * meter.bars / 0.05):
			Music.sample_mix(meter)
			vocal_min = minf(vocal_min, meter.rms[12])
			vocal_max = maxf(vocal_max, meter.rms[12])
			kick_max = maxf(kick_max, meter.rms[2])
			if vocal_max > 0.006 and vocal_min < 0.0001:
				break
			await lab.wait(0.05)
		lab.check(kick_max > 0.02 and vocal_max > 0.006 and vocal_min < 0.0001, "real PCM lights kicks/vocal notes but leaves vocal rests silent")
		await lab.capture("pressure")
		var full_gain: float = meter.gains[2]
		lab.fire(true)
		await lab.wait(0.35)
		lab.fire(false)
		Music.sample_mix(meter)
		lab.check(is_equal_approx(meter.gains[2], full_gain), "real weapon effects do not lower the backing kick gain")
		await lab.capture("weapon_fx")
		game.voice.say(&"skill")
		for sample in 20:
			await lab.wait(0.05)
			Music.sample_mix(meter)
			if meter.gains[12] == 0.0:
				break
		lab.check(meter.voice == &"skill" and meter.gains[12] == 0.0 and is_equal_approx(meter.gains[2], full_gain), "spoken voice clears remix vocals without lowering the backing kick gain")
		await lab.capture("speech_steady")
		game.voice.stop()
		await lab.wait(0.3)
		game.get_tree().paused = true
		await lab.wait(0.2)
		Music.sample_mix(meter)
		var position: float = meter.position
		var visual_position: float = panel._meter.position
		var phrase_seconds: float = meter.bar_seconds * meter.bars
		await lab.wait(0.2)
		Music.sample_mix(meter)
		lab.check(fposmod(meter.position - position, phrase_seconds) > 0.05 and fposmod(panel._meter.position - visual_position, phrase_seconds) > 0.05 and is_equal_approx(meter.gains[2], full_gain), "pause keeps audio/UI clocks alive at unchanged backing gain")
		await lab.capture("pause")
		game.get_tree().paused = false
		for stinger: StringName in MusicScore.STINGERS:
			for attempt in 100:
				Music.stinger(stinger)
				await lab.wait(0.05)
				Music.sample_mix(meter)
				if meter.stingers.has(stinger):
					break
			await lab.wait(0.15)
			Music.sample_mix(meter)
			lab.check(meter.stingers.has(stinger) and is_equal_approx(meter.gains[2], full_gain), "%s stinger plays without attenuating the backing" % stinger)
		await lab.capture("stingers_steady")
		for bus in [music, master]:
			AudioServer.set_bus_mute(bus, true)
			await lab.wait(0.15)
			Music.sample_mix(meter)
			lab.check(meter.muted and meter.gains.max() == 0.0 and meter.rms.max() == 0.0 and panel._bars.max() == 0.0, "%s mute clears routed/source levels and visible bars" % AudioServer.get_bus_name(bus))
			await lab.capture("mute_" + String(AudioServer.get_bus_name(bus)))
			AudioServer.set_bus_mute(bus, false)
		game.horde.clear()
		# Earlier weapon-effect kills leave real style pressure; begin salvage from a calm mix.
		game.player._reset_combo()
		# Exponential pressure release must fall below the normal acid threshold.
		await lab.wait(8.0)
		var deposit: MineralDeposit
		for node in game.deposits.get_children():
			if node is MineralDeposit and node.global_position.y < 2.4:
				deposit = node
				break
		var reached := deposit != null and await lab.aim_deposit(deposit, 2.2)
		lab.check(reached, "real machine compartment is reachable")
		if reached:
			await lab.wait(0.2)
			var before := deposit.health
			Music.sample_mix(meter)
			var idle_drive: float = meter.gains[3]
			var idle_kick: float = meter.gains[2]
			var peak_drive := idle_drive
			var saw_salvage := false
			var salvage_kick := INF
			# One fresh press: the short crowbar smash is the whole salvage contact.
			Input.action_press(&"mine")
			for sample in 7:
				await lab.wait(0.05)
				Music.sample_mix(meter)
				peak_drive = maxf(peak_drive, meter.gains[3])
				if meter.accent == &"salvage" and meter.accent_rms > 0.001:
					saw_salvage = true
					salvage_kick = minf(salvage_kick, meter.gains[2])
			Input.action_release(&"mine")
			lab.check(deposit.health < before and peak_drive > idle_drive + 0.02, "one fresh F smash opens a real compartment and its short contact audibly raises acid gain")
			await lab.capture("one_press_smash")
			await lab.wait(0.6)
			Music.sample_mix(meter)
			lab.check(meter.gains[3] <= idle_drive + 0.02, "acid salvage drive returns to the calm mix once the smash ends")
			# A beat-quantized 388 ms vocal may finish during the pry screenshot.
			# Observe it during contact too, rather than requiring it afterwards.
			for attempt in 50:
				if saw_salvage:
					break
				Music.sample_mix(meter)
				if meter.accent == &"salvage" and meter.accent_rms > 0.001:
					saw_salvage = true
					salvage_kick = minf(salvage_kick, meter.gains[2])
					break
				await lab.wait(0.05)
			# Pressure still releases normally; an event must not impose a duck.
			lab.check(saw_salvage and salvage_kick >= idle_kick * 0.9, "real salvage vocal accent plays without a backing-volume dip")
			await lab.capture("accent_steady")
		var previous_seed: int = meter.seed
		var previous_kick: int = hash(Music._tracks[&"stage"].players[2].stream.data)
		game._new_run()
		for attempt in 600:
			await lab.wait(0.1)
			if game.round_state == ArenaGame.RoundState.PLAYING:
				game.director.set_physics_process(false)
			Music.sample_mix(meter)
			if meter.playing:
				break
		lab.check(meter.playing and meter.seed != previous_seed and hash(Music._tracks[&"stage"].players[2].stream.data) != previous_kick, "actual new-run restart replaces the rendered kick music, not only a seed label")
		await lab.capture("fresh_run")
		var run_seed: int = meter.seed
		var run_kick: int = hash(Music._tracks[&"stage"].players[2].stream.data)
		game._load_stage(1, 8722)
		await lab.wait(0.2)
		Music.sample_mix(meter)
		lab.check(meter.seed == run_seed and hash(Music._tracks[&"stage"].players[2].stream.data) == run_kick, "sector transition preserves the run's sample-locked score")
		await lab.capture("same_mix_next_sector")
	AudioServer.set_bus_mute(master, saved_master_mute)
	AudioServer.set_bus_mute(music, saved_music_mute)
	AudioServer.set_bus_volume_db(master, saved_master_db)
	AudioServer.set_bus_volume_db(music, saved_music_db)


func _consistent_kick(wav: AudioStreamWAV, step: int, bars: int) -> bool:
	var data := wav.data
	# Before the first offbeat hat, only the downbeat kick is sounding.
	for bar in range(1, bars):
		for frame in step * 2:
			if data.decode_s16(frame * 2) != data.decode_s16((bar * step * 16 + frame) * 2):
				return false
	return true
