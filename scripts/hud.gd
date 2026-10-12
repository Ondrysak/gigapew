class_name ArenaHUD
extends CanvasLayer

## In-run overlay. Static layout lives in hud.tscn; the primary firearm,
## five independent abilities and loot readouts are built from gameplay data.

const LOW_HEALTH_FRACTION := 0.3
const BOSS_PHASE_FRACTION := 0.3
const BOSS_SEGMENTS := 20
## Seconds the boss bar's damage trail holds before draining to the real value.
const TRAIL_HOLD := 0.45
const TRAIL_SPEED := 0.6
## Seconds the WARNING banner rests after blinking, before it folds away.
const WARNING_HOLD := 0.3
const PICKUP_NOTICE_SECONDS := 3.0
const NOTICE_FADE_SECONDS := 0.4
const PICKUP_KINDS: Array[StringName] = [&"magnet", &"repair"]
const BOSS_CUE_TITLES: Array[String] = ["DRŽ SI ODSTUP", "ROZBĚH PROTI TOBĚ", "ROZBĚH PROTI TOBĚ", "TŘI RÁNY SHORA", "TŘI RÁNY SHORA", "KRYT DOLE", ""]

@export var healthy_color := Color(0.57, 0.61, 0.36)
@export var critical_color := Color(0.88, 0.28, 0.22)
@export var boss_color := Color(0.81, 0.48, 0.24)
@export var boss_phase_color := Color(0.81, 0.24, 0.22)
@export var ability_ready_color := Color(0.75, 0.72, 0.45)
@export var ability_charging_color := Color(0.53, 0.49, 0.4)
@export var focus_color := Color(0.84, 0.62, 0.32)

@onready var sector_label: Label = $Stage/Rows/Sector
@onready var subtitle_label: Label = $Stage/Rows/Subtitle
@onready var resource_row: HBoxContainer = $Stage/Rows/Resources
@onready var supply_bar: ProgressBar = $Stage/Rows/Supply/Bar
@onready var supply_value: Label = $Stage/Rows/Supply/Value
@onready var contract_box: Control = $Contract
@onready var contract_label: Label = $Contract/Label
@onready var quest_panel: PanelContainer = $Quests
@onready var quest_list: VBoxContainer = $Quests/Rows/List
@onready var quest_seed: Label = $Quests/Rows/Header/Seed
var _quests: LevelQuests
var _quest_rows: Array[Dictionary] = []
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
@onready var ability_row: HBoxContainer = $Abilities
@onready var controls_label: Label = $Controls
## First-time tips, built in code above the skill bar.
var tutor: Tutor
var _unlocked_shown := -1
@onready var primary_title: Label = $Primary/Header/Title
@onready var mod_row: HBoxContainer = $Primary/Header/Mods
@onready var primary_row: HBoxContainer = $Primary/Details
@onready var mining_prompt: Label = $MiningPrompt
@onready var pickup_notices: VBoxContainer = $PickupNotices
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

