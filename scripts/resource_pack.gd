class_name ResourcePack
extends RefCounted
## Resource packs: every sound, music track, font, texture and color the game
## uses is named by a pack's pack.json instead of by the game code, so the
## look and the sound can be replaced without touching a script (the idea of
## a Minecraft resource pack).
##
## A pack is a folder holding a pack.json plus the files it names:
##   res://packs/<id>/   bundled packs ("default" is the built-in one)
##   user://packs/<id>/  packs dropped in next to the save data
## Several packs can be enabled at once, in priority order; a lookup walks
## them top to bottom and ends at the default pack.
## pack.json sections (all optional except in the default pack):
##   sounds    event -> "file" or {"file": ..., "volume_db": ...}
##   music     track -> same shape as a sound
##   fonts     main / mini / mono -> file
##   textures  background / orb -> file
##   colors    name -> "#rrggbb" or "#rrggbbaa"
##   blocks    {"atlas": file, "order": [...]} or {"tile": file}: see
##             scripts/block_skin.gd
##   ui        nine-patch images for panels and buttons:
##             name -> {"file": ..., "margin": pixels}; names: panel, card,
##             button, button_hover, button_pressed, button_focus
##   layouts   name -> scene file: the screens themselves (HUDs, setup page,
##             pack list). See "Layouts" below.
##   effects   board event -> a sprite-sheet animation played at that event:
##             {"sheet": file, "frame": [w, h], "frames": n, "fps": n,
##             "scale": n, "anchor": "center" / "bottom", "glow": 0..1,
##             "replace": bool}. See effect() and scripts/board_fx.gd.
##   title     the animated title of the menus, a sprite sheet:
##             {"sheet": file, "frame": [w, h], "frames": n, "fps": n,
##             "scale": n, "loop_from": frame, "glow": 0..1}. See title().
##   fx        numbers that tune the built-in drawn effects (shake,
##             shards_per_cell, sparks_per_drop): see fx_number().
##
## Layouts: a layout is a .tscn whose root carries one of the game's binding
## scripts (scripts/ui/*.gd). The script lists the unique-named nodes it
## needs (REQUIRED_NODES); everything else in the scene - positions, extra
## decoration, nesting - is the pack's to decide. A layout that fails to load,
## misses a required node or (for packs outside the project) references
## anything but the game's own scripts is skipped and the next pack's layout
## is used, ending at the default pack.
## A file is a path relative to the pack folder, or a full res:// / user://
## path. Whatever a pack leaves out (or names but cannot be loaded) falls back
## to the default pack entry by entry, so a pack may replace a single sound.
##
## Supported files: .wav / .ogg / .mp3 sounds, .png / .jpg / .webp textures,
## .ttf / .otf fonts. The choice is remembered through PlayerConfig.
##
## All state is static: scripts read the pack through the class name, with or
## without the PackRuntime autoload (which applies the pack to the menus).

const DEFAULT_ID: String = "default"
const BUNDLED_DIR: String = "res://packs"
const USER_DIR: String = "user://packs"
const MANIFEST: String = "pack.json"
const CONFIG_SECTION: String = "ResourcePack"
const CONFIG_KEY: String = "Active"
const SFX_BUS: StringName = &"SFX"
## Color keys of the seven pieces, in Tetromino.PieceType order.
const PIECE_COLOR_KEYS: Array[String] = ["piece_i", "piece_o", "piece_t", "piece_s", "piece_z", "piece_j", "piece_l"]
## CJK glyphs for fonts loaded from outside the project.
const CJK_FALLBACK_FONT: String = "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"
const MISSING_COLOR: Color = Color(1.0, 0.0, 1.0)
## Scripts a layout scene of a pack outside the project may reference.
const LAYOUT_SCRIPT_ROOT: String = "res://scripts/"
const LAYOUT_NEST_LIMIT: int = 4

static var _loaded: bool = false
## Enabled packs, highest priority first; the default pack always closes the
## list. Each entry: {"id", "manifest", "dir"}.
static var _stack: Array[Dictionary] = []
## "section/key" -> loaded resource (null entries are cached too).
static var _cache: Dictionary = {}
static var _colors: Dictionary = {}
## Bumped whenever the enabled packs change; views compare it to know that
## the pack data they cached is stale.
static var _revision: int = 0


