extends SceneTree

const MODULE_NAME: String = "pause_menu"

# O-08 machine assertions (WP-pause-1): the in-game pause flow is the archived
# Maaack template pause menu copied to scenes/windows/ (provenance recorded in
# docs/vendor/maaack-game-template.json). Game freezing stays on the existing
# main.gd `_paused` mechanism (BS-07: one mechanism); the template scene's
# pauses_game export is adapted to false for that choice and recorded as a
# vendor modification. All cases are headless and repeatable; no persistent
# state (config file, input map) is touched.
const VENDOR_RECORD_PATH: String = "res://docs/vendor/maaack-game-template.json"
const PAUSE_MENU_SCENE_PATH: String = "res://scenes/windows/pause_menu.tscn"
const PAUSE_MENU_GD_PATH: String = "res://scenes/windows/pause_menu.gd"
const PAUSE_MENU_UID_PATH: String = "res://scenes/windows/pause_menu.gd.uid"
const PAUSE_OPTIONS_WINDOW_PATH: String = "res://scenes/windows/pause_menu_options_window.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const VENDOR_COPIES: Array[String] = [
	PAUSE_MENU_SCENE_PATH,
	PAUSE_MENU_GD_PATH,
	PAUSE_MENU_UID_PATH,
	PAUSE_OPTIONS_WINDOW_PATH,
]
const SETTLE_FRAMES: int = 3
const FREEZE_FRAMES: int = 30
const RESUME_FRAMES: int = 90
const RELOAD_POLL_FRAMES: int = 240


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d pause_menu cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("PAUSE MENU TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var session_mode: Variant = _snapshot_session_mode()
	await _case_scene_is_archived_template_copy(ctx)
	await _case_buttons_present_and_wired(ctx)
	await _case_pause_freezes_and_resume_restores_state(ctx)
	await _case_restart_resets_match(ctx)
	await _case_main_menu_button_switches_scene(ctx)
	_restore_session_mode(session_mode)
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


static func _game_session():
	return _tree().root.get_node_or_null(^"GameSession")


static func _snapshot_session_mode() -> Variant:
	var session = _game_session()
	if session == null:
		return null
	return session.mode


static func _restore_session_mode(saved: Variant) -> void:
	var session = _game_session()
	if session != null and saved != null:
		session.start_mode(saved)


static func _poll_until(frames: int, condition: Callable) -> bool:
	var tree: SceneTree = _tree()
	for i: int in frames:
		await tree.process_frame
		if condition.call():
			return true
	return bool(condition.call())


static func _spawn_main_in_tree() -> Node2D:
	var tree: SceneTree = _tree()
	await tree.process_frame
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	tree.root.add_child(main)
	# Engine _process off: gameplay is driven by manual fixed-delta steps so a
	# programmatic action press is seen by exactly one _process call (the
	# engine's own callback would see the same just_pressed again in-frame).
	main.set_process(false)
	await tree.process_frame
	return main


static func _spawn_pause_menu_hidden() -> PopupWindowPanel:
	var packed: PackedScene = load(PAUSE_MENU_SCENE_PATH) as PackedScene
	if packed == null or not packed.can_instantiate():
		return null
	var menu: PopupWindowPanel = packed.instantiate() as PopupWindowPanel
	if menu == null:
		return null
	menu.visible = false
	_tree().root.add_child(menu)
	await _tree().process_frame
	return menu


static func _press_and_process(main: Node2D, action: String) -> void:
	await _tree().process_frame
	Input.action_press(action)
	main._process(0.016)
	Input.action_release(action)
	await _tree().process_frame


static func _step(main: Node2D, frames: int) -> void:
	# Manual fixed-delta steps (test_play_flow convention): headless engine
	# frame deltas are not deterministic, gameplay timing must be.
	for i: int in frames:
		main._process(0.016)


static func _count_locked(board: Board) -> int:
	var count: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) != Board.EMPTY:
				count += 1
	return count


static func _has_connected_method(sender: Object, signal_name: String, expected: String) -> bool:
	if sender == null or not sender.has_signal(signal_name):
		return false
	for connection: Dictionary in sender.get_signal_connection_list(signal_name):
		var callable: Callable = connection["callable"]
		if callable.get_method() == StringName(expected):
			return true
	return false


