extends SceneTree

const MODULE_NAME: String = "ui_reference"

# O-05 machine assertions (WP-verify-1): the menu / settings / mode-select /
# pause / HUD surfaces come from the archived references, not from invented
# design. Everything here is read-only with respect to product files and the
# docs/vendor archives:
#  (a) every interface scene/script path is recorded in docs/vendor
#      (maaack scenes_copies, byte-bound like test_pause_menu does) or is a
#      project-authored source file (mode select, HUD) that stays outside the
#      vendor claims; the marinho effect resources are byte-bound to the
#      marinho manifest files[] via FileAccess.get_sha256;
#  (b) the four copied interfaces inherit their archived template originals
#      (base-scene ext_resource path + base-script chain + key methods);
#  (c) the Maaack ProjectUISoundController hover/pressed streams are archived
#      CC0 assets covered by assets/assets-provenance.json (BQ-11);
#  (d) the HUD keeps the information architecture: Hold left of the board,
#      Next right of it, and SCORE/LINES/LEVEL readouts inside the green
#      GameArea border with HOLD below them, all left of the board;
#  (e) no self-authored theme resource exists under scenes/ (no .tres/.theme
#      controls, every ext_resource stays on archived/project roots, and
#      project.godot selects no project-authored custom theme).

const MAAACK_RECORD_PATH: String = "res://docs/vendor/maaack-game-template.json"
const MARINHO_RECORD_PATH: String = "res://docs/vendor/marinho-visual-effects.json"
const PROVENANCE_PATH: String = "res://assets/assets-provenance.json"
const RUN_ALL_PATH: String = "res://tests/run_all.gd"
const PROJECT_GODOT_PATH: String = "res://project.godot"
const UI_SOUND_CONTROLLER_SCENE: String = "res://addons/maaacks_ui_sound_controller/base/scenes/autoloads/project_ui_sound_controller.tscn"
const HOVER_STREAM_PATH: String = "res://assets/audio/interface/tick_002.ogg"
const PRESSED_STREAM_PATH: String = "res://assets/audio/interface/confirmation_004.ogg"
const ARCHIVED_AUDIO_INTERFACE_DEST: String = "assets/audio/interface"