@onready var objective: PanelContainer = $Objective
@onready var objective_title: Label = $Objective/Rows/Header/Title
@onready var objective_detail: Label = $Objective/Rows/Detail
@onready var objective_progress: ProgressBar = $Objective/Rows/Progress
@onready var boss_cue: PanelContainer = $BossCue
@onready var boss_cue_title: Label = $BossCue/Rows/Header/Title
@onready var boss_cue_time: Label = $BossCue/Rows/Header/Time
@onready var boss_cue_instruction: Label = $BossCue/Rows/Instruction
@onready var boss_cue_progress: ProgressBar = $BossCue/Rows/Progress
var _resource_labels: Dictionary = {}
var _definitions: Array[ResourceDefinition] = []
var _state: RunState
var _stage_name := ""
var _time := 0.0
var _last_health := 0
var _health_fraction := 1.0
var _level := 0
var _health_fill: StyleBoxFlat
var _vitals_style: StyleBoxFlat
var _vitals_border := Color()
var _primary_icon: TextureRect
var _primary_stats: Label
var _abilities: Array[ActiveAbility] = []
var _ability_tiles: Array[Dictionary] = []
# Boss frame: real fraction, delayed trail and hit flash.
var _boss_fraction := 1.0
var _boss_trail := 1.0
var _boss_hold := 0.0
var _boss_flash := 0.0
var _warning_tween: Tween
# Fixed loot rows aggregate independently.
var _pickup_rows: Array[Dictionary] = []
var _pickup_amounts := PackedInt32Array([0, 0])
var _pickup_times := PackedFloat32Array([0.0, 0.0])
var _pickup_dirty := false
var _boss_cue_style: StyleBoxFlat
## Label and colour per skill combo id from ArenaPlayer.ability_combo.
const COMBO_CALLOUTS := {
	&"crush": ["POWNED", Color(0.78, 0.65, 0.4)],
	&"collapse": ["PERMABAN", Color(0.78, 0.4, 0.32)],
	&"ram": ["LAST TIME KRATOS", Color(0.71, 0.73, 0.48)],
}
var _combo_callout: Label
var _combo_tween: Tween
var gear_hud: GearHUD
var _gear_status: Label
var _gear_prompt: Label

func _build_gear_overlay() -> void:
	gear_hud = GearHUD.new()
	gear_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	gear_hud.offset_left = -210.0
	gear_hud.offset_right = 210.0
	gear_hud.offset_top = 100.0
	gear_hud.offset_bottom = 174.0
	add_child(gear_hud)
	_gear_status = _label("", 12, Color(0.8, 0.74, 0.57))
	_gear_status.position = Vector2(16.0, 394.0)
	_gear_status.size = Vector2(304.0, 54.0)
	_gear_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_status.add_theme_color_override(&"font_outline_color", Color(0.03, 0.02, 0.015))
	_gear_status.add_theme_constant_override(&"outline_size", 3)
	add_child(_gear_status)
	_gear_prompt = _label("", 16, Color(0.91, 0.79, 0.49))
	_gear_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_gear_prompt.offset_left = -300.0
	_gear_prompt.offset_right = 300.0
	_gear_prompt.offset_top = 48.0
	_gear_prompt.offset_bottom = 95.0
	_gear_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_prompt.add_theme_color_override(&"font_outline_color", Color(0.03, 0.02, 0.015))
	_gear_prompt.add_theme_constant_override(&"outline_size", 4)
	add_child(_gear_prompt)

func set_gear_loot(loot: GearLootDirector, playing: bool) -> void:
	gear_hud.visible = not death.visible and not boss_cue.visible and not warning.visible
	var available := is_instance_valid(loot) and playing and not death.visible
	_gear_status.visible = available
	_gear_prompt.visible = available
	if available:
		_gear_status.position.y = quest_panel.get_rect().end.y + 6.0
		_gear_status.text = loot.status_text()
		_gear_prompt.text = loot.interaction_text()

