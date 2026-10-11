class_name VersusBattle
extends RefCounted
## Headless two-board versus model (goal G-VERSUS-BATTLE, slice versus-entry-1).
##
## Two independent 10x20+4 boards run the frozen single-player timing rules
## (DAS/ARR, soft drop, gravity formula, lock delay/resets, 7-bag, Hold, SRS
## from scripts/main.gd). Line clears send garbage through the Puyo Puyo Tetris
## table and the mainstream modern garbage rules:
## - both sides draw the SAME 7-bag sequence (per-side bag RNGs share the
##   battle seed; garbage holes come from a separate RNG);
## - the attack first cancels the attacker's own pending garbage 1:1 (FIFO
##   batches), and only the remainder is queued on the opponent;
## - a lock that clears lines never receives garbage; a lock that clears
##   nothing receives at most GARBAGE_CAP_PER_LOCK queued rows, the rest waits;
## - each inserted batch gets its own random hole column;
## - Perfect Clear sends a flat 10 (no line/combo addition);
## - a side loses only by lock out (piece locked entirely above the visible
##   field), block out (spawn position occupied) or garbage pushing cells out
##   of the 24-row buffer.
## The view reads what happened through drain_events() (lock / clear / spin /
## garbage / hold / lost dictionaries); the model itself stays signal-free.
##
## The model never touches Input: press/release/tap are the whole input
## surface, so the versus scene (T-08) and the debug duel tests drive the
## exact same code path. This class is RefCounted and headless-only: it has no
## player entry, no scene and no autoload registration.

enum Side { PLAYER, AI }
## RISING: both sides share one level that grows with the round's elapsed
## time (RISING_LEVEL_SECONDS per level, capped at RISING_MAX_LEVEL).
enum Rules { FIXED, RISING }
enum MatchFormat { SINGLE, BEST_OF_3 }
enum Phase { PLAYING, ROUND_OVER, MATCH_OVER, COUNTDOWN }

## Perfect Clear attacks send exactly this many rows (BC-04/BD-11).
const PERFECT_CLEAR_SEND: int = 10
## Mini T-Spin send by cleared lines (Mini Single 0, Mini Double 1).
const T_SPIN_MINI_SEND: Array[int] = [0, 0, 1]
const COMBO_SEND_CAP: int = 5
## At most this many queued garbage rows enter the board on one lock.
const GARBAGE_CAP_PER_LOCK: int = 8
## Rising speed (owner decision 2026-10-10): one level per this many lines
## cleared by both sides together - the harder the fight, the faster it gets.
const RISING_LINES_PER_LEVEL: int = 8
const RISING_MAX_LEVEL: int = 10
## Fastest gravity (the classic levels past 10 use it; versus stops at 10).
const MIN_GRAVITY_INTERVAL: float = 1.0 / 120.0
## drain_events() backlog bound for callers that never drain (headless tests).
const EVENT_BACKLOG_CAP: int = 256

# Timing and scoring constants mirror scripts/main.gd exactly (freeze).
const DAS_DELAY: float = 0.17
const ARR_RATE: float = 0.05
const SOFT_DROP_INTERVAL: float = 0.05
const LOCK_DELAY: float = 0.5
const MAX_LOCK_RESETS: int = 15
const NEXT_COUNT: int = 5
const SOFT_DROP_SCORE: int = 1
const HARD_DROP_SCORE: int = 2

const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_SOFT_DROP: StringName = &"soft_drop"
const ACTION_ROTATE: StringName = &"rotate"
const ACTION_ROTATE_CCW: StringName = &"rotate_ccw"
const ACTION_HARD_DROP: StringName = &"hard_drop"
const ACTION_HOLD: StringName = &"hold"