# Interface files copied from the archived Maaack template; every one must
# exist on disk with exactly the bytes its archive entry records.
const MAAACK_COPIES: Array[String] = [
	"res://scenes/menus/main_menu/main_menu_with_animations.tscn",
	"res://scenes/menus/main_menu/main_menu_with_animations.gd",
	"res://scenes/menus/main_menu/main_menu_with_animations.gd.uid",
	"res://scenes/windows/main_menu_options_window.tscn",
	"res://scenes/menus/options_menu/master_options_menu_with_tabs.tscn",
	"res://scenes/menus/options_menu/master_options_menu_with_tabs.gd",
	"res://scenes/menus/options_menu/master_options_menu_with_tabs.gd.uid",
	"res://scenes/menus/options_menu/audio/audio_options_menu.tscn",
	"res://scenes/menus/options_menu/audio/audio_input_option_control.tscn",
	"res://scenes/menus/options_menu/audio/audio_input_option_control.gd",
	"res://scenes/menus/options_menu/audio/audio_input_option_control.gd.uid",
	"res://scenes/menus/options_menu/input/input_options_menu.tscn",
	"res://scenes/menus/options_menu/input/input_extras_menu.tscn",
	"res://scenes/menus/options_menu/input/input_icon_mapper.tscn",
	"res://scenes/menus/options_menu/video/video_options_menu_with_extras.tscn",
	"res://scenes/menus/options_menu/game/game_options_menu.tscn",
	"res://scenes/menus/options_menu/game/game_options_menu.gd",
	"res://scenes/menus/options_menu/game/reset_game_control/reset_game_control.tscn",
	"res://scenes/menus/options_menu/game/reset_game_control/reset_game_control.gd",
	"res://scenes/windows/pause_menu.tscn",
	"res://scenes/windows/pause_menu.gd",
	"res://scenes/windows/pause_menu.gd.uid",
	"res://scenes/windows/pause_menu_options_window.tscn",
]
# Interface files authored by this project (not vendor copies): the mode
# select adapter, the HUD and the versus double-board scene/script. The vendor
# record must not claim them.
const PROJECT_AUTHORED_PATHS: Array[String] = [
	"res://scenes/menus/mode_select/mode_select.tscn",
	"res://scenes/menus/mode_select/mode_select.gd",
	"res://scenes/versus/versus.tscn",
	"res://scripts/versus.gd",
	"res://scenes/main.tscn",
	"res://scripts/main.gd",
	# OD-06 (BD-14/BD-16): the language option control lives on the reachable
	# Video options page (the Game page is not referenced by the master
	# options menu). Same project-authored adapter category as mode_select.gd.
	"res://scenes/menus/options_menu/video/language_control.gd",
]
# marinho effect resources used by the delivery (BD-09: Kaykit excluded).
const MARINHO_EFFECT_FILES: Array[String] = [
	"res://camera-effects/camera_shake.tscn",
	"res://camera-effects/camera-shake.gdshader",
	"res://camera-effects/chromatic_aberration.tscn",
	"res://camera-effects/chromatic-aberration.gdshader",
	"res://camera-effects/vignette.tscn",
	"res://camera-effects/vignette.gdshader",
	"res://particles/shockwave_2d.tscn",
	"res://particles/sparks_2d.tscn",
	"res://addons/kenney_particle_pack/circle_01.png",
	"res://addons/kenney_particle_pack/trace_01.png",
]
# Archived template originals for the inheritance assertions.
const MAIN_MENU_SCENE_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const MAIN_MENU_VARIANT_GD: String = "res://scenes/menus/main_menu/main_menu_with_animations.gd"
const MODE_SELECT_SCENE_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const MASTER_TABS_GD: String = "res://scenes/menus/options_menu/master_options_menu_with_tabs.gd"
const PAUSE_MENU_SCENE_PATH: String = "res://scenes/windows/pause_menu.tscn"
const TEMPLATE_BASE_SCENE_MAIN_MENU: String = "res://addons/maaacks_game_template/base/nodes/menus/main_menu/main_menu.tscn"
const TEMPLATE_BASE_GD_MAIN_MENU: String = "res://addons/maaacks_game_template/base/nodes/menus/main_menu/main_menu.gd"
const TEMPLATE_BASE_GD_TABS: String = "res://addons/maaacks_game_template/base/nodes/menus/options_menu/paginated_tab_container.gd"
const TEMPLATE_BASE_SCENE_PAUSE: String = "res://addons/maaacks_game_template/base/nodes/windows/popup_window_panel.tscn"
const TEMPLATE_BASE_GD_PAUSE: String = "res://addons/maaacks_game_template/base/nodes/windows/popup_window_panel.gd"
# Scene references may only point at the archived addons tree, the copied /
# authored scenes tree, or the archived assets.
const ALLOWED_EXT_RESOURCE_PREFIXES: Array[String] = [
	"res://addons/",
	"res://scenes/menus/",
	"res://scenes/windows/",
]
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
# O-07 (T-09): the versus double-board scene follows the same archived design
# language. Its scene references may also point at the project script root and
# the archived assets (the versus scene keeps the Kenney background and loads
# the Kenney fonts + copied pause window at runtime).
const VERSUS_DIR: String = "res://scenes/versus"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const VERSUS_SCRIPT_PATH: String = "res://scripts/versus.gd"
const PAUSE_MENU_SCRIPT_PATH: String = "res://scenes/windows/pause_menu.gd"
const VERSUS_ALLOWED_EXT_RESOURCE_PREFIXES: Array[String] = [
	"res://addons/",
	"res://scenes/menus/",
	"res://scenes/windows/",
	"res://scripts/",
	"res://assets/",
]
const BASE_SIZE: Vector2i = Vector2i(1152, 648)
const SPAWN_SETTLE_SECONDS: float = 0.2
const FLOAT_TOL: float = 1.0


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d ui_reference cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("UI REFERENCE TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_maaack_interface_copies_match_archived_bytes(ctx)
	await _case_project_authored_paths_stay_out_of_vendor_claims(ctx)
	await _case_marinho_effect_files_bound_to_manifest(ctx)
	await _case_copied_menus_inherit_archived_template_originals(ctx)
	await _case_ui_sound_streams_are_archived_cc0(ctx)
	await _case_hud_keeps_hold_left_next_right_readouts_inside_game_area(ctx)
	await _case_no_self_authored_theme_or_control_resources(ctx)
	await _case_versus_scene_uses_archived_design_language(ctx)
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


static func _load_scenes_copies() -> Variant:
	if not FileAccess.file_exists(MAAACK_RECORD_PATH):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAAACK_RECORD_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return (parsed as Dictionary).get("scenes_copies")


static func _script_inherits_from(script: Script, ancestor_path: String) -> bool:
	var current: Script = script
	while current != null:
		if current.resource_path == ancestor_path:
			return true
		current = current.get_base_script()
	return false


static func _collect_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if entry_name.begins_with("."):
			entry_name = dir.get_next()
			continue
		var full_path: String = dir_path + "/" + entry_name
		if dir.current_is_dir():
			found.append_array(_collect_files(full_path))
		else:
			found.append(full_path)
		entry_name = dir.get_next()
	dir.list_dir_end()
	return found


static func _ext_resource_paths(scene_path: String) -> Array[String]:
	var paths: Array[String] = []
	var text: String = FileAccess.get_file_as_string(scene_path)
	for line: String in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var marker: String = "path=\""
		var start: int = line.find(marker)
		if start < 0:
			continue
		start += marker.length()
		var end_pos: int = line.find("\"", start)
		if end_pos < 0:
			continue
		paths.append(line.substr(start, end_pos - start))
	return paths


static func _rect_of_region(value: Variant) -> Variant:
	if value is Control:
		return (value as Control).get_global_rect()
	return null


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


static func _spawn_main_windowed():
	var tree: SceneTree = _tree()
	await tree.process_frame
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	tree.root.add_child(main)
	await tree.create_timer(SPAWN_SETTLE_SECONDS).timeout
	return main


static func _case_maaack_interface_copies_match_archived_bytes(ctx: Dictionary) -> void:
	# (a) every copied interface file exists with the exact bytes its
	# docs/vendor/maaack-game-template.json scenes_copies entry records
	# (test_pause_menu convention, extended to the whole menu surface).
	var ok: bool = FileAccess.file_exists(MAAACK_RECORD_PATH)
	var copies: Variant = _load_scenes_copies()
	ok = ok and typeof(copies) == TYPE_ARRAY
	for project_path: String in MAAACK_COPIES:
		if not ok:
			break
		ok = ok and FileAccess.file_exists(project_path)
		var entry: Dictionary = _vendor_entry(copies, project_path)
		ok = ok and not entry.is_empty()
		if entry.is_empty():
			continue
		ok = ok and String(entry.get("upstream_path", "")) == project_path.trim_prefix("res://")
		var recorded: String = String(entry.get("copied_sha256", "")).to_lower()
		ok = ok and recorded.length() == 64
		ok = ok and FileAccess.get_sha256(project_path).to_lower() == recorded
	_case(ctx, "maaack_interface_copies_match_archived_bytes", ok)


static func _case_project_authored_paths_stay_out_of_vendor_claims(ctx: Dictionary) -> void:
	# (a) the project-authored interface files (mode select, HUD) exist, are
	# not claimed by the vendor archive, and are anchored in the project
	# source manifest (run_all.gd LOAD_CHECK_PATHS) or in the archived
	# template they adapt (mode select instances the archived variant).
	var ok: bool = true
	var copies: Variant = _load_scenes_copies()
	var run_all_text: String = FileAccess.get_file_as_string(RUN_ALL_PATH)
	for project_path: String in PROJECT_AUTHORED_PATHS:
		ok = ok and FileAccess.file_exists(project_path)
		ok = ok and _vendor_entry(copies, project_path).is_empty()
	ok = ok and run_all_text.contains("\"res://scenes/main.tscn\"")
	ok = ok and run_all_text.contains("\"res://scripts/main.gd\"")
	var mode_text: String = FileAccess.get_file_as_string(MODE_SELECT_SCENE_PATH)
	ok = ok and mode_text.contains(MAIN_MENU_SCENE_PATH)
	_case(ctx, "project_authored_paths_stay_out_of_vendor_claims", ok)


static func _case_marinho_effect_files_bound_to_manifest(ctx: Dictionary) -> void:
	# (a) the marinho effect resources (camera-effects/*, adapted 2D
	# particles, Kenney CC0 textures) are recorded in the marinho manifest
	# files[] and their bytes match the recorded sha256.
	var ok: bool = FileAccess.file_exists(MARINHO_RECORD_PATH)
	var records: Dictionary = {}
	if ok:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MARINHO_RECORD_PATH))
		ok = typeof(parsed) == TYPE_DICTIONARY
		if ok:
			var files: Variant = (parsed as Dictionary).get("files")
			ok = typeof(files) == TYPE_ARRAY
			if ok:
				for entry: Variant in (files as Array):
					if typeof(entry) != TYPE_DICTIONARY:
						continue
					var key: String = "res://" + String((entry as Dictionary).get("path", "")).replace("\\", "/")
					records[key] = String((entry as Dictionary).get("sha256", "")).to_lower()
	for project_path: String in MARINHO_EFFECT_FILES:
		ok = ok and FileAccess.file_exists(project_path)
		var digest: String = String(records.get(project_path, ""))
		ok = ok and digest.length() == 64 and digest == FileAccess.get_sha256(project_path).to_lower()
	_case(ctx, "marinho_effect_files_bound_to_manifest", ok)


