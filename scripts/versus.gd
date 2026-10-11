extends Node2D
## Versus battle scene.
##
## Two 10x20 boards run side by side. The player drives the left board with the
## keyboard actions; the versus AI (scripts/versus_ai.gd) drives the right one.
## Both boards belong to the headless VersusBattle model
## (scripts/versus_battle.gd), so this scene only polls input, ticks model + AI,
## turns the model's events into sound and BoardFX feedback and refreshes the
## view; it never re-implements game rules.
##
## Session contract: mode_select writes the chosen configuration through
## GameSession before loading this scene. _ready() reads rules / fixed level /
## match format / difficulty from it and always starts the match at 0:0, so
## the pause menu's Restart (reload_current_scene) restarts the whole match.
## Without a versus session the defaults run: fixed speed level 1, single
## match, normal AI.
##
## CPU vs CPU: when the session names an AI tier for the left board, a second
## VersusAI drives it and the keyboard only pauses; the human watches.
##
## Layout (base canvas 1152x648): every element sits inside the green GameArea
## (96,54)-(1056,594) and both clusters mirror around x = 576.
##   player: HOLD 138 | warn 234 | board 252 | NEXT 480 (+ stats under HOLD)
##   AI:     NEXT 584 | board 680 | warn 908 | HOLD 926 (+ stats under HOLD)

## Cell size of the stock layout's board slots (the real one comes from the
## layout: BoardView.cell_size).
const CELL_SIZE: int = 22
const NEXT_COUNT: int = 5
const ROUND_OVER_DELAY: float = 2.0
const COUNTDOWN_SECONDS: float = 3.0
## Time each AI may spend planning per frame (see VersusAI.frame_budget_usec).
const AI_FRAME_BUDGET_USEC: int = 6000
## The stack is "in danger" once it (plus the incoming garbage) reaches this
## many rows.
const DANGER_STACK_ROWS: int = 15

const PAUSE_MENU_SCENE: String = "res://scenes/windows/pause_menu.tscn"
const MODE_SELECT_SCENE: String = "res://scenes/menus/mode_select/mode_select.tscn"
## Sound events of this scene; files and volumes come from the active resource
## pack (scripts/resource_pack.gd). The left board's own actions, the garbage
## that hits it and the match flow make sound; the right board stays silent.
const SFX_EVENTS: Array[String] = [
	"move", "rotate", "hold", "hard_drop", "lock", "clear", "tetris", "tspin",
	"tspin_mini", "tspin_double", "tspin_triple", "b2b",
	"perfect_clear", "combo", "attack", "garbage", "countdown", "go", "ko",
	"win", "lose", "pause", "resume",
]
const COMBO_PITCH_STEP: float = 0.06
const COMBO_PITCH_MAX: float = 1.9
## AI tag text and pack color per difficulty. The tag stays English on every
## locale.
const DIFFICULTY_TAGS: Dictionary = {
	&"easy": ["EASY", "tier_easy"],
	&"normal": ["NORMAL", "tier_normal"],
	&"hard": ["HARD", "tier_hard"],
	&"lunatic": ["LUNATIC", "tier_lunatic"],
}

var _model: VersusBattle
var _ai: VersusAI
var _game_session = null
var _difficulty: StringName = &"normal"
## Tier of the AI on the left board; empty when the human plays it.
var _left_difficulty: StringName = &""
var _left_ai: VersusAI
## LAN match (GameSession.versus_lan): empty, "host" or "client". The host
## runs the battle, takes the other player's keys for the right board and
## sends a snapshot every frame; the client shows what it is sent, mirrored,
## so each player has their own board on the left.
var _lan: StringName = &""
var _lan_link: Node
## Host: events of this frame, to send. Client: packets not applied yet.
var _lan_events: Array = []
var _lan_packets: Array = []
var _settings_button: Button
var _rules: int = VersusBattle.Rules.FIXED
var _fixed_level: int = 1
var _match_format: int = VersusBattle.MatchFormat.SINGLE
var _view: Node2D
var _sides: Array = []
var _paused: bool = false
var _round_over_timer: float = 0.0
var _countdown_shown: int = 0
var _result_sounded: bool = false
var _pause_menu: PopupWindowPanel
## The player that carries the music now (it changes with the tempo and the song).
var _bgm_player: AudioStreamPlayer:
	get:
		return _bgm_director.current() if _bgm_director != null else null
var _bgm_director: BgmDirector
## Tallest stack (plus incoming garbage) seen by this frame's refresh.
var _frame_pressure: int = 0
var _sfx: Dictionary = {}
## The pack's "versus_hud" layout (both sides, the header) and the
## "result_panel" layout used for the round and match results.
var _hud: VersusHud
var _result: ResultPanel
var _overlay: Control
var _overlay_title: Label
var _overlay_detail: Label
var _overlay_wins: Label
var _result_buttons: Control
var _rematch_button: Button
var _level_label: Label
var _wins_label: Label
var _orb_texture: Texture2D
var _font: Font
var _font_mini: Font