var _rules: int = Rules.FIXED
var _fixed_level: int = 1
var _match_format: int = MatchFormat.SINGLE
## The seed this battle was setup() with (S2 read surface for seed_value()).
var _stored_seed: int = 0
var _garbage_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Seconds of the pre-round countdown; 0 (the headless default) starts rounds
## directly in PLAYING. The versus scene sets it before setup().
var countdown_seconds: float = 0.0
var _countdown: float = 0.0
var _elapsed: float = 0.0
var _events: Array[Dictionary] = []
var _rounds_begun: int = 0
var _sides: Array = []
var _phase: int = Phase.PLAYING
var _round_winner: int = -1
var _match_winner: int = -1
var _last_round_draw: bool = false
var _round_wins: Array[int] = [0, 0]
var _round_index: int = 1
var _paused: bool = false
var _started: bool = false


## Freezes the configuration and starts round `round_index` immediately.
## Passing the same `seed` reproduces the identical round (bag order and
## garbage holes are drawn from this battle's own RNG).
func setup(rules: int, fixed_level: int, match_format: int, seed: int = 0, round_wins: Array = [0, 0], round_index: int = 1) -> void:
	_rules = rules
	_fixed_level = fixed_level
	_match_format = match_format
	_stored_seed = seed
	_garbage_rng = RandomNumberGenerator.new()
	_garbage_rng.seed = hash([seed, "garbage"])
	_round_wins = [int(round_wins[0]), int(round_wins[1])]
	_round_index = round_index
	_paused = false
	_started = true
	_rounds_begun = 0
	_begin_round()


## Advances the progression to the next round (no-op index bump on a draw)
## and resets both sides. The versus scene calls it after ROUND_OVER.
func start_round() -> void:
	if _phase == Phase.ROUND_OVER and not _last_round_draw:
		_round_index += 1
	_begin_round()


## Replays the current round: boards/scores/garbage reset, round wins and
## round index are kept (draw replay and the in-game "restart round").
func restart_round() -> void:
	_begin_round()


func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


## Advances both sides by one frame and settles the round when a side topped
## out this tick. Both sides always finish their frame first, so a same-tick
## double top-out is detected as one draw.
func tick(delta: float) -> void:
	if not _started or _paused:
		return
	if _phase == Phase.COUNTDOWN:
		_countdown -= delta
		# Held keys keep charging through the countdown (DAS pre-charge); taps
		# made before GO are dropped.
		for s: SideState in _sides:
			s.oneshot.clear()
		if _countdown <= 0.0:
			_countdown = 0.0
			_phase = Phase.PLAYING
		return
	if _phase != Phase.PLAYING:
		return
	_elapsed += delta
	_apply_rising_level()
	_tick_side(Side.PLAYER, delta)
	_tick_side(Side.AI, delta)
	var player_lost: bool = _side_state(Side.PLAYER).lost
	var ai_lost: bool = _side_state(Side.AI).lost
	if player_lost or ai_lost:
		_settle_round(player_lost, ai_lost)


# ---------------------------------------------------------------------------
# Public read surface (also consumed by the versus scene and tests).
func board(side: int) -> Board:
	return _side_state(side).board


func current_piece(side: int) -> Tetromino:
	return _side_state(side).piece


func piece_pos(side: int) -> Vector2i:
	return _side_state(side).piece_pos


func ghost_pos(side: int) -> Vector2i:
	var s: SideState = _side_state(side)
	if s.piece == null:
		return s.piece_pos
	var pos: Vector2i = s.piece_pos
	while s.board.can_place(s.piece.get_cells(), pos + Vector2i(0, 1)):
		pos += Vector2i(0, 1)
	return pos


func score(side: int) -> int:
	return _side_state(side).score


func level(side: int) -> int:
	return _side_state(side).level


func lines(side: int) -> int:
	return _side_state(side).lines


func next_queue(side: int) -> Array[int]:
	var copy: Array[int] = []
	copy.append_array(_side_state(side).next_queue)
	return copy


func hold_type(side: int) -> int:
	return _side_state(side).hold_type


func pending_garbage(side: int) -> int:
	var total: int = 0
	for count: int in _side_state(side).pending_garbage:
		total += count
	return total


func pending_garbage_batches(side: int) -> Array[int]:
	var copy: Array[int] = []
	copy.append_array(_side_state(side).pending_garbage)
	return copy


