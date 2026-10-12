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
	_case_modes_are_a_state_machine(ctx)
	_case_tetris_mode_stacks_flat_around_a_well(ctx)
	_case_perfect_clears_are_found_and_played(ctx)
	_case_tspin_builds_give_up_and_spins_must_clear(ctx)
	_case_tucks_reach_under_overhangs(ctx)
	await _case_lookahead_plays_the_held_piece(ctx)
	_case_digging_speeds_up_with_the_height(ctx)
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


static func _ai(battle: VersusBattle, tier: StringName, spinning: bool = true) -> VersusAI:
	var ai: VersusAI = VersusAI.new(battle, 1, VersusAI.DIFFICULTY_PROFILES[tier], SEED)
	# These cases are about T-Spin building: the tiers that can are put in
	# that mode (which attack a tier goes for is otherwise drawn, see the
	# mode cases).
	if spinning and VersusAI.DIFFICULTY_PROFILES[tier]["tspin_policy"] != &"none":
		ai.force_mode(VersusAI.Mode.TSPIN)
	return ai


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
## faster pace) and keeps digging until the stack is down to its attack_rows
## (revised 2026-10-11, owner: down to a handful of rows before it attacks
## again) - it does not flip back the moment one row is gone.
static func _case_digging_starts_near_death_and_lasts_until_the_stack_is_clear(ctx: Dictionary) -> void:
	var ok: bool = VersusAI.DANGER_PACE < 1.0
	for tier: StringName in [&"easy", &"normal", &"hard", &"lunatic"]:
		var danger_rows: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["danger_rows"])
		var attack_rows: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["attack_rows"])
		ok = ok and attack_rows <= 6 and attack_rows <= danger_rows - 3
		var battle: VersusBattle = _battle_with(FLAT, 2)
		var ai: VersusAI = _ai(battle, tier)
		# FLAT is two rows on top of `raise` rows.
		ai._build_plan(battle.current_piece(1))
		ok = ok and not ai._ctx_danger and ai.mode() != VersusAI.Mode.DIG
		_paint(battle.board(1), FLAT, danger_rows - 1)
		ai._build_plan(battle.current_piece(1))
		ok = ok and ai._ctx_danger and ai.mode() == VersusAI.Mode.DIG and ai.mode_name() == "DIG"
		# Digging values a line cleared now far above the same line when safe,
		# and a lower peak above a higher one.
		var grid: Array = ai._copy_board_grid(battle.board(1))
		var before: int = ai._score_placement(grid, 0, 10)
		var tall: Array = grid.duplicate()
		tall[(Board.BOARD_HEIGHT - danger_rows - 3) * Board.BOARD_WIDTH] = Board.GARBAGE
		tall[(Board.BOARD_HEIGHT - danger_rows - 2) * Board.BOARD_WIDTH] = Board.GARBAGE
		ok = ok and before - ai._score_placement(tall, 0, 10) >= 2 * VersusAI.DANGER_PEAK_WEIGHT
		# Under the line, even a row over attack_rows: still digging. Down
		# to attack_rows: back to an attack.
		_paint(battle.board(1), FLAT, danger_rows - 4)
		ai._build_plan(battle.current_piece(1))
		ok = ok and ai._ctx_danger
		_paint(battle.board(1), FLAT, attack_rows - 1)
		ai._build_plan(battle.current_piece(1))
		ok = ok and ai._ctx_danger and ai.mode() == VersusAI.Mode.DIG
		_paint(battle.board(1), FLAT, attack_rows - 2)
		ai._build_plan(battle.current_piece(1))
		ok = ok and not ai._ctx_danger and ai.mode() != VersusAI.Mode.DIG
	_case(ctx, "digging_starts_near_death_and_lasts_until_the_stack_is_clear", ok)


static func _case_upper_tiers_land_doubles_in_open_play(ctx: Dictionary) -> void:
	var ok: bool = true
	var doubles: Dictionary = {}
	for tier: StringName in [&"normal", &"hard", &"lunatic"]:
		var battle: VersusBattle = VersusBattle.new()
		battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
		battle.debug_freeze_side(0, true)
		var ai: VersusAI = _ai(battle, tier, false)
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


