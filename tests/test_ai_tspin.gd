extends SceneTree
## T-Spin construction of the upper AI tiers (scripts/versus_ai.gd): finding
## the way into a slot (both rotations, slides, the Triple's fifth kick),
## valuing a slot stage by stage while it is built, keeping the T for it, not
## building when the stack is in danger, and actually landing T-Spin Doubles
## in open play.

const MODULE_NAME: String = "ai_tspin"

const LAB: GDScript = preload("res://tools/tspin_lab.gd")
const TICK: float = 1.0 / 30.0
const SOLO_SECONDS: float = 90.0
const SEED: int = 20261010

# Boards are written top to bottom, the last row is the floor row.
const FLAT: Array[String] = [
	"#########.",
	"#########.",
]
const NOTCH: Array[String] = [
	"####.#####",
	"##########",
]
const READY_HALF_FILLED: Array[String] = [
	"####......",
	"###...#...",
	"####.#####",
]
const ARMED: Array[String] = [
	"####......",
	"###...####",
	"####.#####",
]
const ROOFED_OVER: Array[String] = [
	"####.#....",
	"###...####",
	"####.#####",
]


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d ai tspin cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("AI TSPIN TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_upper_tiers_find_every_lab_entry(ctx)
	_case_slot_value_rises_stage_by_stage(ctx)
	_case_no_slot_building_in_danger_or_on_low_tiers(ctx)
	_case_t_is_kept_for_the_slot_and_brought_back(ctx)
	_case_lookahead_fires_the_armed_slot_and_hold_is_kept_for_the_t(ctx)
	_case_digging_starts_near_death_and_lasts_until_the_stack_is_clear(ctx)
	_case_upper_tiers_land_doubles_in_open_play(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


## A battle whose side 1 holds `rows` at the floor, side 0 frozen.
static func _battle_with(rows: Array[String], raise: int = 0) -> VersusBattle:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
	battle.debug_freeze_side(0, true)
	_paint(battle.board(1), rows, raise)
	return battle


static func _paint(board: Board, rows: Array[String], raise: int = 0) -> void:
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			board.set_cell(Vector2i(x, y), Board.EMPTY)
	# `raise` full-but-one rows under the pattern lift it off the floor.
	for i: int in raise:
		for x: int in range(Board.BOARD_WIDTH - 1):
			board.set_cell(Vector2i(x, Board.BOARD_HEIGHT - 1 - i), Board.GARBAGE)
	for i: int in rows.size():
		var y: int = Board.BOARD_HEIGHT - raise - rows.size() + i
		for x: int in Board.BOARD_WIDTH:
			if rows[i][x] == "#":
				board.set_cell(Vector2i(x, y), Board.GARBAGE)


static func _ai(battle: VersusBattle, tier: StringName) -> VersusAI:
	return VersusAI.new(battle, 1, VersusAI.DIFFICULTY_PROFILES[tier], SEED)


static func _slot_value(tier: StringName, rows: Array[String]) -> int:
	var battle: VersusBattle = _battle_with(rows)
	var ai: VersusAI = _ai(battle, tier)
	ai._ctx_t_near = true
	var grid: Array = ai._copy_board_grid(battle.board(1))
	return ai._tslot_value(grid, VersusAI._column_heights(grid))


static func _case_upper_tiers_find_every_lab_entry(ctx: Dictionary) -> void:
	var ok: bool = LAB.SCENARIOS.size() >= 5
	for tier: StringName in [&"hard", &"lunatic"]:
		for scenario: String in LAB.SCENARIOS:
			var result: Dictionary = LAB.run_scenario(scenario, tier)
			if not bool(result["ok"]):
				ok = false
				(ctx["lines"] as Array).append("DETAIL: %s missed %s (lines %d, keys %s)" % [tier, scenario, int(result["lines"]), " ".join(result["keys"])])
	# The entries really differ: one side needs the other rotation, the
	# Triple needs a slide under the roof before its rotation.
	var left: Array = LAB.run_scenario("tsd_left_overhang", &"lunatic")["keys"]
	var right: Array = LAB.run_scenario("tsd_right_overhang", &"lunatic")["keys"]
	var triple: Array = LAB.run_scenario("tst_right_nub", &"lunatic")["keys"]
	ok = ok and left.has("rotate") and not left.has("rotate_ccw") and right.has("rotate_ccw")
	ok = ok and triple.has("soft") and triple.find("left", triple.find("soft")) > 0
	_case(ctx, "upper_tiers_find_every_lab_entry_tsd_both_ways_and_tst", ok)


static func _case_slot_value_rises_stage_by_stage(ctx: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in [&"hard", &"lunatic"]:
		var flat: int = _slot_value(tier, FLAT)
		var notch: int = _slot_value(tier, NOTCH)
		var ready: int = _slot_value(tier, READY_HALF_FILLED)
		var armed: int = _slot_value(tier, ARMED)
		ok = ok and flat == 0 and notch > 0 and ready > notch and armed > ready
		# A slot roofed on both sides can no longer be entered: worth nothing.
		ok = ok and _slot_value(tier, ROOFED_OVER) == 0
		# With no T in sight the same slot is worth less, not nothing.
		var battle: VersusBattle = _battle_with(ARMED)
		var ai: VersusAI = _ai(battle, tier)
		var grid: Array = ai._copy_board_grid(battle.board(1))
		ai._ctx_t_near = false
		var far: int = ai._tslot_value(grid, VersusAI._column_heights(grid))
		ok = ok and far > 0 and far < armed
	_case(ctx, "slot_value_rises_notch_overhang_filled_rows", ok)


static func _case_no_slot_building_in_danger_or_on_low_tiers(ctx: Dictionary) -> void:
	var ok: bool = true
	# The lower tiers have no slot values at all.
	for tier: StringName in [&"easy", &"normal"]:
		ok = ok and int(VersusAI.DIFFICULTY_PROFILES[tier].get("tslot_ready", 0)) == 0
		ok = ok and VersusAI.DIFFICULTY_PROFILES[tier]["tspin_policy"] == &"none"
		var plain: VersusBattle = _battle_with(ARMED)
		var plain_ai: VersusAI = _ai(plain, tier)
		plain_ai._build_plan(plain.current_piece(1))
		ok = ok and not plain_ai._ctx_slot_started
	for tier: StringName in [&"hard", &"lunatic"]:
		ok = ok and VersusAI.DIFFICULTY_PROFILES[tier]["tspin_policy"] != &"none"
		# Low stack: the plan knows a slot is under construction.
		var low: VersusBattle = _battle_with(READY_HALF_FILLED)
		var low_ai: VersusAI = _ai(low, tier)
		low_ai._build_plan(low.current_piece(1))
		ok = ok and low_ai._ctx_slot_started and not low_ai._ctx_danger
		# The same slot on a stack near the top: survival first, no setup.
		var high: VersusBattle = _battle_with(READY_HALF_FILLED, 12)
		var high_ai: VersusAI = _ai(high, tier)
		high_ai._build_plan(high.current_piece(1))
		ok = ok and high_ai._ctx_danger and not high_ai._ctx_slot_started
	_case(ctx, "no_slot_building_in_danger_or_on_low_tiers", ok)


## A T that cannot make its double yet is put on hold; once the rows are full
## it comes back out and spins.
static func _case_t_is_kept_for_the_slot_and_brought_back(ctx: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in [&"hard", &"lunatic"]:
		var battle: VersusBattle = _battle_with(READY_HALF_FILLED)
		battle.debug_force_piece(1, Tetromino.PieceType.T, 0, battle.piece_pos(1), false, -1)
		var ai: VersusAI = _ai(battle, tier)
		var steps: int = 0
		while battle.hold_type(1) != Tetromino.PieceType.T and battle.pieces_placed(1) == 0 and steps < 600:
			battle.tick(1.0 / 60.0)
			ai.tick(1.0 / 60.0)
			steps += 1
		ok = ok and battle.hold_type(1) == Tetromino.PieceType.T and battle.pieces_placed(1) == 0 and ai.holds_made() == 1
		# The piece that came in for it is played. Then the rows are full
		# (painted in, as if the next pieces had filled them): within two
		# pieces the held T is swapped back in and spun for the double.
		steps = 0
		while battle.pieces_placed(1) == 0 and steps < 1200:
			battle.tick(1.0 / 60.0)
			ai.tick(1.0 / 60.0)
			steps += 1
		ok = ok and battle.pieces_placed(1) == 1 and battle.hold_type(1) == Tetromino.PieceType.T
		_paint(battle.board(1), ARMED)
		steps = 0
		while battle.pieces_placed(1) < 3 and battle.tspin_clears(1, 2) == 0 and steps < 2400:
			battle.tick(1.0 / 60.0)
			ai.tick(1.0 / 60.0)
			steps += 1
		ok = ok and battle.tspin_clears(1, 2) == 1 and ai.holds_made() >= 2 and battle.hold_type(1) != Tetromino.PieceType.T
	_case(ctx, "t_is_held_for_the_slot_and_swapped_back_to_spin", ok)


## The lookahead plays the Double of an armed slot with the T at hand (so
## arming a slot now is worth more than arming it later), and while a slot is
## being built the hold slot is not spent on stashing an I.
static func _case_lookahead_fires_the_armed_slot_and_hold_is_kept_for_the_t(ctx: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in [&"hard", &"lunatic"]:
		var armed: VersusBattle = _battle_with(ARMED)
		var ai: VersusAI = _ai(armed, tier)
		var grid: Array = ai._copy_board_grid(armed.board(1))
		var fired: Dictionary = ai._slot_fire(grid)
		ok = ok and not fired.is_empty() and VersusAI._max_height(fired["after"]) == 1
		# Rows not full yet: nothing to fire.
		var half: VersusBattle = _battle_with(READY_HALF_FILLED)
		var half_ai: VersusAI = _ai(half, tier)
		ok = ok and half_ai._slot_fire(half_ai._copy_board_grid(half.board(1))).is_empty()
		# The I is not stashed while a slot is under construction.
		half_ai._ctx_slot_started = true
		ok = ok and not half_ai._stash_i_piece(Tetromino.PieceType.I, 0)
		half_ai._ctx_slot_started = false
		ok = ok and half_ai._stash_i_piece(Tetromino.PieceType.I, 0)
	_case(ctx, "lookahead_fires_the_armed_slot_and_hold_is_kept_for_the_t", ok)


## Near death every tier switches to digging (clears first, no setups, a
## faster pace) and keeps digging until the stack is DANGER_RELEASE_ROWS under
## its danger line - it does not flip back the moment one row is gone.
static func _case_digging_starts_near_death_and_lasts_until_the_stack_is_clear(ctx: Dictionary) -> void:
	var ok: bool = VersusAI.DANGER_RELEASE_ROWS >= 2 and VersusAI.DANGER_PACE < 1.0
	for tier: StringName in [&"easy", &"normal", &"hard", &"lunatic"]:
		var danger_rows: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["danger_rows"])
		var battle: VersusBattle = _battle_with(FLAT, 2)
		var ai: VersusAI = _ai(battle, tier)
		# FLAT is two rows on top of `raise` rows.
		ai._build_plan(battle.current_piece(1))
		ok = ok and not ai._ctx_danger
		_paint(battle.board(1), FLAT, danger_rows - 1)
		ai._build_plan(battle.current_piece(1))
		ok = ok and ai._ctx_danger
		# Digging values a line cleared now far above the same line when safe,
		# and a lower peak above a higher one.
		var grid: Array = ai._copy_board_grid(battle.board(1))
		var before: int = ai._score_placement(grid, 0, 10)
		var tall: Array = grid.duplicate()
		tall[(Board.BOARD_HEIGHT - danger_rows - 3) * Board.BOARD_WIDTH] = Board.GARBAGE
		tall[(Board.BOARD_HEIGHT - danger_rows - 2) * Board.BOARD_WIDTH] = Board.GARBAGE
		ok = ok and before - ai._score_placement(tall, 0, 10) >= 2 * VersusAI.DANGER_PEAK_WEIGHT
		# One row under the line: still digging. Well clear of it: back to normal.
		_paint(battle.board(1), FLAT, danger_rows - 4)
		ai._build_plan(battle.current_piece(1))
		ok = ok and ai._ctx_danger
		_paint(battle.board(1), FLAT, danger_rows - VersusAI.DANGER_RELEASE_ROWS - 2)
		ai._build_plan(battle.current_piece(1))
		ok = ok and not ai._ctx_danger
	_case(ctx, "digging_starts_near_death_and_lasts_until_the_stack_is_clear", ok)


static func _case_upper_tiers_land_doubles_in_open_play(ctx: Dictionary) -> void:
	var ok: bool = true
	var doubles: Dictionary = {}
	for tier: StringName in [&"normal", &"hard", &"lunatic"]:
		var battle: VersusBattle = VersusBattle.new()
		battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
		battle.debug_freeze_side(0, true)
		var ai: VersusAI = _ai(battle, tier)
		var elapsed: float = 0.0
		while battle.phase() == VersusBattle.Phase.PLAYING and elapsed < SOLO_SECONDS:
			battle.tick(TICK)
			ai.tick(TICK)
			elapsed += TICK
		ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
		doubles[tier] = battle.tspin_clears(1, 2)
		(ctx["lines"] as Array).append("INFO %s: %d T-Spin Doubles in %d pieces" % [tier, battle.tspin_clears(1, 2), battle.pieces_placed(1)])
	# Building them is what separates the upper tiers: several doubles in a
	# minute and a half alone, none from a tier that does not spin.
	ok = ok and int(doubles[&"normal"]) == 0 and int(doubles[&"hard"]) >= 2 and int(doubles[&"lunatic"]) >= 2
	_case(ctx, "upper_tiers_build_and_land_tspin_doubles_in_open_play", ok)
