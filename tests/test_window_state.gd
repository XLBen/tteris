extends SceneTree

const MODULE_NAME: String = "window-state"

# O-06/BD-04 machine assertions (battle-experience-fix S6): a window the user
# maximized must stay MAXIMIZED across the template StartUp replay (main menu
# loads) and battle entry, while a manually chosen windowed size is not
# reverted and the Fullscreen/Resolution/V-Sync paths keep working. The
# module is headless-degradable: the real-window cases are skipped without a
# display server, replaced by the static maximize-guard assertion; the real
# assertions are covered by the non-headless acceptance command.
const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const APP_SETTINGS_PATH: String = "res://addons/maaacks_game_template/base/nodes/config/app_settings.gd"
const CONFIG_LOCATION: String = "user://player_config.cfg"
const WINDOWED_SIZE: Vector2i = Vector2i(900, 600)
const PROBE_RESOLUTION: Vector2i = Vector2i(1024, 640)
const MIN_GUARD_HITS: int = 2


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d window-state cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	var suffix: String = " (headless-degraded)" if _is_degraded() else ""
	print("WINDOW STATE TESTS PASSED (%d)%s" % [int(result["total"]), suffix])
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var degraded: bool = _is_degraded()
	var snapshot: Dictionary = _snapshot_window_and_config()
	await _case_maximized_survives_menu_and_versus(ctx, degraded)
	await _case_windowed_size_not_reverted(ctx, degraded)
	await _case_maximized_size_not_recorded(ctx, degraded)
	await _case_video_controls_coexist(ctx, degraded)
	await _case_app_settings_has_maximize_guard(ctx)
	_restore_window_and_config(snapshot)
	return ctx


static func _is_degraded() -> bool:
	return DisplayServer.get_name() == "headless"


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _skip(ctx: Dictionary, case_name: String, reason: String) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	(ctx["lines"] as Array).append("SKIP %s (%s)" % [case_name, reason])


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _spawn_scene(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		return null
	var instance: Node = packed.instantiate()
	_tree().root.add_child(instance)
	await _tree().process_frame
	return instance


static func _read_config_bytes() -> PackedByteArray:
	if not FileAccess.file_exists(CONFIG_LOCATION):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(CONFIG_LOCATION)


static func _snapshot_window_and_config() -> Dictionary:
	var window: Window = _tree().root
	return {
		"window_mode": window.mode,
		"window_size": window.size,
		"vsync": AppSettings.get_vsync(),
		"config_exists": FileAccess.file_exists(CONFIG_LOCATION),
		"config_bytes": _read_config_bytes(),
	}


static func _restore_window_and_config(snapshot: Dictionary) -> void:
	# Restore the window before the config file: applying the saved size may
	# still run the template size_changed hook, which saves the config file.
	var window: Window = _tree().root
	window.mode = snapshot["window_mode"]
	window.size = snapshot["window_size"]
	AppSettings.set_vsync(snapshot["vsync"])
	PlayerConfig.config_file = null
	if bool(snapshot["config_exists"]):
		var bytes: PackedByteArray = snapshot["config_bytes"]
		var file: FileAccess = FileAccess.open(CONFIG_LOCATION, FileAccess.WRITE)
		if file != null:
			file.store_buffer(bytes)
			file.close()
	elif FileAccess.file_exists(CONFIG_LOCATION):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_LOCATION))
	PlayerConfig.config_file = null


static func _case_maximized_survives_menu_and_versus(ctx: Dictionary, degraded: bool) -> void:
	if degraded:
		_skip(ctx, "maximized_survives_menu_and_versus_loads", "headless-degraded: no real window state")
		return
	var window: Window = _tree().root
	# Let the engine finish bringing the real window up first: window state
	# assigned before the first frames ran never reaches the window manager.
	await _tree().process_frame
	await _tree().process_frame
	window.mode = Window.MODE_MAXIMIZED
	# The WM applies the maximize asynchronously; wait for it to land.
	await _tree().process_frame
	await _tree().process_frame
	var ok: bool = window.mode == Window.MODE_MAXIMIZED
	var modes: Array = [window.mode]
	# The main menu embeds the template StartUp node, so loading it really
	# calls set_from_config_and_window(get_window()) on the root window.
	var menu: Node = await _spawn_scene(MAIN_MENU_PATH)
	ok = ok and menu != null and window.mode == Window.MODE_MAXIMIZED
	modes.append(window.mode)
	if menu != null:
		menu.free()
	# The versus scene has no StartUp node: battle entry must not replay the
	# stored video settings either.
	var versus: Node = await _spawn_scene(VERSUS_SCENE_PATH)
	ok = ok and versus != null and window.mode == Window.MODE_MAXIMIZED
	modes.append(window.mode)
	if versus != null:
		versus.free()
	# Returning to the main menu fires StartUp again.
	var menu_again: Node = await _spawn_scene(MAIN_MENU_PATH)
	ok = ok and menu_again != null and window.mode == Window.MODE_MAXIMIZED
	modes.append(window.mode)
	if menu_again != null:
		menu_again.free()
	if not ok:
		ctx["total"] = int(ctx["total"]) + 1
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: maximized_survives_menu_and_versus_loads (modes start,after_menu,after_versus,after_menu2=%s)" % str(modes))
		return
	_case(ctx, "maximized_survives_menu_and_versus_loads", ok)


