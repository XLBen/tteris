class_name Scoring
extends RefCounted

enum TSpinKind { NONE, MINI, FULL }

const NORMAL_LINE_POINTS: Array[int] = [0, 100, 300, 500, 800]
const T_SPIN_MINI_POINTS: Array[int] = [100, 200, 400]
const T_SPIN_POINTS: Array[int] = [400, 800, 1200, 1600]

## Classic level rule (owner decision 2026-10-10): one level per
## LINES_PER_LEVEL cleared lines on top of the starting level, capped at
## CLASSIC_MAX_LEVEL.
const LINES_PER_LEVEL: int = 10
const CLASSIC_MAX_LEVEL: int = 15
## Perfect Clear points by cleared line count (BQ-16): the single-player bonus
## is PERFECT_CLEAR_POINTS[cleared] * level (800/1200/1800/2000 per line count)
## and is added on top of the clear, B2B and combo score.
const PERFECT_CLEAR_POINTS: Array[int] = [0, 800, 1200, 1800, 2000]


static func is_difficult(lines: int, t_spin: int) -> bool:
	if lines >= 4:
		return true
	return t_spin != TSpinKind.NONE and lines >= 1


static func level_for_lines(lines: int, start_level: int = 1) -> int:
	return clampi(start_level + lines / LINES_PER_LEVEL, 1, CLASSIC_MAX_LEVEL)


static func perfect_clear_points(cleared: int, level: int) -> int:
	if cleared < 1 or cleared >= PERFECT_CLEAR_POINTS.size():
		return 0
	return PERFECT_CLEAR_POINTS[cleared] * level


static func score_for_event(lines: int, t_spin: int, b2b_active: bool, combo_index: int, level: int) -> Dictionary:
	var base: int = 0
	if t_spin == TSpinKind.MINI:
		base = T_SPIN_MINI_POINTS[mini(lines, 2)]
	elif t_spin == TSpinKind.FULL:
		base = T_SPIN_POINTS[mini(lines, 3)]
	else:
		base = NORMAL_LINE_POINTS[mini(lines, 4)]
	var points: int = base * level
	var b2b_applied: bool = is_difficult(lines, t_spin) and b2b_active
	if b2b_applied:
		points = int(round(points * 1.5))
	if lines >= 1:
		points += 50 * combo_index * level
	return {"points": points, "difficult": is_difficult(lines, t_spin), "b2b_applied": b2b_applied}


static func classify_t_spin(board: Board, piece: Tetromino, pos: Vector2i, last_move_was_rotation: bool, last_kick_index: int) -> int:
	if piece == null or piece.piece_type != Tetromino.PieceType.T or not last_move_was_rotation:
		return TSpinKind.NONE
	var center: Vector2i = pos + Vector2i(1, 1)
	var front: Array[Vector2i] = []
	var back: Array[Vector2i] = []
	match piece.rotation % 4:
		0:
			front = [center + Vector2i(-1, -1), center + Vector2i(1, -1)]
			back = [center + Vector2i(-1, 1), center + Vector2i(1, 1)]
		1:
			front = [center + Vector2i(1, -1), center + Vector2i(1, 1)]
			back = [center + Vector2i(-1, -1), center + Vector2i(-1, 1)]
		2:
			front = [center + Vector2i(-1, 1), center + Vector2i(1, 1)]
			back = [center + Vector2i(-1, -1), center + Vector2i(1, -1)]
		_:
			front = [center + Vector2i(-1, -1), center + Vector2i(-1, 1)]
			back = [center + Vector2i(1, -1), center + Vector2i(1, 1)]
	var front_filled: int = _count_filled(board, front)
	var back_filled: int = _count_filled(board, back)
	if front_filled + back_filled < 3:
		return TSpinKind.NONE
	# Guideline 3-corner rule: both front corners (the side the T points at)
	# filled is a full T-Spin; one front + both back is a Mini, unless the
	# rotation used the fifth SRS kick.
	if front_filled == 2 or last_kick_index == 4:
		return TSpinKind.FULL
	return TSpinKind.MINI


static func _count_filled(board: Board, corners: Array[Vector2i]) -> int:
	var count: int = 0
	for corner: Vector2i in corners:
		if not board.is_inside(corner) or not board.is_empty_at(corner):
			count += 1
	return count