static func _case_copied_menus_inherit_archived_template_originals(ctx: Dictionary) -> void:
	# (b) main menu / mode select / master options tabs / pause menu each
	# inherit their archived template original (scene ext_resource path +
	# script base chain) and expose the key template methods.
	var ok: bool = true
	# Main menu variant: instances the archived base scene, its script chains
	# to the archived MainMenu class, template entry methods present.
	ok = ok and FileAccess.get_file_as_string(MAIN_MENU_SCENE_PATH).contains(TEMPLATE_BASE_SCENE_MAIN_MENU)
	var main_menu: Node = (load(MAIN_MENU_SCENE_PATH) as PackedScene).instantiate()
	ok = ok and main_menu != null
	if main_menu != null:
		var script: Variant = main_menu.get_script()
		ok = ok and script is Script and _script_inherits_from(script, TEMPLATE_BASE_GD_MAIN_MENU)
		ok = ok and main_menu.has_method("new_game") and main_menu.has_method("intro_done") \
			and main_menu.has_method("load_game_scene")
		main_menu.free()
	# Mode select: built on the archived animated variant, adds mode choice.
	ok = ok and FileAccess.get_file_as_string(MODE_SELECT_SCENE_PATH).contains(MAIN_MENU_SCENE_PATH)
	var mode_select: Node = (load(MODE_SELECT_SCENE_PATH) as PackedScene).instantiate()
	ok = ok and mode_select != null
	if mode_select != null:
		var script: Variant = mode_select.get_script()
		ok = ok and script is Script and _script_inherits_from(script, MAIN_MENU_VARIANT_GD)
		ok = ok and mode_select.has_method("select_mode") and mode_select.has_method("load_game_scene")
		mode_select.free()
	# Master options tabs: the script extends the archived paginated tab
	# container and the scene keeps the template tab structure.
	var tabs_script: GDScript = load(MASTER_TABS_GD) as GDScript
	ok = ok and tabs_script != null and tabs_script.get_base_script() != null \
		and tabs_script.get_base_script().resource_path == TEMPLATE_BASE_GD_TABS
	# Pause menu: instances the archived popup window panel, script chains to
	# its class, template close/reopen methods present.
	ok = ok and FileAccess.get_file_as_string(PAUSE_MENU_SCENE_PATH).contains(TEMPLATE_BASE_SCENE_PAUSE)
	var pause_menu: Node = (load(PAUSE_MENU_SCENE_PATH) as PackedScene).instantiate()
	ok = ok and pause_menu is PopupWindowPanel
	if pause_menu != null:
		var script: Variant = pause_menu.get_script()
		ok = ok and script is Script and _script_inherits_from(script, TEMPLATE_BASE_GD_PAUSE)
		ok = ok and pause_menu.has_method("get_main_menu_scene_path") \
			and pause_menu.has_method("close_window") and pause_menu.has_method("close")
		pause_menu.free()
	_case(ctx, "copied_menus_inherit_archived_template_originals", ok)


