class_name LevelUpScreen
extends CanvasLayer

## Pause-time upgrade picker. The consumer pauses the tree before present()
## and unpauses after `chosen`; this layer (and its tweens) process while paused.

signal chosen(upgrade: UpgradeDefinition)

const KEY_ACTIONS: Array[StringName] = [&"ability_1", &"ability_2", &"ability_3", &"ability_4", &"ability_5"]
## Entrance: cards rise in one after another.
const CARD_STAGGER := 0.05
const CARD_RISE := 46.0
const CARD_DURATION := 0.22

## Every LevelUpCard child is an offer slot, in order.
@export var card_container: Container
@export var level_label: Label
@export var header: Control
@export var title_label: Label
@export var dim: CanvasItem
## Ignores picks briefly so a held key/click cannot choose blindly.
@export var input_delay := 0.25

var _cards: Array[LevelUpCard] = []
var _offers: Array[UpgradeDefinition] = []
var _open := false
var _arming := 0.0
var _entrance: Tween
var _presentation := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	for child in card_container.get_children():
		var card := child as LevelUpCard
		if card == null:
			continue
		card.pressed.connect(_choose.bind(_cards.size()))
		_cards.append(card)

func present(offers: Array[UpgradeDefinition], run_state: RunState, title: String = "LEVEL UP", subtitle: String = "") -> void:
	_offers.assign(offers)
	title_label.text = title
	level_label.text = subtitle if not subtitle.is_empty() else "OPERATOR LEVEL %d" % run_state.level
	for index in range(_cards.size()):
		var card := _cards[index]
		if index < _offers.size():
			var upgrade := _offers[index]
			var rank := run_state.ability_rank(upgrade.ability_slot) if upgrade.kind == UpgradeDefinition.Kind.ABILITY else run_state.level_of(upgrade)
			card.show_offer(upgrade, rank, index + 1)
			card.show()
		else:
			card.hide()
	_open = true
	_arming = input_delay
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_animate_in()

func _animate_in() -> void:
	_presentation += 1
	var presentation := _presentation
	_settle()
	for card in _cards:
		card.modulate.a = 0.0
	header.modulate.a = 0.0
	dim.modulate.a = 0.0
	# Let the containers place the cards before animating from their slots.
	await get_tree().process_frame
	if presentation != _presentation or not visible:
		return
	_entrance = create_tween().set_parallel().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_entrance.tween_property(dim, "modulate:a", 1.0, 0.15)
	header.pivot_offset = header.size * 0.5
	header.scale = Vector2(1.25, 1.25)
	_entrance.tween_property(header, "modulate:a", 1.0, 0.15)
	_entrance.tween_property(header, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var order := 0
	for card in _cards:
		if not card.visible:
			continue
		var delay := CARD_STAGGER * order
		var rest := card.position.y
		card.position.y = rest + CARD_RISE
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2(0.92, 0.92)
		_entrance.tween_property(card, "modulate:a", 1.0, CARD_DURATION * 0.7).set_delay(delay)
		_entrance.tween_property(card, "position:y", rest, CARD_DURATION).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_entrance.tween_property(card, "scale", Vector2.ONE, CARD_DURATION).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		order += 1

func _process(delta: float) -> void:
	if _open:
		_arming -= delta

func _input(event: InputEvent) -> void:
	if not _open:
		return
	for index in range(KEY_ACTIONS.size()):
		if event.is_action_pressed(KEY_ACTIONS[index]):
			get_viewport().set_input_as_handled()
			_choose(index)
			return

func _choose(index: int) -> void:
	if not _open or _arming > 0.0 or index >= _offers.size():
		return
	_open = false
	_presentation += 1
	_settle()
	hide()
	# Numeric keys also trigger combat skills. Clear their pressed/just-pressed
	# state before the consumer resumes gameplay; the UI already owns the event.
	for action in KEY_ACTIONS:
		Input.action_release(action)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(_offers[index])

## Ends an interrupted entrance with every element at rest in its slot.
func _settle() -> void:
	if _entrance != null:
		_entrance.kill()
	for card in _cards:
		card.modulate.a = 1.0
		card.scale = Vector2.ONE
	header.modulate.a = 1.0
	header.scale = Vector2.ONE
	dim.modulate.a = 1.0
	card_container.queue_sort()
