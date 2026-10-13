extends LabScenario

## A saved run setup drives the real game: chosen level, tuned schedule the
## director actually runs, specialists filter, incoming damage and presets.

func title() -> String:
	return "Run setup"

func summary() -> String:
	return "Level selection, presets, tuned waves and crowd cap in the live director, specialist filter, incoming damage and tier scaling"

func run() -> void:
	_presets()
	var config := RunConfig.new()
	var levels := RunConfig.levels()
	config.select_level(levels[2])
	config.apply_preset(&"pohoda", levels[2])
	config.set_value("difficulty", 2)
	Profile.set_run_config(config)
	# No explicit stage or seed: the real _new_run picks the level from the config.
	var game := await lab.start_game(&"scout", 0, true)
	lab.check(game.stage_index == 2 and game.campaign[2].id == &"reactor", "the saved level choice starts the run on Hlavák, not the first level")
	var authored := levels[2].schedule
	var tuned := game.active_stage.schedule
	var specialists := 0
	for wave in tuned.waves:
		specialists += 1 if wave.enemy.behavior in RunConfig.SPECIALISTS else 0
	var authored_specialists := 0
	for wave in authored.waves:
		authored_specialists += 1 if wave.enemy.behavior in RunConfig.SPECIALISTS else 0
	lab.check(authored_specialists > 0 and specialists == 0, "Pohodička removes all %d authored specialist waves" % authored_specialists)
	var first := authored.waves[0]
	var scaled := tuned.waves[0]
	lab.check(scaled.count == roundi(first.count * config.density_scale()) and is_equal_approx(scaled.health_multiplier, first.health_multiplier * config.health_scale()), "waves carry the density and health tuning stacked with the tier (%d → %d bodies)" % [first.count, scaled.count])
	lab.check(game.director._schedule == tuned and game.director.encounter_count == 2 and tuned.max_alive == roundi(authored.max_alive * 0.75), "the live director runs the tuned schedule: two fights, crowd cap %d" % tuned.max_alive)
	lab.check(scaled != first and tuned != authored and first.count != scaled.count and game.campaign[2].arena_encounters == 5, "tuning works on copies; the authored Hlavák keeps its waves and five fights")
	var player := game.player
	player._invulnerable = 0.0
	var before := player.health
	var armor := int(game.run_state.armor)
	player.take_damage(10)
	var expected := maxi(1, maxi(1, roundi(10 * config.damage_scale())) - armor)
	lab.check(is_equal_approx(player.incoming_damage_scale, config.damage_scale()) and before - player.health == expected and expected < maxi(1, 10 - armor), "a real 10-damage hit lands as %d after the ×%.2f incoming tuning" % [before - player.health, config.damage_scale()])
	player.grant_invulnerability(1.0e9)
	await lab.capture("tuned_hud")

func _presets() -> void:
	var stage := RunConfig.levels()[0]
	var totals := {}
	for id: StringName in RunConfig.PRESETS:
		var config := RunConfig.new()
		config.select_level(stage)
		config.apply_preset(id, stage)
		totals[id] = config.estimated_enemies(stage)
	lab.check(totals[&"horda"] > totals[&"peklo"] and totals[&"peklo"] > totals[&"klasika"] and totals[&"klasika"] > totals[&"pohoda"] and totals[&"rychlovka"] < totals[&"klasika"], "presets order the crowd: Horda %d > Peklo %d > Klasika %d > Pohodička %d; Rychlovka %d" % [totals[&"horda"], totals[&"peklo"], totals[&"klasika"], totals[&"pohoda"], totals[&"rychlovka"]])
	var config := RunConfig.new()
	config.apply_preset(&"peklo", stage)
	config.set_value("difficulty", 4)
	var copy := RunConfig.from_dict(config.to_dict())
	lab.check(copy.to_dict() == config.to_dict() and copy.preset == &"peklo", "a saved config round-trips with its preset and tier")
	var hostile := RunConfig.from_dict({"density": 99, "fights": -4, "difficulty": "x", "preset": "nonsense", "specialists": 3})
	lab.check(is_equal_approx(hostile.density, 3.0) and hostile.fights == 1 and hostile.difficulty == 0 and hostile.preset == RunConfig.DEFAULT_PRESET and hostile.specialists, "corrupt saved values clamp to safe ranges")
