class_name VersusSetup
extends Control
## Binding script of the "versus_setup" layout: the page where a versus match
## is configured. One layout serves three pages (show_page): Versus CPU shows
## the opponent's card, CPU Battle both CPU cards, LAN Battle the network
## card. The scene owns one toggle Button per choice, named as listed in
## OPTIONS, plus (REQUIRED_NODES):
##   LeftCard, RightCard   the CPU tier cards (left: CPU Battle only)
##   RightTitle            Label over the right card's tiers
##   LanCard               the network card; in it LanHostButton,
##                         LanJoinButton, LanAddress (LineEdit) and LanStatus
##                         (Label)
##   VersusLevelRow        whatever holds the level buttons (shown for a
##                         fixed speed only)
##   VersusDescription     Label describing the focused choice
##   VersusStartButton     Button that starts the match
## Optional (OPTIONAL_BUTTONS): the Extra tier's two buttons - a layout made
## before that tier existed simply does not offer it.
## The page does not keep the choices itself: the setup screen tells it what
## is picked (show_choices) and listens to its signals.

## Group -> {value: button name}. "rules" is the mode: Classic or a fixed speed.
const OPTIONS: Dictionary = {
	"rules": {&"rising": "VersusSpeedRisingSpeed", &"fixed": "VersusSpeedFixedSpeed"},
	"level": {
		1: "VersusLevel1", 2: "VersusLevel2", 3: "VersusLevel3", 4: "VersusLevel4", 5: "VersusLevel5",
		6: "VersusLevel6", 7: "VersusLevel7", 8: "VersusLevel8", 9: "VersusLevel9", 10: "VersusLevel10",
	},
	"left": {
		&"easy": "VersusPlayerEasy", &"normal": "VersusPlayerNormal",
		&"hard": "VersusPlayerHard", &"lunatic": "VersusPlayerLunatic", &"extra": "VersusPlayerExtra",
	},
	"difficulty": {
		&"easy": "VersusCPUEasy", &"normal": "VersusCPUNormal", &"hard": "VersusCPUHard", &"lunatic": "VersusCPULunatic",
		&"extra": "VersusCPUExtra",
	},
	"format": {&"single": "VersusMatchSingleMatch", &"best_of_3": "VersusMatchBestof3"},
}
const REQUIRED_NODES: Array[String] = [
	"LeftCard", "RightCard", "RightTitle",
	"LanCard", "LanHostButton", "LanJoinButton", "LanAddress", "LanStatus",
	"VersusLevelRow", "VersusDescription", "VersusStartButton",
	"VersusSpeedFixedSpeed", "VersusSpeedRisingSpeed",
	"VersusLevel1", "VersusLevel2", "VersusLevel3", "VersusLevel4", "VersusLevel5",
	"VersusLevel6", "VersusLevel7", "VersusLevel8", "VersusLevel9", "VersusLevel10",
	"VersusPlayerEasy", "VersusPlayerNormal", "VersusPlayerHard", "VersusPlayerLunatic",
	"VersusCPUEasy", "VersusCPUNormal", "VersusCPUHard", "VersusCPULunatic",
	"VersusMatchSingleMatch", "VersusMatchBestof3",
]
const OPTIONAL_BUTTONS: Array[String] = ["VersusPlayerExtra", "VersusCPUExtra"]
const PAGE_PVE: StringName = &"pve"
const PAGE_EVE: StringName = &"eve"
const PAGE_LAN: StringName = &"lan"

## A choice was clicked: its group and value.
signal option_picked(group: String, value: Variant)
## A choice got the keyboard focus or the pointer.
signal option_focused(group: String, value: Variant)
signal start_focused
signal start_pressed
signal lan_host_pressed
signal lan_join_pressed(address: String)

var level_row: Control
var description: Label
var start_button: Button
var left_card: Control
var right_card: Control
var right_title: Label
var lan_card: Control
var lan_host_button: Button
var lan_join_button: Button
var lan_address: LineEdit
var lan_status: Label