func _ready() -> void:
	_game_session = _find_game_session()
	_font = ResourcePack.font("main")
	_font_mini = ResourcePack.font("mini")
	_orb_texture = ResourcePack.texture("orb")
	_apply_pack_to_scene()
	# The Localization autoload puts the CJK fallback on the shared font
	# instances this scene just loaded, so zh HUD/overlay copy renders.
	if is_inside_tree():
		var localization: Node = get_tree().root.get_node_or_null(^"Localization")
		if localization != null and localization.has_method("ensure_cjk_fallbacks"):
			localization.ensure_cjk_fallbacks()
	_read_session()
	_view = Node2D.new()
	_view.name = "BoardView"
	add_child(_view)
	_build_hud()
	_build_result_panel()
	_build_pause_menu()
	_start_match()
	_refresh_view()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_hud)
	if _lan != &"":
		_lan_link.state_received.connect(_on_lan_state)
		_lan_link.input_received.connect(_on_lan_input)
		_lan_link.peer_left.connect(_on_lan_peer_left)
		# A LAN match cannot be restarted or re-configured from one side.
		var restart: Control = _pause_menu.find_child("RestartButton", true, false) as Control if _pause_menu != null else null
		if restart != null:
			restart.visible = false
		_settings_button.visible = false
		_rematch_button.visible = _lan == &"host"
	# The bus must exist before the player, and both run at the very end of
	# setup so the whole battle face is ready before the first sound.
	_ensure_bgm_bus()
	_setup_bgm()
	_load_sfx()


func _process(delta: float) -> void:
	if _model == null:
		return
	_handle_pause_input()
	if _lan == &"client":
		_process_client()
		return
	# A LAN match goes on behind the pause menu: the other player is not paused.
	if _paused and _lan == &"":
		_refresh_view()
		return
	var phase: int = _model.phase()
	if phase == VersusBattle.Phase.PLAYING or phase == VersusBattle.Phase.COUNTDOWN:
		if _left_ai == null and not _paused:
			_handle_player_input()
		var side: int = VersusBattle.Side.PLAYER
		var piece_before: Tetromino = _model.current_piece(side)
		var x_before: int = _model.piece_pos(side).x
		var rotation_before: int = piece_before.rotation if piece_before != null else 0
		_model.tick(delta)
		if _left_ai != null:
			_left_ai.tick(delta)
		if _ai != null:
			_ai.tick(delta)
		# The model is signal-free: a same-piece x or rotation change this
		# frame is the player's move/rotate (gravity only changes y).
		var piece_after: Tetromino = _model.current_piece(side)
		if piece_after != null and piece_after == piece_before:
			if piece_after.rotation != rotation_before:
				_play_sfx("rotate")
			elif _model.piece_pos(side).x != x_before:
				_play_sfx("move")
		_handle_events()
		_tick_countdown()
	elif phase == VersusBattle.Phase.ROUND_OVER:
		_round_over_timer += delta
		if _round_over_timer >= ROUND_OVER_DELAY:
			_advance_round()
	if _lan == &"host":
		_lan_link.send_state(_model.snapshot(), _lan_events)
		_lan_events = []
	_refresh_view()


## The joining player's frame: keys go to the host, the host's battle comes
## back and is shown.
func _process_client() -> void:
	if not _paused:
		for action: StringName in [VersusBattle.ACTION_MOVE_LEFT, VersusBattle.ACTION_MOVE_RIGHT, VersusBattle.ACTION_SOFT_DROP]:
			if Input.is_action_just_pressed(action):
				_lan_link.send_input(action, _lan_link.INPUT_PRESS)
			if Input.is_action_just_released(action):
				_lan_link.send_input(action, _lan_link.INPUT_RELEASE)
		for action: StringName in [VersusBattle.ACTION_ROTATE, VersusBattle.ACTION_ROTATE_CCW, VersusBattle.ACTION_HARD_DROP, VersusBattle.ACTION_HOLD]:
			if Input.is_action_just_pressed(action):
				_lan_link.send_input(action, _lan_link.INPUT_TAP)
	var side: int = VersusBattle.Side.PLAYER
	var piece_before: Tetromino = _model.current_piece(side)
	var x_before: int = _model.piece_pos(side).x
	var rotation_before: int = piece_before.rotation if piece_before != null else 0
	var round_before: int = _model.round_index()
	var phase_before: int = _model.phase()
	for packet: Array in _lan_packets:
		_model.apply_snapshot(packet[0], packet[1], true)
	_lan_packets.clear()
	# A new round (or a rematch) starts with clean boards.
	if _model.phase() == VersusBattle.Phase.COUNTDOWN and (phase_before != VersusBattle.Phase.COUNTDOWN or _model.round_index() != round_before):
		_countdown_shown = 0
		for view: SideView in _sides:
			view.fx.reset()
	var piece_after: Tetromino = _model.current_piece(side)
	if piece_after != null and piece_after == piece_before:
		if piece_after.rotation != rotation_before:
			_play_sfx("rotate")
		elif _model.piece_pos(side).x != x_before:
			_play_sfx("move")
	_handle_events()
	_tick_countdown()
	_refresh_view()


