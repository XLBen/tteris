extends SceneTree
## Versus match shell (T-07b1): single-match end, best-of-3 round progression,
## same-tick double top-out draw replay, the restart_round reset surface, pause
## freeze and the classic level threshold.
##
## Everything drives the real model chain (setup -> debug_force_piece /
## debug_lock_now -> press / tap -> tick), never a mock. The fixed seed
## 20260917 reproduces the RNG-driven pieces and garbage holes.

const MODULE_NAME: String = "versus_match"

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
		print("FAILED: %d of %d versus match cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VERSUS MATCH TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_single_match_top_out(ctx)
	_case_best_of_3_progression(ctx)
	_case_same_tick_double_top_out_draw(ctx)
	_case_restart_round_clears_round_state(ctx)
	_case_pause_freezes_and_resume_advances(ctx)
	_case_classic_level_threshold_and_restart(ctx)
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


static func _new_battle(rules: int = VersusBattle.Rules.FIXED, fixed_level: int = 1, match_format: int = VersusBattle.MatchFormat.SINGLE, round_wins: Array = [0, 0], round_index: int = 1) -> VersusBattle:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(rules, fixed_level, match_format, SEED, round_wins, round_index)
	return battle


# ---------------------------------------------------------------------------
# 1) Single match: one top-out ends the whole match for the opponent.
static func _case_single_match_top_out(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE)
	var index_before: int = battle.round_index()
	_top_out(battle, SIDE_PLAYER)
	var ok: bool = battle.phase() == VersusBattle.Phase.PLAYING
	battle.tick(0.0)
	ok = ok and battle.phase() == VersusBattle.Phase.MATCH_OVER
	ok = ok and battle.match_winner() == SIDE_AI
	ok = ok and battle.round_winner() == SIDE_AI
	ok = ok and battle.round_wins(SIDE_PLAYER) == 0 and battle.round_wins(SIDE_AI) == 1
	ok = ok and battle.round_index() == index_before and index_before == 1
	ok = ok and not battle.last_round_draw()
	_case(ctx, "single_match_player_top_out_ai_wins_match_over_wins_0_1_index_kept", ok)


# ---------------------------------------------------------------------------
# 2) Best of 3: round wins accumulate, the index advances between rounds and
#    the second win ends the match.
static func _case_best_of_3_progression(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.BEST_OF_3)
	# R1: the AI tops out, the player takes the round but not the match.
	_top_out(battle, SIDE_AI)
	battle.tick(0.0)
	var ok: bool = battle.phase() == VersusBattle.Phase.ROUND_OVER
	ok = ok and battle.round_winner() == SIDE_PLAYER and battle.match_winner() == -1
	ok = ok and battle.round_wins(SIDE_PLAYER) == 1 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.round_index() == 1
	battle.start_round()
	ok = ok and battle.round_index() == 2 and battle.phase() == VersusBattle.Phase.PLAYING
	# R2: the player tops out, the AI levels the match at 1:1.
	_top_out(battle, SIDE_PLAYER)
	battle.tick(0.0)
	ok = ok and battle.phase() == VersusBattle.Phase.ROUND_OVER
	ok = ok and battle.round_wins(SIDE_PLAYER) == 1 and battle.round_wins(SIDE_AI) == 1
	ok = ok and battle.match_winner() == -1 and battle.round_index() == 2
	battle.start_round()
	ok = ok and battle.round_index() == 3
	# R3: the AI tops out, the player takes the match at 2:1.
	_top_out(battle, SIDE_AI)
	battle.tick(0.0)
	ok = ok and battle.round_wins(SIDE_PLAYER) == 2 and battle.round_wins(SIDE_AI) == 1
	ok = ok and battle.phase() == VersusBattle.Phase.MATCH_OVER
	ok = ok and battle.match_winner() == SIDE_PLAYER
	ok = ok and battle.round_index() == 3
	_case(ctx, "best_of_3_r1_player_r2_ai_r3_player_match_over_2_1", ok)


# ---------------------------------------------------------------------------
# 3) Same-tick double top-out: one draw, no wins, the same round is replayed.
static func _case_same_tick_double_top_out_draw(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.BEST_OF_3)
	_top_out(battle, SIDE_PLAYER)
	_top_out(battle, SIDE_AI)
	var ok: bool = battle.phase() == VersusBattle.Phase.PLAYING
	battle.tick(0.0)
	ok = ok and battle.last_round_draw()
	ok = ok and battle.phase() == VersusBattle.Phase.ROUND_OVER
	ok = ok and battle.round_winner() == -1 and battle.match_winner() == -1
	ok = ok and battle.round_wins(SIDE_PLAYER) == 0 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.round_index() == 1
	battle.start_round()
	ok = ok and battle.round_index() == 1
	ok = ok and battle.round_wins(SIDE_PLAYER) == 0 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING and not battle.last_round_draw()
	ok = ok and battle.current_piece(SIDE_PLAYER) != null and battle.current_piece(SIDE_AI) != null
	_case(ctx, "same_tick_double_top_out_is_draw_and_replays_round_index_1", ok)


# ---------------------------------------------------------------------------
# 4) restart_round(): round state resets, round wins and the index survive.
static func _case_restart_round_clears_round_state(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.BEST_OF_3, [1, 0], 2)
	# Dirty the round through the real chain: the AI's Double sends 1 to the
	# player, then the player's Tetris (attack 4) cancels that 1 from its own
	# queue first (no garbage is inserted on the player board) and queues the
	# 3-row remainder on the AI.
	_attack_double_fresh(battle, SIDE_AI)
	_attack_tetris(battle, SIDE_PLAYER)
	var ok: bool = battle.score(SIDE_PLAYER) > 0 and battle.score(SIDE_AI) > 0
	ok = ok and battle.lines(SIDE_PLAYER) > 0 and battle.lines(SIDE_AI) > 0
	ok = ok and _garbage_cells(battle.board(SIDE_PLAYER)) == 0
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and not battle.board(SIDE_AI).is_empty_board()
	ok = ok and battle.pending_garbage(SIDE_AI) == 3
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	battle.restart_round()
	ok = ok and battle.board(SIDE_PLAYER).is_empty_board() and battle.board(SIDE_AI).is_empty_board()
	ok = ok and battle.score(SIDE_PLAYER) == 0 and battle.score(SIDE_AI) == 0
	ok = ok and battle.lines(SIDE_PLAYER) == 0 and battle.lines(SIDE_AI) == 0
	ok = ok and battle.pending_garbage(SIDE_PLAYER) == 0 and battle.pending_garbage(SIDE_AI) == 0
	ok = ok and battle.round_wins(SIDE_PLAYER) == 1 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.round_index() == 2
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	ok = ok and battle.current_piece(SIDE_PLAYER) != null and battle.current_piece(SIDE_AI) != null
	ok = ok and battle.next_queue(SIDE_PLAYER).size() == VersusBattle.NEXT_COUNT and battle.next_queue(SIDE_AI).size() == VersusBattle.NEXT_COUNT
	_case(ctx, "restart_round_clears_boards_scores_lines_pending_keeps_wins_index", ok)


# ---------------------------------------------------------------------------
# 5) Pause freezes ticks and input; resuming advances the exact same frame.
static func _case_pause_freezes_and_resume_advances(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE)
	var frozen_snapshot: String = str(_snapshot(battle))
	var frozen_pos: Array = [battle.piece_pos(SIDE_PLAYER), battle.piece_pos(SIDE_AI)]
	var frozen_score: Array = [battle.score(SIDE_PLAYER), battle.score(SIDE_AI)]
	var frozen_cells: Array = [_board_cells(battle.board(SIDE_PLAYER)), _board_cells(battle.board(SIDE_AI))]
	var frozen_phase: int = battle.phase()
	battle.set_paused(true)
	battle.press(SIDE_PLAYER, VersusBattle.ACTION_MOVE_LEFT)
	battle.tap(SIDE_PLAYER, VersusBattle.ACTION_HARD_DROP)
	battle.press(SIDE_AI, VersusBattle.ACTION_SOFT_DROP)
	battle.tap(SIDE_AI, VersusBattle.ACTION_ROTATE)
	battle.tick(1.0)
	var ok: bool = battle.is_paused()
	ok = ok and str(_snapshot(battle)) == frozen_snapshot
	ok = ok and battle.piece_pos(SIDE_PLAYER) == frozen_pos[0] and battle.piece_pos(SIDE_AI) == frozen_pos[1]
	ok = ok and battle.score(SIDE_PLAYER) == frozen_score[0] and battle.score(SIDE_AI) == frozen_score[1]
	ok = ok and _board_cells(battle.board(SIDE_PLAYER)) == frozen_cells[0]
	ok = ok and _board_cells(battle.board(SIDE_AI)) == frozen_cells[1]
	ok = ok and battle.phase() == frozen_phase
	battle.set_paused(false)
	battle.tick(0.6)
	ok = ok and str(_snapshot(battle)) != frozen_snapshot
	# The queued hard drop consumed: the player scored and the piece changed.
	ok = ok and battle.score(SIDE_PLAYER) > int(frozen_score[0])
	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	_case(ctx, "pause_freezes_ticks_and_input_resume_advances", ok)


# ---------------------------------------------------------------------------
# 6) Rising speed vs fixed speed across a restart. Revised 2026-10-10: the
#    per-side "classic" versus rules (each side levelled by its own score, so
#    the two boards ran at different speeds) became RISING - one shared level
#    that grows with the round clock. Revised again 2026-10-10 (owner
#    decision): it grows with the lines both sides clear, not with the clock.
static func _case_classic_level_threshold_and_restart(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle(VersusBattle.Rules.RISING, 1, VersusBattle.MatchFormat.SINGLE)
	var ok: bool = battle.level(SIDE_PLAYER) == 1 and battle.level(SIDE_AI) == 1
	# Neither score nor the clock moves the level...
	_attack_tetris(battle, SIDE_PLAYER)
	ok = ok and battle.score(SIDE_PLAYER) >= 500 and battle.lines(SIDE_PLAYER) == 4
	battle.debug_freeze_side(SIDE_PLAYER, true)
	battle.debug_freeze_side(SIDE_AI, true)
	battle.tick(45.0)
	ok = ok and battle.level(SIDE_PLAYER) == 1 and battle.level(SIDE_AI) == 1
	# ...the lines of both sides together do, for both sides at once.
	battle.board(SIDE_AI).reset()
	_attack_tetris(battle, SIDE_AI)
	ok = ok and battle.lines(SIDE_PLAYER) + battle.lines(SIDE_AI) == VersusBattle.RISING_LINES_PER_LEVEL
	ok = ok and battle.level(SIDE_PLAYER) == 2 and battle.level(SIDE_AI) == 2
	ok = ok and VersusBattle.rising_level_for_lines(7) == 1 and VersusBattle.rising_level_for_lines(72) == 10 \
		and VersusBattle.rising_level_for_lines(999) == VersusBattle.RISING_MAX_LEVEL
	battle.restart_round()
	ok = ok and battle.level(SIDE_PLAYER) == 1 and battle.level(SIDE_AI) == 1
	ok = ok and battle.score(SIDE_PLAYER) == 0 and battle.elapsed() == 0.0
	# Fixed speed keeps the selected level through score and restart.
	var fixed: VersusBattle = _new_battle(VersusBattle.Rules.FIXED, 3, VersusBattle.MatchFormat.SINGLE)
	ok = ok and fixed.level(SIDE_PLAYER) == 3 and fixed.level(SIDE_AI) == 3
	_attack_tetris(fixed, SIDE_PLAYER)
	ok = ok and fixed.score(SIDE_PLAYER) >= 500
	ok = ok and fixed.level(SIDE_PLAYER) == 3 and fixed.level(SIDE_AI) == 3
	fixed.restart_round()
	ok = ok and fixed.level(SIDE_PLAYER) == 3 and fixed.level(SIDE_AI) == 3
	_case(ctx, "rising_level_follows_lines_restart_level_1_fixed_keeps_3", ok)


# ---------------------------------------------------------------------------
# Fixtures (same technique as test_versus_battle.gd).
static func _top_out(battle: VersusBattle, side: int) -> void:
	# An O locked entirely inside the hidden area is the all-hidden top-out.
	_force_lock(battle, side, PIECE_O, 0, Vector2i(0, 2))


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


## Locks an O piece that clears nothing (`x`,`y` must be free and visible).
static func _lock_noclear(battle: VersusBattle, side: int, x: int, y: int) -> void:
	_force_lock(battle, side, PIECE_O, 0, Vector2i(x, y))


static func _garbage_cells(board: Board) -> int:
	var total: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) == Board.GARBAGE:
				total += 1
	return total


static func _snapshot(battle: VersusBattle) -> Dictionary:
	return {
		"phase": battle.phase(),
		"match_winner": battle.match_winner(),
		"round_winner": battle.round_winner(),
		"draw": battle.last_round_draw(),
		"round_wins": [battle.round_wins(SIDE_PLAYER), battle.round_wins(SIDE_AI)],
		"round_index": battle.round_index(),
		"score": [battle.score(SIDE_PLAYER), battle.score(SIDE_AI)],
		"lines": [battle.lines(SIDE_PLAYER), battle.lines(SIDE_AI)],
		"level": [battle.level(SIDE_PLAYER), battle.level(SIDE_AI)],
		"pending": [battle.pending_garbage(SIDE_PLAYER), battle.pending_garbage(SIDE_AI)],
		"pieces": [_piece_id(battle, SIDE_PLAYER), _piece_id(battle, SIDE_AI)],
		"pos": [battle.piece_pos(SIDE_PLAYER), battle.piece_pos(SIDE_AI)],
		"cells": [_board_cells(battle.board(SIDE_PLAYER)), _board_cells(battle.board(SIDE_AI))],
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
