class_name ArenaHUD
extends CanvasLayer

@export var healthy_color := Color(0.86, 0.98, 1.0)
@export var critical_color := Color(1.0, 0.3, 0.4)
@export var boss_phase_color := Color(1.0, 0.45, 0.25)
@export var ability_ready_color := Color(0.4, 1.0, 0.85)
@export var ability_charging_color := Color(0.55, 0.65, 0.7)

@onready var health_label: Label = $Health
@onready var hostiles_label: Label = $Hostiles
@onready var sector_label: Label = $Sector
@onready var timer_label: Label = $Timer
@onready var kills_label: Label = $Kills
@onready var level_label: Label = $Level
@onready var xp_bar: ProgressBar = $XPBar
@onready var boss_panel: Control = $Boss
@onready var boss_name: Label = $Boss/Name
@onready var boss_bar: ProgressBar = $Boss/Bar
@onready var weapon_label: Label = $Weapon
@onready var weapon_detail: Label = $WeaponDetail
@onready var message: Label = $Message
@onready var radar: HordeRadar = $Radar
@onready var feedback: CombatFeedback = $Feedback
@onready var class_label: Label = $ClassName
@onready var resource_row: HBoxContainer = $Resources
@onready var supply_bar: ProgressBar = $Supply/Bar
@onready var ability_panel: Control = $Ability
@onready var ability_label: Label = $Ability/Name
@onready var ability_bar: ProgressBar = $Ability/Bar

var _last_health := 0
var _resource_labels: Dictionary = {}
var _resource_names: Dictionary = {}
var _hand_summary := ""
var _weapon_mods := ""

## Builds one counter per banked resource, styled by its definition.
func setup_resources(definitions: Array[ResourceDefinition]) -> void:
	for child in resource_row.get_children():
		child.queue_free()
	_resource_labels.clear()
	for definition in definitions:
		if not definition.banked:
			continue
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", definition.color)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_font_size_override("font_size", 16)
		resource_row.add_child(label)
		_resource_labels[definition.id] = label
		_resource_names[definition.id] = definition.display_name.to_upper()
		set_resource(definition.id, 0)

func show_class(definition: ClassDefinition) -> void:
	class_label.text = definition.display_name.to_upper()
	class_label.add_theme_color_override("font_color", definition.accent_color)

func set_resource(id: StringName, amount: int) -> void:
	var label: Label = _resource_labels.get(id)
	if label != null:
		label.text = "◆ %d %s" % [amount, _resource_names[id]]

func set_supply(value: int, required: int) -> void:
	supply_bar.max_value = maxi(1, required)
	supply_bar.value = value

func set_ability(ability: ActiveAbility) -> void:
	ability_panel.visible = ability != null
	if ability == null:
		return
	var total := maxf(0.001, ability.cooldown_total())
	var remaining := ability.cooldown_remaining()
	ability_bar.max_value = total
	ability_bar.value = total - remaining
	var ready := ability.is_ready()
	ability_label.text = "Q   %s%s" % [ability.display_name.to_upper(), "" if ready else "   %.0f" % ceilf(remaining)]
	ability_label.add_theme_color_override("font_color", ability_ready_color if ready else ability_charging_color)

func show_stage(stage: StageDefinition, index: int, total: int) -> void:
	message.hide()
	boss_panel.hide()
	_last_health = 0
	sector_label.text = "%02d / %02d   %s\n%s" % [index + 1, total, stage.display_name.to_upper(), stage.subtitle]
	timer_label.remove_theme_color_override("font_color")
	feedback.reset()

func set_aiming(captured: bool) -> void:
	feedback.aiming = captured

func set_health(current: int, maximum: int) -> void:
	health_label.text = "HEALTH %d / %d" % [current, maximum]
	if current < _last_health:
		feedback.show_damage()
	_last_health = current
	health_label.add_theme_color_override("font_color", critical_color if current <= maximum * 0.3 else healthy_color)

func set_hostiles(count: int) -> void:
	hostiles_label.text = "HOSTILES %d" % count

func set_kills(count: int) -> void:
	kills_label.text = "KILLS %d" % count

func set_timer(seconds_left: float, boss_phase: bool) -> void:
	if boss_phase:
		timer_label.text = ("DESTROY THE %s" % boss_name.text) if boss_panel.visible else "HOLD OUT"
		timer_label.add_theme_color_override("font_color", boss_phase_color)
	else:
		var whole := ceili(seconds_left)
		timer_label.text = "%d:%02d" % [whole / 60, whole % 60]

func set_xp(xp: int, required: int, level: int) -> void:
	level_label.text = "LV %d" % level
	xp_bar.max_value = maxi(1, required)
	xp_bar.value = xp

func show_boss(definition: HordeEnemyDefinition) -> void:
	boss_name.text = definition.display_name.to_upper()
	boss_panel.show()

func set_boss_health(current: float, maximum: float) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current

func set_hands(state: RunState, focused: int) -> void:
	if state.hands.is_empty():
		return
	var selected := state.hands[clampi(focused, 0, state.hands.size() - 1)].definition
	weapon_label.text = "HAND %d  //  %s" % [focused + 1, selected.display_name.to_upper()]
	var lines := PackedStringArray()
	for index in state.hands.size():
		var gun := state.hands[index].definition
		var pellets := clampi(gun.pellet_count + state.projectile_bonus, 1, WeaponHand.MAX_PROJECTILES)
		lines.append("%s%d %s · %s ×%d%s" % [
			"▶ " if index == focused else "   ", index + 1,
			gun.display_name.to_upper(), DamageType.label(gun.damage_type).to_upper(), pellets,
			" · BLAST %.1fm" % gun.explosion_radius if gun.explosion_radius > 0.0 else "",
		])
	_hand_summary = "\n".join(lines)
	_refresh_weapon_detail()

func _refresh_weapon_detail() -> void:
	weapon_detail.text = _hand_summary + ("\n" + _weapon_mods if not _weapon_mods.is_empty() else "")

## Show currently installed main-gun mods below the selected gun.
func set_weapon_mods(state: RunState) -> void:
	_weapon_mods = ""
	if state.upgrade_levels.get(&"mod_quickdraw", 0) > 0:
		_weapon_mods += "QUICKDRAW"
	if state.upgrade_levels.get(&"mod_longshot", 0) > 0:
		_weapon_mods += "  /  LONGSHOT"
	if state.upgrade_levels.get(&"mod_executioner", 0) > 0:
		_weapon_mods += "  /  EXECUTIONER"
	_weapon_mods = _weapon_mods.trim_prefix("  /  ")
	_refresh_weapon_detail()

func show_shot() -> void:
	feedback.show_shot()

func show_hit(killed: bool) -> void:
	feedback.show_hit(killed)

func show_combo(hits: int, bonus: float) -> void:
	feedback.show_combo(hits, bonus)

func finish_run(summary: String, banked: String) -> void:
	feedback.terminal = true
	boss_panel.hide()
	message.add_theme_color_override("font_color", critical_color)
	message.text = "YOU DIED\n%s\n%s\nR  RETRY   /   ENTER  MENU" % [summary, banked]
	message.show()