func _on_lan_state(snapshot: Dictionary, events: Array) -> void:
	if _lan == &"client":
		_lan_packets.append([snapshot, events])


## A key of the joining player, played on the right board.
func _on_lan_input(action: StringName, kind: int) -> void:
	if _lan != &"host" or _model == null:
		return
	var side: int = VersusBattle.Side.AI
	match kind:
		_lan_link.INPUT_PRESS:
			_model.press(side, action)
		_lan_link.INPUT_RELEASE:
			_model.release(side, action)
		_lan_link.INPUT_TAP:
			_model.tap(side, action)


## The other player is gone: back to the LAN page, which says so.
func _on_lan_peer_left() -> void:
	if _game_session != null:
		_game_session.versus_match_in_progress = false
		_game_session.versus_page = _game_session.PAGE_LAN
		_game_session.lan_notice = "LAN_PEER_LEFT"
		_game_session.open_versus_setup = true
	_lan_link.close()
	_change_scene(MODE_SELECT_SCENE)


## The scene file's own background and area nodes take the pack's look.
func _apply_pack_to_scene() -> void:
	var base: ColorRect = get_node_or_null(^"Background/BackgroundColor") as ColorRect
	if base != null:
		base.color = ResourcePack.color("background_base")
	var image: TextureRect = get_node_or_null(^"Background/BackgroundImage") as TextureRect
	if image != null:
		image.texture = ResourcePack.texture("background")
		image.modulate = ResourcePack.color("background_tint")
		# The pack's animated backdrop, when it has one, covers the still picture.
		if not image.get_parent().has_node(^"PackBackdrop"):
			PackBackdrop.add_to(image.get_parent())
	var area_fill: Polygon2D = get_node_or_null(^"GameArea/AreaFill") as Polygon2D
	if area_fill != null:
		area_fill.color = ResourcePack.color("area_fill")
	var area_border: Line2D = get_node_or_null(^"GameArea/AreaBorder") as Line2D
	if area_border != null:
		area_border.default_color = ResourcePack.color("area_border")


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT and _model != null and not _paused and _lan == &"" \
			and _model.phase() != VersusBattle.Phase.MATCH_OVER:
		_set_paused(true)


# ---------------------------------------------------------------------------
# Session / match setup
func _read_session() -> void:
	if _game_session == null or not bool(_game_session.is_versus()) or not bool(_game_session.versus_match_in_progress):
		return
	# Session string names are read dynamically so the script stays loadable
	# without the autoload.
	if StringName(_game_session.versus_rules) == &"rising":
		_rules = VersusBattle.Rules.RISING
	_fixed_level = clampi(int(_game_session.versus_fixed_level), 1, 10)
	if StringName(_game_session.versus_match_format) == &"best_of_3":
		_match_format = VersusBattle.MatchFormat.BEST_OF_3
	# Unknown stored difficulties keep the normal default.
	var stored_difficulty: StringName = StringName(_game_session.versus_difficulty)
	if VersusAI.DIFFICULTY_PROFILES.has(stored_difficulty):
		_difficulty = stored_difficulty
	var stored_left: StringName = StringName(_game_session.versus_left_difficulty)
	if VersusAI.DIFFICULTY_PROFILES.has(stored_left):
		_left_difficulty = stored_left
	# A LAN match needs its link; without one this is a match against the CPU.
	_lan_link = get_tree().root.get_node_or_null(^"LanSession")
	var role: StringName = StringName(_game_session.versus_lan)
	if role != &"" and _lan_link != null and _lan_link.role() == role:
		_lan = role
		_left_difficulty = &""


