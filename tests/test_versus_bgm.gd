extends SceneTree
## Versus BGM lifecycle (S5 versus-bgm, G-BATTLE-EXPERIENCE-FIX O-01/BS-01).
##
## Asserts the headless-testable surface of the goal:
##   a) entering the versus scene starts a song of the playlist on the BGM bus,
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

const BGM_DIR: String = "res://packs/default/music/"
const LEGACY_PACK_ID: String = "_test_one_song"
const LEGACY_PACK_DIR: String = "user://packs/_test_one_song"
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
	await _case_songs_follow_each_other_shuffled(ctx)
	await _case_single_looping_song_pack(ctx)
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
# a) Entering the versus scene immediately plays a song of the playlist.
static func _case_plays_on_enter(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = scene != null
	var player: Variant = scene.get("_bgm_player") if ok else null
	if not (player is AudioStreamPlayer):
		ok = false
	else:
		var bgm: AudioStreamPlayer = player
		ok = bgm.playing and bgm.bus == "BGM"
		# A song is played once through; the next one follows it.
		var ogg: AudioStreamOggVorbis = bgm.stream as AudioStreamOggVorbis
		ok = ok and ogg != null and not ogg.loop and ogg.resource_path.begins_with(BGM_DIR)
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "versus_enter_starts_a_playlist_song_on_bgm_bus", ok)


# ---------------------------------------------------------------------------
# a2) The tempo ladder (BgmDirector; revised 2026-10-11, owner: a gradual
#     change instead of a jump; 120 BPM at least and 180 when a stack is
#     about to top out): every song of the playlist is six tracks, the same
#     bars at rising tempos, and a growing stack walks the music up one track
#     per bar line, at the same point of the tune - and down again, without
#     wavering at a boundary.
static func _case_music_walks_the_tempo_ladder(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = scene != null and scene.get("_bgm_director") is BgmDirector
	var songs: Array = ResourcePack.playlist()
	ok = ok and songs.size() >= 2
	for song: Dictionary in songs:
		var tracks: Array = song["tracks"]
		ok = ok and tracks.size() == 6 and not bool(song["loops"]) and int(song["bars"]) > 8
		ok = ok and absf(float(tracks[0]["bpm"]) - 120.0) < 0.1 and absf(float(tracks[-1]["bpm"]) - 180.0) < 0.1
		var last_bpm: float = 0.0
		for track: Dictionary in tracks:
			var bpm: float = float(track["bpm"])
			var ogg: AudioStreamOggVorbis = ResourcePack.music_file(String(track["file"])) as AudioStreamOggVorbis
			# A small step each time: no rung is more than a tenth faster than the last.
			ok = ok and ogg != null and bpm > last_bpm and (last_bpm == 0.0 or bpm / last_bpm <= 1.101)
			last_bpm = bpm
			if ogg == null:
				continue
			# Bar for bar the same music in every track, then three seconds
			# in which it rings out.
			var beats: float = (ogg.get_length() - 3.0) * bpm / 60.0
			ok = ok and absf(beats - float(int(song["bars"]) * int(song["beats"]))) < 0.05
	if ok:
		var director: BgmDirector = scene.get("_bgm_director")
		director.set_volume(1.0, false)
		var top: int = director.level_count() - 1
		var calm: AudioStreamPlayer = director.player(0)
		var level_db: float = float(songs[director.song()]["volume_db"])
		var bpm_calm: float = float(songs[director.song()]["tracks"][0]["bpm"])
		var bpm_top: float = float(songs[director.song()]["tracks"][top]["bpm"])
		ok = top == 5 and director.level() == 0 and director.current() == calm and scene.get("_bgm_player") == calm and calm.playing
		for i: int in range(1, top + 1):
			ok = ok and not director.player(i).playing and director.player(i).get_parent() == director and director.player(i).bus == "BGM"
		ok = ok and absf(director.mapped_position(10.0, 0, top) - 10.0 * bpm_calm / bpm_top) < 0.001 \
			and absf(director.mapped_position(8.0, top, 0) - 8.0 * bpm_top / bpm_calm) < 0.001
		# Past the end of the tune the position wraps into the bars.
		ok = ok and absf(director.mapped_position(director.body_seconds(0) + 1.0, 0, 0) - 1.0) < 0.01
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
		ok = ok and scene.get("_bgm_player") == director.player(1)
		# Mid-fade both are heard, neither at full level.
		director._process(BgmDirector.FADE_SECONDS / 2.0)
		ok = ok and director.player(1).volume_db < level_db \
			and calm.volume_db > BgmDirector.SILENT_DB and calm.volume_db < level_db
		director._process(1.0)
		ok = ok and is_equal_approx(director.player(1).volume_db, level_db) and not calm.playing
		var steps: int = 1
		for _i: int in 40:
			var before: int = director.level()
			director._process(1.0)
			ok = ok and director.level() - before <= 1 and director.level() >= before
			steps += director.level() - before
		ok = ok and director.level() == top and steps == top and director.player(top).playing \
			and is_equal_approx(director.player(top).volume_db, level_db)
		for i: int in top:
			ok = ok and not director.player(i).playing
		# The stack is gone: down again the same way.
		director.update_pressure(0)
		director._process(0.01)
		director._process(2.1)
		ok = ok and director.level() == top - 1
		for _i: int in 40:
			director._process(1.0)
		ok = ok and director.level() == 0 and calm.playing and is_equal_approx(calm.volume_db, level_db)
		for i: int in range(1, top + 1):
			ok = ok and not director.player(i).playing
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "music_walks_the_tempo_ladder_a_bar_at_a_time", ok)
	_case(ctx, "danger_track_switches_on_the_beat_and_back", ok)


