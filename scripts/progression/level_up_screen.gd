class_name LevelUpScreen
extends CanvasLayer

## Pause-time upgrade picker. The consumer pauses the tree before present()
## and unpauses after `chosen`; this layer processes while paused.

signal chosen(upgrade: UpgradeDefinition)

const KEY_ACTIONS: Array[StringName] = [&"weapon_1", &"weapon_2", &"weapon_3"]

## Every LevelUpCard child is an offer slot, in order.
@export var card_container: Container
@export var level_label: Label
## Ignores picks briefly so a held key/click cannot choose blindly.
@export var input_delay := 0.25

var _cards: Array[LevelUpCard] = []
var _offers: Array[UpgradeDefinition] = []
var _open := false
var _arming := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	for child in card_container.get_children():
		var card := child as LevelUpCard
		if card == null:
			continue
		card.pressed.connect(_choose.bind(_cards.size()))
		_cards.append(card)

func present(offers: Array[UpgradeDefinition], run_state: RunState) -> void:
	_offers.assign(offers)
	level_label.text = "OPERATOR LEVEL %d" % run_state.level
	for index in range(_cards.size()):
		var card := _cards[index]
		if index < _offers.size():
			card.show_offer(_offers[index], run_state.level_of(_offers[index]), index + 1)
			card.show()
		else:
			card.hide()
	_open = true
	_arming = input_delay
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(_offers[index])
