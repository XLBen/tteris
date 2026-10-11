extends Node2D

## Cell size of the stock layout's board slot (the real one is read from the
## layout: BoardView.cell_size).
const CELL_SIZE: int = 24
const GAME_AREA_WIDTH: float = 960.0
const DAS_DELAY: float = 0.17
const ARR_RATE: float = 0.05
const SOFT_DROP_INTERVAL: float = 0.05
const LOCK_DELAY: float = 0.5
const MAX_LOCK_RESETS: int = 15
const NEXT_COUNT: int = 5
## The stack is "in danger" once it reaches this many rows.
const DANGER_STACK_ROWS: int = 15
## Seconds the game-over buttons ignore input, so a hard drop mashed into the
## final lock cannot press one.
const RESULT_INPUT_DELAY: float = 0.6
const SOFT_DROP_SCORE: int = 1
const HARD_DROP_SCORE: int = 2
const FX_BG_LERP_RATE: float = 6.0

## Sound events of this scene. The files (and their volumes) come from the
## active resource pack (scripts/resource_pack.gd), never from this script.
const SFX_EVENTS: Array[String] = [
	"move", "rotate", "hold", "hard_drop", "lock", "clear", "tetris", "tspin",
	"tspin_mini", "tspin_double", "tspin_triple", "b2b",
	"perfect_clear", "combo", "level_up", "game_over", "pause", "resume",
]
## Each combo step raises the combo pluck by this much, up to the cap.
const COMBO_PITCH_STEP: float = 0.06
const COMBO_PITCH_MAX: float = 1.9
const PAUSE_MENU_SCENE: String = "res://scenes/windows/pause_menu.tscn"

var _board: Board
var _piece: Tetromino
var _piece_pos: Vector2i
var _piece_lowest_y: int = 0
var _fall_timer: float = 0.0
var _was_soft: bool = false
var _lock_timer: float = 0.0
var _lock_resets: int = 0
var _score: int = 0
var _lines: int = 0
var _level: int = 1
var _game_over: bool = false
var _paused: bool = false
var _move_dir: int = 0
var _move_timer: float = 0.0
var _bag: Array = []
var _next_queue: Array[Tetromino.PieceType] = []
var _hold_type: int = -1
var _can_hold: bool = true
var _last_move_was_rotation: bool = false
var _last_kick_index: int = -1
var _combo_index: int = 0
var _b2b_active: bool = false
var _pending_t_spin: int = Scoring.TSpinKind.NONE
var _last_feedback: String = ""
var _board_origin: Vector2 = Vector2.ZERO
var _view: Node2D
var _board_view: BoardView
## The "classic_hud" layout of the resource pack and what the scene reads
## from it (the aliases below keep the names the rest of the script uses).
var _hud: ClassicHud
var _result: ResultPanel
var _hold_preview: PiecePreview
var _next_previews: Array[PiecePreview] = []
var _pause_menu: PopupWindowPanel
var _game_over_veil: Control
var _game_over_score_label: Label
var _score_value: Label
var _lines_value: Label
var _level_value: Label
var _sfx: Dictionary = {}
var _background: TextureRect
var _bgm_player: AudioStreamPlayer
var _bgm_director: BgmDirector
var _font: Font
var _font_mini: Font
var _font_mono: Font
var _bg_base_modulate: Color = Color(0.35, 0.4, 0.55)
var _bg_tier: int = 0
var _hold_container: Control
var _next_container: Control
var _data_labels: Array[Rect2] = []
var _controls_label: Label
var _combo_value: Label
var _game_session = null
var _fx: BoardFX
var _b2b_label: Label
var _level_bar: Range
var _result_buttons: Control
var _retry_button: Button
var _result_delay: float = 0.0