# ---------------------------------------------------------------------------
# Pack selection
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var stored: Variant = PlayerConfig.get_config(CONFIG_SECTION, CONFIG_KEY, [])
	# Older saves hold a single pack id.
	var ids: Array = stored if stored is Array else [stored]
	_build_stack(ids)


## Ids of the enabled packs, highest priority first (the default pack, which
## is always underneath, is not listed).
static func enabled_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	for entry: Dictionary in _stack:
		if entry["id"] != DEFAULT_ID:
			ids.append(String(entry["id"]))
	return ids


## The pack on top (the default when nothing else is enabled).
static func active_id() -> String:
	ensure_loaded()
	return String(_stack[0]["id"])


static func active_name() -> String:
	ensure_loaded()
	return String((_stack[0]["manifest"] as Dictionary).get("name", _stack[0]["id"]))


static func revision() -> int:
	return _revision


## Every pack that can be chosen: [{id, name, description, dir, icon}], the
## default first. A user pack hides a bundled pack with the same id.
static func list_packs() -> Array[Dictionary]:
	var found: Dictionary = {}
	for base: String in [BUNDLED_DIR, USER_DIR]:
		for id: String in DirAccess.get_directories_at(base):
			var dir: String = base.path_join(id)
			var manifest: Dictionary = _read_manifest(dir)
			if manifest.is_empty():
				continue
			found[id] = {
				"id": id,
				"name": String(manifest.get("name", id)),
				"description": String(manifest.get("description", "")),
				"dir": dir,
				"icon": dir.path_join(String(manifest.get("icon", "pack.png"))),
			}
	var ids: Array = found.keys()
	ids.sort()
	var packs: Array[Dictionary] = []
	if found.has(DEFAULT_ID):
		packs.append(found[DEFAULT_ID])
	for id: String in ids:
		if id != DEFAULT_ID:
			packs.append(found[id])
	return packs


## Icon of a listed pack (its pack.png), or null.
static func pack_icon(pack: Dictionary) -> Texture2D:
	return _load_file(String(pack.get("icon", ""))) as Texture2D


## Enables exactly these packs, highest priority first, and remembers the
## choice. Unknown ids are dropped. Scenes pick the packs up when they are
## (re)built; PackRuntime.apply() restyles what is already on screen.
## `remember = false` switches for this run only (tools, previews).
static func set_enabled(ids: Array, remember: bool = true) -> void:
	_loaded = true
	_build_stack(ids)
	if remember:
		PlayerConfig.set_config(CONFIG_SECTION, CONFIG_KEY, enabled_ids())


## Enables one pack on top of the default (the default alone for its own id
## or an unknown one).
static func set_active(id: String) -> void:
	set_enabled([] if id == DEFAULT_ID else [id])


## Drops everything read so far (tests, and after editing a pack on disk).
static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func _build_stack(ids: Array) -> void:
	_cache.clear()
	_colors.clear()
	_revision += 1
	_stack = []
	var seen: Array[String] = [DEFAULT_ID]
	for value: Variant in ids:
		var id: String = String(value)
		if seen.has(id):
			continue
		for base: String in [USER_DIR, BUNDLED_DIR]:
			var dir: String = base.path_join(id)
			var manifest: Dictionary = _read_manifest(dir)
			if not manifest.is_empty():
				seen.append(id)
				_stack.append({"id": id, "manifest": manifest, "dir": dir})
				break
	var default_dir: String = BUNDLED_DIR.path_join(DEFAULT_ID)
	_stack.append({"id": DEFAULT_ID, "manifest": _read_manifest(default_dir), "dir": default_dir})


static func _read_manifest(dir: String) -> Dictionary:
	var path: String = dir.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# Lookups
static func sound(key: String) -> AudioStream:
	return _resource("sounds", key) as AudioStream


static func sound_volume(key: String) -> float:
	return _volume("sounds", key)


static func music(key: String) -> AudioStream:
	return _resource("music", key) as AudioStream


static func music_volume(key: String) -> float:
	return _volume("music", key)


## A number of a music entry (`bpm`, `loop_offset`), from the pack that
## provides the track's file; `fallback` when it names none.
static func music_number(key: String, field: String, fallback: float) -> float:
	ensure_loaded()
	for pack: Dictionary in _stack:
		var entry: Dictionary = _entry("music", key, pack["manifest"])
		if entry.is_empty():
			continue
		return float(entry.get(field, fallback))
	return fallback


