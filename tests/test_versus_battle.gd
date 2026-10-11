extends SceneTree
## Versus battle rules (O-02/O-03): frozen send table, Perfect Clear, garbage
## batches (same hole per batch, re-randomized between batches), insertion
## timing, own-queue 1:1 cancel, the four top-out loss classes and seed
## reproducibility.
##
## Everything drives the real model chain (setup -> debug_force_piece ->
## debug_lock_now -> send/cancel/insert -> tick), never a mock.

const MODULE_NAME: String = "versus_battle"

## Fixed seeds: the same seed and input sequence must reproduce the exact match
## state (7-bag order and garbage hole columns come from the battle RNG).
const SEED: int = 20260917
const ALT_SEED: int = 97531

const SIDE_PLAYER: int = VersusBattle.Side.PLAYER
const SIDE_AI: int = VersusBattle.Side.AI
const PIECE_O: int = Tetromino.PieceType.O
const PIECE_J: int = Tetromino.PieceType.J


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d versus rules cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VERSUS RULES TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_send_table(ctx)
	_case_b2b_active_and_difficult(ctx)
	_case_combo_ladder(ctx)
	_case_perfect_clear_flat_10(ctx)
	_case_pc_resets_b2b_and_cancels(ctx)
	_case_garbage_insert_after_lock(ctx)
	_case_batch_holes_rerandomize(ctx)
	_case_attack_appends_when_own_queue_empty(ctx)
	_case_loss_garbage_overflow(ctx)
	_case_loss_garbage_pushes_stack_into_hidden(ctx)
	_case_loss_lock_all_hidden(ctx)
	_case_loss_spawn_blocked(ctx)
	_case_same_seed_same_sequence(ctx)
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


static func _new_battle(rules: int = VersusBattle.Rules.FIXED, fixed_level: int = 1, match_format: int = VersusBattle.MatchFormat.SINGLE, seed: int = SEED) -> VersusBattle:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(rules, fixed_level, match_format, seed)
	return battle


static func _fill_row_except(board: Board, row: int, except_columns: Array) -> void:
	for x: int in Board.BOARD_WIDTH:
		if not except_columns.has(x):
			board.set_cell(Vector2i(x, row), PIECE_J)


static func _force_lock(battle: VersusBattle, side: int, type: int, rotation: int, pos: Vector2i) -> void:
	battle.debug_force_piece(side, type, rotation, pos, false, -1)
	battle.debug_lock_now(side, true)


## Vertical I: rotation 1 renders its cells in local column 2, so pos.x + 2 is
## the world column it fills (rows 20-23).
static func _lock_vertical_i(battle: VersusBattle, side: int, column: int) -> void:
	_force_lock(battle, side, Tetromino.PieceType.I, 1, Vector2i(column - 2, 20))


## Four cleared rows without a Perfect Clear (rows 20-23 except the I column
## plus one residual cell above them, so the board is not empty afterwards).
static func _attack_tetris(battle: VersusBattle, side: int) -> void:
	var board: Board = battle.board(side)
	for row: int in range(20, 24):
		_fill_row_except(board, row, [6])
	board.set_cell(Vector2i(9, 19), PIECE_J)
	_lock_vertical_i(battle, side, 6)