func _ready() -> void:
	_health_fill = (health_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).duplicate()
	health_bar.add_theme_stylebox_override(&"fill", _health_fill)
	_vitals_style = (vitals.get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate()
	vitals.add_theme_stylebox_override(&"panel", _vitals_style)
	_vitals_border = _vitals_style.border_color
	_boss_cue_style = (boss_cue.get_theme_stylebox(&"panel") as StyleBoxFlat).duplicate()
	boss_cue.add_theme_stylebox_override(&"panel", _boss_cue_style)
	boss_bar.draw.connect(_draw_boss_bar)
	warning_band.draw.connect(_draw_warning_band)
	death_keys.add_child(_key_hint("R", "ZNOVU"))
	death_keys.add_child(_key_hint("ENTER", "MENU"))
	_build_notices()
	_build_primary()
	_build_abilities()
	_build_combo_callout()
	_build_gear_overlay()
	var music_layers := MusicLayers.new()
	music_layers.name = "MusicLayers"
	add_child(music_layers)
	move_child(music_layers, feedback.get_index())
	tutor = Tutor.new()
	add_child(tutor)
	StreetWear.apply_tree(self)
	StreetWear.apply(death_panel, true)

func _build_combo_callout() -> void:
	_combo_callout = Label.new()
	_combo_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_callout.add_theme_font_size_override(&"font_size", 30)
	_combo_callout.add_theme_color_override(&"font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	_combo_callout.add_theme_constant_override(&"outline_size", 6)
	_combo_callout.set_anchors_preset(Control.PRESET_CENTER)
	_combo_callout.offset_left = -220.0
	_combo_callout.offset_right = 220.0
	# Below the crosshair, clear of the damage numbers rising from the target.
	_combo_callout.offset_top = 70.0
	_combo_callout.offset_bottom = 110.0
	_combo_callout.pivot_offset = Vector2(220.0, 20.0)
	_combo_callout.hide()
	add_child(_combo_callout)

## Pops a short named callout below the crosshair when two skills combine.
func show_ability_combo(id: StringName) -> void:
	if feedback.terminal or not COMBO_CALLOUTS.has(id):
		return
	var entry: Array = COMBO_CALLOUTS[id]
	_callout("KOMBO  ·  %s" % entry[0], entry[1])

## Guided start: a new skill slot announces itself and its tile pops in.
func show_skill_unlocked(skill: ActiveAbility) -> void:
	if feedback.terminal:
		return
	_callout("NOVÝ TRIK  ·  %d  %s" % [skill.slot + 1, skill.display_name.to_upper()], ability_ready_color)
	if skill.slot < _ability_tiles.size():
		var root: Control = _ability_tiles[skill.slot].root
		root.show()
		_pop(root, 1.35)

func _callout(text: String, color: Color) -> void:
	_combo_callout.text = text
	_combo_callout.add_theme_color_override(&"font_color", color)
	_combo_callout.modulate.a = 1.0
	_combo_callout.scale = Vector2(1.35, 1.35)
	_combo_callout.show()
	if _combo_tween != null:
		_combo_tween.kill()
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo_callout, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_interval(0.9)
	_combo_tween.tween_property(_combo_callout, "modulate:a", 0.0, 0.3)
	_combo_tween.tween_callback(_combo_callout.hide)

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

func set_abilities(abilities: Array[ActiveAbility]) -> void:
	_abilities = abilities
	ability_row.visible = not abilities.is_empty()
	_refresh_abilities()

## Unlocked skills show live state; under guided start the next locked slot
## shows as a dim teaser with its unlock level, and later ones stay hidden.
func _refresh_abilities() -> void:
	var unlocked_count := 0
	for index in _ability_tiles.size():
		var tile: Dictionary = _ability_tiles[index]
		var root: Control = tile.root
		if index >= _abilities.size():
			root.visible = false
			continue
		var ability := _abilities[index]
		var state := ability.run_state
		var unlocked := state == null or state.is_ability_unlocked(index)
		var teaser := not unlocked and state.is_ability_unlocked(index - 1)
		root.visible = unlocked or teaser
		if unlocked:
			unlocked_count += 1
		if not root.visible:
			continue
		(tile.name as Label).text = ability.display_name.to_upper()
		(tile.icon as TextureRect).texture = ability.icon
		if teaser:
			var level := state.ability_unlock_level(index)
			(tile.icon as TextureRect).modulate = Color(0.36, 0.33, 0.27, 0.55)
			(tile.rank as Label).text = ""
			(tile.status as Label).text = "ÚR %d" % level
			(tile.status as Label).modulate = Color(0.64, 0.58, 0.47)
			(tile.meter as ProgressBar).value = 0.0
			(tile.style as StyleBoxFlat).border_color = Color(0.32, 0.27, 0.19)
			root.tooltip_text = "Odemkne se na úrovni %d · klávesa %d\n%s" % [level, index + 1, ability.description]
			continue
		var ready := ability.is_ready()
		var remaining := ability.cooldown_remaining()
		(tile.icon as TextureRect).modulate = Color.WHITE if ready else Color(0.56, 0.5, 0.4)
		(tile.rank as Label).text = "S%d" % ability.rank()
		(tile.status as Label).text = "PŘIPR." if ready else "%.1f s" % remaining
		(tile.status as Label).modulate = ability_ready_color if ready else Color.WHITE
		(tile.meter as ProgressBar).value = clampf(1.0 - remaining / maxf(0.001, ability.cooldown_total()), 0.0, 1.0)
		(tile.style as StyleBoxFlat).border_color = ability_ready_color if ready else ability_charging_color.darkened(0.45)
		root.tooltip_text = "%s · klávesa %d · stupeň %d / %d\n%s" % [ability.display_name, index + 1, ability.rank(), RunState.MAX_ABILITY_RANK, ability.description]
	if unlocked_count != _unlocked_shown:
		_unlocked_shown = unlocked_count
		var skills := "1 TRIK" if unlocked_count <= 1 else "1–%d TRIKY" % unlocked_count
		controls_label.text = "WASD POHYB · SPACE SKOK · LMB ÚTOK · KOLEČKO ZBRAŇ · F PÁČ AUTOMAT · %s · E POUŽÍT · G VÝBAVA · ESC PAUZA" % skills

func show_stage(stage: StageDefinition, index: int, total: int) -> void:
	death.hide()
	boss_panel.hide()
	warning.hide()
	objective.hide()
	boss_cue.hide()
	contract_box.show()
	_last_health = 0
	_stage_name = "OKRUH %02d  ·  %s" % [index + 1, stage.display_name.to_upper()]
	sector_label.text = "%02d / %02d   %s" % [index + 1, total, stage.display_name.to_upper()]
	subtitle_label.text = stage.subtitle
	quest_panel.hide()
	feedback.reset()
	_reset_notices()

## Build once per level; compartment loot/death signals update real counters.
func set_quests(state: LevelQuests, seed_value: int) -> void:
	_quests = state
	for child in quest_list.get_children():
		child.free()
	_quest_rows.clear()
	quest_seed.text = "#%08X" % seed_value
	$Quests/Rows/Hint.text = "Zamiř zblízka na přihrádku · drž F a páč · dokonči zakázku pro odvoz"
	for quest: Dictionary in state.quests:
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", 3)
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		line.add_child(_icon(quest.icon, 24))
		var action: String
		match quest.kind:
			&"mine": action = "VYPÁČ"
			&"kill": action = "ROZPRAŠ"
			&"stash":
				action = "VYBER"
				$Quests/Rows/Hint.text = "F · páč přihrádky   E · vyber alespoň %d skrýše\nDokonči celou zakázku pro odvoz" % quest.target
		var text := _label("%s %s" % [action, String(quest.name).to_upper()], 13, quest.color.lightened(0.15))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(text)
		var count := _label("", 13, Color.WHITE)
		line.add_child(count)
		row.add_child(line)
		var bar := _progress_meter(quest.color)
		bar.max_value = quest.target
		row.add_child(bar)
		quest_list.add_child(row)
		_quest_rows.append({"row": row, "count": count, "bar": bar})
	quest_panel.show()
	refresh_quests()

func refresh_quests() -> void:
	if _quests == null:
		return
	contract_label.text = "ZAKÁZKA  %d / %d" % [_quests.completed_count(), _quests.quests.size()]
	for index in _quest_rows.size():
		var quest: Dictionary = _quests.quests[index]
		var row: Dictionary = _quest_rows[index]
		var done: bool = quest.progress >= quest.target
		(row.count as Label).text = "HOTOVO" if done else "%d / %d" % [quest.progress, quest.target]
		(row.count as Label).modulate = ability_ready_color if done else Color.WHITE
		(row.bar as ProgressBar).value = quest.progress
		(row.row as Control).modulate.a = 0.65 if done else 1.0

## One objective panel: the extraction once a contract is done, otherwise the
## authored lab guarded machine when present.
func set_objectives(encounter: MiningDefense, extraction: ExtractionPod, operator: ArenaPlayer) -> void:
	if is_instance_valid(extraction) and extraction.state != ExtractionPod.State.DEPARTED and not death.visible:
		objective.visible = true
		_show_extraction(extraction, operator)
		return
	objective.visible = is_instance_valid(encounter) and encounter.state != MiningDefense.State.CANCELLED and encounter.state != MiningDefense.State.CLAIMED and not death.visible
	if not objective.visible:
		return
	var distance := roundi(operator.global_position.distance_to(encounter.global_position))
	var mined := roundi(encounter.progress() * 100.0)
	objective_progress.value = encounter.progress()
	match encounter.state:
		MiningDefense.State.WAITING:
			objective_title.text = "VOLITELNĚ · HLÍDANÝ AUTOMAT"
			objective_detail.text = "Zamiř zblízka na přihrádku a drž F · %dm\nVyprázdni automat a přežij pro vylepšení." % distance
		MiningDefense.State.MINING:
			objective_title.text = "AUTOMAT · %d%% VYPÁČENO" % mined
			objective_detail.text = "Páč mezi útoky · zbývá %d halucinací\nPři puštění F zůstává západka povolená." % encounter.enemies_remaining()
		MiningDefense.State.DEFENDING:
			objective_title.text = "AUTOMAT PRÁZDNÝ · UDRŽ MÍSTO"
			objective_detail.text = "Zbývá %d halucinací · dokonči obranu\nPak si vybereš vylepšení." % encounter.enemies_remaining()
		MiningDefense.State.READY:
			objective_title.text = "AUTOMAT TVŮJ · ODMĚNA ČEKÁ"
			objective_detail.text = "E u značky · vyber vylepšení\n%dm daleko" % distance

func set_boss_fight(fight: YardBossFight) -> void:
	boss_cue.visible = is_instance_valid(fight) and fight.state != YardBossFight.State.CANCELLED and not death.visible
	if not boss_cue.visible:
		return
	var recovering := fight.state == YardBossFight.State.RECOVERY
	var color := ability_ready_color if recovering else boss_color
	boss_cue_title.text = BOSS_CUE_TITLES[fight.state]
	boss_cue_title.add_theme_color_override(&"font_color", color)
	_boss_cue_style.border_color = color
	boss_cue_instruction.text = fight.instruction()
	boss_cue_time.text = "%.1f s" % fight.remaining()
	boss_cue_progress.value = fight.phase_progress()

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


func set_xp(xp: int, required: int, level: int) -> void:
	level_label.text = "ÚR %d" % level
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
	contract_box.hide()
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

func set_primary(state: RunState) -> void:
	_state = state
	if state.primary == null or state.primary.definition == null:
		return
	var gun := state.primary.definition
	primary_title.text = gun.display_name.to_upper()
	_primary_icon.texture = gun.icon
	var projectiles := clampi(gun.pellet_count + state.projectile_bonus, 1, WeaponBuild.MAX_PROJECTILES)
	_primary_stats.text = "%d ŠKODA · %.1f/s · ×%d\n%s · OKRUH %.1fm · PRŮRAZ %d" % [gun.damage, 1.0 / maxf(0.001, gun.fire_interval), projectiles, DamageType.label(gun.damage_type).to_upper(), gun.explosion_radius, gun.pierce + state.pierce_bonus]
	_refresh_armor()

## The crowbar prompt follows the same visible close compartment as its model.
func set_gunplay(player: ArenaPlayer) -> void:
	var ready := player.mining_ready()
	mining_prompt.visible = ready and not feedback.terminal and not get_tree().paused
	mining_prompt.text = "F · PÁČENÍ ZÁMKU" if ready and player.drilling() else "DRŽ F · VYPÁČ PŘIHRÁDKU"
	primary_row.modulate = Color(0.62, 0.55, 0.43) if ready else Color.WHITE

func _progress_meter(color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.max_value = 1.0
	meter.custom_minimum_size.y = 4
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.085, 0.065)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	meter.add_theme_stylebox_override(&"background", back)
	meter.add_theme_stylebox_override(&"fill", fill)
	return meter

## Shows installed primary-firearm mods.
func set_weapon_mods(state: RunState) -> void:
	_state = state
	for child in mod_row.get_children():
		child.queue_free()
	if state.primary != null:
		for id: StringName in state.primary.upgrade_levels:
			var rank := state.primary.rank(id)
			if rank <= 0:
				continue
			var icon := _icon(RoundShop.icon(id), 20)
			icon.tooltip_text = "%s · stupeň %d" % [RoundShop.CATALOG[id].name, rank]
			mod_row.add_child(icon)
	_refresh_armor()

func show_shot() -> void:
	feedback.show_shot()

func show_hit(killed: bool) -> void:
	feedback.show_hit(killed)

func show_combo(hits: int, bonus: float) -> void:
	feedback.show_combo(hits, bonus)

## A bounded row per kind preserves loot feedback during rapid pickups.
func show_pickup(kind: StringName, amount: int) -> void:
	if feedback.terminal or amount <= 0:
		return
	var index := PICKUP_KINDS.find(kind)
	if index < 0:
		return
	_pickup_amounts[index] += amount
	_pickup_times[index] = PICKUP_NOTICE_SECONDS
	_pickup_dirty = true


func _reset_notices() -> void:
	_pickup_amounts.fill(0)
	_pickup_times.fill(0.0)
	_pickup_dirty = false
	for row in _pickup_rows:
		(row.root as Control).hide()

func _advance_notices(delta: float) -> void:
	# Menus, uncaptured aim and death must not consume a gameplay notification.
	if get_tree().paused or feedback.terminal or not feedback.aiming:
		return
	for index in _pickup_rows.size():
		var row: Dictionary = _pickup_rows[index]
		var root: Control = row.root
		if _pickup_times[index] <= 0.0:
			continue
		if _pickup_dirty:
			var amount := _pickup_amounts[index]
			var caption := ""
			match PICKUP_KINDS[index]:
				&"magnet":
					caption = "PŘITAŽENO %d XP STŘEPŮ" % amount
				&"repair":
					caption = "+%d ZDRAVÍ" % amount
			(row.label as Label).text = caption
			root.show()
		_pickup_times[index] = maxf(0.0, _pickup_times[index] - delta)
		root.modulate.a = minf(1.0, _pickup_times[index] / NOTICE_FADE_SECONDS)
		if _pickup_times[index] <= 0.0:
			root.hide()
			_pickup_amounts[index] = 0
	_pickup_dirty = false

## Run-over panel: summary tiles plus the loot moved into the Profile.
func finish_run(level: int, kills: int, seconds: float, stages_cleared: int, banked: Dictionary) -> void:
	feedback.terminal = true
	_reset_notices()
	boss_panel.hide()
	warning.hide()
	contract_box.hide()
	quest_panel.hide()
	death_where.text = "ZASE V SEPTIKU\nPOSLEDNÍ ŠTACE: %s" % _stage_name if not _stage_name.is_empty() else "ZASE V SEPTIKU"
	for child in death_stats.get_children():
		child.queue_free()
	var whole := int(seconds)
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"level"), str(level), "ÚROVEŇ"))
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"kills"), str(kills), "ROZPRÁŠENO"))
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"timer"), "%d:%02d" % [whole / 60, whole % 60], "ČAS NA NOHOU"))
	death_stats.add_child(_stat_tile(GameIcons.lookup(&"hud", &"boss"), str(stages_cleared), "HOTOVÉ OKRUHY"))
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
		entry.add_child(_label(definition.display_name.to_upper(), 12, Color(0.75, 0.69, 0.57)))
		death_banked.add_child(entry)
	if death_banked.get_child_count() == 0:
		death_banked.add_child(_label("DO KAPSY NEZŮSTALO NIC", 16, Color(0.75, 0.69, 0.57)))
	StreetWear.apply_tree(death_panel)
	death.show()
	death.modulate.a = 0.0
	death_panel.pivot_offset = death_panel.size * 0.5
	death_panel.scale = Vector2(0.92, 0.92)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(death, "modulate:a", 1.0, 0.35)
	tween.tween_property(death_panel, "scale", Vector2.ONE, 0.4)

