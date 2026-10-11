extends SceneTree

const MODULE_NAME: String = "scoring"


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d scoring cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("SCORING TESTS PASSED")
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_is_difficult_unit(ctx)
	_case_classify_units(ctx)
	for lines: int in [1, 2, 3, 4]:
		await _case_normal_clear(ctx, lines)
	await _case_t_spin_slot(ctx, "t_spin_mini_no_line_100", {}, [Vector2i(2, 20), Vector2i(2, 22), Vector2i(4, 20)], Vector2i(2, 20), 100)
	await _case_t_spin_slot(ctx, "t_spin_mini_single_200", {21: [3, 4]}, [Vector2i(2, 20), Vector2i(2, 22), Vector2i(4, 20)], Vector2i(2, 20), 200)
	await _case_t_spin_slot(ctx, "t_spin_mini_double_400", {21: [3, 4], 22: [3]}, [Vector2i(2, 20)], Vector2i(2, 20), 400)
	await _case_t_spin_slot(ctx, "t_spin_full_no_line_400", {}, [Vector2i(4, 20), Vector2i(4, 22), Vector2i(2, 20), Vector2i(2, 22)], Vector2i(2, 20), 400)
	await _case_t_spin_slot(ctx, "t_spin_full_single_800", {21: [3, 4]}, [Vector2i(4, 20), Vector2i(4, 22), Vector2i(2, 20), Vector2i(2, 22)], Vector2i(2, 20), 800)
	await _case_t_spin_slot(ctx, "t_spin_full_double_1200", {19: [2, 3], 20: [2]}, [Vector2i(1, 18), Vector2i(3, 18)], Vector2i(1, 18), 1200)
	await _case_t_spin_slot(ctx, "t_spin_full_triple_1600", {18: [2], 19: [2, 3], 20: [2]}, [Vector2i(5, 23)], Vector2i(1, 18), 1600)
	await _case_b2b_tetris_then_tetris(ctx)
	await _case_b2b_tetris_then_tspin_single(ctx)
	await _case_b2b_tetris_then_single_breaks(ctx)
	await _case_b2b_tspin_noline_keeps_chain(ctx)
	await _case_combo_reset_by_noclear_lock(ctx)
	await _case_combo_chain_bonuses(ctx)
	await _case_kick4_upgrades_mini(ctx)
	await _case_pre_level_up_level(ctx)
	await _case_score_display_no_truncation(ctx)
	await _case_feedback_text(ctx)
	await _case_restart_resets_scoring(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _spawn_main():
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	main._ready()
	return main


static func _press_and_process(main, action: String) -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	Input.action_press(action)
	main._process(0.016)
	Input.action_release(action)


static func _fill_row_except(board: Board, row: int, except: Array) -> void:
	for x: int in Board.BOARD_WIDTH:
		if not except.has(x):
			board.set_cell(Vector2i(x, row), Tetromino.PieceType.J)


static func _lock_at(main, piece: Tetromino, pos: Vector2i, was_rotation: bool, kick: int) -> void:
	main._piece = piece
	main._piece_pos = pos
	main._last_move_was_rotation = was_rotation
	main._last_kick_index = kick
	main._lock_piece(true)


static func _lock_i_vertical(main) -> void:
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.I)
	piece.rotation = 1
	_lock_at(main, piece, Vector2i(4, 20), false, -1)


static func _lock_tetris(main) -> void:
	for row: int in range(20, 24):
		_fill_row_except(main._board, row, [6])
	# Residual cell above the cleared rows (row 19), clear of the O lock at
	# (0, 18) and of every T-spin corner fixture, so a tetris that empties
	# rows 20-23 is not a whole-board Perfect Clear. PC scoring is covered by
	# test_mode_classic.gd; this helper pins the plain line/B2B scores.
	main._board.set_cell(Vector2i(9, 19), Tetromino.PieceType.J)
	_lock_i_vertical(main)


