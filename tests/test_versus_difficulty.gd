extends SceneTree
## Versus difficulty pipeline: the difficulty stored on GameSession reaches the
## versus scene, the AI is built from the matching tier profile, and the AI
## tag above the right board shows the tier in fixed English (BD-12) whatever
## the UI language is.
##
## Rewritten 2026-10-10: the mode-select half of this module walked the old
## three-step wizard and froze "the difficulty is never remembered" (BD-06);
## the setup page that replaced it (and its remembered choices) is covered by
## tests/test_versus_flow.gd.

const MODULE_NAME: String = "versus_difficulty"

const MODE_SELECT_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const MODE_SELECT_SCRIPT_PATH: String = "res://scenes/menus/mode_select/mode_select.gd"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
## BD-12: the AI-side tag is fixed English in every language.
const DIFFICULTY_TAGS: Dictionary = {
	&"easy": "EASY",
	&"normal": "NORMAL",
	&"hard": "HARD",
	&"lunatic": "LUNATIC",
}


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d versus difficulty cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VERSUS DIFFICULTY TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _tree().process_frame
	await _case_session_difficulty_builds_matching_ai_and_tag(ctx)
	await _case_missing_or_unknown_difficulty_reads_as_normal(ctx)
	await _case_tag_stays_english_and_setup_names_too(ctx)
	_case_mode_select_sources_have_no_tooling_entry(ctx)
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


static func _session():
	return _tree().root.get_node_or_null(^"GameSession")


static func _spawn_versus():
	var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	await _tree().process_frame
	return scene


static func _tag_text(scene) -> String:
	var tag: Label = scene.find_child("AIDifficultyLabel", true, false) as Label
	return tag.text if tag != null and tag.is_visible_in_tree() else ""


static func _case_session_difficulty_builds_matching_ai_and_tag(ctx: Dictionary) -> void:
	var session = _session()
	var ok: bool = session != null
	var seen_colors: Array[Color] = []
	for difficulty: StringName in DIFFICULTY_TAGS:
		session.start_versus(session.VERSUS_RULES_FIXED, 3, session.VERSUS_FORMAT_SINGLE, difficulty)
		var scene = await _spawn_versus()
		ok = ok and scene._ai.profile() == VersusAI.DIFFICULTY_PROFILES[difficulty]
		ok = ok and _tag_text(scene) == String(DIFFICULTY_TAGS[difficulty])
		ok = ok and scene._model.level(VersusBattle.Side.AI) == 3
		# Each tier's tag has its own color, and the tag is large enough to read.
		var tag: Label = scene.find_child("AIDifficultyLabel", true, false) as Label
		var color: Color = tag.get_theme_color("font_color")
		ok = ok and not seen_colors.has(color) and tag.get_theme_font_size("font_size") >= 16
		seen_colors.append(color)
		scene.free()
		await _tree().process_frame
	session.start_mode(session.MODE_NONE)
	_case(ctx, "session_difficulty_builds_matching_ai_and_readable_tag", ok)


static func _case_missing_or_unknown_difficulty_reads_as_normal(ctx: Dictionary) -> void:
	var session = _session()
	session.start_mode(session.MODE_NONE)
	# No versus session at all (direct scene launch).
	var plain = await _spawn_versus()
	var ok: bool = _tag_text(plain) == "NORMAL" and plain._ai.profile() == VersusAI.DIFFICULTY_PROFILES[&"normal"]
	plain.free()
	await _tree().process_frame
	# A stored value that is not a tier.
	session.start_versus(session.VERSUS_RULES_FIXED, 1, session.VERSUS_FORMAT_SINGLE, &"impossible")
	var unknown = await _spawn_versus()
	ok = ok and _tag_text(unknown) == "NORMAL" and unknown._ai.profile() == VersusAI.DIFFICULTY_PROFILES[&"normal"]
	unknown.free()
	await _tree().process_frame
	session.start_mode(session.MODE_NONE)
	_case(ctx, "missing_or_unknown_difficulty_reads_as_normal", ok)


static func _case_tag_stays_english_and_setup_names_too(ctx: Dictionary) -> void:
	var session = _session()
	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	session.start_versus(session.VERSUS_RULES_FIXED, 1, session.VERSUS_FORMAT_SINGLE, session.VERSUS_DIFFICULTY_HARD)
	var scene = await _spawn_versus()
	var ok: bool = _tag_text(scene) == "HARD"
	scene.free()
	await _tree().process_frame
	# The difficulty names have no translation rows (the setup buttons and
	# the tag read the same in every language); their descriptions do.
	for tier_name: String in ["Easy", "Normal", "Hard", "Lunatic"]:
		ok = ok and TranslationServer.translate(tier_name) == tier_name
	for key: String in ["VERSUS_DESC_EASY", "VERSUS_DESC_NORMAL", "VERSUS_DESC_HARD", "VERSUS_DESC_LUNATIC"]:
		ok = ok and TranslationServer.translate(key) != key
	TranslationServer.set_locale(previous_locale)
	session.start_mode(session.MODE_NONE)
	_case(ctx, "difficulty_tag_and_names_stay_english_descriptions_translate", ok)


static func _case_mode_select_sources_have_no_tooling_entry(ctx: Dictionary) -> void:
	# The player-facing mode select stays free of any tooling entry
	# (NO_DEBUG_ENTRY_PATHS semantics).
	var ok: bool = true
	for path: String in [MODE_SELECT_PATH, MODE_SELECT_SCRIPT_PATH]:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		ok = ok and not text.is_empty() and not text.contains("debug") and not text.contains("duel")
	_case(ctx, "mode_select_sources_have_no_tooling_entry", ok)