func _ready() -> void:
	_game_session = _find_game_session()
	_board = Board.new()
	_view = Node2D.new()
	_view.name = "BoardView"
	add_child(_view)
	_font = ResourcePack.font("main")
	_font_mini = ResourcePack.font("mini")
	_font_mono = ResourcePack.font("mono")
	# S6 l10n (BF-11): the Localization autoload owns this wiring; calling it
	# here puts the Fusion Pixel CJK fallback on exactly the shared font
	# instances this scene just loaded, so zh HUD/game-over copy renders.
	if is_inside_tree():
		var localization: Node = get_tree().root.get_node_or_null(^"Localization")
		if localization != null and localization.has_method("ensure_cjk_fallbacks"):
			localization.ensure_cjk_fallbacks()
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var sfx_bus: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx_bus, "SFX")
		AudioServer.set_bus_send(sfx_bus, "Master")
	if AudioServer.get_bus_index("BGM") == -1:
		AudioServer.add_bus()
		var bgm_bus: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bgm_bus, "BGM")
		AudioServer.set_bus_send(bgm_bus, "Master")
		var compressor: AudioEffectCompressor = AudioEffectCompressor.new()
		compressor.sidechain = "SFX"
		AudioServer.add_bus_effect(bgm_bus, compressor)
	_load_sfx()
	_setup_background()
	_setup_bgm()
	_build_hud()
	_setup_fx()
	_build_result_panel()
	_build_pause_menu()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_hud)
	_restart()


func _process(delta: float) -> void:
	_tick_fx(delta)
	if _game_over:
		_tick_result_buttons(delta)
		if Input.is_action_just_pressed("restart"):
			_restart()
		_refresh_view()
		return
	# Esc while paused belongs to the menu: it closes its top window (and the
	# pause menu's own close resumes the game).
	if Input.is_action_just_pressed("pause") and not (_paused and Input.is_action_just_pressed("ui_cancel")):
		_set_paused(not _paused)
	if _paused:
		_refresh_view()
		return
	_handle_horizontal(delta)
	_handle_rotation()
	_handle_hold()
	if _piece == null:
		_refresh_view()
		return
	_handle_hard_drop()
	if _piece != null and not _game_over:
		_handle_fall(delta)
	_refresh_view()


func _restart() -> void:
	_board.reset()
	_score = 0
	_lines = 0
	_level = _mode_initial_level()
	_game_over = false
	_paused = false
	_hold_type = -1
	_can_hold = true
	_move_dir = 0
	_combo_index = 0
	_b2b_active = false
	_pending_t_spin = Scoring.TSpinKind.NONE
	_last_feedback = ""
	_bag.clear()
	_next_queue.clear()
	_refill_queue()
	_fx.reset()
	_result.visible = false
	_result_buttons.visible = false
	_spawn_piece()
	_update_bg_tier()


func _set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	_play_sfx("pause" if paused else "resume")


func _on_pause_menu_closed() -> void:
	# The pause menu closed itself (Resume button, ui_cancel or scene change);
	# the game resumes with the exact state it was paused in. Keys may have been
	# remapped in the options while paused.
	if _paused:
		_set_paused(false)
	_controls_label.text = _controls_line()


func _gravity_interval() -> float:
	var base: float = maxf(0.001, 0.8 - float(_level - 1) * 0.007)
	return maxf(VersusBattle.MIN_GRAVITY_INTERVAL, pow(base, float(_level - 1)))


func _find_game_session():
	# Autoload lookup is optional so the scene still works when it is
	# instantiated without a tree (tests) or without the autoload registered
	# (legacy behavior). is_inside_tree() is checked first because get_tree()
	# itself reports an engine error when the node is detached.
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null(^"GameSession")


func _mode_initial_level() -> int:
	if _game_session == null:
		return 1
	return int(_game_session.initial_level())


func _check_level_up() -> void:
	# Classic level rule: one level per Scoring.LINES_PER_LEVEL cleared lines on
	# top of the starting level; it never goes down and is capped at
	# CLASSIC_MAX_LEVEL.
	var new_level: int = Scoring.level_for_lines(_lines, _mode_initial_level())
	if new_level <= _level:
		return
	_level = new_level
	_play_sfx("level_up")
	# Shares the call-out with the clear that caused it.
	var detail: String = (_fx.popup_detail() + "  LEVEL UP").strip_edges()
	_fx.popup(_fx.popup_text(), detail, ResourcePack.color("highlight"))
	_update_bg_tier()