static func _vendor_entry(records: Variant, project_path: String) -> Dictionary:
	if typeof(records) != TYPE_ARRAY:
		return {}
	# Vendor records store project-relative paths (no res:// prefix).
	var wanted: String = project_path.trim_prefix("res://")
	for entry: Variant in records:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String((entry as Dictionary).get("path", "")) == wanted:
			return entry
	return {}


static func _case_scene_is_archived_template_copy(ctx: Dictionary) -> void:
	var ok: bool = FileAccess.file_exists(VENDOR_RECORD_PATH)
	var parsed: Variant = null
	if ok:
		parsed = JSON.parse_string(FileAccess.get_file_as_string(VENDOR_RECORD_PATH))
		ok = typeof(parsed) == TYPE_DICTIONARY
	var copies: Variant = null
	if ok:
		copies = (parsed as Dictionary).get("scenes_copies")
		ok = typeof(copies) == TYPE_ARRAY
	# Every copied file must exist on disk with the exact sha256 recorded in
	# the vendor archive entry (source = archived Maaack template copy).
	for project_path: String in VENDOR_COPIES:
		if not ok:
			break
		ok = FileAccess.file_exists(project_path)
		var entry: Dictionary = _vendor_entry(copies, project_path)
		ok = ok and not entry.is_empty()
		if entry.is_empty():
			continue
		ok = ok and String(entry.get("upstream_path", "")) == project_path.trim_prefix("res://")
		var recorded: String = String(entry.get("copied_sha256", "")).to_lower()
		ok = ok and recorded.length() == 64
		ok = ok and FileAccess.get_sha256(project_path).to_lower() == recorded
	# The script and the options window are byte-identical template copies;
	# the scene carries the single recorded pauses_game adaptation.
	var script_entry: Dictionary = _vendor_entry(copies, PAUSE_MENU_GD_PATH)
	ok = ok and bool(script_entry.get("identical", false))
	var uid_entry: Dictionary = _vendor_entry(copies, PAUSE_MENU_UID_PATH)
	ok = ok and bool(uid_entry.get("identical", false))
	var options_entry: Dictionary = _vendor_entry(copies, PAUSE_OPTIONS_WINDOW_PATH)
	ok = ok and bool(options_entry.get("identical", false))
	var scene_entry: Dictionary = _vendor_entry(copies, PAUSE_MENU_SCENE_PATH)
	ok = ok and not bool(scene_entry.get("identical", true))
	var edits_text: String = "; ".join((scene_entry.get("edits", []) as Array).map(func(item: Variant) -> String: return String(item)))
	ok = ok and edits_text.contains("pauses_game")
	# The scene keeps the template inheritance: root script is the copied
	# pause_menu.gd extending the template PopupWindowPanel.
	var packed: PackedScene = load(PAUSE_MENU_SCENE_PATH) as PackedScene
	ok = ok and packed != null and packed.can_instantiate()
	var menu: PopupWindowPanel = null
	if packed != null:
		menu = packed.instantiate() as PopupWindowPanel
	ok = ok and menu is PopupWindowPanel
	if menu != null:
		var script: Script = menu.get_script()
		ok = ok and script != null and script.resource_path == PAUSE_MENU_GD_PATH
		menu.free()
	_case(ctx, "scene_is_archived_template_copy", ok)


