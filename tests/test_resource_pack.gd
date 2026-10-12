extends SceneTree
## Resource packs (scripts/resource_pack.gd, scripts/pack_runtime.gd): the
## default pack names every asset the game scenes ask for, a pack dropped into
## user://packs overrides entry by entry and falls back to the default for the
## rest, the choice is remembered, and the runtime applies the pack to the
## menus (theme, interface sounds, the mode select's pack button).

const MODULE_NAME: String = "resource_pack"

const DEFAULT_MANIFEST: String = "res://packs/default/pack.json"
const TEST_PACK_ID: String = "zz_test_pack"
const TEST_PACK_DIR: String = "user://packs/zz_test_pack"
const MODE_SELECT_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const SCENE_SCRIPTS: Array[String] = ["res://scripts/main.gd", "res://scripts/versus.gd"]


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d resource pack cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("RESOURCE PACK TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _tree().process_frame
	var had_choice: bool = PlayerConfig.has_section_key(ResourcePack.CONFIG_SECTION, ResourcePack.CONFIG_KEY)
	var saved_choice: Array[String] = ResourcePack.enabled_ids()
	ResourcePack.set_active(ResourcePack.DEFAULT_ID)
	_case_default_pack_covers_every_scene_request(ctx)
	_case_scene_scripts_name_no_asset(ctx)
	_install_test_pack()
	_case_user_pack_overrides_and_falls_back(ctx)
	await _case_mode_select_button_cycles_packs(ctx)
	_case_runtime_styles_menus_and_interface_sounds(ctx)
	_remove_test_pack()
	_case_icon_pack_brings_every_part(ctx)
	_case_template_pack_is_complete(ctx)
	_case_versus_side_shows_attack_per_second(ctx)
	# Put the player's own choice back.
	if had_choice:
		ResourcePack.set_enabled(saved_choice)
	else:
		ResourcePack.set_active(ResourcePack.DEFAULT_ID)
		PlayerConfig.erase_section_key(ResourcePack.CONFIG_SECTION, ResourcePack.CONFIG_KEY)
	var runtime: Node = _tree().root.get_node_or_null(^"PackRuntime")
	if runtime != null:
		runtime.apply()
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


## A pack that replaces one color and one sound (the default tetris fanfare
## stands in for "move") and leaves everything else out.
static func _install_test_pack() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_PACK_DIR)
	var wav: FileAccess = FileAccess.open(TEST_PACK_DIR + "/blip.wav", FileAccess.WRITE)
	wav.store_buffer(FileAccess.get_file_as_bytes("res://packs/default/sounds/tetris.wav"))
	wav.close()
	var manifest: FileAccess = FileAccess.open(TEST_PACK_DIR + "/pack.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"format": 1,
		"name": "Test Pack",
		"sounds": {"move": {"file": "blip.wav", "volume_db": -3}, "rotate": "missing.wav"},
		"colors": {"piece_i": "#ff0000", "accent": "not a color"},
	}))
	manifest.close()


static func _remove_test_pack() -> void:
	for file: String in ["blip.wav", "pack.json"]:
		DirAccess.remove_absolute(TEST_PACK_DIR + "/" + file)
	DirAccess.remove_absolute(TEST_PACK_DIR)


static func _case_default_pack_covers_every_scene_request(ctx: Dictionary) -> void:
	var ok: bool = ResourcePack.active_id() == ResourcePack.DEFAULT_ID
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_MANIFEST))
	ok = ok and manifest is Dictionary
	# Every sound event a scene declares, the interface sounds, the track,
	# the fonts and the textures load.
	for script: String in SCENE_SCRIPTS:
		for event: String in (load(script) as GDScript).get_script_constant_map()["SFX_EVENTS"]:
			ok = ok and ResourcePack.sound(event) != null
	for event: String in ["ui_focus", "ui_press"]:
		ok = ok and ResourcePack.sound(event) != null
	ok = ok and ResourcePack.playlist().size() >= 2
	for song: Dictionary in ResourcePack.playlist():
		for track: Dictionary in song["tracks"]:
			ok = ok and ResourcePack.music_file(String(track["file"])) != null
	for key: String in ["main", "mini", "mono"]:
		ok = ok and ResourcePack.font(key) is FontFile
	for key: String in ["background", "orb"]:
		ok = ok and ResourcePack.texture(key) != null
	# Every color either script asks for by name is defined and valid.
	var pattern: RegEx = RegEx.new()
	pattern.compile("ResourcePack\\.color\\(\"([a-z_]+)\"\\)")
	var asked: int = 0
	for script: String in SCENE_SCRIPTS + ["res://scripts/resource_pack.gd", "res://scripts/pack_runtime.gd",
			"res://scripts/how_to_play.gd", "res://scenes/menus/mode_select/mode_select.gd"]:
		for found: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(script)):
			asked += 1
			ok = ok and ResourcePack.color(found.get_string(1)) != ResourcePack.MISSING_COLOR
	ok = ok and asked >= 30
	for key: String in ResourcePack.PIECE_COLOR_KEYS + ["tier_easy", "tier_normal", "tier_hard", "tier_lunatic", "garbage"]:
		ok = ok and ResourcePack.color(key) != ResourcePack.MISSING_COLOR
	# The seven pieces keep seven different colors, garbage an eighth.
	var seen: Array[Color] = []
	for value: int in 7:
		ok = ok and not seen.has(ResourcePack.cell_color(value))
		seen.append(ResourcePack.cell_color(value))
	ok = ok and not seen.has(ResourcePack.cell_color(Board.GARBAGE))
	_case(ctx, "default_pack_covers_every_scene_request", ok)