# ---------------------------------------------------------------------------
# a3) The playlist (2026-10-11, owner: more songs, played at random with
#     equal weight, the change from one to the next made good): where a
#     song's bars end the next one starts on the same rung while the old
#     track rings out; the order is a shuffled bag - every song once a round,
#     never the same one twice in a row.
static func _case_songs_follow_each_other_shuffled(ctx: Dictionary) -> void:
	var scene: Node = await _spawn_versus()
	var ok: bool = scene != null and scene.get("_bgm_director") is BgmDirector
	if ok:
		var director: BgmDirector = scene.get("_bgm_director")
		director.set_shuffle(true, false)
		director.set_volume(1.0, false)
		var count: int = director.song_count()
		ok = count == ResourcePack.playlist().size() and count >= 2
		# The change keeps the rung, and the song that ends is left to ring.
		director.update_pressure(BgmDirector.CALM_ROWS + 2)
		director._process(0.01)
		director._process(2.1)
		director._process(1.0)
		var ending: AudioStreamPlayer = director.current()
		var coming: int = director.coming_song()
		ok = ok and director.level() == 1 and coming != director.song()
		# (This is the change at the end of the bars: the old track rings out.)
		director._start_song(director.level(), true)
		ok = ok and director.song() == coming and director.level() == 1 and director.level_count() == 6
		ok = ok and director.current() != ending and director.current().playing and is_instance_valid(ending) and ending.playing
		# A song the player cuts short (next, or another one picked) does not
		# play on over the new one: it fades away and is gone.
		var cut: AudioStreamPlayer = director.current()
		var after_cut: int = director.coming_song()
		director.next_song()
		coming = after_cut
		ok = ok and director.song() == coming and director.current() != cut and director.current().playing
		await _tree().create_timer(BgmDirector.CUT_SECONDS + 0.2).timeout
		ok = ok and not is_instance_valid(cut)
		ok = ok and director.state() == BgmDirector.State.PLAYING and director.state_name() == "PLAYING"
		ok = ok and is_equal_approx(director.current().volume_db, float(ResourcePack.playlist()[coming]["volume_db"]))
		ok = ok and director.song_title() == String(ResourcePack.playlist()[coming]["title"]) and director.song_title() != ""
		# The end of the bars is what triggers it: nothing while there is
		# music left, the change once there is none.
		var before: int = director.song()
		director._process(0.016)
		ok = ok and director.song() == before
		var body: float = director.body_seconds(1)
		ok = ok and body > 20.0 and not director.bars_over(0.0, 1) and not director.bars_over(body - 0.5, 1) 			and director.bars_over(body - 0.002, 1) and director.bars_over(body + 1.0, 1)
		# Three rounds of the shuffle, from the start of a round: each one
		# plays every song once.
		for _i: int in count * 2:
			if director._bag.size() == count - 1:
				break
			director.next_song()
		ok = ok and director._bag.size() == count - 1
		var played: Array[int] = []
		var previous: int = director.song()
		for _i: int in count * 3:
			director.next_song()
			ok = ok and director.song() != previous
			previous = director.song()
			played.append(previous)
		for song: int in count:
			ok = ok and played.count(song) == 3
		# The other order (the corner player's button switches): the playlist
		# as it is written, round and round, from the song that plays.
		ok = ok and director.shuffled()
		director.set_shuffle(false, false)
		ok = ok and not director.shuffled() and director.coming_song() == (director.song() + 1) % count
		for _i: int in count + 2:
			var following: int = (director.song() + 1) % count
			director.next_song()
			ok = ok and director.song() == following
		var corner: NowPlaying = scene.find_child("NowPlaying", true, false) as NowPlaying
		ok = ok and corner != null
		if corner != null:
			corner._refresh()
			ok = ok and corner.order_text() == TranslationServer.translate("IN ORDER")
			ok = ok and corner.title() == TranslationServer.translate(director.song_title())
			# The press is remembered (the player's own choice is put back after).
			var kept: Variant = PlayerConfig.get_config(BgmDirector.CONFIG_SECTION, BgmDirector.CONFIG_SHUFFLE, null)
			corner._on_order_pressed()
			ok = ok and director.shuffled() and corner.order_text() == TranslationServer.translate("SHUFFLE")
			ok = ok and PlayerConfig.get_config(BgmDirector.CONFIG_SECTION, BgmDirector.CONFIG_SHUFFLE, null) == true
			if kept == null:
				PlayerConfig.erase_section_key(BgmDirector.CONFIG_SECTION, BgmDirector.CONFIG_SHUFFLE)
			else:
				PlayerConfig.set_config(BgmDirector.CONFIG_SECTION, BgmDirector.CONFIG_SHUFFLE, kept)
			# The player's window (2026-10-11, owner: laid out like a grand
			# strategy game's music player): the playlist as a list - a click
			# plays that song - with pause, next and the volume.
			ok = ok and not corner.window_open() and corner.listed().size() == count
			corner._on_open_pressed()
			ok = ok and corner.window_open()
			var wanted: int = (director.song() + 3) % count
			var rung: int = director.level()
			corner._on_row_pressed(wanted)
			ok = ok and director.song() == wanted and director.level() == rung and director.current().playing
			ok = ok and corner.title() == TranslationServer.translate(director.song_title()) \
				and corner.listed()[wanted].ends_with(corner.title())
			var before_next: int = director.song()
			corner._on_next_pressed()
			ok = ok and director.song() != before_next
			# The song that plays, clicked: it starts again - the same players,
			# nothing new on top of it.
			var same: AudioStreamPlayer = director.current()
			var players: int = director.get_child_count()
			corner._on_row_pressed(director.song())
			ok = ok and director.current() == same and same.playing and director.get_child_count() == players \
				and director.position_seconds() < 0.5
			ok = ok and director.length_seconds() > 20.0 and director.progress() >= 0.0 and director.progress() < 0.05
			ok = ok and NowPlaying._clock(75.4) == "1:15"
			corner._refresh()
			ok = ok and corner.status().begins_with(TranslationServer.translate("PLAYING")) and corner.status().contains(" / ")
			corner._on_pause_pressed()
			ok = ok and director.paused() and director.current().stream_paused
			ok = ok and director.state() == BgmDirector.State.PAUSED
			corner._refresh()
			ok = ok and corner.status().begins_with(TranslationServer.translate("PAUSED"))
			var held: int = director.song()
			director._process(1.0)
			ok = ok and director.song() == held
			corner._on_pause_pressed()
			ok = ok and not director.paused() and not director.current().stream_paused
			ok = ok and director.state() == BgmDirector.State.PLAYING
			# A step of the tempo is its own state until the cross-fade is done.
			director.update_pressure(BgmDirector.DANGER_ROWS)
			director._process(0.01)
			director._process(2.1)
			ok = ok and director.state() == BgmDirector.State.STEPPING and director.state_name() == "CHANGING TEMPO"
			director.update_pressure(0)
			director._target = director.level()
			director._process(1.0)
			ok = ok and director.state() == BgmDirector.State.PLAYING
			# The volume turns the song's own level down; full is that level.
			var own_db: float = float(ResourcePack.playlist()[director.song()]["volume_db"])
			ok = ok and is_equal_approx(director.volume(), 1.0) and is_equal_approx(director.current().volume_db, own_db)
			director.set_volume(0.5, false)
			ok = ok and absf(director.current().volume_db - (own_db + linear_to_db(0.5))) < 0.01
			director.set_volume(1.0, false)
			ok = ok and is_equal_approx(director.current().volume_db, own_db)
			corner._on_open_pressed()
			ok = ok and not corner.window_open()
	if scene != null:
		scene.free()
	await _tree().process_frame
	_reset_session()
	_case(ctx, "songs_follow_each_other_in_a_shuffled_bag", ok)