func round_wins(side: int) -> int:
	return _round_wins[side]


func round_index() -> int:
	return _round_index


func match_format() -> int:
	return _match_format


func rules() -> int:
	return _rules


func fixed_level() -> int:
	return _fixed_level


## The seed this battle was setup() with (S2 read surface: the versus scene
## derives the AI's decision RNG from the same source as the bag/garbage RNG,
## so one seed reproduces a whole match).
func seed_value() -> int:
	return _stored_seed


## Total garbage rows this side has sent with its attacks (S2 read surface for
## the difficulty assertions/reports). Accumulated in _send_attack after the
## own-queue cancel/queue logic, so cancelled rows still count. The counter
## lives per round and restarts with the round.
func attack_sent(side: int) -> int:
	return _side_state(side).attack_sent_rows


## T-Spins (MINI and FULL alike) actually consumed at this side's locks this
## round (S3a read surface for the difficulty assertions/reports). Counted
## inside the two award branches of _finish_lock where pending_t_spin is
## really spent, so a classification computed on a lock that never reaches
## scoring (e.g. an all-hidden losing lock) never counts. The counter lives
## on the per-round SideState and restarts with the round like
## score/lines/attack_sent_rows.
func tspins(side: int) -> int:
	return _side_state(side).tspin_count


## Full T-Spins of `side` this round that cleared exactly `lines` rows
## (1 = Single, 2 = Double, 3 = Triple).
func tspin_clears(side: int, lines: int) -> int:
	return _side_state(side).tspin_clears[clampi(lines, 0, 3)]


## 1-based consecutive clearing-lock count (0 after a lock that cleared nothing).
func combo(side: int) -> int:
	return _side_state(side).combo


## Pieces this side has locked this round.
func pieces_placed(side: int) -> int:
	return _side_state(side).pieces_placed


## Seconds left before GO while phase() is COUNTDOWN, else 0.
func countdown_left() -> float:
	return _countdown


## Seconds of PLAYING time in the current round.
func elapsed() -> float:
	return _elapsed


## Returns and clears what happened since the last call, in order. Every entry
## has "type" and "side":
##   &"lock"    cells (world Vector2i), piece_type, hard, drop_distance
##   &"clear"   rows (board y), row_cells (10 cell values per row), lines,
##              t_spin, b2b (bonus applied), combo (1-based), perfect_clear,
##              attack, cancelled, sent (attack - cancelled)
##   &"spin"    t_spin (a T-Spin lock that cleared nothing)
##   &"garbage" rows (inserted row count)
##   &"hold"
##   &"lost"
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


func _emit(event: Dictionary) -> void:
	_events.append(event)
	if _events.size() > EVENT_BACKLOG_CAP:
		_events.pop_front()


## Whether this side's Back-to-Back chain is currently active (S3a read
## surface for tests/reports; also consumed by the S3c T-Spin strategy).
## Per-round state; resets with the round.
func b2b_active(side: int) -> bool:
	return _side_state(side).b2b_active


func phase() -> int:
	return _phase


## -1 while undecided or when the round was a draw.
func round_winner() -> int:
	return _round_winner


## -1 while undecided.
func match_winner() -> int:
	return _match_winner


func last_round_draw() -> bool:
	return _last_round_draw


func _apply_rising_level() -> void:
	if _rules != Rules.RISING:
		return
	var rising_level: int = rising_level_for_lines(_sides[0].lines + _sides[1].lines)
	for s: SideState in _sides:
		s.level = rising_level


## The shared level of a rising-speed round after `lines` cleared in total.
static func rising_level_for_lines(lines: int) -> int:
	return mini(RISING_MAX_LEVEL, 1 + lines / RISING_LINES_PER_LEVEL)


## Gravity interval, identical to scripts/main.gd.
static func gravity_interval(level: int) -> float:
	var base: float = maxf(0.001, 0.8 - float(level - 1) * 0.007)
	return maxf(MIN_GRAVITY_INTERVAL, pow(base, float(level - 1)))