## The bundled "Icon" pack (2026-10-11, owner: an Orthodox icon theme with
## its own interface, blocks and background) and the "Icon FX" pack that goes
## with it (its effects) replace all four and leave the rest - the music, the
## sounds, the layouts - to the default pack.
static func _case_icon_pack_brings_every_part(ctx: Dictionary) -> void:
	var plain_accent: Color = ResourcePack.color("accent")
	ResourcePack.set_enabled(["icon"], false)
	# Alone the theme has no effects of its own: those are the other pack.
	var ok: bool = ResourcePack.enabled_ids().has("icon") and ResourcePack.effect("tetris").is_empty()
	ResourcePack.set_enabled(["iconfx", "icon"], false)
	ok = ok and ResourcePack.enabled_ids().has("iconfx")
	var atlas: Texture2D = ResourcePack.blocks().get("atlas_texture") as Texture2D
	ok = ok and atlas != null and atlas.resource_path.begins_with("res://packs/icon/") and atlas.get_width() == atlas.get_height() * 9
	for event: String in ResourcePack.EFFECT_EVENTS:
		var effect: Dictionary = ResourcePack.effect(event)
		ok = ok and not effect.is_empty() and (effect["texture"] as Texture2D).resource_path.begins_with("res://packs/iconfx/fx/")
	var backdrop: Dictionary = ResourcePack.backdrop()
	ok = ok and not backdrop.is_empty() and (backdrop["texture"] as Texture2D).resource_path == "res://packs/icon/backdrop.png" \
		and int(backdrop["frames"]) >= 24
	for key: String in ["panel", "card", "button", "button_hover", "button_pressed", "button_focus"]:
		ok = ok and ResourcePack._box(key, Color.BLACK, Color.BLACK, 1) is StyleBoxTexture
	ok = ok and ResourcePack.color("accent") != plain_accent and ResourcePack.color("accent") != ResourcePack.MISSING_COLOR
	var seen: Array[Color] = []
	for value: int in 7:
		ok = ok and not seen.has(ResourcePack.cell_color(value))
		seen.append(ResourcePack.cell_color(value))
	# What it does not bring is still there.
	ok = ok and ResourcePack.playlist().size() >= 2 and ResourcePack.sound("move") != null and ResourcePack.layout("versus_hud") != null
	ResourcePack.set_enabled([], false)
	ok = ok and (ResourcePack.backdrop()["texture"] as Texture2D).resource_path == "res://packs/default/backdrop.png"
	_case(ctx, "icon_packs_bring_interface_blocks_effects_and_backdrop", ok)


## The pack template handed to artists (packs/template, 2026-10-11) is a
## working pack that holds every visual part itself and comes with its guide.
static func _case_template_pack_is_complete(ctx: Dictionary) -> void:
	ResourcePack.set_enabled(["template"], false)
	var home: String = "res://packs/template/"
	var ok: bool = ResourcePack.enabled_ids().has("template") and FileAccess.file_exists(home + "说明.md")
	ok = ok and (ResourcePack.blocks().get("atlas_texture") as Texture2D).resource_path == home + "blocks.png"
	for event: String in ResourcePack.EFFECT_EVENTS:
		var effect: Dictionary = ResourcePack.effect(event)
		ok = ok and not effect.is_empty() and (effect["texture"] as Texture2D).resource_path == home + "fx/" + event + ".png"
	ok = ok and (ResourcePack.backdrop()["texture"] as Texture2D).resource_path == home + "backdrop.png"
	ok = ok and (ResourcePack.title()["texture"] as Texture2D).resource_path == home + "title.png"
	ok = ok and ResourcePack.texture("background").resource_path == home + "background.png"
	for key: String in ["panel", "card", "button", "button_hover", "button_pressed", "button_focus"]:
		ok = ok and ResourcePack._box(key, Color.BLACK, Color.BLACK, 1) is StyleBoxTexture
	# Every color the default pack names is in it, and in its guide.
	var stock: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_MANIFEST)) as Dictionary)["colors"]
	var listed: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(home + "pack.json")) as Dictionary)["colors"]
	var guide: String = FileAccess.get_file_as_string(home + "说明.md")
	for key: String in stock:
		ok = ok and listed.has(key) and guide.contains("`%s`" % key)
	ResourcePack.set_enabled([], false)
	_case(ctx, "template_pack_is_complete_and_documented", ok)


