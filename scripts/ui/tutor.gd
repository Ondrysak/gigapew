class_name Tutor
extends PanelContainer

## First-time tips: one short, non-blocking card at a time, above the skill
## bar. Each tip id shows once per profile; turning off Guided start in
## Settings silences them. Pausable: a tip waits out pauses and menus rather
## than expiring behind them.

const TIPS := {
	&"basics": ["MOVE AND SHOOT", "WASD moves and the mouse aims. Hold LMB to fire: your gun never runs dry. The mouse wheel swaps guns."],
	&"contract": ["YOUR CONTRACT", "The list on the left is this level's job: mine the ore and defeat the listed enemies. Finishing it calls your extraction."],
	&"mining": ["MINING", "Your drill comes out near ore. Hold F to cut a section; the glowing ◇ weak seam cuts faster."],
	&"repair": ["LOW HEALTH", "Walk over red repair kits to heal. Enemies drop them, and supply packs land nearby over time."],
	&"extraction": ["EXTRACTION", "Contract done! Follow the green beam and stand in the pod's ring until it lifts off. Enemies surge until then."],
	&"combos": ["SKILL COMBOS", "Blast skills inside your Gravity Well CRUSH for +60%. Cast Pulse Barrier near the well to COLLAPSE it. Dash while shielded to SHIELD RAM."],
}
const MIN_SECONDS := 5.0
const SECONDS_PER_WORD := 0.32
## A tip counts as seen only after this long on screen; interrupted tips return.
const SEEN_AFTER := 2.0

var showing: StringName = &""
var _queue: Array[Dictionary] = []
var _left := 0.0
var _shown := 0.0
var _title: Label
var _body: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.035, 0.05, 0.9)
	style.border_color = Color(0.25, 0.9, 1.0, 0.9)
	style.border_width_left = 4
	style.set_content_margin_all(12.0)
	style.content_margin_left = 16.0
	style.set_corner_radius_all(4)
	add_theme_stylebox_override(&"panel", style)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -280.0
	offset_right = 280.0
	offset_top = -250.0
	offset_bottom = -160.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 4)
	add_child(rows)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 15)
	_title.add_theme_color_override(&"font_color", Color(0.45, 0.95, 1.0))
	rows.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 528.0
	_body.add_theme_font_size_override(&"font_size", 14)
	_body.add_theme_color_override(&"font_color", Color(0.86, 0.93, 0.96))
	rows.add_child(_body)
	hide()

## Queues a tip unless guided start is off or this profile has seen it.
## Unlisted ids (new skills) pass their own title and text.
func offer(id: StringName, title: String = "", text: String = "") -> void:
	if not bool(Profile.settings.get("guided_start", true)) or Profile.tip_seen(id) or showing == id:
		return
	for queued in _queue:
		if queued.id == id:
			return
	if TIPS.has(id):
		title = TIPS[id][0]
		text = TIPS[id][1]
	_queue.append({"id": id, "title": title, "text": text})

## Drops every pending and visible tip, e.g. on stage teardown or death.
func clear() -> void:
	_queue.clear()
	showing = &""
	hide()

func _process(delta: float) -> void:
	if showing != &"":
		_left -= delta
		_shown += delta
		if _shown >= SEEN_AFTER:
			Profile.mark_tip_seen(showing)
		if _left > 0.0:
			return
		showing = &""
		hide()
	if _queue.is_empty():
		return
	var tip: Dictionary = _queue.pop_front()
	showing = tip.id
	_shown = 0.0
	_title.text = tip.title
	_body.text = tip.text
	_left = maxf(MIN_SECONDS, tip.text.split(" ").size() * SECONDS_PER_WORD)
	modulate.a = 0.0
	show()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
