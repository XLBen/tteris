extends SceneTree

const MODULE_NAME: String = "menu"

const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const MODE_SELECT_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const OPTIONS_WINDOW_PATH: String = "res://scenes/windows/main_menu_options_window.tscn"
const GAME_SCENE_PATH: String = "res://scenes/main.tscn"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const AUTOLOAD_NAMES: Array[String] = [
	"SceneLoader",
	"GameSession",
	"ProjectMusicController",
	"ProjectUISoundController",
	"LanSession",
]
const MODE_BUTTONS: Dictionary = {
	"ClassicButton": &"classic",
	"VersusButton": &"versus",
}
const MODE_BUTTON_SCENES: Dictionary = {
	"ClassicButton": GAME_SCENE_PATH,
	"VersusButton": VERSUS_SCENE_PATH,
}
# 2026-10-12 (owner): the main menu picks the way to play; this screen is the
# versus setup page.
const MODE_SELECT_BUTTONS: Array[String] = ["SoloButton", "PveButton", "EveButton", "LanButton", "BackButton"]
const REMOVED_MODE_BUTTONS: Array[String] = [
	"EasyButton",
	"NormalButton",
	"HardButton",
	"LunaticButton",
	"GrowthButton",
	"ClassicButton",
	"VersusButton",
]
# 2026-10-11 (owner): How to Play and Resource Packs are main menu entries.
# 2026-10-12 (owner): the ways to play are on the screen behind New Game.
const VISIBLE_ENTRY_BUTTONS: Array[String] = ["NewGameButton", "OptionsButton", "HowToPlayButton", "ResourcePackButton", "ExitButton"]
const HIDDEN_ENTRY_BUTTONS: Array[String] = ["CreditsButton", "ContinueGameButton", "LevelSelectButton"]
const OPTIONS_TAB_COUNT: int = 4
const EXPECTED_CASES: int = 7


