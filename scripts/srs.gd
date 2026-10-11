class_name SRS
extends RefCounted

const KICKS_JLSTZ_Y_UP: Dictionary = {
	"0>R": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	"R>0": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
	"R>2": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
	"2>R": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	"2>L": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	"L>2": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	"L>0": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	"0>L": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
}

const KICKS_I_Y_UP: Dictionary = {
	"0>R": [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, -1), Vector2i(1, 2)],
	"R>0": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, 1), Vector2i(-1, -2)],
	"R>2": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, 2), Vector2i(2, -1)],
	"2>R": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-2, 1)],
	"2>L": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, 1), Vector2i(-1, -2)],
	"L>2": [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, -1), Vector2i(1, 2)],
	"L>0": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-2, 1)],
	"0>L": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, 2), Vector2i(2, -1)],
}


static func state_name(rotation: int) -> String:
	match rotation % 4:
		1:
			return "R"
		2:
			return "2"
		3:
			return "L"
	return "0"


static func transition_key(from_rotation: int, direction: int) -> String:
	var to_rotation: int = from_rotation + (1 if direction >= 0 else 3)
	return "%s>%s" % [state_name(from_rotation), state_name(to_rotation % 4)]


static func y_up_to_grid_down(offset_y_up: Vector2i) -> Vector2i:
	return Vector2i(offset_y_up.x, -offset_y_up.y)


static func get_grid_kicks(piece_type: int, from_rotation: int, direction: int) -> Array[Vector2i]:
	if piece_type == Tetromino.PieceType.O:
		return [Vector2i.ZERO]
	var key: String = transition_key(from_rotation, direction)
	var table: Array = KICKS_I_Y_UP[key] if piece_type == Tetromino.PieceType.I else KICKS_JLSTZ_Y_UP[key]
	var kicks: Array[Vector2i] = []
	for offset: Vector2i in table:
		kicks.append(y_up_to_grid_down(offset))
	return kicks


static func try_rotate(board: Board, piece: Tetromino, pos: Vector2i, direction: int) -> Dictionary:
	var to_rotation: int = (piece.rotation + (1 if direction >= 0 else 3)) % 4
	var probe: Tetromino = Tetromino.new(piece.piece_type)
	probe.rotation = to_rotation
	var rotated_cells: Array[Vector2i] = probe.get_cells()
	var kicks: Array[Vector2i] = get_grid_kicks(piece.piece_type, piece.rotation, direction)
	for kick_index: int in kicks.size():
		var candidate: Vector2i = pos + kicks[kick_index]
		if board.can_place(rotated_cells, candidate):
			return {"success": true, "pos": candidate, "kick_index": kick_index, "rotation": to_rotation}
	return {"success": false, "pos": pos, "kick_index": -1, "rotation": piece.rotation}
