extends SceneTree

const MODULE_NAME: String = "pause_keyboard"

# G-PAUSE-KBD-FIX machine assertions (owner report 2026-09-17):
#  (1) the pause menu and its confirmation popups are keyboard-navigable:
#      ui_left/ui_right/ui_up/ui_down keep the built-in arrow/joypad events and
#      append the WASD physical keys (A/D/W/S); opening the pause menu focuses
#      a visible button and a Down-arrow key or S moves that focus;
#  (2) Enter only executes the focused UI action and never restarts the match:
#      restart is R-only (82), Enter on the focused Resume unpauses without
#      touching the dirty match state, the Main Menu confirmation focuses
#      Confirm and Enter confirms it, and R still restarts.
#
# Real key presses are simulated through Viewport.push_input with the same
# keycode/physical split the engine's built-in actions use (arrows/Enter match
# by keycode, the appended WASD events by physical_keycode). A real OS key
# press also runs Input::parse_input_event, which marks every matching InputMap
# action as pressed before the event reaches the viewport; push_input alone
# does not, so the matched action state is mirrored from the live InputMap
# around each push. That mirror is what makes the Enter regression honest:
# while Enter is still bound to restart it presses restart and this test fails.
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const RELOAD_POLL_FRAMES: int = 240
const ARROW_KEYCODES: Dictionary = {
	"ui_left": 4194319,
	"ui_right": 4194321,
	"ui_up": 4194320,
	"ui_down": 4194322,
}
const WASD_PHYSICAL_KEYCODES: Dictionary = {
	"ui_left": 65,
	"ui_right": 68,
	"ui_up": 87,
	"ui_down": 83,
}


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d pause_keyboard cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("PAUSE KEYBOARD TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var session_mode: Variant = _snapshot_session_mode()
	await _case_pause_menu_keyboard_navigation(ctx)
	await _case_enter_executes_selected_action(ctx)
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


static func _spawn_main() -> Node2D:
	var tree: SceneTree = _tree()
	await tree.process_frame
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	if main == null:
		return null
	tree.root.add_child(main)
	await tree.process_frame
	tree.current_scene = main
	await tree.process_frame
	return main


static func _release_main(main: Node) -> void:
	var tree: SceneTree = _tree()
	if tree.current_scene == main:
		tree.current_scene = null
	if is_instance_valid(main):
		main.free()
	await tree.process_frame


static func _press_action(action: String) -> void:
	var tree: SceneTree = _tree()
	Input.action_press(action)
	await tree.process_frame
	Input.action_release(action)
	await tree.process_frame


static func _wait_frames(frames: int) -> void:
	var tree: SceneTree = _tree()
	for i: int in frames:
		await tree.process_frame


static func _mirror_matched_actions(event: InputEventKey) -> Array[StringName]:
	# What Input::parse_input_event does for a real key press: every InputMap
	# action the event matches becomes pressed (the release mirrors later).
	var held: Array[StringName] = []
	for action: StringName in InputMap.get_actions():
		if InputMap.event_is_action(event, action):
			Input.action_press(action)
			held.append(action)
	return held


static func _push_key(keycode: int, physical_keycode: int) -> void:
	var tree: SceneTree = _tree()
	var pressed: InputEventKey = InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = physical_keycode
	pressed.pressed = true
	var held: Array[StringName] = _mirror_matched_actions(pressed)
	tree.root.push_input(pressed)
	await tree.process_frame
	var released: InputEventKey = InputEventKey.new()
	released.keycode = keycode
	released.physical_keycode = physical_keycode
	released.pressed = false
	tree.root.push_input(released)
	for action: StringName in held:
		Input.action_release(action)
	await tree.process_frame
	await tree.process_frame


static func _press_enter() -> void:
	await _push_key(KEY_ENTER, KEY_ENTER)


static func _has_key_event(action: String, keycode: int, physical_keycode: int) -> Array:
	var found: Array = [false, false]
	for event: InputEvent in InputMap.action_get_events(action):
		if not (event is InputEventKey):
			continue
		var key: InputEventKey = event
		if keycode != 0 and int(key.keycode) == keycode:
			found[0] = true
		if physical_keycode != 0 and int(key.physical_keycode) == physical_keycode:
			found[1] = true
	return found


static func _has_joypad_event(action: String) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


static func _direction_actions_are_navigable() -> bool:
	var ok: bool = true
	for action: String in ARROW_KEYCODES:
		ok = ok and InputMap.has_action(action)
		var arrow: Array = _has_key_event(action, int(ARROW_KEYCODES[action]), 0)
		ok = ok and bool(arrow[0])
		var wasd: Array = _has_key_event(action, 0, int(WASD_PHYSICAL_KEYCODES[action]))
		ok = ok and bool(wasd[1])
		ok = ok and _has_joypad_event(action)
	return ok


static func _restart_is_r_only() -> bool:
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	var ok: bool = not InputMap.event_is_action(enter, &"restart")
	ok = ok and InputMap.event_is_action(enter, &"ui_accept")
	var r_only: Array = _has_key_event("restart", 0, KEY_R)
	ok = ok and bool(r_only[1])
	for keycode: int in [KEY_ENTER, KEY_KP_ENTER]:
		var found: Array = _has_key_event("restart", keycode, keycode)
		ok = ok and not bool(found[0]) and not bool(found[1])
	return ok


static func _count_locked(board: Board) -> int:
	var count: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) != Board.EMPTY:
				count += 1
	return count