## The versus side shows the attack sent per second (2026-10-12, owner) in
## its ApsValue label; a pack layout made before that label existed still
## works, it just does not show the number.
static func _case_versus_side_shows_attack_per_second(ctx: Dictionary) -> void:
	var side: VersusSide = ResourcePack.layout("versus_side").instantiate() as VersusSide
	side.bind()
	side.set_stats(12, 2, 1.5, true, 0, 0.4567)
	var ok: bool = side.aps_value != null and side.aps_value.text == "0.46" and side.pps_value.text == "1.50"
	side.free()
	var old: VersusSide = ResourcePack.layout("versus_side").instantiate() as VersusSide
	var label: Node = old.get_node(^"%ApsValue")
	label.get_parent().remove_child(label)
	label.free()
	old.bind()
	old.set_stats(12, 2, 1.5, true, 0, 0.4567)
	ok = ok and old.aps_value == null and old.sent_value.text == "12" and not VersusSide.REQUIRED_NODES.has("ApsValue")
	old.free()
	_case(ctx, "versus_side_shows_attack_per_second", ok)


static func _case_scene_scripts_name_no_asset(ctx: Dictionary) -> void:
	var ok: bool = true
	for script: String in SCENE_SCRIPTS:
		var text: String = FileAccess.get_file_as_string(script)
		for needle: String in ["res://assets", "res://addons/kenney", ".ogg", ".wav", ".ttf", ".png"]:
			ok = ok and not text.contains(needle)
	_case(ctx, "game_scene_scripts_name_no_asset_file", ok)


static func _case_user_pack_overrides_and_falls_back(ctx: Dictionary) -> void:
	var ids: Array[String] = []
	for pack: Dictionary in ResourcePack.list_packs():
		ids.append(String(pack["id"]))
	var ok: bool = ids.size() >= 2 and ids[0] == ResourcePack.DEFAULT_ID and ids.has(TEST_PACK_ID)
	var default_move: AudioStream = ResourcePack.sound("move")
	var default_rotate: AudioStream = ResourcePack.sound("rotate")
	var default_lock: AudioStream = ResourcePack.sound("lock")
	var default_accent: Color = ResourcePack.color("accent")
	ResourcePack.set_active(TEST_PACK_ID)
	ok = ok and ResourcePack.active_id() == TEST_PACK_ID and ResourcePack.active_name() == "Test Pack"
	# Replaced entries: read straight from the pack folder.
	ok = ok and ResourcePack.color("piece_i") == Color.html("#ff0000")
	var move: AudioStream = ResourcePack.sound("move")
	ok = ok and move is AudioStreamWAV and move != default_move and move.get_length() > 0.5
	ok = ok and ResourcePack.sound_volume("move") == -3.0
	# Left out, named but missing, or malformed: the default stands in.
	ok = ok and ResourcePack.sound("lock") == default_lock
	ok = ok and ResourcePack.sound("rotate") == default_rotate
	ok = ok and ResourcePack.color("accent") == default_accent
	ok = ok and ResourcePack.color("piece_o") != ResourcePack.MISSING_COLOR and ResourcePack.font("main") is FontFile
	# The choice is remembered; an unknown pack reads as the default.
	ok = ok and PlayerConfig.get_config(ResourcePack.CONFIG_SECTION, ResourcePack.CONFIG_KEY, []) == [TEST_PACK_ID]
	ResourcePack.reload()
	ok = ok and ResourcePack.active_id() == TEST_PACK_ID
	ResourcePack.set_active("no_such_pack")
	ok = ok and ResourcePack.active_id() == ResourcePack.DEFAULT_ID and ResourcePack.sound("move") == default_move
	_case(ctx, "user_pack_overrides_entry_by_entry_and_falls_back", ok)