## Resets the side's board and clears exactly two rows: the first clear of a
## combo, so the attack is the frozen Double value 1.
static func _attack_double_fresh(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in [22, 23]:
		_fill_row_except(battle.board(side), row, [6])
	_lock_vertical_i(battle, side, 6)


## Resets the side's board and clears every row -> Perfect Clear (attack 10).
static func _attack_perfect_clear(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in range(20, 24):
		_fill_row_except(battle.board(side), row, [6])
	_lock_vertical_i(battle, side, 6)


## Locks an O piece that clears nothing (`x`,`y` must be free and visible).
static func _lock_noclear(battle: VersusBattle, side: int, x: int, y: int) -> void:
	_force_lock(battle, side, PIECE_O, 0, Vector2i(x, y))


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


static func _batches_are(battle: VersusBattle, side: int, expected: Array[int]) -> bool:
	var batches: Array[int] = battle.pending_garbage_batches(side)
	if batches.size() != expected.size():
		return false
	for i: int in expected.size():
		if batches[i] != expected[i]:
			return false
	return true


# ---------------------------------------------------------------------------
# Frozen send table (BC-04/BQ-13).
static func _case_send_table(ctx: Dictionary) -> void:
	var none: int = Scoring.TSpinKind.NONE
	var mini: int = Scoring.TSpinKind.MINI
	var full: int = Scoring.TSpinKind.FULL
	var ok: bool = VersusBattle.PERFECT_CLEAR_SEND == 10
	ok = ok and VersusBattle.attack_for_event(1, none, false, 1, false) == 0
	ok = ok and VersusBattle.attack_for_event(2, none, false, 1, false) == 1
	ok = ok and VersusBattle.attack_for_event(3, none, false, 1, false) == 2
	ok = ok and VersusBattle.attack_for_event(4, none, false, 1, false) == 4
	ok = ok and VersusBattle.attack_for_event(1, full, false, 1, false) == 2
	ok = ok and VersusBattle.attack_for_event(2, full, false, 1, false) == 4
	ok = ok and VersusBattle.attack_for_event(3, full, false, 1, false) == 6
	# Revised 2026-10-10 (mainstream table): Mini Single 0, Mini Double 1.
	ok = ok and VersusBattle.attack_for_event(1, mini, false, 1, false) == 0
	ok = ok and VersusBattle.attack_for_event(2, mini, false, 1, false) == 1
	ok = ok and VersusBattle.attack_for_event(0, none, false, 1, false) == 0
	_case(ctx, "send_table_single0_double1_triple2_tetris4_tss2_tsd4_tst6_mini_0_1", ok)


static func _case_b2b_active_and_difficult(ctx: Dictionary) -> void:
	var none: int = Scoring.TSpinKind.NONE
	var mini: int = Scoring.TSpinKind.MINI
	var full: int = Scoring.TSpinKind.FULL
	var ok: bool = VersusBattle.attack_for_event(4, none, true, 1, false) == 5
	ok = ok and VersusBattle.attack_for_event(4, none, false, 1, false) == 4
	# Two lines are not a difficult clear: B2B never applies.
	ok = ok and VersusBattle.attack_for_event(2, none, true, 1, false) == 1
	ok = ok and VersusBattle.attack_for_event(1, none, true, 1, false) == 0
	ok = ok and VersusBattle.attack_for_event(1, full, true, 1, false) == 3
	ok = ok and VersusBattle.attack_for_event(1, full, false, 1, false) == 2
	ok = ok and VersusBattle.attack_for_event(2, mini, true, 1, false) == 2
	ok = ok and VersusBattle.attack_for_event(3, full, true, 1, false) == 7
	_case(ctx, "b2b_plus_one_only_when_active_and_difficult", ok)


static func _case_combo_ladder(ctx: Dictionary) -> void:
	var none: int = Scoring.TSpinKind.NONE
	var full: int = Scoring.TSpinKind.FULL
	# Tetris with combo_count 1..7 -> floor(combo/2) added.
	var expected: Array[int] = [4, 5, 5, 6, 6, 7, 7]
	var ok: bool = true
	for i: int in expected.size():
		ok = ok and VersusBattle.attack_for_event(4, none, false, i + 1, false) == expected[i]
	# Boundaries on a Double and a combined B2B + combo event.
	ok = ok and VersusBattle.attack_for_event(2, none, false, 1, false) == 1
	ok = ok and VersusBattle.attack_for_event(2, none, false, 2, false) == 2
	ok = ok and VersusBattle.attack_for_event(2, none, false, 3, false) == 2
	ok = ok and VersusBattle.attack_for_event(2, none, false, 4, false) == 3
	ok = ok and VersusBattle.attack_for_event(4, none, true, 4, false) == 7
	ok = ok and VersusBattle.attack_for_event(3, full, true, 5, false) == 9
	_case(ctx, "combo_bonus_floor_combo_over_2_ladder_boundaries", ok)


static func _case_perfect_clear_flat_10(ctx: Dictionary) -> void:
	var none: int = Scoring.TSpinKind.NONE
	var mini: int = Scoring.TSpinKind.MINI
	var full: int = Scoring.TSpinKind.FULL
	var ok: bool = VersusBattle.attack_for_event(1, none, false, 1, true) == 10
	ok = ok and VersusBattle.attack_for_event(4, none, false, 1, true) == 10
	ok = ok and VersusBattle.attack_for_event(4, none, true, 6, true) == 10
	ok = ok and VersusBattle.attack_for_event(2, mini, true, 3, true) == 10
	ok = ok and VersusBattle.attack_for_event(3, full, true, 5, true) == 10
	# No cleared lines can never be a Perfect Clear.
	ok = ok and VersusBattle.attack_for_event(0, none, true, 6, true) == 0
	_case(ctx, "perfect_clear_flat_10_ignores_lines_b2b_and_combo", ok)


## Revised 2026-10-10 (mainstream rules): a Perfect Clear sends the flat 10
## and no longer stops Back-to-Back, and one lock takes at most
## GARBAGE_CAP_PER_LOCK queued rows. The player's own queue is empty, so the
## flat 10 is queued as a new batch behind the AI's existing 4-row batch; the
## AI then needs two non-clearing locks to take all 14 rows; and the next
## Tetris still carries the B2B +1.
static func _case_pc_resets_b2b_and_cancels(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 4
	# Combo reset (B2B still active).
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	# Perfect Clear: flat 10 appended as a second batch -> AI holds [4, 10].
	_attack_perfect_clear(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_AI) == 14
	ok = ok and _batches_are(battle, SIDE_AI, [4, 10])
	# First AI lock: 8 rows enter (4 + 4 of the 10), 6 keep waiting.
	_lock_noclear(battle, SIDE_AI, 8, 18)
	ok = ok and battle.pending_garbage(SIDE_AI) == 6
	ok = ok and _batches_are(battle, SIDE_AI, [6])
	# Second AI lock (above the risen stack) takes the rest.
	_lock_noclear(battle, SIDE_AI, 8, 8)
	ok = ok and battle.pending_garbage(SIDE_AI) == 0
	# Combo reset again; the PC was a four-line clear, so B2B is still on and
	# this Tetris sends 4 + 1.
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	_attack_tetris(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_AI) == 5
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	_case(ctx, "pc_flat_10_keeps_b2b_and_garbage_enters_8_rows_per_lock", ok)
	_case(ctx, "pc_flat_10_then_tetris_attack_falls_back_to_4", ok)


## Pending garbage is not inserted when it is queued: it waits for the next
## lock, then inserts one batch with a single shared hole column.
static func _case_garbage_insert_after_lock(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	var ai_board: Board = battle.board(SIDE_AI)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 4
	ok = ok and _batches_are(battle, SIDE_AI, [4])
	ok = ok and ai_board.is_empty_board() and ai_board.highest_occupied_row() == -1
	_lock_noclear(battle, SIDE_AI, 8, 18)
	ok = ok and battle.pending_garbage(SIDE_AI) == 0
	ok = ok and not ai_board.is_empty_board()
	# The lock's O piece was pushed up by the four garbage rows...
	ok = ok and ai_board.get_cell(Vector2i(8, 14)) == PIECE_O
	ok = ok and ai_board.get_cell(Vector2i(8, 18)) == Board.EMPTY
	# ...and rows 20-23 are garbage sharing exactly one hole column.
	var hole: int = _single_hole(ai_board, 20)
	ok = ok and hole >= 0 and hole < Board.BOARD_WIDTH
	ok = ok and _rows_are_garbage_with_hole(ai_board, 20, 23, hole)
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	_case(ctx, "pending_not_inserted_until_next_lock_rows_are_garbage_one_hole", ok)


## Each inserted batch draws its own hole column (re-randomized per batch) and
## the same seed reproduces the same holes.
static func _case_batch_holes_rerandomize(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	_lock_noclear(battle, SIDE_AI, 8, 18)
	var ai_board: Board = battle.board(SIDE_AI)
	var first_hole: int = _single_hole(ai_board, 20)
	# Second batch: a fresh Double sends 1 (combo 1 -> bonus 1 => 2 total).
	_attack_double_fresh(battle, SIDE_PLAYER)
	var second_count: int = battle.pending_garbage(SIDE_AI)
	_lock_noclear(battle, SIDE_AI, 8, 10)
	var new_top: int = Board.BOARD_HEIGHT - second_count
	var second_hole: int = _single_hole(ai_board, new_top)
	var ok: bool = first_hole >= 0 and second_hole >= 0 and first_hole != second_hole
	ok = ok and _rows_are_garbage_with_hole(ai_board, new_top - 4, new_top - 1, first_hole)
	ok = ok and _rows_are_garbage_with_hole(ai_board, new_top, Board.BOARD_HEIGHT - 1, second_hole)
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	# Same seed, same input sequence -> identical hole columns.
	var replay: VersusBattle = _new_battle()
	_attack_tetris(replay, SIDE_PLAYER)
	_lock_noclear(replay, SIDE_AI, 8, 18)
	var replay_first: int = _single_hole(replay.board(SIDE_AI), 20)
	_attack_double_fresh(replay, SIDE_PLAYER)
	var replay_count: int = replay.pending_garbage(SIDE_AI)
	_lock_noclear(replay, SIDE_AI, 8, 10)
	var replay_second: int = _single_hole(replay.board(SIDE_AI), Board.BOARD_HEIGHT - replay_count)
	ok = ok and replay_first == first_hole and replay_second == second_hole
	_case(ctx, "batch_holes_rerandomize_between_batches_and_reseed_reproduces", ok)


## Modern rule with an empty attacker queue: the full attack is appended to the
## opponent as a new batch and the opponent's existing batches are kept (the
## old direction cancelled them).
static func _case_attack_appends_when_own_queue_empty(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_attack_tetris(battle, SIDE_PLAYER)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 4
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	# Double after a combo reset: attack exactly 1, appended as a second batch.
	_attack_double_fresh(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_AI) == 5
	ok = ok and _batches_are(battle, SIDE_AI, [4, 1])
	# Perfect Clear attack 10: appended as a third batch, no cancellation.
	_attack_perfect_clear(battle, SIDE_PLAYER)
	ok = ok and battle.pending_garbage(SIDE_AI) == 15
	ok = ok and _batches_are(battle, SIDE_AI, [4, 1, 10])
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	_case(ctx, "own_queue_empty_full_attack_appended_opponent_batches_kept", ok)


## Loss 1: a garbage insert that would push an occupied cell out of the board
## top (overflow) loses the round for the pushed side.
static func _case_loss_garbage_overflow(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	battle.board(SIDE_AI).set_cell(Vector2i(0, 0), PIECE_J)
	_attack_double_fresh(battle, SIDE_PLAYER)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 1
	_lock_noclear(battle, SIDE_AI, 8, 18)
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	battle.tick(0.0)
	ok = ok and battle.round_winner() == SIDE_PLAYER
	ok = ok and battle.match_winner() == SIDE_PLAYER
	ok = ok and battle.round_wins(SIDE_PLAYER) == 1 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.phase() == VersusBattle.Phase.MATCH_OVER
	_case(ctx, "loss_garbage_overflow_top_row_occupied_player_wins", ok)


## Revised 2026-10-10 (mainstream rules): garbage that pushes the stack into
## the hidden rows is NOT a loss by itself - the side keeps playing until its
## spawn is blocked, a piece locks out, or cells leave the 24-row buffer.
static func _case_loss_garbage_pushes_stack_into_hidden(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	var ai_board: Board = battle.board(SIDE_AI)
	for y: int in range(3, Board.BOARD_HEIGHT):
		ai_board.set_cell(Vector2i(0, y), PIECE_J)
	_attack_double_fresh(battle, SIDE_PLAYER)
	var ok: bool = battle.pending_garbage(SIDE_AI) == 1
	_lock_noclear(battle, SIDE_AI, 8, 18)
	ok = ok and ai_board.get_cell(Vector2i(0, 2)) == PIECE_J
	ok = ok and ai_board.highest_occupied_row() == 2
	battle.tick(0.0)
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	ok = ok and battle.round_winner() == -1 and battle.current_piece(SIDE_AI) != null
	_case(ctx, "garbage_pushing_stack_into_hidden_rows_does_not_lose", ok)


## Loss 3: a lock whose every cell is hidden loses the round.
static func _case_loss_lock_all_hidden(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_force_lock(battle, SIDE_PLAYER, PIECE_O, 0, Vector2i(0, 2))
	var ok: bool = battle.phase() == VersusBattle.Phase.PLAYING
	battle.tick(0.0)
	ok = ok and battle.round_winner() == SIDE_AI
	ok = ok and battle.round_wins(SIDE_AI) == 1 and battle.round_wins(SIDE_PLAYER) == 0
	ok = ok and battle.match_winner() == SIDE_AI
	ok = ok and battle.phase() == VersusBattle.Phase.MATCH_OVER
	_case(ctx, "loss_lock_all_hidden_gives_opponent_the_round", ok)


## Loss 4: the next spawn is blocked by the board content.
static func _case_loss_spawn_blocked(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	var next_type: int = battle.next_queue(SIDE_AI)[0]
	var spawn_pos: Vector2i = Vector2i((Board.BOARD_WIDTH - Tetromino.MATRIX_SIZES[next_type]) / 2, Board.HIDDEN_HEIGHT - 2)
	var probe: Tetromino = Tetromino.new(next_type)
	for cell: Vector2i in probe.get_cells():
		battle.board(SIDE_AI).set_cell(spawn_pos + cell, PIECE_J)
	_lock_noclear(battle, SIDE_AI, 8, 18)
	var ok: bool = battle.phase() == VersusBattle.Phase.PLAYING
	battle.tick(0.0)
	ok = ok and battle.round_winner() == SIDE_PLAYER
	ok = ok and battle.round_wins(SIDE_PLAYER) == 1 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.phase() == VersusBattle.Phase.MATCH_OVER
	_case(ctx, "loss_blocked_spawn_gives_opponent_the_round", ok)


## Same seed + same input sequence -> byte-identical state at every step; a
## different seed changes the RNG-driven state.
static func _case_same_seed_same_sequence(ctx: Dictionary) -> void:
	var first: String = str(_repro_scenario(SEED))
	var second: String = str(_repro_scenario(SEED))
	var other: String = str(_repro_scenario(ALT_SEED))
	var ok: bool = first == second
	ok = ok and first != other
	_case(ctx, "same_seed_same_inputs_identical_state", ok)


static func _repro_scenario(seed: int) -> Array:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 3, VersusBattle.MatchFormat.BEST_OF_3, seed)
	var states: Array = [_snapshot(battle)]
	_attack_tetris(battle, SIDE_PLAYER)
	states.append(_snapshot(battle))
	_lock_noclear(battle, SIDE_AI, 8, 18)
	states.append(_snapshot(battle))
	_attack_double_fresh(battle, SIDE_PLAYER)
	states.append(_snapshot(battle))
	_lock_noclear(battle, SIDE_AI, 8, 10)
	states.append(_snapshot(battle))
	for i: int in 12:
		battle.tick(0.05)
	states.append(_snapshot(battle))
	return states


static func _snapshot(battle: VersusBattle) -> Dictionary:
	return {
		"phase": battle.phase(),
		"match_winner": battle.match_winner(),
		"round_winner": battle.round_winner(),
		"round_wins": [battle.round_wins(0), battle.round_wins(1)],
		"round_index": battle.round_index(),
		"pending": [battle.pending_garbage(0), battle.pending_garbage(1)],
		"batches": [battle.pending_garbage_batches(0), battle.pending_garbage_batches(1)],
		"score": [battle.score(0), battle.score(1)],
		"lines": [battle.lines(0), battle.lines(1)],
		"level": [battle.level(0), battle.level(1)],
		"hold": [battle.hold_type(0), battle.hold_type(1)],
		"next": [battle.next_queue(0), battle.next_queue(1)],
		"pieces": [_piece_id(battle, 0), _piece_id(battle, 1)],
		"pos": [battle.piece_pos(0), battle.piece_pos(1)],
		"cells": [_board_cells(battle.board(0)), _board_cells(battle.board(1))],
	}


static func _piece_id(battle: VersusBattle, side: int) -> int:
	var piece: Tetromino = battle.current_piece(side)
	if piece == null:
		return -1
	return int(piece.piece_type)


static func _board_cells(board: Board) -> Array[int]:
	var cells: Array[int] = []
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			cells.append(board.get_cell(Vector2i(x, y)))
	return cells
