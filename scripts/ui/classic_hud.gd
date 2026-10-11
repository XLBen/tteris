class_name ClassicHud
extends Control
## Binding script of the "classic_hud" layout (single-player HUD). The scene
## is a resource pack's to arrange; this script only needs the nodes listed in
## REQUIRED_NODES, wherever the layout puts them:
##   BoardSlot      Control whose rect is the playfield (10:20); the game puts
##                  the board and its effects inside it
##   HoldPreview    PiecePreview of the held piece
##   NextPreviews   container whose PiecePreview children are the NEXT queue
##   ScoreValue, LevelValue, LinesValue, ComboValue   Labels
##   LevelBar       Range (0..1): progress to the next level
##   B2BLamp        Label lit while Back-to-Back is active
##   ControlsHint   Label for the one-line key hints

const REQUIRED_NODES: Array[String] = [
	"BoardSlot", "HoldPreview", "NextPreviews", "ScoreValue", "LevelValue",
	"LinesValue", "ComboValue", "LevelBar", "B2BLamp", "ControlsHint",
]

var board_slot: Control
var hold_preview: PiecePreview
var score_value: Label
var level_value: Label
var lines_value: Label
var combo_value: Label
var level_bar: Range
var b2b_lamp: Label
var controls_hint: Label

var next_previews: Array[PiecePreview] = []


var _bound: bool = false


func _ready() -> void:
	bind()


## Looks the layout's nodes up. Runs from _ready(); owners that use the layout
## before it is inside the tree call it themselves.
func bind() -> void:
	if _bound:
		return
	_bound = true
	board_slot = get_node(^"%BoardSlot") as Control
	hold_preview = get_node(^"%HoldPreview") as PiecePreview
	score_value = get_node(^"%ScoreValue") as Label
	level_value = get_node(^"%LevelValue") as Label
	lines_value = get_node(^"%LinesValue") as Label
	combo_value = get_node(^"%ComboValue") as Label
	level_bar = get_node(^"%LevelBar") as Range
	b2b_lamp = get_node(^"%B2BLamp") as Label
	controls_hint = get_node(^"%ControlsHint") as Label
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in %NextPreviews.get_children():
		if child is PiecePreview:
			next_previews.append(child)
	level_bar.min_value = 0.0
	level_bar.max_value = 1.0
	HudLayout.settle(self)


func set_stats(score: int, level: int, level_progress: float, lines: int, combo: int, b2b: bool) -> void:
	score_value.text = str(score)
	level_value.text = str(level)
	lines_value.text = str(lines)
	combo_value.text = str(combo)
	level_bar.value = level_progress
	b2b_lamp.add_theme_color_override("font_color", ResourcePack.color("highlight") if b2b else ResourcePack.color("lamp_off"))


func set_hold(piece_type: int) -> void:
	hold_preview.piece_type = piece_type


func set_next(queue: Array) -> void:
	for slot: int in next_previews.size():
		next_previews[slot].piece_type = int(queue[slot]) if slot < queue.size() else -1
