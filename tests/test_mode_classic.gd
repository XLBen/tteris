extends SceneTree

const MODULE_NAME: String = "mode_classic"

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
# Revised 2026-10-10 (owner decision): the classic level follows the cleared
# lines (one level per 10, capped at 15) instead of score thresholds capped at
# 10. The single source of truth is Scoring.LINES_PER_LEVEL /
# Scoring.CLASSIC_MAX_LEVEL / Scoring.PERFECT_CLEAR_POINTS.
const FROZEN_LINES_PER_LEVEL: int = 10
const FROZEN_PC_POINTS: Array[int] = [0, 800, 1200, 1800, 2000]
const FROZEN_MAX_LEVEL: int = 15
const EXPECTED_CASES: int = 8


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0 or int(result["total"]) != EXPECTED_CASES:
		print("FAILED: %d of %d classic mode cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("CLASSIC MODE TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_scoring_single_constant_source(ctx)
	await _case_level_for_score_boundaries(ctx)
	await _case_perfect_clear_points_by_tier(ctx)
	await _case_classic_starts_at_level_1(ctx)
	await _case_score_threshold_crossing_levels_up(ctx)
	await _case_no_time_upgrade(ctx)
	await _case_perfect_clear_scoring_and_stacking(ctx)
	await _case_no_session_legacy_is_classic(ctx)
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


static func _game_session():
	return _tree().root.get_node_or_null(^"GameSession")


static func _set_mode_none() -> void:
	var session = _game_session()
	if session != null:
		session.start_mode(session.MODE_NONE)


static func _spawn_classic_main():
	var tree: SceneTree = _tree()
	var session = _game_session()
	if session != null:
		session.start_classic()
	var main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(main)
	main.set_process(false)
	await tree.process_frame
	main._paused = false
	return main


static func _fill_row_except(board: Board, row: int, except: Array) -> void:
	for x: int in Board.BOARD_WIDTH:
		if not except.has(x):
			board.set_cell(Vector2i(x, row), Tetromino.PieceType.J)


static func _lock_at(main, piece: Tetromino, pos: Vector2i) -> void:
	main._piece = piece
	main._piece_pos = pos
	main._last_move_was_rotation = false
	main._last_kick_index = -1
	main._lock_piece(true)


static func _lock_i_vertical(main) -> void:
	# Vertical I at (4, 20) fills column 6 of rows 20-23.
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.I)
	piece.rotation = 1
	_lock_at(main, piece, Vector2i(4, 20))


static func _lock_i_horizontal_row23(main) -> void:
	# Horizontal I at (4, 22) fills columns 4-7 of row 23.
	_lock_at(main, Tetromino.new(Tetromino.PieceType.I), Vector2i(4, 22))


static func _lock_tetris_pc(main) -> void:
	for row: int in range(20, 24):
		_fill_row_except(main._board, row, [6])
	_lock_i_vertical(main)


static func _case_scoring_single_constant_source(ctx: Dictionary) -> void:
	var ok: bool = int(Scoring.LINES_PER_LEVEL) == FROZEN_LINES_PER_LEVEL \
		and int(Scoring.CLASSIC_MAX_LEVEL) == FROZEN_MAX_LEVEL \
		and Scoring.PERFECT_CLEAR_POINTS == FROZEN_PC_POINTS
	ok = ok and Scoring.level_for_lines(0) == 1 and Scoring.level_for_lines(10) == 2 \
		and Scoring.level_for_lines(140) == FROZEN_MAX_LEVEL
	ok = ok and Scoring.perfect_clear_points(4, 1) == 2000 \
		and Scoring.perfect_clear_points(1, 3) == 2400
	var session = _game_session()
	ok = ok and session != null
	if session != null:
		# The threshold table and PC values live only in Scoring: the session
		# and the game scene consume them instead of keeping private copies.
		var constants: Dictionary = session.get_script().get_script_constant_map()
		ok = ok and not constants.has("LINES_PER_LEVEL") \
			and not constants.has("CLASSIC_MAX_LEVEL") \
			and not constants.has("PERFECT_CLEAR_POINTS")
	_case(ctx, "classic_level_rule_single_source_in_scoring", ok)


