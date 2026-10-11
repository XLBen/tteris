class_name Board
extends RefCounted

const BOARD_WIDTH: int = 10
const HIDDEN_HEIGHT: int = 4
const VISIBLE_HEIGHT: int = 20
const BOARD_HEIGHT: int = HIDDEN_HEIGHT + VISIBLE_HEIGHT
const EMPTY: int = -1
## Cell value used by versus garbage rows (distinct from every Tetromino id).
const GARBAGE: int = 7

var _cells: Array[int] = []


func _init() -> void:
	reset()


func reset() -> void:
	_cells.resize(BOARD_WIDTH * BOARD_HEIGHT)
	_cells.fill(EMPTY)


func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_WIDTH and pos.y >= 0 and pos.y < BOARD_HEIGHT


func get_cell(pos: Vector2i) -> int:
	return _cells[pos.y * BOARD_WIDTH + pos.x]


func set_cell(pos: Vector2i, value: int) -> void:
	_cells[pos.y * BOARD_WIDTH + pos.x] = value


func is_empty_at(pos: Vector2i) -> bool:
	return get_cell(pos) == EMPTY


func can_place(cells: Array[Vector2i], offset: Vector2i = Vector2i.ZERO) -> bool:
	for local: Vector2i in cells:
		var world: Vector2i = local + offset
		if not is_inside(world) or not is_empty_at(world):
			return false
	return true


func lock_cells(cells: Array[Vector2i], offset: Vector2i, color_id: int) -> void:
	for local: Vector2i in cells:
		var world: Vector2i = local + offset
		if is_inside(world):
			set_cell(world, color_id)


func is_line_full(row: int) -> bool:
	if row < 0 or row >= BOARD_HEIGHT:
		return false
	for x: int in BOARD_WIDTH:
		if is_empty_at(Vector2i(x, row)):
			return false
	return true


func get_full_lines() -> Array[int]:
	var lines: Array[int] = []
	for row: int in BOARD_HEIGHT:
		if is_line_full(row):
			lines.append(row)
	return lines


func clear_lines() -> int:
	var full: Array[int] = get_full_lines()
	for row: int in full:
		_clear_row(row)
	return full.size()


func _clear_row(row: int) -> void:
	for y: int in range(row, 0, -1):
		for x: int in BOARD_WIDTH:
			set_cell(Vector2i(x, y), get_cell(Vector2i(x, y - 1)))
	for x: int in BOARD_WIDTH:
		set_cell(Vector2i(x, 0), EMPTY)


func insert_garbage_rows(count: int, hole_column: int) -> Dictionary:
	# Versus garbage (BD-03): the whole stack moves up by `count` rows and the
	# bottom `count` rows become GARBAGE with a single empty hole column, so a
	# batch shares one hole. A cell pushed out of the board top (row < 0)
	# reports overflow; the caller treats that as a loss.
	var rows: int = clampi(count, 0, BOARD_HEIGHT)
	if rows == 0:
		return {"overflow": false}
	var overflow: bool = false
	for y: int in rows:
		for x: int in BOARD_WIDTH:
			if _cells[y * BOARD_WIDTH + x] != EMPTY:
				overflow = true
				break
		if overflow:
			break
	var shifted: Array[int] = []
	shifted.resize(BOARD_WIDTH * BOARD_HEIGHT)
	shifted.fill(EMPTY)
	for y: int in range(rows, BOARD_HEIGHT):
		for x: int in BOARD_WIDTH:
			shifted[(y - rows) * BOARD_WIDTH + x] = _cells[y * BOARD_WIDTH + x]
	var hole: int = clampi(hole_column, 0, BOARD_WIDTH - 1)
	for y: int in range(BOARD_HEIGHT - rows, BOARD_HEIGHT):
		for x: int in BOARD_WIDTH:
			if x != hole:
				shifted[y * BOARD_WIDTH + x] = GARBAGE
	_cells = shifted
	return {"overflow": overflow}


func highest_occupied_row() -> int:
	# Smallest y with an occupied cell; -1 when the board is empty.
	for y: int in BOARD_HEIGHT:
		for x: int in BOARD_WIDTH:
			if _cells[y * BOARD_WIDTH + x] != EMPTY:
				return y
	return -1


func lowest_occupied_row() -> int:
	# Largest y with an occupied cell; -1 when the board is empty.
	for y: int in range(BOARD_HEIGHT - 1, -1, -1):
		for x: int in BOARD_WIDTH:
			if _cells[y * BOARD_WIDTH + x] != EMPTY:
				return y
	return -1


func is_empty_board() -> bool:
	return highest_occupied_row() < 0
