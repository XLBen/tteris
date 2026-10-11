class_name BoardView
extends Node2D
## Draws one playfield: backdrop, grid, frame, the locked blocks, the falling
## piece and its ghost. One node and one _draw() per board; the blocks come
## from BlockSkin, the colors from the resource pack. The owner pushes plain
## data in with show_board() each frame; the node only redraws when that data
## (or the enabled packs) changed.

const FRAME_WIDTH: float = 2.0

## Side of one cell in pixels.
@export var cell_size: float = 24.0:
	set(value):
		cell_size = value
		queue_redraw()
## Gap left around each block so the grid shows through.
@export var block_inset: float = 1.0
@export var columns: int = 10
@export var rows: int = 20

## Visible cells, row-major, top row first (Board.EMPTY for nothing).
var _cells: PackedInt32Array = PackedInt32Array()
var _piece_cells: Array[Vector2i] = []
var _ghost_cells: Array[Vector2i] = []
var _piece_type: int = -1
var _pack_revision: int = -1


func _ready() -> void:
	texture_filter = BlockSkin.texture_filter() as CanvasItem.TextureFilter


## Pixel size of the playfield.
func board_size() -> Vector2:
	return Vector2(float(columns) * cell_size, float(rows) * cell_size)


## Shows `board`'s visible rows plus the falling piece. `piece_cells` and
## `ghost_cells` are in visible coordinates (row 0 = top visible row); cells
## above the field are skipped. Pass piece_type -1 for no falling piece.
func show_board(board: Board, piece_cells: Array[Vector2i] = [], piece_type: int = -1, ghost_cells: Array[Vector2i] = []) -> void:
	var cells: PackedInt32Array = PackedInt32Array()
	cells.resize(columns * rows)
	for y: int in rows:
		for x: int in columns:
			cells[y * columns + x] = board.get_cell(Vector2i(x, y + Board.HIDDEN_HEIGHT))
	var revision: int = ResourcePack.revision()
	if cells == _cells and piece_cells == _piece_cells and ghost_cells == _ghost_cells \
			and piece_type == _piece_type and revision == _pack_revision:
		return
	if revision != _pack_revision:
		texture_filter = BlockSkin.texture_filter() as CanvasItem.TextureFilter
	_cells = cells
	_piece_cells = piece_cells.duplicate()
	_ghost_cells = ghost_cells.duplicate()
	_piece_type = piece_type
	_pack_revision = revision
	queue_redraw()


## Cell value at a visible position (Board.EMPTY outside the data).
func cell_at(x: int, y: int) -> int:
	var index: int = y * columns + x
	return _cells[index] if x >= 0 and x < columns and y >= 0 and index < _cells.size() else Board.EMPTY


func piece_cells() -> Array[Vector2i]:
	return _piece_cells


func ghost_cells() -> Array[Vector2i]:
	return _ghost_cells


func _block_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * cell_size + Vector2(block_inset, block_inset), Vector2(cell_size - block_inset * 2.0, cell_size - block_inset * 2.0))


func _draw() -> void:
	var size: Vector2 = board_size()
	draw_rect(Rect2(Vector2.ZERO, size), ResourcePack.color("board_fill"))
	var grid: Color = ResourcePack.color("grid")
	for x: int in range(1, columns):
		draw_rect(Rect2(float(x) * cell_size, 0.0, 1.0, size.y), grid)
	for y: int in range(1, rows):
		draw_rect(Rect2(0.0, float(y) * cell_size, size.x, 1.0), grid)
	draw_rect(Rect2(Vector2.ZERO, size).grow(FRAME_WIDTH / 2.0), ResourcePack.color("board_border"), false, FRAME_WIDTH)
	for y: int in rows:
		for x: int in columns:
			var index: int = y * columns + x
			if index < _cells.size() and _cells[index] != Board.EMPTY:
				BlockSkin.draw_cell(self, _block_rect(Vector2i(x, y)), _cells[index])
	if _piece_type < 0:
		return
	for cell: Vector2i in _ghost_cells:
		if cell.y >= 0:
			BlockSkin.draw_cell(self, _block_rect(cell), _piece_type, true)
	for cell: Vector2i in _piece_cells:
		if cell.y >= 0:
			BlockSkin.draw_cell(self, _block_rect(cell), _piece_type)