static func _case_level_for_score_boundaries(ctx: Dictionary) -> void:
	var vectors: Array = [
		[0, 1], [9, 1], [10, 2], [19, 2], [20, 3], [89, 9], [90, 10], [139, 14],
		[140, FROZEN_MAX_LEVEL], [99999, FROZEN_MAX_LEVEL],
	]
	var ok: bool = true
	for vector: Array in vectors:
		ok = ok and Scoring.level_for_lines(int(vector[0])) == int(vector[1])
	# A higher starting level counts from there.
	ok = ok and Scoring.level_for_lines(9, 3) == 3 and Scoring.level_for_lines(10, 3) == 4 \
		and Scoring.level_for_lines(500, 3) == FROZEN_MAX_LEVEL
	# Gravity keeps getting faster up to the cap (the old floor froze it at 10).
	for level: int in range(2, FROZEN_MAX_LEVEL + 1):
		ok = ok and VersusBattle.gravity_interval(level) < VersusBattle.gravity_interval(level - 1)
	_case(ctx, "level_for_lines_exact_boundaries_and_level_15_cap", ok)


static func _case_perfect_clear_points_by_tier(ctx: Dictionary) -> void:
	var ok: bool = Scoring.perfect_clear_points(1, 1) == 800 \
		and Scoring.perfect_clear_points(2, 1) == 1200 \
		and Scoring.perfect_clear_points(3, 1) == 1800 \
		and Scoring.perfect_clear_points(4, 1) == 2000 \
		and Scoring.perfect_clear_points(1, 10) == 8000 \
		and Scoring.perfect_clear_points(4, 7) == 14000 \
		and Scoring.perfect_clear_points(0, 3) == 0
	_case(ctx, "perfect_clear_points_800_1200_1800_2000_times_level", ok)


static func _case_classic_starts_at_level_1(ctx: Dictionary) -> void:
	var session = _game_session()
	var ok: bool = session != null
	if session != null:
		# Versus classic shares the classic level rules: it starts at level 1
		# (versus fixed uses its own fixed level, covered by the menu module).
		session.start_versus(session.VERSUS_RULES_RISING, 9, session.VERSUS_FORMAT_SINGLE)
		ok = ok and session.is_versus() == true and int(session.initial_level()) == 1
	var main = await _spawn_classic_main()
	ok = ok and main != null and int(main._level) == 1 and not main._game_over
	if session != null:
		ok = ok and session.is_classic() == true
	if main != null:
		main.free()
	await _tree().create_timer(0.1).timeout
	_set_mode_none()
	_case(ctx, "classic_mode_starts_at_level_1", ok)


static func _case_score_threshold_crossing_levels_up(ctx: Dictionary) -> void:
	var main = await _spawn_classic_main()
	var ok: bool = main != null
	# A: the tenth line (a single worth 100 at level 1) raises the level.
	main._board.reset()
	main._combo_index = 0
	main._score = 400
	main._lines = 9
	_fill_row_except(main._board, 23, [6])
	_lock_i_vertical(main)
	ok = ok and int(main._score) == 500 and int(main._level) == 2
	# B: the twentieth line (a single worth 200 at level 2) raises it again.
	main._board.reset()
	main._combo_index = 0
	main._score = 1300
	main._lines = 19
	_fill_row_except(main._board, 23, [6])
	_lock_i_vertical(main)
	ok = ok and int(main._score) == 1500 and int(main._level) == 3
	# C: line 21 (a single worth 300 at level 3) is not a tenth line: the
	# level does not move, whatever the score.
	main._board.reset()
	main._combo_index = 0
	main._score = 2000
	_fill_row_except(main._board, 23, [6])
	_lock_i_vertical(main)
	ok = ok and int(main._score) == 2300 and int(main._level) == 3
	main.free()
	await _tree().create_timer(0.1).timeout
	_set_mode_none()
	_case(ctx, "every_tenth_line_levels_up", ok)