static func _case_buttons_present_and_wired(ctx: Dictionary) -> void:
	var ok: bool = true
	var menu: PopupWindowPanel = await _spawn_pause_menu_hidden()
	ok = ok and menu != null
	# Template buttons: Resume (= template CloseButton), Restart, Options,
	# Main Menu, Exit, plus the three confirmation popups.
	var restart_button: Button = null
	var options_button: Button = null
	var main_menu_button: Button = null
	var exit_button: Button = null
	if menu != null:
		restart_button = menu.find_child("RestartButton", true, false) as Button
		options_button = menu.get_node_or_null(^"%OptionsButton") as Button
		main_menu_button = menu.get_node_or_null(^"%MainMenuButton") as Button
		exit_button = menu.get_node_or_null(^"%ExitButton") as Button
		ok = ok and menu.get_node_or_null(^"%CloseButton") is Button
		ok = ok and menu.restart_confirmation != null
		ok = ok and menu.main_menu_confirmation != null
		ok = ok and menu.exit_confirmation != null
	ok = ok and restart_button != null and options_button != null
	ok = ok and main_menu_button != null and exit_button != null
	# Button -> template handler wiring.
	ok = ok and _has_connected_method(restart_button, "pressed", "_on_restart_button_pressed")
	ok = ok and _has_connected_method(options_button, "pressed", "_on_options_button_pressed")
	ok = ok and _has_connected_method(main_menu_button, "pressed", "_on_main_menu_button_pressed")
	ok = ok and _has_connected_method(exit_button, "pressed", "_on_exit_button_pressed")
	if menu != null:
		ok = ok and _has_connected_method(menu.close_button, "pressed", "_on_close_button_pressed")
		ok = ok and _has_connected_method(menu.restart_confirmation, "confirmed", "_on_restart_confirmation_confirmed")
		ok = ok and _has_connected_method(menu.main_menu_confirmation, "confirmed", "_on_main_menu_confirmation_confirmed")
		# Options opens the vendored template options window; Main Menu
		# resolves the project main menu through the template project setting.
		var options_scene: PackedScene = menu.options_menu_scene
		ok = ok and options_scene != null and options_scene.resource_path == PAUSE_OPTIONS_WINDOW_PATH
		ok = ok and menu.get_main_menu_scene_path() == MAIN_MENU_PATH
		# Recorded adaptation: freezing is owned by the game's _paused flag.
		ok = ok and menu.pauses_game == false
	# Game-side wiring: the game scene instantiates the menu and resumes when
	# the menu reports closed.
	var main: Node2D = await _spawn_main_in_tree()
	ok = ok and main != null and main._pause_menu is PopupWindowPanel
	if main != null and main._pause_menu != null:
		ok = ok and main._pause_menu.get_script().resource_path == PAUSE_MENU_GD_PATH
		ok = ok and not main._pause_menu.visible
		ok = ok and _has_connected_method(main._pause_menu, "closed", "_on_pause_menu_closed")
	if menu != null:
		menu.free()
	if main != null:
		main.free()
	_case(ctx, "buttons_present_and_wired", ok)


static func _case_pause_freezes_and_resume_restores_state(ctx: Dictionary) -> void:
	var session = _game_session()
	if session != null:
		session.start_mode(session.MODE_NONE)
	var main: Node2D = await _spawn_main_in_tree()
	var ok: bool = main != null
	# Dirty, observable state: a locked piece plus a mid-air active piece.
	if main != null:
		main._piece = Tetromino.new(Tetromino.PieceType.T)
		main._piece_pos = Vector2i(3, 5)
		await _press_and_process(main, "hard_drop")
		main._piece = Tetromino.new(Tetromino.PieceType.T)
		main._piece_pos = Vector2i(5, 8)
		ok = ok and main._score > 0 and _count_locked(main._board) >= 4
	# Pause through the frozen "pause" action path.
	if ok:
		await _press_and_process(main, "pause")
		ok = ok and main._paused and main._pause_menu.visible
	var piece_at_pause: Vector2i = main._piece_pos if main != null else Vector2i.ZERO
	var score_at_pause: int = main._score if main != null else -1
	var level_at_pause: int = main._level if main != null else -1
	var hold_at_pause: int = main._hold_type if main != null else -2
	var next_at_pause: Array = (main._next_queue.duplicate() if main != null else [])
	var locked_at_pause: int = _count_locked(main._board) if main != null else -1
	# While paused the game logic must not advance.
	_step(main, FREEZE_FRAMES)
	var frozen: bool = main != null \
		and main._piece_pos == piece_at_pause \
		and main._score == score_at_pause \
		and main._level == level_at_pause \
		and _count_locked(main._board) == locked_at_pause
	# Resume through the pause menu's Resume button (template CloseButton).
	if main != null and main._pause_menu != null:
		(main._pause_menu.close_button as Button).pressed.emit()
	var resumed: bool = await _poll_until(10, func() -> bool:
		return main != null and not main._paused and not main._pause_menu.visible)
	# After resume: score/board/level/Hold/Next identical; only gravity
	# continues (the active piece moves again).
	_step(main, RESUME_FRAMES)
	await _tree().process_frame
	var restored: bool = main != null \
		and main._score == score_at_pause \
		and main._level == level_at_pause \
		and main._hold_type == hold_at_pause \
		and main._next_queue == next_at_pause \
		and _count_locked(main._board) == locked_at_pause
	var gravity_back: bool = main != null and main._piece != null and main._piece_pos.y > piece_at_pause.y
	if main != null:
		main.free()
	_case(ctx, "pause_freezes_and_resume_restores_state", ok and frozen and resumed and restored and gravity_back)


