extends SceneTree
## Writes the default resource pack's layout scenes (packs/default/ui/*.tscn)
## and the project theme (assets/ui/base_theme.tres) from code.
##
##   godot --headless --path . --script res://tools/build_default_layouts.gd
##
## The saved .tscn files are the source of truth afterwards: open them in the
## editor and rearrange freely (keep the unique-named nodes each binding
## script in scripts/ui/ lists). RUNNING THIS TOOL AGAIN OVERWRITES THEM - it
## exists to (re)create the stock layouts, e.g. after adding a required node.

const OUT_DIR: String = "res://packs/default/ui/"
const THEME_PATH: String = "res://assets/ui/base_theme.tres"
const CARD_WIDTH: float = 176.0
const BOARD_SIZE: Vector2 = Vector2(240, 480)
const VERSUS_BOARD_SIZE: Vector2 = Vector2(220, 440)
## The board draws its frame this far outside its slot (BoardView.FRAME_WIDTH);
## the slot gets that much room, and the cards next to it are as tall as the
## frame, so every outer edge of a row lines up.
const FRAME: float = 2.0
const FRAMED: Vector2 = Vector2(0, FRAME * 2.0)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(THEME_PATH.get_base_dir())
	# Build from the default pack alone, without touching the saved choice.
	ResourcePack.set_enabled([], false)
	var theme: Theme = Theme.new()
	ResourcePack.style_theme(theme)
	_report(ResourceSaver.save(theme, THEME_PATH), THEME_PATH)
	_save(_classic_hud(), "classic_hud")
	_save(_versus_side(), "versus_side")
	_save(_versus_hud(), "versus_hud")
	_save(_result_panel(), "result_panel")
	_save(_versus_setup(), "versus_setup")
	_save(_pack_row(), "pack_row")
	_save(_pack_select(), "pack_select")
	quit(0)


func _report(error: int, path: String) -> void:
	print("%s  %s" % ["ok  " if error == OK else "FAIL", path])


func _save(root: Node, key: String) -> void:
	_own(root, root)
	var scene: PackedScene = PackedScene.new()
	var error: int = scene.pack(root)
	if error == OK:
		error = ResourceSaver.save(scene, OUT_DIR + key + ".tscn")
	_report(error, OUT_DIR + key + ".tscn")
	root.free()