func _process(delta: float) -> void:
	_time += delta
	_advance_notices(delta)
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
	_refresh_abilities()
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
		fill = fill.lerp(Color(0.91, 0.48, 0.32), 0.25 + 0.25 * sin(_time * 9.0))
	fill = fill.lerp(Color(0.94, 0.86, 0.69), _boss_flash * 0.55)
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
			boss_bar.draw_rect(Rect2(x, 0.0, width * trail, rect.size.y), Color(0.88, 0.77, 0.54, 0.9))
		var part := clampf((_boss_fraction - start) / (end - start), 0.0, 1.0)
		if part > 0.0:
			boss_bar.draw_rect(Rect2(x, 0.0, width * part, rect.size.y), fill)
			boss_bar.draw_rect(Rect2(x, 0.0, width * part, 3.0), fill.lightened(0.15))
	# Quarter ticks for reading thresholds at a glance.
	for q in [0.25, 0.5, 0.75]:
		var tx: float = rect.size.x * q
		boss_bar.draw_line(Vector2(tx, -3.0), Vector2(tx, rect.size.y + 3.0), Color(0.89, 0.77, 0.58, 0.5), 1.0)
	boss_bar.draw_rect(rect, Color(0.65, 0.39, 0.23, 0.7), false, 1.0)


