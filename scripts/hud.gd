class_name ArenaHUD
extends CanvasLayer

## In-run overlay. Static layout lives in hud.tscn; repeated readouts (resource
## counters, hand slots, mod icons, death-screen tiles) are built here from data
## and the boss bar / ability cooldown are drawn by this script.

const LOW_HEALTH_FRACTION := 0.3
const BOSS_PHASE_FRACTION := 0.3
const BOSS_SEGMENTS := 20
## Seconds the boss bar's damage trail holds before draining to the real value.
const TRAIL_HOLD := 0.45
const TRAIL_SPEED := 0.6
## Seconds the WARNING banner rests after blinking, before it folds away.
const WARNING_HOLD := 0.3
const HAND_SLOT_SIZE := Vector2(136, 0)

@export var healthy_color := Color(0.3, 0.9, 0.62)
@export var critical_color := Color(1.0, 0.24, 0.32)
@export var boss_color := Color(1.0, 0.36, 0.2)
@export var boss_phase_color := Color(1.0, 0.16, 0.42)
@export var hold_out_color := Color(1.0, 0.45, 0.25)
@export var ability_ready_color := Color(0.4, 1.0, 0.85)
@export var ability_charging_color := Color(0.55, 0.65, 0.7)
@export var focus_color := Color(1.0, 0.58, 0.22)

@onready var sector_label: Label = $Stage/Rows/Sector
@onready var subtitle_label: Label = $Stage/Rows/Subtitle
@onready var resource_row: HBoxContainer = $Stage/Rows/Resources
@onready var supply_bar: ProgressBar = $Stage/Rows/Supply/Bar
@onready var supply_value: Label = $Stage/Rows/Supply/Value
@onready var timer_box: Control = $Timer
@onready var timer_icon: TextureRect = $Timer/Icon
@onready var timer_label: Label = $Timer/Label
@onready var boss_panel: Control = $Boss
@onready var boss_name: Label = $Boss/Row/Info/Header/Name
@onready var boss_phase: Label = $Boss/Row/Info/Header/Phase
@onready var boss_percent: Label = $Boss/Row/Info/Header/Percent
@onready var boss_bar: Control = $Boss/Row/Info/Bar
@onready var boss_icon: TextureRect = $Boss/Row/Badge/Icon
@onready var hostiles_label: Label = $Threat/Rows/Hostiles/Value
@onready var kills_label: Label = $Threat/Rows/Kills/Value
@onready var radar: HordeRadar = $Radar
@onready var vitals: PanelContainer = $Vitals
@onready var level_label: Label = $Vitals/Rows/Top/Level/Label
@onready var level_badge: Control = $Vitals/Rows/Top/Level
@onready var class_label: Label = $Vitals/Rows/Top/ClassName
@onready var xp_value: Label = $Vitals/Rows/Top/XPValue
@onready var xp_bar: ProgressBar = $Vitals/Rows/XPBar
@onready var health_icon: TextureRect = $Vitals/Rows/Health/Icon
@onready var health_bar: ProgressBar = $Vitals/Rows/Health/Bar
@onready var health_value: Label = $Vitals/Rows/Health/Bar/Value
@onready var armor_box: Control = $Vitals/Rows/Health/Armor
@onready var armor_value: Label = $Vitals/Rows/Health/Armor/Value
@onready var ability_panel: Control = $Ability
@onready var ability_slot: Panel = $Ability/Slot
@onready var ability_icon: TextureRect = $Ability/Icon
@onready var ability_cooldown: Control = $Ability/Cooldown
@onready var ability_seconds: Label = $Ability/Seconds
@onready var ability_label: Label = $Ability/Name
@onready var hand_title: Label = $Hands/Header/Title
@onready var mod_row: HBoxContainer = $Hands/Header/Mods
@onready var hand_row: HBoxContainer = $Hands/Slots
@onready var warning: Control = $Warning
@onready var warning_band: Control = $Warning/Band
@onready var warning_title: Label = $Warning/Content/Text/Title
@onready var warning_subtitle: Label = $Warning/Content/Text/Subtitle
@onready var feedback: CombatFeedback = $Feedback
@onready var death: Control = $Death
@onready var death_panel: Control = $Death/Center/Panel
@onready var death_where: Label = $Death/Center/Panel/Rows/Where
@onready var death_stats: HBoxContainer = $Death/Center/Panel/Rows/Stats
@onready var death_banked: HBoxContainer = $Death/Center/Panel/Rows/Banked
@onready var death_keys: HBoxContainer = $Death/Center/Panel/Rows/Keys

