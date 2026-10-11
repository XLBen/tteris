class_name BoardFX
extends Node2D
## Visual feedback for one 10x20 board, shared by the classic scene
## (scripts/main.gd) and both versus boards (scripts/versus.gd).
##
## The node sits at the board's top-left visible corner and draws everything
## procedurally in _draw(): line-clear sweeps with colored shards, lock
## flashes, hard-drop trails and sparks, call-out text, the garbage shove, the
## danger border and the K.O. wipe. Nothing here touches game state or timing:
## effects are fire-and-forget and the game never waits for one.
##
## The look belongs to the resource pack. Colors come from its "colors"
## (fx_* and callout_*), the amounts from its "fx" numbers, and a pack may
## give any event of ResourcePack.EFFECT_EVENTS a sprite-sheet animation in
## its "effects" section: it is played at the event - on top of the drawn
## effect, or instead of it when the entry says "replace".
##
## `offset` is the board displacement (shake + garbage shove) the owning scene
## applies to that board's nodes each frame. advance() is the whole update, so
## headless tests can step effects without a running tree.

const COLS: int = 10
const ROWS: int = 20

const SWEEP_GROW: float = 0.07
const SWEEP_FADE: float = 0.16
const LOCK_FLASH: float = 0.12
const TRAIL_FADE: float = 0.18
const POPUP_POP: float = 0.10
const POPUP_HOLD: float = 0.75
const POPUP_FADE: float = 0.30
const SHOVE_TIME: float = 0.16
const GARBAGE_FLASH: float = 0.28
const KO_TIME: float = 0.7
const SHAKE_DECAY: float = 14.0
const SHAKE_MAX: float = 14.0
const SHARD_GRAVITY: float = 900.0
const ORB_TIME: float = 0.32
## Cell size the "scale" of a pack's sprite effects is written for.
const SPRITE_CELL: float = 22.0

var cell: float = 22.0
var font: Font
## Board displacement for the owner to apply (see the header).
var offset: Vector2 = Vector2.ZERO

var _sweeps: Array[Dictionary] = []
var _flashes: Array[Dictionary] = []
var _trails: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _popup: Dictionary = {}
var _shake: float = 0.0
var _shove: float = 0.0
var _shove_time: float = 0.0
var _garbage_rows: int = 0
var _garbage_time: float = 0.0
var _danger: bool = false
var _danger_phase: float = 0.0
var _ko_time: float = -1.0
var _ko_text: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Playing sprite effects: {fx (ResourcePack.effect), pos, t}.
var _sprites: Array[Dictionary] = []
var _sprite_layer: SpriteLayer
var _glow_layer: SpriteLayer
## Where the last line clear happened (board pixels), for the T-spin effect.
var _clear_center: Vector2 = Vector2.ZERO
var _shake_scale: float = 1.0
var _shards_per_cell: int = 2
var _sparks_per_drop: int = 10


func setup(cell_size: float, text_font: Font) -> void:
	cell = cell_size
	font = text_font
	_shake_scale = ResourcePack.fx_number("shake", 1.0)
	_shards_per_cell = int(ResourcePack.fx_number("shards_per_cell", 2.0))
	_sparks_per_drop = int(ResourcePack.fx_number("sparks_per_drop", 10.0))
	if _sprite_layer == null:
		_sprite_layer = SpriteLayer.new(self, false)
		add_child(_sprite_layer)
		_glow_layer = SpriteLayer.new(self, true)
		add_child(_glow_layer)


## Draws the playing sprite effects over the board: once as they are, and
## once more added on top for the effects that ask for a glow.
class SpriteLayer:
	extends Node2D

	var _fx: BoardFX
	var _glow: bool

	func _init(fx: BoardFX, glow: bool) -> void:
		_fx = fx
		_glow = glow
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if glow:
			var add: CanvasItemMaterial = CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			material = add

	func _draw() -> void:
		for sprite: Dictionary in _fx._sprites:
			var fx: Dictionary = sprite["fx"]
			var glow: float = float(fx["glow"])
			if _glow and glow <= 0.0:
				continue
			var frame: int = mini(int(float(sprite["t"]) * float(fx["fps"])), int(fx["frames"]) - 1)
			var size: Vector2i = fx["frame"]
			var columns: int = int(fx["columns"])
			var shown: Vector2 = Vector2(size) * float(fx["scale"]) * _fx.cell / SPRITE_CELL
			var corner: Vector2 = (sprite["pos"] as Vector2) - Vector2(shown.x / 2.0, shown.y if bool(fx["bottom"]) else shown.y / 2.0)
			draw_texture_rect_region(fx["texture"], Rect2(corner.round(), shown),
				Rect2(Vector2(frame % columns, frame / columns) * Vector2(size), Vector2(size)),
				Color(1, 1, 1, glow) if _glow else Color.WHITE)