## Starts a fresh match at 0:0 (scene start and the result screen's Rematch).
func _start_match() -> void:
	_model = VersusBattle.new()
	_model.countdown_seconds = COUNTDOWN_SECONDS
	_model.setup(_rules, _fixed_level, _match_format, randi())
	# The AI's decision RNG derives from the battle seed, so one seed
	# reproduces the whole match.
	# In a LAN match the right board is the other player's.
	_ai = null if _lan != &"" else VersusAI.new(_model, VersusBattle.Side.AI, VersusAI.DIFFICULTY_PROFILES[_difficulty], _model.seed_value())
	_left_ai = null
	if _left_difficulty != &"":
		_left_ai = VersusAI.new(_model, VersusBattle.Side.PLAYER, VersusAI.DIFFICULTY_PROFILES[_left_difficulty], _model.seed_value() + 7919)
	# On screen a plan is spread over frames instead of freezing one (headless
	# runs drive the scene without frames passing, so they plan in one go).
	if DisplayServer.get_name() != "headless" and _ai != null:
		_ai.frame_budget_usec = AI_FRAME_BUDGET_USEC
		if _left_ai != null:
			_left_ai.frame_budget_usec = AI_FRAME_BUDGET_USEC
	_round_over_timer = 0.0
	_countdown_shown = 0
	for view: SideView in _sides:
		view.fx.reset()
	_save_progress()
	if _result_buttons != null:
		_result_buttons.visible = false


func _find_game_session():
	# Autoload lookup is optional so the scene still works when instantiated
	# without the autoload (same pattern as scripts/main.gd).
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null(^"GameSession")


func _save_progress() -> void:
	if _game_session == null:
		return
	_game_session.save_versus_progress(
		[_model.round_wins(VersusBattle.Side.PLAYER), _model.round_wins(VersusBattle.Side.AI)],
		_model.round_index()
	)


func _advance_round() -> void:
	_round_over_timer = 0.0
	_countdown_shown = 0
	_model.start_round()
	for view: SideView in _sides:
		view.fx.reset()
	_save_progress()


# ---------------------------------------------------------------------------
# Input
func _handle_pause_input() -> void:
	if _model.phase() == VersusBattle.Phase.MATCH_OVER:
		return
	if Input.is_action_just_pressed("pause"):
		# Esc while paused belongs to the menu: it closes its top window
		# (and the pause menu's own close resumes the game).
		if _paused and Input.is_action_just_pressed("ui_cancel"):
			return
		_set_paused(not _paused)


func _handle_player_input() -> void:
	var side: int = VersusBattle.Side.PLAYER
	for action: StringName in [VersusBattle.ACTION_MOVE_LEFT, VersusBattle.ACTION_MOVE_RIGHT, VersusBattle.ACTION_SOFT_DROP]:
		if Input.is_action_just_pressed(action):
			_model.press(side, action)
		if Input.is_action_just_released(action):
			_model.release(side, action)
	for action: StringName in [VersusBattle.ACTION_ROTATE, VersusBattle.ACTION_ROTATE_CCW, VersusBattle.ACTION_HARD_DROP, VersusBattle.ACTION_HOLD]:
		if Input.is_action_just_pressed(action):
			_model.tap(side, action)


func _set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	if _lan == &"":
		_model.set_paused(paused)
	_play_sfx("pause" if paused else "resume")


func _on_pause_menu_closed() -> void:
	if _paused:
		_set_paused(false)


func _on_rematch_pressed() -> void:
	_start_match()


func _on_change_settings_pressed() -> void:
	if _game_session != null:
		_game_session.versus_match_in_progress = false
		_game_session.open_versus_setup = true
	_change_scene(MODE_SELECT_SCENE)


func _return_to_main_menu() -> void:
	if _lan != &"":
		# Hanging up tells the other player.
		_lan_link.peer_left.disconnect(_on_lan_peer_left)
		_lan_link.close()
	if _game_session != null:
		_save_progress()
		_game_session.versus_match_in_progress = false
	var main_menu_path: String = MaaacksGameTemplate.get_main_menu_path()
	if not main_menu_path.is_empty():
		_change_scene(main_menu_path)


func _change_scene(path: String) -> void:
	var scene_loader: Node = get_tree().root.get_node_or_null(^"SceneLoader")
	if scene_loader != null:
		scene_loader.load_scene(path)
	else:
		get_tree().change_scene_to_file(path)


