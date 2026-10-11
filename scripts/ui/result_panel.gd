class_name ResultPanel
extends Control
## Binding script of the "result_panel" layout: the panel over the game when a
## round, a match or a classic game ends. Required nodes (REQUIRED_NODES):
##   Title, Detail, Extra   Labels (headline, one line of numbers, an
##                          optional second line)
##   Buttons                container the game fills with the choices

const REQUIRED_NODES: Array[String] = ["Title", "Detail", "Extra", "Buttons"]

var title: Label
var detail: Label
var extra: Label
var buttons: Container


var _bound: bool = false


func _ready() -> void:
	bind()


## Looks the layout's nodes up. Runs from _ready(); owners that use the layout
## before it is inside the tree call it themselves.
func bind() -> void:
	if _bound:
		return
	_bound = true
	title = get_node(^"%Title") as Label
	detail = get_node(^"%Detail") as Label
	extra = get_node(^"%Extra") as Label
	buttons = get_node(^"%Buttons") as Container
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The game writes already translated copy into the labels.
	for label: Label in [title, detail, extra]:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	visible = false
	buttons.visible = false


## Shows the headline and its lines; an empty `extra_text` hides that line.
func show_result(title_text: String, title_color: Color, detail_text: String, extra_text: String = "") -> void:
	title.text = title_text
	title.add_theme_color_override("font_color", title_color)
	detail.text = detail_text
	extra.text = extra_text
	extra.visible = not extra_text.is_empty()
	visible = true


## Adds one choice. `text` is the English key (auto-translated); the node is
## named "<Text>Button" without spaces.
func add_button(text: String, pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.name = text.replace(" ", "") + "Button"
	button.text = text
	button.pressed.connect(pressed)
	buttons.add_child(button)
	return button
