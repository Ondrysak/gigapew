class_name Tutor
extends PanelContainer

## First-time tips: one short, non-blocking card at a time, above the skill
## bar. Each tip id shows once per profile; turning off Guided start in
## Settings silences them. Pausable: a tip waits out pauses and menus rather
## than expiring behind them.

const TIPS := {
	&"basics": ["POHYB A RÁNY", "WASD pro pohyb, myš pro míření. Drž LMB a útoč: munice nikdy nedojde. Kolečkem myši měníš zbraně."],
	&"contract": ["TVŮJ KŠEFT", "Seznam vlevo je zakázka: vypáč požadovanou kořist z automatů, rozpráš uvedené halucinace a vyber alespoň dvě různé skrýše. U skrýše drž E; můžeš ji ukrást i pod palbou. Elitní drop se nepočítá, odmítnutí výbavy nevadí. Až celá zakázka přivolá odvoz."],
	&"mining": ["VYSEKEJ AUTOMAT", "Zamiř zblízka na přihrádku: páčidlo se zvedne samo. Drž F a páč zámek označený + pro ×1,75 síly. Vytrvalé páčení stejné západky přidá až 35 %. Drobné z výherního automatu, Cigára z cigaretového, Kešulky z jackpotu."],
	&"repair": ["UŽ SE SYPEŠ", "Přejdi přes červené lékárničky a doplň zdraví. Padají z nepřátel; časem poblíž přistanou i balíky zásob."],
	&"extraction": ["ODVOZ", "Zakázka hotová! Běž ke světelnému sloupu a zůstaň v kruhu odvozu až do odjezdu. Halucinace do té doby přibývají."],
	&"combos": ["TRIKY DOHROMADY", "Výbušné triky uvnitř Ban zóny spustí POWNED za +60 %. Valhalla poblíž zóny spustí PERMABAN. Úprk pod štítem spustí LAST TIME KRATOS."],
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
	style.bg_color = Color(0.095, 0.075, 0.055, 0.97)
	style.border_color = Color(0.64, 0.49, 0.28, 0.9)
	style.border_width_left = 4
	style.set_content_margin_all(12.0)
	style.content_margin_left = 16.0
	style.set_corner_radius_all(0)
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
	_title.add_theme_color_override(&"font_color", Color(0.87, 0.7, 0.4))
	rows.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 528.0
	_body.add_theme_font_size_override(&"font_size", 14)
	_body.add_theme_color_override(&"font_color", Color(0.86, 0.8, 0.67))
	rows.add_child(_body)
	StreetWear.apply_tree(self)
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
