extends SceneTree

const MODULE_NAME: String = "ui_fix"

# ui-fx-hud-fix machine assertions (owner feedback 2026-09-17):
#  (1) hard-drop landing sparks anchor on the landed piece's world cell (the
#      old anchor ignored the piece's board x offset) and are parented to the
#      board view so they follow the shake;
#  (2) the menu Intro no longer holds the buttons invisible and locked for
#      2.4 s (reported as slow loading) - entry is interactive almost at once;
#  (3) hover and keyboard/joypad focus land on the same button through the
#      project-authored UIPointerFocus autoload;
#  (4) the HUD readout rail sits inside the green GameArea border from
#      scenes/main.tscn at all three 16:9 window sizes;
#  (5) entering the game through the menu flow shows no marinho overlay (the
#      pure-red vignette entry pulse read as an unexplained red frame);
#  (6) both pause-menu exit paths are distinguishable and wired to quit.
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const MENU_SCENE_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const MODE_SELECT_SCENE_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const PAUSE_MENU_SCENE_PATH: String = "res://scenes/windows/pause_menu.tscn"
const TEMPLATE_MAIN_MENU_GD: String = "res://addons/maaacks_game_template/base/nodes/menus/main_menu/main_menu.gd"
const PAUSE_MENU_GD: String = "res://scenes/windows/pause_menu.gd"
const CONFIG_LOCATION: String = "user://player_config.cfg"

const BASE_SIZE: Vector2i = Vector2i(1152, 648)
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1152, 648), Vector2i(1920, 1080)]
const ANCHOR_TOLERANCE_PX: float = 0.5
const CONTAIN_TOLERANCE_PX: float = 1.0
const INTRO_MAX_SECONDS: float = 0.35
const INTERACTIVE_BUDGET_MS: int = 500
const ENTRY_SAMPLE_FRAMES: int = 60

