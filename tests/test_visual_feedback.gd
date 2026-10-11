extends SceneTree

## Visual feedback of the classic scene (scripts/main.gd).
##
## Revised 2026-10-10: the old flash / pulse / periodic-shake / marinho overlay
## feedback was replaced by the shared BoardFX component (owner: "effects look
## cheap"), so the cases that froze those internals are retired. What stays:
## the background intensity tiers, the vendored marinho files' provenance and
## the menu animation / UI sound wiring. What is new: the classic scene's use
## of BoardFX - non-blocking line clears, call-outs, hard-drop feedback, the
## danger border, the K.O. wipe and the delayed game-over buttons, plus the
## level progress bar and chain HUD. BoardFX itself is covered by
## tests/test_board_fx.gd.

const MODULE_NAME: String = "visual_feedback"

const BASE_SIZE: Vector2i = Vector2i(1152, 648)
const MIX_SETTLE_SECONDS: float = 0.2
const BG_PROPAGATE_SECONDS: float = 0.6
const BG_DECAY_SECONDS: float = 2.6
const SAMPLE_SECONDS: float = 0.7
const MAIN_MENU_SCENE: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"
const MENU_VARIANT_SCRIPT: String = "res://scenes/menus/main_menu/main_menu_with_animations.gd"
const MODE_SELECT_SCENE: String = "res://scenes/menus/mode_select/mode_select.tscn"
const MARINHO_MANIFEST: String = "res://docs/vendor/marinho-visual-effects.json"
const MARINHO_MIT_ARCHIVE: String = "res://docs/vendor/marinho-visual-effects-README.md"
const MARINHO_CC0_LICENSE: String = "res://addons/kenney_particle_pack/LICENSE.txt"
const MARINHO_FILES: Array[String] = [
	"res://camera-effects/camera_shake.tscn",
	"res://camera-effects/camera-shake.gdshader",
	"res://camera-effects/chromatic_aberration.tscn",
	"res://camera-effects/chromatic-aberration.gdshader",
	"res://camera-effects/vignette.tscn",
	"res://camera-effects/vignette.gdshader",
	"res://addons/kenney_particle_pack/circle_01.png",
	"res://addons/kenney_particle_pack/trace_01.png",
	"res://addons/kenney_particle_pack/LICENSE.txt",
	"res://docs/vendor/marinho-visual-effects-README.md",
	"res://particles/shockwave_2d.tscn",
	"res://particles/sparks_2d.tscn",
]


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d visual feedback cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VISUAL FEEDBACK TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.size = BASE_SIZE
	await tree.process_frame
	await _case_line_clear_is_non_blocking_with_sweep_and_callout(ctx)
	await _case_hard_drop_and_lock_feedback(ctx)
	await _case_danger_border_follows_stack_height(ctx)
	await _case_game_over_ko_and_delayed_result_buttons(ctx)
	await _case_level_bar_chain_hud_and_controls_hint(ctx)
	await _case_background_tier_tracks_game_intensity_and_decays_toward_base(ctx)
	await _case_marinho_effect_files_manifest_bound(ctx)
	await _case_mode_select_reuses_template_entry_animation(ctx)
	await _case_ui_sound_controller_button_feedback_wired(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _spawn_main():
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	tree.root.add_child(main)
	await tree.create_timer(MIX_SETTLE_SECONDS).timeout
	return main


static func _settle(seconds: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.create_timer(seconds).timeout


static func _case_background_tier_tracks_game_intensity_and_decays_toward_base(ctx: Dictionary) -> void:
	# Owner decision 2026-09-16: background tiers are decoupled from the BGM
	# (single looping track now) and follow game intensity — level and lines
	# cleared — while still decaying back to the base tier when it drops.
	var main = await _spawn_main()
	var bg: Variant = main.get("_background")
	var base: Variant = main.get("_bg_base_modulate")
	var ok: bool = bg is CanvasItem and typeof(base) == TYPE_COLOR
	if ok:
		var base_color: Color = base
		main._level = 9
		main._lines = 0
		main._update_bg_tier()
		await _settle(BG_PROPAGATE_SECONDS)
		var visual_tier: int = int(main.get("_bg_tier"))
		var high_ratio: float = (bg as CanvasItem).modulate.get_luminance() / maxf(base_color.get_luminance(), 0.001)
		ok = visual_tier == 2 and high_ratio >= 1.10 and high_ratio <= 1.24
		var high_distance: float = absf(high_ratio - 1.0)
		if ok:
			# lines alone lift the tier above the base tier
			main._level = 1
			main._lines = 40
			main._update_bg_tier()
			ok = int(main.get("_bg_tier")) == 1
		if ok:
			main._level = 1
			main._lines = 0
			main._update_bg_tier()
			await _settle(BG_DECAY_SECONDS)
			var rest_tier: int = int(main.get("_bg_tier"))
			var rest_ratio: float = (bg as CanvasItem).modulate.get_luminance() / maxf(base_color.get_luminance(), 0.001)
			var rest_distance: float = absf(rest_ratio - 1.0)
			ok = rest_tier == 0 \
				and rest_distance < high_distance \
				and rest_ratio >= 0.96 and rest_ratio <= 1.06
	main.free()
	_case(ctx, "background_tier_tracks_game_intensity_and_decays_toward_base", ok)


static func _case_marinho_effect_files_manifest_bound(ctx: Dictionary) -> void:
	# O-07 (a): every vendored marinho effect file exists and its bytes are
	# bound to the provenance record (source URL, commit, license per file).
	var ok: bool = true
	for path: String in MARINHO_FILES:
		ok = ok and FileAccess.file_exists(path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MARINHO_MANIFEST))
	var manifest: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed
	else:
		ok = false
	if ok:
		var commit: String = String(manifest.get("commit", ""))
		ok = ok and commit.length() == 40 and commit.is_valid_hex_number()
		ok = ok and String(manifest.get("repository", "")).begins_with("https://github.com/marinho/godot-visual-effects")
		var records: Dictionary = {}
		var files: Variant = manifest.get("files")
		if typeof(files) == TYPE_ARRAY and not (files as Array).is_empty():
			for entry: Variant in files:
				if typeof(entry) == TYPE_DICTIONARY:
					var record: Dictionary = entry
					var key: String = "res://" + String(record.get("path", "")).replace("\\", "/")
					records[key] = String(record.get("sha256", "")).to_lower()
					ok = ok and String(record.get("source_url", "")).begins_with("https://")
					ok = ok and not String(record.get("license", "")).is_empty()
		else:
			ok = false
		for path: String in MARINHO_FILES:
			var digest: String = String(records.get(path, ""))
			ok = ok and digest.length() == 64 and digest == FileAccess.get_sha256(path).to_lower()
		# license archives: MIT statement (README) + Kenney CC0 license file
		ok = ok and FileAccess.get_file_as_string(MARINHO_MIT_ARCHIVE).contains("MIT")
		ok = ok and FileAccess.file_exists(MARINHO_CC0_LICENSE) \
			and FileAccess.get_file_as_string(MARINHO_CC0_LICENSE).length() > 0
	_case(ctx, "marinho_effect_files_exist_and_manifest_bound", ok)


static func _script_inherits_from(script: Script, ancestor_path: String) -> bool:
	var current: Script = script
	while current != null:
		if current.resource_path == ancestor_path:
			return true
		current = current.get_base_script()
	return false


static func _case_mode_select_reuses_template_entry_animation(ctx: Dictionary) -> void:
	# O-07 (b): mode select is built on the vendored animated main-menu
	# variant, so the template Intro/OpenMainMenu entry animation plays.
	var ok: bool = true
	var packed: PackedScene = load(MODE_SELECT_SCENE) as PackedScene
	var select: Node = null
	if packed != null:
		select = packed.instantiate()
	ok = ok and select != null
	if select != null:
		var script: Variant = select.get_script()
		ok = ok and script is Script \
			and _script_inherits_from(script, MENU_VARIANT_SCRIPT)
		var player: Variant = select.find_child("MenuAnimationPlayer", true, false)
		var anim_tree: Variant = select.find_child("MenuAnimationTree", true, false)
		ok = ok and player is AnimationPlayer and anim_tree is AnimationTree
		if player is AnimationPlayer:
			ok = ok and (player as AnimationPlayer).has_animation("Intro") \
				and (player as AnimationPlayer).has_animation("OpenMainMenu")
		select.free()
	# the main menu keeps its template animations too (transition out of it
	# back into it replays a visible animation)
	var menu_packed: PackedScene = load(MAIN_MENU_SCENE) as PackedScene
	ok = ok and menu_packed != null
	if ok:
		var menu: Node = menu_packed.instantiate()
		ok = ok and menu.find_child("MenuAnimationTree", true, false) is AnimationTree
		menu.free()
	_case(ctx, "mode_select_reuses_template_entry_animation", ok)


static func _case_ui_sound_controller_button_feedback_wired(ctx: Dictionary) -> void:
	# O-07 (b): button hover/click feedback runs through the archived Maaack
	# ProjectUISoundController with stream assets wired (BQ-11).
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var controller: Node = tree.root.get_node_or_null(^"ProjectUISoundController")
	var ok: bool = controller != null and controller.has_method("connect_ui_sounds")
	if ok:
		var script: Variant = controller.get_script()
		ok = script is Script \
			and String((script as Script).resource_path).contains("maaacks_ui_sound_controller")
		var hovered: Variant = controller.get("button_hovered")
		var pressed: Variant = controller.get("button_pressed")
		ok = ok and hovered is AudioStream and pressed is AudioStream
		if ok:
			ok = ok and (hovered as AudioStream).resource_path.begins_with("res://assets/audio/") \
				and (pressed as AudioStream).resource_path.begins_with("res://assets/audio/")
	_case(ctx, "ui_sound_controller_button_feedback_wired", ok)


# ---------------------------------------------------------------------------
# Classic scene x BoardFX.
static func _fill_row_except(board: Board, row: int, hole: int) -> void:
	for x: int in Board.BOARD_WIDTH:
		if x != hole:
			board.set_cell(Vector2i(x, row), Tetromino.PieceType.J)


static func _lock_vertical_i(main, column: int) -> void:
	var piece: Tetromino = Tetromino.new(Tetromino.PieceType.I)
	piece.rotation = 1
	main._piece = piece
	main._piece_pos = Vector2i(column - 2, 20)
	main._last_move_was_rotation = false
	main._lock_piece(true)


static func _case_line_clear_is_non_blocking_with_sweep_and_callout(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	for row: int in range(20, 24):
		_fill_row_except(main._board, row, 6)
	# Residue above the cleared rows so the Tetris is not a Perfect Clear.
	main._board.set_cell(Vector2i(0, 19), Tetromino.PieceType.J)
	_lock_vertical_i(main, 6)
	# Same call: the rows are gone, the score is in and the next piece is live
	# (the old clear froze input for 0.48 s behind a blinking overlay).
	var ok: bool = main._lines == 4 and main._score >= 800
	ok = ok and main._piece != null and not main._game_over
	ok = ok and main._board.get_cell(Vector2i(0, 23)) == Tetromino.PieceType.J \
		and main._board.is_empty_at(Vector2i(1, 23))
	ok = ok and main._fx._sweeps.size() == 4 and not main._fx._particles.is_empty()
	ok = ok and main._fx.popup_text() == "TETRIS" and main._last_feedback.contains("TETRIS")
	# Input is honoured on the very next frame.
	var x_before: int = main._piece_pos.x
	await (Engine.get_main_loop() as SceneTree).process_frame
	Input.action_press("move_left")
	main._process(0.016)
	Input.action_release("move_left")
	ok = ok and main._piece_pos.x == x_before - 1
	main.free()
	_case(ctx, "line_clear_is_non_blocking_with_sweep_and_callout", ok)


static func _case_hard_drop_and_lock_feedback(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	main._piece = Tetromino.new(Tetromino.PieceType.O)
	main._piece_pos = Vector2i(4, 6)
	await (Engine.get_main_loop() as SceneTree).process_frame
	Input.action_press("hard_drop")
	main._process(0.016)
	Input.action_release("hard_drop")
	var ok: bool = main._fx._trails.size() == 2 and main._fx._flashes.size() == 4
	ok = ok and not main._fx._particles.is_empty()
	# The whole board view carries the shake, and it comes back to rest.
	await _settle(1.0)
	ok = ok and not main._fx.is_active() and main._view.position == Vector2.ZERO
	main.free()
	_case(ctx, "hard_drop_trail_lock_flash_then_view_returns_to_rest", ok)


static func _case_danger_border_follows_stack_height(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	main._refresh_view()
	var ok: bool = not main._fx.is_danger()
	for row: int in range(Board.BOARD_HEIGHT - main.DANGER_STACK_ROWS, Board.BOARD_HEIGHT):
		main._board.set_cell(Vector2i(0, row), Tetromino.PieceType.J)
	main._refresh_view()
	ok = ok and main._fx.is_danger()
	main._board.set_cell(Vector2i(0, Board.BOARD_HEIGHT - main.DANGER_STACK_ROWS), Board.EMPTY)
	main._refresh_view()
	ok = ok and not main._fx.is_danger()
	main.free()
	_case(ctx, "danger_border_follows_stack_height", ok)


static func _case_game_over_ko_and_delayed_result_buttons(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	main._trigger_game_over()
	var retry: Button = main._retry_button
	var ok: bool = main._fx.is_ko() and main._result_buttons.visible and retry.disabled
	# A hard drop mashed into the final lock must not press a button.
	main._process(main.RESULT_INPUT_DELAY * 0.5)
	ok = ok and retry.disabled
	main._process(main.RESULT_INPUT_DELAY)
	ok = ok and not retry.disabled
	retry.pressed.emit()
	ok = ok and not main._game_over and not main._result_buttons.visible and not main._fx.is_ko()
	ok = ok and main._score == 0 and main._piece != null
	main.free()
	_case(ctx, "game_over_plays_ko_and_enables_result_buttons_after_delay", ok)


static func _case_level_bar_chain_hud_and_controls_hint(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	# Revised 2026-10-10: the bar shows the lines of the level, not the score.
	main._lines = Scoring.LINES_PER_LEVEL / 2
	main._refresh_view()
	var ok: bool = absf(main._level_progress() - 0.5) < 0.01 and absf(main._level_bar.value - 0.5) < 0.01
	main._level = 2
	main._lines = Scoring.LINES_PER_LEVEL
	ok = ok and main._level_progress() == 0.0
	main._level = Scoring.CLASSIC_MAX_LEVEL
	ok = ok and main._level_progress() == 1.0
	main._combo_index = 3
	main._b2b_active = true
	main._refresh_view()
	# Revised 2026-10-10 (UI re-layout): COMBO is a readout of its own card and
	# counts like the versus HUD (a lone clear is combo 0).
	ok = ok and main._combo_value.text == "2"
	main._combo_index = 1
	main._refresh_view()
	ok = ok and main._combo_value.text == "0"
	# The key hints name the keys really bound right now.
	var hint: String = main._controls_label.text
	for action: String in ["move_left", "rotate", "hard_drop", "hold", "pause"]:
		ok = ok and hint.contains(HowToPlay.keys_for([action])[0])
	ok = ok and main._next_queue.size() == 5 and main._next_previews.size() == 5
	main.free()
	_case(ctx, "level_bar_chain_hud_controls_hint_and_five_next", ok)
