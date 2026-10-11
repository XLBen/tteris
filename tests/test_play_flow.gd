extends SceneTree

const MODULE_NAME: String = "play_flow"


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d play_flow cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("PLAY FLOW TESTS PASSED")
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_das_arr_movement(ctx)
	await _case_soft_drop_points(ctx)
	await _case_hard_drop_points_single_lock(ctx)
	await _case_atomicity_gravity_lock_with_hard_drop(ctx)
	await _case_hold_swap_and_lockout(ctx)
	await _case_pause_freezes_and_resumes(ctx)
	await _case_restart_resets_everything(ctx)
	await _case_game_over_only_via_bd05(ctx)
	await _case_stress_session(ctx)
	await _case_rotate_after_hidden_spawn(ctx)
	await _case_hold_harddrop_blocked_spawn_guard(ctx)
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
	await (Engine.get_main_loop() as SceneTree).process_frame


static func _hold_and_step(main, action: String, frames: int) -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	Input.action_press(action)
	for i: int in frames:
		main._process(0.016)
	Input.action_release(action)
	await (Engine.get_main_loop() as SceneTree).process_frame


static func _step(main, frames: int) -> void:
	for i: int in frames:
		main._process(0.016)


static func _count_locked(board: Board) -> int:
	var count: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) != Board.EMPTY:
				count += 1
	return count


static func _piece_legal(main) -> bool:
	return main._piece == null or main._board.can_place(main._piece.get_cells(), main._piece_pos)


static func _case_das_arr_movement(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(5, 6)
	await _hold_and_step(main, "move_left", 8)
	var immediate_ok: bool = main._piece_pos.x == 4
	_step(main, 1)
	await _hold_and_step(main, "move_left", 60)
	var das_ok: bool = main._piece_pos.x == 0
	main.free()
	_case(ctx, "das_arr_movement", immediate_ok and das_ok)


static func _case_soft_drop_points(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.J)
	main._piece_pos = Vector2i(3, 6)
	var score_before: int = main._score
	await _hold_and_step(main, "soft_drop", 15)
	var dropped: int = main._piece_pos.y - 6
	var ok: bool = dropped >= 3 and main._score - score_before == dropped
	main.free()
	_case(ctx, "soft_drop_one_point_per_cell", ok)


static func _case_hard_drop_points_single_lock(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 5)
	var locked_before: int = _count_locked(main._board)
	await _press_and_process(main, "hard_drop")
	var dist: int = 22 - 5
	var ok: bool = main._score == dist * 2 \
		and _count_locked(main._board) == locked_before + 4 \
		and main._piece != null \
		and not main._game_over
	var spawn_pos: Vector2i = main._piece_pos
	_step(main, 5)
	ok = ok and main._piece_pos == spawn_pos and main._piece_pos.y == Board.HIDDEN_HEIGHT - 2
	main.free()
	_case(ctx, "hard_drop_two_points_per_cell_single_lock", ok)


static func _case_atomicity_gravity_lock_with_hard_drop(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 22)
	var locked_before: int = _count_locked(main._board)
	main._lock_timer = main.LOCK_DELAY - 0.008
	await (Engine.get_main_loop() as SceneTree).process_frame
	Input.action_press("hard_drop")
	main._process(0.016)
	Input.action_release("hard_drop")
	await (Engine.get_main_loop() as SceneTree).process_frame
	var ok: bool = _count_locked(main._board) == locked_before + 4 \
		and main._piece != null \
		and main._piece_pos.y == Board.HIDDEN_HEIGHT - 2 \
		and not main._game_over \
		and _piece_legal(main)
	main.free()
	_case(ctx, "gravity_lock_frame_with_hard_drop_press_locks_once", ok)


static func _case_hold_swap_and_lockout(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 10)
	main._next_queue[0] = Tetromino.PieceType.L
	await _press_and_process(main, "hold")
	var swapped: bool = main._hold_type == Tetromino.PieceType.T \
		and main._piece.piece_type != Tetromino.PieceType.T \
		and not main._can_hold
	var type_after_first: int = main._piece.piece_type
	var pos_after_first: Vector2i = main._piece_pos
	await _press_and_process(main, "hold")
	var locked_out: bool = main._piece.piece_type == type_after_first \
		and main._piece_pos == pos_after_first \
		and not main._can_hold
	await _press_and_process(main, "hard_drop")
	var ok: bool = swapped and locked_out and main._can_hold
	main.free()
	_case(ctx, "hold_swap_and_lockout", ok)


static func _case_pause_freezes_and_resumes(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 10)
	var score_before: int = main._score
	await _press_and_process(main, "pause")
	var paused: bool = main._paused and main._pause_menu.visible
	_step(main, 30)
	var frozen: bool = main._piece_pos == Vector2i(3, 10) and main._score == score_before
	await _press_and_process(main, "pause")
	var resumed: bool = not main._paused
	_step(main, 70)
	var gravity_back: bool = main._piece != null and main._piece_pos.y > 10
	main.free()
	_case(ctx, "pause_freezes_state_resumes", paused and frozen and resumed and gravity_back)


static func _case_restart_resets_everything(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 5)
	await _press_and_process(main, "hard_drop")
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(5, 5)
	await _press_and_process(main, "hard_drop")
	main._combo_index = 2
	main._b2b_active = true
	var played: bool = main._score > 0 and _count_locked(main._board) >= 8
	# Revised 2026-10-10: R no longer restarts a running game (an accidental
	# key press used to wipe the run); mid-game restarts go through the pause
	# menu, and R only answers on the game-over screen.
	await _press_and_process(main, "restart")
	played = played and main._score > 0 and _count_locked(main._board) >= 8
	main._trigger_game_over()
	await _press_and_process(main, "restart")
	var ok: bool = played \
		and main._score == 0 and main._lines == 0 and main._level == 1 \
		and main._combo_index == 0 and not main._b2b_active \
		and _count_locked(main._board) == 0 \
		and main._piece != null and not main._game_over
	main.free()
	_case(ctx, "restart_resets_everything", ok)


static func _case_game_over_only_via_bd05(ctx: Dictionary) -> void:
	var main = _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 5)
	await _press_and_process(main, "hard_drop")
	var visible_lock_safe: bool = not main._game_over
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(5, 5)
	await _press_and_process(main, "hard_drop")
	visible_lock_safe = visible_lock_safe and not main._game_over
	for x: int in range(3, 7):
		main._board.set_cell(Vector2i(x, 2), Tetromino.PieceType.T)
		main._board.set_cell(Vector2i(x, 3), Tetromino.PieceType.T)
	main._spawn_piece()
	var game_over_hit: bool = main._game_over
	main.free()
	_case(ctx, "game_over_only_via_bd05", visible_lock_safe and game_over_hit)


