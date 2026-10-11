class_name PiecePreview
extends Control
## One tetromino drawn small and centered in this control (the HOLD slot and
## each NEXT slot). Blocks come from BlockSkin, so previews follow the
## resource pack exactly like the boards.

## Piece shown (Tetromino.PieceType value); -1 shows nothing.
@export_range(-1, 6) var piece_type: int = -1:
	set(value):
		if piece_type != value:
			piece_type = value
			queue_redraw()
## Side of one preview block in pixels.
@export var cell_size: float = 14.0:
	set(value):
		cell_size = value
		update_minimum_size()
		queue_redraw()
## Draws the piece dimmed (HOLD while the swap is used up).
@export var dimmed: bool = false:
	set(value):
		if dimmed != value:
			dimmed = value
			queue_redraw()

var _pack_revision: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	# Room for the widest (I, 4x1) and tallest (2 rows) spawn shapes.
	return Vector2(cell_size * 4.0, cell_size * 2.0)


func _process(_delta: float) -> void:
	# Follow a pack switch without the owner having to say so.
	if _pack_revision != ResourcePack.revision():
		_pack_revision = ResourcePack.revision()
		texture_filter = BlockSkin.texture_filter() as CanvasItem.TextureFilter
		queue_redraw()


func _draw() -> void:
	if piece_type < 0:
		return
	var cells: Array[Vector2i] = Tetromino.base_cells_for(piece_type)
	var low: Vector2i = Vector2i(99, 99)
	var high: Vector2i = Vector2i(-99, -99)
	for cell: Vector2i in cells:
		low = low.min(cell)
		high = high.max(cell)
	var extent: Vector2 = Vector2(high - low + Vector2i.ONE) * cell_size
	var origin: Vector2 = ((size - extent) / 2.0).floor()
	for cell: Vector2i in cells:
		var rect: Rect2 = Rect2(origin + Vector2(cell - low) * cell_size, Vector2(cell_size - 1.0, cell_size - 1.0))
		BlockSkin.draw_cell(self, rect, piece_type, dimmed)
