class_name BgmDirector
extends Node
## Plays the pack's playlist: one song after another in random order, each as
## often as the others, and each sped up as a stack grows, one small step at
## a time.
##
## A song (ResourcePack.playlist()) is a ladder of tracks that are the same
## music bar for bar at rising tempos, the calm one first. The height of the
## tallest stack picks a rung; the music walks there one rung per bar, each
## step taken on a bar line and landing on the same point of the tune in the
## next track under a short cross-fade - an accelerando, not a jump.
##
## A track holds its song once through and then rings out. Where its bars
## end the next song starts on the same rung, in time, while the old track's
## ringing dies away over it: changing songs is the same as playing on. The
## order is the player's choice (set_shuffle, remembered): a shuffled bag -
## every song once before any comes again, never the same one twice in a
## row - or the playlist as it is written, round and round. A pack whose
## music is a single looping stream (the older "music" section) just goes
## round.
##
## The scene reports the stack height every frame through update_pressure().

## Rows of stack (plus incoming garbage) up to which the calm track plays, and
## from which the top of the ladder does; the rungs between are spread evenly.
const CALM_ROWS: int = 8
const DANGER_ROWS: int = 16
const FADE_SECONDS: float = 0.35
const SILENT_DB: float = -60.0
## The next song is started when less than this is left of the bars. A
## started stream is heard from the next block the audio driver mixes, so
## the change lands within about a hundredth of a second of the bar line
## (tools/bgm_smoke.gd measures it).
const HANDOFF_SECONDS: float = 0.004
const CONFIG_SECTION: String = "Music"
const CONFIG_SHUFFLE: String = "Shuffle"
const CONFIG_VOLUME: String = "Volume"

var _bus: StringName = &"BGM"
var _songs: Array = []
## Songs still to come in this round of the shuffle, and the one drawn next.
var _bag: Array[int] = []
var _shuffle: bool = true
## The player's own volume for the music (0..1, on top of each song's level)
## and whether the player paused it.
var _volume: float = 1.0
var _paused: bool = false
var _song: int = -1
var _coming: int = -1
## Files of the coming song still to be read, one a frame.
var _warming: Array[String] = []
## The ladder of the song that plays, calm first: {player, bpm}.
var _tracks: Array[Dictionary] = []
var _db: float = 0.0
var _beats: float = 4.0
var _bars: int = 0
var _offset: float = 0.0
## The rung that plays, the one the stack asks for, and the one fading out.
var _level: int = 0
var _target: int = 0
var _previous: int = 0
## Seconds until the pending step (the next bar line); negative when none.
var _switch_in: float = -1.0
var _fade: float = 1.0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


## Starts the music on `bus` with a song picked at random.
func setup(bus: StringName = &"BGM") -> void:
	_bus = bus
	_songs = ResourcePack.playlist()
	_random.randomize()
	_shuffle = bool(PlayerConfig.get_config(CONFIG_SECTION, CONFIG_SHUFFLE, true))
	_volume = clampf(float(PlayerConfig.get_config(CONFIG_SECTION, CONFIG_VOLUME, 1.0)), 0.0, 1.0)
	if _songs.is_empty():
		return
	_coming = _draw()
	_start_song(0)


## Whether the songs come in random order (else in the playlist's own).
func shuffled() -> bool:
	return _shuffle


## Random order or the playlist's own, from the next song on. `remember`
## keeps the choice for the next games.
func set_shuffle(on: bool, remember: bool = true) -> void:
	_shuffle = on
	if remember:
		PlayerConfig.set_config(CONFIG_SECTION, CONFIG_SHUFFLE, on)
	if _songs.is_empty():
		return
	_bag.clear()
	_coming = _draw()
	_warming = []
	for track: Dictionary in _songs[_coming]["tracks"]:
		_warming.append(String(track["file"]))


## The music's volume as the player set it (0..1; 1 is each song's own level).
func volume() -> float:
	return _volume


func set_volume(value: float, remember: bool = true) -> void:
	_volume = clampf(value, 0.0, 1.0)
	if remember:
		PlayerConfig.set_config(CONFIG_SECTION, CONFIG_VOLUME, _volume)
	if _song >= 0:
		_db = _song_db()
		if not _tracks.is_empty():
			_apply_fade()


## Whether the player paused the music.
func paused() -> bool:
	return _paused


## Stops the music where it is, or lets it go on from there.
func set_paused(on: bool) -> void:
	_paused = on
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stream_paused = on