## What a tier goes for is a state machine (VersusAI.Mode): a tier without a
## well just stacks, one without T-Spins stacks for Tetrises, the upper tiers
## draw one of the two attacks - again after every attack that landed, and
## when they come out of digging.
static func _case_modes_are_a_state_machine(ctx: Dictionary) -> void:
	var ok: bool = VersusAI.MODE_NAMES.size() == VersusAI.Mode.size()
	var battle: VersusBattle = _battle_with(FLAT, 2)
	ok = ok and _ai(battle, &"easy").mode() == VersusAI.Mode.STACK and _ai(battle, &"normal").mode() == VersusAI.Mode.TETRIS
	for tier: StringName in [&"hard", &"lunatic"]:
		var share: float = float(VersusAI.DIFFICULTY_PROFILES[tier]["tetris_share"])
		ok = ok and share > 0.1 and share < 0.9
		var ai: VersusAI = _ai(battle, tier, false)
		var drawn: Dictionary = {VersusAI.Mode.TETRIS: 0, VersusAI.Mode.TSPIN: 0}
		for _i: int in 200:
			var mode: int = ai._draw_attack_mode()
			ok = ok and drawn.has(mode)
			drawn[mode] = int(drawn.get(mode, 0)) + 1
		ok = ok and absf(float(drawn[VersusAI.Mode.TETRIS]) / 200.0 - share) < 0.12
		# An attack that landed draws the next one; nothing else changes a mode
		# on a calm board.
		ai.force_mode(VersusAI.Mode.TSPIN)
		var grid: Array = ai._copy_board_grid(battle.board(1))
		for _i: int in 5:
			ai._update_mode(grid, 4)
		ok = ok and ai.mode() == VersusAI.Mode.TSPIN and ai.mode_changes() == 0
		var seen: Dictionary = {}
		for _i: int in 60:
			ai._attack_landed = true
			ai._update_mode(grid, 4)
			seen[ai.mode()] = true
		ok = ok and seen.size() == 2 and seen.has(VersusAI.Mode.TETRIS) and seen.has(VersusAI.Mode.TSPIN)
		# Stacking for a Tetris builds no slots and keeps no T for one.
		var slot: VersusBattle = _battle_with(READY_HALF_FILLED)
		var flat_ai: VersusAI = _ai(slot, tier, false)
		flat_ai.force_mode(VersusAI.Mode.TETRIS)
		flat_ai._build_plan(slot.current_piece(1))
		ok = ok and flat_ai.mode() == VersusAI.Mode.TETRIS and not flat_ai._ctx_slot_started and flat_ai.mode_name() == "TETRIS"
	_case(ctx, "ai_modes_are_a_state_machine", ok)


