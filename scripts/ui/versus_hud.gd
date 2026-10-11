class_name VersusHud
extends Control
## Binding script of the "versus_hud" layout: the whole versus screen around
## the two boards. Required nodes (REQUIRED_NODES):
##   LeftSide, RightSide   two VersusSide layouts (the player / the opponent)
##   LevelLabel            Label: the current speed level
##   RoundWins             Label: the round score of a best-of-3

const REQUIRED_NODES: Array[String] = ["LeftSide", "RightSide", "LevelLabel", "RoundWins"]

var left_side: VersusSide
var right_side: VersusSide
var level_label: Label
var round_wins: Label


var _bound: bool = false


func _ready() -> void:
	bind()


## Looks the layout's nodes up. Runs from _ready(); owners that use the layout
## before it is inside the tree call it themselves.
func bind() -> void:
	if _bound:
		return
	_bound = true
	left_side = get_node(^"%LeftSide") as VersusSide
	right_side = get_node(^"%RightSide") as VersusSide
	level_label = get_node(^"%LevelLabel") as Label
	round_wins = get_node(^"%RoundWins") as Label
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_side.bind()
	right_side.bind()
	HudLayout.settle(self)


func side(index: int) -> VersusSide:
	return left_side if index == 0 else right_side