## PPT send table:
## Single 0, Double 1, Triple 2, Tetris 4, T-Spin Single 2, T-Spin Double 4,
## T-Spin Triple 6, Mini T-Spin Single 0 / Double 1, Back-to-Back +1 (difficult
## clears only), combo bonus floor(combo_count / 2) capped at COMBO_SEND_CAP,
## where `combo_count` is the 1-based consecutive clear count of this event
## (1st clear +0, 2nd-3rd +1, 4th-5th +2, ...). Perfect Clear is a flat 10 and
## ignores every other term.
static func attack_for_event(lines: int, t_spin: int, b2b_active: bool, combo_count: int, perfect_clear: bool) -> int:
	if lines < 1:
		return 0
	if perfect_clear:
		return PERFECT_CLEAR_SEND
	var base: int = 0
	match t_spin:
		Scoring.TSpinKind.MINI:
			base = T_SPIN_MINI_SEND[mini(lines, 2)]
		Scoring.TSpinKind.FULL:
			base = [0, 2, 4, 6][mini(lines, 3)]
		_:
			base = [0, 0, 1, 2, 4][mini(lines, 4)]
	var send: int = base
	if Scoring.is_difficult(lines, t_spin) and b2b_active:
		send += 1
	# floor(combo_count / 2): the 1st consecutive clear adds 0.
	send += mini(combo_count / 2, COMBO_SEND_CAP)
	return send


# ---------------------------------------------------------------------------
# Input surface: nothing here reads Input, so tests and the scene feed the
# same model. `press` queues the same one-shot an Input.is_action_just_pressed
# would, `release` ends a hold, `tap` is a full press+release in one call.
func press(side: int, action: StringName) -> void:
	var s: SideState = _side_state(side)
	if not bool(s.held.get(action, false)):
		s.held[action] = true
		s.oneshot[action] = true


func release(side: int, action: StringName) -> void:
	_side_state(side).held[action] = false


func tap(side: int, action: StringName) -> void:
	_side_state(side).oneshot[action] = true


## Test/debug seam: places an exact piece for deterministic board fixtures.
## Production never calls this.
func debug_force_piece(side: int, type: int, rotation: int, pos: Vector2i, was_rotation: bool, kick_index: int) -> void:
	var s: SideState = _side_state(side)
	var piece: Tetromino = Tetromino.new(type)
	piece.rotation = rotation
	s.piece = piece
	s.piece_pos = pos
	s.piece_lowest_y = pos.y
	s.fall_timer = 0.0
	s.was_soft = false
	s.lock_timer = 0.0
	s.lock_resets = 0
	s.last_move_was_rotation = was_rotation
	s.last_kick_index = kick_index


## Test/debug seam: a frozen side is skipped by tick() (its piece never falls),
## so the other side can be measured without an opponent. Production never
## calls this.
func debug_freeze_side(side: int, frozen: bool) -> void:
	_side_state(side).frozen = frozen


## Test/debug seam: locks the current piece immediately through the regular
## lock/clear/send/garbage/spawn path (`hard` mirrors hard vs soft lock).
func debug_lock_now(side: int, hard: bool = true) -> void:
	var s: SideState = _side_state(side)
	if not _started or s.piece == null or s.lost or _phase != Phase.PLAYING:
		return
	_finish_lock(s, hard)


# ---------------------------------------------------------------------------
func _begin_round() -> void:
	_rounds_begun += 1
	_countdown = maxf(0.0, countdown_seconds)
	_phase = Phase.COUNTDOWN if _countdown > 0.0 else Phase.PLAYING
	_elapsed = 0.0
	_events.clear()
	_round_winner = -1
	_last_round_draw = false
	_sides.clear()
	_sides.append(SideState.new())
	_sides.append(SideState.new())
	for index: int in [Side.PLAYER, Side.AI]:
		var s: SideState = _side_state(index)
		s.index = index
		s.board = Board.new()
		s.level = _initial_level()
		# Same seed on both sides: identical piece sequences. The round
		# serial keeps later rounds of a match from replaying the first.
		s.bag_rng.seed = hash([_stored_seed, _rounds_begun, "bag"])
		_spawn(s)


