extends SceneTree
## BoardFX (scripts/board_fx.gd): the shared effect component of both modes.
##
## Unit cases drive a bare BoardFX through advance() (no tree needed): every
## effect is bounded, settles on its own and returns the board offset to
## exactly zero. The versus cases run the real scene and check that the model's
## events (clear / garbage / lost) reach the right board's effects.

const MODULE_NAME: String = "board_fx"

const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const STEP: float = 1.0 / 60.0
## Longest any effect may keep animating after its trigger.
const SETTLE_CAP_SECONDS: float = 1.5
const SIDE_PLAYER: int = VersusBattle.Side.PLAYER
const SIDE_AI: int = VersusBattle.Side.AI


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d board fx cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("BOARD FX TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _tree().process_frame
	_case_every_effect_settles_and_offset_returns_to_zero(ctx)
	_case_shake_is_bounded_and_decays(ctx)
	_case_garbage_shoves_board_up_then_releases(ctx)
	_case_callout_wording(ctx)
	_case_reset_clears_everything(ctx)
	await _case_pack_sprite_effects_play_and_replace(ctx)
	_case_every_special_clear_has_its_own_sound(ctx)
	await _case_versus_clear_drives_attacker_fx_and_sends_orb(ctx)
	await _case_versus_garbage_and_loss_drive_receiver_fx(ctx)
	await _case_versus_countdown_holds_pieces_then_go(ctx)
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


static func _new_fx() -> BoardFX:
	var fx: BoardFX = BoardFX.new()
	fx.setup(22.0, ThemeDB.fallback_font)
	return fx


static func _row_colors() -> Array:
	var row: Array[Color] = []
	for x: int in BoardFX.COLS:
		row.append(Color.CYAN)
	return [row]


static func _case_every_effect_settles_and_offset_returns_to_zero(ctx: Dictionary) -> void:
	var fx: BoardFX = _new_fx()
	var ok: bool = not fx.is_active() and fx.offset == Vector2.ZERO
	var one_row: Array[int] = [19]
	var cells: Array[Vector2i] = [Vector2i(4, 18), Vector2i(5, 18), Vector2i(4, 19), Vector2i(5, 19)]
	fx.line_clear(one_row, _row_colors())
	fx.lock_flash(cells)
	fx.hard_drop(cells, 12, Color.YELLOW)
	fx.popup("TETRIS", "B2B  +5", Color.CYAN)
	fx.shake(10.0)
	fx.garbage_in(4)
	ok = ok and fx.is_active() and fx.popup_text() == "TETRIS"
	var elapsed: float = 0.0
	while fx.is_active() and elapsed < SETTLE_CAP_SECONDS + 1.0:
		fx.advance(STEP)
		elapsed += STEP
	ok = ok and not fx.is_active() and elapsed <= SETTLE_CAP_SECONDS
	ok = ok and fx.offset == Vector2.ZERO and fx.popup_text().is_empty()
	fx.free()
	_case(ctx, "every_effect_settles_within_cap_and_offset_returns_to_zero", ok)


static func _case_shake_is_bounded_and_decays(ctx: Dictionary) -> void:
	var fx: BoardFX = _new_fx()
	fx.shake(9999.0)
	var peak: float = 0.0
	var late_peak: float = 0.0
	for i: int in 90:
		fx.advance(STEP)
		peak = maxf(peak, fx.offset.length())
		if i >= 30:
			late_peak = maxf(late_peak, fx.offset.length())
	# Each axis is within SHAKE_MAX, so the vector is within SHAKE_MAX * sqrt(2).
	var ok: bool = peak > 0.0 and peak <= BoardFX.SHAKE_MAX * 1.4143
	ok = ok and late_peak < 0.5 and fx.offset == Vector2.ZERO
	fx.free()
	_case(ctx, "shake_is_capped_and_decays_to_rest", ok)


static func _case_garbage_shoves_board_up_then_releases(ctx: Dictionary) -> void:
	var fx: BoardFX = _new_fx()
	fx.garbage_in(0)
	var ok: bool = not fx.is_active()
	fx.garbage_in(3)
	# Shove only (no shake in the measurement): the offset starts downward and
	# eases back, selling the rows pushing in from below.
	fx._shake = 0.0
	fx.advance(STEP)
	ok = ok and fx.offset.y > 0.0 and fx.offset.y <= 1.5 * fx.cell
	for i: int in 30:
		fx.advance(STEP)
	ok = ok and fx.offset == Vector2.ZERO
	fx.free()
	_case(ctx, "garbage_shoves_board_then_releases", ok)


static func _case_callout_wording(ctx: Dictionary) -> void:
	var none: int = Scoring.TSpinKind.NONE
	var ok: bool = BoardFX.callout(4, none, true, 3, false, 5) == ["TETRIS", "B2B  COMBO x3  +5"]
	ok = ok and BoardFX.callout(2, Scoring.TSpinKind.FULL, false, 1, false, 4) == ["T-SPIN DOUBLE", "+4"]
	ok = ok and BoardFX.callout(1, Scoring.TSpinKind.MINI, false, 1, false, 0) == ["T-SPIN MINI SINGLE", ""]
	ok = ok and BoardFX.callout(0, Scoring.TSpinKind.FULL, false, 0, false) == ["T-SPIN", ""]
	ok = ok and BoardFX.callout(1, none, false, 1, true, 10) == ["PERFECT CLEAR", "+10"]
	# A plain single with nothing attached says nothing at all.
	ok = ok and BoardFX.callout(1, none, false, 1, false, 0) == ["", ""]
	# A combo'd double sends its row count without a headline.
	ok = ok and BoardFX.callout(2, none, false, 2, false, 2) == ["", "COMBO x2  +2"]
	_case(ctx, "callout_wording_for_clears_spins_combo_b2b_and_rows_sent", ok)


# Every special clear has its own sound (2026-10-12), and the default pack
# ships a file for each of them.
static func _case_every_special_clear_has_its_own_sound(ctx: Dictionary) -> void:
	var none: int = Scoring.TSpinKind.NONE
	var mini: int = Scoring.TSpinKind.MINI
	var full: int = Scoring.TSpinKind.FULL
	var ok: bool = BoardFX.clear_sound(1, none, false) == "clear" and BoardFX.clear_sound(3, none, false) == "clear" 		and BoardFX.clear_sound(4, none, false) == "tetris" 		and BoardFX.clear_sound(0, mini, false) == "tspin_mini" and BoardFX.clear_sound(1, mini, false) == "tspin_mini" 		and BoardFX.clear_sound(0, full, false) == "tspin" and BoardFX.clear_sound(1, full, false) == "tspin" 		and BoardFX.clear_sound(2, full, false) == "tspin_double" and BoardFX.clear_sound(3, full, false) == "tspin_triple" 		and BoardFX.clear_sound(2, full, true) == "perfect_clear" and BoardFX.clear_sound(4, none, true) == "perfect_clear"
	ResourcePack.set_enabled([], false)
	var seen: Array[AudioStream] = []
	for event: String in ["clear", "tetris", "tspin_mini", "tspin", "tspin_double", "tspin_triple", "perfect_clear", "b2b", "combo"]:
		var stream: AudioStream = ResourcePack.sound(event)
		ok = ok and stream != null and not seen.has(stream)
		seen.append(stream)
		ok = ok and (load("res://scripts/main.gd").SFX_EVENTS as Array).has(event) and (load("res://scripts/versus.gd").SFX_EVENTS as Array).has(event)
	_case(ctx, "every_special_clear_has_its_own_sound", ok)


static func _case_reset_clears_everything(ctx: Dictionary) -> void:
	var fx: BoardFX = _new_fx()
	var one_row: Array[int] = [10]
	fx.line_clear(one_row, _row_colors())
	fx.popup("TETRIS", "", Color.WHITE)
	fx.set_danger(true)
	fx.play_ko()
	fx.advance(STEP)
	var ok: bool = fx.is_active() and fx.is_danger() and fx.is_ko()
	fx.reset()
	ok = ok and not fx.is_active() and not fx.is_danger() and not fx.is_ko() and fx.offset == Vector2.ZERO
	fx.free()
	_case(ctx, "reset_clears_every_running_effect", ok)


# A pack's "effects" (2026-10-11): the Pixel FX pack gives every board event
# a sprite sheet that loads, plays at the event instead of the drawn effect,
# and ends; without the pack the drawn effects are back.
static func _case_pack_sprite_effects_play_and_replace(ctx: Dictionary) -> void:
	var before: Array[String] = ResourcePack.enabled_ids()
	ResourcePack.set_enabled(["pixelfx"], false)
	var ok: bool = true
	for event: String in ResourcePack.EFFECT_EVENTS:
		var effect: Dictionary = ResourcePack.effect(event)
		ok = ok and not effect.is_empty() and effect["texture"] is Texture2D and bool(effect["replace"])
		if effect.is_empty():
			continue
		# The sheet holds every frame it promises.
		var size: Vector2i = effect["frame"]
		var sheet: Texture2D = effect["texture"]
		var rows: int = ceili(float(int(effect["frames"])) / float(int(effect["columns"])))
		ok = ok and int(effect["columns"]) * size.x <= sheet.get_width() and rows * size.y <= sheet.get_height()
	var fx: BoardFX = _new_fx()
	var one_row: Array[int] = [19]
	var four_rows: Array[int] = [16, 17, 18, 19]
	var cells: Array[Vector2i] = [Vector2i(4, 18), Vector2i(5, 18), Vector2i(6, 18), Vector2i(5, 17)]
	fx.line_clear(one_row, _row_colors())
	ok = ok and fx.sprite_count() == 1 and fx._sweeps.is_empty() and fx._particles.is_empty()
	# Four rows are one Tetris animation, not four row animations.
	fx.line_clear(four_rows, [_row_colors()[0], _row_colors()[0], _row_colors()[0], _row_colors()[0]])
	ok = ok and fx.sprite_count() == 2
	fx.special_clear(true, true)
	fx.lock_flash(cells)
	fx.hard_drop(cells, 6, Color.WHITE)
	fx.garbage_in(2)
	fx.play_ko()
	ok = ok and fx.sprite_count() == 8 and fx._flashes.is_empty() and fx._trails.is_empty() and fx._garbage_time == 0.0
	# The board still reacts: shake and shove are not part of the look.
	fx.advance(STEP)
	ok = ok and fx.offset != Vector2.ZERO
	for _i: int in 120:
		fx.advance(STEP)
	ok = ok and fx.sprite_count() == 0
	fx.free()
	ResourcePack.set_enabled([], false)
	ok = ok and ResourcePack.effect("line_clear").is_empty()
	var plain: BoardFX = _new_fx()
	plain.line_clear(one_row, _row_colors())
	ok = ok and plain.sprite_count() == 0 and plain._sweeps.size() == 1 and not plain._particles.is_empty()
	plain.free()
	ResourcePack.set_enabled(before, false)
	_case(ctx, "pack_sprite_effects_play_and_replace", ok)


# ---------------------------------------------------------------------------
# Versus scene wiring.
static func _spawn_versus():
	var session: Node = _tree().root.get_node_or_null(^"GameSession")
	if session != null:
		session.start_mode(session.MODE_NONE)
	var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	return scene


static func _skip_countdown(scene: Node) -> void:
	scene._model.tick(scene.COUNTDOWN_SECONDS + 0.1)
	await _tree().process_frame


static func _orb_count(scene: Node) -> int:
	var count: int = 0
	for child: Node in scene._view.get_children():
		if child is Sprite2D:
			count += 1
	return count


static func _case_versus_clear_drives_attacker_fx_and_sends_orb(ctx: Dictionary) -> void:
	var scene = _spawn_versus()
	await _skip_countdown(scene)
	var model: VersusBattle = scene._model
	var board: Board = model.board(SIDE_PLAYER)
	# The CPU's board holds still: a lock of its own would take the queued
	# rows in before the meter is read below (2026-10-12: this made the case
	# fail now and then, depending on how fast the frames went by).
	model.debug_freeze_side(SIDE_AI, true)
	# Four rows full except column 6; a vertical I finishes the Tetris.
	for row: int in range(20, 24):
		for col: int in Board.BOARD_WIDTH:
			if col != 6:
				board.set_cell(Vector2i(col, row), Tetromino.PieceType.J)
	# Residue above, so the Tetris is not a Perfect Clear.
	board.set_cell(Vector2i(0, 19), Tetromino.PieceType.J)
	model.debug_force_piece(SIDE_PLAYER, Tetromino.PieceType.I, 1, Vector2i(4, 20), false, -1)
	model.debug_lock_now(SIDE_PLAYER, true)
	await _tree().process_frame
	var player_fx: BoardFX = scene._sides[SIDE_PLAYER].fx
	var ai_fx: BoardFX = scene._sides[SIDE_AI].fx
	var ok: bool = model.lines(SIDE_PLAYER) == 4 and model.pending_garbage(SIDE_AI) == 4
	ok = ok and player_fx._sweeps.size() == 4 and not player_fx._particles.is_empty()
	ok = ok and player_fx.popup_text() == "TETRIS" and player_fx.popup_detail() == "+4"
	ok = ok and ai_fx._sweeps.is_empty() and ai_fx.popup_text().is_empty()
	# One orb is in flight toward the AI's warning bar and frees itself.
	ok = ok and _orb_count(scene) == 1
	# The piece that follows is already in play: the clear never blocks.
	ok = ok and model.current_piece(SIDE_PLAYER) != null and model.phase() == VersusBattle.Phase.PLAYING
	await _tree().create_timer(BoardFX.ORB_TIME + 0.2).timeout
	ok = ok and _orb_count(scene) == 0
	# The warning bar and its count show the queued rows.
	# Revised 2026-10-10: the count is drawn by the side's WarnBar.
	ok = ok and (scene._sides[SIDE_AI].layout.warn_bar as WarnBar).pending == 4 \
		and (scene._sides[SIDE_AI].layout.warn_bar as WarnBar).count_text() == "4"
	scene.free()
	await _tree().process_frame
	_case(ctx, "versus_clear_drives_attacker_fx_callout_and_orb", ok)


static func _case_versus_garbage_and_loss_drive_receiver_fx(ctx: Dictionary) -> void:
	var scene = _spawn_versus()
	await _skip_countdown(scene)
	var model: VersusBattle = scene._model
	# Queue 4 rows on the player through a real AI Tetris.
	var ai_board: Board = model.board(SIDE_AI)
	for row: int in range(20, 24):
		for col: int in Board.BOARD_WIDTH:
			if col != 6:
				ai_board.set_cell(Vector2i(col, row), Tetromino.PieceType.J)
	ai_board.set_cell(Vector2i(0, 19), Tetromino.PieceType.J)
	model.debug_force_piece(SIDE_AI, Tetromino.PieceType.I, 1, Vector2i(4, 20), false, -1)
	model.debug_lock_now(SIDE_AI, true)
	await _tree().process_frame
	var player_fx: BoardFX = scene._sides[SIDE_PLAYER].fx
	var ok: bool = model.pending_garbage(SIDE_PLAYER) == 4 and player_fx._garbage_time == 0.0
	# The player's next non-clearing lock takes them: shove + flash.
	model.debug_force_piece(SIDE_PLAYER, Tetromino.PieceType.O, 0, Vector2i(0, 22), false, -1)
	model.debug_lock_now(SIDE_PLAYER, false)
	await _tree().process_frame
	ok = ok and model.pending_garbage(SIDE_PLAYER) == 0
	ok = ok and player_fx._garbage_time > 0.0 and player_fx._garbage_rows == 4
	# A lock entirely above the field loses: K.O. wipe on that board only.
	model.debug_force_piece(SIDE_PLAYER, Tetromino.PieceType.O, 0, Vector2i(4, 0), false, -1)
	model.debug_lock_now(SIDE_PLAYER, false)
	await _tree().process_frame
	await _tree().process_frame
	ok = ok and player_fx.is_ko() and not (scene._sides[SIDE_AI].fx as BoardFX).is_ko()
	ok = ok and model.phase() == VersusBattle.Phase.MATCH_OVER
	# Result choices are real buttons; the overlay reports rows sent.
	ok = ok and (scene._result_buttons as Control).visible
	ok = ok and (scene._overlay_detail as Label).text.contains("0 : 4")
	scene.free()
	await _tree().process_frame
	_case(ctx, "versus_garbage_shove_and_ko_on_the_receiving_board", ok)


static func _case_versus_countdown_holds_pieces_then_go(ctx: Dictionary) -> void:
	var scene = _spawn_versus()
	await _tree().process_frame
	var model: VersusBattle = scene._model
	var ok: bool = model.phase() == VersusBattle.Phase.COUNTDOWN
	var start_pos: Vector2i = model.piece_pos(SIDE_PLAYER)
	var fx: BoardFX = scene._sides[SIDE_PLAYER].fx
	ok = ok and fx.popup_text() == "3"
	# Taps made before GO are dropped and nothing falls.
	model.tap(SIDE_PLAYER, VersusBattle.ACTION_HARD_DROP)
	model.tick(1.2)
	await _tree().process_frame
	ok = ok and model.phase() == VersusBattle.Phase.COUNTDOWN and fx.popup_text() == "2"
	ok = ok and model.piece_pos(SIDE_PLAYER) == start_pos and model.pieces_placed(SIDE_PLAYER) == 0
	# The falling piece is not drawn until GO.
	# (Revised 2026-10-10: the board is one BoardView now.)
	ok = ok and (scene._sides[SIDE_PLAYER].board as BoardView).piece_cells().is_empty()
	model.tick(2.0)
	await _tree().process_frame
	await _tree().process_frame
	ok = ok and model.phase() == VersusBattle.Phase.PLAYING and fx.popup_text() == "GO!"
	scene.free()
	await _tree().process_frame
	_case(ctx, "versus_countdown_holds_pieces_drops_taps_then_go", ok)
