class_name LevelUpCard
extends Button

## One offer on the level-up screen. Layout lives in level_up_card.tscn; the
## script writes text/colors/icons into the referenced controls and builds the
## rank pips (owned / gained by this pick / still locked).

const OVERCLOCK_GOLD := Color(1.0, 0.76, 0.26)
const PIP_SIZE := Vector2(22, 10)
## Shown in the badge while an upgrade has no icon of its own.
const FALLBACK_ICONS := {
	UpgradeDefinition.Kind.STAT: &"level",
	UpgradeDefinition.Kind.WEAPON: &"crit",
	UpgradeDefinition.Kind.OVERCLOCK: &"shock",
	UpgradeDefinition.Kind.PERK: &"xp",
	UpgradeDefinition.Kind.GUN_MOD: &"kinetic",
}

@export var accent_bar: ColorRect
@export var key_label: Label
@export var kind_chip: PanelContainer
@export var kind_label: Label
@export var badge: PanelContainer
@export var icon_rect: TextureRect
@export var name_label: Label
@export var new_badge: PanelContainer
@export var new_label: Label
@export var pips: HBoxContainer
@export var description_label: Label

var _normal: StyleBoxFlat
var _hover: StyleBoxFlat
var _kind: StyleBoxFlat
var _badge: StyleBoxFlat
var _new: StyleBoxFlat
var _base_background := Color()
var _base_hover := Color()
var _base_shadow := Color()
var _base_shadow_size := 0
var _gaining: Control
var _time := 0.0

func _ready() -> void:
	# Own copies so each card can carry its offer's accent.
	_normal = _own_style(self, &"normal")
	_hover = _own_style(self, &"hover")
	add_theme_stylebox_override(&"pressed", _hover)
	_kind = _own_style(kind_chip, &"panel")
	_badge = _own_style(badge, &"panel")
	_new = _own_style(new_badge, &"panel")
	_base_background = _normal.bg_color
	_base_hover = _hover.bg_color
	_base_shadow = _normal.shadow_color
	_base_shadow_size = _normal.shadow_size

func show_offer(upgrade: UpgradeDefinition, current_level: int, key: int) -> void:
	var overclock := upgrade.kind == UpgradeDefinition.Kind.OVERCLOCK
	var accent := OVERCLOCK_GOLD if overclock else upgrade.accent_color
	accent_bar.color = accent
	_normal.border_color = accent.darkened(0.3) if not overclock else accent
	_normal.bg_color = Color(0.075, 0.052, 0.014, 0.98) if overclock else _base_background
	_normal.shadow_color = Color(accent, 0.3) if overclock else _base_shadow
	_normal.shadow_size = 14 if overclock else _base_shadow_size
	_hover.border_color = accent.lightened(0.3)
	_hover.bg_color = Color(0.11, 0.08, 0.02, 0.99) if overclock else _base_hover
	_hover.shadow_color = Color(accent, 0.35)
	key_label.text = str(key)
	kind_label.text = kind_text(upgrade)
	kind_label.add_theme_color_override(&"font_color", accent.lightened(0.45))
	_kind.bg_color = accent.darkened(0.78)
	_kind.border_color = accent.darkened(0.15)
	_badge.border_color = accent
	_badge.bg_color = accent.darkened(0.86)
	_badge.shadow_color = Color(accent, 0.35 if overclock else 0.18)
	var texture := upgrade.icon
	if texture == null:
		texture = GameIcons.lookup(&"hud", FALLBACK_ICONS.get(upgrade.kind, &"level"))
	icon_rect.texture = texture
	icon_rect.modulate = Color.WHITE if upgrade.icon != null else Color(1, 1, 1, 0.7)
	name_label.text = upgrade.display_name.to_upper()
	name_label.add_theme_color_override(&"font_color", accent.lightened(0.25 if overclock else 0.35))
	_show_rank(upgrade, current_level, accent)
	description_label.text = upgrade.describe(current_level + 1)

static func kind_text(upgrade: UpgradeDefinition) -> String:
	match upgrade.kind:
		UpgradeDefinition.Kind.WEAPON:
			return "AUTO WEAPON"
		UpgradeDefinition.Kind.GUN_MOD:
			return "GUN MOD"
		UpgradeDefinition.Kind.PERK:
			return "PERK"
		UpgradeDefinition.Kind.OVERCLOCK:
			return "OVERCLOCK"
	return "SUPPLY" if upgrade.repeatable else "SYSTEM"

func _process(delta: float) -> void:
	if _gaining == null or not is_visible_in_tree():
		return
	_time += delta
	_gaining.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_time * 8.0))

## NEW / INSTANT chip plus one pip per rank: owned ranks filled, the rank this
## pick grants pulsing bright, later ranks hollow.
func _show_rank(upgrade: UpgradeDefinition, current_level: int, accent: Color) -> void:
	for child in pips.get_children():
		child.queue_free()
	_gaining = null
	if upgrade.repeatable:
		new_badge.show()
		new_label.text = "INSTANT"
		_new.bg_color = accent
		pips.hide()
		return
	# Chip: NEW for a first pick, MAX when this pick completes the upgrade.
	var maxing := current_level + 1 >= upgrade.max_level and upgrade.max_level > 1
	new_badge.visible = current_level == 0 or maxing
	new_label.text = "NEW" if current_level == 0 else "MAX"
	_new.bg_color = Color(1, 0.58, 0.2) if current_level == 0 else OVERCLOCK_GOLD
	pips.show()
	var owned := _pip_style(accent.darkened(0.1), accent.darkened(0.1))
	var gaining := _pip_style(accent.lightened(0.65), Color.WHITE)
	gaining.shadow_color = Color(accent, 0.7)
	gaining.shadow_size = 6
	var locked := _pip_style(Color(0.05, 0.07, 0.09), accent.darkened(0.55))
	for rank in upgrade.max_level:
		var pip := Panel.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = PIP_SIZE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := owned if rank < current_level else (gaining if rank == current_level else locked)
		pip.add_theme_stylebox_override(&"panel", style)
		pips.add_child(pip)
		if rank == current_level:
			_gaining = pip

func _pip_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.skew = Vector2(0.4, 0.0)
	return style

func _own_style(control: Control, style_name: StringName) -> StyleBoxFlat:
	var style := control.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
	control.add_theme_stylebox_override(style_name, style)
	return style