func _initial_level() -> int:
	return _fixed_level if _rules == Rules.FIXED else 1


func _side_state(side: int) -> SideState:
	return _sides[side] as SideState


func _opponent(s: SideState) -> SideState:
	return _side_state(1 - s.index)


func _tick_side(side: int, delta: float) -> void:
	var s: SideState = _side_state(side)
	if s.lost or s.frozen:
		return
	_handle_horizontal(s, delta)
	_handle_rotation(s)
	_handle_hold(s)
	if s.piece == null or s.lost:
		return
	_handle_hard_drop(s)
	if s.piece == null or s.lost:
		return
	_handle_fall(s, delta)


func _handle_horizontal(s: SideState, delta: float) -> void:
	var dir: int = 0
	if bool(s.held.get(ACTION_MOVE_LEFT, false)):
		dir -= 1
	if bool(s.held.get(ACTION_MOVE_RIGHT, false)):
		dir += 1
	var queued_left: bool = bool(s.oneshot.get(ACTION_MOVE_LEFT, false))
	var queued_right: bool = bool(s.oneshot.get(ACTION_MOVE_RIGHT, false))
	if dir != 0:
		if dir != s.move_dir:
			s.move_dir = dir
			s.move_timer = 0.0
			if _try_move(s, Vector2i(dir, 0)):
				_apply_lock_reset(s)
		else:
			s.move_timer += delta
			if s.move_timer >= DAS_DELAY:
				s.move_timer -= ARR_RATE
				if _try_move(s, Vector2i(dir, 0)):
					_apply_lock_reset(s)
	elif queued_left:
		if _try_move(s, Vector2i(-1, 0)):
			_apply_lock_reset(s)
	elif queued_right:
		if _try_move(s, Vector2i(1, 0)):
			_apply_lock_reset(s)
	else:
		s.move_dir = 0
		s.move_timer = 0.0
	s.oneshot.erase(ACTION_MOVE_LEFT)
	s.oneshot.erase(ACTION_MOVE_RIGHT)


func _handle_rotation(s: SideState) -> void:
	var direction: int = 0
	if bool(s.oneshot.get(ACTION_ROTATE, false)):
		direction = 1
	elif bool(s.oneshot.get(ACTION_ROTATE_CCW, false)):
		direction = -1
	s.oneshot.erase(ACTION_ROTATE)
	s.oneshot.erase(ACTION_ROTATE_CCW)
	if direction == 0 or s.piece == null:
		return
	var result: Dictionary = SRS.try_rotate(s.board, s.piece, s.piece_pos, direction)
	if not bool(result["success"]):
		return
	s.piece.rotation = int(result["rotation"])
	s.piece_pos = result["pos"]
	s.last_move_was_rotation = true
	s.last_kick_index = int(result["kick_index"])
	_apply_lock_reset(s)


func _handle_hold(s: SideState) -> void:
	if not bool(s.oneshot.get(ACTION_HOLD, false)):
		return
	s.oneshot.erase(ACTION_HOLD)
	if s.piece == null or not s.can_hold:
		return
	s.move_dir = 0
	var current: int = s.piece.piece_type
	if s.hold_type == -1:
		s.hold_type = current
		_spawn(s)
	else:
		var swapped: int = s.hold_type
		s.hold_type = current
		_spawn_specific(s, swapped)
	s.can_hold = false
	_emit({"type": &"hold", "side": s.index})
	if s.lost:
		_emit({"type": &"lost", "side": s.index})


func _handle_hard_drop(s: SideState) -> void:
	if not bool(s.oneshot.get(ACTION_HARD_DROP, false)):
		return
	s.oneshot.erase(ACTION_HARD_DROP)
	if s.piece == null or s.lost:
		return
	var dist: int = 0
	while _try_move(s, Vector2i(0, 1)):
		dist += 1
	s.score += dist * HARD_DROP_SCORE
	_finish_lock(s, true, dist)