## Stacking for a Tetris: any column can be the well (the lowest one when the
## mode starts), the rest is kept flat, and the I pieces score Tetrises.
static func _case_tetris_mode_stacks_flat_around_a_well(ctx: Dictionary) -> void:
	var ok: bool = true
	# The well goes where the stack is lowest: here the fourth column.
	var dented: VersusBattle = _battle_with(FLAT, 2)
	for row: int in range(Board.BOARD_HEIGHT - 4, Board.BOARD_HEIGHT):
		dented.board(1).set_cell(Vector2i(Board.BOARD_WIDTH - 1, row), Board.GARBAGE)
		dented.board(1).set_cell(Vector2i(3, row), Board.EMPTY)
	var picker: VersusAI = _ai(dented, &"lunatic", false)
	picker.force_mode(VersusAI.Mode.DIG)
	picker._tetris_share = 1.0
	picker._update_mode(picker._copy_board_grid(dented.board(1)), 4)
	ok = ok and picker.mode() == VersusAI.Mode.TETRIS and picker.well_column() == 3
	for tier: StringName in [&"hard", &"lunatic"]:
		var battle: VersusBattle = VersusBattle.new()
		battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
		battle.debug_freeze_side(0, true)
		var profile: Dictionary = (VersusAI.DIFFICULTY_PROFILES[tier] as Dictionary).duplicate()
		profile["tetris_share"] = 1.0
		var ai: VersusAI = VersusAI.new(battle, 1, profile, SEED)
		var tetrises: int = 0
		var elapsed: float = 0.0
		while battle.phase() == VersusBattle.Phase.PLAYING and elapsed < SOLO_SECONDS:
			battle.tick(TICK)
			ai.tick(TICK)
			elapsed += TICK
			for event: Dictionary in battle.drain_events():
				if event["type"] == &"clear" and int(event["side"]) == 1 and int(event["lines"]) == 4:
					tetrises += 1
		(ctx["lines"] as Array).append("INFO %s stacking for Tetrises: %d Tetrises, %d T-Spin Doubles in %d pieces" % [
			tier, tetrises, battle.tspin_clears(1, 2), battle.pieces_placed(1)])
		ok = ok and battle.phase() == VersusBattle.Phase.PLAYING and ai.mode() != VersusAI.Mode.TSPIN
		# A Tetris needs ten pieces: a good share of them becomes one.
		ok = ok and tetrises >= 4 and tetrises * 40 >= battle.pieces_placed(1)
	_case(ctx, "tetris_mode_stacks_flat_around_a_well", ok)


## A Perfect Clear a few plain drops away is searched for and played before
## anything else (2026-10-12, owner: the CPU missed them), with the hold piece
## when the line needs it; how far a tier looks is its pc_pieces.
static func _case_perfect_clears_are_found_and_played(ctx: Dictionary) -> void:
	var o: int = Tetromino.PieceType.O
	var i: int = Tetromino.PieceType.I
	var s: int = Tetromino.PieceType.S
	var ok: bool = int(VersusAI.DIFFICULTY_PROFILES[&"easy"].get("pc_pieces", 0)) == 0
	var one: Array[String] = ["########..", "########.."]
	var three: Array[String] = ["####......", "####......"]
	for tier: StringName in [&"normal", &"hard", &"lunatic"]:
		var reach: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["pc_pieces"])
		var battle: VersusBattle = _battle_with(one)
		var ai: VersusAI = _ai(battle, tier, false)
		var grid: Array = ai._copy_board_grid(battle.board(1))
		var none: Array[int] = []
		# The O fits: one move. An S does not, but the O behind it (next, or
		# on hold) does: hold first. Nothing that fits: no line.
		var first: Dictionary = ai._find_perfect_clear(grid, o, none, -1, true)
		ok = ok and not first.is_empty() and not bool(first["hold"])
		var queue: Array[int] = [o, s]
		first = ai._find_perfect_clear(grid, s, queue, -1, true)
		ok = ok and not first.is_empty() and bool(first["hold"])
		first = ai._find_perfect_clear(grid, s, none, o, true)
		ok = ok and not first.is_empty() and bool(first["hold"])
		ok = ok and ai._find_perfect_clear(grid, s, queue, -1, false).is_empty()
		ok = ok and ai._find_perfect_clear(grid, s, none, -1, true).is_empty()
		# Three pieces away: only for the tiers that look that far.
		var far: VersusBattle = _battle_with(three)
		var far_grid: Array = ai._copy_board_grid(far.board(1))
		queue = [i, o, s]
		ok = ok and ai._find_perfect_clear(far_grid, i, queue, -1, true).is_empty() == (reach < 3)
		# Too tall a stack is not searched at all.
		var tall: VersusBattle = _battle_with(one, 4)
		ok = ok and ai._find_perfect_clear(ai._copy_board_grid(tall.board(1)), o, none, -1, true).is_empty()
		# Played for real: the O goes in and the board is empty.
		battle.debug_force_piece(1, o, 0, battle.piece_pos(1), false, -1)
		var perfect: bool = false
		var steps: int = 0
		while battle.pieces_placed(1) == 0 and steps < 1200:
			battle.tick(1.0 / 60.0)
			ai.tick(1.0 / 60.0)
			steps += 1
			for event: Dictionary in battle.drain_events():
				if event["type"] == &"clear" and int(event["side"]) == 1 and bool(event["perfect_clear"]):
					perfect = true
		ok = ok and perfect and ai.perfect_clear_plans() == 1 and battle.attack_sent(1) == VersusBattle.PERFECT_CLEAR_SEND
	# Stacking for a Tetris, a Perfect Clear made with fewer lines still counts
	# as the ten rows it sends.
	var battle: VersusBattle = _battle_with(one)
	var stacker: VersusAI = _ai(battle, &"lunatic", false)
	stacker.force_mode(VersusAI.Mode.TETRIS)
	var empty: Array = []
	empty.resize(Board.BOARD_WIDTH * Board.BOARD_HEIGHT)
	empty.fill(Board.EMPTY)
	var left: Array = empty.duplicate()
	left[(Board.BOARD_HEIGHT - 1) * Board.BOARD_WIDTH] = Board.GARBAGE
	ok = ok and stacker._score_placement(empty, 2, 10) - stacker._score_placement(left, 2, 10) > 5 * int(VersusAI.DIFFICULTY_PROFILES[&"lunatic"]["attack_weight"])
	_case(ctx, "perfect_clears_are_found_and_played", ok)


