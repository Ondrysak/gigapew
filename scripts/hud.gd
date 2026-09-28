class_name ArenaHUD
extends CanvasLayer

@export var healthy_color := Color(0.86, 0.98, 1.0)
@export var critical_color := Color(1.0, 0.3, 0.4)
@export var victory_color := Color(0.55, 1.0, 0.88)
@export var boss_phase_color := Color(1.0, 0.45, 0.25)

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

var _last_health := 0

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

func set_weapon(definition: WeaponDefinition, index: int) -> void:
	weapon_label.text = "[%d] %s" % [index + 1, definition.display_name.to_upper()]
	weapon_detail.text = definition.description

func show_shot() -> void:
	feedback.show_shot()

func show_hit(killed: bool) -> void:
	feedback.show_hit(killed)

func finish_stage(victory: bool, final_stage: bool, summary: String) -> void:
	feedback.terminal = true
	boss_panel.hide()
	message.add_theme_color_override("font_color", victory_color if victory else critical_color)
	if victory and final_stage:
		message.text = "RUN COMPLETE\n%s\nENTER  NEW RUN" % summary
	elif victory:
		message.text = "STAGE CLEAR\n%s\nENTER  NEXT STAGE" % summary
	else:
		message.text = "YOU DIED\n%s\nR  NEW RUN" % summary
	message.show()
