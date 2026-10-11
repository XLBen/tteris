extends SceneTree
## Versus BGM lifecycle (S5 versus-bgm, G-BATTLE-EXPERIENCE-FIX O-01/BS-01).
##
## Asserts the headless-testable surface of the goal:
##   a) entering the versus scene starts the korobeiniki loop on the BGM bus,
##   b) the player is invisible to ProjectMusicController's adoption hook
##      (autoplay stays off and the bus is never "Music", the two gates of
##      _node_matches_checks) and the controller holds no adopted player,
##   c) the same player keeps playing across a round advance,
##   d) freeing the versus scene leaves no playing music player on the tree,
##   e) the main menu instantiates with no playing music player,
##   f) the defensive BGM-bus sidechain restore (sweep-report-v2 MINOR-1)
##      brings back exactly one SFX compressor when the bus has none.
## The classic-mode BGM regression is owned by tests/test_music.gd (run_all).

const MODULE_NAME: String = "versus_bgm"

const BGM_FILE: String = "res://assets/audio/bgm/korobeiniki-coldwar-synth.ogg"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/menus/main_menu/main_menu_with_animations.tscn"


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d versus bgm cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VERSUS BGM TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _case_plays_on_enter(ctx)
	await _case_not_adopted_by_music_controller(ctx)
	await _case_keeps_playing_across_rounds(ctx)
	await _case_music_walks_the_tempo_ladder(ctx)
	await _case_no_playing_player_after_scene_exit(ctx)
	await _case_main_menu_silent(ctx)
	await _case_bgm_bus_compressor_restored(ctx)
	await _tree().process_frame
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _reset_session() -> void:
	var session: Node = _tree().root.get_node_or_null(^"GameSession")
	if session != null:
		session.start_mode(session.MODE_NONE)


## Spawns the versus scene headless (the test_ai_realmatch precedent) with a
## clean GameSession, so the frozen defaults run.
static func _spawn_versus() -> Node:
	_reset_session()
	var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
	_tree().root.add_child(scene)
	await _tree().process_frame
	return scene


## Walks every playing AudioStreamPlayer on the tree. The ProjectUISound
## Controller autoload's own persistent one-shot click players are excluded:
## they are UI SFX owned by an autoload for the whole app lifetime (not
## scene-owned music), and earlier suite modules legitimately pressing buttons
## can leave one flagged playing. Every other player - ProjectMusicController's
## adopted player included - stays in scope.
static func _collect_playing_players(node: Node, into: Array) -> void:
	for child: Node in node.get_children():
		if node == _tree().root and child.name == &"ProjectUISoundController":
			continue
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			into.append(child)
		_collect_playing_players(child, into)


# ---------------------------------------------------------------------------
# a) Entering the versus scene immediately plays the korobeiniki loop.
static func _case_plays_on_enter(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = scene != null
	var player: Variant = scene.get("_bgm_player") if ok else null
	if not (player is AudioStreamPlayer):
		ok = false
	else:
		var bgm: AudioStreamPlayer = player
		ok = bgm.playing and bgm.bus == "BGM"
		var ogg: AudioStreamOggVorbis = bgm.stream as AudioStreamOggVorbis
		ok = ok and ogg != null and ogg.loop and ogg.resource_path == BGM_FILE
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "versus_enter_starts_looping_korobeiniki_on_bgm_bus", ok)


