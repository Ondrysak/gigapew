class_name Tutor
extends PanelContainer

## First-time tips: one short, non-blocking card at a time, above the skill
## bar. Each tip id shows once per profile; turning off Guided start in
## Settings silences them. Pausable: a tip waits out pauses and menus rather
## than expiring behind them.

const TIPS := {
	&"basics": ["POHYB A RÁNY", "WASD, myš a LMB. SPACE skočí, druhý SPACE ve vzduchu vyskočí znovu. CTRL spustí slide; můžeš dál střílet. Q nebo kolečko přepíná vybranou dvojici. RMB kope a odráží blízké přilétající střely."],
	&"arena": ["KAM DÁL?", "Vyber hospodu, hernu, nonstop nebo metro a dojdi na místo. Fight začíná až tam. Rozpraš všechny živé a vyber další trasu; mezi fighty groove zůstává. Dvojici zbraní měníš jen během přestávky nebo v obchodě."],
	&"mining": ["VYSEKEJ AUTOMAT", "Zamiř zblízka na přihrádku a jednou stiskni F. Jedna rána ji otevře a vysype skutečnou kořist. Pro další přihrádku pusť a znovu stiskni F. Nemusíš stát a páčit; arena pokračuje i bez kořisti."],
	&"repair": ["OTOČ TO PROTI NIM", "Úspěšné parry a riskantní zabití zblízka doplní zdraví okamžitě. Samotné kopání do rekvizit ani zásahy do mrtvol nic nevrátí. Lékárničky a zásoby zůstávají další možností."],
	&"drop": ["TEĎ PŘIJDE DROP", "Zabití nabíjí jeden DROP; přesná, rytmická, vzdušná a slide zabití jej urychlí. Až je připravený, novým stiskem LMB vystřel pomalou zbraní na beat pro ×10 a speciální efekt. Mimo beat normálně střílíš a náboj zůstává."],
	&"pinball": ["NEPŘÍTEL JE PROJEKTIL", "Zamraz tvarohem a kopni do davu. Hořícího doraz brokovnicí. Vyhozeného sejmi railem. Zelektrizovaný dav odpal výbuchem. Slide kop vyhazuje, kop ze vzduchu sráží dolů."],
	&"finisher": ["KOP DO KSICHTU", "Zesláblý nepřítel zlatě pulzuje jen krátce. Zamiř až na 8 metrů a jednou stiskni F: skočíš k němu a jeden ze čtyř střídajících se kopů doplní zdraví. Zeď, strop nebo ztracený cíl skok přeruší. Nejsi nesmrtelný; pro další kop pusť F. Bossové se takhle dorazit nedají."],
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
