extends "res://scenes/menus/main_menu/main_menu_with_animations.gd"
## The play screen behind the main menu's New Game, built on the vendored
## Maaack animated menu so the template's entry animation plays when it opens.
## It starts on the list of ways to play:
##
##   Solo         the classic game, started at once
##   Versus CPU   page "pve": the player against one CPU tier
##   CPU Battle   page "eve": two CPU tiers against each other, the player watches
##   LAN Battle   page "lan": two players on the local network
##                (scripts/lan_session.gd); one hosts and picks the rules, the
##                other joins by address
##
## A versus entry opens its setup page in place - the resource pack's
## "versus_setup" layout (scripts/ui/versus_setup.gd). Every page picks the
## mode - Classic (the speed rises as lines are cleared) or a fixed speed level
## - and, as a choice of its own, the match format. The choices are remembered
## between sessions through PlayerConfig and written through
## GameSession.start_versus() before the versus scene is loaded. Back returns
## from a page to the list, and from the list to the main menu. A match's
## "Change Settings" comes straight back to its page (GameSession.open_versus_setup).

const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const VERSUS_RULES_FIXED: StringName = &"fixed"
const VERSUS_RULES_RISING: StringName = &"rising"
const VERSUS_FORMAT_SINGLE: StringName = &"single"
const VERSUS_FORMAT_BEST_OF_3: StringName = &"best_of_3"
const VERSUS_DIFFICULTY_NORMAL: StringName = &"normal"
const VERSUS_FIXED_LEVEL_MIN: int = 1
const VERSUS_FIXED_LEVEL_MAX: int = 10
const PAGE_MENU: StringName = &"menu"
const PAGE_PVE: StringName = &"pve"
const PAGE_EVE: StringName = &"eve"
const PAGE_LAN: StringName = &"lan"
const PAGE_TITLES: Dictionary = {&"menu": "Select Mode", &"pve": "Versus CPU", &"eve": "CPU Battle", &"lan": "LAN Battle"}
## The list: button name -> [text, page ("" = the solo game)].
const PLAY_ENTRIES: Array = [
	["SoloButton", "Solo", &""],
	["PveButton", "Versus CPU", &"pve"],
	["EveButton", "CPU Battle", &"eve"],
	["LanButton", "LAN Battle", &"lan"],
]
const CONFIG_SECTION: String = "VersusSettings"
## Choices per group: [value, button text, description key]. Classic comes first.
const RULE_OPTIONS: Array = [
	[&"rising", "Classic", "VERSUS_DESC_RISING"],
	[&"fixed", "Fixed Speed", "VERSUS_DESC_FIXED"],
]
const DIFFICULTY_OPTIONS: Array = [
	[&"easy", "Easy", "VERSUS_DESC_EASY"],
	[&"normal", "Normal", "VERSUS_DESC_NORMAL"],
	[&"hard", "Hard", "VERSUS_DESC_HARD"],
	[&"lunatic", "Lunatic", "VERSUS_DESC_LUNATIC"],
	[&"extra", "Extra", "VERSUS_DESC_EXTRA"],
]
const FORMAT_OPTIONS: Array = [
	[&"single", "Single Match", "VERSUS_DESC_SINGLE"],
	[&"best_of_3", "Best of 3", "VERSUS_DESC_BEST_OF_3"],
]

var _page: StringName = PAGE_MENU
var _play_buttons: Dictionary = {}
var _subtitle: Label
## Classic unless the player chose otherwise.
var _versus_rules: StringName = VERSUS_RULES_RISING
var _versus_level: int = VERSUS_FIXED_LEVEL_MIN
var _versus_difficulty: StringName = VERSUS_DIFFICULTY_NORMAL
## Tier of the left CPU on the CPU Battle page.
var _versus_left: StringName = VERSUS_DIFFICULTY_NORMAL
var _versus_format: StringName = VERSUS_FORMAT_SINGLE
var _versus_options: BoxContainer
var _setup: VersusSetup
var _description: Label
var _start_button: Button
var _level_row: Control
## LAN page: the link, the last status line (a translation key and its
## argument) and whether this screen is leaving for the match it started.
var _link: Node
var _lan_status: String = "LAN_STATUS_IDLE"
var _lan_status_arg: String = ""
var _lan_starting: bool = false
var _lan_wired: bool = false


