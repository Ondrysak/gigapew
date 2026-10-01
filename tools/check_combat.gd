extends SceneTree
## A synchronous damage listener may trigger another blast (e.g. Chain Reaction).
## Each invocation must retain its own targets, including beyond pooled depth.
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.director.set_physics_process(false)
	game.horde.set_physics_process(false)
	game.player.set_physics_process(false)
	var horde = game.horde
	var definition = game._stage_enemies(game.campaign[0].schedule)[0]
	for levels in [2, horde.RADIUS_DEPTH + 2]:
		horde.clear()
		var groups: Array = []
		for depth in range(levels):
			var slots: Array[int] = []
			for target in range(3 if depth == 0 else 2):
				slots.append(horde.spawn(definition, Vector2(-12 + depth * 4 + target * 0.3, 6), 100.0 / definition.max_health))
			groups.append(slots)
		horde._rebuild_grid()
		var nested := {"depth": 0}
		var listener := func(_at: Vector3, _amount: float, _kind: int, _critical: bool, _killed: bool):
			if nested.depth + 1 < levels:
				nested.depth += 1
				horde.damage_radius(Vector3(-12 + nested.depth * 4, 0.5, 6), 1.0, 5.0 + nested.depth)
		horde.damage_reported.connect(listener)
		var count: int = horde.damage_radius(Vector3(-12, 0.5, 6), 1.0, 5.0)
		horde.damage_reported.disconnect(listener)
		_check(count == 3, "Nested blast changed the outer hit count")
		for depth in range(levels):
			for slot in groups[depth]:
				_check(is_equal_approx(horde._hp[slot], 95.0 - depth), "Nested blast lost, duplicated or substituted a target at depth %d" % depth)
	game.free()
	print("Nested blast regression: failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