# ---------------------------------------------------------------------------
# Model events -> sound and BoardFX
func _handle_events() -> void:
	var events: Array[Dictionary] = _model.drain_events()
	if _lan == &"host":
		_lan_events.append_array(events)
	for i: int in events.size():
		var event: Dictionary = events[i]
		var side: int = int(event["side"])
		var view: SideView = _sides[side] as SideView
		var mine: bool = side == VersusBattle.Side.PLAYER
		match event["type"]:
			&"lock":
				var cells: Array[Vector2i] = _visible_cells(event["cells"])
				view.fx.lock_flash(cells)
				if bool(event["hard"]):
					view.fx.hard_drop(cells, int(event["drop_distance"]), ResourcePack.cell_color(int(event["piece_type"])))
				# A clearing lock sounds as its clear instead.
				var clears: bool = i + 1 < events.size() and events[i + 1]["type"] == &"clear" and int(events[i + 1]["side"]) == side
				if mine and not clears:
					_play_sfx("hard_drop" if bool(event["hard"]) else "lock")
			&"clear":
				_show_clear(side, view, event)
				if mine:
					_play_clear_sfx(event)
			&"spin":
				if mine:
					_play_sfx(BoardFX.clear_sound(0, int(event["t_spin"]), false))
				var words: Array[String] = BoardFX.callout(0, int(event["t_spin"]), false, 0, false)
				view.fx.popup(words[0], words[1], BoardFX.callout_color(0, int(event["t_spin"]), false))
			&"garbage":
				view.fx.garbage_in(int(event["rows"]))
				if mine:
					_play_sfx("garbage")
			&"hold":
				if mine:
					_play_sfx("hold")
			&"lost":
				view.fx.play_ko()
				_play_sfx("ko")
	_play_result_sfx()


## One main sound per clear (BoardFX.clear_sound: every special clear has its
## own), the Back-to-Back stinger on top when the chain pays, a combo pluck
## that climbs in pitch while the combo runs, and a whoosh when rows are sent.
func _play_clear_sfx(event: Dictionary) -> void:
	var lines: int = int(event["lines"])
	var sound: String = BoardFX.clear_sound(lines, int(event["t_spin"]), bool(event["perfect_clear"]))
	_play_sfx(sound, 1.0 + 0.08 * float(lines - 1) if sound == "clear" else 1.0)
	if bool(event["b2b"]):
		_play_sfx("b2b")
	var combo: int = int(event["combo"])
	if combo >= 2:
		_play_sfx("combo", minf(COMBO_PITCH_MAX, 1.0 + COMBO_PITCH_STEP * float(combo - 1)))
	if int(event["sent"]) > 0:
		_play_sfx("attack")


## Jingle when the match has just been decided: the win tune when the left
## board (the human, or CPU 1 when watching) took it, the lose tune otherwise.
func _play_result_sfx() -> void:
	var over: bool = _model.phase() == VersusBattle.Phase.MATCH_OVER
	if over and not _result_sounded:
		_play_sfx("win" if _model.match_winner() == VersusBattle.Side.PLAYER else "lose")
	_result_sounded = over


func _show_clear(side: int, view: SideView, event: Dictionary) -> void:
	var rows: Array[int] = []
	var colors: Array = []
	var mid_row: float = 0.0
	for i: int in (event["rows"] as Array).size():
		var row: int = int(event["rows"][i]) - Board.HIDDEN_HEIGHT
		rows.append(row)
		mid_row += float(row) / float((event["rows"] as Array).size())
		var row_colors: Array[Color] = []
		for value: int in event["row_cells"][i]:
			row_colors.append(ResourcePack.cell_color(value))
		colors.append(row_colors)
	view.fx.line_clear(rows, colors)
	var lines: int = int(event["lines"])
	var t_spin: int = int(event["t_spin"])
	var perfect: bool = bool(event["perfect_clear"])
	var attack: int = int(event["attack"])
	var words: Array[String] = BoardFX.callout(lines, t_spin, bool(event["b2b"]), int(event["combo"]), perfect, attack)
	view.fx.popup(words[0], words[1], BoardFX.callout_color(lines, t_spin, perfect))
	view.fx.special_clear(t_spin != Scoring.TSpinKind.NONE, perfect)
	view.fx.shake(1.5 * float(attack))
	# Attack orbs: cancelled rows fly into the attacker's own warning bar,
	# the rest into the opponent's.
	var from: Vector2 = view.origin + Vector2(view.board.board_size().x / 2.0, (mid_row + 0.5) * view.board.cell_size)
	if int(event["cancelled"]) > 0:
		BoardFX.spawn_orb(_view, from, view.warn_point, ResourcePack.color("cancel"), _orb_texture)
	if int(event["sent"]) > 0:
		var target: SideView = _sides[1 - side] as SideView
		var color: Color = ResourcePack.color("player") if side == VersusBattle.Side.PLAYER else ResourcePack.color("opponent")
		BoardFX.spawn_orb(_view, from, target.warn_point, color, _orb_texture)