# ---------------------------------------------------------------------------
# a4) A pack that names its music the older way - one stream, "game", with
#     faster versions - still plays: that stream loops by itself.
static func _case_single_looping_song_pack(ctx: Dictionary) -> void:
	var file: String = String(ResourcePack.playlist()[0]["tracks"][0]["file"])
	var fast: String = String(ResourcePack.playlist()[0]["tracks"][-1]["file"])
	var enabled: Array = ResourcePack.enabled_ids()
	DirAccess.make_dir_recursive_absolute(LEGACY_PACK_DIR)
	var manifest: FileAccess = FileAccess.open(LEGACY_PACK_DIR + "/pack.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"format": 1,
		"name": "One Song",
		"music": {
			"game": {"file": file, "volume_db": -9, "bpm": 120, "loop_offset": 4.0},
			"game_danger": {"file": fast, "bpm": 180},
		},
	}))
	manifest.close()
	ResourcePack.set_enabled([LEGACY_PACK_ID], false)
	var songs: Array = ResourcePack.playlist()
	var ok: bool = songs.size() == 1 and bool(songs[0]["loops"]) and (songs[0]["tracks"] as Array).size() == 2
	var scene: Node = await _spawn_versus()
	if ok and scene != null:
		var director: BgmDirector = scene.get("_bgm_director")
		var ogg: AudioStreamOggVorbis = director.current().stream as AudioStreamOggVorbis
		ok = director.song_count() == 1 and director.level_count() == 2 and director.current().playing
		ok = ok and ogg != null and ogg.loop and is_equal_approx(ogg.loop_offset, 4.0) and ogg.resource_path == file
		ok = ok and is_equal_approx(director.current().volume_db, -9.0)
		# It goes round by itself: no change of song is waiting at any point.
		director._process(0.016)
		ok = ok and director.song() == 0 and director.current().stream == ogg
	else:
		ok = false
	if scene != null:
		scene.free()
	await _tree().process_frame
	ResourcePack.set_enabled(enabled, false)
	DirAccess.remove_absolute(LEGACY_PACK_DIR + "/pack.json")
	DirAccess.remove_absolute(LEGACY_PACK_DIR)
	# The playlist's streams are shared: give them back as the playlist wants them.
	var shared: AudioStream = ResourcePack.music_file(file)
	if shared != null:
		shared.set("loop", false)
		shared.set("loop_offset", 0.0)
	_reset_session()
	_case(ctx, "pack_with_one_looping_stream_still_plays", ok)


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
			if music_player.playing or (stream != null and stream.resource_path.begins_with(BGM_DIR)):
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