## Plays the pack's sprite effect of `event` at `at` (board pixels). Returns
## true when the pack wants it instead of the drawn effect.
func play_effect(event: String, at: Vector2) -> bool:
	var fx: Dictionary = ResourcePack.effect(event)
	if fx.is_empty():
		return false
	_sprites.append({"fx": fx, "pos": at, "t": 0.0})
	queue_redraw()
	return bool(fx["replace"])


## Sprite effects that are playing (tests).
func sprite_count() -> int:
	return _sprites.size()


func _process(delta: float) -> void:
	advance(delta)


## True while anything is still animating (tests and idle skipping).
func is_active() -> bool:
	return not _sweeps.is_empty() or not _flashes.is_empty() or not _trails.is_empty() \
		or not _particles.is_empty() or not _sprites.is_empty() or not _popup.is_empty() or _shake > 0.05 \
		or _shove_time > 0.0 or _garbage_time > 0.0 or _danger or _ko_time >= 0.0


func popup_text() -> String:
	return String(_popup.get("text", ""))


func popup_detail() -> String:
	return String(_popup.get("detail", ""))


func is_danger() -> bool:
	return _danger


func is_ko() -> bool:
	return _ko_time >= 0.0


## Clears every running effect (new round / restart).
func reset() -> void:
	_sweeps.clear()
	_flashes.clear()
	_trails.clear()
	_particles.clear()
	_sprites.clear()
	_popup = {}
	_shake = 0.0
	_shove_time = 0.0
	_garbage_time = 0.0
	_danger = false
	_ko_time = -1.0
	offset = Vector2.ZERO
	queue_redraw()


## `rows` are visible row indices (0 = top); `row_colors[i]` holds that row's
## ten cell colors before the clear.
func line_clear(rows: Array[int], row_colors: Array) -> void:
	var width: float = float(COLS) * cell
	var middle: float = 0.0
	for row: int in rows:
		middle += (float(row) + 0.5) * cell / float(maxi(1, rows.size()))
	_clear_center = Vector2(width / 2.0, middle)
	# Four rows are one event of their own when the pack has an effect for it.
	var whole: bool = rows.size() >= 4 and not ResourcePack.effect("tetris").is_empty()
	var replaced: bool = play_effect("tetris", _clear_center) if whole else false
	for i: int in rows.size():
		var row: int = rows[i]
		if row < 0 or row >= ROWS:
			continue
		if not whole:
			replaced = play_effect("line_clear", Vector2(width / 2.0, (float(row) + 0.5) * cell)) or replaced
		if replaced:
			continue
		_sweeps.append({"row": row, "t": 0.0})
		var colors: Array = row_colors[i] if i < row_colors.size() else []
		for col: int in COLS:
			var color: Color = colors[col] if col < colors.size() else Color.WHITE
			for n: int in _shards_per_cell:
				_particles.append({
					"pos": Vector2((float(col) + _rng.randf()) * cell, (float(row) + _rng.randf()) * cell),
					"vel": Vector2(_rng.randf_range(-140.0, 140.0), _rng.randf_range(-260.0, -40.0)),
					"color": color.lightened(0.25),
					"size": _rng.randf_range(0.14, 0.3) * cell,
					"t": 0.0,
					"life": _rng.randf_range(0.35, 0.6),
				})
	queue_redraw()


## The extra effect of a special clear, after line_clear(): a T-spin that
## cleared lines (at the cleared rows) and a perfect clear (the whole board).
## Only packs draw these; the built-in feedback is the call-out text.
func special_clear(t_spin: bool, perfect_clear: bool) -> void:
	if t_spin:
		play_effect("tspin", _clear_center)
	if perfect_clear:
		play_effect("perfect_clear", Vector2(float(COLS), float(ROWS)) * cell / 2.0)


