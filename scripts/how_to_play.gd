class_name HowToPlay
extends PanelContainer
## One-page rules reference, opened from the mode select and the pause menu.
##
## Builds itself in code (title, scrolling rich text, Close button) so both
## callers only instantiate it and add it to a layer. Body copy comes from the
## HOWTO_* translation keys; key names are read from the InputMap so the page
## always lists the current bindings. ui_cancel or Close hides it and emits
## `closed`.

signal closed

const PAGE_SIZE: Vector2 = Vector2(760, 470)
const HEADING_COLOR: String = "#9ac0f2"
## Section heading key -> body key, in reading order.
const SECTIONS: Array = [
	["HOWTO_CONTROLS_TITLE", ""],
	["HOWTO_SCORING_TITLE", "HOWTO_SCORING"],
	["HOWTO_ATTACK_TITLE", "HOWTO_ATTACK"],
	["HOWTO_GARBAGE_TITLE", "HOWTO_GARBAGE"],
	["HOWTO_LOSING_TITLE", "HOWTO_LOSING"],
]
## Action label (existing HUD translation keys) -> input actions.
const CONTROL_ROWS: Array = [
	["MOVE", ["move_left", "move_right"]],
	["ROTATE", ["rotate"]],
	["ROTATE CCW", ["rotate_ccw"]],
	["SOFT DROP", ["soft_drop"]],
	["HARD DROP", ["hard_drop"]],
	["HOLD", ["hold"]],
	["PAUSE", ["pause"]],
]

var _body: RichTextLabel
var _close_button: Button


func _init() -> void:
	name = "HowToPlay"
	custom_minimum_size = PAGE_SIZE
	visible = false
	# Opaque: the page covers the menu it was opened from.
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(ResourcePack.color("window_fill"), 1.0)
	background.border_color = ResourcePack.color("window_border")
	background.set_border_width_all(2)
	background.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", background)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title: Label = Label.new()
	title.text = "How to Play"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_body = RichTextLabel.new()
	_body.name = "Body"
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.focus_mode = Control.FOCUS_NONE
	box.add_child(_body)
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "Close"
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.custom_minimum_size = Vector2(160, 0)
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


## Shows the page centered in the viewport and takes focus.
func open() -> void:
	_body.text = body_text()
	visible = true
	if is_inside_tree():
		position = (get_viewport_rect().size - PAGE_SIZE) / 2.0
		_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## The whole page as BBCode (also the read surface for tests).
func body_text() -> String:
	var parts: Array[String] = []
	for section: Array in SECTIONS:
		parts.append("[color=%s][b]%s[/b][/color]" % [HEADING_COLOR, tr(String(section[0]))])
		parts.append(_controls_block() if String(section[1]).is_empty() else tr(String(section[1])))
		parts.append("")
	return "\n".join(parts)


func _controls_block() -> String:
	var rows: Array[String] = []
	for row: Array in CONTROL_ROWS:
		rows.append("%s:  %s" % [tr(String(row[0])), " / ".join(keys_for(row[1]))])
	return "\n".join(rows)


## Adds a "How to Play" entry under Options to a pause menu instance
## (scenes/windows/pause_menu.tscn) from the outside, so the vendored template
## copy stays byte-identical. While the page is open it is the menu's
## `open_window`, which makes the menu leave ui_cancel to the page.
static func attach_to_pause_menu(menu: Control) -> void:
	var options_button: Button = menu.find_child("OptionsButton", true, false) as Button
	if options_button == null:
		return
	var page: HowToPlay = HowToPlay.new()
	menu.add_sibling.call_deferred(page)
	var button: Button = Button.new()
	button.name = "HowToPlayButton"
	button.text = "How to Play"
	options_button.add_sibling(button)
	button.pressed.connect(func() -> void:
		page.open()
		menu.set("open_window", page))
	page.closed.connect(func() -> void:
		menu.set("open_window", null)
		if button.is_visible_in_tree():
			button.grab_focus())


## Up to two key names per action, as currently bound in the InputMap.
static func keys_for(actions: Array) -> Array[String]:
	var keys: Array[String] = []
	for action: String in actions:
		if not InputMap.has_action(action):
			continue
		var shown: int = 0
		for event: InputEvent in InputMap.action_get_events(action):
			var key: InputEventKey = event as InputEventKey
			if key == null or shown >= 2:
				continue
			keys.append(OS.get_keycode_string(key.keycode if key.keycode != 0 else key.physical_keycode).to_upper())
			shown += 1
	return keys