## A T-Spin build that does not come together within the tier's tspin_patience
## pieces is given up for Tetris stacking, and the T is not spun into places
## where it clears nothing and a plain drop lands it just the same
## (2026-10-12, owner: the CPU clung to its T-Spins and spun empty minis).
static func _case_tspin_builds_give_up_and_spins_must_clear(ctx: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in [&"hard", &"lunatic"]:
		var patience: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["tspin_patience"])
		ok = ok and patience >= 8 and not bool(VersusAI.DIFFICULTY_PROFILES[tier].get("empty_spins", false))
		var battle: VersusBattle = _battle_with(FLAT, 2)
		var ai: VersusAI = _ai(battle, tier)
		var grid: Array = ai._copy_board_grid(battle.board(1))
		for _i: int in patience:
			ai._update_mode(grid, 4)
		ok = ok and ai.mode() == VersusAI.Mode.TSPIN
		ai._update_mode(grid, 4)
		ok = ok and ai.mode() == VersusAI.Mode.TETRIS
		# Alone for a while: the spins that land clear lines.
		var counts: Dictionary = {}
		for spins_empty: bool in [false, true]:
			var solo: VersusBattle = VersusBattle.new()
			solo.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
			solo.debug_freeze_side(0, true)
			var profile: Dictionary = (VersusAI.DIFFICULTY_PROFILES[tier] as Dictionary).duplicate()
			profile["empty_spins"] = spins_empty
			var player: VersusAI = VersusAI.new(solo, 1, profile, SEED)
			var empty: int = 0
			var elapsed: float = 0.0
			while solo.phase() == VersusBattle.Phase.PLAYING and elapsed < SOLO_SECONDS:
				solo.tick(TICK)
				player.tick(TICK)
				elapsed += TICK
				for event: Dictionary in solo.drain_events():
					if event["type"] == &"spin" and int(event["side"]) == 1:
						empty += 1
			counts[spins_empty] = empty
			(ctx["lines"] as Array).append("INFO %s, empty spins %s: %d spins that cleared nothing in %d pieces" % [tier, "allowed" if spins_empty else "off", empty, solo.pieces_placed(1)])
		ok = ok and int(counts[false]) <= 1 and int(counts[false]) <= int(counts[true])
	_case(ctx, "tspin_builds_give_up_and_spins_must_clear", ok)