## Titles of the playlist's songs, in its order.
func song_titles() -> PackedStringArray:
	var titles: PackedStringArray = []
	for listed: Dictionary in _songs:
		titles.append(String(listed["title"]))
	return titles


## Plays song `index` of the playlist now, on the rung that plays; the order
## carries on after it.
func play_song(index: int) -> void:
	if index < 0 or index >= _songs.size():
		return
	_coming = index
	_bag.erase(index)
	_start_song(_level)


## The level the playing song is played at: its own, turned down by the
## player's volume.
func _song_db() -> float:
	return float(_songs[_song]["volume_db"]) + linear_to_db(maxf(_volume, 0.0001))


func song_count() -> int:
	return _songs.size()


## Index (in the pack's playlist) and title of the song that plays.
func song() -> int:
	return _song


func song_title() -> String:
	return String(_songs[_song]["title"]) if _song >= 0 else ""


## Beats per minute of the track that plays (0 without music).
func tempo() -> float:
	return float(_tracks[_level]["bpm"]) if not _tracks.is_empty() else 0.0


## The song that follows the one playing.
func coming_song() -> int:
	return _coming


## Rungs of the playing song's ladder (1 when it has only the calm track).
func level_count() -> int:
	return _tracks.size()


## The rung that plays now (0 = calm).
func level() -> int:
	return _level


## The rung the reported stack height asks for.
func target_level() -> int:
	return _target


func player(index: int) -> AudioStreamPlayer:
	return _tracks[index]["player"]


## The player that carries the music now; null without music.
func current() -> AudioStreamPlayer:
	return player(_level) if not _tracks.is_empty() else null


## Reports the tallest stack in play (rows, incoming garbage included).
func update_pressure(rows: int) -> void:
	_target = level_for_rows(rows, _target)


## The rung for a stack of `rows`, coming from rung `current_level`: up as
## soon as a rung's height is reached, down only once the stack is a whole
## rung lower, so a stack hovering at a boundary does not make the music waver.
func level_for_rows(rows: int, current_level: int) -> int:
	var top: int = _tracks.size() - 1
	if top <= 0:
		return 0
	var want: float = float(rows - CALM_ROWS) / float(DANGER_ROWS - CALM_ROWS) * float(top)
	if floori(want) > current_level:
		return mini(top, floori(want))
	if want <= float(current_level - 1):
		return maxi(0, ceili(want))
	return current_level


## Seconds the bars of the playing song take on rung `index` (0 for a stream
## that loops by itself).
func body_seconds(index: int) -> float:
	return float(_bars) * _beats * 60.0 / float(_tracks[index]["bpm"])


## Whether the bars of the playing song are over `position` seconds into its
## track `index` (never, for a stream that loops by itself).
func bars_over(position: float, index: int) -> bool:
	return _bars > 0 and body_seconds(index) - position <= HANDOFF_SECONDS


## Ends the playing song here and starts the next one of the shuffle.
func next_song() -> void:
	if _songs.is_empty():
		return
	_start_song(_level)


func _process(delta: float) -> void:
	if _tracks.is_empty() or _paused:
		return
	if not _warming.is_empty():
		ResourcePack.music_file(_warming.pop_back())
	# The bars are over: the next song comes in on the same rung.
	if current().playing and bars_over(_tune_position(_level), _level):
		_start_song(_level)
		return
	if _tracks.size() < 2:
		return
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / FADE_SECONDS)
		_apply_fade()
	if _switch_in >= 0.0:
		_switch_in -= delta
		if _switch_in <= 0.0:
			_switch_in = -1.0
			if _target != _level:
				_step(_level + signi(_target - _level))
		return
	var wanted: int = mini(_target, _tracks.size() - 1)
	if wanted != _level and _fade >= 1.0:
		# Wait for the bar line the playing track is about to reach.
		var bar: float = 60.0 * _beats / float(_tracks[_level]["bpm"])
		_switch_in = bar - fposmod(_tune_position(_level), bar)


## The next song of the shuffle: every song once a round, in random order,
## and not the one that has just played.
func _draw() -> int:
	if not _shuffle:
		# The one after the song that plays (the first, before any does).
		return (_song + 1) % _songs.size()
	if _bag.is_empty():
		for index: int in _songs.size():
			_bag.append(index)
		for index: int in range(_bag.size() - 1, 0, -1):
			var other: int = _random.randi_range(0, index)
			var held: int = _bag[index]
			_bag[index] = _bag[other]
			_bag[other] = held
		# The bag is drawn from its end.
		if _bag.size() > 1 and _bag[-1] == _song:
			_bag[-1] = _bag[0]
			_bag[0] = _song
	return _bag.pop_back()


