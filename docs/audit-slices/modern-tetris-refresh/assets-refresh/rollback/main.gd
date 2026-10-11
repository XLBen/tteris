extends Node
## RECONSTRUCTED BASELINE SNAPSHOT (not the original rollback bytes).
##
## Provenance: the original pre-assets-refresh main.gd snapshot kept here by
## the modern-tetris-refresh goal was lost from the workspace. Rebuilt on
## 2026-09-18 by the delivery controller with owner authorization (OD-01
## follow-up): the SFX map below is the documented pre-refresh state, derived
## from the orphaned interface files left on disk (confirmation_004.ogg /
## maximize_002.ogg are exactly the two predecessors of the SFX_DELTA_KEYS
## "tetris"/"resume" that the assets-refresh swapped to the digital pack).
## Purpose: test_assets.gd tripwire - the current SFX map must keep differing
## from this baseline for the delta keys (i.e. the crisp replacements stay).

const SFX_FILES: Dictionary = {
	"move": "res://assets/audio/interface/tick_002.ogg",
	"rotate": "res://assets/audio/interface/switch_004.ogg",
	"hold": "res://assets/audio/interface/toggle_003.ogg",
	"hard_drop": "res://assets/audio/interface/drop_003.ogg",
	"lock": "res://assets/audio/interface/drop_001.ogg",
	"clear": "res://assets/audio/interface/glass_004.ogg",
	"tetris": "res://assets/audio/interface/confirmation_004.ogg",
	"level_up": "res://assets/audio/interface/confirmation_002.ogg",
	"game_over": "res://assets/audio/interface/error_004.ogg",
	"pause": "res://assets/audio/interface/minimize_002.ogg",
	"resume": "res://assets/audio/interface/maximize_002.ogg",
}