func _handle_fall(s: SideState, delta: float) -> void:
	if s.piece == null:
		return
	s.fall_timer += delta
	var soft: bool = bool(s.held.get(ACTION_SOFT_DROP, false))
	var interval: float = SOFT_DROP_INTERVAL if soft else gravity_interval(s.level)
	if soft != s.was_soft:
		s.fall_timer = minf(s.fall_timer, interval)
		s.was_soft = soft
	while s.fall_timer >= interval:
		s.fall_timer -= interval
		if _try_move(s, Vector2i(0, 1)):
			if soft:
				s.score += SOFT_DROP_SCORE
		else:
			break
	if s.piece == null:
		return
	if not s.board.can_place(s.piece.get_cells(), s.piece_pos + Vector2i(0, 1)):
		s.lock_timer += delta
		if s.lock_timer >= LOCK_DELAY:
			_finish_lock(s, false)
	else:
		s.lock_timer = 0.0


func _try_move(s: SideState, offset: Vector2i) -> bool:
	if s.piece == null:
		return false
	if s.board.can_place(s.piece.get_cells(), s.piece_pos + offset):
		s.piece_pos += offset
		s.last_move_was_rotation = false
		s.last_kick_index = -1
		if offset.y > 0:
			s.lock_timer = 0.0
			if s.piece_pos.y > s.piece_lowest_y:
				s.piece_lowest_y = s.piece_pos.y
				s.lock_resets = 0
		return true
	return false


func _apply_lock_reset(s: SideState) -> void:
	if s.piece == null:
		return
	if not s.board.can_place(s.piece.get_cells(), s.piece_pos + Vector2i(0, 1)) and s.lock_resets < MAX_LOCK_RESETS:
		s.lock_timer = 0.0
		s.lock_resets += 1


func _finish_lock(s: SideState, hard: bool, drop_distance: int = 0) -> void:
	var locked_all_hidden: bool = true
	var world_cells: Array[Vector2i] = []
	for local: Vector2i in s.piece.get_cells():
		world_cells.append(local + s.piece_pos)
		if local.y + s.piece_pos.y >= Board.HIDDEN_HEIGHT:
			locked_all_hidden = false
	s.pending_t_spin = Scoring.classify_t_spin(s.board, s.piece, s.piece_pos, s.last_move_was_rotation, s.last_kick_index)
	s.board.lock_cells(s.piece.get_cells(), s.piece_pos, s.piece.piece_type)
	_emit({
		"type": &"lock",
		"side": s.index,
		"cells": world_cells,
		"piece_type": int(s.piece.piece_type),
		"hard": hard,
		"drop_distance": drop_distance,
	})
	s.pieces_placed += 1
	s.piece = null
	s.move_dir = 0
	s.lock_timer = 0.0
	s.lock_resets = 0
	s.fall_timer = 0.0
	s.was_soft = false
	if locked_all_hidden:
		_lose(s)
		return
	var full: Array[int] = s.board.get_full_lines()
	if full.is_empty():
		if s.pending_t_spin != Scoring.TSpinKind.NONE:
			_award_no_clear(s)
		else:
			s.combo = 0
		s.pending_t_spin = Scoring.TSpinKind.NONE
		# Garbage only enters on a lock that cleared nothing.
		_insert_pending_garbage(s)
		if s.lost:
			return
	else:
		var row_cells: Array = []
		for row: int in full:
			var values: Array[int] = []
			for x: int in Board.BOARD_WIDTH:
				values.append(s.board.get_cell(Vector2i(x, row)))
			row_cells.append(values)
		var cleared: int = s.board.clear_lines()
		_award_clear(s, cleared, full, row_cells)
		s.pending_t_spin = Scoring.TSpinKind.NONE
	_spawn(s)
	if s.lost:
		_emit({"type": &"lost", "side": s.index})


func _lose(s: SideState) -> void:
	s.lost = true
	_emit({"type": &"lost", "side": s.index})