static func _case_is_difficult_unit(ctx: Dictionary) -> void:
	var ok: bool = not Scoring.is_difficult(1, Scoring.TSpinKind.NONE) \
		and Scoring.is_difficult(4, Scoring.TSpinKind.NONE) \
		and Scoring.is_difficult(1, Scoring.TSpinKind.FULL) \
		and Scoring.is_difficult(2, Scoring.TSpinKind.MINI) \
		and not Scoring.is_difficult(0, Scoring.TSpinKind.FULL)
	_case(ctx, "is_difficult_unit", ok)


static func _case_classify_units(ctx: Dictionary) -> void:
	# Guideline 3-corner rule (revised 2026-10-10, was inverted): the T points
	# right (rotation 1), so its front corners are x=4 and its back corners
	# x=2. Both back + one front is a Mini; both front is a full T-Spin.
	var board: Board = Board.new()
	board.set_cell(Vector2i(2, 20), Tetromino.PieceType.J)
	board.set_cell(Vector2i(2, 22), Tetromino.PieceType.J)
	board.set_cell(Vector2i(4, 20), Tetromino.PieceType.J)
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	piece.rotation = 1
	var mini_kick0: int = Scoring.classify_t_spin(board, piece, Vector2i(2, 20), true, 0)
	var mini_kick4: int = Scoring.classify_t_spin(board, piece, Vector2i(2, 20), true, 4)
	var not_rotation: int = Scoring.classify_t_spin(board, piece, Vector2i(2, 20), false, 0)
	var j_piece: Tetromino = Tetromino.new(Tetromino.PieceType.J)
	var non_t: int = Scoring.classify_t_spin(board, j_piece, Vector2i(2, 20), true, 0)
	board.set_cell(Vector2i(4, 22), Tetromino.PieceType.J)
	var full_back2: int = Scoring.classify_t_spin(board, piece, Vector2i(2, 20), true, 0)
	board.reset()
	board.set_cell(Vector2i(4, 20), Tetromino.PieceType.J)
	board.set_cell(Vector2i(4, 22), Tetromino.PieceType.J)
	var two_corners: int = Scoring.classify_t_spin(board, piece, Vector2i(2, 20), true, 0)
	var ok: bool = mini_kick0 == Scoring.TSpinKind.MINI \
		and mini_kick4 == Scoring.TSpinKind.FULL \
		and not_rotation == Scoring.TSpinKind.NONE \
		and non_t == Scoring.TSpinKind.NONE \
		and full_back2 == Scoring.TSpinKind.FULL \
		and two_corners == Scoring.TSpinKind.NONE
	_case(ctx, "classify_t_spin_units", ok)


static func _case_normal_clear(ctx: Dictionary, lines: int) -> void:
	var main = _spawn_main()
	for row: int in range(24 - lines, 24):
		_fill_row_except(main._board, row, [6])
	if lines == 4:
		# The 4-line fixture would otherwise leave the board empty: keep one
		# residual cell so this case pins the plain 800 tetris score and not
		# the Perfect Clear bonus (covered by test_mode_classic.gd).
		main._board.set_cell(Vector2i(9, 19), Tetromino.PieceType.J)
	_lock_i_vertical(main)
	var expected: int = [0, 100, 300, 500, 800][lines]
	_case(ctx, "normal_clear_%d_lines_scores_%d" % [lines, expected], main._score == expected)
	main.free()


static func _case_t_spin_slot(ctx: Dictionary, case_name: String, rows: Dictionary, blocked: Array, pos: Vector2i, expected: int) -> void:
	var main = _spawn_main()
	for row: int in rows:
		_fill_row_except(main._board, row, rows[row])
	for corner: Vector2i in blocked:
		main._board.set_cell(corner, Tetromino.PieceType.J)
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	piece.rotation = 1
	_lock_at(main, piece, pos, true, 0)
	_case(ctx, case_name, main._score == expected)
	main.free()


static func _lock_full_tspin_single(main) -> void:
	for corner: Vector2i in [Vector2i(4, 20), Vector2i(4, 22), Vector2i(2, 20), Vector2i(2, 22)]:
		main._board.set_cell(corner, Tetromino.PieceType.J)
	_fill_row_except(main._board, 21, [3, 4])
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	piece.rotation = 1
	_lock_at(main, piece, Vector2i(2, 20), true, 0)