var _resource_labels: Dictionary = {}
var _definitions: Array[ResourceDefinition] = []
var _upgrades: Array[UpgradeDefinition] = []
var _state: RunState
var _stage_name := ""
var _time := 0.0
var _last_health := 0
var _health_fraction := 1.0
var _level := 0
var _health_fill: StyleBoxFlat
var _vitals_style: StyleBoxFlat
var _vitals_border := Color()
# Hand slots: one Dictionary of child controls per hand.
var _slots: Array[Dictionary] = []
var _slot_styles: Array[StyleBoxFlat] = []
# Ability readout.
var _ability: ActiveAbility
var _ability_charge := 1.0
var _ability_ready := true
var _ability_style: StyleBoxFlat
# Boss frame: real fraction, delayed trail and hit flash.
var _boss_fraction := 1.0
var _boss_trail := 1.0
var _boss_hold := 0.0
var _boss_flash := 0.0
var _warning_tween: Tween

func _ready() -> void:
	_health_fill = (health_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).duplicate()
	health_bar.add_theme_stylebox_override(&"fill", _health_fill)
	_vitals_style = (vitals.get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate()
	vitals.add_theme_stylebox_override(&"panel", _vitals_style)
	_vitals_border = _vitals_style.border_color
	_ability_style = (ability_slot.get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate()
	ability_slot.add_theme_stylebox_override(&"panel", _ability_style)
	boss_bar.draw.connect(_draw_boss_bar)
	ability_cooldown.draw.connect(_draw_ability_cooldown)
	warning_band.draw.connect(_draw_warning_band)
	death_keys.add_child(_key_hint("R", "RETRY"))
	death_keys.add_child(_key_hint("ENTER", "MENU"))

## Builds one counter per banked resource, styled by its definition.
func setup_resources(definitions: Array[ResourceDefinition]) -> void:
	for child in resource_row.get_children():
		child.queue_free()
	_resource_labels.clear()
	_definitions.clear()
	for definition in definitions:
		if not definition.banked:
			continue
		_definitions.append(definition)
		var counter := HBoxContainer.new()
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		counter.add_theme_constant_override(&"separation", 6)
		counter.tooltip_text = definition.display_name
		counter.add_child(_icon(definition.icon, 32))
		var label := _label("0", 20, definition.color.lightened(0.15))
		label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override(&"shadow_offset_x", 1)
		label.add_theme_constant_override(&"shadow_offset_y", 1)
		label.custom_minimum_size.x = 30
		counter.add_child(label)
		resource_row.add_child(counter)
		_resource_labels[definition.id] = label
		set_resource(definition.id, 0)

## Upgrade catalog used to show installed gun mods as icons.
func setup_upgrades(pool: UpgradePool) -> void:
	_upgrades.clear()
	if pool != null:
		for upgrade in pool.upgrades:
			if upgrade != null and upgrade.kind == UpgradeDefinition.Kind.GUN_MOD:
				_upgrades.append(upgrade)

func show_class(definition: ClassDefinition) -> void:
	class_label.text = definition.display_name.to_upper()
	class_label.add_theme_color_override(&"font_color", definition.accent_color)

func set_resource(id: StringName, amount: int) -> void:
	var label: Label = _resource_labels.get(id)
	if label == null:
		return
	var previous := label.text.to_int()
	label.text = str(amount)
	if amount > previous and is_inside_tree():
		_pop(label)

func set_supply(value: int, required: int) -> void:
	supply_bar.max_value = maxi(1, required)
	supply_bar.value = value
	supply_value.text = "%d / %d" % [value, required]

func set_ability(ability: ActiveAbility) -> void:
	ability_panel.visible = ability != null
	if ability == null:
		_ability = null
		return
	if ability != _ability:
		_ability = ability
		var texture := ability.icon if ability.icon != null else GameIcons.lookup(&"hud", &"ability")
		ability_icon.texture = texture
		ability_label.text = ability.display_name.to_upper()
	var total := maxf(0.001, ability.cooldown_total())
	var remaining := ability.cooldown_remaining()
	var ready := ability.is_ready()
	var charge := clampf(1.0 - remaining / total, 0.0, 1.0)
	ability_seconds.text = "" if ready or remaining <= 0.0 else str(ceili(remaining))
	ability_label.add_theme_color_override(&"font_color", ability_ready_color if ready else ability_charging_color)
	ability_icon.modulate = Color.WHITE if ready else Color(0.55, 0.6, 0.65)
	if ready != _ability_ready or not is_equal_approx(charge, _ability_charge):
		_ability_ready = ready
		_ability_charge = charge
		ability_cooldown.queue_redraw()

func show_stage(stage: StageDefinition, index: int, total: int) -> void:
	death.hide()
	boss_panel.hide()
	warning.hide()
	timer_box.show()
	_last_health = 0
	_stage_name = "SECTOR %02d  ·  %s" % [index + 1, stage.display_name.to_upper()]
	sector_label.text = "%02d / %02d   %s" % [index + 1, total, stage.display_name.to_upper()]
	subtitle_label.text = stage.subtitle
	timer_icon.texture = GameIcons.lookup(&"hud", &"timer")
	timer_label.remove_theme_color_override(&"font_color")
	feedback.reset()

func set_aiming(captured: bool) -> void:
	feedback.aiming = captured

func set_health(current: int, maximum: int) -> void:
	health_bar.max_value = maxi(1, maximum)
	health_bar.value = current
	health_value.text = "%d / %d" % [current, maximum]
	if current < _last_health:
		feedback.show_damage()
		_pop(health_icon, 1.35)
	_last_health = current
	_health_fraction = float(current) / float(maxi(1, maximum))
	_refresh_armor()

func set_hostiles(count: int) -> void:
	hostiles_label.text = str(count)

func set_kills(count: int) -> void:
	kills_label.text = str(count)

func set_timer(seconds_left: float, boss_phase: bool) -> void:
	if boss_phase:
		timer_box.visible = not boss_panel.visible and not death.visible
		timer_label.text = "HOLD OUT"
		timer_icon.texture = GameIcons.lookup(&"hud", &"boss")
		timer_label.add_theme_color_override(&"font_color", hold_out_color)
	else:
		var whole := ceili(seconds_left)
		timer_label.text = "%d:%02d" % [whole / 60, whole % 60]

func set_xp(xp: int, required: int, level: int) -> void:
	level_label.text = "LV %d" % level
	xp_value.text = "%d / %d" % [xp, required]
	xp_bar.max_value = maxi(1, required)
	xp_bar.value = xp
	if level > _level and _level > 0:
		_pop(level_badge, 1.3)
	_level = level

func show_boss(definition: HordeEnemyDefinition) -> void:
	boss_name.text = definition.display_name.to_upper()
	_boss_fraction = 1.0
	_boss_trail = 1.0
	_boss_hold = 0.0
	_boss_flash = 0.0
	boss_phase.hide()
	boss_percent.text = "100%"
	timer_box.hide()
	boss_panel.show()
	boss_panel.pivot_offset = boss_panel.size * 0.5
	boss_panel.modulate.a = 0.0
	boss_panel.scale = Vector2(1.08, 1.08)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(boss_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(boss_panel, "scale", Vector2.ONE, 0.35)
	_show_warning(definition.display_name.to_upper())

func set_boss_health(current: float, maximum: float) -> void:
	var fraction := clampf(current / maxf(0.001, maximum), 0.0, 1.0)
	if fraction < _boss_fraction:
		_boss_hold = TRAIL_HOLD
		_boss_flash = 1.0
	_boss_trail = maxf(_boss_trail, fraction)
	_boss_fraction = fraction
	boss_percent.text = "%d%%" % ceili(fraction * 100.0)
	var enraged := fraction <= BOSS_PHASE_FRACTION and fraction > 0.0
	boss_phase.visible = enraged
	boss_percent.add_theme_color_override(&"font_color", boss_phase_color.lightened(0.3) if enraged else Color(1, 0.62, 0.45))
	boss_bar.queue_redraw()

func set_hands(state: RunState, focused: int) -> void:
	_state = state
	if state.hands.is_empty():
		return
	focused = clampi(focused, 0, state.hands.size() - 1)
	while _slots.size() < state.hands.size():
		_add_hand_slot()
	for index in _slots.size():
		var slot: Dictionary = _slots[index]
		var root: Control = slot.root
		root.visible = index < state.hands.size()
		if not root.visible:
			continue
		var hand := state.hands[index]
		var gun := hand.definition
		var is_focused := index == focused
		(slot.weapon as TextureRect).texture = gun.icon
		(slot.type as TextureRect).texture = GameIcons.damage_type(gun.damage_type)
		var pellets := clampi(gun.pellet_count + state.projectile_bonus, 1, WeaponHand.MAX_PROJECTILES)
		(slot.pellets as Label).text = "×%d" % pellets
		var mods: HBoxContainer = slot.mods
		for child in mods.get_children():
			child.queue_free()
		for kind: StringName in hand.upgrade_levels:
			if int(hand.upgrade_levels[kind]) > 0:
				var icon := _icon(GameIcons.lookup(&"shop", kind), 16)
				icon.tooltip_text = String(kind)
				mods.add_child(icon)
		var style := _slot_styles[index]
		style.border_color = focus_color if is_focused else Color(0.1, 0.36, 0.4)
		style.set_border_width_all(2 if is_focused else 1)
		style.bg_color = Color(0.07, 0.05, 0.03, 0.92) if is_focused else Color(0.012, 0.03, 0.045, 0.82)
		var key: Label = slot.key
		key.add_theme_color_override(&"font_color", focus_color if is_focused else Color(0.5, 0.62, 0.66))
		root.modulate = Color.WHITE if is_focused else Color(1, 1, 1, 0.78)
	var selected := state.hands[focused].definition
	hand_title.text = "HAND %d  ·  %s" % [focused + 1, selected.display_name.to_upper()]
	_refresh_armor()

## Updated from the actual player state; no menu preview drives these meters.
func set_gunplay(player: ArenaPlayer) -> void:
	for index in mini(_slots.size(), player.weapons.size()):
		var slot: Dictionary = _slots[index]
		var gun := player.weapons[index]
		if gun == null:
			continue
		var reload := player.is_reloading(index)
		var focused := index == player.selected_weapon
		var rounds := player.ammo(index)
		var text := "%d / %d" % [rounds, gun.magazine_size]
		if reload:
			text = "EMPTY · SWAP" if focused and rounds == 0 else "RELOAD %d%%" % roundi(player.reload_progress(index) * 100.0)
		if (slot.ammo as Label).text != text:
			(slot.ammo as Label).text = text
		(slot.ammo as Label).modulate = focus_color if reload else Color.WHITE
		(slot.reload as ProgressBar).value = player.reload_progress(index) * 100.0 if reload else 100.0
		var alternate := player.secondaries[index]
		var charge := player.secondary_charge[index]
		(slot.charge as ProgressBar).value = charge
		var hint := ""
		if alternate != null:
			hint = alternate.display_name.to_upper()
			if focused and player.drilling():
				hint = "DRILL → CHARGE"
			elif alternate.charge_progress() > 0.0:
				hint = "LANCE %d%% · RELEASE" % roundi(alternate.charge_progress() * 100.0)
			elif alternate.is_active():
				hint = "ALT ACTIVE"
			elif focused and charge >= alternate.charge_cost:
				hint = "RMB · " + hint
		if (slot.alternate as Label).text != hint:
			(slot.alternate as Label).text = hint
		(slot.alternate as Label).modulate = ability_ready_color if charge >= 100.0 else Color(0.65, 0.76, 0.8)

func _gun_meter(color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.custom_minimum_size.y = 4
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.1, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	meter.add_theme_stylebox_override(&"background", back)
	meter.add_theme_stylebox_override(&"fill", fill)
	return meter

## Shows installed main-gun mods as icons beside the focused hand's name.
func set_weapon_mods(state: RunState) -> void:
	_state = state
	for child in mod_row.get_children():
		child.queue_free()
	var installed: Array[UpgradeDefinition] = []
	for upgrade in _upgrades:
		if state.level_of(upgrade) > 0:
			installed.append(upgrade)
	if not installed.is_empty():
		mod_row.add_child(_label("MODS", 11, Color(0.5, 0.62, 0.66)))
	for upgrade in installed:
		var tip := upgrade.display_name.to_upper()
		if upgrade.icon != null:
			var icon := _icon(upgrade.icon, 32)
			icon.tooltip_text = tip
			mod_row.add_child(icon)
		else:
			var chip := _chip(tip.get_slice(" ", 0), upgrade.accent_color)
			mod_row.add_child(chip)
	_refresh_armor()

func show_shot() -> void:
	feedback.show_shot()

func show_hit(killed: bool) -> void:
	feedback.show_hit(killed)

func show_combo(hits: int, bonus: float) -> void:
	feedback.show_combo(hits, bonus)

## Run-over panel: summary tiles plus the minerals moved into the Profile.
func finish_run(level: int, kills: int, seconds: float, stages_cleared: int, banked: Dictionary) -> void:
	feedback.terminal = true
	boss_panel.hide()
	warning.hide()
	timer_box.hide()
	death_where.text = "SIGNAL LOST IN %s" % _stage_name if not _stage_name.is_empty() else "SIGNAL LOST"
	for child in death_stats.get_children():
		child.queue_free()
	var whole := int(seconds)
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"level"), str(level), "LEVEL"))
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"kills"), str(kills), "KILLS"))
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"timer"), "%d:%02d" % [whole / 60, whole % 60], "SURVIVED"))
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"boss"), str(stages_cleared), "BOSSES"))
	for child in death_banked.get_children():
		child.queue_free()
	for definition in _definitions:
		var amount := int(banked.get(definition.id, 0))
		if amount <= 0:
			continue
		var entry := HBoxContainer.new()
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_theme_constant_override(&"separation", 8)
		entry.add_child(_icon(definition.icon, 32))
		entry.add_child(_label("+%d" % amount, 24, definition.color.lightened(0.2)))
		entry.add_child(_label(definition.display_name.to_upper(), 12, Color(0.6, 0.68, 0.72)))
		death_banked.add_child(entry)
	if death_banked.get_child_count() == 0:
		death_banked.add_child(_label("NOTHING BANKED", 16, Color(0.5, 0.56, 0.6)))
	death.show()
	death.modulate.a = 0.0
	death_panel.pivot_offset = death_panel.size * 0.5
	death_panel.scale = Vector2(0.92, 0.92)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(death, "modulate:a", 1.0, 0.35)
	tween.tween_property(death_panel, "scale", Vector2.ONE, 0.4)