func _award_no_clear(s: SideState) -> void:
	# Only called when pending_t_spin != NONE (see _finish_lock): this lock
	# really consumed a T-Spin (MINI/FULL alike) without clearing (S3a).
	s.tspin_count += 1
	var result: Dictionary = Scoring.score_for_event(0, s.pending_t_spin, s.b2b_active, s.combo, s.level)
	s.score += int(result["points"])
	s.combo = 0
	_emit({"type": &"spin", "side": s.index, "t_spin": s.pending_t_spin})


func _award_clear(s: SideState, cleared: int, rows: Array[int], row_cells: Array) -> void:
	var spin: int = s.pending_t_spin
	# This lock really consumed a T-Spin (MINI/FULL alike) with its clear
	# (S3a counter; plain clears keep it at zero).
	if spin != Scoring.TSpinKind.NONE:
		s.tspin_count += 1
	if spin == Scoring.TSpinKind.FULL:
		s.tspin_clears[mini(cleared, 3)] += 1
	var combo_at_event: int = s.combo
	var b2b_before: bool = s.b2b_active
	var result: Dictionary = Scoring.score_for_event(cleared, spin, b2b_before, combo_at_event, s.level)
	s.score += int(result["points"])
	s.lines += cleared
	_apply_rising_level()
	var perfect_clear: bool = s.board.is_empty_board()
	# B2B +1 applies only when the chain was already active before this clear.
	var attack: int = attack_for_event(cleared, spin, b2b_before, combo_at_event + 1, perfect_clear)
	s.b2b_active = bool(result["difficult"])
	s.combo = combo_at_event + 1
	var cancelled: int = _send_attack(s, attack)
	_emit({
		"type": &"clear",
		"side": s.index,
		"rows": rows,
		"row_cells": row_cells,
		"lines": cleared,
		"t_spin": spin,
		"b2b": bool(result["b2b_applied"]),
		"combo": s.combo,
		"perfect_clear": perfect_clear,
		"attack": attack,
		"cancelled": cancelled,
		"sent": attack - cancelled,
	})


## Modern garbage rule (BD-08): the attack first cancels this side's own
## queued incoming garbage 1:1 in FIFO batch order; only the remainder is
## appended as a new batch on the opponent's queue, whose existing batches
## are never reduced. A fully cancelled attack appends nothing (semantic
## zero), and the full attack amount is still credited to attack_sent_rows.
## Returns the number of rows that were cancelled.
func _send_attack(s: SideState, amount: int) -> int:
	if amount <= 0:
		return 0
	var defender: SideState = _opponent(s)
	var remaining: int = amount
	while remaining > 0 and not s.pending_garbage.is_empty():
		var first: int = s.pending_garbage[0]
		var cancelled: int = mini(first, remaining)
		s.pending_garbage[0] = first - cancelled
		remaining -= cancelled
		if s.pending_garbage[0] <= 0:
			s.pending_garbage.pop_front()
	if remaining > 0:
		defender.pending_garbage.append(remaining)
	# S2 read surface: the sent amount is credited to the attacker after the
	# own-queue cancel/queue path above (cancelled rows are part of the attack).
	s.attack_sent_rows += amount
	return amount - remaining


func _insert_pending_garbage(s: SideState) -> void:
	if s.pending_garbage.is_empty():
		return
	var budget: int = GARBAGE_CAP_PER_LOCK
	var inserted: int = 0
	var overflowed: bool = false
	while budget > 0 and not s.pending_garbage.is_empty():
		var count: int = mini(s.pending_garbage[0], budget)
		var hole: int = _garbage_rng.randi_range(0, Board.BOARD_WIDTH - 1)
		var result: Dictionary = s.board.insert_garbage_rows(count, hole)
		budget -= count
		inserted += count
		s.pending_garbage[0] -= count
		if s.pending_garbage[0] <= 0:
			s.pending_garbage.pop_front()
		if bool(result["overflow"]):
			overflowed = true
			break
	_emit({"type": &"garbage", "side": s.index, "rows": inserted})
	# Only cells pushed out of the 24-row buffer lose here; a stack that merely
	# reaches the hidden rows keeps playing until its spawn is blocked.
	if overflowed:
		_lose(s)