static func _lock_full_tspin_noline(main) -> void:
	for corner: Vector2i in [Vector2i(4, 20), Vector2i(4, 22), Vector2i(2, 20), Vector2i(2, 22)]:
		main._board.set_cell(corner, Tetromino.PieceType.J)
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	piece.rotation = 1
	_lock_at(main, piece, Vector2i(2, 20), true, 0)


static func _lock_o_noclear(main) -> void:
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.O)
	_lock_at(main, piece, Vector2i(0, 18), false, -1)


static func _case_b2b_tetris_then_tetris(ctx: Dictionary) -> void:
	var main = _spawn_main()
	_lock_tetris(main)
	var first: int = main._score
	var ok: bool = first == 800
	_lock_o_noclear(main)
	_lock_tetris(main)
	# Revised 2026-10-10: the level follows the lines now, so both clears are
	# scored at level 1. O lock resets the combo. Second tetris: 800, B2B
	# x1.5 -> 1200.
	ok = ok and main._score - first == 1200
	main.free()
	_case(ctx, "b2b_tetris_then_tetris_scores_1200", ok)


static func _case_b2b_tetris_then_tspin_single(ctx: Dictionary) -> void:
	var main = _spawn_main()
	_lock_tetris(main)
	_lock_o_noclear(main)
	var before: int = main._score
	_lock_full_tspin_single(main)
	# Revised 2026-10-10 (level by lines: still level 1). O lock resets the
	# combo. Full T-Spin Single: 800, B2B x1.5 -> 1200.
	var ok: bool = main._score - before == 1200 and main._b2b_active
	main.free()
	_case(ctx, "b2b_continues_through_tspin_single_1200", ok)


static func _case_b2b_tetris_then_single_breaks(ctx: Dictionary) -> void:
	var main = _spawn_main()
	_lock_tetris(main)
	_lock_o_noclear(main)
	_fill_row_except(main._board, 23, [6])
	var before: int = main._score
	_lock_i_vertical(main)
	# Revised 2026-10-10 (level by lines: still level 1). Normal Single: 100;
	# not a difficult clear, so B2B breaks.
	var ok: bool = main._score - before == 100 and not main._b2b_active
	main.free()
	_case(ctx, "b2b_broken_by_normal_single_100", ok)


static func _case_b2b_tspin_noline_keeps_chain(ctx: Dictionary) -> void:
	var main = _spawn_main()
	_lock_tetris(main)
	var before: int = main._score
	_lock_full_tspin_noline(main)
	# Revised 2026-10-10 (level by lines: all at level 1). T-Spin no-line: 400
	# (no B2B multiplier, no combo bonus). Second tetris: 800, B2B x1.5 -> 1200.
	var ok: bool = main._score - before == 400 and main._b2b_active
	before = main._score
	_lock_tetris(main)
	ok = ok and main._score - before == 1200
	main.free()
	_case(ctx, "b2b_kept_through_tspin_no_line", ok)


static func _case_combo_reset_by_noclear_lock(ctx: Dictionary) -> void:
	var main = _spawn_main()
	_fill_row_except(main._board, 23, [6])
	_lock_i_vertical(main)
	var ok: bool = main._score == 100
	var o_piece: Tetromino = Tetromino.new(Tetromino.PieceType.O)
	_lock_at(main, o_piece, Vector2i(0, 18), false, -1)
	ok = ok and main._combo_index == 0
	_fill_row_except(main._board, 22, [7])
	var i2: Tetromino = Tetromino.new(Tetromino.PieceType.I)
	i2.rotation = 1
	var before: int = main._score
	_lock_at(main, i2, Vector2i(5, 20), false, -1)
	ok = ok and main._score - before == 100 and main._combo_index == 1
	main.free()
	_case(ctx, "combo_reset_by_no_clear_lock", ok)