static func _is_visible_menu_button(menu: Node, control: Control) -> bool:
	if menu == null or control == null:
		return false
	if not (control is Button):
		return false
	if not menu.is_ancestor_of(control):
		return false
	return control.is_visible_in_tree()


static func _poll_until(frames: int, condition: Callable) -> bool:
	var tree: SceneTree = _tree()
	for i: int in frames:
		await tree.process_frame
		if condition.call():
			return true
	return bool(condition.call())


static func _case_pause_menu_keyboard_navigation(ctx: Dictionary) -> void:
	var ok: bool = _direction_actions_are_navigable()
	var tree: SceneTree = _tree()
	var main: Node = null
	if ok:
		main = await _spawn_main()
		ok = main != null
	if main != null:
		var menu: PopupWindowPanel = main._pause_menu
		await _press_action("pause")
		ok = ok and main._paused and menu.visible
		var first_focus: Control = tree.root.gui_get_focus_owner()
		ok = ok and _is_visible_menu_button(menu, first_focus)
		# Down-arrow (ui_down's built-in keycode) moves the focus.
		await _push_key(KEY_DOWN, KEY_DOWN)
		var after_arrow: Control = tree.root.gui_get_focus_owner()
		ok = ok and _is_visible_menu_button(menu, after_arrow)
		ok = ok and after_arrow != first_focus
		# S (ui_down's appended physical key) moves it again.
		await _push_key(KEY_S, KEY_S)
		var after_s: Control = tree.root.gui_get_focus_owner()
		ok = ok and _is_visible_menu_button(menu, after_s)
		ok = ok and after_s != after_arrow
		await _release_main(main)
	_case(ctx, "pause_menu_keyboard_navigation_focuses_buttons", ok)


static func _case_enter_executes_selected_action(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var main: Node2D = await _spawn_main()
	if main == null:
		_case(ctx, "pause_menu_enter_executes_selected_action_without_restart", false)
		return
	var ok: bool = true
	# (a) Dirty, observable match state: one locked piece plus score > 0.
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 5)
	await _press_action("hard_drop")
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(5, 8)
	var score_before: int = main._score
	var locked_before: int = _count_locked(main._board)
	ok = ok and score_before > 0 and locked_before >= 4
	# (b) Paused with Resume focused: Enter resumes, it never restarts.
	await _press_action("pause")
	ok = ok and main._paused and main._pause_menu.visible
	var focus_before: Control = tree.root.gui_get_focus_owner()
	ok = ok and _is_visible_menu_button(main._pause_menu, focus_before)
	await _press_enter()
	ok = ok and not main._paused
	ok = ok and not main._pause_menu.visible
	ok = ok and main._score == score_before
	ok = ok and _count_locked(main._board) == locked_before
	# (c) restart is R-only and Enter is still ui_accept.
	ok = ok and _restart_is_r_only()
	# (d) With no UI focus, Enter has no restart path either.
	var focus_after_resume: Control = tree.root.gui_get_focus_owner()
	if focus_after_resume != null:
		ok = ok and not main._pause_menu.is_ancestor_of(focus_after_resume)
	await _press_enter()
	ok = ok and main._score == score_before
	ok = ok and _count_locked(main._board) == locked_before
	# (e) Revised 2026-10-10: R no longer restarts a running match (it only
	# answers on the game-over screen); the pause menu's Restart is the
	# mid-game path.
	await _press_action("restart")
	await tree.process_frame
	ok = ok and main._score == score_before and _count_locked(main._board) == locked_before
	# (f) Confirmation popups focus Confirm and Enter confirms them. The Main
	# Menu path really switches scenes, so it runs last.
	await _press_action("pause")
	ok = ok and main._paused and main._pause_menu.visible
	var exit_confirmation: ConfirmationPopupWindowPanel = main._pause_menu.exit_confirmation
	(main._pause_menu.exit_button as Button).pressed.emit()
	await _wait_frames(4)
	ok = ok and exit_confirmation.visible
	ok = ok and tree.root.gui_get_focus_owner() == exit_confirmation.confirm_button
	exit_confirmation.close()
	await _wait_frames(2)
	var main_menu_confirmation: ConfirmationPopupWindowPanel = main._pause_menu.main_menu_confirmation
	(main._pause_menu.main_menu_button as Button).grab_focus()
	(main._pause_menu.main_menu_button as Button).pressed.emit()
	await _wait_frames(4)
	ok = ok and main_menu_confirmation.visible
	ok = ok and tree.root.gui_get_focus_owner() == main_menu_confirmation.confirm_button
	var confirmed: Array = []
	main_menu_confirmation.confirmed.connect(func() -> void: confirmed.append(true))
	await _press_enter()
	await _wait_frames(3)
	ok = ok and confirmed.size() == 1
	if is_instance_valid(main_menu_confirmation):
		ok = ok and not main_menu_confirmation.visible
	# The confirmation switches to the archived main menu; poll it out and
	# restore the tree the way test_pause_menu leaves it (no current scene).
	var switched: bool = await _poll_until(RELOAD_POLL_FRAMES, func() -> bool:
		if tree.current_scene == null:
			return false
		return tree.current_scene.scene_file_path == MAIN_MENU_PATH)
	ok = ok and switched
	if switched and tree.current_scene != null:
		var menu_scene: Node = tree.current_scene
		tree.current_scene = null
		menu_scene.free()
		await tree.process_frame
	_case(ctx, "pause_menu_enter_executes_selected_action_without_restart", ok)
