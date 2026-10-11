extends SceneTree

const MODULE_NAME: String = "settings"

# O-04 machine assertions: the template settings paths must change runtime
# state immediately and persist across sessions through the template config
# file (owner BQ-05: user://player_config.cfg). The module is headless and
# repeatable: every touched setting (config file, InputMap, bus volumes and
# mutes, window mode/size) is snapshotted first and restored afterwards so
# the local player configuration survives the suite.
const CONFIG_LOCATION: String = "user://player_config.cfg"
const OPTIONS_WINDOW_PATH: String = "res://scenes/windows/main_menu_options_window.tscn"
const AUDIO_MENU_PATH: String = "res://scenes/menus/options_menu/audio/audio_options_menu.tscn"
const VIDEO_MENU_PATH: String = "res://scenes/menus/options_menu/video/video_options_menu_with_extras.tscn"
const START_UP_PATH: String = "res://addons/maaacks_game_template/base/nodes/config/start_up/start_up.gd"
const REMAP_ACTION: String = "move_left"
const REMAP_PHYSICAL_KEYCODE: int = 81 # KEY_Q, unused by the frozen nine gameplay actions
const PERSISTED_SFX_LINEAR: float = 0.4
const AUDIO_EPSILON: float = 0.001
const DB_EPSILON: float = 0.05
const REQUIRED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),
	Vector2i(1152, 648),
	Vector2i(1920, 1080),
]
const BUS_NAMES: Array[String] = ["SFX", "Music", "BGM"]


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d settings cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("SETTINGS TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var snapshot: Dictionary = _snapshot_state()
	await _case_config_interface_and_option_scenes(ctx)
	await _case_audio_bus_layout(ctx)
	await _case_bus_volume_applies_immediately(ctx)
	await _case_audio_options_menu_slider_path(ctx)
	await _case_input_remap_template_path(ctx)
	await _case_fullscreen_toggle_applies(ctx)
	await _case_video_menu_resolution_options(ctx)
	await _case_video_menu_resolution_selection(ctx)
	await _case_persistence_roundtrip(ctx)
	_restore_state(snapshot)
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


static func _spawn_scene(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		return null
	var instance: Node = packed.instantiate()
	_tree().root.add_child(instance)
	await _tree().process_frame
	return instance


static func _initial_linear_factor(bus_index: int) -> float:
	if AppSettings.initial_bus_volumes.size() > bus_index:
		return float(AppSettings.initial_bus_volumes[bus_index])
	return 1.0


static func _event_keycode(value: Variant) -> int:
	if value is InputEventKey:
		return int((value as InputEventKey).physical_keycode)
	if value is Array and not (value as Array).is_empty():
		return _event_keycode((value as Array)[0])
	return -1


static func _read_config_bytes() -> PackedByteArray:
	if not FileAccess.file_exists(CONFIG_LOCATION):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(CONFIG_LOCATION)


static func _snapshot_input_map() -> Dictionary:
	var snapshot: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var events: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event)
		snapshot[action] = events
	return snapshot


static func _snapshot_state() -> Dictionary:
	var bus_volumes: Array[float] = []
	var bus_mutes: Array[bool] = []
	for bus_index: int in range(AudioServer.bus_count):
		bus_volumes.append(AudioServer.get_bus_volume_db(bus_index))
		bus_mutes.append(AudioServer.is_bus_mute(bus_index))
	var defaults: Variant = AppSettings.default_action_events
	var default_events_snapshot: Variant = null
	if defaults is Dictionary:
		default_events_snapshot = (defaults as Dictionary).duplicate(true)
	var window: Window = _tree().root
	return {
		"config_exists": FileAccess.file_exists(CONFIG_LOCATION),
		"config_bytes": _read_config_bytes(),
		"input_map": _snapshot_input_map(),
		"bus_volumes": bus_volumes,
		"bus_mutes": bus_mutes,
		"initial_bus_volumes": AppSettings.initial_bus_volumes.duplicate(),
		"default_action_events": default_events_snapshot,
		"window_mode": window.mode,
		"window_size": window.size,
	}


static func _restore_config_file(snapshot: Dictionary) -> void:
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


static func _restore_state(snapshot: Dictionary) -> void:
	var bus_volumes: Array = snapshot["bus_volumes"]
	for bus_index: int in range(mini(bus_volumes.size(), AudioServer.bus_count)):
		AudioServer.set_bus_volume_db(bus_index, float(bus_volumes[bus_index]))
	var bus_mutes: Array = snapshot["bus_mutes"]
	for bus_index: int in range(mini(bus_mutes.size(), AudioServer.bus_count)):
		AudioServer.set_bus_mute(bus_index, bool(bus_mutes[bus_index]))
	var input_map: Dictionary = snapshot["input_map"]
	for action: StringName in input_map:
		InputMap.action_erase_events(action)
		for event: InputEvent in (input_map[action] as Array):
			InputMap.action_add_event(action, event)
	AppSettings.initial_bus_volumes.clear()
	AppSettings.initial_bus_volumes.append_array(snapshot["initial_bus_volumes"] as Array)
	var default_events: Variant = snapshot["default_action_events"]
	if default_events is Dictionary:
		AppSettings.default_action_events = default_events
	# Restore the window before the config file: applying the saved size may
	# still run the template size_changed hook, which saves the config file.
	var window: Window = _tree().root
	window.mode = snapshot["window_mode"]
	window.size = snapshot["window_size"]
	_restore_config_file(snapshot)


static func _case_config_interface_and_option_scenes(ctx: Dictionary) -> void:
	var ok: bool = PlayerConfig.CONFIG_FILE_LOCATION == CONFIG_LOCATION
	ok = ok and AppSettings.INPUT_SECTION == &"InputSettings"
	ok = ok and AppSettings.AUDIO_SECTION == &"AudioSettings"
	ok = ok and AppSettings.VIDEO_SECTION == &"VideoSettings"
	ok = ok and AppSettings.FULLSCREEN == &"Fullscreen"
	ok = ok and AppSettings.SCREEN_RESOLUTION == &"ScreenResolution"
	for scene_path: String in [OPTIONS_WINDOW_PATH, AUDIO_MENU_PATH, VIDEO_MENU_PATH]:
		var packed: PackedScene = load(scene_path) as PackedScene
		ok = ok and packed != null and packed.can_instantiate()
	# The template StartUp node is what reapplies the config file on launch.
	var start_up_text: String = FileAccess.get_file_as_string(START_UP_PATH)
	ok = ok and start_up_text.contains("set_from_config_and_window")
	_case(ctx, "config_interface_and_option_scenes_available", ok)


static func _case_audio_bus_layout(ctx: Dictionary) -> void:
	var music_index: int = AudioServer.get_bus_index("Music")
	var sfx_index: int = AudioServer.get_bus_index("SFX")
	var bgm_index: int = AudioServer.get_bus_index("BGM")
	var ok: bool = music_index != -1 and sfx_index != -1 and bgm_index != -1
	ok = ok and music_index != sfx_index and sfx_index != bgm_index
	_case(ctx, "audio_bus_layout_has_music_sfx_bgm", ok)


static func _case_bus_volume_applies_immediately(ctx: Dictionary) -> void:
	var ok: bool = true
	for bus_name: String in BUS_NAMES:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index == -1:
			ok = false
			continue
		var before_db: float = AudioServer.get_bus_volume_db(bus_index)
		var before_linear: float = AppSettings.get_bus_volume(bus_index)
		var target: float = 0.3 if absf(before_linear - 0.3) > 0.01 else 0.7
		AppSettings.set_bus_volume(bus_index, target)
		var after_db: float = AudioServer.get_bus_volume_db(bus_index)
		var after_linear: float = AppSettings.get_bus_volume(bus_index)
		# No frame is awaited: the change must already be visible on the bus.
		ok = ok and not is_equal_approx(before_db, after_db)
		ok = ok and absf(after_linear - target) <= AUDIO_EPSILON
		ok = ok and absf(after_db - linear_to_db(target * _initial_linear_factor(bus_index))) <= DB_EPSILON
		AppSettings.set_bus_volume(bus_index, before_linear)
		ok = ok and absf(AudioServer.get_bus_volume_db(bus_index) - before_db) <= DB_EPSILON
	_case(ctx, "audio_bus_volume_changes_apply_immediately", ok)


static func _case_audio_options_menu_slider_path(ctx: Dictionary) -> void:
	var ok: bool = true
	var menu: Node = await _spawn_scene(AUDIO_MENU_PATH)
	var container: Node = null
	if menu != null:
		container = menu.get_node_or_null("%AudioControlContainer")
	ok = ok and menu != null and container != null
	var sfx_control: OptionControl = null
	var control_names: Array[String] = []
	if container != null:
		# Bus sliders are added through call_deferred by the template menu.
		for _frame: int in range(3):
			await _tree().process_frame
		for child: Node in container.get_children():
			if child is OptionControl:
				var option_name: String = String((child as OptionControl).option_name)
				control_names.append(option_name)
				if option_name == "SFX":
					sfx_control = child
	for bus_name: String in ["Music", "SFX", "BGM"]:
		ok = ok and bus_name in control_names
	var sfx_index: int = AudioServer.get_bus_index("SFX")
	if sfx_control != null and sfx_index != -1:
		var before_linear: float = AppSettings.get_bus_volume(sfx_index)
		var target: float = 0.25 if absf(before_linear - 0.25) > 0.01 else 0.55
		sfx_control.set_value(target)
		var after_linear: float = AppSettings.get_bus_volume(sfx_index)
		ok = ok and absf(after_linear - target) <= AUDIO_EPSILON
		ok = ok and absf(AudioServer.get_bus_volume_db(sfx_index) - linear_to_db(target * _initial_linear_factor(sfx_index))) <= DB_EPSILON
		var recorded: Variant = PlayerConfig.get_config(String(AppSettings.AUDIO_SECTION), "Sfx", -1.0)
		ok = ok and absf(float(recorded) - target) <= AUDIO_EPSILON
		AppSettings.set_bus_volume(sfx_index, before_linear)
	else:
		ok = false
	if menu != null:
		menu.free()
	_case(ctx, "audio_options_menu_slider_changes_sfx_bus", ok)


static func _case_input_remap_template_path(ctx: Dictionary) -> void:
	var ok: bool = InputMap.has_action(REMAP_ACTION)
	var original_events: Array = InputMap.action_get_events(REMAP_ACTION)
	# Avoid AppSettings.get_config_input_events(action, null): the template
	# signature promises Array and errors when the key is absent.
	var had_config: bool = PlayerConfig.has_section_key(String(AppSettings.INPUT_SECTION), REMAP_ACTION)
	var original_config: Variant = null
	if had_config:
		original_config = PlayerConfig.get_config(String(AppSettings.INPUT_SECTION), REMAP_ACTION, [])
	var new_event := InputEventKey.new()
	new_event.physical_keycode = REMAP_PHYSICAL_KEYCODE
	# Template remap path (see input_actions_list._assign_input_event_to_action_group).
	InputMap.action_erase_events(REMAP_ACTION)
	InputMap.action_add_event(REMAP_ACTION, new_event)
	AppSettings.set_config_input_events(REMAP_ACTION, InputMap.action_get_events(REMAP_ACTION))
	ok = ok and InputMap.action_has_event(REMAP_ACTION, new_event)
	ok = ok and InputMap.event_is_action(new_event, REMAP_ACTION)
	var remapped_events: Array = InputMap.action_get_events(REMAP_ACTION)
	ok = ok and remapped_events.size() == 1 and _event_keycode(remapped_events[0]) == REMAP_PHYSICAL_KEYCODE
	for original_event: InputEvent in original_events:
		ok = ok and not InputMap.action_has_event(REMAP_ACTION, original_event)
	var config_events: Variant = AppSettings.get_config_input_events(REMAP_ACTION, [])
	ok = ok and config_events is Array and (config_events as Array).size() == 1
	ok = ok and _event_keycode(config_events) == REMAP_PHYSICAL_KEYCODE
	# Restore the frozen mapping and the previous config entry.
	InputMap.action_erase_events(REMAP_ACTION)
	for original_event: InputEvent in original_events:
		InputMap.action_add_event(REMAP_ACTION, original_event)
	if original_config == null:
		PlayerConfig.erase_section_key(String(AppSettings.INPUT_SECTION), REMAP_ACTION)
	else:
		AppSettings.set_config_input_events(REMAP_ACTION, original_config)
	var restored: Array = InputMap.action_get_events(REMAP_ACTION)
	ok = ok and restored.size() == original_events.size()
	if restored.size() == original_events.size():
		for i: int in range(restored.size()):
			ok = ok and _event_keycode(restored[i]) == _event_keycode(original_events[i])
	_case(ctx, "input_remap_template_path_applies_and_restores", ok)


static func _case_fullscreen_toggle_applies(ctx: Dictionary) -> void:
	var ok: bool = true
	# Headless keeps the root window minimized regardless of mode changes, so
	# the AppSettings window-mode behavior is asserted on a regular Window.
	var probe_window := Window.new()
	_tree().root.add_child(probe_window)
	AppSettings.set_fullscreen_enabled(true, probe_window)
	ok = ok and AppSettings.is_fullscreen(probe_window)
	ok = ok and probe_window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	AppSettings.set_fullscreen_enabled(false, probe_window)
	ok = ok and not AppSettings.is_fullscreen(probe_window)
	ok = ok and probe_window.mode == Window.MODE_WINDOWED
	probe_window.free()
	# Template video menu toggle path: the check button writes VideoSettings
	# and forwards the value to AppSettings through the scene connection.
	var menu: Node = await _spawn_scene(VIDEO_MENU_PATH)
	var fullscreen_control: OptionControl = null
	if menu != null:
		fullscreen_control = menu.find_child("FullscreenControl", true, false) as OptionControl
	var check_button: CheckButton = null
	if fullscreen_control != null:
		check_button = fullscreen_control.find_child("CheckButton", true, false) as CheckButton
	ok = ok and fullscreen_control != null and check_button != null
	if fullscreen_control != null:
		var handler_wired: bool = false
		for connection: Dictionary in fullscreen_control.setting_changed.get_connections():
			if (connection["callable"] as Callable).get_method() == "_on_fullscreen_control_setting_changed":
				handler_wired = true
		ok = ok and handler_wired
	if check_button != null:
		check_button.button_pressed = true
		ok = ok and bool(PlayerConfig.get_config(String(AppSettings.VIDEO_SECTION), AppSettings.FULLSCREEN, false))
		check_button.button_pressed = false
		ok = ok and not bool(PlayerConfig.get_config(String(AppSettings.VIDEO_SECTION), AppSettings.FULLSCREEN, true))
	if menu != null:
		menu.free()
	_case(ctx, "fullscreen_toggle_applies_via_api_and_menu", ok)


static func _case_video_menu_resolution_options(ctx: Dictionary) -> void:
	var ok: bool = true
	var menu: Node = await _spawn_scene(VIDEO_MENU_PATH)
	var resolution_control: Node = null
	if menu != null:
		resolution_control = menu.find_child("ResolutionControl", true, false)
	ok = ok and resolution_control is ListOptionControl
	if resolution_control is ListOptionControl:
		var values: Array = (resolution_control as ListOptionControl).option_values
		for required: Vector2i in REQUIRED_RESOLUTIONS:
			ok = ok and required in values
	if menu != null:
		menu.free()
	_case(ctx, "video_menu_resolution_offers_three_required_tiers", ok)


static func _case_video_menu_resolution_selection(ctx: Dictionary) -> void:
	var ok: bool = true
	var menu: Node = await _spawn_scene(VIDEO_MENU_PATH)
	var resolution_control: ListOptionControl = null
	if menu != null:
		resolution_control = menu.find_child("ResolutionControl", true, false) as ListOptionControl
	ok = ok and resolution_control != null
	if resolution_control != null:
		var option_button: OptionButton = resolution_control.find_child("OptionButton", true, false) as OptionButton
		ok = ok and option_button != null
		var target: Vector2i = Vector2i(960, 540)
		# The template prepends the current window size when it is not part of
		# the configured list, so resolve the index against custom_option_values.
		var index: int = (resolution_control.custom_option_values as Array).find(target)
		ok = ok and index >= 0
		if option_button != null and index >= 0:
			option_button.item_selected.emit(index)
			var recorded: Variant = PlayerConfig.get_config(String(AppSettings.VIDEO_SECTION), AppSettings.SCREEN_RESOLUTION, null)
			ok = ok and recorded is Vector2i and (recorded as Vector2i) == target
			ok = ok and AppSettings.get_resolution(_tree().root) == target
	if menu != null:
		menu.free()
	_case(ctx, "video_menu_resolution_selection_records_and_applies", ok)


static func _case_persistence_roundtrip(ctx: Dictionary) -> void:
	var window: Window = _tree().root
	var ok: bool = true
	var sfx_index: int = AudioServer.get_bus_index("SFX")
	ok = ok and sfx_index != -1
	# --- write through the template paths ---
	var new_event := InputEventKey.new()
	new_event.physical_keycode = REMAP_PHYSICAL_KEYCODE
	InputMap.action_erase_events(REMAP_ACTION)
	InputMap.action_add_event(REMAP_ACTION, new_event)
	AppSettings.set_config_input_events(REMAP_ACTION, InputMap.action_get_events(REMAP_ACTION))
	PlayerConfig.set_config(String(AppSettings.AUDIO_SECTION), "Sfx", PERSISTED_SFX_LINEAR)
	# --- the saved file is re-readable from disk ---
	PlayerConfig.config_file = null
	var direct_file := ConfigFile.new()
	ok = ok and direct_file.load(CONFIG_LOCATION) == OK
	ok = ok and _event_keycode(direct_file.get_value(String(AppSettings.INPUT_SECTION), REMAP_ACTION, [])) == REMAP_PHYSICAL_KEYCODE
	ok = ok and absf(float(direct_file.get_value(String(AppSettings.AUDIO_SECTION), "Sfx", -1.0)) - PERSISTED_SFX_LINEAR) <= AUDIO_EPSILON
	# --- simulate a fresh session: runtime state diverges from the file ---
	InputMap.action_erase_events(REMAP_ACTION)
	AudioServer.set_bus_volume_db(sfx_index, -60.0)
	# --- StartUp equivalent: apply config to a window ---
	AppSettings.set_from_config_and_window(window)
	var applied_events: Array = InputMap.action_get_events(REMAP_ACTION)
	ok = ok and applied_events.size() == 1 and _event_keycode(applied_events[0]) == REMAP_PHYSICAL_KEYCODE
	ok = ok and InputMap.event_is_action(new_event, REMAP_ACTION)
	ok = ok and absf(AppSettings.get_bus_volume(sfx_index) - PERSISTED_SFX_LINEAR) <= AUDIO_EPSILON
	ok = ok and absf(AudioServer.get_bus_volume_db(sfx_index) - linear_to_db(PERSISTED_SFX_LINEAR * _initial_linear_factor(sfx_index))) <= DB_EPSILON
	_case(ctx, "settings_persist_and_reapply_from_config", ok)
