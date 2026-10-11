class_name PackBackdrop
extends Control
## The animated background: the resource pack's "backdrop" sprite sheet
## (ResourcePack.backdrop()), one seamless loop, drawn unfiltered and scaled
## to cover the whole view (whole pixels of the sheet stay whole on screen
## when the view is a multiple of the frame). It sits where the still
## background image used to: behind the menus (scripts/pack_runtime.gd) and
## in the Background layer of the two game scenes. A pack without a backdrop
## leaves the still image in place.

var _backdrop: Dictionary = {}
var _time: float = 0.0


## A backdrop filling `parent`, or null when the pack has none.
static func add_to(parent: Node) -> PackBackdrop:
	var backdrop: Dictionary = ResourcePack.backdrop()
	if backdrop.is_empty():
		return null
	var shown: PackBackdrop = PackBackdrop.new()
	shown.name = "PackBackdrop"
	shown._backdrop = backdrop
	parent.add_child(shown)
	return shown


## The frame that is showing (tests).
func frame() -> int:
	return frame_at(_time)


func frame_at(time: float) -> int:
	return int(time * float(_backdrop["fps"])) % int(_backdrop["frames"])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var before: int = frame()
	_time += delta
	if frame() != before:
		queue_redraw()


func _draw() -> void:
	var size_px: Vector2i = _backdrop["frame"]
	var columns: int = int(_backdrop["columns"])
	var index: int = frame()
	# Cover the view, centered, keeping the frame's shape.
	var scale_up: float = maxf(size.x / float(size_px.x), size.y / float(size_px.y))
	var shown: Vector2 = Vector2(size_px) * scale_up
	draw_texture_rect_region(_backdrop["texture"], Rect2(((size - shown) / 2.0).round(), shown),
		Rect2(Vector2(index % columns, index / columns) * Vector2(size_px), Vector2(size_px)))