func _board_is_clear() -> bool:
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if not _board.is_empty_at(Vector2i(x, y)):
				return false
	return true


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT and not _game_over and not _paused:
		_set_paused(true)


func _handle_horizontal(delta: float) -> void:
	var dir: int = 0
	if Input.is_action_pressed("move_left"):
		dir -= 1
	if Input.is_action_pressed("move_right"):
		dir += 1
	if dir != _move_dir:
		_move_dir = dir
		_move_timer = 0.0
		if dir != 0 and _try_move_piece(Vector2i(dir, 0)):
			_play_sfx("move")
			_apply_lock_reset()
		return
	if dir != 0:
		_move_timer += delta
		if _move_timer >= DAS_DELAY:
			_move_timer -= ARR_RATE
			if _try_move_piece(Vector2i(dir, 0)):
				_play_sfx("move")
				_apply_lock_reset()


func _handle_rotation() -> void:
	if _piece == null:
		return
	var direction: int = 0
	if Input.is_action_just_pressed("rotate"):
		direction = 1
	elif Input.is_action_just_pressed("rotate_ccw"):
		direction = -1
	if direction == 0:
		return
	var result: Dictionary = SRS.try_rotate(_board, _piece, _piece_pos, direction)
	if not result["success"]:
		return
	_piece.rotation = result["rotation"]
	_piece_pos = result["pos"]
	_last_move_was_rotation = true
	_last_kick_index = result["kick_index"]
	_play_sfx("rotate")
	_apply_lock_reset()


func _handle_hold() -> void:
	if not Input.is_action_just_pressed("hold"):
		return
	if _piece == null or not _can_hold:
		return
	_play_sfx("hold")
	_move_dir = 0
	var current: int = _piece.piece_type
	if _hold_type == -1:
		_hold_type = current
		_spawn_piece()
	else:
		var swapped: int = _hold_type
		_hold_type = current
		_spawn_specific(swapped)
	_can_hold = false


func _handle_fall(delta: float) -> void:
	if _piece == null:
		return
	_fall_timer += delta
	var soft: bool = Input.is_action_pressed("soft_drop")
	# Past level 10 gravity outruns the soft drop; holding it never slows a piece.
	var interval: float = minf(SOFT_DROP_INTERVAL, _gravity_interval()) if soft else _gravity_interval()
	if soft != _was_soft:
		_fall_timer = minf(_fall_timer, interval)
		_was_soft = soft
	while _fall_timer >= interval:
		_fall_timer -= interval
		if _try_move_piece(Vector2i(0, 1)):
			if soft:
				_score += SOFT_DROP_SCORE
				_check_level_up()
		else:
			break
	if not _board.can_place(_piece.get_cells(), _piece_pos + Vector2i(0, 1)):
		_lock_timer += delta
		if _lock_timer >= LOCK_DELAY:
			_lock_piece(false)
	else:
		_lock_timer = 0.0


func _handle_hard_drop() -> void:
	if _piece == null or _game_over:
		return
	if Input.is_action_just_pressed("hard_drop"):
		var dist: int = 0
		while _try_move_piece(Vector2i(0, 1)):
			dist += 1
		_score += dist * HARD_DROP_SCORE
		_check_level_up()
		_play_sfx("hard_drop")
		_fx.hard_drop(_visible_piece_cells(), dist, ResourcePack.cell_color(_piece.piece_type))
		_lock_piece(true)


func _try_move_piece(offset: Vector2i) -> bool:
	if _board.can_place(_piece.get_cells(), _piece_pos + offset):
		_piece_pos += offset
		_last_move_was_rotation = false
		_last_kick_index = -1
		if offset.y > 0:
			_lock_timer = 0.0
			if _piece_pos.y > _piece_lowest_y:
				_piece_lowest_y = _piece_pos.y
				_lock_resets = 0
		return true
	return false