func _draw_warning_band() -> void:
	var size := warning_band.size
	warning_band.draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.01, 0.01, 0.78))
	var stripe := 12.0
	var offset := 0.0
	for y in [0.0, size.y - 10.0]:
		var x := -stripe * 2.0 + offset
		while x < size.x + stripe:
			warning_band.draw_colored_polygon(PackedVector2Array([
				Vector2(x, y + 10.0), Vector2(x + stripe, y + 10.0),
				Vector2(x + stripe * 2.0, y), Vector2(x + stripe, y),
			]), Color(0.72, 0.51, 0.25, 0.85))
			x += stripe * 2.0
	warning_band.draw_line(Vector2(0, 11), Vector2(size.x, 11), Color(0.57, 0.3, 0.18, 0.9), 2.0)
	warning_band.draw_line(Vector2(0, size.y - 11), Vector2(size.x, size.y - 11), Color(0.57, 0.3, 0.18, 0.9), 2.0)

func show_extraction_warning() -> void:
	_show_warning("ODVOZ")

func _show_extraction(extraction: ExtractionPod, operator: ArenaPlayer) -> void:
	# The finished contract list gives way to the extraction objective.
	quest_panel.hide()
	contract_label.text = "ODVOZ"
	var distance := roundi(extraction.distance_to(operator.global_position))
	var left := extraction.hold_time - extraction.progress
	objective_progress.value = extraction.fraction()
	if extraction.state == ExtractionPod.State.LANDING:
		objective_title.text = "ODVOZ · ZNAČKA SE BLÍŽÍ"
		objective_detail.text = "Běž ke světelnému sloupu · %dm\nHalucinace přibývají až do odjezdu." % distance
	elif extraction.player_inside():
		objective_title.text = "DRŽ SE V KRUHU · %.1f s" % left
		objective_detail.text = "Zůstaň uvnitř kruhu pro odvoz.\nHalucinace pořád přibývají."
	else:
		objective_title.text = "ODVOZ · DOBĚHNI KE ZNAČCE"
		objective_detail.text = "%dm daleko · zbývá %.0f s v kruhu\nKdyž vyběhneš, postup zůstane." % [distance, left]