## Makes every built node part of the scene; the insides of an instanced
## sub-scene stay with that scene.
func _own(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			_own(child, root)


# ---------------------------------------------------------------------------
# Small builders
func _add(parent: Node, node: Node, node_name: String, unique: bool = false) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.unique_name_in_owner = unique
	return node


func _label(parent: Node, node_name: String, text: String, variation: String = "", unique: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	if not variation.is_empty():
		label.theme_type_variation = variation
	_add(parent, label, node_name, unique)
	return label


func _button(parent: Node, node_name: String, text: String, unique: bool = true) -> Button:
	var button: Button = Button.new()
	button.text = text
	_add(parent, button, node_name, unique)
	return button


func _box(parent: Node, node_name: String, vertical: bool, separation: int, unique: bool = false) -> BoxContainer:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	_add(parent, box, node_name, unique)
	return box


func _card(parent: Node, node_name: String, min_size: Vector2, variation: String = "HudCard") -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = variation
	card.custom_minimum_size = min_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(parent, card, node_name)
	return card


func _preview(parent: Node, node_name: String, cell: float, unique: bool = false) -> PiecePreview:
	var preview: PiecePreview = PiecePreview.new()
	preview.cell_size = cell
	preview.custom_minimum_size = Vector2(cell * 4.0, cell * 2.0 + 6.0)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_add(parent, preview, node_name, unique)
	return preview


func _spacer(parent: Node, node_name: String, vertical: bool) -> Control:
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add(parent, spacer, node_name)
	return spacer


func _slot(parent: Node, size: Vector2) -> Control:
	var frame: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, int(FRAME))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(parent, frame, "BoardFrame")
	var slot: Control = Control.new()
	slot.custom_minimum_size = size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(frame, slot, "BoardSlot", true)
	return slot


func _screen(script_path: String, node_name: String) -> Control:
	var root: Control = Control.new()
	root.name = node_name
	# Base canvas size; the game stretches the screen to the viewport.
	root.size = Vector2(1152, 648)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_script(load(script_path))
	return root


func _center(parent: Node) -> CenterContainer:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(parent, center, "Center")
	return center


## Title over a value, as one readout of a card.
func _stat(parent: Node, title: String, value_name: String, variation: String = "HudValue") -> Label:
	var box: BoxContainer = _box(parent, value_name.trim_suffix("Value") + "Stat", true, -2)
	_label(box, "Title", title, "HudTitle")
	return _label(box, value_name, "0", variation, true)


# ---------------------------------------------------------------------------
# Layouts
func _classic_hud() -> Control:
	var root: Control = _screen("res://scripts/ui/classic_hud.gd", "ClassicHud")
	var row: BoxContainer = _box(_center(root), "Row", false, 12)
	# Left: one card - HOLD on top, the readouts under it, the chain state last.
	var left: BoxContainer = _box(_card(row, "InfoCard", Vector2(CARD_WIDTH, BOARD_SIZE.y) + FRAMED), "Content", true, 10)
	_label(left, "HoldTitle", "HOLD", "HudTitle")
	_preview(left, "HoldPreview", 16.0, true)
	_add(left, HSeparator.new(), "Rule")
	_stat(left, "SCORE", "ScoreValue")
	var level: Label = _stat(left, "LEVEL", "LevelValue")
	level.add_theme_color_override("font_color", ResourcePack.color("highlight"))
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 4)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	_add(level.get_parent(), bar, "LevelBar", true)
	var lines: Label = _stat(left, "LINES", "LinesValue")
	lines.add_theme_color_override("font_color", ResourcePack.color("good"))
	_spacer(left, "Spacer", true)
	_add(left, HSeparator.new(), "Rule2")
	var chain: BoxContainer = _box(left, "Chain", false, 8)
	_stat(chain, "COMBO", "ComboValue")
	_spacer(chain, "Spacer", false)
	var lamp: Label = _label(chain, "B2BLamp", "B2B", "HudLamp", true)
	lamp.size_flags_vertical = Control.SIZE_SHRINK_END
	# Middle: the playfield.
	_slot(row, BOARD_SIZE)
	# Right: NEXT, a card the size of the one on the left.
	var next_card: PanelContainer = _card(row, "NextCard", Vector2(CARD_WIDTH, BOARD_SIZE.y) + FRAMED)
	var right: BoxContainer = _box(next_card, "Content", true, 8)
	_label(right, "NextTitle", "NEXT", "HudTitle")
	var queue: BoxContainer = _box(right, "NextPreviews", true, 10, true)
	for i: int in 5:
		_preview(queue, "Next%d" % (i + 1), 16.0 if i == 0 else 13.0)
	# One line of key hints under the board.
	var hint: Label = _label(root, "ControlsHint", "", "HudDim", true)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -470.0
	hint.offset_right = 470.0
	hint.offset_top = -78.0
	hint.offset_bottom = -60.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return root


func _versus_side() -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "VersusSide"
	root.add_theme_constant_override("separation", 6)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_script(load("res://scripts/ui/versus_side.gd"))
	var row: BoxContainer = _box(root, "Row", false, 8, true)
	# HOLD and the numbers share one narrow card.
	var info_card: PanelContainer = _card(row, "InfoCard", Vector2(104, VERSUS_BOARD_SIZE.y) + FRAMED)
	info_card.size_flags_vertical = Control.SIZE_SHRINK_END
	var info: BoxContainer = _box(info_card, "Content", true, 8)
	_label(info, "HoldTitle", "HOLD", "HudTitle")
	_preview(info, "HoldPreview", 12.0, true)
	_add(info, HSeparator.new(), "Rule")
	_stat(info, "SENT", "SentValue", "HudBig")
	_stat(info, "COMBO", "ComboValue", "HudBig")
	_stat(info, "PPS", "PpsValue", "HudBig")
	_stat(info, "ATK/S", "ApsValue", "HudBig")
	_spacer(info, "Spacer", true)
	_label(info, "B2BLamp", "B2B", "HudLamp", true)
	var warn: WarnBar = WarnBar.new()
	warn.custom_minimum_size = Vector2(12, VERSUS_BOARD_SIZE.y) + FRAMED
	warn.size_flags_vertical = Control.SIZE_SHRINK_END
	_add(row, warn, "WarnBar", true)
	# The name tag sits right on top of the board.
	var column: BoxContainer = _box(row, "BoardColumn", true, 4)
	var tags: BoxContainer = _box(column, "Tags", false, 10)
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_tag: Label = _label(tags, "NameTag", "YOU", "HudBig", true)
	name_tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var tier: Label = _label(tags, "TierTag", "", "HudBig", true)
	tier.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_slot(column, VERSUS_BOARD_SIZE)
	var next_card: PanelContainer = _card(row, "NextCard", Vector2(84, 0))
	next_card.size_flags_vertical = Control.SIZE_SHRINK_END
	next_card.custom_minimum_size = Vector2(84, VERSUS_BOARD_SIZE.y) + FRAMED
	var next_box: BoxContainer = _box(next_card, "Content", true, 6)
	_label(next_box, "NextTitle", "NEXT", "HudTitle")
	var queue: BoxContainer = _box(next_box, "NextPreviews", true, 8, true)
	for i: int in 5:
		_preview(queue, "Next%d" % (i + 1), 11.0 if i == 0 else 9.0)
	return root


