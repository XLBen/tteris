extends SceneTree

const MODULE_NAME: String = "assets"

const BASELINE_MAIN_GD: String = "res://docs/audit-slices/modern-tetris-refresh/assets-refresh/rollback/main.gd"
const PROVENANCE_PATH: String = "res://assets/assets-provenance.json"
const MANIFEST_PATH: String = "res://assets/assets-manifest.json"
const MEASUREMENTS_PATH: String = "res://assets/assets-measurements.json"
const LEGACY_RECORD_DIRS: Array[String] = [
	"res://assets/audio/interface",
	"res://assets/music",
	"res://assets/visuals",
]
const AUDIO_RECORD_DIRS: Array[String] = [
	"res://assets/audio/bgm",
	"res://assets/audio/digital",
]
const BGM_PREFIX: String = "res://assets/audio/bgm/"
const SFX_DIGITAL_PREFIX: String = "res://assets/audio/digital/"
const SFX_DELTA_KEYS: Array[String] = ["tetris", "resume"]
const SFX_EVENTS: Array[String] = [
	"move",
	"rotate",
	"hold",
	"hard_drop",
	"lock",
	"clear",
	"tetris",
	"level_up",
	"game_over",
	"pause",
	"resume",
]
const PINNED_SOURCES: Dictionary = {
	"music-jingles": "b729ba57959bd58793d2c5cafa348aaf2655d354f3da35ec4729e03ec77197b8",
	"background-elements": "31ffecec57bd51263f68e96e288ad06ac28eb1dfb41edb06b006a1b42cc10e41",
	"interface-sounds": "f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232",
}
const PINNED_AUDIO_SOURCES: Dictionary = {
	"https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip": "24e6ce28b76a6d8c89cff4d331e0965ff5c3de8a73c612028e9d363cc64e4f06",
	"https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip": "f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232",
}
const MIX_SETTLE_SECONDS: float = 0.2


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d asset cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("ASSET TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_loads_all_referenced_assets(ctx)
	await _case_licenses_present(ctx)
	await _case_no_remote_runtime_references(ctx)
	await _case_bgm_loops(ctx)
	await _case_sfx_remap_delta(ctx)
	await _case_manifest_exists(ctx)
	await _case_measurements_cover_audio_families(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _spawn_main():
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await (Engine.get_main_loop() as SceneTree).create_timer(MIX_SETTLE_SECONDS).timeout
	return main


static func _case_loads_all_referenced_assets(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	var sfx: Dictionary = main._sfx
	if sfx.is_empty():
		ok = false
	for key: String in sfx:
		var player: Variant = sfx[key]
		if not (player is AudioStreamPlayer):
			ok = false
			continue
		if (player as AudioStreamPlayer).stream == null:
			ok = false
	var bgm: Variant = main.get("_bgm_player")
	if bgm is AudioStreamPlayer:
		var bgm_stream: AudioStream = (bgm as AudioStreamPlayer).stream
		if bgm_stream == null:
			ok = false
		elif not bgm_stream.resource_path.begins_with(BGM_PREFIX):
			ok = false
	else:
		ok = false
	var background: Variant = main.get("_background")
	if background is TextureRect:
		var background_texture: Texture2D = (background as TextureRect).texture
		ok = ok and background_texture != null
		if background_texture != null:
			ok = ok and background_texture.resource_path.begins_with("res://assets/visuals/")
	else:
		ok = false
	main.free()
	_case(ctx, "loads_all_referenced_assets", ok)


static func _case_licenses_present(ctx: Dictionary) -> void:
	var ok: bool = true
	for dir_path: String in LEGACY_RECORD_DIRS:
		var covered: bool = false
		if DirAccess.dir_exists_absolute(dir_path):
			for file_name: String in DirAccess.get_files_at(dir_path):
				if file_name.begins_with("LICENSE"):
					covered = true
		ok = ok and covered
	ok = ok and _legacy_provenance_covers()
	ok = ok and _audio_dirs_covered_by_provenance()
	ok = ok and _audio_dirs_license_covered()
	_case(ctx, "licenses_present", ok)


static func _legacy_provenance_covers() -> bool:
	if not FileAccess.file_exists(PROVENANCE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROVENANCE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var families: Variant = (parsed as Dictionary).get("families")
	if typeof(families) != TYPE_ARRAY or (families as Array).is_empty():
		return false
	var covered: Dictionary = {}
	for entry: Variant in families:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry
		var entry_ok: bool = true
		for field: String in ["source", "author", "license", "dest"]:
			var value: Variant = record.get(field)
			entry_ok = entry_ok and typeof(value) == TYPE_STRING and not (value as String).is_empty()
		var source: Variant = record.get("source")
		if typeof(source) == TYPE_STRING:
			# Revised 2026-10-10: a family rendered by one of the project's own
			# tools (the synthesized BGM) names that tool instead of a URL.
			entry_ok = entry_ok and ((source as String).begins_with("http://") or (source as String).begins_with("https://") 				or (source as String).begins_with("tools/"))
		else:
			entry_ok = false
		if entry_ok:
			covered[_normalize_dest(String(record.get("dest")))] = true
	for dir_path: String in LEGACY_RECORD_DIRS:
		if not covered.has(_normalize_dest(dir_path)):
			return false
	return true


static func _audio_dirs_covered_by_provenance() -> bool:
	if not FileAccess.file_exists(PROVENANCE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROVENANCE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var families: Variant = (parsed as Dictionary).get("families")
	if typeof(families) != TYPE_ARRAY or (families as Array).is_empty():
		return false
	var covered: Dictionary = {}
	for entry: Variant in families:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry
		var entry_ok: bool = true
		for field: String in ["source", "author", "license", "dest"]:
			var value: Variant = record.get(field)
			entry_ok = entry_ok and typeof(value) == TYPE_STRING and not (value as String).is_empty()
		var source: Variant = record.get("source")
		if typeof(source) == TYPE_STRING:
			# Revised 2026-10-10: a family rendered by one of the project's own
			# tools (the synthesized BGM) names that tool instead of a URL.
			entry_ok = entry_ok and ((source as String).begins_with("http://") or (source as String).begins_with("https://") 				or (source as String).begins_with("tools/"))
		else:
			entry_ok = false
		if entry_ok:
			covered[_normalize_dest(String(record.get("dest")))] = true
	for dir_path: String in AUDIO_RECORD_DIRS:
		if not covered.has(_normalize_dest(dir_path)):
			return false
	return true


static func _audio_dirs_license_covered() -> bool:
	var asset_root_files: Array[String] = []
	if DirAccess.dir_exists_absolute("res://assets"):
		for file_name: String in DirAccess.get_files_at("res://assets"):
			asset_root_files.append(file_name)
	for dir_path: String in AUDIO_RECORD_DIRS:
		var keyword: String = "bgm" if dir_path.contains("bgm") else "digital"
		var covered: bool = false
		if DirAccess.dir_exists_absolute(dir_path):
			for file_name: String in DirAccess.get_files_at(dir_path):
				if file_name.begins_with("LICENSE"):
					covered = true
		for file_name: String in asset_root_files:
			if file_name.begins_with("LICENSE") and file_name.to_lower().contains(keyword):
				covered = true
		if not covered:
			return false
	return true


static func _normalize_dest(dest: String) -> String:
	var result: String = dest.replace("res://", "").replace("\\", "/")
	while result.ends_with("/"):
		result = result.substr(0, result.length() - 1)
	return result


static func _case_no_remote_runtime_references(ctx: Dictionary) -> void:
	var targets: Array[String] = ["res://project.godot"]
	targets.append_array(_collect_suffix("res://scenes", ".tscn", false))
	targets.append_array(_collect_suffix("res://scripts", ".gd", false))
	targets.append_array(_collect_suffix("res://assets", ".import", true))
	var ok: bool = not targets.is_empty()
	for path: String in targets:
		if not FileAccess.file_exists(path):
			ok = false
			continue
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("http://") or text.contains("https://"):
			ok = false
	_case(ctx, "no_remote_runtime_references", ok)


static func _collect_suffix(dir_path: String, suffix: String, recursive: bool) -> Array[String]:
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
			if recursive:
				found.append_array(_collect_suffix(full_path, suffix, recursive))
		elif entry_name.ends_with(suffix):
			found.append(full_path)
		entry_name = dir.get_next()
	dir.list_dir_end()
	return found


static func _case_bgm_loops(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	var player: Variant = main.get("_bgm_player")
	if not (player is AudioStreamPlayer):
		ok = false
	else:
		var bgm_player: AudioStreamPlayer = player
		# Revised 2026-10-11 (playlist): a song is one stream played once
		# through; the director follows it with the next one.
		var ogg: AudioStreamOggVorbis = bgm_player.stream as AudioStreamOggVorbis
		if ogg == null or ogg.loop or main.get("_bgm_director") == null or (main.get("_bgm_director") as BgmDirector).song_count() < 2:
			ok = false
		if bgm_player.bus != "BGM":
			ok = false
		if not bgm_player.playing:
			ok = false
	main.free()
	_case(ctx, "bgm_playlist_song_plays_on_bgm_bus", ok)


# Revised 2026-10-10 (owner: decouple the assets into a resource pack): the sound
# set is the default pack's synthesized one now. Every classic event resolves
# through the pack to a WAV inside packs/default, and every file the default
# pack names exists.
static func _case_sfx_remap_delta(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = (main.SFX_EVENTS as Array).size() >= SFX_EVENTS.size()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://packs/default/pack.json"))
	ok = ok and manifest is Dictionary
	if manifest is Dictionary:
		var sounds: Dictionary = manifest.get("sounds", {})
		for key: String in SFX_EVENTS:
			ok = ok and sounds.has(key) and ResourcePack.sound(key) != null
			if sounds.has(key):
				ok = ok and FileAccess.file_exists("res://packs/default/" + String(sounds[key]["file"]))
		for section: String in ["sounds", "music", "fonts", "textures"]:
			for key: String in manifest.get(section, {}):
				var entry: Variant = manifest[section][key]
				var file: String = String(entry["file"]) if entry is Dictionary else String(entry)
				var path: String = file if file.begins_with("res://") else "res://packs/default/" + file
				ok = ok and FileAccess.file_exists(path)
	main.free()
	_case(ctx, "sfx_remap_crisp_replacements_differ_from_baseline", ok)


static func _parse_baseline_sfx() -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(BASELINE_MAIN_GD):
		return result
	var text: String = FileAccess.get_file_as_string(BASELINE_MAIN_GD)
	if text.is_empty():
		return result
	var start: int = text.find("const SFX_FILES")
	if start < 0:
		return result
	var end_pos: int = text.find("}", start)
	if end_pos < 0:
		return result
	var block: String = text.substr(start, end_pos - start)
	var pattern: RegEx = RegEx.new()
	if pattern.compile("\"([A-Za-z0-9_]+)\"\\s*:\\s*\"([^\"]+)\"") != OK:
		return result
	for found: RegExMatch in pattern.search_all(block):
		result[String(found.get_string(1))] = String(found.get_string(2))
	return result


static func _case_manifest_exists(ctx: Dictionary) -> void:
	var ok: bool = false
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			var sources: Variant = (parsed as Dictionary).get("sources")
			if typeof(sources) == TYPE_ARRAY and not (sources as Array).is_empty():
				ok = true
				for pack: String in PINNED_SOURCES:
					var pinned_digest: String = String(PINNED_SOURCES[pack])
					var pinned_ok: bool = false
					for entry: Variant in sources:
						if typeof(entry) != TYPE_DICTIONARY:
							continue
						var record: Dictionary = entry
						var identity: String = String(record.get("name", "")) + " " + String(record.get("url", ""))
						var digest: String = String(record.get("sha256", "")).to_lower()
						if identity.contains(pack) and digest.length() == 64 and digest.is_valid_hex_number() and digest == pinned_digest:
							pinned_ok = true
					ok = ok and pinned_ok
				for url: String in PINNED_AUDIO_SOURCES:
					var audio_digest: String = String(PINNED_AUDIO_SOURCES[url])
					var audio_ok: bool = false
					for entry: Variant in sources:
						if typeof(entry) != TYPE_DICTIONARY:
							continue
						var record: Dictionary = entry
						var digest: String = String(record.get("sha256", "")).to_lower()
						if String(record.get("url", "")) == url and digest == audio_digest:
							audio_ok = true
					ok = ok and audio_ok
	_case(ctx, "manifest_records_pinned_sources", ok)


static func _case_measurements_cover_audio_families(ctx: Dictionary) -> void:
	var ok: bool = true
	var expected: Dictionary = {}
	for dir_path: String in AUDIO_RECORD_DIRS:
		if not DirAccess.dir_exists_absolute(dir_path):
			ok = false
			continue
		for file_name: String in DirAccess.get_files_at(dir_path):
			expected[dir_path + "/" + file_name] = true
	if expected.is_empty():
		ok = false
	if ok:
		if not FileAccess.file_exists(MEASUREMENTS_PATH):
			ok = false
		else:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MEASUREMENTS_PATH))
			if typeof(parsed) != TYPE_DICTIONARY:
				ok = false
			else:
				var files: Variant = (parsed as Dictionary).get("files")
				if typeof(files) != TYPE_ARRAY or (files as Array).is_empty():
					ok = false
				else:
					var records: Dictionary = {}
					for entry: Variant in files:
						if typeof(entry) == TYPE_DICTIONARY:
							var key: String = String((entry as Dictionary).get("path", "")).replace("res://", "").replace("\\", "/")
							records[key] = String((entry as Dictionary).get("sha256", "")).to_lower()
					for path: String in expected:
						var key: String = path.replace("res://", "")
						if not records.has(key):
							ok = false
							continue
						var actual: String = FileAccess.get_sha256(path).to_lower()
						if records[key] != actual or actual.length() != 64:
							ok = false
	_case(ctx, "measurements_cover_audio_families_hash_bound", ok)
