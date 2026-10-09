extends LabScenario

## Every pixel-art icon under res://assets/icons/<group>/, shown at the 3x
## nearest-neighbour scale the UI uses, one page per group.

const ROOT := "res://assets/icons"
const MENU_THEME := preload("res://scenes/ui/menu/menu_theme.tres")
const CELL := Vector2(118, 104)

func title() -> String:
	return "Icons"

func summary() -> String:
	return "Gallery of every generated pixel-art icon by group"

func run() -> void:
	var groups := Array(ResourceLoader.list_directory(ROOT))
	groups = groups.filter(func(entry: String): return entry.ends_with("/"))
	lab.check(not groups.is_empty(), "icon groups exist under %s" % ROOT)
	var layer := CanvasLayer.new()
	lab.stage_root = layer
	lab.add_child(layer)
	for group: String in groups:
		for child in layer.get_children():
			child.free()
		var files := Array(ResourceLoader.list_directory(ROOT.path_join(group))).filter(func(entry: String): return entry.ends_with(".png"))
		layer.add_child(_page(group.trim_suffix("/"), files))
		await lab.wait(0.25)
		await lab.capture(group.trim_suffix("/"))

func _page(group: String, files: Array) -> Control:
	var page := PanelContainer.new()
	page.theme = MENU_THEME
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rows := VBoxContainer.new()
	page.add_child(rows)
	var heading := Label.new()
	heading.text = "%s  ·  %d icons" % [group.to_upper(), files.size()]
	heading.add_theme_font_size_override(&"font_size", 22)
	rows.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	rows.add_child(grid)
	for file: String in files:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = CELL
		var icon := TextureRect.new()
		icon.texture = load(ROOT.path_join(group).path_join(file)) as Texture2D
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(72, 72)
		cell.add_child(icon)
		var label := Label.new()
		label.text = file.get_basename()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 11)
		label.clip_text = true
		label.custom_minimum_size.x = CELL.x
		cell.add_child(label)
		grid.add_child(cell)
	return page
