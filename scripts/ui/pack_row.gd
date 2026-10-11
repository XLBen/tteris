class_name PackRow
extends Control
## Binding script of the "pack_row" layout: one resource pack in the pack
## list. Required nodes (REQUIRED_NODES):
##   Icon                TextureRect (the pack's pack.png)
##   NameLabel, DescriptionLabel   Labels
##   MoveButton          Button: enable an available pack / disable an
##                       enabled one
##   UpButton, DownButton   Buttons: priority of an enabled pack

const REQUIRED_NODES: Array[String] = ["Icon", "NameLabel", "DescriptionLabel", "MoveButton", "UpButton", "DownButton"]

signal move_pressed(pack_id: String)
signal up_pressed(pack_id: String)
signal down_pressed(pack_id: String)

var pack_id: String = ""

var icon: TextureRect
var name_label: Label
var description_label: Label
var move_button: Button
var up_button: Button
var down_button: Button


var _bound: bool = false


func _ready() -> void:
	bind()


## Looks the layout's nodes up. Runs from _ready(); owners that use the layout
## before it is inside the tree call it themselves.
func bind() -> void:
	if _bound:
		return
	_bound = true
	icon = get_node(^"%Icon") as TextureRect
	name_label = get_node(^"%NameLabel") as Label
	description_label = get_node(^"%DescriptionLabel") as Label
	move_button = get_node(^"%MoveButton") as Button
	up_button = get_node(^"%UpButton") as Button
	down_button = get_node(^"%DownButton") as Button
	# Pack names and descriptions are the pack author's words.
	for label: Label in [name_label, description_label]:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	move_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	move_button.pressed.connect(func() -> void: move_pressed.emit(pack_id))
	up_button.pressed.connect(func() -> void: up_pressed.emit(pack_id))
	down_button.pressed.connect(func() -> void: down_pressed.emit(pack_id))


## Fills the row. `enabled` rows show the priority arrows; a `locked` row (the
## default pack, always underneath) shows no buttons at all.
func show_pack(pack: Dictionary, enabled: bool, locked: bool, can_up: bool, can_down: bool) -> void:
	pack_id = String(pack["id"])
	name = "Pack_" + pack_id
	icon.texture = ResourcePack.pack_icon(pack)
	name_label.text = String(pack["name"])
	description_label.text = String(pack["description"])
	move_button.visible = not locked
	move_button.text = "<" if enabled else ">"
	up_button.visible = enabled and not locked
	down_button.visible = enabled and not locked
	up_button.disabled = not can_up
	down_button.disabled = not can_down