func _apply_lock_reset() -> void:
	if _piece == null:
		return
	if not _board.can_place(_piece.get_cells(), _piece_pos + Vector2i(0, 1)) and _lock_resets < MAX_LOCK_RESETS:
		_lock_timer = 0.0
		_lock_resets += 1


func _lock_piece(hard: bool) -> void:
	if not hard:
		_play_sfx("lock")
	_fx.lock_flash(_visible_piece_cells())
	var locked_all_hidden: bool = true
	for local: Vector2i in _piece.get_cells():
		if local.y + _piece_pos.y >= Board.HIDDEN_HEIGHT:
			locked_all_hidden = false
			break
	_pending_t_spin = Scoring.classify_t_spin(_board, _piece, _piece_pos, _last_move_was_rotation, _last_kick_index)
	_board.lock_cells(_piece.get_cells(), _piece_pos, _piece.piece_type)
	_piece = null
	_move_dir = 0
	_lock_timer = 0.0
	_lock_resets = 0
	if locked_all_hidden:
		_trigger_game_over()
		return
	var full: Array[int] = _board.get_full_lines()
	if full.is_empty():
		if _pending_t_spin != Scoring.TSpinKind.NONE:
			_play_sfx(BoardFX.clear_sound(0, _pending_t_spin, false))
			_award_score(0)
		else:
			_combo_index = 0
	else:
		_clear_lines(full)
	_spawn_piece()
	_update_bg_tier()


## Settles a clearing lock at once; the sweep and shards play over the already
## collapsed board, so the next piece is never held back.
func _clear_lines(full: Array[int]) -> void:
	var rows: Array[int] = []
	var colors: Array = []
	for row: int in full:
		rows.append(row - Board.HIDDEN_HEIGHT)
		var row_colors: Array[Color] = []
		for x: int in Board.BOARD_WIDTH:
			row_colors.append(ResourcePack.cell_color(_board.get_cell(Vector2i(x, row))))
		colors.append(row_colors)
	_fx.line_clear(rows, colors)
	var cleared: int = _board.clear_lines()
	_lines += cleared
	_fx.shake(1.5 * float(cleared))
	_award_score(cleared)


func _visible_piece_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for local: Vector2i in _piece.get_cells():
		cells.append(local + _piece_pos - Vector2i(0, Board.HIDDEN_HEIGHT))
	return cells


func _trigger_game_over() -> void:
	_game_over = true
	_play_sfx("game_over")
	_fx.play_ko(false)
	# Rewritten after the fact, so auto-translate cannot cover it: format the
	# translated template explicitly.
	_result.show_result(tr("GAME OVER"), ResourcePack.color("bad"), tr("SCORE %d") % _score)
	_result_delay = RESULT_INPUT_DELAY
	for button: Button in _result_buttons.get_children():
		button.disabled = true
	_result_buttons.visible = true


func _tick_result_buttons(delta: float) -> void:
	if _result_delay <= 0.0:
		return
	_result_delay -= delta
	if _result_delay <= 0.0:
		for button: Button in _result_buttons.get_children():
			button.disabled = false
		if _retry_button.is_inside_tree():
			_retry_button.grab_focus()


## The enabled packs changed from the pause menu: the scene is rebuilt so
## layouts, sounds and colors all come from the new set.
func _on_packs_changed() -> void:
	get_tree().reload_current_scene()


func _return_to_main_menu() -> void:
	var main_menu_path: String = MaaacksGameTemplate.get_main_menu_path()
	if main_menu_path.is_empty():
		return
	var scene_loader: Node = get_tree().root.get_node_or_null(^"SceneLoader")
	if scene_loader != null:
		scene_loader.load_scene(main_menu_path)
	else:
		get_tree().change_scene_to_file(main_menu_path)


func _spawn_piece() -> void:
	var next_type: Tetromino.PieceType = _next_queue.pop_front()
	_refill_queue()
	_spawn_specific(next_type)
	_can_hold = true


