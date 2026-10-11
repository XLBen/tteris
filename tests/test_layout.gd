extends SceneTree

const MODULE_NAME: String = "layout"

# korobeiniki-hud-input freeze (binding record §B, as corrected by CR-01),
# SUPERSEDED for readout placement by the owner decision 2026-09-16 and the
# ui-fx-hud-fix owner feedback 2026-09-17: the readout blocks (labels +
# seven-segment digit unions, one merged block per display) now live in the
# left rail INSIDE the green GameArea border drawn by scenes/main.tscn, with
# HOLD below them and all of them left of the board frame; each display's
# digit-union top-left still equals
# DIGIT_ANCHOR (8, 24) label-locally within a per-axis 2 px tolerance
# (segment-union top-left == SevenSegment origin) and the three digit columns
# align within 1 px; the score growth case asserts window-only containment in
# GLOBAL/canvas space. The game-over veil stays inside the board frame; pause
# is presented by the Maaack pause menu window (WP-pause-1), asserted centered
# inside the canvas window by its own container geometry.
const BASE_SIZE: Vector2i = Vector2i(1152, 648)
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1152, 648), Vector2i(1920, 1080)]
const SPAWN_SETTLE_SECONDS: float = 0.2
const CENTERING_TOLERANCE_PX: float = 2.0
const PANEL_GAP_PX: float = 12.0
const FLOAT_TOL: float = 1.0
const CONTROLS_ALPHA_FLOOR: float = 0.25
const DIGIT_ANCHOR: Vector2 = Vector2(8.0, 24.0)
const DIGIT_ANCHOR_TOLERANCE_PX: float = 2.0
const DIGIT_X_ALIGN_TOLERANCE_PX: float = 1.0


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d layout cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("LAYOUT TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_board_centered_all_three_sizes(ctx)
	await _case_hold_left_next_right_twelve_px_gap(ctx)
	await _case_readout_blocks_left_of_board_frame_all_sizes(ctx)
	await _case_digit_union_anchor_matches_binding_per_display(ctx)
	await _case_digit_union_x_offsets_aligned_within_1px(ctx)
	await _case_data_blocks_no_overlap_hold_next_controls(ctx)
	await _case_data_blocks_pairwise_non_overlapping(ctx)
	await _case_data_and_panels_inside_window_all_sizes(ctx)
	await _case_controls_hidden_or_deemphasized(ctx)
	await _case_veil_labels_contained_and_centered(ctx)
	await _case_score_display_growth_bounded_in_window(ctx)
	await _case_stretch_config_uniform_board_centered_composition(ctx)
	# WP-verify-1 (O-06): the menu-era interfaces under the same three-tier
	# 16:9 contract (implementations appended below).
	await _case_menu_like_scene_contained_all_sizes(ctx, "main_menu_contained_no_overlap_all_sizes", MENU_SCENE_PATH)
	await _case_menu_like_scene_contained_all_sizes(ctx, "mode_select_contained_no_overlap_all_sizes", MODE_SELECT_SCENE_PATH)
	await _case_options_window_contained_no_overlap_all_sizes(ctx)
	await _case_pause_menu_window_contained_all_sizes(ctx)
	# T-09 (O-07): the versus double-board scene and the versus selection steps
	# under the same three-tier 16:9 contract (implementations appended below).
	await _case_versus_scene_contained_all_sizes(ctx)
	await _case_mode_select_versus_level_step_contained_all_sizes(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.size = BASE_SIZE
	await tree.process_frame
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _spawn_main_windowed():
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	tree.root.add_child(main)
	await tree.create_timer(SPAWN_SETTLE_SECONDS).timeout
	return main


static func _at_size(size: Vector2i) -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.size = size
	for i: int in range(4):
		await tree.process_frame
	return float(tree.root.get_final_transform().x.x)


static func _board_rect(main) -> Rect2:
	var size: Vector2 = Vector2(Board.BOARD_WIDTH * main.CELL_SIZE, Board.VISIBLE_HEIGHT * main.CELL_SIZE)
	return Rect2(main._board_origin, size)


static func _game_area_rect(main) -> Rect2:
	# The green GameArea rectangle comes from the scene node (its position plus
	# the AreaFill polygon bounds); no size is hardcoded here.
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


static func _to_px(rect: Rect2, scale: float) -> Rect2:
	return Rect2(rect.position * scale, rect.size * scale)


static func _rect_of_region(value: Variant) -> Variant:
	if value is Control:
		return (value as Control).get_global_rect()
	if value is Array:
		var union: Variant = null
		for element: Variant in value:
			var rect: Variant = _rect_of_region(element)
			if rect == null:
				return null
			if union == null:
				union = rect
			else:
				union = (union as Rect2).merge(rect)
		return union
	if value is Dictionary:
		return _rect_of_region((value as Dictionary).values())
	return null


static func _region_rects(main) -> Dictionary:
	return {
		"board": _board_rect(main),
		"hold": _rect_of_region(main.get("_hold_container")),
		"next": _rect_of_region(main.get("_next_container")),
		"data": main.get("_data_labels"),
		"controls": _rect_of_region(main.get("_controls_label")),
	}


static func _window_ok(rect_px: Rect2, window: Rect2) -> bool:
	return window.encloses(rect_px)


static func _case_board_centered_all_three_sizes(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var ok: bool = true
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var board_px: Rect2 = _to_px(_board_rect(main), scale)
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
		var center: Vector2 = board_px.get_center()
		ok = ok and _window_ok(board_px, window)
		ok = ok and absf(center.x - float(size.x) / 2.0) <= CENTERING_TOLERANCE_PX * scale
		ok = ok and absf(center.y - float(size.y) / 2.0) <= CENTERING_TOLERANCE_PX * scale
	main.free()
	_case(ctx, "board_centered_all_three_sizes", ok)


static func _case_hold_left_next_right_twelve_px_gap(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var ok: bool = true
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var rects: Dictionary = _region_rects(main)
		var hold: Variant = rects["hold"]
		var next: Variant = rects["next"]
		if hold == null or next == null:
			ok = false
			continue
		var hold_px: Rect2 = _to_px(hold, scale)
		var next_px: Rect2 = _to_px(next, scale)
		var board_px: Rect2 = _to_px(_board_rect(main), scale)
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
		ok = ok and _window_ok(hold_px, window) and _window_ok(next_px, window)
		ok = ok and hold_px.end.x + (PANEL_GAP_PX * scale - FLOAT_TOL) <= board_px.position.x
		ok = ok and next_px.position.x >= board_px.end.x + (PANEL_GAP_PX * scale - FLOAT_TOL)
	main.free()
	_case(ctx, "hold_left_next_right_twelve_px_gap", ok)


# Revised 2026-10-10 (owner: re-lay out the UI, decouple the assets): the readouts
# are font labels inside the stats card now (the seven-segment digits are
# gone), so the cases below measure those labels.
static func _value_labels(main) -> Array:
	return [main.get("_score_value"), main.get("_level_value"), main.get("_lines_value")]


static func _readout_block_rects(main) -> Variant:
	var labels: Variant = main.get("_data_labels")
	if typeof(labels) != TYPE_ARRAY or (labels as Array).size() != 3:
		return null
	return labels


static func _case_readout_blocks_left_of_board_frame_all_sizes(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var ok: bool = true
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var board_px: Rect2 = _to_px(_board_rect(main), scale)
		var game_area_px: Rect2 = _to_px(_game_area_rect(main), scale)
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
		var blocks: Variant = _readout_block_rects(main)
		if blocks == null:
			ok = false
			continue
		var values: Array = _value_labels(main)
		for i: int in range(3):
			# Each readout block holds its value label, sits inside the
			# GameArea border and the window, and stays left of the board.
			var block: Rect2 = (blocks as Array)[i]
			ok = ok and values[i] is Label and block.grow(FLOAT_TOL).encloses((values[i] as Label).get_global_rect())
			var block_px: Rect2 = _to_px(block, scale)
			ok = ok and game_area_px.grow(FLOAT_TOL).encloses(block_px)
			ok = ok and window.encloses(block_px)
			ok = ok and block_px.end.x <= board_px.position.x
	main.free()
	_case(ctx, "readout_blocks_left_of_board_frame_all_sizes", ok)


# Revised 2026-10-10 (owner: the UI is laid out by resource-pack scenes): the HUD
# is the pack's "classic_hud" layout. In the stock layout the info card stands
# left of the board, exactly as tall as it and one panel gap away; the NEXT
# card mirrors it on the right, so the board stays centered.
static func _case_digit_union_anchor_matches_binding_per_display(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	await _at_size(BASE_SIZE)
	var board: Rect2 = _board_rect(main)
	var info: Rect2 = (main._hud.find_child("InfoCard", true, false) as Control).get_global_rect()
	var next: Rect2 = (main._hud.find_child("NextCard", true, false) as Control).get_global_rect()
	# Revised 2026-10-11 (owner: visual alignment): the cards line up with the
	# outer edge of the board's frame, which is drawn FRAME_WIDTH outside the
	# slot, and both cards are the same size.
	var frame: Rect2 = board.grow(BoardView.FRAME_WIDTH)
	var ok: bool = absf(info.position.y - frame.position.y) <= FLOAT_TOL and absf(info.end.y - frame.end.y) <= FLOAT_TOL
	ok = ok and absf(frame.position.x - info.end.x - PANEL_GAP_PX) <= FLOAT_TOL
	ok = ok and absf(next.position.x - frame.end.x - PANEL_GAP_PX) <= FLOAT_TOL
	ok = ok and info.size.is_equal_approx(next.size) and absf(next.position.y - info.position.y) <= FLOAT_TOL
	# The board view sits exactly on the layout's slot.
	ok = ok and main._board_view.board_size() == board.size
	ok = ok and (main._hud.board_slot as Control).get_global_rect().position.is_equal_approx(board.position)
	main.free()
	_case(ctx, "side_columns_match_board_height_one_gap_away", ok)


static func _case_digit_union_x_offsets_aligned_within_1px(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	await _at_size(BASE_SIZE)
	var ok: bool = true
	var xs: Array[float] = []
	for value: Variant in _value_labels(main):
		if value is Label:
			xs.append((value as Label).get_global_rect().position.x)
		else:
			ok = false
	if ok and xs.max() - xs.min() > DIGIT_X_ALIGN_TOLERANCE_PX:
		ok = false
	main.free()
	_case(ctx, "readout_values_share_one_left_edge", ok)


static func _case_data_blocks_no_overlap_hold_next_controls(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var ok: bool = true
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var rects: Dictionary = _region_rects(main)
		var blocks: Variant = _readout_block_rects(main)
		if blocks == null:
			ok = false
			continue
		for key: String in ["hold", "next", "controls"]:
			var other: Variant = rects[key]
			if other == null:
				ok = false
				continue
			var other_px: Rect2 = _to_px(other, scale)
			for block: Variant in (blocks as Array):
				if _to_px(block, scale).grow(-0.25).intersects(other_px.grow(-0.25)):
					ok = false
	main.free()
	_case(ctx, "data_blocks_no_overlap_hold_next_controls", ok)


static func _case_data_blocks_pairwise_non_overlapping(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var ok: bool = true
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var blocks: Variant = _readout_block_rects(main)
		if blocks == null:
			ok = false
			continue
		var block_px: Array = []
		for block: Variant in (blocks as Array):
			block_px.append(_to_px(block, scale))
		for i: int in range(block_px.size()):
			for j: int in range(i + 1, block_px.size()):
				if (block_px[i] as Rect2).grow(-0.25).intersects((block_px[j] as Rect2).grow(-0.25)):
					ok = false
	main.free()
	_case(ctx, "data_blocks_pairwise_non_overlapping", ok)


static func _case_data_and_panels_inside_window_all_sizes(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var ok: bool = true
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
		var rects: Dictionary = _region_rects(main)
		var labels: Variant = rects["data"]
		if typeof(labels) != TYPE_ARRAY or (labels as Array).size() != 3:
			ok = false
			continue
		for i: int in range(3):
			ok = ok and _window_ok(_to_px((labels as Array)[i], scale), window)
		for key: String in ["board", "hold", "next", "controls"]:
			var rect: Variant = rects[key]
			if rect == null:
				ok = false
				continue
			ok = ok and _window_ok(_to_px(rect, scale), window)
	main.free()
	_case(ctx, "data_and_panels_inside_window_all_sizes", ok)


static func _case_controls_hidden_or_deemphasized(ctx: Dictionary) -> void:
	# Revised 2026-10-10 (owner: "do not spread everything out"): the key hints
	# are one line under the board, with the real bindings, inside the GameArea
	# and clear of the board and the cards.
	var main = await _spawn_main_windowed()
	var controls: Variant = main.get("_controls_label")
	var ok: bool = controls is Label
	if ok:
		var label: Label = controls
		var text_size: Vector2 = label.get_minimum_size()
		var rect: Rect2 = Rect2(label.get_global_rect().get_center() - text_size / 2.0, text_size)
		ok = label.visible and not label.text.is_empty() and not label.text.contains("\n") \
			and _game_area_rect(main).encloses(rect) \
			and text_size.x <= label.size.x + FLOAT_TOL \
			and not rect.intersects(_board_rect(main)) \
			and not rect.intersects((main._next_container as Control).get_global_rect())
	main.free()
	_case(ctx, "controls_visible_and_contained", ok)


static func _case_veil_labels_contained_and_centered(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	await _at_size(BASE_SIZE)
	var canvas_window: Rect2 = Rect2(Vector2.ZERO, Vector2(BASE_SIZE))
	main._paused = true
	main._game_over = true
	main._refresh_view()
	# WP-pause-1: the retired hand-drawn PAUSED veil is replaced by the Maaack
	# pause menu window. Its own container must satisfy the same-tier geometry:
	# visible, fully inside the canvas window, centered on both axes (same
	# tolerance values as before, none changed).
	var pause_menu: Control = main._pause_menu
	var ok: bool = pause_menu != null and pause_menu.visible and main._game_over_veil.visible
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for i: int in 3:
		await tree.process_frame
	if pause_menu != null:
		var menu_rect: Rect2 = pause_menu.get_global_rect()
		ok = ok and menu_rect.size.x > 0.0 and menu_rect.size.y > 0.0
		ok = ok and canvas_window.encloses(menu_rect)
		ok = ok and absf(menu_rect.get_center().x - canvas_window.get_center().x) <= CENTERING_TOLERANCE_PX
		ok = ok and absf(menu_rect.get_center().y - canvas_window.get_center().y) <= CENTERING_TOLERANCE_PX
	# Revised 2026-10-10: the game-over panel is the pack's "result_panel"
	# layout - a window centered in the canvas with its labels inside it.
	var panel: Control = main._game_over_veil
	var window_rect: Rect2 = (panel.find_child("Window", true, false) as Control).get_global_rect()
	ok = ok and canvas_window.encloses(window_rect)
	ok = ok and absf(window_rect.get_center().x - canvas_window.get_center().x) <= CENTERING_TOLERANCE_PX
	for label: Label in [panel.title, panel.detail]:
		var label_rect: Rect2 = label.get_global_rect()
		ok = ok and label.is_visible_in_tree() and window_rect.grow(FLOAT_TOL).encloses(label_rect)
		ok = ok and absf(label_rect.get_center().x - window_rect.get_center().x) <= FLOAT_TOL
	main._paused = false
	main._game_over = false
	main._refresh_view()
	main.free()
	_case(ctx, "veil_labels_contained_and_centered", ok)


static func _case_score_display_growth_bounded_in_window(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	await _at_size(BASE_SIZE)
	main._score = 1234567
	main._refresh_view()
	var value: Label = main._score_value
	# A seven-digit score still fits the stats card (no clipping, no overlap
	# with the board).
	var ok: bool = value.text == "1234567" and value.get_minimum_size().x <= value.size.x + FLOAT_TOL
	ok = ok and value.get_global_rect().end.x <= _board_rect(main).position.x
	main.free()
	_case(ctx, "score_display_growth_bounded_in_window", ok)


static func _case_stretch_config_uniform_board_centered_composition(ctx: Dictionary) -> void:
	var main = await _spawn_main_windowed()
	var mode: String = ProjectSettings.get_setting("display/window/stretch/mode")
	var aspect: String = ProjectSettings.get_setting("display/window/stretch/aspect")
	var base_w: int = int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h: int = int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var ok: bool = mode == "canvas_items" and aspect == "expand" and base_w == 1152 and base_h == 648
	var board: Rect2 = _board_rect(main)
	for size: Vector2i in WINDOW_SIZES:
		var scale: float = await _at_size(size)
		var scale_x: float = float(size.x) / float(BASE_SIZE.x)
		var scale_y: float = float(size.y) / float(BASE_SIZE.y)
		ok = ok and absf(scale_x - scale_y) <= 0.001
		ok = ok and absf(scale - scale_x) <= 0.001
		var board_px: Rect2 = _to_px(board, scale)
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
		ok = ok and window.encloses(board_px)
		ok = ok and absf(board_px.get_center().x - float(size.x) / 2.0) <= CENTERING_TOLERANCE_PX * scale
	main.free()
	_case(ctx, "stretch_config_uniform_board_centered_composition", ok)


# ---------------------------------------------------------------------------
# WP-verify-1 (O-06) extension: the menu-era interfaces under the same
# three-tier 16:9 contract. Append-only: every constant, helper and case
# above is untouched, and the cases below reuse the existing tolerances
# (CENTERING_TOLERANCE_PX, FLOAT_TOL, WINDOW_SIZES, _at_size) with no new
# geometry numbers. The vendored main menu runs the template StartUp node,
# which applies the persisted config and connects the template window-size
# hook that saves ScreenResolution on every resize (test_settings.gd
# convention), so window mode/size and the config file are snapshotted and
# restored around every menu spawn.
const MENU_SCENE_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const MODE_SELECT_SCENE_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const OPTIONS_WINDOW_SCENE_PATH: String = "res://scenes/windows/main_menu_options_window.tscn"
const CONFIG_LOCATION: String = "user://player_config.cfg"
const MENU_SETTLE_FRAMES: int = 3

static var _window_protection: Dictionary = {}


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
	# Disconnect the template size hook first (only when this module added
	# it) so restoring the window does not re-save the config file.
	if not bool(_window_protection["hook_connected"]):
		for connection: Dictionary in tree.root.size_changed.get_connections():
			var callable: Callable = connection["callable"]
			if callable.get_method() == "_on_window_size_changed":
				tree.root.size_changed.disconnect(callable)
	tree.root.mode = _window_protection["window_mode"]
	tree.root.size = _window_protection["window_size"]
	# The template hook may have re-saved the config while the menu was in
	# the tree; put the player's persisted config back byte-for-byte.
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


static func _menu_spawn(scene_path: String) -> Control:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var menu: Control = (load(scene_path) as PackedScene).instantiate() as Control
	if menu == null:
		return null
	tree.root.add_child(menu)
	for i: int in MENU_SETTLE_FRAMES:
		await tree.process_frame
	return menu


static func _inside_scroll_container(node: Node) -> bool:
	# ScrollContainer children are legitimately clipped/scrolled; the window
	# containment claim applies to everything else.
	var current: Node = node.get_parent()
	while current != null:
		if current is ScrollContainer:
			return true
		current = current.get_parent()
	return false


static func _collect_visible_leaves(node: Node, leaves: Array[Rect2], buttons: Array[Rect2]) -> void:
	if node is Control:
		var control: Control = node
		if not control.visible:
			return
		var has_control_child: bool = false
		for child: Node in control.get_children():
			if child is Control:
				has_control_child = true
				break
		if not has_control_child and control.size.x > 0.0 and control.size.y > 0.0 \
				and not _inside_scroll_container(control):
			leaves.append(control.get_global_rect())
			if control is BaseButton:
				buttons.append(control.get_global_rect())
	for child: Node in node.get_children():
		_collect_visible_leaves(child, leaves, buttons)


static func _menu_geometry_ok(menu_root: Control, window_px: Rect2, scale: float) -> bool:
	# Geometry is measured in window pixels via the existing _to_px helper:
	# under the project's uniform 16:9 canvas_items+expand stretch the canvas
	# stays at BASE_SIZE units in every tier (asserted by
	# stretch_config_uniform_board_centered_composition), so canvas rects are
	# scaled exactly like the board/panel rects above. Root spans the window,
	# no visible leaf is out of the window (no clipping), and no two
	# actionable buttons overlap.
	var root_px: Rect2 = _to_px(menu_root.get_global_rect(), scale)
	var ok: bool = Rect2(window_px).grow(FLOAT_TOL).encloses(root_px)
	ok = ok and absf(root_px.size.x - window_px.size.x) <= CENTERING_TOLERANCE_PX * scale
	ok = ok and absf(root_px.size.y - window_px.size.y) <= CENTERING_TOLERANCE_PX * scale
	var buttons: Array[Rect2] = []
	var leaves: Array[Rect2] = []
	_collect_visible_leaves(menu_root, leaves, buttons)
	for rect: Rect2 in leaves:
		ok = ok and Rect2(window_px).grow(FLOAT_TOL).encloses(_to_px(rect, scale))
	for i: int in range(buttons.size()):
		for j: int in range(i + 1, buttons.size()):
			ok = ok and not (buttons[i] as Rect2).grow(-0.25).intersects((buttons[j] as Rect2).grow(-0.25))
	return ok


static func _case_menu_like_scene_contained_all_sizes(ctx: Dictionary, case_name: String, scene_path: String) -> void:
	# O-06: a full-rect menu scene (main menu / mode select) shows no
	# overlap, out-of-window leaf or clipping at any of the three 16:9 tiers.
	_protect_window_and_config()
	var menu: Control = await _menu_spawn(scene_path)
	var ok: bool = menu is Control
	if ok:
		for size: Vector2i in WINDOW_SIZES:
			var scale: float = await _at_size(size)
			ok = ok and _menu_geometry_ok(menu, Rect2(Vector2.ZERO, Vector2(size)), scale)
	if menu != null:
		menu.free()
	_restore_window_and_config()
	_case(ctx, case_name, ok)


static func _case_options_window_contained_no_overlap_all_sizes(ctx: Dictionary) -> void:
	# O-06: the settings window (opened through the template Options entry)
	# satisfies the same geometry at all three tiers.
	_protect_window_and_config()
	var menu: Control = await _menu_spawn(MENU_SCENE_PATH)
	var ok: bool = menu != null
	if ok:
		var options_button: Button = menu.find_child("OptionsButton", true, false) as Button
		ok = ok and options_button != null
		if options_button != null:
			options_button.pressed.emit()
			for i: int in MENU_SETTLE_FRAMES:
				await (Engine.get_main_loop() as SceneTree).process_frame
		var sub_menu: Variant = menu.get("sub_menu")
		ok = ok and sub_menu is Control and (sub_menu as Control).visible
		if sub_menu is Control and (sub_menu as Control).visible:
			for size: Vector2i in WINDOW_SIZES:
				var scale: float = await _at_size(size)
				ok = ok and _menu_geometry_ok(sub_menu, Rect2(Vector2.ZERO, Vector2(size)), scale)
			var close_button: Variant = (sub_menu as Control).get("close_button")
			if close_button is Button:
				(close_button as Button).pressed.emit()
				for i: int in 2:
					await (Engine.get_main_loop() as SceneTree).process_frame
	if menu != null:
		menu.free()
	_restore_window_and_config()
	_case(ctx, "options_window_contained_no_overlap_all_sizes", ok)


static func _case_pause_menu_window_contained_all_sizes(ctx: Dictionary) -> void:
	# O-06: the Maaack pause menu window stays inside the canvas window,
	# centered, with non-overlapping buttons, at all three tiers (the
	# pre-existing veil case keeps its own BASE_SIZE assertions untouched).
	# Window-pixel space like the board cases above: canvas rect scaled by
	# the tier's content scale, tolerance scaled with it.
	var main = await _spawn_main_windowed()
	var ok: bool = main != null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if main != null:
		for size: Vector2i in WINDOW_SIZES:
			var scale: float = await _at_size(size)
			main._paused = true
			main._refresh_view()
			for i: int in 3:
				await tree.process_frame
			var window_px: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
			var pause_menu: Control = main._pause_menu
			ok = ok and pause_menu is Control and pause_menu.visible
			if pause_menu is Control and pause_menu.visible:
				var menu_px: Rect2 = _to_px(pause_menu.get_global_rect(), scale)
				ok = ok and menu_px.size.x > 0.0 and menu_px.size.y > 0.0
				ok = ok and window_px.encloses(menu_px)
				ok = ok and absf(menu_px.get_center().x - window_px.get_center().x) <= CENTERING_TOLERANCE_PX * scale
				ok = ok and absf(menu_px.get_center().y - window_px.get_center().y) <= CENTERING_TOLERANCE_PX * scale
				var buttons: Array[Rect2] = []
				var leaves: Array[Rect2] = []
				_collect_visible_leaves(pause_menu, leaves, buttons)
				for rect: Rect2 in leaves:
					ok = ok and pause_menu.get_global_rect().grow(FLOAT_TOL).encloses(rect)
				for i: int in range(buttons.size()):
					for j: int in range(i + 1, buttons.size()):
						ok = ok and not (buttons[i] as Rect2).grow(-0.25).intersects((buttons[j] as Rect2).grow(-0.25))
			main._paused = false
			main._refresh_view()
			await tree.process_frame
	main.free()
	_case(ctx, "pause_menu_window_contained_all_sizes", ok)


# ---------------------------------------------------------------------------
# T-09 (O-07) extension: the delivered versus double-board scene and the versus
# selection steps under the same three-tier 16:9 contract. Append-only: every
# constant, helper and case above is untouched. Board rectangles and per-side
# regions are exported from versus.gd's frozen layout constants (CELL_SIZE /
# BOARD_TOP_Y / PLAYER_BOARD_X / AI_BOARD_X and the per-side HOLD / NEXT /
# WARN / READOUT columns); the measured items are the real visible nodes under
# BoardView, reused with the existing tolerances (FLOAT_TOL,
# CENTERING_TOLERANCE_PX, WINDOW_SIZES, _at_size, _to_px, _menu_geometry_ok).
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const VERSUS_BOARD_COLUMNS: int = 10
const VERSUS_BOARD_ROWS: int = 20
const VERSUS_CENTER_X: float = 576.0
const VERSUS_READOUT_HEIGHT: float = 176.0
const VERSUS_OVERLAY_NAME: NodePath = ^"RoundOverlay"


# Revised 2026-10-10 (owner: the UI is laid out by resource-pack scenes): the regions are
# read from the two "versus_side" layouts instead of position constants.
static func _versus_side_regions(versus) -> Dictionary:
	var regions: Dictionary = {}
	for pair: Array in [["player", 0], ["ai", 1]]:
		var side: VersusSide = versus._hud.side(pair[1])
		regions[pair[0]] = {
			"board": side.board_slot.get_global_rect(),
			"hold": (side.find_child("InfoCard", true, false) as Control).get_global_rect(),
			"warn": side.warn_bar.get_global_rect(),
			"next": (side.find_child("NextCard", true, false) as Control).get_global_rect(),
		}
	return regions


static func _versus_canvas_rect(item: CanvasItem) -> Variant:
	if item is Control:
		var control: Control = item
		if control.size.x <= 0.0 or control.size.y <= 0.0:
			return null
		return control.get_global_rect()
	if item is Polygon2D:
		var poly: Polygon2D = item
		if poly.polygon.is_empty():
			return null
		var xform: Transform2D = poly.get_global_transform()
		var min_point: Vector2 = Vector2(INF, INF)
		var max_point: Vector2 = Vector2(-INF, -INF)
		for point: Vector2 in poly.polygon:
			var global_point: Vector2 = xform * point
			min_point = min_point.min(global_point)
			max_point = max_point.max(global_point)
		return Rect2(min_point, max_point - min_point)
	return null


static func _collect_versus_items(node: Node, skip: Node, items: Array[Rect2],
		managed: Array[Rect2], polygons: Array[Rect2]) -> void:
	if node == skip:
		return
	if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
		var rect: Variant = _versus_canvas_rect(node)
		if rect != null:
			items.append(rect)
			if node is ColorRect:
				managed.append(rect)
			elif node is Polygon2D:
				polygons.append(rect)
	for child: Node in node.get_children():
		_collect_versus_items(child, skip, items, managed, polygons)


static func _spawn_versus_windowed():
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var versus: Node2D = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate() as Node2D
	tree.root.add_child(versus)
	await tree.create_timer(SPAWN_SETTLE_SECONDS).timeout
	return versus


static func _case_versus_scene_contained_all_sizes(ctx: Dictionary) -> void:
	# O-07: both boards inside the green GameArea (96,54)-(1056,594) and the
	# window, equal sized and mirrored around the window center; the player
	# cluster never crosses x=576 and the AI cluster never crosses it from the
	# right (the frozen center gap); every visible ColorRect / Polygon2D under
	# BoardView stays inside the GameArea; and the per-side board / HOLD / NEXT
	# / warning-bar / readout regions are pairwise disjoint.
	var versus: Node2D = await _spawn_versus_windowed()
	var ok: bool = versus != null
	if versus != null:
		var regions: Dictionary = _versus_side_regions(versus)
		var all_regions: Array[Rect2] = []
		for side_key: String in ["player", "ai"]:
			var side_regions: Dictionary = regions[side_key]
			for region_key: String in side_regions:
				all_regions.append(side_regions[region_key] as Rect2)
		for i: int in range(all_regions.size()):
			for j: int in range(i + 1, all_regions.size()):
				ok = ok and not (all_regions[i] as Rect2).grow(-0.25).intersects((all_regions[j] as Rect2).grow(-0.25))
		var player_board: Rect2 = (regions["player"] as Dictionary)["board"] as Rect2
		var ai_board: Rect2 = (regions["ai"] as Dictionary)["board"] as Rect2
		ok = ok and player_board.size == ai_board.size
		var game_area: Rect2 = _game_area_rect(versus)
		ok = ok and game_area.size.x > 0.0 and game_area.size.y > 0.0
		var board_view: Node = versus.get_node_or_null(^"BoardView")
		ok = ok and board_view != null
		# The boards drawn are exactly the layout's slots.
		for side_index: int in 2:
			var view = versus._sides[side_index]
			ok = ok and (view.board as BoardView).board_size() == (view.layout.board_slot as Control).size
			ok = ok and (view.board as BoardView).global_position.is_equal_approx((view.layout.board_slot as Control).global_position)
		for size: Vector2i in WINDOW_SIZES:
			var scale: float = await _at_size(size)
			var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
			var player_px: Rect2 = _to_px(player_board, scale)
			var ai_px: Rect2 = _to_px(ai_board, scale)
			ok = ok and window.encloses(player_px) and window.encloses(ai_px)
			ok = ok and game_area.grow(FLOAT_TOL).encloses(player_board)
			ok = ok and game_area.grow(FLOAT_TOL).encloses(ai_board)
			var pair_center: Vector2 = (player_px.get_center() + ai_px.get_center()) / 2.0
			ok = ok and absf(pair_center.x - float(size.x) / 2.0) <= CENTERING_TOLERANCE_PX * scale
			# Revised 2026-10-10: the stock layout stacks a header and the name
			# tags over the boards, so the pair is centered horizontally only;
			# vertically both boards share one top and one bottom edge.
			ok = ok and absf(player_px.position.y - ai_px.position.y) <= FLOAT_TOL
			if board_view != null:
				# Containment includes the centered round-overlay veil, which
				# only appears after a round ends.
				var all_items: Array[Rect2] = []
				var managed: Array[Rect2] = []
				var polygons: Array[Rect2] = []
				_collect_versus_items(board_view, null, all_items, managed, polygons)
				# (2026-10-10: the versus stats are Labels now, so the scene has
				# no Polygon2D readouts left to require.)
				# Revised 2026-10-10: the scene is built from layout scenes, so
				# what must stay inside the GameArea is every card, meter and
				# board slot of both sides.
				for side_key: String in ["player", "ai"]:
					for region_key: String in regions[side_key]:
						ok = ok and game_area.grow(FLOAT_TOL).encloses(regions[side_key][region_key] as Rect2)
				for rect: Rect2 in managed:
					ok = ok and game_area.grow(FLOAT_TOL).encloses(rect)
				for rect: Rect2 in polygons:
					ok = ok and game_area.grow(FLOAT_TOL).encloses(rect)
				# The center gap is measured on the real side clusters: the
				# centered round overlay is a modal, not a side cluster.
				var items: Array[Rect2] = []
				var ignored_managed: Array[Rect2] = []
				var ignored_polygons: Array[Rect2] = []
				# (The header - level and round score - is centered on the
				# screen by design and belongs to neither side.)
				_collect_versus_items(board_view, versus._hud.level_label.get_parent(), items, ignored_managed, ignored_polygons)
				ok = ok and not items.is_empty()
				var player_max_end: float = -INF
				var ai_min_start: float = INF
				for rect: Rect2 in items:
					var center_x: float = rect.get_center().x
					if center_x < VERSUS_CENTER_X:
						player_max_end = maxf(player_max_end, rect.end.x)
					elif center_x > VERSUS_CENTER_X:
						ai_min_start = minf(ai_min_start, rect.position.x)
				ok = ok and player_max_end > -INF and ai_min_start < INF
				ok = ok and player_max_end <= VERSUS_CENTER_X + FLOAT_TOL
				ok = ok and ai_min_start >= VERSUS_CENTER_X - FLOAT_TOL
		versus.free()
	_case(ctx, "versus_scene_contained_all_sizes", ok)


static func _case_mode_select_versus_level_step_contained_all_sizes(ctx: Dictionary) -> void:
	# Revised 2026-10-10: the three-step wizard became one setup page. Mode
	# select -> Versus shows the Speed / Level / CPU / Match rows, the
	# description and Start Match + Back; with Fixed Speed (ten level buttons
	# visible) and with Rising Speed (level row hidden) every control stays
	# inside the window, unclipped and non-overlapping at all three tiers.
	# Window mode/size and the persisted config are snapshotted and restored
	# around the spawn, because the template StartUp node connects the
	# window-size hook (same convention as the menu-like cases above).
	_protect_window_and_config()
	var menu: Control = await _menu_spawn(MODE_SELECT_SCENE_PATH)
	var ok: bool = menu != null
	if menu != null:
		# 2026-10-12: the screen opens on the setup page (Versus CPU here).
		var back_button: Button = menu.find_child("BackButton", true, false) as Button
		ok = ok and back_button != null
		if ok:
			for rules: StringName in [&"fixed", &"rising"]:
				menu._on_option_picked("rules", rules)
				for i: int in MENU_SETTLE_FRAMES:
					await (Engine.get_main_loop() as SceneTree).process_frame
				var visible_levels: int = 0
				for level: int in range(1, 11):
					var level_button: Button = menu.find_child("VersusLevel%d" % level, true, false) as Button
					ok = ok and level_button != null
					if level_button != null and level_button.is_visible_in_tree():
						visible_levels += 1
				ok = ok and visible_levels == (10 if rules == &"fixed" else 0)
				for control_name: String in ["VersusCPUEasy", "VersusCPULunatic", "VersusMatchBestof3", "VersusStartButton", "BackButton"]:
					var control: Control = menu.find_child(control_name, true, false) as Control
					ok = ok and control != null and control.is_visible_in_tree()
				for size: Vector2i in WINDOW_SIZES:
					var scale: float = await _at_size(size)
					ok = ok and _menu_geometry_ok(menu, Rect2(Vector2.ZERO, Vector2(size)), scale)
	if menu != null:
		menu.free()
	_restore_window_and_config()
	_case(ctx, "mode_select_versus_level_step_contained_all_sizes", ok)
