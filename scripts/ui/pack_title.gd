class_name PackTitle
extends Control
## The game's animated title: the resource pack's "title" sprite sheet
## (ResourcePack.title()), played in place of the menu's text title. The
## intro frames run once, then the frames from `loop_from` on repeat.
##
## Added to the template's menu scenes from the outside (the PackRuntime
## autoload calls attach() when one appears), into the container of the text
## title, so it fades in with the template's own animation. A pack without a
## title leaves the text title as it is.

const NODE_NAME: String = "PackTitle"

var _title: Dictionary = {}
var _time: float = 0.0
var _glow: Control


## Puts the pack's title over the text title of `menu`. Does nothing when the
## pack has none, the menu has no title label, or it was done already.
static func attach(menu: Node) -> void:
	var label: Label = menu.find_child("TitleLabel", true, false) as Label
	var title: Dictionary = ResourcePack.title()
	if label == null or title.is_empty() or label.get_parent().has_node(NODE_NAME):
		return
	var shown: PackTitle = PackTitle.new()
	shown.name = NODE_NAME
	shown._title = title
	label.get_parent().add_child(shown)
	# The label keeps its place in the layout; only its text is not drawn.
	label.self_modulate.a = 0.0
	# The line under the title moves below the animation.
	var subtitle: MarginContainer = menu.find_child("SubTitleMargin", true, false) as MarginContainer
	if subtitle != null:
		var title_margin: MarginContainer = menu.find_child("TitleMargin", true, false) as MarginContainer
		var top: int = title_margin.get_theme_constant("margin_top") if title_margin != null else 0
		subtitle.add_theme_constant_override("margin_top", top + int(float((title["frame"] as Vector2i).y) * float(title["scale"])) - 4)


## The frame that is showing (tests).
func frame() -> int:
	return frame_at(_time)


## Frame at `time` seconds: the intro once, then the loop for ever.
func frame_at(time: float) -> int:
	var index: int = int(time * float(_title["fps"]))
	var frames: int = int(_title["frames"])
	if index < frames:
		return index
	var loop_from: int = int(_title["loop_from"])
	return loop_from + (index - loop_from) % (frames - loop_from)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# A second, added pass of the same frame for the pack's glow.
	if float(_title["glow"]) > 0.0:
		_glow = Control.new()
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var add: CanvasItemMaterial = CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add
		_glow.draw.connect(_draw_frame.bind(_glow, float(_title["glow"])))
		add_child(_glow)


func _process(delta: float) -> void:
	var before: int = frame()
	_time += delta
	if frame() != before:
		queue_redraw()
		if _glow != null:
			_glow.queue_redraw()


func _draw() -> void:
	_draw_frame(self, 1.0)


func _draw_frame(canvas: CanvasItem, alpha: float) -> void:
	var size_px: Vector2i = _title["frame"]
	var columns: int = int(_title["columns"])
	var index: int = frame()
	var shown: Vector2 = Vector2(size_px) * float(_title["scale"])
	canvas.draw_texture_rect_region(_title["texture"], Rect2(Vector2(roundf((size.x - shown.x) / 2.0), 0.0), shown),
		Rect2(Vector2(index % columns, index / columns) * Vector2(size_px), Vector2(size_px)), Color(1, 1, 1, alpha))