# ---------------------------------------------------------------------------
# a2) The tempo ladder (BgmDirector; revised 2026-10-11, owner: a gradual
#     change instead of a jump): the BGM loops its body past the intro, the
#     faster tracks are the same bars at rising tempos, and a growing stack
#     walks the music up one track per bar line, at the same point of the
#     tune - and down again, without wavering at a boundary.
static func _case_music_walks_the_tempo_ladder(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = scene != null and scene.get("_bgm_director") is BgmDirector
	if ok:
		var director: BgmDirector = scene.get("_bgm_director")
		var calm: AudioStreamPlayer = scene.get("_bgm_player")
		var keys: Array[String] = ["game", "game_rise_1", "game_rise_2", "game_rise_3", "game_rise_4", "game_danger"]
		var top: int = keys.size() - 1
		var offset: float = ResourcePack.music_number("game", "loop_offset", 0.0)
		ok = director.level_count() == keys.size() and director.player(0) == calm and director.level() == 0
		ok = ok and offset > 1.0 and is_equal_approx((calm.stream as AudioStreamOggVorbis).loop_offset, offset)
		var last_bpm: float = 0.0
		for i: int in (keys.size() if ok else 0):
			var player: AudioStreamPlayer = director.player(i)
			var ogg: AudioStreamOggVorbis = player.stream as AudioStreamOggVorbis
			var bpm: float = ResourcePack.music_number(keys[i], "bpm", 0.0)
			ok = ok and ogg != null and ogg.loop and player.bus == "BGM" and bpm > last_bpm
			# A small step each time: no rung is more than 6 % faster than the last.
			ok = ok and (i == 0 or bpm / last_bpm < 1.06)
			last_bpm = bpm
			if ogg == null:
				continue
			# Bar for bar the same music: 40 bars of four beats in every track.
			var beats: float = (ogg.get_length() - (offset if i == 0 else 0.0)) * bpm / 60.0
			ok = ok and absf(beats - 160.0) < 0.05
			if i > 0:
				ok = ok and not player.playing and player.get_parent() == director
		if ok:
			var calm_bpm: float = ResourcePack.music_number("game", "bpm", 0.0)
			ok = absf(director.mapped_position(10.0, 0, top) - 10.0 * calm_bpm / 150.0) < 0.001 \
				and absf(director.mapped_position(8.0, top, 0) - (offset + 8.0 * 150.0 / calm_bpm)) < 0.001
			# Past the end of the tune the position wraps into the body.
			ok = ok and absf(director.mapped_position(80.0 * 120.0 / calm_bpm + 1.0, 0, 0) - (offset + 1.0)) < 0.01
			# Height to rung: calm up to CALM_ROWS, the top from DANGER_ROWS, up
			# at once, down only a whole rung lower.
			ok = ok and director.level_for_rows(BgmDirector.CALM_ROWS, 0) == 0 \
				and director.level_for_rows(BgmDirector.CALM_ROWS + 1, 0) == 0 \
				and director.level_for_rows(BgmDirector.CALM_ROWS + 2, 0) == 1 \
				and director.level_for_rows(BgmDirector.DANGER_ROWS - 1, 0) == top - 1 \
				and director.level_for_rows(BgmDirector.DANGER_ROWS, 0) == top \
				and director.level_for_rows(40, 0) == top
			ok = ok and director.level_for_rows(12, 3) == 3 and director.level_for_rows(11, 3) == 2 \
				and director.level_for_rows(0, top) == 0
			# A stack at the top: the music gets there one rung per bar line.
			director.update_pressure(BgmDirector.DANGER_ROWS)
			ok = ok and director.target_level() == top
			director._process(0.01)
			ok = ok and director.level() == 0 and director._switch_in >= 0.0 and director._switch_in <= 2.01
			director._process(2.1)
			ok = ok and director.level() == 1 and director.player(1).playing and calm.playing
			# Mid-fade both are heard, neither at full level.
			director._process(BgmDirector.FADE_SECONDS / 2.0)
			ok = ok and director.player(1).volume_db < ResourcePack.music_volume("game_rise_1") \
				and calm.volume_db > BgmDirector.SILENT_DB and calm.volume_db < ResourcePack.music_volume("game")
			director._process(1.0)
			ok = ok and is_equal_approx(director.player(1).volume_db, ResourcePack.music_volume("game_rise_1")) \
				and is_equal_approx(calm.volume_db, BgmDirector.SILENT_DB)
			var steps: int = 1
			for _i: int in 40:
				var before: int = director.level()
				director._process(1.0)
				ok = ok and director.level() - before <= 1 and director.level() >= before
				steps += director.level() - before
			ok = ok and director.level() == top and steps == top and director.player(top).playing \
				and is_equal_approx(director.player(top).volume_db, ResourcePack.music_volume("game_danger"))
			for i: int in range(1, top):
				ok = ok and not director.player(i).playing
			# The stack is gone: down again the same way, and the calm stream,
			# which never stopped, is the one left playing.
			director.update_pressure(0)
			director._process(0.01)
			director._process(2.1)
			ok = ok and director.level() == top - 1
			for _i: int in 40:
				director._process(1.0)
			ok = ok and director.level() == 0 and calm.playing and is_equal_approx(calm.volume_db, ResourcePack.music_volume("game"))
			for i: int in range(1, keys.size()):
				ok = ok and not director.player(i).playing
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "music_walks_the_tempo_ladder_a_bar_at_a_time", ok)
	_case(ctx, "danger_track_switches_on_the_beat_and_back", ok)


