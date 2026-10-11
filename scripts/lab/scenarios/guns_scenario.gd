extends LabScenario

const GUNS := ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]

func title() -> String:
	return "Gun models"

func summary() -> String:
	return "Original Blender weapons: side and three-quarter views, plus the flying beer bottle"

func run() -> void:
	var root := Node3D.new()
	lab.add_child(root)
	lab.stage_root = root
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.055, 0.075, 0.085)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.72, 0.83, 1.0)
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	root.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 2.0
	root.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.6, 0.2, -0.6)
	fill.omni_range = 4.0
	fill.light_energy = 1.3
	root.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.75
	root.add_child(camera)
	camera.current = true
	for id in GUNS:
		var gun := (load("res://assets/guns/%s.glb" % id) as PackedScene).instantiate() as Node3D
		root.add_child(gun)
		gun.position.z = 0.22
		# The thrown-bottle projectile template is only shown in flight.
		var template := gun.find_child("ThrownBottle", true, false) as Node3D
		if template != null:
			template.hide()
		camera.position = Vector3(1.5, 0.12, 0)
		camera.look_at(Vector3(0, 0.02, 0))
		await lab.frames(3)
		await lab.capture(id + "_side")
		camera.position = Vector3(1.0, 0.5, -0.95)
		camera.look_at(Vector3(0, 0.015, -0.04))
		await lab.frames(3)
		await lab.capture(id + "_quarter")
		if template != null:
			# Inspect the actual pooled projectile asset without the hand obscuring it.
			var hand := gun.find_child("Hand", true, false) as Node3D
			if hand != null:
				hand.hide()
			template.show()
			gun.position = Vector3.ZERO
			camera.size = 0.5
			camera.position = Vector3(0.65, 0.3, -0.6)
			camera.look_at(Vector3.ZERO)
			await lab.frames(3)
			await lab.capture(id + "_projectile")
			camera.size = 0.75
		gun.free()
