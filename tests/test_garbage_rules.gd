extends SceneTree
## Garbage rules (S1 garbage-modern-rules / BD-08): an attack first cancels the
## attacker's own queued incoming garbage 1:1 (FIFO batches), and only the
## remainder is appended as a new batch on the opponent's queue; the
## opponent's existing batches are never reduced by an incoming attack. The
## receiver still inserts its queue after its next lock (regression case).
##
## Everything drives the real model chain (setup -> debug_force_piece /
## debug_lock_now -> send/cancel/insert), never a mock. The fixed seed
## 20260917 reproduces the RNG-driven piece order and garbage holes.

const MODULE_NAME: String = "garbage_rules"

const SEED: int = 20260917

const SIDE_PLAYER: int = VersusBattle.Side.PLAYER
const SIDE_AI: int = VersusBattle.Side.AI
const PIECE_O: int = Tetromino.PieceType.O
const PIECE_J: int = Tetromino.PieceType.J


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d garbage rules cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("GARBAGE RULES TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_own_pending_cancelled_then_remainder_queued(ctx)
	_case_consecutive_same_side_attacks_accumulate(ctx)
	_case_both_directions_own_queue_cancellable(ctx)
	_case_pending_inserts_at_next_lock_regression(ctx)
	_case_zero_amount_and_exact_cancel_semantics(ctx)
	_case_fifo_multibatch_full_consume_with_remainder_queued(ctx)
	_case_partial_batch_cancel_leaves_nonzero_remainder_inserted(ctx)
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


# ---------------------------------------------------------------------------
# (a) The attacker's own queue is cancelled 1:1 first: with 3 rows queued on
#     the player, a Tetris (attack 4) spends 3 on the own queue and appends
#     only the 1-row remainder to the AI.
static func _case_own_pending_cancelled_then_remainder_queued(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	# Real AI chain: Single (attack 0, combo 1) then Triple
	# (base 2 + floor(combo 2 / 2) = 3) queues exactly 3 rows on the player.
	_ai_single(battle)
	_ai_triple(battle)
	var ok: bool = battle.pending_garbage(SIDE_PLAYER) == 3
	ok = ok and _batches_are(battle, SIDE_PLAYER, [3])
	# Player Tetris (attack 4): 3 cancelled from the own queue, 1 appended.
	_attack_tetris(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and _batches_are(battle, SIDE_PLAYER, [])
	ok = ok and battle.pending_garbage(SIDE_AI) == 1
	ok = ok and _batches_are(battle, SIDE_AI, [1])
	ok = ok and battle.attack_sent(SIDE_PLAYER) == 4
	_case(ctx, "own_pending_3_cancelled_by_tetris_4_remainder_1_queued_on_ai", ok)


# ---------------------------------------------------------------------------
# (b) Consecutive attacks from the same side accumulate as separate batches on
#     the opponent and never consume each other.
static func _case_consecutive_same_side_attacks_accumulate(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	var ok: bool = _batches_are(battle, SIDE_AI, [4]) and battle.pending_garbage(SIDE_AI) == 4
	# Combo reset, then a fresh Double (attack 1) as a second batch.
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	_attack_double_fresh(battle, SIDE_PLAYER)
	ok = ok and _batches_are(battle, SIDE_AI, [4, 1])
	ok = ok and battle.pending_garbage(SIDE_AI) == 5
	# Combo reset again, then another Tetris (attack 4) as a third batch.
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	_attack_tetris(battle, SIDE_PLAYER)
	ok = ok and _batches_are(battle, SIDE_AI, [4, 1, 4])
	ok = ok and battle.pending_garbage(SIDE_AI) == 9
	_case(ctx, "consecutive_same_side_attacks_accumulate_4_1_4_not_swallowed", ok)


# ---------------------------------------------------------------------------
# (c) Both directions: a side can cancel its own queue. The AI's real Tetris
#     (attack 4) exactly cancels the 4 rows the player queued, leaving both
#     queues empty with no 0-row batch anywhere (semantic zero).
static func _case_both_directions_own_queue_cancellable(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	var ok: bool = _batches_are(battle, SIDE_AI, [4]) and battle.pending_garbage(SIDE_AI) == 4
	_attack_tetris(battle, SIDE_AI)
	ok = ok and battle.pending_garbage(SIDE_AI) == 0
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and _batches_are(battle, SIDE_AI, [])
	ok = ok and _batches_are(battle, SIDE_PLAYER, [])
	ok = ok and battle.attack_sent(SIDE_AI) == 4
	_case(ctx, "ai_tetris_exactly_cancels_own_4_both_queues_empty", ok)


# ---------------------------------------------------------------------------
# (d) Regression: queue insertion timing is untouched. Pending garbage is not
#     inserted when queued; the receiver's next lock inserts it with a single
#     hole column per batch.
static func _case_pending_inserts_at_next_lock_regression(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	var ai_board: Board = battle.board(SIDE_AI)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 4
	ok = ok and ai_board.is_empty_board()
	_lock_noclear(battle, SIDE_AI, 8, 18)
	ok = ok and battle.pending_garbage(SIDE_AI) == 0
	var hole: int = _single_hole(ai_board, 20)
	ok = ok and hole >= 0 and hole < Board.BOARD_WIDTH
	ok = ok and _rows_are_garbage_with_hole(ai_board, 20, 23, hole)
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	_case(ctx, "pending_inserted_at_next_lock_4_rows_one_hole_regression", ok)


# ---------------------------------------------------------------------------
# (e) amount <= 0 is a no-op (no batch, no accounting) and an exact 1:1
#     cancel appends nothing (no zero-row batch) while the full attack is
#     still credited to the attacker.
static func _case_zero_amount_and_exact_cancel_semantics(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	# Player Single: attack 0 -> no batch anywhere and nothing accounted.
	_attack_single(battle, SIDE_PLAYER)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 0
	ok = ok and _batches_are(battle, SIDE_AI, [])
	ok = ok and battle.attack_sent(SIDE_PLAYER) == 0
	# AI Single (attack 0, combo 1) + Triple (attack 3) queues 3 on the player.
	_ai_single(battle)
	_ai_triple(battle)
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 3
	# Player Triple: combo_at_event 1 -> attack 2 + floor(2 / 2) = 3, exactly
	# cancelling the own queue; no remainder reaches the AI.
	_attack_triple(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and _batches_are(battle, SIDE_PLAYER, [])
	ok = ok and battle.pending_garbage(SIDE_AI) == 0
	ok = ok and _batches_are(battle, SIDE_AI, [])
	ok = ok and battle.attack_sent(SIDE_PLAYER) == 3
	_case(ctx, "zero_attack_no_batch_exact_cancel_no_zero_row_batch", ok)


# ---------------------------------------------------------------------------
# (f) FIFO across multiple batches: two queued batches [2, 1] are consumed in
#     queue order (both pops happen on the loop's second pass) and only the
#     1-row remainder crosses over to the AI. Once the own queue is fully
#     spent nothing is inserted on the player board.
static func _case_fifo_multibatch_full_consume_with_remainder_queued(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	# Build two real batches on the player: a fresh AI Triple (first clear of a
	# fresh combo, base 2 + floor(1 / 2) = attack 2) queues [2]; a combo-reset
	# lock + a fresh Double (attack 1) queues the second batch -> [2, 1].
	_attack_triple(battle, SIDE_AI)
	_lock_noclear(battle, SIDE_AI, 8, 18)
	_attack_double_fresh(battle, SIDE_AI)
	var ok: bool = battle.pending_garbage(SIDE_PLAYER) == 3
	ok = ok and _batches_are(battle, SIDE_PLAYER, [2, 1])
	# Player Tetris (first clear, attack 4): cancels 2, then 1 (the FIFO loop's
	# second iteration pops the last batch), remainder 1 appended to the AI.
	_attack_tetris(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and _batches_are(battle, SIDE_PLAYER, [])
	ok = ok and battle.pending_garbage(SIDE_AI) == 1
	ok = ok and _batches_are(battle, SIDE_AI, [1])
	ok = ok and _garbage_cells(battle.board(SIDE_PLAYER)) == 0
	ok = ok and battle.attack_sent(SIDE_PLAYER) == 4
	_case(ctx, "fifo_multibatch_full_consume_with_remainder_queued", ok)


# ---------------------------------------------------------------------------
# (g) Partial batch cancel: the single queued batch [3] is only partly spent by
#     an attack 2, so its non-zero remainder (1) stays inside the batch (no
#     pop) and no row crosses over to the AI. Revised 2026-10-10 (mainstream
#     rules): the clearing lock itself takes no garbage - the remainder waits
#     in the queue and enters on the player's next non-clearing lock.
static func _case_partial_batch_cancel_leaves_nonzero_remainder_inserted(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	# Reuse the (a) construction: AI Single (attack 0, combo 1) + Triple
	# (attack 3) queues the single batch [3] on the player.
	_ai_single(battle)
	_ai_triple(battle)
	var ok: bool = battle.pending_garbage(SIDE_PLAYER) == 3
	ok = ok and _batches_are(battle, SIDE_PLAYER, [3])
	# Player Triple (first clear of a fresh combo, attack 2): 3 - 2 leaves a
	# non-zero remainder of 1 written back into the batch.
	_attack_triple(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 1
	ok = ok and _batches_are(battle, SIDE_PLAYER, [1])
	ok = ok and _garbage_cells(battle.board(SIDE_PLAYER)) == 0
	ok = ok and battle.pending_garbage(SIDE_AI) == 0
	ok = ok and _batches_are(battle, SIDE_AI, [])
	ok = ok and battle.attack_sent(SIDE_PLAYER) == 2
	# The next lock that clears nothing takes the waiting row.
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and _batches_are(battle, SIDE_PLAYER, [])
	var player_board: Board = battle.board(SIDE_PLAYER)
	var hole: int = _single_hole(player_board, 23)
	ok = ok and hole >= 0 and hole < Board.BOARD_WIDTH
	ok = ok and _rows_are_garbage_with_hole(player_board, 23, 23, hole)
	# One garbage row = 9 garbage cells + exactly one hole; the I residue from
	# the clear sits higher and is not garbage.
	ok = ok and _garbage_cells(player_board) == 9
	_case(ctx, "partial_batch_cancel_leaves_nonzero_remainder_inserted", ok)


# ---------------------------------------------------------------------------
# Fixtures (same technique as test_debug_duel.gd / test_versus_battle.gd).
static func _new_battle() -> VersusBattle:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
	return battle


static func _force_lock(battle: VersusBattle, side: int, type: int, rotation: int, pos: Vector2i) -> void:
	battle.debug_force_piece(side, type, rotation, pos, false, -1)
	battle.debug_lock_now(side, true)


static func _fill_row_except(board: Board, row: int, except_columns: Array) -> void:
	for x: int in Board.BOARD_WIDTH:
		if not except_columns.has(x):
			board.set_cell(Vector2i(x, row), PIECE_J)


## Vertical I: rotation 1 renders its cells in local column 2, so pos.x + 2 is
## the world column it fills (rows 20-23).
static func _lock_vertical_i(battle: VersusBattle, side: int, column: int) -> void:
	_force_lock(battle, side, Tetromino.PieceType.I, 1, Vector2i(column - 2, 20))


## Resets and clears exactly one row: the first clear of a fresh combo, so the
## attack is the frozen Single value 0.
static func _attack_single(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	_fill_row_except(battle.board(side), 23, [6])
	_lock_vertical_i(battle, side, 6)


## Resets and clears exactly three rows as the 2nd consecutive clear:
## base 2 + floor(combo_count 2 / 2) = attack 3.
static func _attack_triple(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in [21, 22, 23]:
		_fill_row_except(battle.board(side), row, [6])
	_lock_vertical_i(battle, side, 6)


## Resets and clears four rows without a Perfect Clear (one residual cell above
## the cleared rows keeps the board non-empty).
static func _attack_tetris(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in range(20, 24):
		_fill_row_except(battle.board(side), row, [6])
	battle.board(side).set_cell(Vector2i(9, 19), PIECE_J)
	_lock_vertical_i(battle, side, 6)


## Resets and clears exactly two rows: the first clear of a fresh combo, so the
## attack is the frozen Double value 1.
static func _attack_double_fresh(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in [22, 23]:
		_fill_row_except(battle.board(side), row, [6])
	_lock_vertical_i(battle, side, 6)


## Resets and clears every row: a Perfect Clear (flat attack 10).
static func _attack_perfect_clear(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in range(20, 24):
		_fill_row_except(battle.board(side), row, [6])
	_lock_vertical_i(battle, side, 6)


## AI Single: attack 0 and combo 1, the first link of the real chain that makes
## the following Triple send exactly 3.
static func _ai_single(battle: VersusBattle) -> void:
	_attack_single(battle, SIDE_AI)


## AI Triple: the 2nd consecutive clear, base 2 + floor(2 / 2) = attack 3.
static func _ai_triple(battle: VersusBattle) -> void:
	_attack_triple(battle, SIDE_AI)


## Locks an O piece that clears nothing (`x`,`y` must be free and visible).
static func _lock_noclear(battle: VersusBattle, side: int, x: int, y: int) -> void:
	_force_lock(battle, side, PIECE_O, 0, Vector2i(x, y))


static func _batches_are(battle: VersusBattle, side: int, expected: Array[int]) -> bool:
	var batches: Array[int] = battle.pending_garbage_batches(side)
	if batches.size() != expected.size():
		return false
	for i: int in expected.size():
		if batches[i] != expected[i]:
			return false
	return true


static func _garbage_cells(board: Board) -> int:
	var total: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) == Board.GARBAGE:
				total += 1
	return total


static func _single_hole(board: Board, row: int) -> int:
	var hole: int = -1
	for x: int in Board.BOARD_WIDTH:
		if board.is_empty_at(Vector2i(x, row)):
			if hole != -1:
				return -2
			hole = x
	return hole


static func _rows_are_garbage_with_hole(board: Board, top: int, bottom: int, hole: int) -> bool:
	for row: int in range(top, bottom + 1):
		if _single_hole(board, row) != hole:
			return false
		for x: int in Board.BOARD_WIDTH:
			if x != hole and board.get_cell(Vector2i(x, row)) != Board.GARBAGE:
				return false
	return true