# ---------------------------------------------------------------------------
# b) Leak mechanism closed: both adoption gates stay shut and the autoload
#    holds no adopted player carrying the versus stream.
static func _case_not_adopted_by_music_controller(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = true
	var player: Variant = scene.get("_bgm_player") if scene != null else null
	if not (player is AudioStreamPlayer):
		ok = false
	else:
		var bgm: AudioStreamPlayer = player
		ok = not bgm.autoplay and bgm.bus != "Music"
	var controller: Node = _tree().root.get_node_or_null(^"ProjectMusicController")
	if controller != null:
		var adopted: Variant = controller.get("music_stream_player")
		if adopted is AudioStreamPlayer:
			var music_player: AudioStreamPlayer = adopted
			var stream: AudioStream = music_player.stream
			if music_player.playing or (stream != null and stream.resource_path == BGM_FILE):
				(ctx["lines"] as Array).append("DETAIL: music controller holds %s playing=%s" % [
					music_player.name, str(music_player.playing)])
				ok = false
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "bgm_player_invisible_to_music_controller_adoption", ok)


# ---------------------------------------------------------------------------
# c) Cross-round continuity: the exact inter-round path (_advance_round ->
#    _model.start_round) never touches the scene tree, so the very same
#    player object must still be playing afterwards.
static func _case_keeps_playing_across_rounds(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = true
	var player: Variant = scene.get("_bgm_player") if scene != null else null
	if not (player is AudioStreamPlayer):
		ok = false
	else:
		var bgm: AudioStreamPlayer = player
		scene._advance_round()
		await _tree().process_frame
		ok = is_instance_valid(bgm) and scene.get("_bgm_player") == bgm \
			and bgm.playing and bgm.bus == "BGM"
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "bgm_keeps_playing_across_round_advance", ok)


# ---------------------------------------------------------------------------
# d) Leaving the versus scene (scene switch frees it) leaves no player
#    playing anywhere on the tree (UI-sound autoload one-shots excluded, see
#    _collect_playing_players) - no adoption, no leak.
static func _case_no_playing_player_after_scene_exit(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = scene != null and scene.get("_bgm_player") is AudioStreamPlayer
	if scene != null:
		scene.free()
	await _tree().process_frame
	var playing: Array = []
	_collect_playing_players(_tree().root, playing)
	for stray: AudioStreamPlayer in playing:
		(ctx["lines"] as Array).append("DETAIL: still playing after versus exit: %s (%s)" % [
			stray.name, str(stray.get_path())])
	ok = ok and playing.is_empty()
	_case(ctx, "no_playing_player_left_after_versus_scene_exit", ok)


# ---------------------------------------------------------------------------
# e) Menu-silent face: the main menu instantiates headless with no playing
#    music player of its own (test_menu already proves the instantiation).
static func _case_main_menu_silent(ctx: Dictionary) -> void:
	_reset_session()
	var packed: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	var ok: bool = packed != null and packed.can_instantiate()
	if ok:
		var menu: Node = packed.instantiate()
		_tree().root.add_child(menu)
		await _tree().process_frame
		var playing: Array = []
		_collect_playing_players(menu, playing)
		for stray: AudioStreamPlayer in playing:
			(ctx["lines"] as Array).append("DETAIL: menu player playing: %s" % stray.name)
		ok = playing.is_empty()
		menu.free()
		await _tree().process_frame
	_reset_session()
	_case(ctx, "main_menu_instantiates_with_no_playing_music_player", ok)


# ---------------------------------------------------------------------------
# f) Defensive bus repair (sweep-report-v2 MINOR-1, owner decision "fix"):
#    with a stripped BGM bus (no effects), a fresh versus scene must restore
#    exactly one SFX sidechain compressor. With the shipped
#    default_bus_layout.tres this path never fires, so test_music's
#    compressors==1 freeze is unaffected either way.
static func _case_bgm_bus_compressor_restored(ctx: Dictionary) -> void:
	var bgm_bus: int = AudioServer.get_bus_index("BGM")
	var ok: bool = bgm_bus != -1
	var scene: Node = null
	if ok:
		while AudioServer.get_bus_effect_count(bgm_bus) > 0:
			AudioServer.remove_bus_effect(bgm_bus, 0)
		ok = AudioServer.get_bus_effect_count(bgm_bus) == 0
		scene = await _spawn_versus()
		var compressors: int = 0
		var sidechain_ok: bool = true
		for i in AudioServer.get_bus_effect_count(bgm_bus):
			var effect: AudioEffect = AudioServer.get_bus_effect(bgm_bus, i)
			if effect is AudioEffectCompressor:
				compressors += 1
				if String((effect as AudioEffectCompressor).sidechain) != "SFX":
					sidechain_ok = false
		ok = ok and compressors == 1 and sidechain_ok
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "bgm_bus_compressor_restored_when_missing", ok)