## `cells` are visible cell coordinates of the piece that just locked.
func lock_flash(cells: Array[Vector2i]) -> void:
	var center: Vector2 = Vector2.ZERO
	for c: Vector2i in cells:
		center += (Vector2(c) + Vector2(0.5, 0.5)) * cell / float(cells.size())
	if not cells.is_empty() and play_effect("lock", center):
		return
	for c: Vector2i in cells:
		if c.y >= 0 and c.y < ROWS:
			_flashes.append({"cell": c, "t": 0.0})
	queue_redraw()


## Streak above a hard-dropped piece plus sparks at its feet.
func hard_drop(cells: Array[Vector2i], distance: int, color: Color) -> void:
	if distance <= 0:
		return
	var tops: Dictionary = {}
	var bottom: int = -1
	for c: Vector2i in cells:
		tops[c.x] = mini(int(tops.get(c.x, c.y)), c.y)
		bottom = maxi(bottom, c.y)
	var min_x: int = COLS
	var max_x: int = 0
	for col: int in tops:
		min_x = mini(min_x, col)
		max_x = maxi(max_x, col)
	shake(minf(1.0 + float(distance) * 0.12, 3.0))
	if play_effect("hard_drop", Vector2(float(min_x + max_x + 1) / 2.0, float(bottom + 1)) * cell):
		return
	for col: int in tops:
		_trails.append({
			"col": col,
			"top": maxi(0, int(tops[col]) - distance),
			"bottom": int(tops[col]),
			"color": color,
			"t": 0.0,
		})
	for n: int in _sparks_per_drop:
		_particles.append({
			"pos": Vector2(_rng.randf_range(float(min_x), float(max_x + 1)) * cell, float(bottom + 1) * cell),
			"vel": Vector2(_rng.randf_range(-170.0, 170.0), _rng.randf_range(-190.0, -60.0)),
			"color": color.lightened(0.5),
			"size": 0.12 * cell,
			"t": 0.0,
			"life": _rng.randf_range(0.18, 0.32),
		})
	queue_redraw()


## Call-out over the board: `text` (TETRIS, T-SPIN DOUBLE ...), a smaller
## `detail` line (B2B, COMBO x3, +4) and a color.
func popup(text: String, detail: String, color: Color) -> void:
	if text.is_empty() and detail.is_empty():
		return
	_popup = {"text": text, "detail": detail, "color": color, "t": 0.0}
	queue_redraw()


## Adds shake energy in pixels (decays on its own).
func shake(strength: float) -> void:
	_shake = minf(SHAKE_MAX, maxf(_shake, strength * _shake_scale))


## Garbage entered from below: shove the board up and flash the new rows.
func garbage_in(rows: int) -> void:
	if rows <= 0:
		return
	_shove = minf(float(rows) * 0.35, 1.5) * cell
	_shove_time = SHOVE_TIME
	_garbage_rows = mini(rows, ROWS)
	if not play_effect("garbage", Vector2(float(COLS) / 2.0, float(ROWS)) * cell):
		_garbage_time = GARBAGE_FLASH
	shake(2.0 + float(rows))
	queue_redraw()


func set_danger(active: bool) -> void:
	if active != _danger:
		_danger = active
		queue_redraw()


## Dark wipe rising over the lost board. `with_text` adds the "K.O." stamp;
## the classic scene turns it off because its own game-over panel follows.
func play_ko(with_text: bool = true) -> void:
	if _ko_time < 0.0:
		_ko_time = 0.0
		_ko_text = with_text
		play_effect("ko", Vector2(float(COLS), float(ROWS)) * cell / 2.0)
		shake(SHAKE_MAX)