func _ready() -> void:
	super._ready()
	var session: Node = get_node_or_null(^"/root/GameSession")
	var page: StringName = PAGE_MENU
	if session != null:
		# "Change Settings" of a match comes back to that match's page.
		if bool(session.open_versus_setup) and PAGE_TITLES.has(StringName(session.versus_page)):
			page = StringName(session.versus_page)
		session.open_versus_setup = false
	_subtitle = find_child("SubTitleLabel", true, false) as Label
	_versus_options = find_child("VersusOptionsBoxContainer", true, false) as BoxContainer
	_build_play_buttons()
	_load_versus_choices()
	_build_versus_page()
	_show_page(page)


## The list of ways to play, above the setup page's place.
func _build_play_buttons() -> void:
	var last: Node = null
	for entry: Array in PLAY_ENTRIES:
		var button: Button = Button.new()
		button.name = String(entry[0])
		button.text = String(entry[1])
		button.pressed.connect(_on_play_pressed.bind(StringName(entry[2])))
		if last == null:
			_versus_options.add_sibling(button)
			_versus_options.get_parent().move_child(button, 0)
		else:
			last.add_sibling(button)
		last = button
		_play_buttons[StringName(entry[2])] = button


func _on_play_pressed(page: StringName) -> void:
	if page == &"":
		select_mode(GameSession.MODE_CLASSIC)
	else:
		_show_page(page)


## Shows the list ("menu") or one setup page.
func _show_page(page: StringName) -> void:
	if _page == PAGE_LAN and page != PAGE_LAN and _link != null:
		_link.close()
	_page = page
	var listing: bool = page == PAGE_MENU
	for key: StringName in _play_buttons:
		(_play_buttons[key] as Button).visible = listing
	_versus_options.visible = not listing
	if _subtitle != null:
		_subtitle.text = String(PAGE_TITLES[page])
	var session: Node = get_node_or_null(^"/root/GameSession")
	if listing:
		# Deferred so the visibility changes are applied before the focus moves.
		var back_to: StringName = StringName(session.versus_page) if session != null else PAGE_PVE
		(_play_buttons.get(back_to, _play_buttons[&""]) as Button).grab_focus.call_deferred()
		return
	if session != null:
		session.versus_page = page
	_setup.show_page(page)
	_sync_versus_page()
	if page == PAGE_LAN:
		_open_lan_page(session)
	_start_button.grab_focus.call_deferred()


func _exit_tree() -> void:
	# Leaving any other way than into the match hangs up.
	if _link != null and not _lan_starting:
		_link.close()


## The page this screen shows.
func page() -> StringName:
	return _page


## Starts `mode` and loads its scene. Optional versus fields override the
## defaults so the setup page can pass its selection in one call.
func select_mode(mode: StringName, scene_path: String = "", versus_rules: StringName = &"", versus_level: int = 0, versus_format: StringName = &"", versus_difficulty: StringName = &"", versus_left: StringName = &"", lan: StringName = &"") -> void:
	# Resolved by node path (same pattern as scripts/main.gd) so this script
	# also compiles standalone under --check-only, where autoload names are
	# not registered as compile-time globals.
	var session: Node = get_node_or_null(^"/root/GameSession")
	if session != null:
		if mode == GameSession.MODE_CLASSIC:
			session.start_classic()
		elif mode == GameSession.MODE_VERSUS:
			var rules: StringName = versus_rules if versus_rules != &"" else session.VERSUS_RULES_FIXED
			var level: int = versus_level if versus_level > 0 else int(session.VERSUS_FIXED_LEVEL_MIN)
			var match_format: StringName = versus_format if versus_format != &"" else session.VERSUS_FORMAT_SINGLE
			var difficulty: StringName = versus_difficulty if versus_difficulty != &"" else session.VERSUS_DIFFICULTY_NORMAL
			session.start_versus(rules, level, match_format, difficulty, versus_left, lan)
		else:
			session.start_mode(mode)
	if scene_path.is_empty():
		load_game_scene()
	else:
		_load_scene(scene_path)


func _load_scene(scene_path: String) -> void:
	if scene_loader_node:
		scene_loader_node.load_scene(scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)


func _return_to_main_menu() -> void:
	var main_menu_path: String = MaaacksGameTemplate.get_main_menu_path()
	# Same loader hook as _load_scene: in production this is the SceneLoader
	# autoload, and tests can swap in an isolated stub instead of changing the
	# real scene.
	if scene_loader_node:
		scene_loader_node.load_scene(main_menu_path)
		return
	var scene_loader: Node = get_tree().root.get_node_or_null(^"SceneLoader")
	if scene_loader != null:
		scene_loader.load_scene(main_menu_path)
	else:
		get_tree().change_scene_to_file(main_menu_path)