## The id of the pack that provides a music track ("" when none does).
static func music_pack(key: String) -> String:
	ensure_loaded()
	for pack: Dictionary in _stack:
		if not _entry("music", key, pack["manifest"]).is_empty():
			return String(pack["id"])
	return ""


## Events a pack can give a sprite animation (scripts/board_fx.gd plays them).
const EFFECT_EVENTS: Array[String] = ["lock", "hard_drop", "line_clear", "tetris", "tspin", "perfect_clear", "garbage", "ko"]


## The sprite animation of a board event, from the top-most pack that has a
## usable one; empty when none does (the event then only has its built-in
## drawn effect). Keys: texture, frame (Vector2i), frames, columns, fps,
## scale (screen pixels per sheet pixel at the 22-pixel cell), bottom (the
## frame hangs on its bottom center instead of its center), glow (strength
## of an extra additive pass) and replace (the built-in effect is left out).
static func effect(key: String) -> Dictionary:
	ensure_loaded()
	var cache_key: String = "effects/" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var found: Dictionary = {}
	for pack: Dictionary in _stack:
		var entry: Dictionary = _entry("effects", key, pack["manifest"])
		if entry.is_empty():
			continue
		var sheet: Texture2D = _load_file(_resolve(String(entry.get("sheet", "")), String(pack["dir"]))) as Texture2D
		var frame: Variant = entry.get("frame")
		if sheet == null or not (frame is Array) or (frame as Array).size() != 2:
			continue
		var size: Vector2i = Vector2i(int(frame[0]), int(frame[1]))
		if size.x <= 0 or size.y <= 0 or size.x > sheet.get_width() or size.y > sheet.get_height():
			continue
		var columns: int = sheet.get_width() / size.x
		found = {
			"texture": sheet,
			"frame": size,
			"columns": columns,
			"frames": clampi(int(entry.get("frames", 1)), 1, columns * (sheet.get_height() / size.y)),
			"fps": clampf(float(entry.get("fps", 30.0)), 1.0, 120.0),
			"scale": maxf(0.1, float(entry.get("scale", 1.0))),
			"bottom": String(entry.get("anchor", "center")) == "bottom",
			"glow": clampf(float(entry.get("glow", 0.0)), 0.0, 1.0),
			"replace": bool(entry.get("replace", false)),
		}
		break
	_cache[cache_key] = found
	return found


## The animated title, from the top-most pack that has a usable one; empty
## when none does (the menus then keep their text title). Keys: texture, frame
## (Vector2i), frames, columns, fps, scale (screen pixels per sheet pixel),
## loop_from (the frames before it play once, the rest repeat) and glow.
static func title() -> Dictionary:
	ensure_loaded()
	if _cache.has("title"):
		return _cache["title"]
	var found: Dictionary = {}
	for pack: Dictionary in _stack:
		var entry: Variant = (pack["manifest"] as Dictionary).get("title")
		if not (entry is Dictionary):
			continue
		var sheet: Texture2D = _load_file(_resolve(String(entry.get("sheet", "")), String(pack["dir"]))) as Texture2D
		var frame: Variant = entry.get("frame")
		if sheet == null or not (frame is Array) or (frame as Array).size() != 2:
			continue
		var size: Vector2i = Vector2i(int(frame[0]), int(frame[1]))
		if size.x <= 0 or size.y <= 0 or size.x > sheet.get_width() or size.y > sheet.get_height():
			continue
		var columns: int = sheet.get_width() / size.x
		var frames: int = clampi(int(entry.get("frames", 1)), 1, columns * (sheet.get_height() / size.y))
		found = {
			"texture": sheet,
			"frame": size,
			"columns": columns,
			"frames": frames,
			"fps": clampf(float(entry.get("fps", 30.0)), 1.0, 120.0),
			"scale": maxf(0.1, float(entry.get("scale", 1.0))),
			"loop_from": clampi(int(entry.get("loop_from", 0)), 0, frames - 1),
			"glow": clampf(float(entry.get("glow", 0.0)), 0.0, 1.0),
		}
		break
	_cache["title"] = found
	return found