func _process(delta: float) -> void:
	_time += delta
	# Low health: the bar, heart and vitals border pulse red.
	var low := _health_fraction <= LOW_HEALTH_FRACTION and _last_health > 0
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	if low:
		_health_fill.bg_color = critical_color.lerp(Color(0.55, 0.05, 0.1), pulse * 0.6)
		_health_fill.border_color = critical_color.darkened(0.45)
		_vitals_style.border_color = critical_color.lerp(_vitals_border, pulse * 0.5)
		health_icon.modulate = Color(1, 1, 1).lerp(Color(1, 0.45, 0.45), pulse)
	else:
		_health_fill.bg_color = healthy_color
		_health_fill.border_color = healthy_color.darkened(0.45)
		_vitals_style.border_color = _vitals_border
		health_icon.modulate = Color.WHITE
	if _ability != null:
		_ability_style.border_color = ability_ready_color.lerp(ability_ready_color.darkened(0.5), pulse * 0.5) if _ability_ready else Color(0.1, 0.32, 0.36)
		_ability_style.shadow_size = 8 if _ability_ready else 0
		_ability_style.shadow_color = Color(ability_ready_color, 0.25)
	if boss_panel.visible:
		if _boss_hold > 0.0:
			_boss_hold -= delta
		else:
			_boss_trail = move_toward(_boss_trail, _boss_fraction, TRAIL_SPEED * delta)
		_boss_flash = maxf(0.0, _boss_flash - delta * 6.0)
		boss_bar.queue_redraw()
		var enraged := _boss_fraction <= BOSS_PHASE_FRACTION
		boss_icon.modulate = Color(1, 1, 1).lerp(Color(1, 0.4, 0.5), pulse) if enraged else Color.WHITE
		boss_phase.modulate.a = 0.55 + 0.45 * pulse
	if warning.visible:
		warning_band.queue_redraw()