func advance(delta: float) -> void:
	var animating: bool = is_active()
	_age(_sweeps, delta, SWEEP_GROW + SWEEP_FADE)
	_age(_flashes, delta, LOCK_FLASH)
	_age(_trails, delta, TRAIL_FADE)
	for i: int in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) >= float(p["life"]):
			_particles.remove_at(i)
			continue
		var vel: Vector2 = p["vel"]
		vel.y += SHARD_GRAVITY * delta
		p["vel"] = vel
		p["pos"] = (p["pos"] as Vector2) + vel * delta
	for i: int in range(_sprites.size() - 1, -1, -1):
		var sprite: Dictionary = _sprites[i]
		sprite["t"] = float(sprite["t"]) + delta
		if float(sprite["t"]) * float(sprite["fx"]["fps"]) >= float(sprite["fx"]["frames"]):
			_sprites.remove_at(i)
	if not _popup.is_empty():
		_popup["t"] = float(_popup["t"]) + delta
		if float(_popup["t"]) >= POPUP_POP + POPUP_HOLD + POPUP_FADE:
			_popup = {}
	_shake *= exp(-SHAKE_DECAY * delta)
	if _shake < 0.05:
		_shake = 0.0
	_shove_time = maxf(0.0, _shove_time - delta)
	_garbage_time = maxf(0.0, _garbage_time - delta)
	if _danger:
		_danger_phase = fmod(_danger_phase + delta * 2.2, 1.0)
	if _ko_time >= 0.0:
		_ko_time = minf(KO_TIME, _ko_time + delta)
	offset = Vector2.ZERO
	if _shake > 0.0:
		offset += Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake
	if _shove_time > 0.0:
		offset.y += _shove * (_shove_time / SHOVE_TIME)
	if animating:
		queue_redraw()
		if _sprite_layer != null:
			_sprite_layer.queue_redraw()
			_glow_layer.queue_redraw()


func _age(list: Array[Dictionary], delta: float, life: float) -> void:
	for i: int in range(list.size() - 1, -1, -1):
		list[i]["t"] = float(list[i]["t"]) + delta
		if float(list[i]["t"]) >= life:
			list.remove_at(i)


func _draw() -> void:
	var width: float = float(COLS) * cell
	var height: float = float(ROWS) * cell
	for trail: Dictionary in _trails:
		var fade: float = 1.0 - float(trail["t"]) / TRAIL_FADE
		var color: Color = trail["color"]
		var top: float = float(int(trail["top"])) * cell
		var bottom: float = float(int(trail["bottom"])) * cell
		var x: float = float(int(trail["col"])) * cell
		draw_polygon(
			PackedVector2Array([Vector2(x + 2.0, top), Vector2(x + cell - 2.0, top), Vector2(x + cell - 2.0, bottom), Vector2(x + 2.0, bottom)]),
			PackedColorArray([Color(color, 0.0), Color(color, 0.0), Color(color, 0.45 * fade), Color(color, 0.45 * fade)]))
	for flash: Dictionary in _flashes:
		var c: Vector2i = flash["cell"]
		var alpha: float = 0.6 * (1.0 - float(flash["t"]) / LOCK_FLASH)
		draw_rect(Rect2(Vector2(c) * cell, Vector2(cell, cell)), Color(ResourcePack.color("fx_flash"), alpha))
	if _garbage_time > 0.0:
		var g_alpha: float = 0.55 * (_garbage_time / GARBAGE_FLASH)
		var g_height: float = float(_garbage_rows) * cell
		draw_rect(Rect2(0.0, height - g_height, width, g_height), Color(ResourcePack.color("fx_garbage"), g_alpha))
	for sweep: Dictionary in _sweeps:
		var t: float = float(sweep["t"])
		var grow: float = minf(1.0, t / SWEEP_GROW)
		var fade: float = 1.0 - clampf((t - SWEEP_GROW) / SWEEP_FADE, 0.0, 1.0)
		var bar_w: float = width * grow
		var bar_h: float = cell * (0.25 + 0.75 * fade)
		var y: float = (float(int(sweep["row"])) + 0.5) * cell - bar_h / 2.0
		draw_rect(Rect2((width - bar_w) / 2.0, y, bar_w, bar_h), Color(ResourcePack.color("fx_flash"), 0.9 * fade))
	for p: Dictionary in _particles:
		var life: float = 1.0 - float(p["t"]) / float(p["life"])
		var size: float = float(p["size"]) * (0.4 + 0.6 * life)
		draw_rect(Rect2((p["pos"] as Vector2) - Vector2(size, size) / 2.0, Vector2(size, size)), Color(p["color"] as Color, life))
	if _danger:
		var danger_color: Color = ResourcePack.color("fx_danger")
		var pulse: float = 0.35 + 0.45 * (0.5 - 0.5 * cos(_danger_phase * TAU))
		draw_rect(Rect2(-2.0, -2.0, width + 4.0, height + 4.0), Color(danger_color, pulse), false, 3.0)
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(width, 0), Vector2(width, cell * 4.0), Vector2(0, cell * 4.0)]),
			PackedColorArray([Color(danger_color, 0.28 * pulse), Color(danger_color, 0.28 * pulse), Color(danger_color, 0.0), Color(danger_color, 0.0)]))
	if _ko_time >= 0.0:
		var rise: float = height * (_ko_time / KO_TIME)
		draw_rect(Rect2(0.0, height - rise, width, rise), ResourcePack.color("fx_ko_veil"))
		if _ko_text and font != null and _ko_time >= KO_TIME * 0.6:
			_draw_centered("K.O.", Vector2(width / 2.0, height * 0.45), int(cell * 1.6), ResourcePack.color("fx_ko_text"))
	if not _popup.is_empty() and font != null:
		var t: float = float(_popup["t"])
		var pop: float = 1.0 + 0.45 * (1.0 - minf(1.0, t / POPUP_POP))
		var alpha: float = 1.0 - clampf((t - POPUP_POP - POPUP_HOLD) / POPUP_FADE, 0.0, 1.0)
		var color: Color = Color(_popup["color"] as Color, alpha)
		var center: Vector2 = Vector2(width / 2.0, height * 0.3 - t * 18.0)
		var text: String = String(_popup["text"])
		var detail: String = String(_popup["detail"])
		if not text.is_empty():
			_draw_centered(text, center, int(cell * 0.95 * pop), color)
		if not detail.is_empty():
			_draw_centered(detail, center + Vector2(0.0, cell * 1.15), int(cell * 0.7), Color(1, 1, 1, alpha))


