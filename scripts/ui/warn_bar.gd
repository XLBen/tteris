class_name WarnBar
extends Control
## Incoming-garbage meter beside a versus board: one segment per pending row,
## stacked from the bottom and aligned with the board's rows. The rows the
## next non-clearing lock will receive are bright, the rest dim; the count is
## written above the stack.

## Rows of garbage waiting to enter.
var pending: int = 0:
	set(value):
		if pending != value:
			pending = value
			queue_redraw()
## Height of one segment (the board's cell size).
var cell_size: float = 22.0:
	set(value):
		cell_size = value
		queue_redraw()
## Rows a single lock can receive.
var cap: int = 8
var font: Font
var rows: int = 20


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Text of the count above the meter ("" while nothing is pending).
func count_text() -> String:
	return str(pending) if pending > 0 else ""


func _draw() -> void:
	var shown: int = clampi(pending, 0, rows)
	var bottom: float = size.y
	for i: int in shown:
		var rect: Rect2 = Rect2(1.0, bottom - float(i + 1) * cell_size + 2.0, size.x - 2.0, cell_size - 4.0)
		draw_rect(rect, ResourcePack.color("warning") if i < cap else ResourcePack.color("warning_queued"))
	if pending > 0 and font != null:
		var text: String = count_text()
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var y: float = maxf(12.0, bottom - float(shown) * cell_size - 4.0)
		draw_string(font, Vector2((size.x - text_size.x) / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ResourcePack.color("warning"))