static func _case_windowed_size_not_reverted(ctx: Dictionary, degraded: bool) -> void:
	if degraded:
		_skip(ctx, "windowed_size_not_reverted_by_menu_load", "headless-degraded: no real window state")
		return
	var window: Window = _tree().root
	# Same real-window warmup as the maximize case: state assigned before
	# the first frames ran never reaches the window manager.
	await _tree().process_frame
	await _tree().process_frame
	window.mode = Window.MODE_WINDOWED
	window.size = WINDOWED_SIZE
	await _tree().process_frame
	await _tree().process_frame
	# The size_changed hook already wrote the new size into the config, so
	# the StartUp replay must not move the window away from it.
	var ok: bool = window.size == WINDOWED_SIZE
	var menu: Node = await _spawn_scene(MAIN_MENU_PATH)
	ok = ok and menu != null and window.size == WINDOWED_SIZE
	if menu != null:
		menu.free()
	_case(ctx, "windowed_size_not_reverted_by_menu_load", ok)


static func _case_maximized_size_not_recorded(ctx: Dictionary, degraded: bool) -> void:
	if degraded:
		_skip(ctx, "maximized_size_not_recorded_to_config", "headless-degraded: no real window state")
		return
	var window: Window = _tree().root
	# Same real-window warmup as the other real cases.
	await _tree().process_frame
	await _tree().process_frame
	# Establish a known windowed size first: the size_changed hook records
	# it (the window is not maximized), giving the assertion a baseline.
	window.mode = Window.MODE_WINDOWED
	window.size = WINDOWED_SIZE
	await _tree().process_frame
	await _tree().process_frame
	var recorded: Vector2i = PlayerConfig.get_config(AppSettings.VIDEO_SECTION, AppSettings.SCREEN_RESOLUTION, Vector2i(-1, -1))
	var ok: bool = recorded == WINDOWED_SIZE
	# Maximizing resizes the window through the WM; that viewport size is a
	# transient, not the player's chosen size, and must not overwrite the
	# recorded one (sweep-report-v2 MINOR-2, owner decision "fix").
	window.mode = Window.MODE_MAXIMIZED
	await _tree().process_frame
	await _tree().process_frame
	ok = ok and window.mode == Window.MODE_MAXIMIZED
	var after: Vector2i = PlayerConfig.get_config(AppSettings.VIDEO_SECTION, AppSettings.SCREEN_RESOLUTION, Vector2i(-1, -1))
	ok = ok and after == WINDOWED_SIZE
	# Leave the module the way later cases expect it: windowed again.
	window.mode = Window.MODE_WINDOWED
	await _tree().process_frame
	await _tree().process_frame
	if not ok:
		ctx["total"] = int(ctx["total"]) + 1
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: maximized_size_not_recorded_to_config (recorded=%s after=%s)" % [str(recorded), str(after)])
		return
	_case(ctx, "maximized_size_not_recorded_to_config", ok)


static func _case_video_controls_coexist(ctx: Dictionary, degraded: bool) -> void:
	var ok: bool = true
	# Headless keeps the root window minimized regardless of mode changes, so
	# the AppSettings window-mode behavior is asserted on a regular Window.
	var probe_window := Window.new()
	_tree().root.add_child(probe_window)
	AppSettings.set_fullscreen_enabled(true, probe_window)
	ok = ok and probe_window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	AppSettings.set_fullscreen_enabled(false, probe_window)
	ok = ok and probe_window.mode == Window.MODE_WINDOWED
	# Resolution roundtrip through the template config path.
	AppSettings.set_resolution(PROBE_RESOLUTION, probe_window)
	ok = ok and AppSettings.get_resolution(probe_window) == PROBE_RESOLUTION
	probe_window.free()
	# V-Sync roundtrip on the main window id. The headless display server
	# cannot observe vsync modes, so only the real-window run toggles it.
	var vsync_before := AppSettings.get_vsync()
	if not degraded:
		var vsync_target: DisplayServer.VSyncMode = DisplayServer.VSYNC_DISABLED \
			if int(vsync_before) == int(DisplayServer.VSYNC_ENABLED) else DisplayServer.VSYNC_ENABLED
		AppSettings.set_vsync(vsync_target)
		ok = ok and AppSettings.get_vsync() == vsync_target
	AppSettings.set_vsync(vsync_before)
	ok = ok and AppSettings.get_vsync() == vsync_before
	_case(ctx, "fullscreen_resolution_vsync_controls_coexist", ok)


static func _case_app_settings_has_maximize_guard(ctx: Dictionary) -> void:
	# Static assertion for the degraded run: both guards must be present in
	# the vendored AppSettings source (fullscreen replay + size replay).
	var text: String = FileAccess.get_file_as_string(APP_SETTINGS_PATH)
	var ok: bool = text.count("Window.MODE_MAXIMIZED") >= MIN_GUARD_HITS
	_case(ctx, "app_settings_keeps_maximize_guards", ok)
