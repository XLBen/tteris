extends Node
## Cross-scene play session: the mode selected in the menu and the level rules
## it implies.
##
## Registered as the GameSession autoload. The menu flow stores the chosen mode
## here before loading the game scene; the game scene reads it on restart so
## the mode stays active for the whole run (including R restarts). When no
## session is available the game keeps the classic behavior: start at level 1
## and raise the level every ten cleared lines.
##
## Modes (brief-v4 BD-05/BD-06):
## - classic: starts at level 1 and gains a level every
##   Scoring.LINES_PER_LEVEL cleared lines, capped at level 15. There is no
##   time-based upgrade.
## - versus: player vs AI configuration (speed rules, fixed level, AI
##   difficulty, match format, running round score) for scenes/versus.

const MODE_NONE: StringName = &"none"
const MODE_CLASSIC: StringName = &"classic"
const MODE_VERSUS: StringName = &"versus"

const VERSUS_RULES_FIXED: StringName = &"fixed"
const VERSUS_RULES_RISING: StringName = &"rising"
const VERSUS_FORMAT_SINGLE: StringName = &"single"
const VERSUS_FORMAT_BEST_OF_3: StringName = &"best_of_3"
const VERSUS_FIXED_LEVEL_MIN: int = 1
const VERSUS_FIXED_LEVEL_MAX: int = 10
const VERSUS_DIFFICULTY_EASY: StringName = &"easy"
const VERSUS_DIFFICULTY_NORMAL: StringName = &"normal"
const VERSUS_DIFFICULTY_HARD: StringName = &"hard"
const VERSUS_DIFFICULTY_LUNATIC: StringName = &"lunatic"
const VERSUS_DIFFICULTY_EXTRA: StringName = &"extra"

var mode: StringName = MODE_NONE
var versus_rules: StringName = &""
var versus_fixed_level: int = 0
var versus_match_format: StringName = &""
## AI difficulty chosen in the versus sub-UI (BD-06): memory-only, never
## persisted; an empty session or a direct versus scene launch reads as the
## normal default.
var versus_difficulty: StringName = VERSUS_DIFFICULTY_NORMAL
## AI tier that plays the left board (CPU vs CPU, the human only watches);
## empty when the human plays it.
var versus_left_difficulty: StringName = &""
## Round wins as [player, ai]; versus_round_index is 1-based.
var versus_round_wins: Array[int] = [0, 0]
var versus_round_index: int = 1
var versus_match_in_progress: bool = false
## Set by the versus result screen's "Change Settings": the mode select opens
## straight on the versus setup page and clears the flag.
var open_versus_setup: bool = false
## Which versus setup the menu opens: player vs CPU, CPU vs CPU, or two
## players over the local network.
const PAGE_PVE: StringName = &"pve"
const PAGE_EVE: StringName = &"eve"
const PAGE_LAN: StringName = &"lan"
var versus_page: StringName = PAGE_PVE
## LAN match role of this machine: empty (not a LAN match), "host" (runs the
## battle) or "client" (shows the host's battle and sends its keys).
var versus_lan: StringName = &""
## One line for the LAN page to show when it opens (a lost connection).
var lan_notice: String = ""


func start_mode(new_mode: StringName) -> void:
	mode = new_mode
	if new_mode != MODE_VERSUS:
		_reset_versus_config()


func start_classic() -> void:
	start_mode(MODE_CLASSIC)


## `lan` is this machine's role in a LAN match ("host" / "client"), empty for
## a match against (or between) CPUs.
func start_versus(rules: StringName, fixed_level: int, match_format: StringName, difficulty: StringName = VERSUS_DIFFICULTY_NORMAL, left_difficulty: StringName = &"", lan: StringName = &"") -> void:
	mode = MODE_VERSUS
	versus_lan = lan
	versus_left_difficulty = left_difficulty
	versus_rules = rules
	versus_fixed_level = fixed_level
	versus_match_format = match_format
	versus_difficulty = difficulty
	versus_round_wins = [0, 0]
	versus_round_index = 1
	versus_match_in_progress = true


func is_classic() -> bool:
	return mode == MODE_CLASSIC


func is_versus() -> bool:
	return mode == MODE_VERSUS


func initial_level() -> int:
	if is_versus() and versus_rules == VERSUS_RULES_FIXED:
		return versus_fixed_level
	return 1


func save_versus_progress(round_wins: Array, round_index: int) -> void:
	# Cross-scene reload save for the versus scene (T-08): accepts any
	# two-value int array and copies it so the session never aliases an array
	# owned by the match.
	versus_round_wins = [int(round_wins[0]), int(round_wins[1])]
	versus_round_index = round_index


func _reset_versus_config() -> void:
	versus_rules = &""
	versus_fixed_level = 0
	versus_match_format = &""
	versus_difficulty = VERSUS_DIFFICULTY_NORMAL
	versus_left_difficulty = &""
	versus_round_wins = [0, 0]
	versus_round_index = 1
	versus_match_in_progress = false
	versus_lan = &""