# ---------------------------------------------------------------------------
# The setup page
func _load_versus_choices() -> void:
	var rules: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Rules", String(VERSUS_RULES_RISING))))
	if _option_index(RULE_OPTIONS, rules) >= 0:
		_versus_rules = rules
	_versus_level = clampi(int(PlayerConfig.get_config(CONFIG_SECTION, "Level", VERSUS_FIXED_LEVEL_MIN)), VERSUS_FIXED_LEVEL_MIN, VERSUS_FIXED_LEVEL_MAX)
	var difficulty: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Difficulty", String(VERSUS_DIFFICULTY_NORMAL))))
	if _option_index(DIFFICULTY_OPTIONS, difficulty) >= 0:
		_versus_difficulty = difficulty
	var left: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Left", String(VERSUS_DIFFICULTY_NORMAL))))
	if _option_index(DIFFICULTY_OPTIONS, left) >= 0:
		_versus_left = left
	var match_format: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Format", String(VERSUS_FORMAT_SINGLE))))
	if _option_index(FORMAT_OPTIONS, match_format) >= 0:
		_versus_format = match_format


func _save_versus_choices() -> void:
	PlayerConfig.set_config(CONFIG_SECTION, "Rules", String(_versus_rules))
	PlayerConfig.set_config(CONFIG_SECTION, "Level", _versus_level)
	PlayerConfig.set_config(CONFIG_SECTION, "Difficulty", String(_versus_difficulty))
	PlayerConfig.set_config(CONFIG_SECTION, "Left", String(_versus_left))
	PlayerConfig.set_config(CONFIG_SECTION, "Format", String(_versus_format))


static func _option_index(options: Array, value: StringName) -> int:
	for i: int in options.size():
		if options[i][0] == value:
			return i
	return -1


func _build_versus_page() -> void:
	_setup = ResourcePack.layout("versus_setup").instantiate() as VersusSetup
	_versus_options.add_child(_setup)
	_setup.bind()
	_description = _setup.description
	_start_button = _setup.start_button
	_level_row = _setup.level_row
	_setup.option_picked.connect(_on_option_picked)
	_setup.option_focused.connect(_on_option_focused)
	_setup.start_pressed.connect(_on_start_button_pressed)
	_setup.start_focused.connect(_describe.bind("VERSUS_DESC_START", 0))
	_setup.lan_host_pressed.connect(_on_lan_host_pressed)
	_setup.lan_join_pressed.connect(_on_lan_join_pressed)
	_sync_versus_page()


func _on_option_picked(group: String, value: Variant) -> void:
	match group:
		"rules":
			_versus_rules = value
		"level":
			_versus_level = int(value)
		"left":
			_versus_left = value
		"difficulty":
			_versus_difficulty = value
		"format":
			_versus_format = value
	_sync_versus_page()
	# The joined player sees what the host picks.
	if _page == PAGE_LAN and _link != null:
		_link.send_settings(_lan_settings())


func _on_option_focused(group: String, value: Variant) -> void:
	match group:
		"rules":
			_describe(String(RULE_OPTIONS[_option_index(RULE_OPTIONS, value)][2]), value)
		"level":
			_describe("VERSUS_DESC_LEVEL", value)
		"left", "difficulty":
			_describe(String(DIFFICULTY_OPTIONS[_option_index(DIFFICULTY_OPTIONS, value)][2]), value)
		"format":
			_describe(String(FORMAT_OPTIONS[_option_index(FORMAT_OPTIONS, value)][2]), value)


func _describe(key: String, value: Variant) -> void:
	var text: String = tr(key)
	if text.contains("%d"):
		text = text % int(value)
	_setup.describe(text)


## Mirrors the current choices onto the page's toggle buttons.
func _sync_versus_page() -> void:
	_setup.show_choices({
		"rules": _versus_rules,
		"level": _versus_level,
		"left": _versus_left,
		"difficulty": _versus_difficulty,
		"format": _versus_format,
	})
	if _page == PAGE_LAN:
		_sync_lan_page()
	else:
		_setup.show_lan("", false, true, true)


func _on_start_button_pressed() -> void:
	var level: int = _versus_level if _versus_rules == VERSUS_RULES_FIXED else VERSUS_FIXED_LEVEL_MIN
	if _page == PAGE_LAN:
		if _link == null or _link.role() != _link.ROLE_HOST or not _link.has_peer():
			return
		_save_versus_choices()
		_link.send_start(_lan_settings())
		_begin_lan_match(_link.ROLE_HOST)
		return
	_save_versus_choices()
	var left: StringName = _versus_left if _page == PAGE_EVE else &""
	select_mode(GameSession.MODE_VERSUS, VERSUS_SCENE_PATH, _versus_rules, level, _versus_format, _versus_difficulty, left)