static func _case_combo_chain_bonuses(ctx: Dictionary) -> void:
	var main = _spawn_main()
	var deltas: Array[int] = []
	var columns: Array[int] = [6, 7, 5]
	var rows: Array[int] = [23, 22, 23]
	for i: int in 3:
		_fill_row_except(main._board, rows[i], [columns[i]])
		var piece: Tetromino = Tetromino.new(Tetromino.PieceType.I)
		piece.rotation = 1
		var before: int = main._score
		_lock_at(main, piece, Vector2i(columns[i] - 2, 20), false, -1)
		deltas.append(main._score - before)
	var ok: bool = deltas == [100, 150, 200]
	main.free()
	_case(ctx, "combo_chain_bonuses_0_50_100", ok)


static func _case_kick4_upgrades_mini(ctx: Dictionary) -> void:
	var main = _spawn_main()
	for blocked_cell: Vector2i in [Vector2i(3, 10), Vector2i(4, 12), Vector2i(4, 14), Vector2i(2, 14)]:
		main._board.set_cell(blocked_cell, Tetromino.PieceType.J)
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 10)
	await _press_and_process(main, "rotate")
	var rotated_ok: bool = main._last_kick_index == 4 \
		and main._piece_pos == Vector2i(2, 12) \
		and main._piece.rotation == 1 \
		and main._last_move_was_rotation
	var before: int = main._score
	main._lock_piece(true)
	var ok: bool = rotated_ok \
		and main._score - before == 400 \
		and main._last_feedback.contains("T-SPIN") \
		and not main._last_feedback.contains("MINI")
	main.free()
	_case(ctx, "final_kick_upgrades_mini_to_full_400", ok)


static func _case_pre_level_up_level(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._lines = 9
	# Nine lines so far, so the double clear is still scored at level 1:
	# 300 x L1 = 300. Its lines cross ten and only then raise the level to 2,
	# proving the event used the pre-upgrade level.
	main._score = 400
	for row: int in [22, 23]:
		_fill_row_except(main._board, row, [6])
	var before: int = main._score
	_lock_i_vertical(main)
	var ok: bool = main._score - before == 300 and main._lines == 11 and main._level == 2
	main.free()
	_case(ctx, "pre_level_up_level_used_300", ok)


static func _case_score_display_no_truncation(ctx: Dictionary) -> void:
	# Revised 2026-10-10 (UI re-layout): the readouts are font labels now.
	var main = _spawn_main()
	main._score = 1234567
	main._lines = 1234
	main._refresh_view()
	var ok: bool = main._score_value.text == "1234567" and main._lines_value.text == "1234"
	ok = ok and not main._score_value.clip_text and not main._lines_value.clip_text
	main.free()
	_case(ctx, "score_display_shows_all_digits", ok)


static func _case_feedback_text(ctx: Dictionary) -> void:
	var main = _spawn_main()
	for corner: Vector2i in [Vector2i(1, 18), Vector2i(3, 18)]:
		main._board.set_cell(corner, Tetromino.PieceType.J)
	_fill_row_except(main._board, 19, [2, 3])
	_fill_row_except(main._board, 20, [2])
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	piece.rotation = 1
	_lock_at(main, piece, Vector2i(1, 18), true, 0)
	var ok: bool = main._last_feedback.contains("T-SPIN") and main._fx.popup_text().contains("T-SPIN")
	main.free()
	_case(ctx, "feedback_tspin_double_contains_tspin", ok)

	main = _spawn_main()
	_fill_row_except(main._board, 23, [6])
	_lock_i_vertical(main)
	ok = not main._last_feedback.contains("T-SPIN") and not main._last_feedback.contains("B2B")
	ok = ok and not main._last_feedback.contains("COMBO")
	_fill_row_except(main._board, 22, [6])
	_lock_i_vertical(main)
	ok = ok and main._last_feedback.contains("COMBO x2")
	main.free()
	_case(ctx, "feedback_plain_single_no_tspin_claim", ok)


static func _case_restart_resets_scoring(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._combo_index = 3
	main._b2b_active = true
	main._last_feedback = "B2B TETRIS"
	main._restart()
	var ok: bool = main._combo_index == 0 \
		and not main._b2b_active \
		and main._last_feedback.is_empty() \
		and main._pending_t_spin == Scoring.TSpinKind.NONE
	main.free()
	_case(ctx, "restart_resets_scoring_state", ok)