static func _case_stress_session(ctx: Dictionary) -> void:
	var main = _spawn_main()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260914
	var integrity: bool = true
	var no_double_lock: bool = true
	var prev_locked: int = _count_locked(main._board)
	var restarted: bool = false
	for frame: int in 1200:
		await (Engine.get_main_loop() as SceneTree).process_frame
		var pressed: String = ""
		var roll: int = rng.randi() % 100
		if main._paused and roll < 80:
			pressed = "pause"
		elif roll < 10:
			pressed = "rotate"
		elif roll < 20:
			pressed = "rotate_ccw"
		elif roll < 30:
			pressed = "move_left"
		elif roll < 40:
			pressed = "move_right"
		elif roll < 45:
			pressed = "soft_drop"
		elif roll < 50:
			pressed = "hold"
		elif roll < 53:
			pressed = "pause"
		elif roll < 55 and frame > 590 and frame < 610 and not restarted:
			pressed = "restart"
			restarted = true
		if pressed != "":
			Input.action_press(pressed)
		main._process(0.016)
		if pressed != "":
			Input.action_release(pressed)
		var locked_now: int = _count_locked(main._board)
		if locked_now - prev_locked > 4:
			no_double_lock = false
		prev_locked = locked_now
		if main._game_over:
			break
		if not _piece_legal(main):
			integrity = false
	main.free()
	_case(ctx, "stress_session_no_errors_or_overlap", integrity and no_double_lock)


static func _case_rotate_after_hidden_spawn(ctx: Dictionary) -> void:
	var main = _spawn_main()
	var spawned_hidden: bool = main._piece != null and main._piece_pos.y == Board.HIDDEN_HEIGHT - 2
	await _press_and_process(main, "rotate")
	var cw_legal: bool = _piece_legal(main)
	await _press_and_process(main, "rotate_ccw")
	var ccw_legal: bool = _piece_legal(main)
	main.free()
	_case(ctx, "rotate_immediately_after_hidden_spawn_stays_legal", spawned_hidden and cw_legal and ccw_legal)


static func _case_hold_harddrop_blocked_spawn_guard(ctx: Dictionary) -> void:
	var main = _spawn_main()
	for x: int in range(3, 7):
		main._board.set_cell(Vector2i(x, 2), Tetromino.PieceType.T)
		main._board.set_cell(Vector2i(x, 3), Tetromino.PieceType.T)
	main._piece = Tetromino.new(Tetromino.PieceType.T)
	main._piece_pos = Vector2i(3, 5)
	var locked_before: int = _count_locked(main._board)
	await (Engine.get_main_loop() as SceneTree).process_frame
	Input.action_press("hold")
	Input.action_press("hard_drop")
	main._process(0.016)
	Input.action_release("hold")
	Input.action_release("hard_drop")
	await (Engine.get_main_loop() as SceneTree).process_frame
	var ok: bool = main._game_over \
		and _count_locked(main._board) - locked_before <= 8 \
		and not (main._piece != null and not main._board.can_place(main._piece.get_cells(), main._piece_pos) and not main._game_over)
	main.free()
	_case(ctx, "hold_harddrop_on_blocked_spawn_locks_once_and_ends_game", ok)