func _spawn(s: SideState) -> void:
	# First spawn of a round starts from an empty queue: fill the 7-bag before
	# popping, then top the visible NEXT queue back up (same as scripts/main.gd).
	if s.next_queue.is_empty():
		_refill_queue(s)
	var next_type: int = s.next_queue.pop_front()
	_refill_queue(s)
	_spawn_specific(s, next_type)
	s.can_hold = true


func _spawn_specific(s: SideState, type: int) -> void:
	s.piece = Tetromino.new(type)
	s.piece_pos = Vector2i((Board.BOARD_WIDTH - Tetromino.MATRIX_SIZES[type]) / 2, Board.HIDDEN_HEIGHT - 2)
	s.piece_lowest_y = s.piece_pos.y
	s.fall_timer = 0.0
	s.was_soft = false
	s.lock_timer = 0.0
	s.lock_resets = 0
	s.last_move_was_rotation = false
	s.last_kick_index = -1
	if not s.board.can_place(s.piece.get_cells(), s.piece_pos):
		s.lost = true


func _refill_bag(s: SideState) -> void:
	var types: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	for i: int in range(types.size() - 1, 0, -1):
		var j: int = s.bag_rng.randi_range(0, i)
		var swap: int = types[i]
		types[i] = types[j]
		types[j] = swap
	s.bag.append_array(types)


func _refill_queue(s: SideState) -> void:
	while s.next_queue.size() < NEXT_COUNT:
		if s.bag.is_empty():
			_refill_bag(s)
		s.next_queue.append(s.bag.pop_front())


func _settle_round(player_lost: bool, ai_lost: bool) -> void:
	if player_lost and ai_lost:
		# Same-tick double top-out: the round is drawn, the score is kept and
		# the same round is replayed (round_index unchanged).
		_round_winner = -1
		_last_round_draw = true
		_phase = Phase.ROUND_OVER
		return
	var winner: int = Side.AI if player_lost else Side.PLAYER
	_round_winner = winner
	_last_round_draw = false
	_round_wins[winner] += 1
	if _match_format == MatchFormat.SINGLE or _round_wins[winner] >= 2:
		_match_winner = winner
		_phase = Phase.MATCH_OVER
	else:
		_phase = Phase.ROUND_OVER


class SideState:
	extends RefCounted

	var index: int = 0
	var board: Board
	var piece: Tetromino = null
	var piece_pos: Vector2i = Vector2i.ZERO
	var piece_lowest_y: int = 0
	var fall_timer: float = 0.0
	var was_soft: bool = false
	var lock_timer: float = 0.0
	var lock_resets: int = 0
	var score: int = 0
	var lines: int = 0
	var level: int = 1
	var bag: Array[int] = []
	var bag_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var pieces_placed: int = 0
	var next_queue: Array[int] = []
	var hold_type: int = -1
	var can_hold: bool = true
	var last_move_was_rotation: bool = false
	var last_kick_index: int = -1
	## 1-based consecutive clearing-lock count (0 when the last lock cleared
	## nothing).
	var combo: int = 0
	var b2b_active: bool = false
	var pending_t_spin: int = Scoring.TSpinKind.NONE
	## Queued garbage batches in insertion order; each entry is a row count.
	var pending_garbage: Array[int] = []
	## Total garbage rows sent with attacks this round (see attack_sent).
	var attack_sent_rows: int = 0
	## T-Spins consumed at this side's locks this round, MINI and FULL alike
	## (see tspins()). Resets with the per-round SideState.
	var tspin_count: int = 0
	## Full T-Spin clears by lines cleared (index 1 = Single .. 3 = Triple).
	var tspin_clears: Array[int] = [0, 0, 0, 0]
	var lost: bool = false
	var frozen: bool = false
	var move_dir: int = 0
	var move_timer: float = 0.0
	var held: Dictionary = {}
	var oneshot: Dictionary = {}