# ------------------------------------------------------------------ drawing

func _draw_boss_bar() -> void:
	var rect := Rect2(Vector2.ZERO, boss_bar.size)
	boss_bar.draw_rect(rect, Color(0.06, 0.01, 0.015, 0.95))
	var enraged := _boss_fraction <= BOSS_PHASE_FRACTION
	var fill := boss_phase_color if enraged else boss_color
	if enraged:
		fill = fill.lerp(Color(1, 0.55, 0.65), 0.25 + 0.25 * sin(_time * 9.0))
	fill = fill.lerp(Color.WHITE, _boss_flash * 0.55)
	var gap := 3.0
	var width := (rect.size.x - gap * (BOSS_SEGMENTS - 1)) / BOSS_SEGMENTS
	for n in BOSS_SEGMENTS:
		var x := n * (width + gap)
		var start := float(n) / BOSS_SEGMENTS
		var end := float(n + 1) / BOSS_SEGMENTS
		var segment := Rect2(x, 0.0, width, rect.size.y)
		boss_bar.draw_rect(segment, Color(0.16, 0.04, 0.04, 1.0))
		var trail := clampf((_boss_trail - start) / (end - start), 0.0, 1.0)
		if trail > 0.0:
			boss_bar.draw_rect(Rect2(x, 0.0, width * trail, rect.size.y), Color(1.0, 0.92, 0.7, 0.9))
		var part := clampf((_boss_fraction - start) / (end - start), 0.0, 1.0)
		if part > 0.0:
			boss_bar.draw_rect(Rect2(x, 0.0, width * part, rect.size.y), fill)
			boss_bar.draw_rect(Rect2(x, 0.0, width * part, 3.0), fill.lightened(0.35))
	# Quarter ticks for reading thresholds at a glance.
	for q in [0.25, 0.5, 0.75]:
		var tx: float = rect.size.x * q
		boss_bar.draw_line(Vector2(tx, -3.0), Vector2(tx, rect.size.y + 3.0), Color(1, 0.85, 0.7, 0.5), 1.0)
	boss_bar.draw_rect(rect, Color(1, 0.4, 0.25, 0.6), false, 1.0)

