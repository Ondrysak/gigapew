extends LabScenario

## Luďas's recorded voice through real game events: arrival, kill bursts,
## combos, a skill unlock sequence, hurt/heal, extraction, clear and death;
## plus priority interruption and cooldowns that stop spam.

func title() -> String:
	return "Luďas voice"

func summary() -> String:
	return "Recorded reactions from real events, priorities, cooldowns and sequences"

func run() -> void:
	var game := await lab.start_game(&"scout", 0, true, 8721, true)
	var voice := game.voice
	await lab.wait(0.3)
	lab.check(voice.history.has(&"ijee_haa"), "arriving in a sector plays Luďas's Ijéé-háá")
	# Kill burst: a real quick string of kills.
	voice.stop()
	voice.history.clear()
	# Use the protected spawn floor; the street ahead may contain a building.
	var slots := lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(0.0), game.BURST_KILLS, 0.0)
	for slot in slots:
		game.horde.damage_direct(slot, 1.0e6, Vector3.ZERO, Vector3.ZERO)
	await lab.wait(0.1)
	lab.check(voice.history.has(&"ijee_1") or voice.history.has(&"ijee_2"), "a burst of %d kills triggers a multikill Ijéé" % game.BURST_KILLS)
	var count := voice.history.size()
	for slot in lab.spawn_pack(lab.enemy("robot_grunt"), lab.ahead(0.0), game.BURST_KILLS, 0.0):
		game.horde.damage_direct(slot, 1.0e6, Vector3.ZERO, Vector3.ZERO)
	await lab.wait(0.1)
	lab.check(voice.history.size() == count, "a second burst inside the cooldown stays quiet")
	# A skill unlock plays the Jaj… krajíc… chleba sequence and outranks chatter.
	voice.stop()
	voice.history.clear()
	voice.say(&"multikill")
	game.run_state.add_xp(game.run_state.xp_required - game.run_state.xp)
	await lab.wait(1.6)
	lab.check(voice.history.slice(-3) == [&"jaj", &"krajic", &"chleba"], "a new skill interrupts chatter and plays Jaj… krajíc… chleba in order")
	# Hurt below 40% growls once; healing gulps.
	voice.stop()
	voice.history.clear()
	game.player.grant_invulnerability(0.0)
	game.player._invulnerable = 0.0
	game.player.take_damage(game.player.health - 30)
	await lab.frames(2)
	lab.check(voice.history.has(&"hrrr"), "dropping below 40% health growls")
	game.player.take_damage(5)
	await lab.frames(2)
	lab.check(voice.history.count(&"hrrr") == 1, "further hits inside the cooldown do not repeat the growl")
	voice.stop()
	game.player.heal(20)
	await lab.frames(2)
	lab.check(voice.history.has(&"blp"), "healing plays the gulp")
	# Clear and death outrank everything.
	voice.stop()
	voice.say(&"multikill")
	lab.check(voice.say(&"death") and voice.speaking == &"death", "death interrupts any lower-priority line")
	lab.check(not voice.say(&"heal"), "a lower-priority line cannot interrupt death")
	await lab.capture("voice")