func _visible_cells(world_cells: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in world_cells:
		cells.append(cell - Vector2i(0, Board.HIDDEN_HEIGHT))
	return cells


func _tick_countdown() -> void:
	if _model.phase() == VersusBattle.Phase.COUNTDOWN:
		var number: int = ceili(_model.countdown_left())
		if number != _countdown_shown and number > 0:
			_countdown_shown = number
			_play_sfx("countdown")
			for view: SideView in _sides:
				view.fx.popup(str(number), "", Color.WHITE)
	elif _countdown_shown > 0:
		_countdown_shown = 0
		_play_sfx("go")
		for view: SideView in _sides:
			view.fx.popup("GO!", "", ResourcePack.color("good"))


# ---------------------------------------------------------------------------
# BGM: code-built exactly like scripts/main.gd, never a scene node. The player
# stays a child of this scene with autoplay off and the bus on "BGM", so
# ProjectMusicController's adoption hook (_node_matches_checks requires
# autoplay AND the Music bus) can never capture it across scenes; freeing the
# scene on a mode switch is what stops the music.
func _ensure_bgm_bus() -> void:
	# Idempotent ensure (main.gd creates the bus first on the classic path,
	# compressor included - reuse it as-is, never add a second bus).
	var bgm_bus: int = AudioServer.get_bus_index("BGM")
	if bgm_bus == -1:
		AudioServer.add_bus()
		bgm_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bgm_bus, "BGM")
		AudioServer.set_bus_send(bgm_bus, "Master")
		_add_bgm_sidechain(bgm_bus)
		return
	# Defensive restore: with the shipped default_bus_layout.tres the bus
	# always arrives with exactly one sidechain compressor.
	for i in AudioServer.get_bus_effect_count(bgm_bus):
		if AudioServer.get_bus_effect(bgm_bus, i) is AudioEffectCompressor:
			return
	_add_bgm_sidechain(bgm_bus)


func _add_bgm_sidechain(bgm_bus: int) -> void:
	var compressor: AudioEffectCompressor = AudioEffectCompressor.new()
	compressor.sidechain = "SFX"
	AudioServer.add_bus_effect(bgm_bus, compressor)


func _setup_bgm() -> void:
	# The playlist, the walk up and down each song's tempo ladder and the
	# change from one song to the next: see BgmDirector.
	_bgm_director = BgmDirector.new()
	add_child(_bgm_director)
	_bgm_director.setup(&"BGM")


func _load_sfx() -> void:
	_sfx = ResourcePack.make_sfx_players(self, SFX_EVENTS)


