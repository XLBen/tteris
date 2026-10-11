extends "res://scenes/menus/main_menu/main_menu_with_animations.gd"
## Mode select menu (Classic / Versus), built on the vendored
## Maaack animated main-menu variant so the template's Intro / OpenMainMenu
## entry animation plays when the scene opens.
##
## Classic starts the single-player scene immediately. Versus opens the setup
## page - the resource pack's "versus_setup" layout (scripts/ui/versus_setup.gd)
## - where speed, level, who plays each side and the match format are picked;
## the current choice of each group stays highlighted, a description follows
## the focused option and Start Match begins the battle. The choices are
## remembered between sessions through PlayerConfig and written through
## GameSession.start_versus() before the versus scene is loaded. Back returns
## from the setup page to the mode buttons, and from there to the main menu.
## (How to Play and Resource Packs are entries of the main menu.)

const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const VERSUS_RULES_FIXED: StringName = &"fixed"
const VERSUS_RULES_RISING: StringName = &"rising"
const VERSUS_FORMAT_SINGLE: StringName = &"single"
const VERSUS_FORMAT_BEST_OF_3: StringName = &"best_of_3"
const VERSUS_DIFFICULTY_NORMAL: StringName = &"normal"
## Left-board choice that keeps the human on it (the session stores it empty).
const VERSUS_LEFT_YOU: StringName = &"you"
const VERSUS_FIXED_LEVEL_MIN: int = 1
const VERSUS_FIXED_LEVEL_MAX: int = 10
const CONFIG_SECTION: String = "VersusSettings"
## Choices per group: [value, button text, description key].
const RULE_OPTIONS: Array = [
	[&"fixed", "Fixed Speed", "VERSUS_DESC_FIXED"],
	[&"rising", "Rising Speed", "VERSUS_DESC_RISING"],
]
const DIFFICULTY_OPTIONS: Array = [
	[&"easy", "Easy", "VERSUS_DESC_EASY"],
	[&"normal", "Normal", "VERSUS_DESC_NORMAL"],
	[&"hard", "Hard", "VERSUS_DESC_HARD"],
	[&"lunatic", "Lunatic", "VERSUS_DESC_LUNATIC"],
]
const LEFT_OPTIONS: Array = [
	[&"you", "You", "VERSUS_DESC_YOU"],
	[&"easy", "Easy", "VERSUS_DESC_LEFT_CPU"],
	[&"normal", "Normal", "VERSUS_DESC_LEFT_CPU"],
	[&"hard", "Hard", "VERSUS_DESC_LEFT_CPU"],
	[&"lunatic", "Lunatic", "VERSUS_DESC_LEFT_CPU"],
]
const FORMAT_OPTIONS: Array = [
	[&"single", "Single Match", "VERSUS_DESC_SINGLE"],
	[&"best_of_3", "Best of 3", "VERSUS_DESC_BEST_OF_3"],
]

var _versus_active: bool = false
var _versus_rules: StringName = VERSUS_RULES_FIXED
var _versus_level: int = VERSUS_FIXED_LEVEL_MIN
var _versus_difficulty: StringName = VERSUS_DIFFICULTY_NORMAL
var _versus_left: StringName = VERSUS_LEFT_YOU
var _versus_format: StringName = VERSUS_FORMAT_SINGLE
var _versus_options: BoxContainer
var _classic_button: Button
var _versus_button: Button
var _setup: VersusSetup
var _description: Label
var _start_button: Button
var _level_row: Control


func _ready() -> void:
	super._ready()
	_versus_options = find_child("VersusOptionsBoxContainer", true, false) as BoxContainer
	_classic_button = find_child("ClassicButton", true, false) as Button
	_versus_button = find_child("VersusButton", true, false) as Button
	_load_versus_choices()
	_build_versus_page()
	_versus_options.visible = false
	# The versus result screen's "Change Settings" lands straight on the page.
	var session: Node = get_node_or_null(^"/root/GameSession")
	if session != null and bool(session.open_versus_setup):
		session.open_versus_setup = false
		_on_versus_button_pressed.call_deferred()


## Starts `mode` and loads its scene. Optional versus fields override the
## defaults so the setup page can pass its selection in one call.
func select_mode(mode: StringName, scene_path: String = "", versus_rules: StringName = &"", versus_level: int = 0, versus_format: StringName = &"", versus_difficulty: StringName = &"", versus_left: StringName = &"") -> void:
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
			session.start_versus(rules, level, match_format, difficulty, versus_left)
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
# Versus setup page
func _load_versus_choices() -> void:
	var rules: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Rules", String(VERSUS_RULES_FIXED))))
	if _option_index(RULE_OPTIONS, rules) >= 0:
		_versus_rules = rules
	_versus_level = clampi(int(PlayerConfig.get_config(CONFIG_SECTION, "Level", VERSUS_FIXED_LEVEL_MIN)), VERSUS_FIXED_LEVEL_MIN, VERSUS_FIXED_LEVEL_MAX)
	var difficulty: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Difficulty", String(VERSUS_DIFFICULTY_NORMAL))))
	if _option_index(DIFFICULTY_OPTIONS, difficulty) >= 0:
		_versus_difficulty = difficulty
	var left: StringName = StringName(String(PlayerConfig.get_config(CONFIG_SECTION, "Left", String(VERSUS_LEFT_YOU))))
	if _option_index(LEFT_OPTIONS, left) >= 0:
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


func _on_option_focused(group: String, value: Variant) -> void:
	match group:
		"rules":
			_describe(String(RULE_OPTIONS[_option_index(RULE_OPTIONS, value)][2]), value)
		"level":
			_describe("VERSUS_DESC_LEVEL", value)
		"left":
			_describe(String(LEFT_OPTIONS[_option_index(LEFT_OPTIONS, value)][2]), value)
		"difficulty":
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


func _on_classic_button_pressed() -> void:
	select_mode(GameSession.MODE_CLASSIC)


func _on_versus_button_pressed() -> void:
	_versus_active = true
	_versus_options.visible = true
	for button: Button in [_classic_button, _versus_button]:
		if button != null:
			button.visible = false
	_sync_versus_page()
	# Deferred so the visibility changes above are applied before grabbing.
	_start_button.grab_focus.call_deferred()


func _on_start_button_pressed() -> void:
	_save_versus_choices()
	var level: int = _versus_level if _versus_rules == VERSUS_RULES_FIXED else VERSUS_FIXED_LEVEL_MIN
	var left: StringName = _versus_left if _versus_left != VERSUS_LEFT_YOU else &""
	select_mode(GameSession.MODE_VERSUS, VERSUS_SCENE_PATH, _versus_rules, level, _versus_format, _versus_difficulty, left)


func _on_back_button_pressed() -> void:
	if _versus_active:
		_leave_versus_options()
		return
	_return_to_main_menu()


func _leave_versus_options() -> void:
	_versus_active = false
	_versus_options.visible = false
	for button: Button in [_classic_button, _versus_button]:
		if button != null:
			button.visible = true
	if _versus_button != null and _versus_button.is_inside_tree():
		_versus_button.grab_focus()