## Tucks (2026-10-12, owner): the upper tiers also plan the places only a
## slide or a turn after the soft drop reaches - here the I turned in under an
## overhang to finish the bottom row - and play them.
static func _case_tucks_reach_under_overhangs(ctx: Dictionary) -> void:
	var cave: Array[String] = ["#...######", "....######"]
	var ok: bool = int(VersusAI.DIFFICULTY_PROFILES[&"normal"].get("tuck_depth", 0)) == 0
	for tier: StringName in [&"hard", &"lunatic"]:
		ok = ok and int(VersusAI.DIFFICULTY_PROFILES[tier]["tuck_depth"]) >= 1
		var battle: VersusBattle = _battle_with(cave)
		# (Without the hold: an I that scores no Tetris would be put away.)
		var profile: Dictionary = (VersusAI.DIFFICULTY_PROFILES[tier] as Dictionary).duplicate()
		profile["hold_policy"] = &"none"
		var ai: VersusAI = VersusAI.new(battle, 1, profile, SEED)
		var grid: Array = ai._copy_board_grid(battle.board(1))
		# No straight drop lays the I on the floor under the overhang; a drop
		# beside it and one grounded move does.
		var floor_row: int = Board.BOARD_HEIGHT - 1
		var under: Dictionary = {}
		for entry: Dictionary in ai._reachable_tucks(grid, Tetromino.PieceType.I, {}):
			var cells: Array[Vector2i] = entry["cells"]
			var columns: Array[int] = []
			for cell: Vector2i in cells:
				if int(entry["y"]) + cell.y == floor_row:
					columns.append(int(entry["x"]) + cell.x)
			columns.sort()
			if columns == [0, 1, 2, 3]:
				under = entry
		ok = ok and not under.is_empty() and bool(under["tuck"]) and (under["moves"] as Array).size() == 1
		ok = ok and ai._drop_y(grid, VersusAI._piece_shapes(Tetromino.PieceType.I)[0], 0) < int(under.get("y", 0))
		# Played for real: the row is cleared with that one piece.
		battle.debug_force_piece(1, Tetromino.PieceType.I, 0, battle.piece_pos(1), false, -1)
		var steps: int = 0
		while battle.pieces_placed(1) == 0 and steps < 1800:
			battle.tick(1.0 / 60.0)
			ai.tick(1.0 / 60.0)
			steps += 1
		ok = ok and battle.pieces_placed(1) == 1 and battle.lines(1) == 1 and ai.tucks_planned() == 1 and ai.stuck_drops() == 0
		# A tier that does not tuck finds no such place.
		var plain: VersusAI = _ai(battle, &"normal", false)
		ok = ok and plain._reachable_tucks(grid, Tetromino.PieceType.I, {}).is_empty()
	_case(ctx, "tucks_reach_under_overhangs", ok)


