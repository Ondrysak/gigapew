class_name LevelQuests
extends RefCounted

## Only real deposit fractures and exact ordinary-species deaths advance a level.
signal changed
signal completed

var quests: Array[Dictionary] = []
var _mining_indices: Dictionary = {}
var _kill_indices: Dictionary = {}
var _requirements: Dictionary = {}
var _finished := false

func configure(stage: StageDefinition, deposit_types: Array[DepositDefinition], seed: int) -> void:
	quests.clear()
	_mining_indices.clear()
	_kill_indices.clear()
	_requirements.clear()
	_finished = false
	assert(stage != null and stage.schedule != null, "Level quests require a stage spawn schedule.")
	if stage == null or stage.schedule == null:
		push_error("Level quests require a stage spawn schedule.")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var scale := clampf(stage.quest_scale, 1.0, 3.0)
	for resource_id in [&"gold", &"crystal"]:
		if _mining_indices.size() >= stage.mine_objectives:
			break
		for deposit in deposit_types:
			if deposit == null or deposit.resource == null or deposit.yield_min <= 0:
				continue
			var resource := deposit.resource
			if resource.id != resource_id or _mining_indices.has(resource.id):
				continue
			var base := rng.randi_range(30, 42) if resource.id == &"gold" else rng.randi_range(10, 15)
			var target := clampi(roundi(base * scale), 1, 128)
			_mining_indices[resource.id] = quests.size()
			_requirements[resource] = target
			quests.append({"kind": &"mine", "id": resource.id, "name": resource.display_name,
				"icon": resource.icon, "color": resource.color, "target": target,
				"progress": 0, "definition": resource})
			break
	var candidates: Array[HordeEnemyDefinition] = []
	var rates: Dictionary = {}
	for wave in stage.schedule.waves:
		if wave == null or wave.enemy == null or wave.enemy.is_boss:
			continue
		if maxf(wave.rate_start, wave.rate_end) <= 0.0:
			continue
		if not candidates.has(wave.enemy):
			candidates.append(wave.enemy)
			rates[wave.enemy] = 0.0
		rates[wave.enemy] = float(rates[wave.enemy]) + maxf(0.0, wave.rate_start)
	assert(candidates.size() >= 2, "Level quests require two sustainable ordinary enemy species.")
	if candidates.size() < 2:
		push_error("Level quests require two sustainable ordinary enemy species.")
		quests.clear()
		_requirements.clear()
		_mining_indices.clear()
		_kill_indices.clear()
		return
	# A seeded partial shuffle never chooses the same species twice.
	for index in mini(2, stage.kill_objectives):
		var pick := rng.randi_range(index, candidates.size() - 1)
		var enemy := candidates[pick]
		candidates[pick] = candidates[index]
		candidates[index] = enemy
		var id := StringName(enemy.resource_path.get_file().get_basename())
		if id == &"":
			id = StringName(enemy.display_name.to_snake_case())
		# Sparse tank/bulwark species get reachable targets, common swarms get larger ones.
		var rate := maxf(0.02, float(rates[enemy]))
		var base := clampi(roundi(rate * rng.randf_range(70.0, 100.0)), 5, 130)
		var target := clampi(roundi(base * scale), 5, 300)
		_kill_indices[enemy] = quests.size()
		quests.append({"kind": &"kill", "id": id, "name": enemy.display_name,
			"icon": GameIcons.lookup(&"hud", &"kills"), "color": enemy.fx_color, "target": target,
			"progress": 0, "definition": enemy})
	changed.emit()

func record_mined(resource: ResourceDefinition, amount: int) -> void:
	if resource == null or amount <= 0 or not _mining_indices.has(resource.id):
		return
	var index := int(_mining_indices[resource.id])
	if quests[index]["definition"] != resource:
		return
	_advance(index, amount)

func record_kill(enemy: HordeEnemyDefinition) -> void:
	if enemy == null or enemy.is_boss or not _kill_indices.has(enemy):
		return
	_advance(int(_kill_indices[enemy]), 1)

func is_complete() -> bool:
	return not quests.is_empty() and completed_count() == quests.size()

func completed_count() -> int:
	var count := 0
	for quest in quests:
		if int(quest["progress"]) >= int(quest["target"]):
			count += 1
	return count

func requirements() -> Dictionary:
	return _requirements.duplicate()

func _advance(index: int, amount: int) -> void:
	if _finished:
		return
	var quest := quests[index]
	var progress := int(quest["progress"])
	var target := int(quest["target"])
	if progress >= target:
		return
	quest["progress"] = progress + mini(amount, target - progress)
	# Latch before either signal: observers cannot complete the same level twice.
	var did_complete := is_complete()
	_finished = did_complete
	changed.emit()
	if did_complete and _finished:
		completed.emit()