func _on_back_button_pressed() -> void:
	if _page != PAGE_MENU:
		_show_page(PAGE_MENU)
		return
	_return_to_main_menu()


# ---------------------------------------------------------------------------
# LAN page
func _open_lan_page(session: Node) -> void:
	_link = get_node_or_null(^"/root/LanSession")
	if _link == null:
		return
	# The page always opens with the line down.
	_link.close()
	_lan_status = "LAN_STATUS_IDLE"
	if not _lan_wired:
		_lan_wired = true
		_link.peer_joined.connect(_on_lan_peer_joined)
		_link.peer_left.connect(_on_lan_peer_left)
		_link.settings_received.connect(_on_lan_settings_received)
		_link.start_received.connect(_on_lan_start_received)
	_setup.set_lan_address(String(PlayerConfig.get_config(CONFIG_SECTION, "Address", "")))
	if session != null and not String(session.lan_notice).is_empty():
		_set_lan_status(String(session.lan_notice))
		session.lan_notice = ""
	_sync_lan_page()


func _set_lan_status(key: String, argument: String = "") -> void:
	_lan_status = key
	_lan_status_arg = argument
	_sync_lan_page()


## What the LAN page allows right now: connecting while the line is down, the
## rules for everybody but a joined player, the start for a host with a guest.
func _sync_lan_page() -> void:
	if _link == null:
		return
	var role: StringName = _link.role()
	var text: String = tr(_lan_status)
	if text.contains("%s"):
		text = text % _lan_status_arg
	_setup.show_lan(text, role == _link.ROLE_NONE, role != _link.ROLE_CLIENT, role == _link.ROLE_HOST and _link.has_peer())


func _lan_settings() -> Dictionary:
	return {"rules": _versus_rules, "level": _versus_level, "format": _versus_format}


func _apply_lan_settings(settings: Dictionary) -> void:
	var rules: StringName = StringName(String(settings.get("rules", "")))
	if _option_index(RULE_OPTIONS, rules) >= 0:
		_versus_rules = rules
	_versus_level = clampi(int(settings.get("level", _versus_level)), VERSUS_FIXED_LEVEL_MIN, VERSUS_FIXED_LEVEL_MAX)
	var match_format: StringName = StringName(String(settings.get("format", "")))
	if _option_index(FORMAT_OPTIONS, match_format) >= 0:
		_versus_format = match_format
	_sync_versus_page()


func _on_lan_host_pressed() -> void:
	if _link.host() != OK:
		_set_lan_status("LAN_STATUS_FAILED")
		return
	_set_lan_status("LAN_STATUS_HOSTING", ", ".join(_link.local_addresses()))


func _on_lan_join_pressed(address: String) -> void:
	if address.strip_edges().is_empty():
		_set_lan_status("LAN_STATUS_NO_ADDRESS")
		return
	PlayerConfig.set_config(CONFIG_SECTION, "Address", address.strip_edges())
	if _link.join(address) != OK:
		_set_lan_status("LAN_STATUS_FAILED")
		return
	_set_lan_status("LAN_STATUS_CONNECTING", address.strip_edges())


func _on_lan_peer_joined() -> void:
	if _link.role() == _link.ROLE_HOST:
		_link.send_settings(_lan_settings())
		_set_lan_status("LAN_STATUS_GUEST_JOINED")
	else:
		_set_lan_status("LAN_STATUS_JOINED")


func _on_lan_peer_left() -> void:
	if _link.role() == _link.ROLE_HOST:
		_set_lan_status("LAN_STATUS_HOSTING", ", ".join(_link.local_addresses()))
	else:
		_set_lan_status("LAN_PEER_LEFT")


func _on_lan_settings_received(settings: Dictionary) -> void:
	_apply_lan_settings(settings)


func _on_lan_start_received(settings: Dictionary) -> void:
	_apply_lan_settings(settings)
	_begin_lan_match(_link.ROLE_CLIENT)


func _begin_lan_match(role: StringName) -> void:
	_lan_starting = true
	var level: int = _versus_level if _versus_rules == VERSUS_RULES_FIXED else VERSUS_FIXED_LEVEL_MIN
	select_mode(GameSession.MODE_VERSUS, VERSUS_SCENE_PATH, _versus_rules, level, _versus_format, &"", &"", role)