static var _window_protection: Dictionary = {}


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d ui_fix cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("UI FIX TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var tree: SceneTree = _tree()
	tree.root.size = BASE_SIZE
	await tree.process_frame
	await _case_hard_drop_landing_sparks_anchor_matches_landed_cell(ctx)
	await _case_menu_entry_is_immediately_interactive(ctx)
	await _case_hover_focuses_button(ctx)
	await _case_hud_readouts_inside_game_area_all_sizes(ctx)
	await _case_game_entry_has_no_border_overlay(ctx)
	await _case_exit_confirmations_wired_to_quit(ctx)
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


static func _spawn_main():
	var tree: SceneTree = _tree()
	await tree.process_frame
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	tree.root.add_child(main)
	await tree.process_frame
	return main


static func _game_area_rect(main) -> Rect2:
	# Derives the green GameArea rectangle from the scene node itself (its
	# position plus the AreaFill polygon bounds); nothing is hardcoded.
	var area: Node2D = main.get_node_or_null(^"GameArea") as Node2D
	if area == null:
		return Rect2()
	var fill: Polygon2D = area.get_node_or_null(^"AreaFill") as Polygon2D
	if fill == null or fill.polygon.is_empty():
		return Rect2()
	var min_point: Vector2 = Vector2(INF, INF)
	var max_point: Vector2 = Vector2(-INF, -INF)
	for point: Vector2 in fill.polygon:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	return Rect2(area.position + min_point, max_point - min_point)


static func _digit_union_local(display: Variant) -> Variant:
	if display == null:
		return null
	var obj: Object = display
	var segments: Variant = obj.get("_segments")
	var parent: Variant = obj.get("_parent")
	if typeof(segments) != TYPE_ARRAY or (segments as Array).is_empty():
		return null
	if not (parent is Control):
		return null
	var union: Variant = null
	for seg: Variant in (segments as Array):
		if not (seg is Polygon2D):
			return null
		var poly: Polygon2D = seg
		if poly.get_parent() != parent:
			return null
		var poly_min: Vector2 = Vector2.ZERO
		var poly_max: Vector2 = Vector2.ZERO
		for p: Vector2 in poly.polygon:
			poly_min = poly_min.min(p)
			poly_max = poly_max.max(p)
		var rect: Rect2 = Rect2(poly.position + poly_min, poly_max - poly_min)
		union = rect if union == null else (union as Rect2).merge(rect)
	return union


static func _digit_unions_global(main) -> Variant:
	var labels: Variant = main.get("_data_labels")
	var displays: Array = [main.get("_score_display"), main.get("_lines_display"), main.get("_level_display")]
	if typeof(labels) != TYPE_ARRAY or (labels as Array).size() != 3:
		return null
	var result: Array = []
	for i: int in range(3):
		var local: Variant = _digit_union_local(displays[i])
		if local == null:
			return null
		var label_rect: Rect2 = (labels as Array)[i]
		result.append(Rect2(label_rect.position + (local as Rect2).position, (local as Rect2).size))
	return result


static func _has_connected_method(sender: Object, signal_name: String, expected: String) -> bool:
	if sender == null or not sender.has_signal(signal_name):
		return false
	for connection: Dictionary in sender.get_signal_connection_list(signal_name):
		var callable: Callable = connection["callable"]
		if callable.get_method() == StringName(expected):
			return true
	return false


static func _function_body(text: String, func_name: String) -> String:
	var start: int = text.find("func %s(" % func_name)
	if start < 0:
		return ""
	var next: int = text.find("\nfunc ", start + 1)
	var end_pos: int = next if next > 0 else text.length()
	return text.substr(start, end_pos - start)


static func _find_visible_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button:
		var button: Button = node
		if button.is_visible_in_tree() and not button.disabled \
				and button.focus_mode != Control.FOCUS_NONE:
			return button
	for child: Node in node.get_children():
		var found: Button = _find_visible_button(child)
		if found != null:
			return found
	return null


static func _effective_alpha(node: Node) -> float:
	# CanvasItem modulate is relative to its parent, so the alpha a player
	# actually sees is the product along the ancestor chain. The Intro
	# animation drives MenuButtonsContainer (the parent of the box container),
	# so a node-local modulate check would be vacuous.
	var alpha: float = 1.0
	var current: Node = node
	while current != null:
		if current is CanvasItem:
			alpha *= (current as CanvasItem).modulate.a
		current = current.get_parent()
	return alpha


static func _case_hard_drop_landing_sparks_anchor_matches_landed_cell(ctx: Dictionary) -> void:
	# Revised 2026-10-10: the hard-drop feedback is BoardFX's trail + sparks
	# (the marinho spark burst is retired). The trail must sit on exactly the
	# columns of the landed piece and end on its top cells, and the effect
	# node must ride the board view so it follows the shake.
	var main = await _spawn_main()
	var ok: bool = main != null
	if main != null:
		main._piece = Tetromino.new(Tetromino.PieceType.T)
		main._piece_pos = Vector2i(6, 15)
		await _tree().process_frame
		Input.action_press("hard_drop")
		main._process(0.016)
		Input.action_release("hard_drop")
		# The T (flat, nub up) lands on the floor: columns 6..8.
		var columns: Dictionary = {}
		for trail: Dictionary in main._fx._trails:
			columns[int(trail["col"])] = int(trail["bottom"])
		ok = ok and columns.size() == 3 and columns.has(6) and columns.has(7) and columns.has(8)
		ok = ok and int(columns.get(7, -1)) == Board.VISIBLE_HEIGHT - 2
		ok = ok and int(columns.get(6, -1)) == Board.VISIBLE_HEIGHT - 1
		ok = ok and not main._fx._particles.is_empty()
		ok = ok and main._fx.get_parent() == main._view
		ok = ok and main._fx.position.distance_to(main._board_origin) <= ANCHOR_TOLERANCE_PX
	main.free()
	_case(ctx, "hard_drop_landing_sparks_anchor_matches_landed_cell", ok)


static func _case_menu_entry_is_immediately_interactive(ctx: Dictionary) -> void:
	_protect_window_and_config()
	var tree: SceneTree = _tree()
	var ok: bool = true
	for scene_path: String in [MENU_SCENE_PATH, MODE_SELECT_SCENE_PATH]:
		var packed: PackedScene = load(scene_path) as PackedScene
		ok = ok and packed != null
		if packed == null:
			continue
		var menu: Control = packed.instantiate() as Control
		ok = ok and menu != null
		if menu == null:
			continue
		var player: AnimationPlayer = menu.find_child("MenuAnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation("Intro"):
			ok = ok and player.get_animation("Intro").length <= INTRO_MAX_SECONDS
		else:
			ok = false
		tree.root.add_child(menu)
		var container: Control = menu.find_child("MenuButtonsBoxContainer", true, false) as Control
		ok = ok and container != null and container is BoxContainer
		if container != null:
			var deadline: int = Time.get_ticks_msec() + INTERACTIVE_BUDGET_MS
			while Time.get_ticks_msec() < deadline:
				var lock_value: Variant = container.get("lock")
				if _effective_alpha(container) >= 0.99 and lock_value != null and not bool(lock_value):
					break
				await tree.process_frame
			var final_lock: Variant = container.get("lock")
			ok = ok and _effective_alpha(container) >= 0.99
			ok = ok and final_lock != null and not bool(final_lock)
		menu.free()
	_restore_window_and_config()
	_case(ctx, "menu_entry_is_immediately_interactive", ok)


static func _case_hover_focuses_button(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var ok: bool = tree.root.get_node_or_null(^"UIPointerFocus") != null
	_protect_window_and_config()
	var menu: Control = null
	if ok:
		menu = (load(MENU_SCENE_PATH) as PackedScene).instantiate() as Control
		ok = ok and menu != null
		if menu != null:
			tree.root.add_child(menu)
			for i: int in 3:
				await tree.process_frame
	var button: Button = _find_visible_button(menu) if menu != null else null
	ok = ok and button != null
	if button != null:
		button.mouse_entered.emit()
		await tree.process_frame
		ok = ok and button.get_viewport().gui_get_focus_owner() == button
	var fresh: Button = Button.new()
	fresh.text = "Fresh"
	tree.root.add_child(fresh)
	for i: int in 2:
		await tree.process_frame
	fresh.mouse_entered.emit()
	await tree.process_frame
	ok = ok and fresh.get_viewport().gui_get_focus_owner() == fresh
	fresh.free()
	if menu != null:
		menu.free()
	_restore_window_and_config()
	_case(ctx, "hover_focuses_button", ok)


static func _case_hud_readouts_inside_game_area_all_sizes(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var main = await _spawn_main()
	var ok: bool = main != null
	if main != null:
		var game_area: Rect2 = _game_area_rect(main)
		ok = ok and game_area.size.x > 0.0 and game_area.size.y > 0.0
		for size: Vector2i in WINDOW_SIZES:
			tree.root.size = size
			for i: int in 4:
				await tree.process_frame
			var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
			# Revised 2026-10-10 (UI re-layout): the readout blocks carry font
			# labels; their rects are the blocks themselves.
			var labels: Variant = main.get("_data_labels")
			ok = ok and typeof(labels) == TYPE_ARRAY and (labels as Array).size() == 3
			if typeof(labels) == TYPE_ARRAY and (labels as Array).size() == 3:
				for i: int in range(3):
					var block: Rect2 = (labels as Array)[i]
					ok = ok and game_area.grow(CONTAIN_TOLERANCE_PX).encloses(block)
					ok = ok and block.end.x <= main._board_origin.x + CONTAIN_TOLERANCE_PX
					ok = ok and window.encloses(block)
			var hold: Rect2 = main._hold_container.get_global_rect()
			ok = ok and game_area.grow(CONTAIN_TOLERANCE_PX).encloses(hold)
			ok = ok and hold.end.x <= main._board_origin.x + CONTAIN_TOLERANCE_PX
			ok = ok and window.encloses(hold)
		tree.root.size = BASE_SIZE
		await tree.process_frame
	main.free()
	_case(ctx, "hud_readouts_inside_game_area_all_sizes", ok)


static func _case_game_entry_has_no_border_overlay(ctx: Dictionary) -> void:
	var tree: SceneTree = _tree()
	var session: Node = tree.root.get_node_or_null(^"GameSession")
	var ok: bool = session != null
	if ok:
		var previous_mode: StringName = session.mode
		session.start_mode(session.MODE_CLASSIC)
		var main = await _spawn_main()
		ok = ok and main != null
		if main != null:
			ok = ok and not main.has_method("_start_scene_entry_transition")
			# Revised 2026-10-10: the full-screen marinho overlays (vignette /
			# chromatic / camera shake) are gone altogether; entering a match
			# must not start any board effect either.
			ok = ok and main.get("_fx_vignette") == null and main.get("_fx_chromatic") == null \
				and main.get("_fx_camera_shake") == null
			for i: int in ENTRY_SAMPLE_FRAMES:
				await tree.process_frame
				ok = ok and not main._fx.is_active() and main._fx.offset == Vector2.ZERO
			main.free()
		session.start_mode(previous_mode)
	_case(ctx, "game_entry_has_no_border_overlay", ok)


static func _case_exit_confirmations_wired_to_quit(ctx: Dictionary) -> void:
	_protect_window_and_config()
	var tree: SceneTree = _tree()
	var ok: bool = true
	# (a) main menu: its exit confirmation routes to exit_game.
	var packed_menu: PackedScene = load(MENU_SCENE_PATH) as PackedScene
	ok = ok and packed_menu != null
	if packed_menu != null:
		var menu: Control = packed_menu.instantiate() as Control
		ok = ok and menu != null
		if menu != null:
			tree.root.add_child(menu)
			await tree.process_frame
			var exit_conf: Node = menu.get_node_or_null(^"%ExitConfirmation")
			ok = ok and exit_conf != null
			if exit_conf != null:
				ok = ok and _has_connected_method(exit_conf, "confirmed", "_on_exit_confirmation_confirmed")
				# The exit confirmation must not also (or instead) route into a
				# scene load / new game, which is the failure class the owner
				# reported for the main menu.
				ok = ok and not _has_connected_method(exit_conf, "confirmed", "load_game_scene")
				ok = ok and not _has_connected_method(exit_conf, "confirmed", "_on_new_game_confirmation_confirmed")
				ok = ok and not _has_connected_method(exit_conf, "confirmed", "new_game")
			ok = ok and menu.has_method("exit_game")
			menu.free()
	# (b) pause menu: the two exit paths are distinct and exit is wired to quit.
	var packed_pause: PackedScene = load(PAUSE_MENU_SCENE_PATH) as PackedScene
	ok = ok and packed_pause != null
	if packed_pause != null:
		var pause: PopupWindowPanel = packed_pause.instantiate() as PopupWindowPanel
		ok = ok and pause != null
		if pause != null:
			pause.visible = false
			tree.root.add_child(pause)
			await tree.process_frame
			var exit_confirmation: Node = pause.exit_confirmation
			var main_menu_confirmation: Node = pause.main_menu_confirmation
			var restart_confirmation: Node = pause.restart_confirmation
			ok = ok and exit_confirmation != null and main_menu_confirmation != null \
				and restart_confirmation != null
			if exit_confirmation != null:
				ok = ok and _has_connected_method(exit_confirmation, "confirmed", "_on_exit_confirmation_confirmed")
				ok = ok and not _has_connected_method(exit_confirmation, "confirmed", "_on_restart_confirmation_confirmed")
				ok = ok and not _has_connected_method(exit_confirmation, "confirmed", "_on_main_menu_confirmation_confirmed")
			var exit_title: Variant = exit_confirmation.get("title") if exit_confirmation != null else null
			var main_menu_title: Variant = main_menu_confirmation.get("title") if main_menu_confirmation != null else null
			var restart_title: Variant = restart_confirmation.get("title") if restart_confirmation != null else null
			ok = ok and exit_title != null and main_menu_title != null and restart_title != null
			ok = ok and exit_title != main_menu_title
			ok = ok and restart_title != exit_title
			pause.free()
	# (c) source text evidence for the actual quit calls.
	var main_menu_text: String = FileAccess.get_file_as_string(TEMPLATE_MAIN_MENU_GD)
	ok = ok and _function_body(main_menu_text, "exit_game").contains("get_tree().quit()")
	# The confirmed handler must hop to exit_game (not to a scene load); the
	# quit() body check alone would stay green if this hop were repointed.
	var confirmed_body: String = _function_body(main_menu_text, "_on_exit_confirmation_confirmed")
	ok = ok and confirmed_body.contains("exit_game")
	ok = ok and not confirmed_body.contains("load_game_scene")
	ok = ok and not confirmed_body.contains("reload_current_scene")
	var pause_text: String = FileAccess.get_file_as_string(PAUSE_MENU_GD)
	ok = ok and pause_text.contains("_on_exit_confirmation_confirmed")
	ok = ok and pause_text.contains("get_tree().quit()")
	_restore_window_and_config()
	_case(ctx, "exit_confirmations_wired_to_quit", ok)


static func _window_hook_connected() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for connection: Dictionary in tree.root.size_changed.get_connections():
		if (connection["callable"] as Callable).get_method() == "_on_window_size_changed":
			return true
	return false


static func _protect_window_and_config() -> void:
	if not _window_protection.is_empty():
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var config_exists: bool = FileAccess.file_exists(CONFIG_LOCATION)
	_window_protection = {
		"hook_connected": _window_hook_connected(),
		"window_mode": tree.root.mode,
		"window_size": tree.root.size,
		"config_exists": config_exists,
		"config_bytes": FileAccess.get_file_as_bytes(CONFIG_LOCATION) if config_exists else PackedByteArray(),
	}


static func _restore_window_and_config() -> void:
	if _window_protection.is_empty():
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not bool(_window_protection["hook_connected"]):
		for connection: Dictionary in tree.root.size_changed.get_connections():
			var callable: Callable = connection["callable"]
			if callable.get_method() == "_on_window_size_changed":
				tree.root.size_changed.disconnect(callable)
	tree.root.mode = _window_protection["window_mode"]
	tree.root.size = _window_protection["window_size"]
	PlayerConfig.config_file = null
	if bool(_window_protection["config_exists"]):
		var file: FileAccess = FileAccess.open(CONFIG_LOCATION, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_window_protection["config_bytes"])
			file.close()
	elif FileAccess.file_exists(CONFIG_LOCATION):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_LOCATION))
	PlayerConfig.config_file = null
	_window_protection = {}