func _spawn_specific(type: Tetromino.PieceType) -> void:
	_piece = Tetromino.new(type)
	_piece_pos = Vector2i((Board.BOARD_WIDTH - Tetromino.MATRIX_SIZES[type]) / 2, Board.HIDDEN_HEIGHT - 2)
	_piece_lowest_y = _piece_pos.y
	_fall_timer = 0.0
	_was_soft = false
	_lock_timer = 0.0
	_lock_resets = 0
	_last_move_was_rotation = false
	_last_kick_index = -1
	if not _board.can_place(_piece.get_cells(), _piece_pos):
		_trigger_game_over()


func _refill_bag() -> void:
	var types: Array = Tetromino.PieceType.values()
	types.shuffle()
	for t in types:
		_bag.append(t)


func _refill_queue() -> void:
	while _next_queue.size() < NEXT_COUNT:
		if _bag.is_empty():
			_refill_bag()
		_next_queue.append(_bag.pop_front())


func _get_ghost_pos() -> Vector2i:
	var pos: Vector2i = _piece_pos
	while _board.can_place(_piece.get_cells(), pos + Vector2i(0, 1)):
		pos += Vector2i(0, 1)
	return pos


func _award_score(lines: int) -> void:
	var combo_at_event: int = _combo_index
	var result: Dictionary = Scoring.score_for_event(lines, _pending_t_spin, _b2b_active, combo_at_event, _level)
	_score += int(result["points"])
	# Perfect Clear (BD-11/BQ-16): the clear flow left no occupied cell on the
	# board, so the PC bonus is added on top of the clear/B2B/combo score at
	# the level that scored this event.
	var perfect_clear: bool = lines >= 1 and _board_is_clear()
	if perfect_clear:
		_score += Scoring.perfect_clear_points(lines, _level)
	if lines >= 1:
		_b2b_active = bool(result["difficult"])
		_combo_index += 1
	else:
		_combo_index = 0
	if lines >= 1:
		_play_clear_sfx(lines, _pending_t_spin, perfect_clear, combo_at_event, bool(result["b2b_applied"]))
	_last_feedback = _feedback_text(lines, result, combo_at_event, perfect_clear)
	if not _last_feedback.is_empty():
		var words: Array[String] = BoardFX.callout(lines, _pending_t_spin, bool(result["b2b_applied"]), combo_at_event + 1 if lines >= 1 else 0, perfect_clear)
		_fx.popup(words[0], words[1], BoardFX.callout_color(lines, _pending_t_spin, perfect_clear))
		_fx.special_clear(lines >= 1 and _pending_t_spin != Scoring.TSpinKind.NONE, perfect_clear)
	_check_level_up()
	_update_bg_tier()


## One main sound per clear (BoardFX.clear_sound: every special clear has its
## own), the Back-to-Back stinger on top when the chain pays, plus a combo
## pluck that climbs in pitch while the combo runs.
func _play_clear_sfx(lines: int, t_spin: int, perfect_clear: bool, combo_before: int, b2b: bool) -> void:
	var sound: String = BoardFX.clear_sound(lines, t_spin, perfect_clear)
	_play_sfx(sound, 1.0 + 0.08 * float(lines - 1) if sound == "clear" else 1.0)
	if b2b:
		_play_sfx("b2b")
	if combo_before >= 1:
		_play_sfx("combo", minf(COMBO_PITCH_MAX, 1.0 + COMBO_PITCH_STEP * float(combo_before)))


func _feedback_text(lines: int, result: Dictionary, combo_at_event: int, perfect_clear: bool) -> String:
	# Clear-feedback jargon stays English on every locale (BD-12-style
	# exemption, OD-recorded): TETRIS/T-SPIN/B2B/SINGLE/DOUBLE/TRIPLE are
	# Tetris-community terms, and keeping them literal keeps the frozen
	# play-flow assertions locale-independent.
	var parts: Array[String] = []
	if perfect_clear:
		parts.append("PERFECT CLEAR")
	if bool(result["b2b_applied"]):
		parts.append("B2B")
	if _pending_t_spin == Scoring.TSpinKind.MINI:
		parts.append("T-SPIN MINI" if lines == 0 else "T-SPIN MINI " + _line_word(lines))
	elif _pending_t_spin == Scoring.TSpinKind.FULL:
		parts.append("T-SPIN" if lines == 0 else "T-SPIN " + _line_word(lines))
	elif lines >= 4:
		parts.append("TETRIS")
	if lines >= 1 and combo_at_event >= 1:
		parts.append("COMBO x%d" % (combo_at_event + 1))
	return " ".join(parts)