func _show_warning(boss_title: String) -> void:
	warning_subtitle.text = "BLÍŽÍ SE: %s" % boss_title
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
func _build_notices() -> void:
	var glyphs: Array[StringName] = [&"magnet", &"health"]
	var colors: Array[Color] = [Color(0.78, 0.72, 0.51), Color(0.7, 0.73, 0.46)]
	for index in PICKUP_KINDS.size():
		var root := HBoxContainer.new()
		root.custom_minimum_size.y = 24
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_theme_constant_override(&"separation", 8)
		root.add_child(_icon(GameIcons.lookup(&"hud", glyphs[index]), 24))
		var label := _label("", 14, colors[index])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.95))
		label.add_theme_constant_override(&"shadow_offset_x", 1)
		label.add_theme_constant_override(&"shadow_offset_y", 1)
		root.add_child(label)
		pickup_notices.add_child(root)
		root.hide()
		_pickup_rows.append({"root": root, "label": label})

func _build_primary() -> void:
	_primary_icon = _icon(null, 48)
	primary_row.add_child(_primary_icon)
	_primary_stats = _label("", 13, Color(0.81, 0.76, 0.65))
	primary_row.add_child(_primary_stats)

func _build_abilities() -> void:
	for index in range(5):
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.085, 0.07, 0.055, 0.96)
		style.set_border_width_all(1)
		style.set_corner_radius_all(0)
		style.set_content_margin_all(5)
		var root := PanelContainer.new()
		root.custom_minimum_size = Vector2(86, 106)
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_theme_stylebox_override(&"panel", style)
		ability_row.add_child(root)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override(&"separation", 2)
		root.add_child(rows)
		var header := HBoxContainer.new()
		rows.add_child(header)
		var key := _label(str(index + 1), 14, focus_color)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(key)
		var rank_label := _label("S0", 11, Color(0.81, 0.76, 0.65))
		header.add_child(rank_label)
		var icon := _icon(null, 32)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rows.add_child(icon)
		var name_label := _label("", 10, Color(0.81, 0.76, 0.65))
		name_label.custom_minimum_size.x = 76
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(name_label)
		var status := _label("PŘIPR.", 12, ability_ready_color)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(status)
		var meter := _progress_meter(ability_ready_color)
		rows.add_child(meter)
		_ability_tiles.append({"root": root, "style": style, "icon": icon, "name": name_label, "rank": rank_label, "status": status, "meter": meter})

func _stat_tile(texture: Texture2D, value: String, caption: String) -> Control:
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(120, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.09, 0.07, 1)
	style.border_color = Color(0.44, 0.36, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	tile.add_theme_stylebox_override(&"panel", style)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	tile.add_child(rows)
	var icon := _icon(texture, 32)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_child(icon)
	var number := _label(value, 24, Color(0.9, 0.84, 0.71))
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(number)
	var label := _label(caption, 11, Color(0.75, 0.69, 0.57))
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
	style.bg_color = Color(0.13, 0.105, 0.075)
	style.border_color = focus_color
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.set_corner_radius_all(0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override(&"panel", style)
	chip.add_child(_label(key, 16, Color(0.89, 0.76, 0.52)))
	row.add_child(chip)
	var label := _label(action, 17, Color(0.86, 0.8, 0.68))
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
	style.set_corner_radius_all(0)
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