## group -> {value: Button}
var _buttons: Dictionary = {}
var _page: StringName = PAGE_PVE


var _bound: bool = false


func _ready() -> void:
	bind()


## Looks the layout's nodes up. Runs from _ready(); owners that use the layout
## before it is inside the tree call it themselves.
func bind() -> void:
	if _bound:
		return
	_bound = true
	level_row = get_node(^"%VersusLevelRow") as Control
	description = get_node(^"%VersusDescription") as Label
	start_button = get_node(^"%VersusStartButton") as Button
	left_card = get_node(^"%LeftCard") as Control
	right_card = get_node(^"%RightCard") as Control
	right_title = get_node(^"%RightTitle") as Label
	lan_card = get_node(^"%LanCard") as Control
	lan_host_button = get_node(^"%LanHostButton") as Button
	lan_join_button = get_node(^"%LanJoinButton") as Button
	lan_address = get_node(^"%LanAddress") as LineEdit
	lan_status = get_node(^"%LanStatus") as Label
	# The description and the status are rewritten with already translated copy.
	description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lan_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for group: String in OPTIONS:
		_buttons[group] = {}
		for value: Variant in OPTIONS[group]:
			var button: Button = get_node_or_null(NodePath("%" + String(OPTIONS[group][value]))) as Button
			if button == null and OPTIONAL_BUTTONS.has(String(OPTIONS[group][value])):
				continue
			button.toggle_mode = true
			for state: String in ["font_pressed_color", "font_hover_pressed_color"]:
				button.add_theme_color_override(state, ResourcePack.color("highlight"))
			button.pressed.connect(option_picked.emit.bind(group, value))
			button.focus_entered.connect(option_focused.emit.bind(group, value))
			button.mouse_entered.connect(option_focused.emit.bind(group, value))
			_buttons[group][value] = button
	start_button.pressed.connect(start_pressed.emit)
	start_button.focus_entered.connect(start_focused.emit)
	lan_host_button.pressed.connect(lan_host_pressed.emit)
	lan_join_button.pressed.connect(func() -> void: lan_join_pressed.emit(lan_address.text))
	lan_address.text_submitted.connect(func(text: String) -> void: lan_join_pressed.emit(text))
	show_page(_page)


func button(group: String, value: Variant) -> Button:
	return (_buttons.get(group, {}) as Dictionary).get(value) as Button


## Shows the cards of one page: "pve", "eve" or "lan".
func show_page(page: StringName) -> void:
	_page = page
	left_card.visible = page == PAGE_EVE
	right_card.visible = page != PAGE_LAN
	lan_card.visible = page == PAGE_LAN
	right_title.text = "CPU 2" if page == PAGE_EVE else "Opponent"


func page() -> StringName:
	return _page


## Highlights the picked option of every group ({group: value}) and shows
## the level row only for a fixed speed.
func show_choices(choices: Dictionary) -> void:
	for group: String in _buttons:
		for value: Variant in _buttons[group]:
			(_buttons[group][value] as Button).set_pressed_no_signal(value == choices.get(group))
	level_row.visible = choices.get("rules") == &"fixed"


func describe(text: String) -> void:
	description.text = text


func set_lan_address(address: String) -> void:
	lan_address.text = address


## LAN page state: the status line, and what may be touched - the connection
## controls, the rules (mode, level, match), the start button.
func show_lan(status: String, can_connect: bool, can_edit: bool, can_start: bool) -> void:
	lan_status.text = status
	lan_host_button.disabled = not can_connect
	lan_join_button.disabled = not can_connect
	lan_address.editable = can_connect
	for group: String in ["rules", "level", "format"]:
		for value: Variant in _buttons[group]:
			(_buttons[group][value] as Button).disabled = not can_edit
	start_button.disabled = not can_start