static func _case_restart_resets_match(ctx: Dictionary) -> void:
	var session = _game_session()
	if session != null:
		session.start_mode(session.MODE_NONE)
	var tree: SceneTree = _tree()
	var main: Node2D = await _spawn_main_in_tree()
	var ok: bool = main != null
	if ok:
		tree.current_scene = main
		main._piece = Tetromino.new(Tetromino.PieceType.T)
		main._piece_pos = Vector2i(3, 5)
		await _press_and_process(main, "hard_drop")
		main._piece = Tetromino.new(Tetromino.PieceType.T)
		main._piece_pos = Vector2i(5, 5)
		await _press_and_process(main, "hard_drop")
		ok = ok and main._score > 0 and _count_locked(main._board) >= 8
		await _press_and_process(main, "pause")
		ok = ok and main._paused and main._pause_menu.visible
		# Template restart path: Restart button -> confirmation -> Confirm.
		# One frame between the two clicks: the template's draw-synchronized
		# reload needs the confirmation popup machinery to run as in real use
		# (both clicks never land in the same frame for a human).
		main._pause_menu._on_restart_button_pressed()
		await _tree().process_frame
		ok = ok and main._pause_menu.restart_confirmation.visible
		main._pause_menu.restart_confirmation.confirm()
	var main_id: int = main.get_instance_id() if main != null else 0
	# The template confirmation closes into reload_current_scene: the game
	# scene is re-entered and the match starts over.
	var reloaded: bool = await _poll_until(RELOAD_POLL_FRAMES, func() -> bool:
		return not is_instance_valid(instance_from_id(main_id)) \
			and tree.current_scene != null \
			and tree.current_scene.scene_file_path == MAIN_SCENE_PATH)
	var fresh: Node = tree.current_scene
	ok = ok and reloaded and fresh != null
	ok = ok and fresh != null and fresh.scene_file_path == MAIN_SCENE_PATH
	if fresh != null:
		ok = ok and fresh._score == 0 and fresh._lines == 0 and fresh._level == 1 \
			and _count_locked(fresh._board) == 0 \
			and not fresh._paused and not fresh._game_over \
			and fresh._piece != null
	_case(ctx, "restart_resets_match", ok)


static func _case_main_menu_button_switches_scene(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var main: Node = tree.current_scene
	var ok: bool = main != null and main.scene_file_path == MAIN_SCENE_PATH
	# Open the pause menu through the pause action, then leave through the
	# template Main Menu confirmation.
	if ok:
		main.set_process(false)
		await _press_and_process(main, "pause")
		ok = ok and main._paused and main._pause_menu.visible
		(main._pause_menu.main_menu_button as Button).pressed.emit()
		await _tree().process_frame
		ok = ok and main._pause_menu.main_menu_confirmation.visible
		main._pause_menu.main_menu_confirmation.confirm()
	var main_id: int = main.get_instance_id() if main != null else 0
	var switched: bool = await _poll_until(RELOAD_POLL_FRAMES, func() -> bool:
		return not is_instance_valid(instance_from_id(main_id)) \
			and tree.current_scene != null \
			and tree.current_scene.scene_file_path == MAIN_MENU_PATH)
	ok = ok and switched
	# Cleanup: leave the tree as it was found (no current scene in module runs).
	if switched and tree.current_scene != null:
		var menu_scene: Node = tree.current_scene
		tree.current_scene = null
		menu_scene.free()
	_case(ctx, "main_menu_button_switches_scene", ok)
