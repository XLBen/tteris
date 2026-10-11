class_name PackSelect
extends Control
## Binding script of the "pack_select" layout: the resource pack screen.
## Available packs on the left, enabled packs on the right in priority order
## (top wins), the default pack fixed at the bottom. Nothing changes until
## Done. Required nodes (REQUIRED_NODES):
##   AvailableList, EnabledList   containers the rows ("pack_row" layouts) go
##                                into
##   OpenFolderButton   Button: opens user://packs in the file manager
##   DoneButton         Button: applies the list and closes the screen

const REQUIRED_NODES: Array[String] = ["AvailableList", "EnabledList", "OpenFolderButton", "DoneButton"]
const OVERLAY_LAYER: int = 20

## The screen was closed; `changed` tells whether the enabled packs differ.
signal closed(changed: bool)

var available_list: Container
var enabled_list: Container
var open_folder_button: Button
var done_button: Button

## Enabled pack ids being edited, highest priority first.
var _enabled: Array[String] = []


var _bound: bool = false


func _ready() -> void:
	bind()


## Looks the layout's nodes up. Runs from _ready(); owners that use the layout
## before it is inside the tree call it themselves.
func bind() -> void:
	if _bound:
		return
	_bound = true
	available_list = get_node(^"%AvailableList") as Container
	enabled_list = get_node(^"%EnabledList") as Container
	open_folder_button = get_node(^"%OpenFolderButton") as Button
	done_button = get_node(^"%DoneButton") as Button
	visible = false
	open_folder_button.pressed.connect(_on_open_folder_pressed)
	done_button.pressed.connect(apply_and_close)


func open() -> void:
	_enabled = ResourcePack.enabled_ids()
	_rebuild()
	visible = true
	if is_inside_tree():
		HudLayout.fill_viewport(self)
		done_button.grab_focus()


## Ids being edited (the read surface for tests).
func enabled_ids() -> Array[String]:
	return _enabled.duplicate()


## Applies the edited list, restyles the game and closes.
func apply_and_close() -> void:
	if not visible:
		return
	var changed: bool = _enabled != ResourcePack.enabled_ids()
	if changed:
		ResourcePack.set_enabled(_enabled)
		var runtime: Node = get_node_or_null(^"/root/PackRuntime")
		if runtime != null:
			runtime.apply()
	visible = false
	closed.emit(changed)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		apply_and_close()


## Moves a pack between the two lists (a newly enabled pack goes on top).
func toggle_pack(pack_id: String) -> void:
	if _enabled.has(pack_id):
		_enabled.erase(pack_id)
	else:
		_enabled.insert(0, pack_id)
	_rebuild()


## Raises (-1) or lowers (+1) an enabled pack's priority.
func shift_pack(pack_id: String, direction: int) -> void:
	var index: int = _enabled.find(pack_id)
	var target: int = index + direction
	if index < 0 or target < 0 or target >= _enabled.size():
		return
	_enabled[index] = _enabled[target]
	_enabled[target] = pack_id
	_rebuild()


func _rebuild() -> void:
	for list: Container in [available_list, enabled_list]:
		for child: Node in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var packs: Dictionary = {}
	for pack: Dictionary in ResourcePack.list_packs():
		packs[pack["id"]] = pack
	# Packs that were removed from disk while enabled drop out here.
	_enabled = _enabled.filter(func(id: String) -> bool: return packs.has(id))
	for id: String in packs:
		if id != ResourcePack.DEFAULT_ID and not _enabled.has(id):
			_add_row(available_list, packs[id], false, false, false, false)
	for i: int in _enabled.size():
		_add_row(enabled_list, packs[_enabled[i]], true, false, i > 0, i < _enabled.size() - 1)
	if packs.has(ResourcePack.DEFAULT_ID):
		_add_row(enabled_list, packs[ResourcePack.DEFAULT_ID], true, true, false, false)


func _add_row(list: Container, pack: Dictionary, enabled: bool, locked: bool, can_up: bool, can_down: bool) -> void:
	var scene: PackedScene = ResourcePack.layout("pack_row")
	if scene == null:
		return
	var row: PackRow = scene.instantiate() as PackRow
	list.add_child(row)
	row.bind()
	row.show_pack(pack, enabled, locked, can_up, can_down)
	row.move_pressed.connect(toggle_pack)
	row.up_pressed.connect(shift_pack.bind(-1))
	row.down_pressed.connect(shift_pack.bind(1))


func _on_open_folder_pressed() -> void:
	DirAccess.make_dir_recursive_absolute(ResourcePack.USER_DIR)
	OS.shell_open(ProjectSettings.globalize_path(ResourcePack.USER_DIR))


## A pack screen on its own canvas layer under `host`, ready to open().
static func create(host: Node) -> PackSelect:
	var scene: PackedScene = ResourcePack.layout("pack_select")
	if scene == null:
		return null
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PackSelectLayer"
	layer.layer = OVERLAY_LAYER
	host.add_child(layer)
	var screen: PackSelect = scene.instantiate() as PackSelect
	layer.add_child(screen)
	screen.bind()
	return screen


## Adds a "Resource Packs" entry to a pause menu instance from the outside
## (the vendored template copy stays byte-identical), like
## HowToPlay.attach_to_pause_menu. `on_changed` runs after the packs changed.
static func attach_to_pause_menu(menu: Control, on_changed: Callable) -> void:
	var options_button: Button = menu.find_child("OptionsButton", true, false) as Button
	if options_button == null:
		return
	var screen: PackSelect = create(menu.get_parent())
	if screen == null:
		return
	var button: Button = Button.new()
	button.name = "ResourcePacksButton"
	button.text = "Resource Packs"
	options_button.add_sibling(button)
	button.pressed.connect(func() -> void:
		screen.open()
		menu.set("open_window", screen))
	screen.closed.connect(func(changed: bool) -> void:
		menu.set("open_window", null)
		if button.is_visible_in_tree():
			button.grab_focus()
		if changed:
			on_changed.call())