func _draw_ability_cooldown() -> void:
	if _ability == null or _ability_ready or _ability_charge >= 1.0:
		return
	var size := ability_cooldown.size
	var center := size * 0.5
	var half := center - Vector2(3, 3)
	# Remaining cooldown as a dark wedge sweeping clockwise from 12 o'clock,
	# cast onto the square slot so it covers the corners too.
	var points := PackedVector2Array([center])
	var start := -PI * 0.5 + TAU * _ability_charge
	var steps := 40
	for n in steps + 1:
		var angle := lerpf(start, -PI * 0.5 + TAU, float(n) / steps)
		var direction := Vector2(cos(angle), sin(angle))
		var reach := minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
		points.append(center + direction * reach)
	ability_cooldown.draw_colored_polygon(points, Color(0.0, 0.02, 0.03, 0.72))
	ability_cooldown.draw_arc(center, size.x * 0.5 + 6.0, -PI * 0.5, -PI * 0.5 + TAU * _ability_charge, 40, ability_ready_color, 3.0, true)

func _draw_warning_band() -> void:
	var size := warning_band.size
	warning_band.draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.01, 0.01, 0.78))
	var stripe := 12.0
	var offset := fmod(_time * 60.0, stripe * 2.0)
	for y in [0.0, size.y - 10.0]:
		var x := -stripe * 2.0 + offset
		while x < size.x + stripe:
			warning_band.draw_colored_polygon(PackedVector2Array([
				Vector2(x, y + 10.0), Vector2(x + stripe, y + 10.0),
				Vector2(x + stripe * 2.0, y), Vector2(x + stripe, y),
			]), Color(1.0, 0.62, 0.1, 0.95))
			x += stripe * 2.0
	warning_band.draw_line(Vector2(0, 11), Vector2(size.x, 11), Color(1, 0.4, 0.1, 0.9), 2.0)
	warning_band.draw_line(Vector2(0, size.y - 11), Vector2(size.x, size.y - 11), Color(1, 0.4, 0.1, 0.9), 2.0)