## A number of the "fx" section (tuning of the built-in drawn effects), from
## the top-most pack that names it.
static func fx_number(key: String, fallback: float) -> float:
	ensure_loaded()
	for pack: Dictionary in _stack:
		var section: Variant = (pack["manifest"] as Dictionary).get("fx")
		if section is Dictionary and (section as Dictionary).has(key):
			return float(section[key])
	return fallback


static func font(key: String) -> Font:
	var loaded: Font = _resource("fonts", key) as Font
	return loaded if loaded != null else ThemeDB.fallback_font


static func texture(key: String) -> Texture2D:
	return _resource("textures", key) as Texture2D


static func color(key: String) -> Color:
	ensure_loaded()
	# Cached: the boards ask for cell colors every frame.
	if _colors.has(key):
		return _colors[key]
	var found: Color = MISSING_COLOR
	for pack: Dictionary in _stack:
		var colors: Variant = (pack["manifest"] as Dictionary).get("colors")
		if colors is Dictionary and (colors as Dictionary).has(key):
			var text: String = String(colors[key])
			if Color.html_is_valid(text):
				found = Color.html(text)
				break
	_colors[key] = found
	return found


## Block look of the top-most pack that defines one it can load: the raw
## "blocks" section plus the loaded "atlas_texture" / "tile_texture". Empty
## when no pack has a usable one (BlockSkin then draws plain bevelled tiles).
static func blocks() -> Dictionary:
	ensure_loaded()
	for pack: Dictionary in _stack:
		var section: Variant = (pack["manifest"] as Dictionary).get("blocks")
		if not (section is Dictionary):
			continue
		var found: Dictionary = (section as Dictionary).duplicate()
		for key: String in ["atlas", "tile"]:
			if found.has(key):
				found[key + "_texture"] = _load_file(_resolve(String(found[key]), String(pack["dir"])))
		if found.get("atlas_texture") != null or found.get("tile_texture") != null:
			return found
	return {}


## Color of a board cell value: a piece type, or Board.GARBAGE.
static func cell_color(value: int) -> Color:
	if value >= 0 and value < PIECE_COLOR_KEYS.size():
		return color(PIECE_COLOR_KEYS[value])
	return color("garbage")


## Sound events the active pack (or the default behind it) can play.
static func sound_keys() -> Array[String]:
	ensure_loaded()
	var keys: Array[String] = []
	for pack: Dictionary in _stack:
		var sounds: Variant = (pack["manifest"] as Dictionary).get("sounds")
		if sounds is Dictionary:
			for key: String in sounds:
				if not keys.has(key):
					keys.append(key)
	return keys


## One AudioStreamPlayer per event on the SFX bus, parented to `owner`.
## Returns event -> player; events without a loadable stream are left out.
static func make_sfx_players(owner: Node, events: Array[String]) -> Dictionary:
	var players: Dictionary = {}
	for event: String in events:
		var stream: AudioStream = sound(event)
		if stream == null:
			continue
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Sfx" + event.to_pascal_case()
		player.stream = stream
		player.bus = SFX_BUS
		player.volume_db = sound_volume(event)
		owner.add_child(player)
		players[event] = player
	return players


# ---------------------------------------------------------------------------
# Loading
static func _entry(section: String, key: String, manifest: Dictionary) -> Dictionary:
	var entries: Variant = manifest.get(section)
	if not (entries is Dictionary) or not (entries as Dictionary).has(key):
		return {}
	var entry: Variant = entries[key]
	if entry is String:
		return {"file": entry}
	return entry if entry is Dictionary else {}


static func _volume(section: String, key: String) -> float:
	ensure_loaded()
	for pack: Dictionary in _stack:
		var entry: Dictionary = _entry(section, key, pack["manifest"])
		if entry.has("volume_db"):
			return float(entry["volume_db"])
	return 0.0


static func _resource(section: String, key: String) -> Resource:
	ensure_loaded()
	var cache_key: String = section + "/" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var loaded: Resource = null
	for pack: Dictionary in _stack:
		var entry: Dictionary = _entry(section, key, pack["manifest"])
		if entry.is_empty():
			continue
		loaded = _load_file(_resolve(String(entry.get("file", "")), String(pack["dir"])))
		if loaded != null:
			break
	_cache[cache_key] = loaded
	return loaded


static func _resolve(file: String, pack_dir: String) -> String:
	if file.is_empty() or file.begins_with("res://") or file.begins_with("user://"):
		return file
	return pack_dir.path_join(file)