func _line_word(lines: int) -> String:
	match lines:
		1:
			return "SINGLE"
		2:
			return "DOUBLE"
		3:
			return "TRIPLE"
	return "TETRIS"


func _load_sfx() -> void:
	_sfx = ResourcePack.make_sfx_players(self, SFX_EVENTS)


func _play_sfx(name: String, pitch: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var player: AudioStreamPlayer = _sfx.get(name) as AudioStreamPlayer
	if player != null and player.stream != null:
		player.pitch_scale = pitch
		player.play()


func _setup_fx() -> void:
	# Added after the board blocks so effects draw over them.
	_fx = BoardFX.new()
	_fx.name = "FX"
	_fx.position = _board_origin
	_fx.setup(_board_view.cell_size, _font)
	_view.add_child(_fx)


func _tick_fx(delta: float) -> void:
	if not is_inside_tree():
		return
	_view.position = _fx.offset
	if _background != null:
		var target: Color = _bg_tier_target_color(_bg_tier)
		_background.modulate = _background.modulate.lerp(target, minf(1.0, delta * FX_BG_LERP_RATE))


func _update_bg_tier() -> void:
	# Background intensity tiers are decoupled from the BGM (single looping
	# track since 2026-09-16): the tier follows game intensity — level plus
	# lines cleared — and falls back to the base tier as intensity drops.
	var intensity: float = float(_level - 1) / 4.0 + float(_lines) / 40.0
	_bg_tier = clampi(int(intensity), 0, 3)


func _bg_tier_target_color(tier: int) -> Color:
	var level: int = clampi(tier, 0, 3)
	var tinted: Color = _bg_base_modulate
	tinted.h = fposmod(tinted.h + 0.02 * float(level), 1.0)
	var bright: float = 1.0 + 0.08 * float(level)
	var base_lum: float = maxf(_bg_base_modulate.get_luminance(), 0.001)
	var lum_ratio: float = base_lum / maxf(tinted.get_luminance(), 0.001)
	return Color(tinted.r * lum_ratio * bright, tinted.g * lum_ratio * bright, tinted.b * lum_ratio * bright, tinted.a)


func _setup_background() -> void:
	_background = TextureRect.new()
	_background.texture = ResourcePack.texture("background")
	_background.stretch_mode = TextureRect.StretchMode.STRETCH_KEEP_ASPECT_COVERED
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_base_modulate = ResourcePack.color("background_tint")
	_background.modulate = _bg_base_modulate
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	($Background as CanvasLayer).add_child(_background)
	# The scene's flat fills take the pack colors too.
	var base: ColorRect = get_node_or_null(^"Background/BackgroundColor") as ColorRect
	if base != null:
		base.color = ResourcePack.color("background_base")
	var area_fill: Polygon2D = get_node_or_null(^"GameArea/AreaFill") as Polygon2D
	if area_fill != null:
		area_fill.color = ResourcePack.color("area_fill")
	var area_border: Line2D = get_node_or_null(^"GameArea/AreaBorder") as Line2D
	if area_border != null:
		area_border.default_color = ResourcePack.color("area_border")


func _setup_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	var track: AudioStream = ResourcePack.music("game")
	if track != null:
		# Every stream type the packs support loops through this property.
		if "loop" in track:
			track.set("loop", true)
		_bgm_player.stream = track
	_bgm_player.bus = "BGM"
	_bgm_player.volume_db = ResourcePack.music_volume("game")
	add_child(_bgm_player)
	# play() reports "Playback can only happen when a node is inside the
	# scene tree" when the scene is detached (tests call _ready() directly);
	# the real startup path is already in-tree here, so BGM still plays.
	if _bgm_player.is_inside_tree():
		_bgm_player.play()
	# The faster versions and the walk between them (see BgmDirector).
	_bgm_director = BgmDirector.new()
	add_child(_bgm_director)
	_bgm_director.setup(_bgm_player)


## Game-over panel: the pack's "result_panel" layout on its own layer above
## the board, with the two choices as real focusable buttons.
func _build_result_panel() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ResultLayer"
	add_child(layer)
	_result = ResourcePack.layout("result_panel").instantiate() as ResultPanel
	layer.add_child(_result)
	_result.bind()
	HudLayout.fill_viewport(_result)
	_game_over_veil = _result
	_game_over_score_label = _result.detail
	_result_buttons = _result.buttons
	_result_buttons.name = "ResultButtons"
	_retry_button = _result.add_button("Retry", _restart)
	_result.add_button("Main Menu", _return_to_main_menu)


func _build_pause_menu() -> void:
	# In-game pause (O-08): the Maaack template pause menu (copied verbatim to
	# scenes/windows/, one recorded pauses_game adaptation). Freezing stays on
	# the _paused flag (BS-07); _refresh_view syncs the menu visibility and the
	# template's own visibility handling opens/closes the window. The window is
	# hosted in a dedicated canvas layer above the board with the template's
	# popup-parent reparenting disabled (parent_scene = null): that subsystem
	# re-parents the window through its own open/close coroutines and races
	# the per-frame visibility sync, closing the menu one frame after it
	# opens. Buttons, confirmations and options nesting are unchanged.
	var packed: PackedScene = load(PAUSE_MENU_SCENE) as PackedScene
	if packed == null:
		return
	_pause_menu = packed.instantiate() as PopupWindowPanel
	if _pause_menu == null:
		return
	_pause_menu.parent_scene = null
	_pause_menu.visible = false
	var pause_layer: CanvasLayer = CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	add_child(pause_layer)
	pause_layer.add_child(_pause_menu)
	HowToPlay.attach_to_pause_menu(_pause_menu)
	PackSelect.attach_to_pause_menu(_pause_menu, _on_packs_changed)
	# S6 l10n (BD-15): the confirmation body is a RichTextLabel, which is not
	# covered by Control auto-translate, so the questions are translated
	# explicitly (no-op under English). Assigning after add_child so the
	# template's _ready re-application of its exported text has already run;
	# pause_menu.tscn keeps its English literals untouched (BC-06). Titles
	# and buttons are Labels and render through auto-translate.
	for confirmation_name: String in ["RestartConfirmation", "MainMenuConfirmation", "ExitConfirmation"]:
		var confirmation: WindowPanel = _pause_menu.get_node_or_null(NodePath(confirmation_name)) as WindowPanel
		if confirmation != null:
			confirmation.text = tr(confirmation.text)
	_pause_menu.closed.connect(_on_pause_menu_closed)


## HUD: the resource pack's "classic_hud" layout. The scene decides where
## everything sits; this script places the board into the layout's BoardSlot
## and feeds the readouts.
func _build_hud() -> void:
	_hud = ResourcePack.layout("classic_hud").instantiate() as ClassicHud
	_view.add_child(_hud)
	_hud.bind()
	_hold_preview = _hud.hold_preview
	_next_previews = _hud.next_previews
	_hold_container = _hud.hold_preview
	_next_container = _hud.get_node(^"%NextPreviews") as Control
	_score_value = _hud.score_value
	_level_value = _hud.level_value
	_lines_value = _hud.lines_value
	_combo_value = _hud.combo_value
	_level_bar = _hud.level_bar
	_b2b_label = _hud.b2b_lamp
	_controls_label = _hud.controls_hint
	_controls_label.text = _controls_line()
	_board_view = BoardView.new()
	_board_view.name = "Board"
	_view.add_child(_board_view)
	_fit_hud()


## Fits the layout to the viewport and moves the board (and its effects) onto
## the layout's BoardSlot.
func _fit_hud() -> void:
	if is_inside_tree():
		HudLayout.fill_viewport(_hud)
		if _result != null:
			HudLayout.fill_viewport(_result)
	else:
		HudLayout.settle(_hud)
	_place_board()


## Keeps the board (and its effects) on the layout's slot. Runs every frame: a
## label that changes width can shift the layout at any time.
func _place_board() -> void:
	var slot: Control = _hud.board_slot
	_board_origin = slot.global_position - _hud.global_position
	_board_view.position = _board_origin
	_board_view.cell_size = floorf(slot.size.x / float(Board.BOARD_WIDTH))
	if _fx != null:
		_fx.position = _board_origin
	_data_labels = []
	for value: Label in [_score_value, _level_value, _lines_value]:
		_data_labels.append((value.get_parent() as Control).get_global_rect())


## The key hints as two aligned lists: translated action names, and the keys
## currently bound to them (read from the InputMap, so remapped keys show up).
func _controls_columns() -> Array[String]:
	var rows: Array = [
		["MOVE", ["move_left", "move_right"]],
		["ROTATE", ["rotate"]],
		["ROTATE CCW", ["rotate_ccw"]],
		["SOFT DROP", ["soft_drop"]],
		["HARD DROP", ["hard_drop"]],
		["HOLD", ["hold"]],
		["PAUSE", ["pause"]],
	]
	var names: Array[String] = []
	var keys: Array[String] = []
	for row: Array in rows:
		# One key per action keeps the line short.
		var bound: Array[String] = []
		for action: String in row[1]:
			bound.append_array(HowToPlay.keys_for([action]).slice(0, 1))
		names.append(tr(String(row[0])))
		keys.append("/".join(bound))
	return ["\n".join(names), "\n".join(keys)]


## The hints on one line: "KEY name" per action.
func _controls_line() -> String:
	var columns: Array[String] = _controls_columns()
	var names: PackedStringArray = columns[0].split("\n")
	var keys: PackedStringArray = columns[1].split("\n")
	var parts: Array[String] = []
	for i: int in names.size():
		parts.append("%s %s" % [keys[i], names[i]])
	return "    ".join(parts)


func _refresh_view() -> void:
	_place_board()
	var piece_cells: Array[Vector2i] = []
	var ghost_cells: Array[Vector2i] = []
	var piece_type: int = -1
	if _piece != null and not _game_over:
		piece_type = _piece.piece_type
		var offset: Vector2i = Vector2i(0, Board.HIDDEN_HEIGHT)
		var ghost_pos: Vector2i = _get_ghost_pos()
		for cell: Vector2i in _piece.get_cells():
			piece_cells.append(cell + _piece_pos - offset)
			if ghost_pos != _piece_pos:
				ghost_cells.append(cell + ghost_pos - offset)
	_board_view.show_board(_board, piece_cells, piece_type, ghost_cells)
	_hud.set_next(_next_queue)
	_hud.set_hold(_hold_type)
	_hud.set_stats(_score, _level, _level_progress(), _lines, maxi(0, _combo_index - 1), _b2b_active)
	var top_row: int = _board.highest_occupied_row()
	_fx.set_danger(not _game_over and top_row >= 0 and Board.BOARD_HEIGHT - top_row >= DANGER_STACK_ROWS)
	if _bgm_director != null:
		_bgm_director.update_pressure(Board.BOARD_HEIGHT - top_row if top_row >= 0 and not _game_over else 0)
	if _pause_menu != null:
		_pause_menu.visible = _paused
	_result.visible = _game_over


## Share of the lines of the current level already cleared (1.0 at the
## level cap).
func _level_progress() -> float:
	if _level >= Scoring.CLASSIC_MAX_LEVEL:
		return 1.0
	return float(_lines % Scoring.LINES_PER_LEVEL) / float(Scoring.LINES_PER_LEVEL)
