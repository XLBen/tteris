extends HBoxContainer
## Language option control (S5 l10n infrastructure, BD-14/BD-16).
##
## Hosted on the reachable Video options page (the Game page is not referenced
## by the master options menu). Picking an entry applies it immediately through
## the Localization autoload, which persists the choice via the shared
## PlayerConfig pipeline. Entry names are native-language names and are never
## translated.

const LANGUAGE_CODES: Array[String] = ["en", "zh"]

@onready var _option_button: OptionButton = $LanguageOptionButton


func _ready() -> void:
	# Entries are built here instead of serialized in the scene so the
	# OptionButton stays a bare themed control like its neighbours.
	if _option_button != null and _option_button.item_count == 0:
		_option_button.add_item("English")
		_option_button.add_item("中文")
	_refresh_language_selection()


func _on_LanguageOptionButton_item_selected(index: int) -> void:
	var localization: Node = _localization()
	if localization == null:
		return
	var code_index: int = clampi(index, 0, LANGUAGE_CODES.size() - 1)
	localization.set_language(LANGUAGE_CODES[code_index])
	_refresh_language_selection()


## The selected entry always mirrors the effective language, including after
## a restart where the stored preference wins over the system language.
func _refresh_language_selection() -> void:
	if _option_button == null:
		return
	var localization: Node = _localization()
	if localization == null:
		return
	_option_button.select(LANGUAGE_CODES.find(String(localization.get_language())))


# Same autoload lookup pattern as main.gd/versus.gd: node path on the root,
# no global identifier (keeps headless script checks working).
func _localization() -> Node:
	return get_tree().root.get_node_or_null(^"Localization")