## Imported project files go through the resource loader; anything else (a
## pack outside the project) is read straight from disk.
static func _load_file(path: String) -> Resource:
	if path.is_empty():
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path)
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"png", "jpg", "jpeg", "webp":
			var image: Image = Image.load_from_file(path)
			return ImageTexture.create_from_image(image) if image != null else null
		"ttf", "otf":
			var font_file: FontFile = FontFile.new()
			if font_file.load_dynamic_font(path) != OK:
				return null
			var cjk: Font = load(CJK_FALLBACK_FONT) as Font
			if cjk != null:
				font_file.fallbacks = [cjk]
			return font_file
	return null


# ---------------------------------------------------------------------------
# Layouts
## The scene of one screen, from the top-most enabled pack that has a valid
## one. Null only when even the default pack's layout is broken.
static func layout(key: String) -> PackedScene:
	ensure_loaded()
	var cache_key: String = "layouts/" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var found: PackedScene = null
	for pack: Dictionary in _stack:
		var entry: Dictionary = _entry("layouts", key, pack["manifest"])
		if entry.is_empty():
			continue
		var path: String = _resolve(String(entry.get("file", "")), String(pack["dir"]))
		var problem: String = _layout_problem(path)
		if problem.is_empty():
			found = _load_scene(path)
			break
		push_warning("Resource pack '%s': layout '%s' skipped (%s)." % [pack["id"], key, problem])
	_cache[cache_key] = found
	return found


## Empty when the scene at `path` can be used as a layout, else the reason.
static func _layout_problem(path: String) -> String:
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return "file not found"
	if not path.begins_with("res://"):
		var unsafe: String = _scene_text_problem(path, 0)
		if not unsafe.is_empty():
			return unsafe
	var scene: PackedScene = _load_scene(path)
	if scene == null or not scene.can_instantiate():
		return "not a scene"
	var root: Node = scene.instantiate()
	var missing: Array[String] = []
	var script: Script = root.get_script() as Script
	if script != null and script.get_script_constant_map().has("REQUIRED_NODES"):
		for node_name: String in script.get_script_constant_map()["REQUIRED_NODES"]:
			if root.get_node_or_null(NodePath("%" + node_name)) == null:
				missing.append(node_name)
	elif script == null:
		missing.append("(binding script on the root node)")
	root.free()
	return "" if missing.is_empty() else "missing node(s): " + ", ".join(missing)


## Scenes of packs outside the project are read fresh from disk each time
## (they can change while the game runs; the loader cache would hide that).
static func _load_scene(path: String) -> PackedScene:
	if path.begins_with("res://"):
		return load(path) as PackedScene
	return ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene


## A scene file can carry code. Scenes from outside the project are read as
## text first: no embedded scripts, script references only into the game's
## own scripts, nested scenes held to the same rule.
static func _scene_text_problem(path: String, depth: int) -> String:
	if depth > LAYOUT_NEST_LIMIT:
		return "scenes nested too deep"
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return "unreadable"
	if text.contains("type=\"GDScript\"") and text.contains("[sub_resource"):
		var embedded: RegEx = RegEx.new()
		embedded.compile("\\[sub_resource[^\\]]*type=\"(GDScript|CSharpScript)\"")
		if embedded.search(text) != null:
			return "embedded script"
	var reference: RegEx = RegEx.new()
	reference.compile("\\[ext_resource[^\\]]*\\]")
	var attribute: RegEx = RegEx.new()
	attribute.compile("(type|path)=\"([^\"]*)\"")
	for found: RegExMatch in reference.search_all(text):
		var values: Dictionary = {}
		for pair: RegExMatch in attribute.search_all(found.get_string()):
			values[pair.get_string(1)] = pair.get_string(2)
		var target: String = String(values.get("path", ""))
		match String(values.get("type", "")):
			"Script":
				if not target.begins_with(LAYOUT_SCRIPT_ROOT):
					return "script outside the game: " + target
			"PackedScene":
				if not target.begins_with("res://"):
					var nested: String = _scene_text_problem(target, depth + 1)
					if not nested.is_empty():
						return nested
	return ""