static func _case_ui_sound_streams_are_archived_cc0(ctx: Dictionary) -> void:
	# (c) BQ-11: menu/button feedback audio runs through the archived Maaack
	# ProjectUISoundController, and both wired streams are archived CC0
	# assets (Kenney interface sounds, assets-provenance.json family).
	var ok: bool = FileAccess.file_exists(UI_SOUND_CONTROLLER_SCENE)
	var text: String = FileAccess.get_file_as_string(UI_SOUND_CONTROLLER_SCENE)
	ok = ok and text.contains("path=\"%s\"" % HOVER_STREAM_PATH)
	ok = ok and text.contains("path=\"%s\"" % PRESSED_STREAM_PATH)
	ok = ok and text.contains("button_hovered") and text.contains("button_focused") \
		and text.contains("button_pressed")
	ok = ok and FileAccess.file_exists(HOVER_STREAM_PATH) and FileAccess.file_exists(PRESSED_STREAM_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROVENANCE_PATH))
	ok = ok and typeof(parsed) == TYPE_DICTIONARY
	if ok:
		var covered: bool = false
		var families: Variant = (parsed as Dictionary).get("families")
		if typeof(families) == TYPE_ARRAY:
			for entry: Variant in (families as Array):
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var record: Dictionary = entry
				var dest: String = String(record.get("dest", "")).replace("res://", "").replace("\\", "/")
				while dest.ends_with("/"):
					dest = dest.substr(0, dest.length() - 1)
				if dest == ARCHIVED_AUDIO_INTERFACE_DEST \
						and String(record.get("license", "")).contains("CC0"):
					covered = true
		ok = ok and covered
		ok = ok and HOVER_STREAM_PATH.begins_with("res://%s/" % ARCHIVED_AUDIO_INTERFACE_DEST)
		ok = ok and PRESSED_STREAM_PATH.begins_with("res://%s/" % ARCHIVED_AUDIO_INTERFACE_DEST)
	# Runtime: the registered autoload wires exactly these archived streams.
	var controller: Node = _tree().root.get_node_or_null(^"ProjectUISoundController")
	ok = ok and controller != null
	if controller != null:
		var hovered: Variant = controller.get("button_hovered")
		var focused: Variant = controller.get("button_focused")
		var pressed: Variant = controller.get("button_pressed")
		ok = ok and hovered is AudioStream and focused is AudioStream and pressed is AudioStream
		if ok:
			ok = ok and (hovered as AudioStream).resource_path == HOVER_STREAM_PATH \
				and (focused as AudioStream).resource_path == HOVER_STREAM_PATH \
				and (pressed as AudioStream).resource_path == PRESSED_STREAM_PATH
	_case(ctx, "ui_sound_streams_are_archived_cc0", ok)


