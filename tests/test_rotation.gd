extends SceneTree

const MODULE_NAME: String = "rotation"


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d rotation cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("ROTATION TESTS PASSED")
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_kick_writeback_i_left_wall(ctx)
	await _case_rotate_ccw_input(ctx)
	await _case_hard_drop_locks_once(ctx)
	await _case_blocked_spawn_game_over(ctx)
	await _case_fully_hidden_lock_game_over(ctx)
	await _case_partly_hidden_lock_continues(ctx)
	await _case_jlstz_t_left_wall_cw(ctx)
	await _case_jlstz_t_floor_kick_cw(ctx)
	await _case_jlstz_t_hidden_up_kick(ctx)
	await _case_i_floor_kick_cw(ctx)
	await _case_i_left_wall_ccw_kick(ctx)
	await _case_jlstz_t_floor_kick_ccw(ctx)
	await _case_o_cw_zero_displacement(ctx)
	await _case_o_ccw_zero_displacement(ctx)
	await _case_t_partially_hidden_rotation(ctx)
	await _case_srs_kick_table_grid_offsets(ctx)
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


static func _count_locked(board: Board) -> int:
	var count: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) != Board.EMPTY:
				count += 1
	return count


static func _case_kick_writeback_i_left_wall(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.I)
	main._piece.rotation = 1
	main._piece_pos = Vector2i(-2, 10)
	await _press_and_process(main, "rotate")
	var ok: bool = main._piece.rotation == 2 \
		and main._piece_pos == Vector2i(0, 10) \
		and main._board.can_place(main._piece.get_cells(), main._piece_pos) \
		and main._last_move_was_rotation \
		and main._last_kick_index == 2
	main.free()
	_case(ctx, "kick_writeback_i_left_wall", ok)


static func _case_rotate_ccw_input(ctx: Dictionary) -> void:
	var ok: bool = InputMap.has_action("rotate_ccw")
	if ok:
		var main = _spawn_main()
		main._piece = Tetromino.new(Tetromino.PieceType.T)
		main._piece_pos = Vector2i(3, 10)
		await _press_and_process(main, "rotate_ccw")
		ok = main._piece.rotation == 3 \
			and main._board.can_place(main._piece.get_cells(), main._piece_pos)
		main.free()
	_case(ctx, "rotate_ccw_input_rotates_counterclockwise", ok)


static func _case_hard_drop_locks_once(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 5)
	var before: int = _count_locked(main._board)
	await _press_and_process(main, "hard_drop")
	var ok: bool = _count_locked(main._board) == before + 4 \
		and main._piece != null \
		and not main._game_over \
		and not main._last_move_was_rotation
	main.free()
	_case(ctx, "hard_drop_locks_once_and_respawns", ok)


static func _case_blocked_spawn_game_over(ctx: Dictionary) -> void:
	var main = _spawn_main()
	for x: int in range(3, 7):
		main._board.set_cell(Vector2i(x, 2), Tetromino.PieceType.T)
		main._board.set_cell(Vector2i(x, 3), Tetromino.PieceType.T)
	main._spawn_piece()
	var ok: bool = main._game_over
	main.free()
	_case(ctx, "blocked_spawn_sets_game_over", ok)


static func _case_fully_hidden_lock_game_over(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 2)
	main._lock_piece(true)
	var ok: bool = main._game_over and _count_locked(main._board) == 4
	main.free()
	_case(ctx, "fully_hidden_lock_sets_game_over", ok)