static func _case_no_time_upgrade(ctx: Dictionary) -> void:
	var main = await _spawn_classic_main()
	var ok: bool = main != null
	main._piece = null
	for i: int in 120:
		main._process(1.0)
	ok = ok and int(main._level) == 1 and int(main._score) == 0 and int(main._lines) == 0
	if main != null:
		main.free()
	await _tree().create_timer(0.1).timeout
	var session = _game_session()
	if session != null:
		var constants: Dictionary = session.get_script().get_script_constant_map()
		ok = ok and not session.has_method("is_growth") and not session.has_method("is_difficulty")
		ok = ok and not constants.has("GROWTH_PERIOD") and not constants.has("GROWTH_CAP") \
			and not constants.has("GROWTH_START_LEVEL")
	_set_mode_none()
	_case(ctx, "no_time_based_level_up_after_120_seconds", ok)


static func _case_perfect_clear_scoring_and_stacking(ctx: Dictionary) -> void:
	var main = await _spawn_classic_main()
	var ok: bool = main != null
	# (1) Single-line Perfect Clear at level 1: clear 100 + PC 800 = 900.
	_fill_row_except(main._board, 23, [4, 5, 6, 7])
	_lock_i_horizontal_row23(main)
	ok = ok and int(main._score) == 900 and int(main._level) == 1
	ok = ok and main._last_feedback.contains("PERFECT CLEAR") \
		and int(main._combo_index) == 1 and not main._b2b_active
	# (2) Second single PC with combo 1 active: clear 100 + combo 50 + PC 800.
	_fill_row_except(main._board, 23, [4, 5, 6, 7])
	_lock_i_horizontal_row23(main)
	ok = ok and int(main._score) == 1850 and int(main._level) == 1 \
		and int(main._combo_index) == 2
	# (3) Tetris PC with combo 2: clear 800 + combo 100 + PC 2000.
	var before: int = main._score
	_lock_tetris_pc(main)
	ok = ok and int(main._score) - before == 2900 and int(main._level) == 1 \
		and main._b2b_active == true and int(main._combo_index) == 3
	ok = ok and main._last_feedback.contains("PERFECT CLEAR") \
		and main._last_feedback.contains("TETRIS")
	# (4) B2B Tetris PC with combo 3: clear 800*1.5 = 1200 + combo 150 +
	# PC 2000 = 3350; it is the tenth line, so the level rises after it.
	before = main._score
	_lock_tetris_pc(main)
	ok = ok and int(main._score) - before == 3350 \
		and int(main._score) == 8100 and int(main._lines) == 10 and int(main._level) == 2 \
		and main._b2b_active == true and int(main._combo_index) == 4
	# (5) At level 2 every part is doubled: clear 800*1.5*2 = 2400 + combo
	# 50*4*2 = 400 + PC 2000*2 = 4000.
	before = main._score
	_lock_tetris_pc(main)
	ok = ok and int(main._score) - before == 6800 and int(main._level) == 2
	main.free()
	await _tree().create_timer(0.1).timeout
	_set_mode_none()
	_case(ctx, "perfect_clear_stacking_with_clear_b2b_combo", ok)


static func _case_no_session_legacy_is_classic(ctx: Dictionary) -> void:
	# No GameSession at all (scene instantiated without a tree): the legacy
	# behavior is the classic one, starting at level 1 and leveling by lines.
	var main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	main._ready()
	var ok: bool = int(main._level) == 1
	main._score = 400
	main._lines = 9
	_fill_row_except(main._board, 23, [6])
	_lock_i_vertical(main)
	ok = ok and int(main._score) == 500 and int(main._level) == 2
	main.free()
	await _tree().create_timer(0.1).timeout
	_case(ctx, "no_session_legacy_starts_at_1_and_levels_by_lines", ok)