# ---------------------------------------------------------------------------
# Theme
## Writes the pack's Control styling into `theme`: the stock Button / Label /
## panel types every menu uses, and the type variations the layouts use
## (HudCard, HudTitle, HudValue, HudBig, HudDim, HudLamp, MenuTitle,
## PrimaryButton, PackRow). PackRuntime passes the project theme. Fonts of the
## stock types are left to the project default so CJK text keeps working.
static func style_theme(theme: Theme) -> void:
	var text: Color = color("button_text")
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, _box("button", color("button_fill"), color("button_border"), 1))
		theme.set_stylebox("hover", type, _box("button_hover", color("button_hover"), color("button_focus"), 1))
		theme.set_stylebox("pressed", type, _box("button_pressed", color("button_pressed"), color("highlight"), 2))
		theme.set_stylebox("hover_pressed", type, _box("button_pressed", color("button_hover"), color("highlight"), 2))
		theme.set_stylebox("disabled", type, _box("button", color("button_disabled"), Color(color("button_border"), 0.3), 1))
		var focus: StyleBox = _box("button_focus", Color(0, 0, 0, 0), color("button_focus"), 2)
		if focus is StyleBoxFlat:
			(focus as StyleBoxFlat).draw_center = false
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, text)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, color("highlight"))
		theme.set_color("font_hover_pressed_color", type, color("highlight"))
		theme.set_color("font_disabled_color", type, color("button_text_disabled"))
	theme.set_color("font_color", "Label", color("text_value"))
	for type: String in ["PanelContainer", "Panel", "PopupPanel"]:
		var panel: StyleBox = _box("panel", color("window_fill"), color("window_border"), 2, 10.0)
		panel.set_content_margin_all(12)
		theme.set_stylebox("panel", type, panel)
	# --- variations used by the layouts
	theme.set_type_variation("HudCard", "PanelContainer")
	var card: StyleBox = _box("card", color("panel_fill"), color("panel_border"), 2, 8.0)
	card.set_content_margin_all(12)
	theme.set_stylebox("panel", "HudCard", card)
	theme.set_type_variation("PackRow", "PanelContainer")
	var row: StyleBox = _box("card", Color(color("panel_fill"), 0.6), Color(color("panel_border"), 0.5), 1, 6.0)
	row.set_content_margin_all(6)
	theme.set_stylebox("panel", "PackRow", row)
	for spec: Array in [
		["HudTitle", "mini", 13, "text_title"],
		["HudValue", "main", 22, "text_value"],
		["HudBig", "main", 18, "text_value"],
		["HudLamp", "main", 18, "lamp_off"],
		["HudDim", "mono", 11, "text_dim"],
		["MenuTitle", "main", 22, "accent"],
	]:
		theme.set_type_variation(spec[0], "Label")
		theme.set_font("font", spec[0], font(spec[1]))
		theme.set_font_size("font_size", spec[0], spec[2])
		theme.set_color("font_color", spec[0], color(spec[3]))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _box("button", color("button_hover"), color("accent"), 2))
	theme.set_font_size("font_size", "PrimaryButton", 18)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(color("text_value"), 0.14)
	track.set_corner_radius_all(2)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color("highlight")
	fill.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", fill)
	var line: StyleBoxLine = StyleBoxLine.new()
	line.color = Color(color("panel_border"), 0.6)
	theme.set_stylebox("separator", "HSeparator", line)


## A panel/button box: the pack's nine-patch image `ui_key` when it has one,
## else a flat rounded box in the given colors.
static func _box(ui_key: String, fill: Color, border: Color, border_width: int, radius: float = 6.0) -> StyleBox:
	var image: Texture2D = _resource("ui", ui_key) as Texture2D
	if image != null:
		var textured: StyleBoxTexture = StyleBoxTexture.new()
		textured.texture = image
		textured.set_texture_margin_all(_ui_margin(ui_key))
		textured.set_content_margin_all(_ui_margin(ui_key))
		textured.content_margin_left = maxf(14.0, _ui_margin(ui_key))
		textured.content_margin_right = maxf(14.0, _ui_margin(ui_key))
		return textured
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(int(radius))
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box


static func _ui_margin(ui_key: String) -> float:
	for pack: Dictionary in _stack:
		var entry: Dictionary = _entry("ui", ui_key, pack["manifest"])
		if entry.has("margin"):
			return float(entry["margin"])
	return 8.0


## Flat rounded panel for HUD parts built in code.
static func hud_panel_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color("panel_fill")
	box.border_color = color("panel_border")
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	return box
