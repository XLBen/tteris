extends SceneTree
## Debug duel tests (T-07b3): the versus battle model driven only through its
## real input surface, the full attack -> queue -> insert chain built from
## real lock events, a programmatic top-out, and the launch-surface freeze that
## keeps any debug/duel entry out of the player path.
##
## Every case runs the real model chain (setup -> press/release/tap and
## debug_force_piece / debug_lock_now -> tick), never a mock. The fixed seed
## 20260917 reproduces the RNG-driven piece order and garbage holes.

const MODULE_NAME: String = "debug_duel"

const SEED: int = 20260917

const SIDE_PLAYER: int = VersusBattle.Side.PLAYER
const SIDE_AI: int = VersusBattle.Side.AI
const PIECE_O: int = Tetromino.PieceType.O
const PIECE_J: int = Tetromino.PieceType.J

## Frozen gameplay InputMap at this slice: the debug duel must not add actions.
const FROZEN_INPUT_ACTIONS: Array[String] = [
	"move_left",
	"move_right",
	"soft_drop",
	"rotate",
	"rotate_ccw",
	"hard_drop",
	"hold",
	"pause",
	"restart",
]

## Player-facing launch surfaces that must stay free of every debug/duel entry.
const NO_DEBUG_ENTRY_PATHS: Array[String] = [
	"res://scenes/menus/mode_select/mode_select.tscn",
	"res://scenes/menus/mode_select/mode_select.gd",
	"res://scenes/menus/main_menu/main_menu_with_animations.tscn",
	"res://scenes/menus/main_menu/main_menu_with_animations.gd",
]


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d debug duel cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("DEBUG DUEL TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_input_surface_dual_drive(ctx)
	_case_send_cancel_chain(ctx)
	_case_ai_top_out_player_wins(ctx)
	_case_no_debug_player_entry(ctx)
	await _tree().process_frame
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


# ---------------------------------------------------------------------------
# 1) Pure input surface: both sides are driven only through press / release /
#    tap (movement, rotation, soft drop, hard drop) over several pieces, and
#    the two boards and pieces never interfere with each other.
static func _case_input_surface_dual_drive(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	var spawn_y: int = Board.HIDDEN_HEIGHT - 2
	var ok: bool = battle.phase() == VersusBattle.Phase.PLAYING
	ok = ok and battle.current_piece(SIDE_PLAYER) != null and battle.current_piece(SIDE_AI) != null

	# PLAYER press -> tick -> release moves one cell left; the AI state and the
	# AI board are untouched by player input.
	var player_spawn_x: int = battle.piece_pos(SIDE_PLAYER).x
	var ai_spawn_pos: Vector2i = battle.piece_pos(SIDE_AI)
	var ai_cells_before: Array = _board_cells(battle.board(SIDE_AI))
	battle.press(SIDE_PLAYER, VersusBattle.ACTION_MOVE_LEFT)
	battle.tick(0.05)
	ok = ok and battle.piece_pos(SIDE_PLAYER).x == player_spawn_x - 1
	battle.release(SIDE_PLAYER, VersusBattle.ACTION_MOVE_LEFT)
	ok = ok and battle.piece_pos(SIDE_AI) == ai_spawn_pos
	ok = ok and _board_cells(battle.board(SIDE_AI)) == ai_cells_before

	# PLAYER tap rotates on the empty field without moving the AI piece.
	var player_rotation_before: int = battle.current_piece(SIDE_PLAYER).rotation
	battle.tap(SIDE_PLAYER, VersusBattle.ACTION_ROTATE)
	battle.tick(0.05)
	ok = ok and battle.current_piece(SIDE_PLAYER).rotation != player_rotation_before
	ok = ok and battle.piece_pos(SIDE_AI) == ai_spawn_pos

	# AI tap right, then press/release rotate_ccw and press/release soft drop.
	var ai_x_before: int = battle.piece_pos(SIDE_AI).x
	battle.tap(SIDE_AI, VersusBattle.ACTION_MOVE_RIGHT)
	battle.tick(0.05)
	ok = ok and battle.piece_pos(SIDE_AI).x == ai_x_before + 1
	var ai_rotation_before: int = battle.current_piece(SIDE_AI).rotation
	battle.press(SIDE_AI, VersusBattle.ACTION_ROTATE_CCW)
	battle.tick(0.05)
	battle.release(SIDE_AI, VersusBattle.ACTION_ROTATE_CCW)
	ok = ok and battle.current_piece(SIDE_AI).rotation != ai_rotation_before
	var ai_y_before: int = battle.piece_pos(SIDE_AI).y
	battle.press(SIDE_AI, VersusBattle.ACTION_SOFT_DROP)
	battle.tick(0.05)
	battle.release(SIDE_AI, VersusBattle.ACTION_SOFT_DROP)
	ok = ok and battle.piece_pos(SIDE_AI).y == ai_y_before + 1

	# Three pieces per side land through tap hard_drop; every lock only mutates
	# the locking side's board and leaves a fresh piece at the spawn row.
	for i: int in 3:
		var ai_cells_before_lock: Array = _board_cells(battle.board(SIDE_AI))
		battle.tap(SIDE_PLAYER, VersusBattle.ACTION_HARD_DROP)
		battle.tick(0.05)
		ok = ok and _board_cells(battle.board(SIDE_AI)) == ai_cells_before_lock
		if i == 0:
			ok = ok and not battle.board(SIDE_PLAYER).is_empty_board()
			ok = ok and battle.board(SIDE_AI).is_empty_board()
		var player_cells_before_lock: Array = _board_cells(battle.board(SIDE_PLAYER))
		battle.tap(SIDE_AI, VersusBattle.ACTION_HARD_DROP)
		battle.tick(0.05)
		ok = ok and _board_cells(battle.board(SIDE_PLAYER)) == player_cells_before_lock
		ok = ok and not battle.board(SIDE_AI).is_empty_board()
		ok = ok and battle.current_piece(SIDE_PLAYER) != null and battle.current_piece(SIDE_AI) != null
		ok = ok and battle.piece_pos(SIDE_PLAYER).y == spawn_y and battle.piece_pos(SIDE_AI).y == spawn_y

	ok = ok and battle.phase() == VersusBattle.Phase.PLAYING
	ok = ok and _occupied_cells(battle.board(SIDE_PLAYER)) > 0 and _occupied_cells(battle.board(SIDE_AI)) > 0
	# The player shifted left and the AI shifted right: the two landed boards
	# never share the same content.
	ok = ok and _board_cells(battle.board(SIDE_PLAYER)) != _board_cells(battle.board(SIDE_AI))
	_case(ctx, "input_press_release_tap_drives_both_sides_boards_land_independent", ok)


# ---------------------------------------------------------------------------
# 2) Attack -> queue -> insert chain under the modern rule (an attack cancels
#    the attacker's own queue first), asserted on pending_garbage_batches rows
#    at every step. All attacks come from real lock/clear/send events.
static func _case_send_cancel_chain(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()

	# a) Player Tetris: four cleared rows -> one batch of 4 rows on the AI.
	_attack_tetris(battle, SIDE_PLAYER)
	_case(ctx, "chain_a_player_tetris_queues_batch_4_on_ai", _batches_are(battle, SIDE_AI, [4]))

	# b) Player Double (first clear of a fresh combo) sends 1: the player's own
	#    queue is empty, so the 1 is appended as a new batch: AI [4, 1].
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	_attack_double_fresh(battle, SIDE_PLAYER)
	_case(ctx, "chain_b_player_double_appends_batch_1_ai_4_1", _batches_are(battle, SIDE_AI, [4, 1]))

	# c) AI answers with a real attack of exactly 3. Construction: a Single is
	#    the 1st clear (attack 0, combo 1), then a Triple is the 2nd consecutive
	#    clear: base 2 + floor(combo_count 2 / 2) = 3, i.e. exactly
	#    attack_for_event(3, NONE, false, 2, false). Revised 2026-10-10
	#    (mainstream rules): clearing locks take no garbage, so the AI still
	#    holds [4, 1] when the Triple lands; the 3 cancels inside its first
	#    batch (4 -> 1) and nothing reaches the player.
	_ai_single(battle)
	_ai_triple(battle)
	var c_ok: bool = VersusBattle.attack_for_event(3, Scoring.TSpinKind.NONE, false, 2, false) == 3
	c_ok = c_ok and _batches_are(battle, SIDE_PLAYER, [])
	c_ok = c_ok and battle.pending_garbage(SIDE_PLAYER) == 0
	c_ok = c_ok and _batches_are(battle, SIDE_AI, [1, 1])
	_case(ctx, "chain_c_ai_single_then_triple_cancels_3_of_its_own_queue", c_ok)

	# d) Keep stacking attacks on the AI's queue through the real chain: a
	#    fresh Tetris (attack 4) and a Double (attack 1) append behind the
	#    [1, 1] the AI still holds.
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	var d1_ok: bool = _batches_are(battle, SIDE_PLAYER, [])
	d1_ok = d1_ok and battle.pending_garbage(SIDE_PLAYER) == 0
	_attack_tetris(battle, SIDE_PLAYER)
	d1_ok = d1_ok and _batches_are(battle, SIDE_AI, [1, 1, 4])
	_lock_noclear(battle, SIDE_PLAYER, 8, 18)
	_attack_double_fresh(battle, SIDE_PLAYER)
	d1_ok = d1_ok and _batches_are(battle, SIDE_AI, [1, 1, 4, 1])
	_case(ctx, "chain_d1_real_chain_appends_batches_behind_ai_queue", d1_ok)

	#    Player Perfect Clear: the flat 10 is appended as another batch (the
	#    player's own queue is empty).
	_attack_perfect_clear(battle, SIDE_PLAYER)
	var d2_ok: bool = _batches_are(battle, SIDE_AI, [1, 1, 4, 1, 10])
	d2_ok = d2_ok and battle.pending_garbage(SIDE_AI) == 17
	d2_ok = d2_ok and battle.phase() == VersusBattle.Phase.PLAYING
	_case(ctx, "chain_d2_player_perfect_clear_10_appends_batch", d2_ok)


# ---------------------------------------------------------------------------
# 3) Programmatic top-out: an AI lock whose every cell is hidden loses the
#    round, and SINGLE format ends the match for the player.
static func _case_ai_top_out_player_wins(ctx: Dictionary) -> void:
	var battle: VersusBattle = _new_battle()
	_force_lock(battle, SIDE_AI, PIECE_O, 0, Vector2i(0, 2))
	var ok: bool = battle.phase() == VersusBattle.Phase.PLAYING
	battle.tick(0.0)
	ok = ok and battle.round_winner() == SIDE_PLAYER
	ok = ok and battle.round_wins(SIDE_PLAYER) == 1 and battle.round_wins(SIDE_AI) == 0
	ok = ok and battle.match_winner() == SIDE_PLAYER
	ok = ok and battle.phase() == VersusBattle.Phase.MATCH_OVER
	ok = ok and not battle.last_round_draw()
	_case(ctx, "ai_all_hidden_lock_player_wins_round_and_single_match", ok)


# ---------------------------------------------------------------------------
# 4) No player entry for the debug duel: menu texts, project autoloads and the
#    frozen InputMap are all untouched.
static func _case_no_debug_player_entry(ctx: Dictionary) -> void:
	for path: String in NO_DEBUG_ENTRY_PATHS:
		var text: String = _read_text(path).to_lower()
		var ok: bool = not text.is_empty()
		ok = ok and not text.contains("debug") and not text.contains("duel")
		_case(ctx, "menu_text_no_debug_or_duel_entry_%s" % path.get_file(), ok)
	_case_no_versus_autoload(ctx)
	_case_input_map_frozen(ctx)


static func _case_no_versus_autoload(ctx: Dictionary) -> void:
	var text: String = _read_text("res://project.godot").to_lower()
	var ok: bool = not text.is_empty()
	ok = ok and not text.contains("versus_battle") and not text.contains("versus_ai")
	_case(ctx, "project_godot_has_no_versus_battle_or_versus_ai_autoload", ok)


static func _case_input_map_frozen(ctx: Dictionary) -> void:
	var expected: Array = FROZEN_INPUT_ACTIONS.duplicate()
	expected.sort()
	var actual: Array = []
	for action: String in InputMap.get_actions():
		if not action.begins_with("ui_"):
			actual.append(action)
	actual.sort()
	var ok: bool = actual.size() == expected.size()
	if ok:
		for i: int in expected.size():
			if String(actual[i]) != String(expected[i]):
				ok = false
				break
	_case(ctx, "input_map_is_exactly_the_frozen_nine_actions", ok)


# ---------------------------------------------------------------------------
# Fixtures (same technique as test_versus_battle.gd / test_versus_match.gd).
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


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


## Resets and clears exactly two rows: the first clear of a fresh combo, so the
## attack is the frozen Double value 1.
static func _attack_double_fresh(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in [22, 23]:
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


## Resets and clears every row: a Perfect Clear (flat attack 10).
static func _attack_perfect_clear(battle: VersusBattle, side: int) -> void:
	battle.board(side).reset()
	for row: int in range(20, 24):
		_fill_row_except(battle.board(side), row, [6])
	_lock_vertical_i(battle, side, 6)


## AI Single: attack 0 and combo 1, the first link of the real chain that makes
## the following Triple send exactly 3.
static func _ai_single(battle: VersusBattle) -> void:
	battle.board(SIDE_AI).reset()
	_fill_row_except(battle.board(SIDE_AI), 23, [6])
	_lock_vertical_i(battle, SIDE_AI, 6)


## AI Triple: the 2nd consecutive clear, base 2 + floor(2 / 2) = attack 3.
static func _ai_triple(battle: VersusBattle) -> void:
	battle.board(SIDE_AI).reset()
	for row: int in [21, 22, 23]:
		_fill_row_except(battle.board(SIDE_AI), row, [6])
	_lock_vertical_i(battle, SIDE_AI, 6)


## Locks an O piece that clears nothing (`x`,`y` must be free and visible).
static func _lock_noclear(battle: VersusBattle, side: int, x: int, y: int) -> void:
	_force_lock(battle, side, PIECE_O, 0, Vector2i(x, y))


static func _batches_are(battle: VersusBattle, side: int, expected: Array) -> bool:
	var batches: Array[int] = battle.pending_garbage_batches(side)
	if batches.size() != expected.size():
		return false
	for i: int in expected.size():
		if batches[i] != int(expected[i]):
			return false
	return true


static func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


static func _occupied_cells(board: Board) -> int:
	var total: int = 0
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if not board.is_empty_at(Vector2i(x, y)):
				total += 1
	return total


static func _board_cells(board: Board) -> Array[int]:
	var cells: Array[int] = []
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			cells.append(board.get_cell(Vector2i(x, y)))
	return cells