# Revised 2026-10-10 (owner: a Minecraft-style pack screen) and 2026-10-11
# (owner: the entry moved from the mode select to the main menu): the main
# menu's button opens the pack screen. Available packs sit on the left, enabled ones
# on the right in priority order above the fixed default; nothing is applied
# until Done.
static func _case_mode_select_button_cycles_packs(ctx: Dictionary) -> void:
	ResourcePack.set_enabled([])
	var select: Node = (load(MAIN_MENU_PATH) as PackedScene).instantiate()
	_tree().root.add_child(select)
	var loader: LoaderStub = LoaderStub.new()
	select.scene_loader_node = loader
	await _tree().process_frame
	var button: Button = select.find_child("ResourcePackButton", true, false) as Button
	var entries: MainMenuEntries = select.get_node_or_null(^"MainMenuEntries") as MainMenuEntries
	var screen: PackSelect = entries.pack_select() if entries != null else null
	var ok: bool = button != null and button.is_visible_in_tree() and screen != null and not screen.visible
	if ok:
		button.pressed.emit()
		ok = ok and screen.visible and screen.enabled_ids().is_empty()
		ok = ok and screen.available_list.find_child("Pack_" + TEST_PACK_ID, false, false) != null
		ok = ok and screen.available_list.find_child("Pack_pixel", false, false) != null
		# The default pack is the fixed last row of the enabled list.
		var default_row: PackRow = screen.enabled_list.get_child(screen.enabled_list.get_child_count() - 1) as PackRow
		ok = ok and default_row.pack_id == ResourcePack.DEFAULT_ID and not default_row.move_button.visible
		# Enable two packs: the later one goes on top; then swap them.
		(screen.available_list.find_child("Pack_" + TEST_PACK_ID, false, false) as PackRow).move_button.pressed.emit()
		(screen.available_list.find_child("Pack_pixel", false, false) as PackRow).move_button.pressed.emit()
		ok = ok and screen.enabled_ids() == ["pixel", TEST_PACK_ID]
		(screen.enabled_list.find_child("Pack_pixel", false, false) as PackRow).down_button.pressed.emit()
		ok = ok and screen.enabled_ids() == [TEST_PACK_ID, "pixel"]
		ok = ok and (screen.enabled_list.get_child(0) as PackRow).pack_id == TEST_PACK_ID
		# Nothing is applied before Done.
		ok = ok and ResourcePack.enabled_ids().is_empty() and loader.loaded.is_empty()
		screen.done_button.pressed.emit()
		ok = ok and not screen.visible and ResourcePack.enabled_ids() == [TEST_PACK_ID, "pixel"]
		# Layered lookup: the top pack's red I piece, the pixel pack's blocks
		# underneath it, everything else from the default.
		ok = ok and ResourcePack.color("piece_i") == Color.html("#ff0000")
		ok = ok and ResourcePack.color("piece_o") == Color.html("#f8d820")
		ok = ok and String(ResourcePack.blocks().get("filter", "")) == "nearest"
		ok = ok and ResourcePack.sound("lock") != null
		# The menu reloads itself so its own layout follows the packs.
		ok = ok and loader.loaded.size() == 1
		# Done without a change applies nothing.
		screen.open()
		screen.done_button.pressed.emit()
		ok = ok and loader.loaded.size() == 1
		# A saved single id from an older version still reads.
		PlayerConfig.set_config(ResourcePack.CONFIG_SECTION, ResourcePack.CONFIG_KEY, "pixel")
		ResourcePack.reload()
		ok = ok and ResourcePack.enabled_ids() == ["pixel"]
	select.free()
	ResourcePack.set_enabled([])
	await _tree().process_frame
	_case(ctx, "pack_screen_enables_orders_and_applies_on_done", ok)


class LoaderStub:
	extends Node

	var loaded: Array[String] = []

	func load_scene(path: String) -> void:
		loaded.append(path)


static func _case_runtime_styles_menus_and_interface_sounds(ctx: Dictionary) -> void:
	var runtime: Node = _tree().root.get_node_or_null(^"PackRuntime")
	var ok: bool = runtime != null
	if ok:
		ResourcePack.set_active(ResourcePack.DEFAULT_ID)
		runtime.apply()
		var probe: Button = Button.new()
		_tree().root.add_child(probe)
		var box: StyleBoxFlat = probe.get_theme_stylebox("normal") as StyleBoxFlat
		ok = ok and box != null and box.bg_color == ResourcePack.color("button_fill")
		ok = ok and probe.get_theme_color("font_color") == ResourcePack.color("button_text")
		probe.free()
		var controller: Node = _tree().root.get_node_or_null(^"ProjectUISoundController")
		ok = ok and controller != null
		if controller != null:
			ok = ok and (controller.button_pressed_player as AudioStreamPlayer).stream == ResourcePack.sound("ui_press")
			ok = ok and (controller.button_focused_player as AudioStreamPlayer).stream == ResourcePack.sound("ui_focus")
		# Switching the pack restyles at once.
		ResourcePack.set_active(TEST_PACK_ID)
		runtime.apply()
		ok = ok and (runtime._backdrop as CanvasLayer).layer < 0
		ResourcePack.set_active(ResourcePack.DEFAULT_ID)
		runtime.apply()
	_case(ctx, "runtime_styles_menus_and_interface_sounds", ok)
