extends SceneTree
## Versus entry flow: the mode select's versus setup page (one page - Speed /
## Level / CPU / Match toggle rows, a description line and Start Match) writes
## the GameSession configuration, loads the versus scene, remembers the
## choices and steps Back correctly. A SceneLoaderStub isolates every scene
## change from the real autoload.
##
## Rewritten 2026-10-10: the page replaces the three-step wizard (rules ->
## difficulty -> level + format) these cases used to walk. Owner feedback was
## that the wizard gave no selection feedback, started the match from the
## format button and forgot the difficulty.

const MODULE_NAME: String = "versus_flow"

const MODE_SELECT_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const CONFIG_SECTION: String = "VersusSettings"
const CONFIG_KEYS: Array[String] = ["Rules", "Level", "Difficulty", "Left", "Format"]

const SIDE_PLAYER: int = VersusBattle.Side.PLAYER
const SIDE_AI: int = VersusBattle.Side.AI


class SceneLoaderStub:
	extends RefCounted

	var loaded_paths: Array[String] = []

	func load_scene(scene_path: String, _in_background: bool = false) -> void:
		loaded_paths.append(scene_path)


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d versus flow cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VERSUS FLOW TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	# The page persists its choices; keep the player's own ones intact.
	var saved: Dictionary = {}
	for key: String in CONFIG_KEYS:
		if PlayerConfig.has_section_key(CONFIG_SECTION, key):
			saved[key] = PlayerConfig.get_config(CONFIG_SECTION, key)
	await _case_page_hidden_with_every_choice_built(ctx)
	await _case_fixed_choices_start_writes_session_and_loads_versus(ctx)
	await _case_rising_hides_level_row_and_starts_at_level_1(ctx)
	await _case_picked_option_stays_highlighted(ctx)
	await _case_back_leaves_page_then_returns_to_main_menu(ctx)
	await _case_start_versus_resets_progress(ctx)
	await _case_page_focus_and_description_follow_the_option(ctx)
	await _case_choices_are_remembered(ctx)
	await _case_change_settings_reopens_the_page(ctx)
	await _case_versus_scene_reads_session_and_starts_at_0_0(ctx)
	await _case_left_cpu_choice_reaches_session_and_is_remembered(ctx)
	await _case_cpu_vs_cpu_scene_plays_itself(ctx)
	for key: String in CONFIG_KEYS:
		if saved.has(key):
			PlayerConfig.set_config(CONFIG_SECTION, key, saved[key])
		elif PlayerConfig.has_section_key(CONFIG_SECTION, key):
			PlayerConfig.erase_section_key(CONFIG_SECTION, key)
	await _tree().process_frame
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


static func _session():
	return _tree().root.get_node_or_null(^"GameSession")


static func _forget_choices() -> void:
	for key: String in CONFIG_KEYS:
		if PlayerConfig.has_section_key(CONFIG_SECTION, key):
			PlayerConfig.erase_section_key(CONFIG_SECTION, key)