static func _case_partly_hidden_lock_continues(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(0, 3)
	main._lock_piece(true)
	var ok: bool = not main._game_over and main._piece != null
	main.free()
	_case(ctx, "partly_hidden_lock_continues_play", ok)


static func _case_jlstz_t_left_wall_cw(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	piece.rotation = 1
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(-1, 10), 1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(0, 10) \
		and result["kick_index"] == 1 \
		and result["rotation"] == 2
	_case(ctx, "jlstz_t_left_wall_cw_kick", ok)


static func _case_jlstz_t_floor_kick_cw(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(3, 22), 1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(2, 21) \
		and result["kick_index"] == 2 \
		and result["rotation"] == 1
	_case(ctx, "jlstz_t_floor_kick_cw", ok)


static func _case_jlstz_t_hidden_up_kick(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	board.set_cell(Vector2i(4, 4), Tetromino.PieceType.J)
	board.set_cell(Vector2i(3, 4), Tetromino.PieceType.J)
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(3, 2), 1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(2, 1) \
		and result["kick_index"] == 2 \
		and result["rotation"] == 1
	if ok:
		var probe: Tetromino = Tetromino.new(Tetromino.PieceType.T)
		probe.rotation = int(result["rotation"])
		ok = board.can_place(probe.get_cells(), result["pos"])
	_case(ctx, "jlstz_t_hidden_up_kick", ok)


static func _case_i_floor_kick_cw(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.I)
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(3, 22), 1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(4, 20) \
		and result["kick_index"] == 4 \
		and result["rotation"] == 1
	_case(ctx, "i_floor_kick_cw", ok)


static func _case_i_left_wall_ccw_kick(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.I)
	piece.rotation = 1
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(-2, 10), -1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(0, 10) \
		and result["kick_index"] == 1 \
		and result["rotation"] == 0
	_case(ctx, "i_left_wall_ccw_kick", ok)


static func _case_jlstz_t_floor_kick_ccw(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(3, 22), -1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(4, 21) \
		and result["kick_index"] == 2 \
		and result["rotation"] == 3
	_case(ctx, "jlstz_t_floor_kick_ccw", ok)


static func _case_o_cw_zero_displacement(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.O)
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(4, 10), 1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(4, 10) \
		and result["kick_index"] == 0 \
		and result["rotation"] == 1
	_case(ctx, "o_cw_zero_displacement", ok)


static func _case_o_ccw_zero_displacement(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.O)
	piece.rotation = 2
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(4, 10), -1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(4, 10) \
		and result["kick_index"] == 0 \
		and result["rotation"] == 1
	_case(ctx, "o_ccw_zero_displacement", ok)


static func _case_t_partially_hidden_rotation(ctx: Dictionary) -> void:
	var board: Board = Board.new()
	board.set_cell(Vector2i(4, 5), Tetromino.PieceType.J)
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.T)
	var result: Dictionary = SRS.try_rotate(board, piece, Vector2i(3, 3), 1)
	var ok: bool = result["success"] \
		and result["pos"] == Vector2i(2, 3) \
		and result["kick_index"] == 1 \
		and result["rotation"] == 1
	if ok:
		var probe: Tetromino = Tetromino.new(Tetromino.PieceType.T)
		probe.rotation = int(result["rotation"])
		var spans_hidden_and_visible: bool = false
		var min_y: int = 99
		var max_y: int = -99
		for local: Vector2i in probe.get_cells():
			var world_y: int = local.y + (result["pos"] as Vector2i).y
			min_y = mini(min_y, world_y)
			max_y = maxi(max_y, world_y)
		spans_hidden_and_visible = min_y < Board.HIDDEN_HEIGHT and max_y >= Board.HIDDEN_HEIGHT
		ok = spans_hidden_and_visible and board.can_place(probe.get_cells(), result["pos"])
	_case(ctx, "t_partially_hidden_rotation_placeable", ok)


static func _case_srs_kick_table_grid_offsets(ctx: Dictionary) -> void:
	var jlstz_cw: Array[Vector2i] = SRS.get_grid_kicks(Tetromino.PieceType.T, 0, 1)
	var jlstz_ccw: Array[Vector2i] = SRS.get_grid_kicks(Tetromino.PieceType.T, 0, -1)
	var i_cw: Array[Vector2i] = SRS.get_grid_kicks(Tetromino.PieceType.I, 0, 1)
	var expected_jlstz_cw: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)]
	var expected_jlstz_ccw: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)]
	var expected_i_cw: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2)]
	var ok: bool = jlstz_cw == expected_jlstz_cw \
		and jlstz_ccw == expected_jlstz_ccw \
		and i_cw == expected_i_cw
	_case(ctx, "srs_kick_table_grid_offsets", ok)
