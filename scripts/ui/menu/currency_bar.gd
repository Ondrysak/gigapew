class_name CurrencyBar
extends HBoxContainer

## Live Profile balances, one chip per listed currency (name, color and icon
## come from the ResourceDefinition). Other menu code asks it for currency
## labels so prices read the same everywhere.

@export var currencies: Array[ResourceDefinition] = []
@export var font_size := 20

var _values: Dictionary = {}

func _ready() -> void:
	for definition in currencies:
		if definition == null:
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override(&"separation", 8)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if definition.icon != null:
			var icon := TextureRect.new()
			icon.texture = definition.icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(font_size, font_size)
			chip.add_child(icon)
		else:
			var swatch := ColorRect.new()
			swatch.color = definition.color
			swatch.custom_minimum_size = Vector2(10, 10)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.add_child(swatch)
		var value := Label.new()
		value.add_theme_font_size_override(&"font_size", font_size)
		value.add_theme_color_override(&"font_color", definition.color.lightened(0.25))
		chip.add_child(value)
		add_child(chip)
		_values[definition.id] = value
	Profile.currency_changed.connect(_on_currency_changed)
	refresh()

func refresh() -> void:
	for id: StringName in _values:
		_values[id].text = "%d %s" % [Profile.currency(id), label_for(id)]

## Upper-case display name for a currency id (falls back to the id).
func label_for(id: StringName) -> String:
	var definition := definition_for(id)
	return definition.display_name.to_upper() if definition != null else String(id).to_upper()

func color_for(id: StringName) -> Color:
	var definition := definition_for(id)
	return definition.color if definition != null else Color.WHITE

func definition_for(id: StringName) -> ResourceDefinition:
	for definition in currencies:
		if definition != null and definition.id == id:
			return definition
	return null

func _on_currency_changed(id: StringName, amount: int) -> void:
	if _values.has(id):
		_values[id].text = "%d %s" % [amount, label_for(id)]