## The versus setup screen on `page` (2026-10-12: the main menu opens it on
## one of three pages), with no remembered choices and its scene changes
## stubbed.
static func _spawn_mode_select(forget: bool = true, page: StringName = &"pve"):
	if forget:
		_forget_choices()
	# Opened the way a match's "Change Settings" does: straight on the page
	# (from the main menu the screen starts on the list of ways to play).
	_session().versus_page = page
	_session().open_versus_setup = true
	var scene = (load(MODE_SELECT_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	scene.scene_loader_node = SceneLoaderStub.new()
	await _tree().process_frame
	return scene


static func _button(scene, button_name: String) -> Button:
	if scene == null:
		return null
	return scene.find_child(button_name, true, false) as Button


static func _press(scene, button_name: String) -> bool:
	# The setup page is the whole screen now: there is no Versus entry to
	# press first.
	if button_name == "VersusButton":
		return scene != null
	var button: Button = _button(scene, button_name)
	if button == null:
		return false
	button.pressed.emit()
	return true


static func _wins_are(session, player: int, ai: int) -> bool:
	var wins: Array = session.versus_round_wins
	return wins.size() == 2 and int(wins[0]) == player and int(wins[1]) == ai


static func _free(scene) -> void:
	scene.free()
	await _tree().process_frame


static func _case_page_hidden_with_every_choice_built(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var options: BoxContainer = select.find_child("VersusOptionsBoxContainer", true, false) as BoxContainer
	var ok: bool = options != null and options.visible
	# Versus CPU: the opponent's card only. Mode and match are cards of their own.
	ok = ok and select.page() == &"pve" and not (select.find_child("LeftCard", true, false) as Control).visible \
		and (select.find_child("RightCard", true, false) as Control).visible \
		and not (select.find_child("LanCard", true, false) as Control).visible
	ok = ok and select.find_child("ModeCard", true, false) != null and select.find_child("MatchCard", true, false) != null \
		and _button(select, "VersusMatchSingleMatch").get_parent().get_parent().name == &"MatchCard" \
		and _button(select, "VersusSpeedRisingSpeed").get_index() < _button(select, "VersusSpeedFixedSpeed").get_index()
	ok = ok and _button(select, "VersusButton") == null and _button(select, "ClassicButton") == null
	# The list of ways to play is behind the page.
	for entry: String in ["SoloButton", "PveButton", "EveButton", "LanButton"]:
		ok = ok and _button(select, entry) != null and not _button(select, entry).visible
	var level_total: int = 0
	for level: int in range(1, 11):
		var button: Button = _button(select, "VersusLevel%d" % level)
		ok = ok and button != null and button.text == str(level) and button.toggle_mode
		if button != null:
			level_total += 1
	ok = ok and level_total == 10
	for button_name: String in ["BackButton",
			"VersusSpeedFixedSpeed", "VersusSpeedRisingSpeed",
			"VersusCPUEasy", "VersusCPUNormal", "VersusCPUHard", "VersusCPULunatic",
			"VersusMatchSingleMatch", "VersusMatchBestof3", "VersusStartButton"]:
		ok = ok and _button(select, button_name) != null
	# Defaults (2026-10-12, owner: versus opens on Classic): classic speed,
	# level 1, normal, single match.
	ok = ok and select._versus_rules == &"rising" and select._versus_level == 1 \
		and _button(select, "VersusSpeedRisingSpeed").text == "Classic" \
		and select._versus_difficulty == &"normal" and select._versus_format == &"single"
	await _free(select)
	_case(ctx, "versus_page_hidden_with_all_rows_and_10_level_buttons", ok)


static func _case_fixed_choices_start_writes_session_and_loads_versus(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var session = _session()
	session.start_mode(session.MODE_NONE)
	var stub: SceneLoaderStub = select.scene_loader_node
	var ok: bool = _press(select, "VersusButton")
	ok = ok and (select.find_child("VersusOptionsBoxContainer", true, false) as Control).visible
	ok = ok and _press(select, "VersusSpeedFixedSpeed")
	ok = ok and _press(select, "VersusLevel7")
	ok = ok and _press(select, "VersusCPUHard")
	ok = ok and _press(select, "VersusMatchBestof3")
	# Picking options starts nothing: the match begins from Start Match only.
	ok = ok and stub.loaded_paths.is_empty() and not session.is_versus()
	ok = ok and _press(select, "VersusStartButton")
	ok = ok and session.is_versus() and session.versus_rules == session.VERSUS_RULES_FIXED
	ok = ok and int(session.versus_fixed_level) == 7 and int(session.initial_level()) == 7
	ok = ok and session.versus_difficulty == &"hard"
	ok = ok and session.versus_match_format == session.VERSUS_FORMAT_BEST_OF_3
	ok = ok and session.versus_match_in_progress == true
	ok = ok and stub.loaded_paths.size() == 1 and stub.loaded_paths[0] == VERSUS_SCENE_PATH
	# The session level feeds both boards.
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, int(session.versus_fixed_level), VersusBattle.MatchFormat.SINGLE, 20260917)
	ok = ok and battle.level(SIDE_PLAYER) == 7 and battle.level(SIDE_AI) == 7
	await _free(select)
	session.start_mode(session.MODE_NONE)
	_case(ctx, "fixed_choices_then_start_writes_session_and_loads_versus", ok)


static func _case_rising_hides_level_row_and_starts_at_level_1(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var session = _session()
	session.start_mode(session.MODE_NONE)
	var stub: SceneLoaderStub = select.scene_loader_node
	var ok: bool = _press(select, "VersusButton")
	# Classic is the default, so the level row only shows for a fixed speed.
	ok = ok and not _button(select, "VersusLevel9").is_visible_in_tree()
	ok = ok and _press(select, "VersusSpeedFixedSpeed")
	ok = ok and _press(select, "VersusLevel9")
	ok = ok and _button(select, "VersusLevel9").is_visible_in_tree()
	ok = ok and _press(select, "VersusSpeedRisingSpeed")
	ok = ok and not _button(select, "VersusLevel9").is_visible_in_tree()
	ok = ok and _press(select, "VersusStartButton")
	ok = ok and session.versus_rules == session.VERSUS_RULES_RISING
	# Rising speed ignores the level row: it always starts at level 1.
	ok = ok and int(session.versus_fixed_level) == 1 and int(session.initial_level()) == 1
	ok = ok and session.versus_match_format == session.VERSUS_FORMAT_SINGLE
	ok = ok and stub.loaded_paths.size() == 1 and stub.loaded_paths[0] == VERSUS_SCENE_PATH
	await _free(select)
	session.start_mode(session.MODE_NONE)
	_case(ctx, "rising_speed_hides_level_row_and_starts_at_level_1", ok)


static func _case_picked_option_stays_highlighted(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var ok: bool = _press(select, "VersusButton")
	# Defaults are shown as pressed toggles.
	for name: String in ["VersusSpeedRisingSpeed", "VersusLevel1", "VersusCPUNormal", "VersusMatchSingleMatch"]:
		ok = ok and _button(select, name).button_pressed
	ok = ok and _press(select, "VersusSpeedFixedSpeed")
	ok = ok and _press(select, "VersusLevel4") and _press(select, "VersusCPULunatic")
	ok = ok and _button(select, "VersusLevel4").button_pressed and not _button(select, "VersusLevel1").button_pressed
	ok = ok and _button(select, "VersusCPULunatic").button_pressed and not _button(select, "VersusCPUNormal").button_pressed
	# One group per row: a level pick never clears the CPU pick.
	ok = ok and _press(select, "VersusLevel10")
	ok = ok and _button(select, "VersusCPULunatic").button_pressed and not _button(select, "VersusLevel4").button_pressed
	await _free(select)
	_case(ctx, "picked_option_of_each_row_stays_highlighted", ok)


static func _case_back_leaves_page_then_returns_to_main_menu(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var session = _session()
	session.start_mode(session.MODE_NONE)
	var stub: SceneLoaderStub = select.scene_loader_node
	var ok: bool = _press(select, "VersusCPUHard")
	ok = ok and stub.loaded_paths.is_empty() and not session.is_versus()
	# Back leaves the page for the list of ways to play, and from there the
	# screen for the main menu.
	ok = ok and _press(select, "BackButton")
	ok = ok and select.page() == &"menu" and not (select.find_child("VersusOptionsBoxContainer", true, false) as Control).visible \
		and _button(select, "PveButton").visible and _button(select, "SoloButton").visible
	ok = ok and stub.loaded_paths.is_empty() and not session.is_versus()
	ok = ok and _press(select, "BackButton")
	ok = ok and stub.loaded_paths.size() == 1 and stub.loaded_paths[0] == MaaacksGameTemplate.get_main_menu_path()
	await _free(select)
	_case(ctx, "back_leaves_page_then_outermost_returns_to_main_menu", ok)


static func _case_start_versus_resets_progress(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var session = _session()
	# A previous match left a 3:1 lead in round 4.
	session.start_versus(session.VERSUS_RULES_FIXED, 4, session.VERSUS_FORMAT_BEST_OF_3)
	session.save_versus_progress([3, 1], 4)
	var ok: bool = _wins_are(session, 3, 1) and int(session.versus_round_index) == 4
	ok = ok and _press(select, "VersusButton") and _press(select, "VersusStartButton")
	ok = ok and _wins_are(session, 0, 0) and int(session.versus_round_index) == 1
	ok = ok and session.versus_match_in_progress == true and session.mode == session.MODE_VERSUS
	await _free(select)
	session.start_mode(session.MODE_NONE)
	_case(ctx, "start_versus_resets_round_wins_and_index", ok)


static func _case_page_focus_and_description_follow_the_option(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var ok: bool = _press(select, "VersusButton")
	await _tree().process_frame
	await _tree().process_frame
	var viewport: Viewport = select.get_viewport()
	# Opening the page lands on Start Match: Enter starts with the shown setup.
	ok = ok and viewport.gui_get_focus_owner() == _button(select, "VersusStartButton")
	var description: Label = select.find_child("VersusDescription", true, false) as Label
	ok = ok and description != null and description.text == select.tr("VERSUS_DESC_START")
	_button(select, "VersusCPULunatic").grab_focus()
	ok = ok and description.text == select.tr("VERSUS_DESC_LUNATIC") and description.text != "VERSUS_DESC_LUNATIC"
	_button(select, "VersusLevel6").grab_focus()
	ok = ok and description.text.contains("6") and not description.text.contains("%d")
	await _free(select)
	_case(ctx, "page_focus_starts_on_start_and_description_follows_focus", ok)


static func _case_choices_are_remembered(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var session = _session()
	var ok: bool = _press(select, "VersusButton")
	ok = ok and _press(select, "VersusSpeedFixedSpeed") and _press(select, "VersusLevel5") and _press(select, "VersusCPULunatic") and _press(select, "VersusMatchBestof3")
	ok = ok and _press(select, "VersusStartButton")
	await _free(select)
	# A new visit (and a new session of the game) opens on the same setup.
	var again = await _spawn_mode_select(false)
	ok = ok and again._versus_level == 5 and again._versus_difficulty == &"lunatic" and again._versus_format == &"best_of_3"
	ok = ok and _press(again, "VersusButton")
	ok = ok and _button(again, "VersusLevel5").button_pressed and _button(again, "VersusCPULunatic").button_pressed \
		and _button(again, "VersusMatchBestof3").button_pressed
	await _free(again)
	_forget_choices()
	session.start_mode(session.MODE_NONE)
	_case(ctx, "choices_are_remembered_across_visits", ok)


static func _case_change_settings_reopens_the_page(ctx: Dictionary) -> void:
	var session = _session()
	session.open_versus_setup = true
	var select = await _spawn_mode_select()
	await _tree().process_frame
	var ok: bool = (select.find_child("VersusOptionsBoxContainer", true, false) as Control).visible
	ok = ok and session.open_versus_setup == false
	await _free(select)
	_case(ctx, "change_settings_flag_opens_straight_on_the_page", ok)


## The two CPU pages. Versus CPU never puts a CPU on the left board; CPU
## Battle shows both CPU cards and its left tier is stored, sent to the
## session and remembered.
static func _case_left_cpu_choice_reaches_session_and_is_remembered(ctx: Dictionary) -> void:
	var select = await _spawn_mode_select()
	var session = _session()
	session.start_mode(session.MODE_NONE)
	var ok: bool = _button(select, "VersusPlayerYou") == null
	ok = ok and _press(select, "VersusStartButton") and session.versus_left_difficulty == &"" and session.versus_lan == &""
	await _free(select)
	select = await _spawn_mode_select(true, &"eve")
	ok = ok and select.page() == &"eve" and (select.find_child("LeftCard", true, false) as Control).visible \
		and (select.find_child("RightCard", true, false) as Control).visible \
		and (select.find_child("RightTitle", true, false) as Label).text == "CPU 2"
	ok = ok and _button(select, "VersusPlayerNormal").button_pressed
	ok = ok and _press(select, "VersusPlayerHard") and _press(select, "VersusCPUEasy")
	ok = ok and _button(select, "VersusPlayerHard").button_pressed and not _button(select, "VersusPlayerNormal").button_pressed
	# The two tier rows are independent groups.
	ok = ok and _button(select, "VersusCPUEasy").button_pressed
	ok = ok and _press(select, "VersusStartButton")
	ok = ok and session.versus_left_difficulty == &"hard" and session.versus_difficulty == &"easy"
	await _free(select)
	var again = await _spawn_mode_select(false, &"eve")
	ok = ok and again._versus_left == &"hard" and _button(again, "VersusPlayerHard").button_pressed
	await _free(again)
	_forget_choices()
	# Leaving versus clears the left-board AI again.
	session.start_mode(session.MODE_NONE)
	session.versus_page = &"pve"
	ok = ok and session.versus_left_difficulty == &""
	_case(ctx, "left_cpu_choice_reaches_session_and_is_remembered", ok)


## CPU vs CPU scene: both boards are AI-driven, the keyboard does not move the
## left piece, both sides are tagged as CPUs and the match plays out alone.
static func _case_cpu_vs_cpu_scene_plays_itself(ctx: Dictionary) -> void:
	var session = _session()
	session.start_versus(session.VERSUS_RULES_FIXED, 5, session.VERSUS_FORMAT_SINGLE, &"easy", &"lunatic")
	var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	await _tree().process_frame
	var model: VersusBattle = scene._model
	var ok: bool = scene._left_ai != null and scene._left_ai.profile() == VersusAI.DIFFICULTY_PROFILES[&"lunatic"]
	ok = ok and scene._ai.profile() == VersusAI.DIFFICULTY_PROFILES[&"easy"]
	var left_tag: Label = scene.find_child("PlayerTag", true, false) as Label
	var right_tag: Label = scene.find_child("AITag", true, false) as Label
	var left_tier: Label = scene.find_child("PlayerDifficultyLabel", true, false) as Label
	ok = ok and left_tag != null and left_tag.text == "CPU 1" and right_tag != null and right_tag.text == "CPU 2"
	ok = ok and left_tier != null and left_tier.text == "LUNATIC"
	ok = ok and (scene.find_child("AIDifficultyLabel", true, false) as Label).text == "EASY"
	# The keyboard does not reach the left board.
	model.tick(scene.COUNTDOWN_SECONDS + 0.1)
	Input.action_press("hard_drop")
	await _tree().process_frame
	Input.action_release("hard_drop")
	ok = ok and model.pieces_placed(SIDE_PLAYER) == 0
	# Both AIs play on their own (stepped by hand so the case is not real-time).
	for i: int in 30 * 20:
		if model.phase() != VersusBattle.Phase.PLAYING:
			break
		model.tick(1.0 / 30.0)
		scene._left_ai.tick(1.0 / 30.0)
		scene._ai.tick(1.0 / 30.0)
	ok = ok and model.pieces_placed(SIDE_PLAYER) >= 10 and model.pieces_placed(SIDE_AI) >= 3
	ok = ok and model.pieces_placed(SIDE_PLAYER) > model.pieces_placed(SIDE_AI)
	# The result names the winning CPU, not "the player".
	model.debug_force_piece(SIDE_AI, Tetromino.PieceType.O, 0, Vector2i(4, 0), false, -1)
	model.debug_lock_now(SIDE_AI, false)
	await _tree().process_frame
	if model.phase() == VersusBattle.Phase.MATCH_OVER:
		ok = ok and scene._overlay_title.text == scene.tr("CPU %d WINS MATCH") % (model.match_winner() + 1)
	else:
		ok = false
	# Rematch keeps it CPU vs CPU.
	scene._on_rematch_pressed()
	ok = ok and scene._left_ai != null and scene._model != model
	scene.free()
	await _tree().process_frame
	session.start_mode(session.MODE_NONE)
	_case(ctx, "cpu_vs_cpu_scene_plays_itself_and_ignores_the_keyboard", ok)


static func _case_versus_scene_reads_session_and_starts_at_0_0(ctx: Dictionary) -> void:
	var session = _session()
	session.start_versus(session.VERSUS_RULES_RISING, 1, session.VERSUS_FORMAT_BEST_OF_3, &"hard")
	# Stale progress (a pause-menu Restart reloads the scene mid-match): the
	# match restarts from 0:0 instead of replaying the current round.
	session.save_versus_progress([1, 1], 3)
	var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	await _tree().process_frame
	var model: VersusBattle = scene._model
	var ok: bool = model.rules() == VersusBattle.Rules.RISING and model.match_format() == VersusBattle.MatchFormat.BEST_OF_3
	ok = ok and model.round_wins(SIDE_PLAYER) == 0 and model.round_wins(SIDE_AI) == 0 and model.round_index() == 1
	ok = ok and _wins_are(session, 0, 0) and int(session.versus_round_index) == 1
	ok = ok and scene._ai.profile() == VersusAI.DIFFICULTY_PROFILES[&"hard"]
	var tag: Label = scene.find_child("AIDifficultyLabel", true, false) as Label
	ok = ok and tag != null and tag.text == "HARD" and tag.is_visible_in_tree()
	ok = ok and model.phase() == VersusBattle.Phase.COUNTDOWN
	# R is not a versus key any more: it must not restart the round.
	model.tick(scene.COUNTDOWN_SECONDS + 0.1)
	model.debug_force_piece(SIDE_PLAYER, Tetromino.PieceType.O, 0, Vector2i(0, 22), false, -1)
	model.debug_lock_now(SIDE_PLAYER, false)
	Input.action_press("restart")
	await _tree().process_frame
	Input.action_release("restart")
	await _tree().process_frame
	ok = ok and model.pieces_placed(SIDE_PLAYER) == 1 and scene._model == model
	scene.free()
	await _tree().process_frame
	session.start_mode(session.MODE_NONE)
	_case(ctx, "versus_scene_reads_session_starts_0_0_and_ignores_r", ok)
