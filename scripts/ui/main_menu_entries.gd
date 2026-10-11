class_name MainMenuEntries
extends Node
## The game's own main menu entries: How to Play (scripts/how_to_play.gd) and
## Resource Packs (scripts/ui/pack_select.gd), under Options.
##
## Added to the main menu from the outside - the PackRuntime autoload calls
## attach() when the menu scene appears - so the vendored template copy of the
## menu stays byte-identical (same idea as HowToPlay.attach_to_pause_menu).
## This node sits inside the menu and gets input before it: while one of the
## two pages is open, ui_cancel closes the page instead of reaching the menu's
## "exit the game?" question.

const MAIN_MENU_SETTING: String = "maaacks_game_template/main_menu_scene_path"

var _menu: Control
var _how_to_play_button: Button
var _pack_button: Button
var _how_to_play: HowToPlay
var _pack_select: PackSelect


## True for the main menu scene itself (the mode select instances the same
## scene and stays without the entries).
static func is_main_menu(node: Node) -> bool:
	return node is MainMenu and node.scene_file_path != "" \
		and node.scene_file_path == String(ProjectSettings.get_setting(MAIN_MENU_SETTING, ""))


## Adds the entries to a main menu that is ready. Does nothing twice.
static func attach(menu: Control) -> void:
	if menu.has_node(^"MainMenuEntries") or menu.find_child("OptionsButton", true, false) == null:
		return
	var entries: MainMenuEntries = MainMenuEntries.new()
	entries.name = "MainMenuEntries"
	entries._menu = menu
	menu.add_child(entries)


func _ready() -> void:
	var options_button: Button = _menu.find_child("OptionsButton", true, false) as Button
	_how_to_play_button = _add_entry("HowToPlayButton", "How to Play", options_button)
	_how_to_play_button.pressed.connect(_on_how_to_play_button_pressed)
	_pack_button = _add_entry("ResourcePackButton", "Resource Packs", _how_to_play_button)
	_pack_button.pressed.connect(_on_pack_button_pressed)
	_how_to_play = HowToPlay.new()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HowToPlayLayer"
	layer.layer = 10
	add_child(layer)
	layer.add_child(_how_to_play)
	_how_to_play.closed.connect(_on_how_to_play_closed)
	_pack_select = PackSelect.create(self)
	if _pack_select != null:
		_pack_select.closed.connect(_on_pack_select_closed)


func _add_entry(entry_name: String, text: String, after: Button) -> Button:
	var button: Button = Button.new()
	button.name = entry_name
	button.text = text
	after.add_sibling(button)
	return button


## The pack screen; null when the pack has no layout for it.
func pack_select() -> PackSelect:
	return _pack_select


func how_to_play() -> HowToPlay:
	return _how_to_play


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _how_to_play.visible:
		get_viewport().set_input_as_handled()
		_how_to_play.close()
	elif _pack_select != null and _pack_select.visible:
		get_viewport().set_input_as_handled()
		_pack_select.apply_and_close()


func _on_how_to_play_button_pressed() -> void:
	_how_to_play.open()


func _on_how_to_play_closed() -> void:
	if _how_to_play_button.is_visible_in_tree():
		_how_to_play_button.grab_focus()


func _on_pack_button_pressed() -> void:
	if _pack_select != null:
		_pack_select.open()


## The pack screen applied a new set of packs: the menu is loaded again so its
## own look comes from them too.
func _on_pack_select_closed(changed: bool) -> void:
	if changed and is_inside_tree():
		var loader: Variant = _menu.get("scene_loader_node")
		if loader != null:
			loader.load_scene(_menu.scene_file_path)
		else:
			get_tree().change_scene_to_file(_menu.scene_file_path)
	elif _pack_button.is_visible_in_tree():
		_pack_button.grab_focus()