## Hold inside the lookahead (2026-10-12, owner): on the upper tiers every
## step of the search may play the held piece instead of the queued one, and
## the hold tap itself is decided by comparing the two lines. While digging
## only: building an attack, the slot is for the I and the T kept for it
## (measured: with the search holding there too, the tiers stacked half as
## many Tetrises).
static func _case_lookahead_plays_the_held_piece(ctx: Dictionary) -> void:
	var o: int = Tetromino.PieceType.O
	var s: int = Tetromino.PieceType.S
	var slot: Array[String] = ["########..", "########.."]
	var ok: bool = not bool(VersusAI.DIFFICULTY_PROFILES[&"normal"].get("hold_lookahead", false))
	for tier: StringName in [&"hard", &"lunatic"]:
		ok = ok and bool(VersusAI.DIFFICULTY_PROFILES[tier]["hold_lookahead"])
		var battle: VersusBattle = _battle_with(slot)
		var ai: VersusAI = _ai(battle, tier, false)
		var grid: Array = ai._copy_board_grid(battle.board(1))
		var queue: Array[int] = [s, s]
		var base: int = ai._score_placement(grid, 0, 10)
		# The S alone cannot use the gap; with an O on hold the step plays it.
		ai._plan_sims = 0
		var as_it_comes: int = await ai._beam_follow_value(grid, queue, 0, 1, base)
		ai._plan_sims = 0
		var with_hold: int = await ai._beam_follow_value(grid, queue, 0, 1, base, false, o)
		ai._plan_sims = 0
		var empty_slot: int = await ai._beam_follow_value(grid, queue, 0, 1, base, false, -1)
		ok = ok and with_hold > as_it_comes + 1000 and empty_slot == as_it_comes
		# With the slot empty the hold tap brings the next piece.
		queue = [s, o]
		ai._plan_sims = 0
		ok = ok and await ai._beam_follow_value(grid, queue, 0, 1, base, false, -1) == with_hold
		# Buried, the lookahead decides hold taps; on a calm board it does not.
		ok = ok and not bool(VersusAI.DIFFICULTY_PROFILES[tier].get("hold_lookahead_attack", false))
		var calm: VersusBattle = _battle_with(FLAT, 2)
		var calm_ai: VersusAI = _ai(calm, tier, false)
		calm_ai._build_plan(calm.current_piece(1))
		ok = ok and not calm_ai._ctx_hold_search
		var solo: VersusBattle = _battle_with(FLAT, 13)
		var player: VersusAI = _ai(solo, tier, false)
		var elapsed: float = 0.0
		while solo.phase() == VersusBattle.Phase.PLAYING and elapsed < 30.0 and solo.pieces_placed(1) < 40:
			solo.tick(TICK)
			player.tick(TICK)
			elapsed += TICK
		(ctx["lines"] as Array).append("INFO %s: %d of %d hold taps decided by the lookahead in %d pieces" % [tier, player.searched_holds(), player.holds_made(), solo.pieces_placed(1)])
		ok = ok and solo.phase() == VersusBattle.Phase.PLAYING and player.searched_holds() >= 1
	_case(ctx, "lookahead_plays_the_held_piece", ok)


## The higher the stack, the faster the digging (2026-10-12, owner): the time
## per piece shrinks step by step from attack_rows up, and never grows.
static func _case_digging_speeds_up_with_the_height(ctx: Dictionary) -> void:
	var ok: bool = VersusAI.DANGER_PACE_TOP < VersusAI.DANGER_PACE
	for tier: StringName in [&"easy", &"normal", &"hard", &"lunatic"]:
		var battle: VersusBattle = _battle_with(FLAT, 2)
		var ai: VersusAI = _ai(battle, tier, false)
		var danger_rows: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["danger_rows"])
		var attack_rows: int = int(VersusAI.DIFFICULTY_PROFILES[tier]["attack_rows"])
		var before: float = 1.0
		for rows: int in range(0, Board.BOARD_HEIGHT + 4):
			ai._ctx_pressure = rows
			var pace: float = ai._dig_pace()
			ok = ok and pace <= before + 0.0001
			before = pace
		ai._ctx_pressure = attack_rows
		ok = ok and is_equal_approx(ai._dig_pace(), 1.0)
		ai._ctx_pressure = danger_rows
		ok = ok and is_equal_approx(ai._dig_pace(), VersusAI.DANGER_PACE)
		ai._ctx_pressure = VersusAI.DANGER_TOP_ROWS
		ok = ok and is_equal_approx(ai._dig_pace(), VersusAI.DANGER_PACE_TOP)
		# Buried, the tier really plays faster than its cruise pace.
		var deep: VersusBattle = _battle_with(FLAT, 14)
		var digger: VersusAI = _ai(deep, tier, false)
		var elapsed: float = 0.0
		while deep.phase() == VersusBattle.Phase.PLAYING and deep.pieces_placed(1) < 6 and elapsed < 60.0:
			deep.tick(1.0 / 60.0)
			digger.tick(1.0 / 60.0)
			elapsed += 1.0 / 60.0
		ok = ok and deep.pieces_placed(1) == 6 and 6.0 / elapsed > 1.1 * float(VersusAI.DIFFICULTY_PROFILES[tier]["pps"])
	_case(ctx, "digging_speeds_up_with_the_height", ok)