static func _case_hud_keeps_hold_left_next_right_readouts_inside_game_area(ctx: Dictionary) -> void:
	# (d) HUD information architecture at the base canvas size: the Hold
	# container sits left of the board frame, the Next container right of it,
	# and the SCORE/LEVEL/LINES readouts sit inside the GameArea border
	# (rectangle derived from the scene node).
	# Revised 2026-10-10 (UI re-layout): HOLD is the top card of the left
	# column now, with the readouts stacked below it.
	var tree: SceneTree = _tree()
	tree.root.size = BASE_SIZE
	for i: int in 4:
		await tree.process_frame
	var main = await _spawn_main_windowed()
	var ok: bool = main != null
	if main != null:
		var board: Rect2 = _board_rect(main)
		var game_area: Rect2 = _game_area_rect(main)
		ok = ok and game_area.size.x > 0.0 and game_area.size.y > 0.0
		var hold: Variant = _rect_of_region(main.get("_hold_container"))
		var next: Variant = _rect_of_region(main.get("_next_container"))
		ok = ok and hold is Rect2 and next is Rect2
		if hold is Rect2 and next is Rect2:
			ok = ok and (hold as Rect2).end.x <= board.position.x + FLOAT_TOL
			ok = ok and (next as Rect2).position.x >= board.end.x - FLOAT_TOL
		var labels: Variant = main.get("_data_labels")
		ok = ok and typeof(labels) == TYPE_ARRAY and (labels as Array).size() == 3
		if typeof(labels) == TYPE_ARRAY and (labels as Array).size() == 3:
			var previous_end_y: float = -1.0
			for label_value: Variant in (labels as Array):
				if not (label_value is Rect2):
					ok = false
					continue
				var rect: Rect2 = label_value
				ok = ok and game_area.grow(FLOAT_TOL).encloses(rect)
				ok = ok and rect.end.x <= board.position.x + FLOAT_TOL
				ok = ok and Rect2(Vector2.ZERO, Vector2(BASE_SIZE)).encloses(rect)
				ok = ok and rect.position.y > previous_end_y
				previous_end_y = rect.end.y
			if hold is Rect2:
				ok = ok and (hold as Rect2).end.y <= ((labels as Array)[0] as Rect2).position.y + FLOAT_TOL
				ok = ok and game_area.grow(FLOAT_TOL).encloses(hold as Rect2)
	if main != null:
		main.free()
	_case(ctx, "hud_keeps_hold_left_next_right_readouts_inside_game_area", ok)