func _play_sfx(sfx_name: String, pitch: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var player: AudioStreamPlayer = _sfx.get(sfx_name) as AudioStreamPlayer
	if player != null and player.stream != null:
		player.pitch_scale = pitch
		player.play()


# ---------------------------------------------------------------------------
# View construction
## The whole screen comes from the resource pack's "versus_hud" layout: two
## "versus_side" layouts and a header. This script puts a board (and its
## effects) onto each side's BoardSlot and feeds the readouts.
func _build_hud() -> void:
	_hud = ResourcePack.layout("versus_hud").instantiate() as VersusHud
	_view.add_child(_hud)
	_hud.bind()
	_level_label = _hud.level_label
	_wins_label = _hud.round_wins
	_wins_label.name = "RoundWinsLabel"
	_sides.resize(2)
	for side: int in [VersusBattle.Side.PLAYER, VersusBattle.Side.AI]:
		var view: SideView = SideView.new()
		view.layout = _hud.side(side)
		_sides[side] = view
		# Board and effects move together with the side's BoardFX offset.
		view.root = Node2D.new()
		view.root.name = "PlayerBoard" if side == VersusBattle.Side.PLAYER else "AIBoard"
		_view.add_child(view.root)
		view.board = BoardView.new()
		view.board.name = "Board"
		view.root.add_child(view.board)
		view.fx = BoardFX.new()
		view.fx.name = "FX"
		view.root.add_child(view.fx)
		view.layout.warn_bar.font = _font_mini
		view.layout.warn_bar.cap = VersusBattle.GARBAGE_CAP_PER_LOCK
		view.layout.warn_bar.name = "IncomingPlayer" if side == VersusBattle.Side.PLAYER else "IncomingAI"
		_set_tags(side, view)
	_fit_hud()
	for view: SideView in _sides:
		view.fx.setup(view.board.cell_size, _font)


## Name tag above each board: "YOU" for the human, "CPU" plus the tier for an
## AI (fixed English, color-coded per tier). In CPU vs CPU the two sides read
## "CPU 1" and "CPU 2".
func _set_tags(side: int, view: SideView) -> void:
	var left: bool = side == VersusBattle.Side.PLAYER
	view.layout.name_tag.name = "PlayerTag" if left else "AITag"
	view.layout.tier_tag.name = "PlayerDifficultyLabel" if left else "AIDifficultyLabel"
	if left and _left_difficulty == &"":
		view.layout.set_tags(tr("YOU"), ResourcePack.color("player"), "", Color.WHITE)
		return
	if _lan != &"":
		view.layout.set_tags(tr("RIVAL"), ResourcePack.color("opponent"), "", Color.WHITE)
		return
	var cpu_text: String = "CPU" if _left_difficulty == &"" else "CPU %d" % (side + 1)
	var tag: Array = DIFFICULTY_TAGS.get(_left_difficulty if left else _difficulty, DIFFICULTY_TAGS[&"normal"])
	view.layout.set_tags(cpu_text, ResourcePack.color("player") if left else ResourcePack.color("opponent"),
		String(tag[0]), ResourcePack.color(String(tag[1])))


## Fits the layout to the viewport and moves each board onto its BoardSlot.
func _fit_hud() -> void:
	if is_inside_tree():
		HudLayout.fill_viewport(_hud)
		if _result != null:
			HudLayout.fill_viewport(_result)
	else:
		HudLayout.settle(_hud)
	_place_boards()


## Keeps each board (and its effects and meter) on its layout slot. Runs every
## frame: a label that changes width can shift the layout at any time.
func _place_boards() -> void:
	for view: SideView in _sides:
		var slot: Control = view.layout.board_slot
		view.origin = slot.global_position - _hud.global_position
		view.board.position = view.origin
		view.board.cell_size = floorf(slot.size.x / float(Board.BOARD_WIDTH))
		view.fx.position = view.origin
		view.layout.warn_bar.cell_size = view.board.cell_size
		var bar: Control = view.layout.warn_bar
		view.warn_point = bar.global_position - _hud.global_position + Vector2(bar.size.x / 2.0, bar.size.y - 10.0)


## Round / match result: the pack's "result_panel" layout on its own layer,
## with the match-over choices as real focusable buttons.
func _build_result_panel() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ResultLayer"
	add_child(layer)
	_result = ResourcePack.layout("result_panel").instantiate() as ResultPanel
	_result.name = "RoundOverlay"
	layer.add_child(_result)
	_result.bind()
	HudLayout.fill_viewport(_result)
	_overlay = _result
	_overlay_title = _result.title
	_overlay_detail = _result.detail
	_overlay_wins = _result.extra
	_result_buttons = _result.buttons
	_result_buttons.name = "ResultButtons"
	_rematch_button = _result.add_button("Rematch", _on_rematch_pressed)
	_settings_button = _result.add_button("Change Settings", _on_change_settings_pressed)
	_result.add_button("Main Menu", _return_to_main_menu)


## The enabled packs changed from the pause menu: the scene is rebuilt so
## layouts, sounds and colors all come from the new set.
func _on_packs_changed() -> void:
	get_tree().reload_current_scene()


func _build_pause_menu() -> void:
	# Same assembly as scripts/main.gd: the Maaack pause menu lives in its own
	# canvas layer above the boards with the template's popup-parent
	# reparenting disabled (parent_scene = null) so the per-frame visibility
	# sync cannot race the template's open/close coroutines.
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
	# The RichTextLabel confirmation body is translated explicitly because
	# Control auto-translate does not cover it.
	for confirmation_name: String in ["RestartConfirmation", "MainMenuConfirmation", "ExitConfirmation"]:
		var confirmation: WindowPanel = _pause_menu.get_node_or_null(NodePath(confirmation_name)) as WindowPanel
		if confirmation != null:
			confirmation.text = tr(confirmation.text)
	_pause_menu.closed.connect(_on_pause_menu_closed)


# ---------------------------------------------------------------------------
# View refresh
func _refresh_view() -> void:
	_place_boards()
	_frame_pressure = 0
	for side: int in [VersusBattle.Side.PLAYER, VersusBattle.Side.AI]:
		_refresh_side(side, _sides[side] as SideView)
	if _bgm_director != null:
		_bgm_director.update_pressure(_frame_pressure)
	_level_label.text = tr("LEVEL %d") % _model.level(VersusBattle.Side.PLAYER)
	var best_of_3: bool = _model.match_format() == VersusBattle.MatchFormat.BEST_OF_3
	_wins_label.visible = best_of_3
	if best_of_3:
		_wins_label.text = "%d - %d" % [_model.round_wins(VersusBattle.Side.PLAYER), _model.round_wins(VersusBattle.Side.AI)]
	_refresh_overlay()
	if _pause_menu != null:
		_pause_menu.visible = _paused


func _refresh_side(side: int, view: SideView) -> void:
	view.root.position = view.fx.offset
	var board: Board = _model.board(side)
	# The falling piece stays hidden until GO.
	var piece: Tetromino = _model.current_piece(side) if _model.phase() != VersusBattle.Phase.COUNTDOWN else null
	var piece_cells: Array[Vector2i] = []
	var ghost_cells: Array[Vector2i] = []
	if piece != null:
		var offset: Vector2i = Vector2i(0, Board.HIDDEN_HEIGHT)
		var piece_pos: Vector2i = _model.piece_pos(side)
		var ghost_pos: Vector2i = _model.ghost_pos(side)
		for cell: Vector2i in piece.get_cells():
			piece_cells.append(cell + piece_pos - offset)
			if ghost_pos != piece_pos:
				ghost_cells.append(cell + ghost_pos - offset)
	view.board.show_board(board, piece_cells, piece.piece_type if piece != null else -1, ghost_cells)
	var pending: int = _model.pending_garbage(side)
	view.layout.set_next(_model.next_queue(side))
	view.layout.set_hold(_model.hold_type(side))
	view.layout.set_stats(_model.attack_sent(side), maxi(0, _model.combo(side) - 1),
		float(_model.pieces_placed(side)) / maxf(1.0, _model.elapsed()), _model.b2b_active(side), pending)
	var top_row: int = board.highest_occupied_row()
	var stack_rows: int = Board.BOARD_HEIGHT - top_row if top_row >= 0 else 0
	view.fx.set_danger(_model.phase() == VersusBattle.Phase.PLAYING and stack_rows + pending >= DANGER_STACK_ROWS)
	if _model.phase() == VersusBattle.Phase.PLAYING:
		_frame_pressure = maxi(_frame_pressure, stack_rows + pending)


func _refresh_overlay() -> void:
	# Every overlay string is rewritten each frame, so each assignment routes
	# its format key through tr() before the % substitution.
	var phase: int = _model.phase()
	var match_over: bool = phase == VersusBattle.Phase.MATCH_OVER
	if _result_buttons.visible != match_over:
		_result_buttons.visible = match_over
		if match_over and _rematch_button.is_inside_tree():
			_rematch_button.grab_focus()
	if phase == VersusBattle.Phase.PLAYING or phase == VersusBattle.Phase.COUNTDOWN:
		_overlay.visible = false
		return
	_overlay.visible = true
	_overlay_wins.visible = false
	var best_of_3: bool = _model.match_format() == VersusBattle.MatchFormat.BEST_OF_3
	_overlay_wins.visible = best_of_3
	if phase == VersusBattle.Phase.ROUND_OVER:
		if _model.last_round_draw():
			_overlay_title.text = tr("DRAW - REPLAY")
			_overlay_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		elif _left_ai != null:
			# CPU vs CPU: nobody is "the player", each side wins in its own color.
			_overlay_title.text = tr("CPU %d WINS ROUND %d") % [_model.round_winner() + 1, _model.round_index()]
			_overlay_title.add_theme_color_override("font_color", ResourcePack.color("player") if _model.round_winner() == VersusBattle.Side.PLAYER else ResourcePack.color("opponent"))
		elif _model.round_winner() == VersusBattle.Side.PLAYER:
			_overlay_title.text = (tr("YOU WIN ROUND %d") if _lan != &"" else tr("PLAYER WINS ROUND %d")) % _model.round_index()
			_overlay_title.add_theme_color_override("font_color", ResourcePack.color("good"))
		else:
			_overlay_title.text = (tr("RIVAL WINS ROUND %d") if _lan != &"" else tr("AI WINS ROUND %d")) % _model.round_index()
			_overlay_title.add_theme_color_override("font_color", ResourcePack.color("bad"))
	elif _left_ai != null:
		_overlay_title.text = tr("CPU %d WINS MATCH") % (_model.match_winner() + 1)
		_overlay_title.add_theme_color_override("font_color", ResourcePack.color("player") if _model.match_winner() == VersusBattle.Side.PLAYER else ResourcePack.color("opponent"))
	else:
		var human_won: bool = _model.match_winner() == VersusBattle.Side.PLAYER
		if _lan != &"":
			_overlay_title.text = tr("YOU WIN THE MATCH") if human_won else tr("RIVAL WINS THE MATCH")
		else:
			_overlay_title.text = tr("PLAYER WINS MATCH") if human_won else tr("AI WINS MATCH")
		_overlay_title.add_theme_color_override("font_color", ResourcePack.color("good") if human_won else ResourcePack.color("bad"))
	_overlay_detail.text = tr("LINES SENT %d : %d") % [_model.attack_sent(VersusBattle.Side.PLAYER), _model.attack_sent(VersusBattle.Side.AI)]
	if best_of_3:
		_overlay_wins.text = tr("ROUND WINS %d : %d") % [_model.round_wins(VersusBattle.Side.PLAYER), _model.round_wins(VersusBattle.Side.AI)]


# ---------------------------------------------------------------------------
class SideView:
	extends RefCounted

	## This side's part of the layout.
	var layout: VersusSide
	## Top-left of the board in the scene.
	var origin: Vector2 = Vector2.ZERO
	var root: Node2D
	var fx: BoardFX
	var board: BoardView
	## Where attack orbs fly to: the foot of this side's garbage meter.
	var warn_point: Vector2 = Vector2.ZERO