## Starts the coming song on rung `level` (or its highest), leaving the one
## that played to ring out.
func _start_song(on_level: int) -> void:
	# A song asked for while the music was paused plays.
	if _paused:
		set_paused(false)
	for index: int in _tracks.size():
		var old: AudioStreamPlayer = _tracks[index]["player"]
		if index == _level and old.playing and _bars > 0:
			# Its reverb and echo die away over the new song.
			old.finished.connect(old.queue_free)
		else:
			old.stop()
			old.queue_free()
	_song = _coming
	_coming = _draw()
	var playing: Dictionary = _songs[_song]
	_db = _song_db()
	_beats = float(playing["beats"])
	_bars = int(playing["bars"])
	_offset = float(playing["offset"])
	_tracks = []
	for track: Dictionary in playing["tracks"]:
		var stream: AudioStream = ResourcePack.music_file(String(track["file"]))
		if stream == null:
			continue
		# Every stream type the packs support loops through this property.
		if "loop" in stream:
			stream.set("loop", bool(playing["loops"]))
		if _tracks.is_empty() and "loop_offset" in stream:
			stream.set("loop_offset", _offset)
		var added: AudioStreamPlayer = AudioStreamPlayer.new()
		added.stream = stream
		added.bus = _bus
		added.volume_db = SILENT_DB
		add_child(added)
		_tracks.append({"player": added, "bpm": float(track["bpm"])})
	_warming = []
	for track: Dictionary in _songs[_coming]["tracks"]:
		_warming.append(String(track["file"]))
	_switch_in = -1.0
	_fade = 1.0
	if _tracks.is_empty():
		return
	_level = clampi(on_level, 0, _tracks.size() - 1)
	_previous = _level
	var starting: AudioStreamPlayer = _tracks[_level]["player"]
	starting.volume_db = _db
	# play() reports "Playback can only happen when a node is inside the
	# scene tree" when the scene is detached (tests call _ready() directly).
	if starting.is_inside_tree():
		starting.play()


## Where track `index` is in the song, in its own seconds past its intro.
func _tune_position(index: int) -> float:
	var playing: AudioStreamPlayer = _tracks[index]["player"]
	if not playing.playing:
		return 0.0
	var position: float = playing.get_playback_position() + AudioServer.get_time_since_last_mix()
	return maxf(0.0, position - (_offset if index == 0 else 0.0))


## The stream position in track `to` of the point of the song that is
## `position` seconds past the intro of track `from`.
func mapped_position(position: float, from: int, to: int) -> float:
	var offset: float = _offset if to == 0 else 0.0
	var target: float = position * float(_tracks[from]["bpm"]) / float(_tracks[to]["bpm"])
	var body: float = body_seconds(to)
	if _bars <= 0:
		var stream: AudioStream = (_tracks[to]["player"] as AudioStreamPlayer).stream
		body = (stream.get_length() if stream != null else 0.0) - offset
	if body > 0.0:
		target = fposmod(target, body)
	return offset + target


func _step(to: int) -> void:
	var incoming: AudioStreamPlayer = _tracks[to]["player"]
	var target: float = mapped_position(_tune_position(_level), _level, to)
	# A rung still fading out from the step before is cut: two tracks at most.
	if _fade < 1.0 and _previous != to:
		_rest(_previous)
	incoming.volume_db = SILENT_DB
	if incoming.is_inside_tree():
		incoming.play(target)
	_previous = _level
	_level = to
	_fade = 0.0
	_apply_fade()


## Equal-power cross-fade from the previous rung to the playing one.
func _apply_fade() -> void:
	var turn: float = _fade * PI / 2.0
	player(_level).volume_db = maxf(SILENT_DB, _db + linear_to_db(maxf(sin(turn), 0.0001)))
	if _previous == _level:
		return
	player(_previous).volume_db = maxf(SILENT_DB, _db + linear_to_db(maxf(cos(turn), 0.0001)))
	if _fade >= 1.0:
		_rest(_previous)


## Silences a rung that is no longer heard.
func _rest(index: int) -> void:
	var resting: AudioStreamPlayer = player(index)
	resting.volume_db = SILENT_DB
	resting.stop()