static func _case_no_self_authored_theme_or_control_resources(ctx: Dictionary) -> void:
	# (e) no self-authored theme or control resource replaces the template
	# theme: scenes/menus + scenes/windows contain no .tres/.theme resource,
	# every script there is vendor-recorded or the known project-authored
	# adapter, every scene reference stays on the archived/project roots, and
	# project.godot selects no project-authored custom theme.
	var ok: bool = true
	var files: Array[String] = []
	for root_path: String in ["res://scenes/menus", "res://scenes/windows"]:
		files.append_array(_collect_files(root_path))
	ok = ok and not files.is_empty()
	var known_scripts: Array[String] = MAAACK_COPIES.duplicate()
	known_scripts.append_array(PROJECT_AUTHORED_PATHS)
	for file_path: String in files:
		if file_path.ends_with(".tres") or file_path.ends_with(".theme"):
			ok = false
		if file_path.ends_with(".gd"):
			ok = ok and known_scripts.has(file_path)
		if file_path.ends_with(".tscn"):
			for referenced: String in _ext_resource_paths(file_path):
				var allowed: bool = false
				for prefix: String in ALLOWED_EXT_RESOURCE_PREFIXES:
					allowed = allowed or referenced.begins_with(prefix)
				ok = ok and allowed and FileAccess.file_exists(referenced)
	var project_text: String = FileAccess.get_file_as_string(PROJECT_GODOT_PATH)
	if project_text.contains("gui/theme/custom"):
		var theme_archived: bool = false
		for line: String in project_text.split("\n"):
			if line.contains("gui/theme/custom"):
				var start: int = line.find("res://")
				theme_archived = theme_archived \
					or (start >= 0 and line.substr(start).begins_with("res://addons/"))
		ok = ok and theme_archived
	_case(ctx, "no_self_authored_theme_or_control_resources", ok)


static func _case_versus_scene_uses_archived_design_language(ctx: Dictionary) -> void:
	# O-07 (T-09): the versus double-board surface keeps the archived design
	# language — no self-authored .tres/.theme under res://scenes/versus, every
	# script there vendor-recorded or project-authored, every scene
	# ext_resource on an allowed root and present on disk, versus.gd anchored
	# on the copied pause window and the Kenney fonts, the scene on the Kenney
	# background, and the runtime pause window the copied Maaack
	# PopupWindowPanel (template reuse, not a new control resource).
	var ok: bool = true
	var known_scripts: Array[String] = MAAACK_COPIES.duplicate()
	known_scripts.append_array(PROJECT_AUTHORED_PATHS)
	var files: Array[String] = _collect_files(VERSUS_DIR)
	ok = ok and not files.is_empty()
	for file_path: String in files:
		if file_path.ends_with(".tres") or file_path.ends_with(".theme"):
			ok = false
		if file_path.ends_with(".gd"):
			ok = ok and known_scripts.has(file_path)
		if file_path.ends_with(".tscn"):
			for referenced: String in _ext_resource_paths(file_path):
				var allowed: bool = false
				for prefix: String in VERSUS_ALLOWED_EXT_RESOURCE_PREFIXES:
					allowed = allowed or referenced.begins_with(prefix)
				ok = ok and allowed and FileAccess.file_exists(referenced)
	var script_text: String = FileAccess.get_file_as_string(VERSUS_SCRIPT_PATH)
	ok = ok and script_text.contains("PAUSE_MENU_SCENE: String = \"%s\"" % PAUSE_MENU_SCENE_PATH)
	# Revised 2026-10-10 (resource packs): the fonts are named by the default
	# pack; versus.gd asks the pack for them.
	var pack_text: String = FileAccess.get_file_as_string("res://packs/default/pack.json")
	ok = ok and pack_text.contains("res://assets/fonts/Kenney Future.ttf")
	ok = ok and pack_text.contains("res://assets/fonts/Kenney Mini.ttf")
	ok = ok and script_text.contains('ResourcePack.font("main")') and script_text.contains('ResourcePack.font("mini")')
	var scene_text: String = FileAccess.get_file_as_string(VERSUS_SCENE_PATH)
	ok = ok and scene_text.contains("res://assets/visuals/background.png")
	var versus: Node2D = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate() as Node2D
	ok = ok and versus != null
	if versus != null:
		_tree().root.add_child(versus)
		await _tree().process_frame
		var pause_menu: Variant = versus.get("_pause_menu")
		ok = ok and pause_menu is PopupWindowPanel
		if pause_menu is PopupWindowPanel:
			var script: Variant = (pause_menu as Node).get_script()
			ok = ok and script is Script and (script as Script).resource_path == PAUSE_MENU_SCRIPT_PATH
		versus.free()
	_case(ctx, "versus_scene_uses_archived_design_language", ok)
