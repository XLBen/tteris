extends SceneTree

const MODULE_NAME: String = "music"

const BGM_FILE: String = "res://assets/audio/bgm/korobeiniki-120.ogg"
const BGM_DIR_SUBSTRING: String = "assets/audio/bgm/"
const OLD_JINGLE_SUBSTRING: String = "assets/music/bgm.ogg"
const OLD_JINGLE_DIR_SUBSTRING: String = "assets/music/"
const MIX_SETTLE_SECONDS: float = 0.2

# single-track BGM (owner decision 2026-09-16): the four synthesized
# Korobeiniki tier/accent files are removed from disk and from the project;
# ONE looping stream on the BGM bus replaces them (runtime stream.loop, played
# from launch), with the SFX sidechain compressor on the BGM bus retained.
# Revised 2026-10-10 (owner decision): that stream is the project's own synth
# arrangement rendered by tools/make_bgm.py (record:
# assets/audio/bgm/LICENSE-bgm.txt); byte sha256 bound in
# assets/assets-measurements.json.
# Revised 2026-10-11 (owner decision): a playlist of songs in that
# arrangement, one playing at a time (scripts/bgm_director.gd): the stream is
# a song of the default pack's playlist, played once through, not looped.
const MAGORY_FILENAMES: Array[String] = [
	"going_undercover-loop1.ogg",
	"hostile_territory-loop1.ogg",
	"shadow_operations-loop1.ogg",
	"the_price_of_freedom-loop1.ogg",
]
const REMOVED_TIER_FILES: Array[String] = [
	"res://assets/audio/bgm/korobeiniki-tier1.ogg",
	"res://assets/audio/bgm/korobeiniki-tier2.ogg",
	"res://assets/audio/bgm/korobeiniki-tier3.ogg",
	"res://assets/audio/bgm/korobeiniki-accent.ogg",
]
const REMOVED_TIER_NAMES: Array[String] = [
	"korobeiniki-tier1.ogg",
	"korobeiniki-tier2.ogg",
	"korobeiniki-tier3.ogg",
	"korobeiniki-accent.ogg",
]
const MEASUREMENTS_PATH: String = "res://assets/assets-measurements.json"
const MIN_BGM_DURATION_S: float = 20.0


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d music cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("MUSIC TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_single_bgm_stream_looped_on_bgm_bus(ctx)
	await _case_old_jingle_unreferenced_and_unplayed(ctx)
	await _case_bgm_bus_ducked_under_sfx(ctx)
	await _case_magory_bgm_files_unreferenced(ctx)
	await _case_removed_tier_files_absent_and_unreferenced(ctx)
	await _case_bgm_file_sha256_bound_to_measurements(ctx)
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


static func _case_single_bgm_stream_looped_on_bgm_bus(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	if not ResourceLoader.exists(BGM_FILE):
		ok = false
	# Revised 2026-10-10 (resource packs): the track is named by the default
	# pack's manifest, not by main.gd.
	var text: String = FileAccess.get_file_as_string("res://packs/default/pack.json")
	if not text.contains(BGM_FILE):
		ok = false
	var player: Variant = main.get("_bgm_player")
	if not (player is AudioStreamPlayer):
		ok = false
	else:
		var bgm_player: AudioStreamPlayer = player
		if bgm_player.bus != "BGM":
			ok = false
		var ogg: AudioStreamOggVorbis = bgm_player.stream as AudioStreamOggVorbis
		if ogg == null or ogg.loop:
			ok = false
		elif not text.contains(ogg.resource_path) or not ogg.resource_path.contains(BGM_DIR_SUBSTRING):
			ok = false
		if not bgm_player.playing:
			ok = false
	main.free()
	_case(ctx, "single_bgm_stream_of_the_playlist_on_bgm_bus", ok)


static func _case_old_jingle_unreferenced_and_unplayed(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	for script_path: String in _collect_suffix("res://scripts", ".gd", false):
		if FileAccess.get_file_as_string(script_path).contains(OLD_JINGLE_SUBSTRING):
			ok = false
	for scene_path: String in _collect_suffix("res://scenes", ".tscn", false):
		if FileAccess.get_file_as_string(scene_path).contains(OLD_JINGLE_SUBSTRING):
			ok = false
	if FileAccess.get_file_as_string("res://scripts/main.gd").contains(OLD_JINGLE_DIR_SUBSTRING):
		ok = false
	var player: Variant = main.get("_bgm_player")
	if player is AudioStreamPlayer:
		var stream: AudioStream = (player as AudioStreamPlayer).stream
		if stream != null and stream.resource_path.contains(OLD_JINGLE_DIR_SUBSTRING):
			ok = false
	main.free()
	_case(ctx, "old_jingle_unreferenced_and_unplayed", ok)


static func _case_bgm_bus_ducked_under_sfx(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	var bgm_index: int = AudioServer.get_bus_index("BGM")
	var sfx_index: int = AudioServer.get_bus_index("SFX")
	if bgm_index == -1 or sfx_index == -1:
		ok = false
	else:
		var compressors: int = 0
		for i: int in AudioServer.get_bus_effect_count(bgm_index):
			var effect: AudioEffect = AudioServer.get_bus_effect(bgm_index, i)
			if effect is AudioEffectCompressor:
				compressors += 1
				if String((effect as AudioEffectCompressor).sidechain) != "SFX":
					ok = false
		if compressors != 1:
			ok = false
	main.free()
	_case(ctx, "bgm_bus_compressor_sidechain_wired_to_sfx", ok)


static func _case_magory_bgm_files_unreferenced(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	var scan_targets: Array[String] = [
		"res://scripts/main.gd",
		"res://scenes/main.tscn",
	]
	for target: String in scan_targets:
		if not FileAccess.file_exists(target):
			ok = false
			continue
		var text: String = FileAccess.get_file_as_string(target)
		for magory_name: String in MAGORY_FILENAMES:
			if text.contains(magory_name):
				ok = false
	var player: Variant = main.get("_bgm_player")
	if player is AudioStreamPlayer:
		var stream: AudioStream = (player as AudioStreamPlayer).stream
		if stream != null:
			for magory_name: String in MAGORY_FILENAMES:
				if stream.resource_path.contains(magory_name):
					ok = false
	main.free()
	_case(ctx, "magory_bgm_files_unreferenced", ok)


static func _case_removed_tier_files_absent_and_unreferenced(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	for tier_path: String in REMOVED_TIER_FILES:
		if FileAccess.file_exists(tier_path):
			ok = false
		if FileAccess.file_exists(tier_path + ".import"):
			ok = false
		if ResourceLoader.exists(tier_path):
			ok = false
	for script_path: String in _collect_suffix("res://scripts", ".gd", false):
		var script_text: String = FileAccess.get_file_as_string(script_path)
		for tier_name: String in REMOVED_TIER_NAMES:
			if script_text.contains(tier_name):
				ok = false
	for scene_path: String in _collect_suffix("res://scenes", ".tscn", false):
		var scene_text: String = FileAccess.get_file_as_string(scene_path)
		for tier_name: String in REMOVED_TIER_NAMES:
			if scene_text.contains(tier_name):
				ok = false
	var player: Variant = main.get("_bgm_player")
	if player is AudioStreamPlayer:
		var stream: AudioStream = (player as AudioStreamPlayer).stream
		if stream != null:
			for tier_name: String in REMOVED_TIER_NAMES:
				if stream.resource_path.contains(tier_name):
					ok = false
	main.free()
	_case(ctx, "removed_tier_files_absent_and_unreferenced", ok)


static func _case_bgm_file_sha256_bound_to_measurements(ctx: Dictionary) -> void:
	var ok: bool = true
	var records: Dictionary = _load_measurement_records()
	# Every track of every song of the playlist is bound.
	var files: Array[String] = [BGM_FILE]
	for song: Dictionary in ResourcePack.playlist():
		for track: Dictionary in song["tracks"]:
			if not files.has(String(track["file"])):
				files.append(String(track["file"]))
	ok = files.size() >= 12
	for file: String in files:
		var record: Variant = records.get(file)
		if typeof(record) != TYPE_DICTIONARY:
			ok = false
			continue
		var rec: Dictionary = record
		var actual_sha: String = FileAccess.get_sha256(file).to_lower()
		var recorded_sha: String = String(rec.get("sha256", "")).to_lower()
		if actual_sha.length() != 64 or recorded_sha != actual_sha:
			ok = false
		var duration_s: float = _record_float(rec, "duration_s", -1.0)
		if duration_s < MIN_BGM_DURATION_S:
			ok = false
	_case(ctx, "bgm_file_sha256_bound_to_measurements", ok)


static func _load_measurement_records() -> Dictionary:
	var records: Dictionary = {}
	if not FileAccess.file_exists(MEASUREMENTS_PATH):
		return records
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MEASUREMENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return records
	var files: Variant = (parsed as Dictionary).get("files")
	if typeof(files) != TYPE_ARRAY:
		return records
	for entry: Variant in (files as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			records[String((entry as Dictionary).get("path", ""))] = entry
	return records


static func _record_float(rec: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = rec.get(key)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


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