func _show_warning(boss_title: String) -> void:
	warning_subtitle.text = "%s INBOUND" % boss_title
	warning.show()
	warning.pivot_offset = warning.size * 0.5
	warning.scale = Vector2(1.0, 0.0)
	warning.modulate.a = 1.0
	warning_title.modulate.a = 1.0
	if _warning_tween != null:
		_warning_tween.kill()
	_warning_tween = create_tween()
	_warning_tween.tween_property(warning, "scale:y", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for n in 3:
		_warning_tween.tween_property(warning_title, "modulate:a", 0.25, 0.14)
		_warning_tween.tween_property(warning_title, "modulate:a", 1.0, 0.14)
	_warning_tween.tween_interval(WARNING_HOLD)
	_warning_tween.tween_property(warning, "modulate:a", 0.0, 0.3)
	_warning_tween.parallel().tween_property(warning, "scale:y", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_warning_tween.tween_callback(warning.hide)

func _refresh_armor() -> void:
	var armor := _state.armor if _state != null else 0.0
	armor_box.visible = armor > 0.0
	armor_value.text = str(roundi(armor))

# ------------------------------------------------------------------ builders

func _add_hand_slot() -> void:
	var index := _slots.size()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	_slot_styles.append(style)
	var root := PanelContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = HAND_SLOT_SIZE
	root.add_theme_stylebox_override(&"panel", style)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	root.add_child(rows)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 4)
	rows.add_child(top)
	var key := _label(str(index + 1), 14, Color.WHITE)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(key)
	var type := _icon(null, 16)
	top.add_child(type)
	var pellets := _label("×1", 13, Color(0.75, 0.85, 0.88))
	top.add_child(pellets)
	var weapon := _icon(null, 48)
	weapon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_child(weapon)
	var ammo := _label("", 14, Color(0.87, 0.95, 0.98))
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(ammo)
	var reload := _gun_meter(focus_color)
	rows.add_child(reload)
	var alternate := _label("", 10, Color.WHITE)
	alternate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alternate.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(alternate)
	var charge := _gun_meter(ability_ready_color)
	rows.add_child(charge)
	var mods := HBoxContainer.new()
	mods.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mods.custom_minimum_size.y = 16
	mods.alignment = BoxContainer.ALIGNMENT_CENTER
	mods.add_theme_constant_override(&"separation", 2)
	rows.add_child(mods)
	hand_row.add_child(root)
	_slots.append({"root": root, "key": key, "type": type, "pellets": pellets, "weapon": weapon, "mods": mods, "ammo": ammo, "reload": reload, "alternate": alternate, "charge": charge})

func _stat_tile(texture: Texture2D, value: String, caption: String) -> Control:
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(120, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.08, 1)
	style.border_color = Color(0.1, 0.35, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	tile.add_theme_stylebox_override(&"panel", style)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	tile.add_child(rows)
	var icon := _icon(texture, 32)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_child(icon)
	var number := _label(value, 24, Color(0.9, 0.97, 1))
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(number)
	var label := _label(caption, 11, Color(0.45, 0.62, 0.66))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(label)
	return tile

func _key_hint(key: String, action: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.12)
	style.border_color = Color(1, 0.58, 0.22)
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override(&"panel", style)
	chip.add_child(_label(key, 16, Color(1, 0.8, 0.55)))
	row.add_child(chip)
	var label := _label(action, 17, Color(0.82, 0.92, 0.95))
	row.add_child(label)
	return row

func _chip(text: String, color: Color) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.7), 0.9)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	chip.add_theme_stylebox_override(&"panel", style)
	chip.add_child(_label(text, 11, color.lightened(0.3)))
	return chip

func _icon(texture: Texture2D, pixels: float) -> TextureRect:
	var icon := GameIcons.rect(texture, pixels)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label

func _pop(control: Control, amount: float = 1.25) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(amount, amount)
	var tween := control.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.22)
