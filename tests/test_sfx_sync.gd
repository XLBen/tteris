extends SceneTree

const MODULE_NAME: String = "sfx_sync"

const SFX_EVENTS: Array[String] = [
	"move",
	"rotate",
	"hold",
	"hard_drop",
	"lock",
	"clear",
	"tetris",
	"level_up",
	"game_over",
	"pause",
	"resume",
]
const MAX_ONSET_MS: float = 30.0
const MAX_HALF_AMPLITUDE_MS: float = 30.0
const MAX_OUTPUT_LATENCY_MS: float = 10.0
const MEASUREMENTS_PATH: String = "res://assets/assets-measurements.json"
const MIX_SETTLE_SECONDS: float = 0.2


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d sfx sync cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("SFX SYNC TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_mapping_covers_all_11_events(ctx)
	await _case_streams_preloaded_on_sfx_bus(ctx)
	await _case_same_frame_start_without_timer_or_queue(ctx)
	await _case_output_latency_lowered(ctx)
	await _case_all_11_sfx_measured_crisp_hash_bound(ctx)
	await _case_versus_sfx_mapping_matches_classic(ctx)
	await _case_versus_lock_sfx_on_non_clearing_lock(ctx)
	await _case_versus_hard_drop_sfx_via_input(ctx)
	await _case_versus_clear_sfx_on_line_clear(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _spawn_main():
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await (Engine.get_main_loop() as SceneTree).create_timer(MIX_SETTLE_SECONDS).timeout
	return main


# Revised 2026-10-10 (owner: re-lay out the UI, decouple the assets): the scene
# names sound EVENTS only; the files behind them come from the resource pack.
static func _case_mapping_covers_all_11_events(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	var events: Array[String] = main.SFX_EVENTS
	var players: Dictionary = main._sfx
	for event: String in SFX_EVENTS:
		ok = ok and events.has(event) and players.has(event) and ResourcePack.sound(event) != null
	# No asset path is left in the scene scripts.
	for script: String in ["res://scripts/main.gd", "res://scripts/versus.gd"]:
		var text: String = FileAccess.get_file_as_string(script)
		ok = ok and not text.is_empty() and not text.contains("res://assets") and not text.contains(".ogg") and not text.contains(".wav")
	main.free()
	_case(ctx, "mapping_covers_all_11_events", ok)


static func _case_streams_preloaded_on_sfx_bus(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = AudioServer.get_bus_index("SFX") != -1
	var players: Dictionary = main._sfx
	for event: String in main.SFX_EVENTS:
		var stream_player: AudioStreamPlayer = players.get(event) as AudioStreamPlayer
		if stream_player == null:
			ok = false
			continue
		ok = ok and stream_player.stream != null and stream_player.stream == ResourcePack.sound(event)
		ok = ok and stream_player.bus == "SFX"
		ok = ok and absf(stream_player.volume_db - ResourcePack.sound_volume(event)) < 0.01
	main.free()
	_case(ctx, "streams_preloaded_on_dedicated_sfx_bus", ok)


static func _case_same_frame_start_without_timer_or_queue(ctx: Dictionary) -> void:
	var main = await _spawn_main()
	var ok: bool = true
	var players: Dictionary = main._sfx
	for event: String in SFX_EVENTS:
		if not players.has(event):
			ok = false
			continue
		var player: Variant = players[event]
		if not (player is AudioStreamPlayer):
			ok = false
			continue
		var stream_player: AudioStreamPlayer = player
		if stream_player.stream == null:
			ok = false
			continue
		stream_player.stop()
		main._play_sfx(event)
		if not stream_player.playing:
			ok = false
		elif stream_player.get_stream_playback() == null:
			ok = false
	if ok:
		ok = _play_sfx_body_is_direct()
	main.free()
	_case(ctx, "same_frame_start_without_timer_or_queue", ok)


static func _play_sfx_body_is_direct() -> bool:
	var text: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	if text.is_empty():
		return false
	var start: int = text.find("func _play_sfx(")
	if start < 0:
		return false
	var next: int = text.find("\nfunc ", start + 1)
	var end_pos: int = next if next > 0 else text.length()
	var body: String = text.substr(start, end_pos - start)
	for forbidden: String in ["create_timer", "Timer", "await", "call_deferred", "queue"]:
		if body.contains(forbidden):
			return false
	return true


static func _case_output_latency_lowered(ctx: Dictionary) -> void:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	var ok: bool = not text.is_empty()
	if ok:
		var pattern: RegEx = RegEx.new()
		ok = pattern.compile("driver/output_latency\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)") == OK
		if ok:
			var found: RegExMatch = pattern.search(text)
			if found == null:
				ok = false
			else:
				ok = float(found.get_string(1)) <= MAX_OUTPUT_LATENCY_MS
	_case(ctx, "audio_output_latency_lowered_to_10ms_or_less", ok)


# Revised 2026-10-10 (owner: re-lay out the UI, decouple the assets): the old case
# bound the 11 Kenney files to a measurements file. The default pack's sounds
# are synthesized (tools/make_default_sfx.py), so the crispness is measured
# here, straight from the WAV files: a sound must reach a tenth of its peak
# within MAX_ONSET_MS, and the piece-handling sounds must be short.
static func _case_all_11_sfx_measured_crisp_hash_bound(ctx: Dictionary) -> void:
	var ok: bool = true
	for event: String in SFX_EVENTS:
		var path: String = "res://packs/default/sounds/%s.wav" % event
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.size() <= 44:
			ok = false
			continue
		var rate: int = bytes.decode_u32(24)
		var count: int = (bytes.size() - 44) / 2
		var peak: int = 0
		for i: int in count:
			peak = maxi(peak, absi(bytes.decode_s16(44 + i * 2)))
		var onset: int = count
		for i: int in count:
			if absi(bytes.decode_s16(44 + i * 2)) * 10 >= peak:
				onset = i
				break
		ok = ok and peak > 8000 and float(onset) * 1000.0 / float(rate) <= MAX_ONSET_MS
		if event in ["move", "rotate", "lock", "hard_drop", "hold"]:
			ok = ok and float(count) / float(rate) <= 0.2
	_case(ctx, "all_11_mapped_sfx_measured_crisp_hash_bound", ok)


# ---------------------------------------------------------------------------
# Post-delivery versus battle SFX (owner report 2026-09-19: battle had no SFX
# at all). The versus scene reuses the classic subset 1:1 for player-side
# events; these cases pin the wiring and the two nontrivial triggers.
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const VERSUS_SFX_EVENTS: Array[String] = [
	"move", "rotate", "hold", "hard_drop", "lock", "clear", "tetris", "pause", "resume",
]
const VERSUS_BOARD_HEIGHT: int = 24


static func _reset_versus_session() -> void:
	var session: Node = _tree().root.get_node_or_null(^"GameSession")
	if session != null:
		session.start_mode(session.MODE_NONE)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _spawn_versus():
	_reset_versus_session()
	var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	# Rounds open with a 3-2-1 countdown (2026-10-10); these cases start at GO.
	scene._model.tick(scene.COUNTDOWN_SECONDS + 0.1)
	await _tree().process_frame
	await _tree().process_frame
	return scene


static func _case_versus_sfx_mapping_matches_classic(ctx: Dictionary) -> void:
	var scene = await _spawn_versus()
	var ok: bool = scene != null
	if ok:
		var events: Array[String] = scene.SFX_EVENTS
		var players: Dictionary = scene._sfx
		# The classic handling set, plus what only a battle has.
		for event: String in VERSUS_SFX_EVENTS + ["tspin", "combo", "attack", "garbage", "countdown", "go", "ko", "win", "lose"]:
			var stream_player: AudioStreamPlayer = players.get(event) as AudioStreamPlayer
			if not events.has(event) or stream_player == null:
				ok = false
				continue
			ok = ok and stream_player.bus == "SFX" and stream_player.stream == ResourcePack.sound(event)
			ok = ok and absf(stream_player.volume_db - ResourcePack.sound_volume(event)) < 0.01
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_versus_session()
	_case(ctx, "versus_sfx_mapping_matches_classic_set", ok)


static func _case_versus_lock_sfx_on_non_clearing_lock(ctx: Dictionary) -> void:
	var scene = await _spawn_versus()
	var ok: bool = scene != null
	if ok:
		var side: int = VersusBattle.Side.PLAYER
		scene._model.debug_force_piece(side, 1, 0, Vector2i(3, Board.BOARD_HEIGHT - 2), false, 0)
		await _tree().process_frame
		await _tree().process_frame
		(scene._sfx["lock"] as AudioStreamPlayer).stop()
		# Revised 2026-10-10: sounds follow the model's lock events, so a
		# hard-drop lock plays "hard_drop" and "lock" belongs to the gravity
		# lock (the non-hard path driven here).
		scene._model.debug_lock_now(side, false)
		await _tree().process_frame
		var lock_player: AudioStreamPlayer = scene._sfx["lock"]
		ok = lock_player.playing and scene._model.lines(side) == 0
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_versus_session()
	_case(ctx, "versus_lock_sfx_on_non_clearing_lock", ok)


static func _case_versus_hard_drop_sfx_via_input(ctx: Dictionary) -> void:
	var scene = await _spawn_versus()
	var ok: bool = scene != null
	if ok:
		scene._model.debug_force_piece(VersusBattle.Side.PLAYER, 1, 0, Vector2i(3, Board.BOARD_HEIGHT - 2), false, 0)
		await _tree().process_frame
		(scene._sfx["hard_drop"] as AudioStreamPlayer).stop()
		Input.action_press("hard_drop")
		await _tree().process_frame
		Input.action_release("hard_drop")
		var hard_drop_player: AudioStreamPlayer = scene._sfx["hard_drop"]
		ok = hard_drop_player.playing
		await _tree().process_frame
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_versus_session()
	_case(ctx, "versus_hard_drop_sfx_fires_from_real_input", ok)


static func _case_versus_clear_sfx_on_line_clear(ctx: Dictionary) -> void:
	var scene = await _spawn_versus()
	var ok: bool = scene != null
	if ok:
		var side: int = VersusBattle.Side.PLAYER
		var board: Board = scene._model.board(side)
		for col: int in range(2, Board.BOARD_WIDTH):
			board.set_cell(Vector2i(col, Board.BOARD_HEIGHT - 1), 1)
		scene._model.debug_force_piece(side, 1, 0, Vector2i(0, Board.BOARD_HEIGHT - 3), false, 0)
		await _tree().process_frame
		(scene._sfx["clear"] as AudioStreamPlayer).stop()
		(scene._sfx["tetris"] as AudioStreamPlayer).stop()
		Input.action_press("hard_drop")
		await _tree().process_frame
		Input.action_release("hard_drop")
		await _tree().process_frame
		var clear_player: AudioStreamPlayer = scene._sfx["clear"]
		ok = clear_player.playing and scene._model.lines(side) == 1
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_versus_session()
	_case(ctx, "versus_clear_sfx_on_line_clear", ok)