class SceneLoaderStub:
	extends RefCounted

	var loaded_paths: Array[String] = []

	func load_scene(scene_path: String, _in_background: bool = false) -> void:
		loaded_paths.append(scene_path)


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0 or int(result["total"]) != EXPECTED_CASES:
		print("FAILED: %d of %d menu cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("MENU TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_autoloads_and_game_session(ctx)
	await _case_main_scene_is_main_menu(ctx)
	await _case_menu_entries(ctx)
	await _case_main_menu_pages_open_and_close(ctx)
	await _case_mode_select_structure(ctx)
	await _case_mode_buttons_map_to_session(ctx)
	await _case_options_window_opens_and_closes(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _wins_are(session, player: int, ai: int) -> bool:
	var wins: Array = session.versus_round_wins
	return wins.size() == 2 and int(wins[0]) == player and int(wins[1]) == ai


static func _spawn_menu():
	var menu = (load(MAIN_MENU_PATH) as PackedScene).instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	return menu


static func _case_autoloads_and_game_session(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var ok: bool = true
	for autoload_name: String in AUTOLOAD_NAMES:
		if tree.root.get_node_or_null(NodePath(autoload_name)) == null:
			ok = false
	var session = tree.root.get_node_or_null(^"GameSession")
	if session == null:
		ok = false
	else:
		var previous_mode: StringName = session.mode
		ok = ok and session.MODE_NONE == &"none" \
			and session.MODE_CLASSIC == &"classic" and session.MODE_VERSUS == &"versus"
		ok = ok and session.VERSUS_RULES_FIXED == &"fixed" \
			and session.VERSUS_RULES_RISING == &"rising" \
			and session.VERSUS_FORMAT_SINGLE == &"single" \
			and session.VERSUS_FORMAT_BEST_OF_3 == &"best_of_3" \
			and int(session.VERSUS_FIXED_LEVEL_MIN) == 1 \
			and int(session.VERSUS_FIXED_LEVEL_MAX) == 10
		session.start_mode(session.MODE_NONE)
		ok = ok and session.is_classic() == false and session.is_versus() == false \
			and int(session.initial_level()) == 1
		ok = ok and session.versus_rules == &"" and int(session.versus_fixed_level) == 0 \
			and session.versus_match_format == &"" and _wins_are(session, 0, 0) \
			and int(session.versus_round_index) == 1 and session.versus_match_in_progress == false
		session.start_classic()
		ok = ok and session.mode == &"classic" and session.is_classic() == true \
			and session.is_versus() == false and int(session.initial_level()) == 1
		session.start_versus(session.VERSUS_RULES_FIXED, 6, session.VERSUS_FORMAT_BEST_OF_3)
		ok = ok and session.mode == &"versus" and session.is_versus() == true \
			and session.is_classic() == false and int(session.initial_level()) == 6
		ok = ok and session.versus_rules == &"fixed" and int(session.versus_fixed_level) == 6 \
			and session.versus_match_format == &"best_of_3" \
			and _wins_are(session, 0, 0) and int(session.versus_round_index) == 1 \
			and session.versus_match_in_progress == true
		session.save_versus_progress([1, 0], 2)
		ok = ok and _wins_are(session, 1, 0) and int(session.versus_round_index) == 2
		# Rising speed always starts at level 1 (2026-10-10: replaces the old
		# per-side "classic" versus rules).
		session.start_versus(session.VERSUS_RULES_RISING, 3, session.VERSUS_FORMAT_SINGLE)
		ok = ok and int(session.initial_level()) == 1
		session.start_mode(previous_mode)
	_case(ctx, "autoloads_and_game_session_classic_versus", ok)


static func _case_main_scene_is_main_menu(ctx: Dictionary) -> void:
	var run_main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	var menu_setting: String = String(ProjectSettings.get_setting("maaacks_game_template/main_menu_scene_path"))
	var packed: PackedScene = load(MAIN_MENU_PATH) as PackedScene
	var ok: bool = run_main_scene == MAIN_MENU_PATH and menu_setting == MAIN_MENU_PATH \
		and packed != null
	if packed != null:
		var instance: Node = packed.instantiate()
		ok = ok and instance != null
		if instance != null:
			ok = ok and instance.find_child("MenuButtonsBoxContainer", true, false) != null
			instance.free()
	_case(ctx, "main_scene_is_main_menu_scene", ok)


static func _case_menu_entries(ctx: Dictionary) -> void:
	var menu = await _spawn_menu()
	var ok: bool = true
	for button_name: String in VISIBLE_ENTRY_BUTTONS:
		var button: Node = menu.find_child(button_name, true, false)
		ok = ok and button is Button and (button as Button).visible \
			and not (button as Button).disabled
	for button_name: String in HIDDEN_ENTRY_BUTTONS:
		var button: Node = menu.find_child(button_name, true, false)
		ok = ok and button is Button and not (button as Button).visible
	# Top to bottom: the four ways to play, then the rest.
	var order: Array[int] = []
	for button_name: String in VISIBLE_ENTRY_BUTTONS:
		var entry: Node = menu.find_child(button_name, true, false)
		order.append(entry.get_index() if entry != null else -1)
	var sorted: Array[int] = order.duplicate()
	sorted.sort()
	ok = ok and order == sorted
	# New Game opens the play screen, where the ways to play are; none of
	# them sits on the main menu itself.
	ok = ok and String(menu.get_game_scene_path()) == MODE_SELECT_PATH
	for button_name: String in ["SoloButton", "PveButton", "EveButton", "LanButton"]:
		ok = ok and menu.find_child(button_name, true, false) == null
	# The pack's animated title stands in for the text title.
	var title: PackTitle = menu.find_child("PackTitle", true, false) as PackTitle
	var label: Label = menu.find_child("TitleLabel", true, false) as Label
	ok = ok and title != null and label != null and label.self_modulate.a == 0.0
	if title != null:
		var pack_title: Dictionary = ResourcePack.title()
		var frames: int = int(pack_title["frames"])
		var loop_from: int = int(pack_title["loop_from"])
		var fps: float = float(pack_title["fps"])
		# The intro plays once, then the loop goes round.
		ok = ok and loop_from > 0 and loop_from < frames and title.frame_at(0.0) == 0
		ok = ok and title.frame_at((float(frames) - 0.5) / fps) == frames - 1 and title.frame_at((float(frames) + 0.5) / fps) == loop_from
		ok = ok and title.frame_at((float(frames + (frames - loop_from)) + 0.5) / fps) == loop_from
		ok = ok and int(pack_title["columns"]) * (pack_title["frame"] as Vector2i).x <= (pack_title["texture"] as Texture2D).get_width()
	# Behind the menus runs the pack's animated backdrop: one loop of whole frames.
	var backdrop: PackBackdrop = _tree().root.find_child("PackBackdrop", true, false) as PackBackdrop
	var pack_backdrop: Dictionary = ResourcePack.backdrop()
	ok = ok and backdrop != null and not pack_backdrop.is_empty()
	if backdrop != null and not pack_backdrop.is_empty():
		var count: int = int(pack_backdrop["frames"])
		var rate: float = float(pack_backdrop["fps"])
		var rows: int = ceili(float(count) / float(int(pack_backdrop["columns"])))
		ok = ok and count > 1 and backdrop.frame_at(0.0) == 0 and backdrop.frame_at((float(count) - 0.5) / rate) == count - 1 			and backdrop.frame_at((float(count) + 0.5) / rate) == 0
		ok = ok and rows * (pack_backdrop["frame"] as Vector2i).y <= (pack_backdrop["texture"] as Texture2D).get_height()
	menu.free()
	_case(ctx, "menu_entries_new_game_options_exit", ok)


# How to Play and Resource Packs open from the main menu; ui_cancel closes
# the open page instead of asking to exit, and the mode select has neither.
static func _case_main_menu_pages_open_and_close(ctx: Dictionary) -> void:
	var menu = await _spawn_menu()
	var how_button: Button = menu.find_child("HowToPlayButton", true, false) as Button
	var pack_button: Button = menu.find_child("ResourcePackButton", true, false) as Button
	var options: Button = menu.find_child("OptionsButton", true, false) as Button
	var page: HowToPlay = menu.find_child("HowToPlay", true, false) as HowToPlay
	var entries: MainMenuEntries = menu.get_node_or_null(^"MainMenuEntries") as MainMenuEntries
	var screen: PackSelect = entries.pack_select() if entries != null else null
	var exit_confirmation: Control = menu.find_child("ExitConfirmation", true, false) as Control
	var ok: bool = how_button != null and pack_button != null and page != null and screen != null 		and exit_confirmation != null
	if ok:
		# Order: Options, How to Play, Resource Packs.
		ok = how_button.get_index() == options.get_index() + 1 and pack_button.get_index() == how_button.get_index() + 1
		ok = ok and how_button.text == "How to Play" and pack_button.text == "Resource Packs"
		var cancel: InputEventAction = InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		how_button.pressed.emit()
		ok = ok and page.visible and page.body_text().contains(TranslationServer.translate("HOWTO_SCORING_TITLE"))
		menu.get_viewport().push_input(cancel)
		ok = ok and not page.visible and not exit_confirmation.visible
		pack_button.pressed.emit()
		ok = ok and screen.visible
		menu.get_viewport().push_input(cancel)
		ok = ok and not screen.visible and not exit_confirmation.visible
		# With no page open ui_cancel is the template's exit question again.
		menu.get_viewport().push_input(cancel)
		ok = ok and exit_confirmation.visible
	menu.free()
	var select = (load(MODE_SELECT_PATH) as PackedScene).instantiate()
	_tree().root.add_child(select)
	await _tree().process_frame
	ok = ok and select.find_child("HowToPlayButton", true, false) == null 		and select.find_child("ResourcePackButton", true, false) == null
	select.free()
	await _tree().process_frame
	_case(ctx, "main_menu_how_to_play_and_packs_open_and_close", ok)


static func _case_mode_select_structure(ctx: Dictionary) -> void:
	var packed: PackedScene = load(MODE_SELECT_PATH) as PackedScene
	var ok: bool = packed != null
	var select = null
	if packed != null:
		select = packed.instantiate()
		ok = ok and select != null
	if select != null:
		_tree().root.add_child(select)
		await _tree().process_frame
		for button_name: String in MODE_SELECT_BUTTONS:
			var button: Node = select.find_child(button_name, true, false)
			ok = ok and button is Button and (button as Button).visible
		# The old difficulty/growth entries are gone, not just hidden.
		for button_name: String in REMOVED_MODE_BUTTONS:
			ok = ok and select.find_child(button_name, true, false) == null
		var select_target: String = String(select.get_game_scene_path())
		ok = ok and select_target == GAME_SCENE_PATH
		select.free()
	_case(ctx, "mode_select_scene_has_classic_versus_and_back", ok)


static func _case_mode_buttons_map_to_session(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var session = tree.root.get_node_or_null(^"GameSession")
	var real_loader = tree.root.get_node_or_null(^"SceneLoader")
	if session == null or real_loader == null:
		_case(ctx, "mode_buttons_map_to_game_session_without_scene_change", false)
		return
	var loader_path_before: Variant = real_loader.get("_scene_path")
	var select = (load(MODE_SELECT_PATH) as PackedScene).instantiate()
	tree.root.add_child(select)
	await tree.process_frame
	var stub: SceneLoaderStub = SceneLoaderStub.new()
	select.scene_loader_node = stub
	var ok: bool = true
	session.start_mode(session.MODE_NONE)
	# select_mode() is the one way out of this screen: classic writes the mode
	# and loads the single-player scene.
	select.select_mode(MODE_BUTTONS["ClassicButton"])
	ok = ok and session.mode == MODE_BUTTONS["ClassicButton"]
	ok = ok and session.is_classic() == true and session.is_versus() == false
	ok = ok and session.versus_match_in_progress == false and _wins_are(session, 0, 0)
	ok = ok and stub.loaded_paths.size() == 1 \
		and stub.loaded_paths[0] == MODE_BUTTON_SCENES["ClassicButton"]
	# The list comes first: Solo is the same way out, each versus entry opens
	# its setup page in place. Nothing is written to the session and no scene
	# is loaded until Start Match.
	var options: Node = select.find_child("VersusOptionsBoxContainer", true, false)
	ok = ok and select.page() == &"menu" and options is BoxContainer and not (options as BoxContainer).visible
	session.start_mode(session.MODE_NONE)
	(select.find_child("SoloButton", true, false) as Button).pressed.emit()
	ok = ok and session.is_classic() and stub.loaded_paths.size() == 2 and stub.loaded_paths[1] == MODE_BUTTON_SCENES["ClassicButton"]
	stub.loaded_paths.remove_at(1)
	for entry: Array in [["EveButton", &"eve"], ["LanButton", &"lan"], ["PveButton", &"pve"]]:
		if select.page() != &"menu":
			(select.find_child("BackButton", true, false) as Button).pressed.emit()
		(select.find_child(String(entry[0]), true, false) as Button).pressed.emit()
		ok = ok and select.page() == entry[1] and session.versus_page == entry[1] and (options as BoxContainer).visible \
			and not (select.find_child("SoloButton", true, false) as Button).visible
	ok = ok and options is BoxContainer and (options as BoxContainer).visible
	ok = ok and session.mode == MODE_BUTTONS["ClassicButton"] \
		and session.is_versus() == false and stub.loaded_paths.size() == 1
	(select.find_child("VersusSpeedFixedSpeed", true, false) as Button).pressed.emit()
	# Every choice is on the page at once and the picked option of each row
	# stays highlighted (toggle buttons in one group per row).
	for option_name: String in ["VersusSpeedFixedSpeed", "VersusSpeedRisingSpeed",
			"VersusCPUEasy", "VersusCPUNormal", "VersusCPUHard", "VersusCPULunatic",
			"VersusMatchSingleMatch", "VersusMatchBestof3"]:
		var option: Button = select.find_child(option_name, true, false) as Button
		ok = ok and option != null and option.visible and option.toggle_mode
	var level_total: int = 0
	for level: int in range(1, 11):
		var level_button: Button = select.find_child("VersusLevel%d" % level, true, false) as Button
		ok = ok and level_button != null and level_button.visible and level_button.text == str(level)
		if level_button != null:
			level_total += 1
	ok = ok and level_total == 10
	for pick: String in ["VersusSpeedFixedSpeed", "VersusLevel1", "VersusCPUNormal", "VersusMatchSingleMatch"]:
		var picked: Button = select.find_child(pick, true, false) as Button
		if picked != null:
			picked.pressed.emit()
			ok = ok and picked.button_pressed
	ok = ok and stub.loaded_paths.size() == 1
	var start_button: Button = select.find_child("VersusStartButton", true, false) as Button
	ok = ok and start_button != null and start_button.visible
	if start_button != null:
		start_button.pressed.emit()
	ok = ok and session.mode == MODE_BUTTONS["VersusButton"]
	ok = ok and session.is_versus() == true and session.is_classic() == false
	ok = ok and session.versus_rules == &"fixed" and int(session.versus_fixed_level) == 1
	ok = ok and session.versus_match_format == &"single"
	ok = ok and session.versus_difficulty == &"normal"
	ok = ok and _wins_are(session, 0, 0) and int(session.versus_round_index) == 1
	ok = ok and session.versus_match_in_progress == true
	ok = ok and stub.loaded_paths.size() == 2 \
		and stub.loaded_paths[1] == MODE_BUTTON_SCENES["VersusButton"]
	var back: Node = select.find_child("BackButton", true, false)
	var back_wired: bool = false
	if back is Button:
		for connection: Dictionary in (back as Button).pressed.get_connections():
			if (connection["callable"] as Callable).get_method() == "_on_back_button_pressed":
				back_wired = true
	ok = ok and back_wired
	# Isolation: mode selection must not start a real background scene change.
	await tree.process_frame
	await tree.process_frame
	ok = ok and real_loader.get("_scene_path") == loader_path_before
	ok = ok and select.get_parent() == tree.root
	select.free()
	session.start_mode(session.MODE_NONE)
	_case(ctx, "mode_buttons_map_to_game_session_without_scene_change", ok)


static func _case_options_window_opens_and_closes(ctx: Dictionary) -> void:
	var menu = await _spawn_menu()
	var options_scene: Variant = menu.get("options_packed_scene")
	var ok: bool = options_scene is PackedScene \
		and String((options_scene as PackedScene).resource_path) == OPTIONS_WINDOW_PATH
	var options_button: Node = menu.find_child("OptionsButton", true, false)
	if options_button is Button:
		(options_button as Button).pressed.emit()
	else:
		ok = false
	await _tree().process_frame
	await _tree().process_frame
	var sub_menu: Variant = menu.get("sub_menu")
	ok = ok and sub_menu != null
	if sub_menu != null:
		ok = ok and sub_menu.get("is_opened") == true and (sub_menu as Node).visible
		var tabs: Node = (sub_menu as Node).find_child("MasterOptionsMenu", true, false)
		ok = ok and tabs is TabContainer and (tabs as TabContainer).get_tab_count() == OPTIONS_TAB_COUNT
		var close_button: Variant = sub_menu.get("close_button")
		ok = ok and close_button is Button
		if close_button is Button:
			(close_button as Button).pressed.emit()
			await _tree().process_frame
			await _tree().process_frame
			if is_instance_valid(sub_menu):
				ok = ok and sub_menu.get("is_opened") == false
				ok = ok and not (sub_menu as Node).visible
			ok = ok and menu.get("sub_menu") == null
	menu.free()
	_case(ctx, "options_entry_opens_tabbed_window_and_closes", ok)
