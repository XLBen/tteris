extends Node
## Localization bootstrap (S5 l10n infrastructure, BD-14/BD-15/BD-16).
##
## Registered as the Localization autoload. On startup it applies the UI
## language in priority order (BD-16):
##   1. the explicit preference persisted through the PlayerConfig pipeline
##      (user://player_config.cfg, GameSettings/Language — the same config
##      file the template settings use, BF-12),
##   2. the system language when no valid preference is stored, mapped onto
##      the supported whitelist ["en", "zh"]; unknown system languages fall
##      back to English.
## Translations come from the Godot CSV translation pipeline
## (assets/localization/localization.csv, imported into TranslationServer via
## the internationalization/locale/translations project setting). Control
## texts keep their English source strings in the scenes; Godot auto-translate
## renders them per locale, so .text literals stay untouched (BC-06).
##
## Chinese rendering (BF-11): the project default font
## (gui/theme/custom_font -> assets/localization/ui_font.tres, a FontVariation
## based on the Fusion Pixel zh_hans font) carries the CJK glyphs, so every
## default-font UI text renders without tofu in either language. The in-game
## Kenney HUD fonts are explicit overrides owned by main.gd/versus.gd; the
## idempotent ensure_cjk_fallbacks() hook below (run at startup and re-run by
## the game scenes after loading their fonts) attaches the same Fusion Pixel
## font to those three FontFile resources as a global fallback (S6), so the
## zh copy rendered in-game (game-over text, versus overlay) has glyphs in
## either language.

## Whitelisted UI languages (BD-14). Adding a language later means a new CSV
## column plus one entry here.
const SUPPORTED_LANGUAGES: Array[String] = ["en", "zh"]
const DEFAULT_LANGUAGE: String = "en"

## The exact font paths main.gd and versus.gd load for the in-game HUD.
const KENNEY_FONT_PATHS: Array[String] = [
	"res://assets/fonts/Kenney Future.ttf",
	"res://assets/fonts/Kenney Mini.ttf",
	"res://assets/fonts/Kenney Mini Square Mono.ttf",
]
const FUSION_FONT_PATH: String = "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"

## Preference storage rides the existing PlayerConfig pipeline (BF-12): the
## template's GameSettings section of user://player_config.cfg.
const SETTING_SECTION: String = "GameSettings"
const SETTING_KEY: String = "Language"

var _current_language: String = DEFAULT_LANGUAGE


func _ready() -> void:
	ensure_cjk_fallbacks()
	apply_stored_preference()


## Attaches the Fusion Pixel CJK font to the three Kenney FontFile resources
## as a fallback (BF-11). Idempotent: a fallback that is already present is
## never appended twice.
##
## Wiring note: besides this _ready call, main.gd and versus.gd call this
## right after loading their font overrides. load() resolves through the
## shared resource cache, so within one frame a consumer holds the exact
## instance this function mutates; the extra call guarantees the font
## instances the game scenes actually loaded carry the fallback even if the
## resource cache swaps instances across the startup frames (observed in
## --script runs). One call therefore covers every label sharing the font.
func ensure_cjk_fallbacks() -> void:
	var fusion: Font = load(FUSION_FONT_PATH) as Font
	if fusion == null:
		return
	for path: String in KENNEY_FONT_PATHS:
		var kenney: FontFile = load(path) as FontFile
		if kenney == null or kenney.fallbacks.has(fusion):
			continue
		var fallbacks: Array[Font] = kenney.fallbacks
		fallbacks.append(fusion)
		kenney.fallbacks = fallbacks


## Re-applies the stored preference to TranslationServer. Public so tests can
## simulate a restart with a fresh instance (BD-16 persistence priority).
func apply_stored_preference() -> void:
	_apply_language(_stored_language_or_system())


## Selects the UI language: persists it through the PlayerConfig pipeline and
## applies it immediately. An empty string clears the stored preference and
## returns to following the system language (BD-16 default). Values outside
## the whitelist are ignored.
func set_language(lang: String) -> void:
	if lang.is_empty():
		PlayerConfig.erase_section_key(SETTING_SECTION, SETTING_KEY)
		_apply_language(_system_language())
		return
	if not SUPPORTED_LANGUAGES.has(lang):
		return
	PlayerConfig.set_config(SETTING_SECTION, SETTING_KEY, lang)
	_apply_language(lang)


## The currently effective language ("en" or "zh").
func get_language() -> String:
	return _current_language


## Explicit preference wins over the system language (BD-16); a stored value
## outside the whitelist counts as unset.
func _stored_language_or_system() -> String:
	var stored: String = String(PlayerConfig.get_config(SETTING_SECTION, SETTING_KEY, ""))
	if SUPPORTED_LANGUAGES.has(stored):
		return stored
	return _system_language()


func _system_language() -> String:
	var system_code: String = OS.get_locale_language()
	if SUPPORTED_LANGUAGES.has(system_code):
		return system_code
	return DEFAULT_LANGUAGE


func _apply_language(lang: String) -> void:
	if not SUPPORTED_LANGUAGES.has(lang):
		return
	_current_language = lang
	TranslationServer.set_locale(lang)
