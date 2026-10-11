class_name BlockSkin
extends RefCounted
## How one block (mino) is drawn. Every board, HOLD and NEXT preview goes
## through draw_cell(), so the look of the blocks belongs to the resource
## pack (scripts/resource_pack.gd), not to the scenes.
##
## pack.json "blocks" section, one of:
##   {"atlas": "blocks.png", "order": [...]}
##       one row of square tiles. `order` names what each tile is, left to
##       right; default: i o t s z j l garbage ghost. Tiles keep their own
##       colors. Reordering `order` adapts strips drawn for other games.
##   {"tile": "block.png"}
##       one (usually grey) tile, tinted with the pack's piece colors.
## Optional keys: "ghost_alpha" (0..1, default 0.35) and "filter" ("linear"
## or "nearest" - nearest keeps pixel art crisp).
## Without a usable section the blocks are drawn as flat bevelled tiles in the
## pack's piece colors.

const DEFAULT_ORDER: Array[String] = ["i", "o", "t", "s", "z", "j", "l", "garbage", "ghost"]
## Tile names of the board cell values 0..6 (Tetromino.PieceType order).
const PIECE_TILES: Array[String] = ["i", "o", "t", "s", "z", "j", "l"]
const GARBAGE_TILE: String = "garbage"
const GHOST_TILE: String = "ghost"
const DEFAULT_GHOST_ALPHA: float = 0.35

enum Mode { PLAIN, TILE, ATLAS }

static var _revision: int = -1
static var _mode: int = Mode.PLAIN
static var _texture: Texture2D
## Tile name -> source region in the atlas.
static var _regions: Dictionary = {}
static var _ghost_alpha: float = DEFAULT_GHOST_ALPHA
static var _nearest: bool = false


## Reads the block look again when the enabled packs changed.
static func _sync() -> void:
	if _revision == ResourcePack.revision() and _revision >= 0:
		return
	var section: Dictionary = ResourcePack.blocks()
	_revision = ResourcePack.revision()
	_mode = Mode.PLAIN
	_texture = null
	_regions = {}
	_ghost_alpha = clampf(float(section.get("ghost_alpha", DEFAULT_GHOST_ALPHA)), 0.05, 1.0)
	_nearest = String(section.get("filter", "linear")) == "nearest"
	var atlas: Texture2D = section.get("atlas_texture") as Texture2D
	if atlas != null:
		var order: Array = section.get("order", DEFAULT_ORDER)
		var side: float = float(atlas.get_height())
		for i: int in order.size():
			if side * float(i + 1) <= float(atlas.get_width()) + 0.5:
				_regions[String(order[i])] = Rect2(side * float(i), 0.0, side, side)
		if not _regions.is_empty():
			_mode = Mode.ATLAS
			_texture = atlas
			return
	var tile: Texture2D = section.get("tile_texture") as Texture2D
	if tile != null:
		_mode = Mode.TILE
		_texture = tile


## Mode.PLAIN / TILE / ATLAS of the enabled packs.
static func mode() -> int:
	_sync()
	return _mode


## Texture filter a canvas item drawing blocks should use.
static func texture_filter() -> int:
	_sync()
	return CanvasItem.TEXTURE_FILTER_NEAREST if _nearest else CanvasItem.TEXTURE_FILTER_LINEAR


static func _tile_name(value: int) -> String:
	if value >= 0 and value < PIECE_TILES.size():
		return PIECE_TILES[value]
	return GARBAGE_TILE


## Draws one block into `rect` of `canvas` (call from its _draw()). `value` is
## a board cell value: a piece type, or Board.GARBAGE. `ghost` draws the
## landing preview of that piece instead of a solid block.
static func draw_cell(canvas: CanvasItem, rect: Rect2, value: int, ghost: bool = false) -> void:
	_sync()
	var color: Color = ResourcePack.cell_color(value)
	match _mode:
		Mode.ATLAS:
			var tile_name: String = _tile_name(value)
			if ghost:
				if _regions.has(GHOST_TILE):
					# The ghost tile is neutral: it takes the piece's color.
					canvas.draw_texture_rect_region(_texture, rect, _regions[GHOST_TILE], Color(color, _ghost_alpha))
					return
				if _regions.has(tile_name):
					canvas.draw_texture_rect_region(_texture, rect, _regions[tile_name], Color(1, 1, 1, _ghost_alpha))
					return
			elif _regions.has(tile_name):
				canvas.draw_texture_rect_region(_texture, rect, _regions[tile_name])
				return
		Mode.TILE:
			canvas.draw_texture_rect(_texture, rect, false, Color(color, _ghost_alpha) if ghost else color)
			return
	_draw_plain(canvas, rect, color, ghost)


## The built-in look: a dark rim, the body and a glint line.
static func _draw_plain(canvas: CanvasItem, rect: Rect2, color: Color, ghost: bool) -> void:
	if ghost:
		canvas.draw_rect(rect, Color(color, _ghost_alpha * 0.65))
		return
	var size: float = rect.size.x
	var inset: float = maxf(1.0, size * 0.09)
	canvas.draw_rect(rect, color.darkened(0.45))
	canvas.draw_rect(rect.grow(-inset), color)
	canvas.draw_rect(Rect2(rect.position + Vector2(inset * 2.0, inset * 2.0), Vector2(size - inset * 4.0, maxf(2.0, size * 0.11))), color.lightened(0.35))