func _versus_hud() -> Control:
	var root: Control = _screen("res://scripts/ui/versus_hud.gd", "VersusHud")
	var column: BoxContainer = _box(_center(root), "Column", true, 4)
	var header: BoxContainer = _box(column, "Header", false, 16)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	var level: Label = _label(header, "LevelLabel", "", "HudTitle", true)
	level.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var wins: Label = _label(header, "RoundWins", "0 - 0", "HudBig", true)
	wins.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var sides: BoxContainer = _box(column, "Sides", false, 20)
	var side_scene: PackedScene = load(OUT_DIR + "versus_side.tscn") as PackedScene
	var left: Node = side_scene.instantiate()
	_add(sides, left, "LeftSide", true)
	var right: Node = side_scene.instantiate()
	right.set("mirrored", true)
	_add(sides, right, "RightSide", true)
	return root


func _result_panel() -> Control:
	var root: Control = _screen("res://scripts/ui/result_panel.gd", "ResultPanel")
	var veil: ColorRect = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = ResourcePack.color("veil")
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(root, veil, "Veil")
	var window: PanelContainer = PanelContainer.new()
	window.custom_minimum_size = Vector2(400, 0)
	_add(_center(root), window, "Window")
	var box: BoxContainer = _box(window, "Content", true, 10)
	for spec: Array in [["Title", "MenuTitle"], ["Detail", "HudTitle"], ["Extra", "HudTitle"]]:
		var label: Label = _label(box, spec[0], "", spec[1], true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons: BoxContainer = _box(box, "Buttons", true, 8, true)
	buttons.custom_minimum_size = Vector2(220, 0)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return root


func _choice(parent: Node, node_name: String, text: String) -> Button:
	var button: Button = _button(parent, node_name, text)
	button.toggle_mode = true
	return button


func _versus_setup() -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "VersusSetup"
	root.custom_minimum_size = Vector2(600, 0)
	root.add_theme_constant_override("separation", 10)
	root.set_script(load("res://scripts/ui/versus_setup.gd"))
	# Who plays. Versus CPU shows the right card, CPU Battle both, LAN Battle
	# neither (the binding script decides); the tier buttons fill their card.
	var players: BoxContainer = _box(root, "Players", false, 16)
	for side: Array in [["Left", "CPU 1", "VersusPlayer"], ["Right", "Opponent", "VersusCPU"]]:
		var card_panel: PanelContainer = _card(players, side[0] + "Card", Vector2(260, 0))
		card_panel.unique_name_in_owner = true
		card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card: BoxContainer = _box(card_panel, "Content", true, 6)
		var title: Label = _label(card, side[0] + "Title", side[1], "HudTitle", side[0] == "Right")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tiers: BoxContainer = _box(card, "Tiers", false, 6)
		for tier: String in ["Easy", "Normal", "Hard", "Lunatic"]:
			_choice(tiers, side[2] + tier, tier).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# LAN Battle: host or join, and what the line is doing.
	var lan_panel: PanelContainer = _card(root, "LanCard", Vector2(0, 0))
	lan_panel.unique_name_in_owner = true
	var lan: BoxContainer = _box(lan_panel, "Content", true, 8)
	_label(lan, "LanTitle", "Local Network", "HudTitle").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var line: BoxContainer = _box(lan, "Connect", false, 8)
	_button(line, "LanHostButton", "Host Game")
	var address: LineEdit = LineEdit.new()
	address.placeholder_text = "Host address"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.max_length = 64
	_add(line, address, "LanAddress", true)
	_button(line, "LanJoinButton", "Join Game")
	var status: Label = _label(lan, "LanStatus", "", "", true)
	status.custom_minimum_size = Vector2(0, 40)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The rules, two choices of their own side by side: the mode (Classic
	# first; the levels belong to the fixed speed) and the match format.
	var rules: BoxContainer = _box(root, "Rules", false, 16)
	var mode_panel: PanelContainer = _card(rules, "ModeCard", Vector2(0, 0))
	mode_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mode: BoxContainer = _box(mode_panel, "Content", true, 8)
	_label(mode, "ModeTitle", "Mode", "HudTitle").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var modes: BoxContainer = _box(mode, "Modes", false, 6)
	_choice(modes, "VersusSpeedRisingSpeed", "Classic").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice(modes, "VersusSpeedFixedSpeed", "Fixed Speed").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var levels: BoxContainer = _box(mode, "VersusLevelRow", false, 4, true)
	_label(levels, "LevelTitle", "Level", "HudTitle").custom_minimum_size = Vector2(52, 0)
	for level: int in range(1, 11):
		_choice(levels, "VersusLevel%d" % level, str(level)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var match_panel: PanelContainer = _card(rules, "MatchCard", Vector2(190, 0))
	var match_box: BoxContainer = _box(match_panel, "Content", true, 8)
	_label(match_box, "MatchTitle", "Match", "HudTitle").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice(match_box, "VersusMatchSingleMatch", "Single Match")
	_choice(match_box, "VersusMatchBestof3", "Best of 3")
	var description: Label = _label(root, "VersusDescription", "", "", true)
	description.custom_minimum_size = Vector2(536, 44)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.add_theme_color_override("font_color", ResourcePack.color("text_title"))
	var start: Button = _button(root, "VersusStartButton", "Start Match")
	start.theme_type_variation = "PrimaryButton"
	return root


func _pack_row() -> Control:
	var root: PanelContainer = PanelContainer.new()
	root.name = "PackRow"
	root.theme_type_variation = "PackRow"
	root.custom_minimum_size = Vector2(380, 64)
	root.set_script(load("res://scripts/ui/pack_row.gd"))
	var row: BoxContainer = _box(root, "Row", false, 8)
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add(row, icon, "Icon", true)
	var text: BoxContainer = _box(row, "Text", true, 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(text, "NameLabel", "", "", true)
	var description: Label = _label(text, "DescriptionLabel", "", "HudTitle", true)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(180, 0)
	for spec: Array in [["UpButton", "^"], ["DownButton", "v"], ["MoveButton", ">"]]:
		var button: Button = _button(row, spec[0], spec[1])
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.custom_minimum_size = Vector2(34, 34)
	return root


func _pack_select() -> Control:
	var root: Control = _screen("res://scripts/ui/pack_select.gd", "PackSelect")
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.7)
	_add(root, shade, "Shade")
	var window: PanelContainer = PanelContainer.new()
	window.custom_minimum_size = Vector2(900, 540)
	_add(_center(root), window, "Window")
	var box: BoxContainer = _box(window, "Content", true, 10)
	var title: Label = _label(box, "Title", "Resource Packs", "MenuTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint: Label = _label(box, "Hint", "PACKS_HINT", "HudTitle")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var columns: BoxContainer = _box(box, "Columns", false, 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for spec: Array in [["Available", "AvailableList"], ["Enabled", "EnabledList"]]:
		var column: BoxContainer = _box(columns, spec[0] + "Column", true, 6)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(column, "Title", spec[0], "HudTitle")
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_add(column, scroll, "Scroll")
		var list: BoxContainer = _box(scroll, spec[1], true, 6, true)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer: BoxContainer = _box(box, "Footer", false, 8)
	_button(footer, "OpenFolderButton", "Open Pack Folder")
	_spacer(footer, "Spacer", false)
	var done: Button = _button(footer, "DoneButton", "Done")
	done.theme_type_variation = "PrimaryButton"
	done.custom_minimum_size = Vector2(180, 0)
	return root
