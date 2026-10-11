class_name Tetromino
extends RefCounted

enum PieceType { I, O, T, S, Z, J, L }

const COLOR_I: Color = Color(0.2, 0.85, 0.95)
const COLOR_O: Color = Color(0.95, 0.8, 0.25)
const COLOR_T: Color = Color(0.75, 0.4, 0.95)
const COLOR_S: Color = Color(0.4, 0.9, 0.5)
const COLOR_Z: Color = Color(0.95, 0.45, 0.45)
const COLOR_J: Color = Color(0.35, 0.55, 0.95)
const COLOR_L: Color = Color(0.95, 0.62, 0.28)

const COLORS: Array[Color] = [COLOR_I, COLOR_O, COLOR_T, COLOR_S, COLOR_Z, COLOR_J, COLOR_L]

const SHAPE_I: Array[int] = [
	0, 0, 0, 0,
	1, 1, 1, 1,
	0, 0, 0, 0,
	0, 0, 0, 0,
]

const SHAPE_O: Array[int] = [
	1, 1,
	1, 1,
]

const SHAPE_T: Array[int] = [
	0, 1, 0,
	1, 1, 1,
	0, 0, 0,
]

const SHAPE_S: Array[int] = [
	0, 1, 1,
	1, 1, 0,
	0, 0, 0,
]

const SHAPE_Z: Array[int] = [
	1, 1, 0,
	0, 1, 1,
	0, 0, 0,
]

const SHAPE_J: Array[int] = [
	1, 0, 0,
	1, 1, 1,
	0, 0, 0,
]

const SHAPE_L: Array[int] = [
	0, 0, 1,
	1, 1, 1,
	0, 0, 0,
]

const SHAPES: Array = [SHAPE_I, SHAPE_O, SHAPE_T, SHAPE_S, SHAPE_Z, SHAPE_J, SHAPE_L]
const MATRIX_SIZES: Array[int] = [4, 2, 3, 3, 3, 3, 3]

var piece_type: PieceType = PieceType.I
var rotation: int = 0


func _init(piece_kind: PieceType = PieceType.T) -> void:
	piece_type = piece_kind


func rotate_cw() -> void:
	rotation = (rotation + 1) % 4


func rotate_ccw() -> void:
	rotation = (rotation + 3) % 4


func get_cells() -> Array[Vector2i]:
	var matrix: Array[int] = SHAPES[piece_type]
	var size: int = MATRIX_SIZES[piece_type]
	for i: int in rotation:
		matrix = rotate_matrix_cw(matrix, size)
	var cells: Array[Vector2i] = []
	for y: int in size:
		for x: int in size:
			if matrix[y * size + x] == 1:
				cells.append(Vector2i(x, y))
	return cells


func get_color() -> Color:
	return COLORS[piece_type]


static func rotate_matrix_cw(matrix: Array[int], size: int) -> Array[int]:
	var rotated: Array[int] = []
	rotated.resize(matrix.size())
	for y: int in size:
		for x: int in size:
			rotated[y * size + x] = matrix[(size - 1 - x) * size + y]
	return rotated


static var _base_cells_cache: Array = []


static func base_cells_for(kind: PieceType) -> Array[Vector2i]:
	while _base_cells_cache.size() <= kind:
		var empty: Array[Vector2i] = []
		_base_cells_cache.append(empty)
	var cached: Array[Vector2i] = _base_cells_cache[kind]
	if cached.is_empty():
		var matrix: Array[int] = SHAPES[kind]
		var size: int = MATRIX_SIZES[kind]
		var cells: Array[Vector2i] = []
		for y: int in size:
			for x: int in size:
				if matrix[y * size + x] == 1:
					cells.append(Vector2i(x, y))
		cached = cells
		_base_cells_cache[kind] = cached
	return cached
