class_name VersusSide
extends Control
## Binding script of the "versus_side" layout: everything that belongs to one
## player of a versus match. The versus HUD shows two of them; the right one
## is `mirrored`. Required nodes (REQUIRED_NODES):
##   BoardSlot      Control whose rect is the playfield (10:20)
##   Row            container whose children are laid out left to right; a
##                  mirrored side reverses their order
##   NameTag, TierTag            Labels above the board ("YOU" / "CPU", tier)
##   HoldPreview    PiecePreview; NextPreviews: container of PiecePreviews
##   SentValue, ComboValue, PpsValue   Labels
##   B2BLamp        Label lit while Back-to-Back is active
##   WarnBar        WarnBar control (incoming garbage meter)
## Optional: ApsValue, a Label for the attack sent per second (a layout made
## before it existed simply does not show the number).

const REQUIRED_NODES: Array[String] = [
	"BoardSlot", "Row", "NameTag", "TierTag", "HoldPreview", "NextPreviews",
	"SentValue", "ComboValue", "PpsValue", "B2BLamp", "WarnBar",
]

## Lays the side out right-to-left (the opponent's side of the screen).
@export var mirrored: bool = false

var board_slot: Control
var name_tag: Label
var tier_tag: Label
var hold_preview: PiecePreview
var sent_value: Label
var combo_value: Label
var pps_value: Label
var aps_value: Label
var b2b_lamp: Label
var warn_bar: WarnBar

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
	name_tag = get_node(^"%NameTag") as Label
	tier_tag = get_node(^"%TierTag") as Label
	hold_preview = get_node(^"%HoldPreview") as PiecePreview
	sent_value = get_node(^"%SentValue") as Label
	combo_value = get_node(^"%ComboValue") as Label
	pps_value = get_node(^"%PpsValue") as Label
	aps_value = get_node_or_null(^"%ApsValue") as Label
	b2b_lamp = get_node(^"%B2BLamp") as Label
	warn_bar = get_node(^"%WarnBar") as WarnBar
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in %NextPreviews.get_children():
		if child is PiecePreview:
			next_previews.append(child)
	if mirrored:
		var row: Node = %Row
		var children: Array[Node] = row.get_children()
		for i: int in children.size():
			row.move_child(children[i], children.size() - 1 - i)


## Name above the board, plus the AI tier (empty for a human).
func set_tags(player_name: String, name_color: Color, tier: String, tier_color: Color) -> void:
	name_tag.text = player_name
	name_tag.add_theme_color_override("font_color", name_color)
	tier_tag.text = tier
	tier_tag.visible = not tier.is_empty()
	tier_tag.add_theme_color_override("font_color", tier_color)


## `aps` is the garbage sent per second of the round so far.
func set_stats(sent: int, combo: int, pps: float, b2b: bool, pending: int, aps: float = 0.0) -> void:
	sent_value.text = str(sent)
	combo_value.text = str(combo)
	pps_value.text = "%.2f" % pps
	if aps_value != null:
		aps_value.text = "%.2f" % aps
	b2b_lamp.add_theme_color_override("font_color", ResourcePack.color("highlight") if b2b else ResourcePack.color("lamp_off"))
	warn_bar.pending = pending


func set_hold(piece_type: int) -> void:
	hold_preview.piece_type = piece_type


func set_next(queue: Array) -> void:
	for slot: int in next_previews.size():
		next_previews[slot].piece_type = int(queue[slot]) if slot < queue.size() else -1
