class_name VersusSetup
extends Control
## Binding script of the "versus_setup" layout: the page where a versus match
## is configured. The scene owns one toggle Button per choice, named as listed
## in OPTIONS, plus (REQUIRED_NODES):
##   VersusLevelRow      whatever holds the level buttons (hidden for rising
##                       speed)
##   VersusDescription   Label describing the focused choice
##   VersusStartButton   Button that starts the match
## The page does not keep the choices itself: the mode select tells it what
## is picked (show_choices) and listens to its signals.

## Group -> {value: button name}.
const OPTIONS: Dictionary = {
	"rules": {&"fixed": "VersusSpeedFixedSpeed", &"rising": "VersusSpeedRisingSpeed"},
	"level": {
		1: "VersusLevel1", 2: "VersusLevel2", 3: "VersusLevel3", 4: "VersusLevel4", 5: "VersusLevel5",
		6: "VersusLevel6", 7: "VersusLevel7", 8: "VersusLevel8", 9: "VersusLevel9", 10: "VersusLevel10",
	},
	"left": {
		&"you": "VersusPlayerYou", &"easy": "VersusPlayerEasy", &"normal": "VersusPlayerNormal",
		&"hard": "VersusPlayerHard", &"lunatic": "VersusPlayerLunatic",
	},
	"difficulty": {
		&"easy": "VersusCPUEasy", &"normal": "VersusCPUNormal", &"hard": "VersusCPUHard", &"lunatic": "VersusCPULunatic",
	},
	"format": {&"single": "VersusMatchSingleMatch", &"best_of_3": "VersusMatchBestof3"},
}
const REQUIRED_NODES: Array[String] = [
	"VersusLevelRow", "VersusDescription", "VersusStartButton",
	"VersusSpeedFixedSpeed", "VersusSpeedRisingSpeed",
	"VersusLevel1", "VersusLevel2", "VersusLevel3", "VersusLevel4", "VersusLevel5",
	"VersusLevel6", "VersusLevel7", "VersusLevel8", "VersusLevel9", "VersusLevel10",
	"VersusPlayerYou", "VersusPlayerEasy", "VersusPlayerNormal", "VersusPlayerHard", "VersusPlayerLunatic",
	"VersusCPUEasy", "VersusCPUNormal", "VersusCPUHard", "VersusCPULunatic",
	"VersusMatchSingleMatch", "VersusMatchBestof3",
]

## A choice was clicked: its group and value.
signal option_picked(group: String, value: Variant)
## A choice got the keyboard focus or the pointer.
signal option_focused(group: String, value: Variant)
signal start_focused
signal start_pressed

var level_row: Control
var description: Label
var start_button: Button

## group -> {value: Button}
var _buttons: Dictionary = {}


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
	# The description is rewritten with already translated copy.
	description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for group: String in OPTIONS:
		_buttons[group] = {}
		for value: Variant in OPTIONS[group]:
			var button: Button = get_node(NodePath("%" + String(OPTIONS[group][value]))) as Button
			button.toggle_mode = true
			for state: String in ["font_pressed_color", "font_hover_pressed_color"]:
				button.add_theme_color_override(state, ResourcePack.color("highlight"))
			button.pressed.connect(option_picked.emit.bind(group, value))
			button.focus_entered.connect(option_focused.emit.bind(group, value))
			button.mouse_entered.connect(option_focused.emit.bind(group, value))
			_buttons[group][value] = button
	start_button.pressed.connect(start_pressed.emit)
	start_button.focus_entered.connect(start_focused.emit)


func button(group: String, value: Variant) -> Button:
	return (_buttons.get(group, {}) as Dictionary).get(value) as Button


## Highlights the picked option of every group ({group: value}) and shows
## the level row only for fixed speed.
func show_choices(choices: Dictionary) -> void:
	for group: String in _buttons:
		for value: Variant in _buttons[group]:
			(_buttons[group][value] as Button).set_pressed_no_signal(value == choices.get(group))
	level_row.visible = choices.get("rules") == &"fixed"


func describe(text: String) -> void:
	description.text = text