func _draw_centered(text: String, center: Vector2, size: int, color: Color) -> void:
	var extent: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	# Long call-outs (T-SPIN TRIPLE) shrink to stay inside the board.
	var max_width: float = float(COLS) * cell * 1.25
	if extent.x > max_width:
		size = maxi(8, int(float(size) * max_width / extent.x))
		extent = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos: Vector2 = center + Vector2(-extent.x / 2.0, extent.y / 4.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 5), Color(0.02, 0.03, 0.06, color.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Call-out wording shared by both modes. Returns [text, detail]; jargon stays
## English on every locale (community terms, like the rest of the HUD).
static func callout(lines: int, t_spin: int, b2b: bool, combo: int, perfect_clear: bool, sent: int = -1) -> Array[String]:
	var text: String = ""
	var words: Array[String] = ["", "SINGLE", "DOUBLE", "TRIPLE"]
	if perfect_clear:
		text = "PERFECT CLEAR"
	elif t_spin == Scoring.TSpinKind.FULL:
		text = "T-SPIN" if lines == 0 else "T-SPIN " + words[mini(lines, 3)]
	elif t_spin == Scoring.TSpinKind.MINI:
		text = "T-SPIN MINI" if lines == 0 else "T-SPIN MINI " + words[mini(lines, 3)]
	elif lines >= 4:
		text = "TETRIS"
	var parts: Array[String] = []
	if b2b:
		parts.append("B2B")
	if combo >= 2:
		parts.append("COMBO x%d" % combo)
	if sent > 0:
		parts.append("+%d" % sent)
	return [text, "  ".join(parts)]


## Color tier for a call-out: bigger events run warmer.
static func callout_color(lines: int, t_spin: int, perfect_clear: bool) -> Color:
	if perfect_clear:
		return ResourcePack.color("callout_perfect")
	if t_spin != Scoring.TSpinKind.NONE:
		return ResourcePack.color("callout_tspin")
	if lines >= 4:
		return ResourcePack.color("callout_tetris")
	return ResourcePack.color("callout_clear")


## A glowing dot that flies from `from` to `to` (parent-local coordinates) and
## frees itself; `arrived` runs when it lands.
static func spawn_orb(parent: Node, from: Vector2, to: Vector2, color: Color, texture: Texture2D, arrived: Callable = Callable()) -> void:
	if parent == null or not parent.is_inside_tree():
		if arrived.is_valid():
			arrived.call()
		return
	var orb: Sprite2D = Sprite2D.new()
	orb.texture = texture
	orb.modulate = color
	orb.position = from
	if texture != null:
		orb.scale = Vector2.ONE * (26.0 / maxf(1.0, float(texture.get_width())))
	orb.material = CanvasItemMaterial.new()
	(orb.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	parent.add_child(orb)
	var tween: Tween = orb.create_tween()
	tween.tween_property(orb, "position", to, ORB_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if arrived.is_valid():
		tween.tween_callback(arrived)
	tween.tween_callback(orb.queue_free)
