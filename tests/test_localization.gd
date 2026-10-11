extends SceneTree

const MODULE_NAME: String = "localization"

# S5 l10n infrastructure machine assertions (BD-14/BD-15/BD-16, BA-04,
# BF-10/BF-11/BF-12, BC-06) plus the S6 full first-party copy coverage
# (O-06). The module is headless and repeatable: the language preference
# key, the TranslationServer locale and the effective autoload state are
# snapshotted first and restored afterwards, so neither the local player
# configuration nor later modules see any test residue.
const CONFIG_LOCATION: String = "user://player_config.cfg"
const VIDEO_WITH_EXTRAS_PATH: String = "res://scenes/menus/options_menu/video/video_options_menu_with_extras.tscn"
const MASTER_TABS_PATH: String = "res://scenes/menus/options_menu/master_options_menu_with_tabs.tscn"
const MAIN_MENU_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const MODE_SELECT_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const PAUSE_MENU_PATH: String = "res://scenes/windows/pause_menu.tscn"
const FUSION_FONT_PATH: String = "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"
const UI_FONT_PATH: String = "res://assets/localization/ui_font.tres"
# The exact paths main.gd / versus.gd load; the Localization autoload attaches
# the Fusion Pixel font to these shared cache entries (BF-11, S6).
const KENNEY_FONT_PATHS: Array[String] = [
	"res://assets/fonts/Kenney Future.ttf",
	"res://assets/fonts/Kenney Mini.ttf",
	"res://assets/fonts/Kenney Mini Square Mono.ttf",
]
const VERSUS_SOURCE_PATH: String = "res://scripts/versus.gd"
const MAIN_SOURCE_PATH: String = "res://scripts/main.gd"
const FROZEN_TAB_COUNT: int = 4
const CSV_PATH: String = "res://assets/localization/localization.csv"
# Seed keys (snake contract family): [en text, zh text].
const SEED_KEYS: Dictionary = {
	"MENU_SELECT_MODE": ["Select Mode", "选择模式"],
	"MENU_NEW_GAME": ["New Game", "开始游戏"],
	"MENU_OPTIONS": ["Options", "选项"],
	"MENU_EXIT": ["Exit", "退出"],
	"MENU_BACK": ["Back", "返回"],
	"MENU_CLASSIC": ["Classic", "经典"],
	"MENU_VERSUS": ["Versus", "对战"],
	"VERSUS_RULES_FIXED": ["Fixed Speed", "固定速度"],
	"VERSUS_FORMAT_SINGLE": ["Single Match", "单局比赛"],
	"VERSUS_FORMAT_BEST_OF_3": ["Best of 3", "三局两胜"],
	"OPTIONS_LANGUAGE": ["Language", "语言"],
}
# Text-equal keys (auto-translate family) for BC-06 rendering without
# touching .text literals.
const AUTO_TRANSLATE_KEYS: Dictionary = {
	"Select Mode": "选择模式",
	"Classic": "经典",
	"Versus": "对战",
	"Back": "返回",
	"Language": "语言",
}
# Difficulty labels are frozen English in every language (BD-12): no key may
# exist whose text-equal lookup would translate them. Both the scene-literal
# casing and the uppercase in-game tag casing are covered.
const FORBIDDEN_DIFFICULTY_KEYS: Array[String] = [
	"Easy", "Normal", "Hard", "Lunatic",
	"EASY", "NORMAL", "HARD", "LUNATIC",
]
# Player-visible texts that stay as-is in every language, with reasons:
#   - Easy/Normal/Hard/Lunatic: BD-12 difficulty words, frozen English.
#   - "1".."10": fixed-speed level numbers, language-neutral digits.
#   - 新建游戏项目: config_name_label projects the project's proper name at
#     runtime; proper names are not translated.
#   - v0.0.0: config_version_label projects the version string at runtime;
#     language-neutral.
const COVERAGE_EXEMPT_TEXTS: Array[String] = [
	"Easy", "Normal", "Hard", "Lunatic",
	"1", "2", "3", "4", "5", "6", "7", "8", "9", "10",
	"新建游戏项目", "v0.0.0",
	# The template main menu's placeholder subtitle (covered since the main
	# menu joined the scan on 2026-10-11; the label itself is unchanged).
	"Subtitle",
]
# Dynamic versus overlay format keys. The overlay labels are rewritten every
# frame, so auto-translate cannot cover them: versus.gd must route each key
# through tr() before the % substitution (BD-15).
const DYNAMIC_OVERLAY_KEYS: Array[String] = [
	"PLAYER WINS ROUND %d", "AI WINS ROUND %d", "DRAW - REPLAY",
	"LINES SENT %d : %d", "PLAYER WINS MATCH", "AI WINS MATCH",
	"ROUND WINS %d : %d", "LEVEL %d",
	# LAN matches (2026-10-12) name the two humans instead.
	"YOU WIN ROUND %d", "RIVAL WINS ROUND %d", "YOU WIN THE MATCH", "RIVAL WINS THE MATCH",
]
const GAME_OVER_SCORE_KEY: String = "SCORE %d"


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d localization cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("LOCALIZATION TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var snapshot: Dictionary = _snapshot_state()
	await _case_csv_translations_loaded(ctx)
	await _case_language_follows_system_when_unset(ctx)
	await _case_language_override_persists_and_prioritizes(ctx)
	await _case_language_option_present_without_new_tab(ctx)
	await _case_cjk_font_loads_with_glyphs(ctx)
	await _case_menu_text_keys_untouched(ctx)
	await _case_first_party_copy_covered(ctx)
	await _case_dynamic_overlay_translated(ctx)
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


static func _l10n() -> Node:
	return _tree().root.get_node_or_null(^"Localization")


static func _new_localization() -> Node:
	# Fresh instance outside the tree: _ready is not run, so the test calls
	# apply_stored_preference() itself to simulate a restart (BD-16).
	var script: GDScript = load("res://scripts/localization.gd") as GDScript
	return script.new()


static func _spawn_scene(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		return null
	var instance: Node = packed.instantiate()
	_tree().root.add_child(instance)
	await _tree().process_frame
	return instance


static func _read_source(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


static func _stored_language() -> String:
	var l10n: Node = _l10n()
	return String(PlayerConfig.get_config(String(l10n.SETTING_SECTION), String(l10n.SETTING_KEY), ""))


static func _set_stored_language(value: String) -> void:
	var l10n: Node = _l10n()
	PlayerConfig.set_config(String(l10n.SETTING_SECTION), String(l10n.SETTING_KEY), value)


static func _erase_stored_language() -> void:
	var l10n: Node = _l10n()
	PlayerConfig.erase_section_key(String(l10n.SETTING_SECTION), String(l10n.SETTING_KEY))


## The whitelist mapping the autoload applies to the system language.
static func _expected_system_language() -> String:
	var system_code: String = OS.get_locale_language()
	if system_code == "en" or system_code == "zh":
		return system_code
	return "en"


static func _snapshot_state() -> Dictionary:
	return {
		"had_key": PlayerConfig.has_section_key("GameSettings", "Language"),
		"value": _stored_language(),
		"locale": TranslationServer.get_locale(),
	}


static func _restore_state(snapshot: Dictionary) -> void:
	if bool(snapshot["had_key"]):
		_set_stored_language(String(snapshot["value"]))
	else:
		_erase_stored_language()
	TranslationServer.set_locale(String(snapshot["locale"]))
	var l10n: Node = _l10n()
	if l10n != null:
		l10n.apply_stored_preference()


static func _case_csv_translations_loaded(ctx: Dictionary) -> void:
	var ok: bool = FileAccess.file_exists(CSV_PATH)
	# The pipeline is wired through the internationalization project setting.
	var translations: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	var has_localization_entry: bool = false
	for entry: String in translations:
		if entry.contains("localization"):
			has_localization_entry = true
	ok = ok and has_localization_entry
	# tr() contract on the snake seed keys, per locale (a probe object runs
	# the same TranslationServer lookup an in-scene tr() call would).
	var probe := Control.new()
	_tree().root.add_child(probe)
	TranslationServer.set_locale("zh")
	for key: String in SEED_KEYS:
		ok = ok and probe.tr(key) == String((SEED_KEYS[key] as Array)[1])
	TranslationServer.set_locale("en")
	for key: String in SEED_KEYS:
		ok = ok and probe.tr(key) == String((SEED_KEYS[key] as Array)[0])
	# Text-equal keys power auto-translate rendering of untouched .text
	# literals (BC-06).
	TranslationServer.set_locale("zh")
	for key: String in AUTO_TRANSLATE_KEYS:
		ok = ok and probe.tr(key) == String(AUTO_TRANSLATE_KEYS[key])
	# BD-12: difficulty labels stay English — no text-equal key may exist.
	probe.free()
	for key: String in FORBIDDEN_DIFFICULTY_KEYS:
		TranslationServer.set_locale("zh")
		ok = ok and TranslationServer.translate(key) == key
	_case(ctx, "csv_translations_loaded", ok)


static func _case_language_follows_system_when_unset(ctx: Dictionary) -> void:
	_erase_stored_language()
	var fresh: Node = _new_localization()
	fresh.apply_stored_preference()
	var expected: String = _expected_system_language()
	var ok: bool = fresh.get_language() == expected
	ok = ok and TranslationServer.get_locale() == expected
	# The persisted preference stays absent after a follow-system apply.
	ok = ok and _stored_language() == ""
	fresh.free()
	_case(ctx, "language_follows_system_when_unset", ok)


static func _case_language_override_persists_and_prioritizes(ctx: Dictionary) -> void:
	var ok: bool = true
	_erase_stored_language()
	var l10n: Node = _l10n()
	# Explicit selection applies immediately and persists (BD-16).
	l10n.set_language("en")
	ok = ok and l10n.get_language() == "en"
	ok = ok and TranslationServer.get_locale() == "en"
	PlayerConfig.config_file = null
	var direct_file := ConfigFile.new()
	ok = ok and direct_file.load(CONFIG_LOCATION) == OK
	ok = ok and String(direct_file.get_value("GameSettings", "Language", "")) == "en"
	# Simulated restart: a fresh instance reads the persisted preference and
	# it wins over a (simulated) zh system language.
	TranslationServer.set_locale("zh")
	var fresh: Node = _new_localization()
	fresh.apply_stored_preference()
	ok = ok and fresh.get_language() == "en"
	ok = ok and TranslationServer.get_locale() == "en"
	fresh.free()
	# Whitelist discipline: unknown values are ignored entirely.
	l10n.set_language("fr")
	ok = ok and l10n.get_language() == "en"
	ok = ok and _stored_language() == "en"
	# Clearing falls back to following the system language.
	l10n.set_language("")
	ok = ok and l10n.get_language() == _expected_system_language()
	ok = ok and _stored_language() == ""
	_case(ctx, "language_override_persists_and_prioritizes", ok)


static func _case_language_option_present_without_new_tab(ctx: Dictionary) -> void:
	var ok: bool = true
	# OD-06: the language control lives on the reachable Video page
	# (video_options_menu_with_extras) - the Game page is not referenced by
	# the master options menu, so hosting the option there would be
	# unreachable from the player path.
	var menu: Node = await _spawn_scene(VIDEO_WITH_EXTRAS_PATH)
	var option_button: OptionButton = null
	if menu != null:
		option_button = menu.find_child("LanguageOptionButton", true, false) as OptionButton
	ok = ok and menu != null and option_button != null
	if option_button != null:
		ok = ok and option_button.item_count == 2
		ok = ok and option_button.get_item_text(0) == "English"
		ok = ok and option_button.get_item_text(1) == "中文"
		# The selection mirrors the effective language.
		ok = ok and option_button.selected == (1 if _l10n().get_language() == "zh" else 0)
		# Selecting applies immediately and persists through PlayerConfig.
		option_button.item_selected.emit(1)
		ok = ok and _l10n().get_language() == "zh"
		ok = ok and TranslationServer.get_locale() == "zh"
		ok = ok and _stored_language() == "zh"
		ok = ok and option_button.selected == 1
		option_button.item_selected.emit(0)
		ok = ok and _l10n().get_language() == "en"
		ok = ok and _stored_language() == "en"
	if menu != null:
		menu.free()
	# No new options tab (BC-06: OPTIONS_TAB_COUNT frozen at 4).
	var tabs: Node = await _spawn_scene(MASTER_TABS_PATH)
	ok = ok and tabs is TabContainer and (tabs as TabContainer).get_tab_count() == FROZEN_TAB_COUNT
	if tabs != null:
		tabs.free()
	_case(ctx, "language_option_present_without_new_tab", ok)


static func _case_cjk_font_loads_with_glyphs(ctx: Dictionary) -> void:
	var ok: bool = true
	var font: Font = load(FUSION_FONT_PATH) as Font
	ok = ok and font != null
	if font != null:
		# 中 / 文 / 难 spot checks (dispatch case e).
		ok = ok and font.has_char(0x4E2D)
		ok = ok and font.has_char(0x6587)
		ok = ok and font.has_char(0x96BE)
	# The wiring resource behind gui/theme/custom_font is a Font that also
	# resolves the CJK glyphs (BF-11).
	var ui_font: Font = load(UI_FONT_PATH) as Font
	ok = ok and ui_font != null and ui_font.has_char(0x4E2D)
	# S6: the in-game Kenney HUD fonts carry the Fusion Pixel font as a
	# fallback (BF-11). The font resource cache can swap instances across the
	# startup frames, so the assertion reproduces the consumer discipline:
	# trigger the idempotent wiring on the live autoload first, then check
	# the same-frame loads. Probed by glyph identity rather than resource
	# identity so the assertion survives resource reloads.
	var l10n: Node = _l10n()
	ok = ok and l10n != null
	for path: String in KENNEY_FONT_PATHS:
		# Consumer discipline: load first, then trigger the idempotent wiring
		# (exactly what main.gd/versus.gd do), then verify the instance the
		# load returned carries a CJK-capable fallback. Probed by glyph
		# identity rather than resource identity so the assertion survives
		# resource reloads.
		var kenney: FontFile = load(path) as FontFile
		ok = ok and kenney != null
		if kenney == null:
			continue
		if l10n != null and l10n.has_method("ensure_cjk_fallbacks"):
			l10n.ensure_cjk_fallbacks()
		var has_cjk_fallback: bool = false
		for fallback: Font in kenney.fallbacks:
			if fallback != null and fallback.has_char(0x4E2D):
				has_cjk_fallback = true
		ok = ok and has_cjk_fallback
	# The wiring itself: main.gd and versus.gd must re-trigger the fallback
	# after loading their font overrides.
	ok = ok and _read_source(MAIN_SOURCE_PATH).contains("ensure_cjk_fallbacks")
	ok = ok and _read_source(VERSUS_SOURCE_PATH).contains("ensure_cjk_fallbacks")
	_case(ctx, "cjk_font_loads_with_glyphs", ok)


static func _case_menu_text_keys_untouched(ctx: Dictionary) -> void:
	var ok: bool = true
	var select: Node = await _spawn_scene(MODE_SELECT_PATH)
	ok = ok and select != null
	if select != null:
		# 2026-10-12: the Classic / Versus entries became the setup page's own
		# choices; the same rule holds for them.
		var classic: Node = select.find_child("VersusSpeedRisingSpeed", true, false)
		var start: Node = select.find_child("VersusStartButton", true, false)
		# Frozen semantics (BC-06, same standard as test_menu.gd): .text
		# keeps the English literal; rendering translation is separate.
		ok = ok and classic is Button and (classic as Button).text == "Classic"
		ok = ok and start is Button and (start as Button).text == "Start Match"
		select.free()
	_case(ctx, "menu_text_keys_untouched", ok)


## S6 full first-party copy coverage (O-06/BD-15): every Button/Label text in
## the first-party menu scenes either has a zh entry in the TranslationServer
## or is in the explicit exemption list (BD-12 difficulty words, language-
## neutral digits, runtime-projected config values — see COVERAGE_EXEMPT_TEXTS).
static func _case_first_party_copy_covered(ctx: Dictionary) -> void:
	var ok: bool = true
	var missing: Array[String] = []
	var checked: int = 0
	var exempt: int = 0
	TranslationServer.set_locale("zh")
	for scene_path: String in [MAIN_MENU_PATH, MODE_SELECT_PATH, PAUSE_MENU_PATH]:
		var scene: Node = await _spawn_scene(scene_path)
		ok = ok and scene != null
		if scene == null:
			continue
		for node: Node in scene.find_children("*", "", true, false):
			if not (node is Button or node is Label):
				continue
			var text: String = (node as Control).text
			if text.is_empty():
				continue
			checked += 1
			if TranslationServer.translate(text) != text:
				continue
			# A label the game writes already translated copy into (the setup
			# page's description and LAN status) turns auto-translate off.
			if (node as Control).auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED:
				exempt += 1
				continue
			# "<Resource Pack>: <pack name>" is composed at runtime: the label
			# part is translated, the pack's own name is a proper name.
			if node.name == &"ResourcePackButton":
				ok = ok and text.begins_with(TranslationServer.translate("Resource Pack") + ": ") \
					and TranslationServer.translate("Resource Pack") != "Resource Pack"
				exempt += 1
				continue
			if COVERAGE_EXEMPT_TEXTS.has(text):
				exempt += 1
				continue
			missing.append("%s: %s" % [scene_path.get_file(), text])
		scene.free()
	ok = ok and missing.is_empty()
	for entry: String in missing:
		(ctx["lines"] as Array).append("MISSING zh: %s" % entry)
	(ctx["lines"] as Array).append("INFO coverage: %d texts checked, %d exempt, %d missing" % [checked, exempt, missing.size()])
	_case(ctx, "first_party_copy_covered", ok)


## S6 dynamic copy coverage (O-06/BD-15): the per-frame overlay strings can
## never be covered by auto-translate, so the zh entries must exist for their
## format keys and versus.gd/main.gd must route them through tr() before the
## % substitution.
static func _case_dynamic_overlay_translated(ctx: Dictionary) -> void:
	var ok: bool = true
	var probe := Control.new()
	_tree().root.add_child(probe)
	TranslationServer.set_locale("zh")
	for key: String in DYNAMIC_OVERLAY_KEYS:
		ok = ok and TranslationServer.translate(key) != key
	ok = ok and TranslationServer.translate(GAME_OVER_SCORE_KEY) != GAME_OVER_SCORE_KEY
	# Concrete formatted samples of the pipeline: tr(format-key) then %.
	ok = ok and probe.tr("PLAYER WINS ROUND %d") % 1 == "玩家赢下第 1 局"
	# Revised 2026-10-10: the versus overlay reports rows sent (what decides a
	# match) instead of the single-player score.
	ok = ok and probe.tr("LINES SENT %d : %d") % [7, 3] == "送出行数 7 : 3"
	ok = ok and probe.tr(GAME_OVER_SCORE_KEY) % 42 == "得分 42"
	probe.free()
	# The wiring itself: the overlay assignments must call tr() with each
	# format key in versus.gd, and the game-over score line in main.gd.
	var versus_source: String = _read_source(VERSUS_SOURCE_PATH)
	var main_source: String = _read_source(MAIN_SOURCE_PATH)
	ok = ok and not versus_source.is_empty() and not main_source.is_empty()
	for key: String in DYNAMIC_OVERLAY_KEYS:
		ok = ok and versus_source.contains('tr("%s")' % key)
	ok = ok and main_source.contains('tr("%s")' % GAME_OVER_SCORE_KEY)
	_case(ctx, "dynamic_overlay_translated", ok)
