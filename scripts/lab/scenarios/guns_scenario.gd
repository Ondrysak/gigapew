extends LabScenario

const GUNS := ["pulse", "rail", "scatter", "minigun", "autocannon", "flamethrower"]
## Longer guns need the model shifted and a wider frame; the rest share the default.
const LAYOUT := {"rail": {"z": 0.42, "size": 1.0, "projectile": 0.95}, "minigun": {"projectile": 0.3}, "scatter": {"projectile": 0.3}, "autocannon": {"projectile": 0.6}}

func title() -> String:
	return "Gun models"

func summary() -> String:
	return "Improvised junk weapons: side and three-quarter views, plus each pooled projectile (bottle, rebar spike, vinyl, pigeon, molotov)"

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
		var layout: Dictionary = LAYOUT.get(id, {})
		var frame: float = layout.get("size", 0.75)
		camera.size = frame
		gun.position.z = layout.get("z", 0.22)
		# The pooled projectile template (Thrown*) is only shown in flight.
		var template: Node3D = null
		var thrown := gun.find_children("Thrown*", "Node3D", true, false)
		if not thrown.is_empty():
			template = thrown[0] as Node3D
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
			# Inspect the actual pooled projectile asset on its own, as shipped.
			var parts := gun.get_child(0)
			for part in parts.get_children():
				if part is Node3D:
					(part as Node3D).visible = part == template
			template.show()
			gun.position = -(parts as Node3D).position
			camera.size = layout.get("projectile", 0.5)
			camera.position = Vector3(0.65, 0.3, -0.6)
			camera.look_at(Vector3.ZERO)
			await lab.frames(3)
			await lab.capture(id + "_projectile")
		gun.free()
