class_name BgmDirector
extends Node
## Speeds the game's music up as a stack grows, one small step at a time.
##
## The pack's music is a ladder of tracks that are the same music bar for bar
## at rising tempos: "game" (the calm one, which may have an intro before its
## `loop_offset`), then "game_rise_1", "game_rise_2", ... as far as the pack
## goes, then "game_danger" on top. Each names its `bpm`. The height of the
## tallest stack picks a rung; the music walks there one rung per bar, each
## step taken on a bar line and landing on the same point of the tune in the
## next track under a short cross-fade - an accelerando, not a jump. A pack
## with only "game" never changes tempo.
##
## The scene owns the calm player (it is the one stream that plays from launch)
## and reports the stack height every frame through update_pressure().

## Rows of stack (plus incoming garbage) up to which the calm track plays, and
## from which the top of the ladder does; the rungs between are spread evenly.
const CALM_ROWS: int = 8
const DANGER_ROWS: int = 16
const BEATS_PER_BAR: float = 4.0
const FADE_SECONDS: float = 0.35
const SILENT_DB: float = -60.0
const RISE_KEY: String = "game_rise_%d"
const DANGER_KEY: String = "game_danger"

## The ladder, calm first: {player, db, bpm, offset}.
var _tracks: Array[Dictionary] = []
## The rung that plays, the one the stack asks for, and the one fading out.
var _level: int = 0
var _target: int = 0
var _previous: int = 0
## Seconds until the pending step (the next bar line); negative when none.
var _switch_in: float = -1.0
var _fade: float = 1.0


## Takes over the scene's calm player (stream and volume already set).
func setup(calm_player: AudioStreamPlayer) -> void:
	var offset: float = ResourcePack.music_number("game", "loop_offset", 0.0)
	if calm_player.stream != null and "loop_offset" in calm_player.stream:
		calm_player.stream.set("loop_offset", offset)
	_tracks = [{
		"player": calm_player,
		"db": ResourcePack.music_volume("game"),
		"bpm": ResourcePack.music_number("game", "bpm", 120.0),
		"offset": offset,
	}]
	# Only tracks of the pack the calm one comes from: a pack that replaces
	# the music must not be mixed with another pack's faster versions.
	var owner_id: String = ResourcePack.music_pack("game")
	var keys: Array[String] = []
	var rung: int = 1
	while ResourcePack.music_pack(RISE_KEY % rung) == owner_id and owner_id != "":
		keys.append(RISE_KEY % rung)
		rung += 1
	if owner_id != "" and ResourcePack.music_pack(DANGER_KEY) == owner_id:
		keys.append(DANGER_KEY)
	for key: String in keys:
		var track: AudioStream = ResourcePack.music(key)
		var bpm: float = ResourcePack.music_number(key, "bpm", 0.0)
		if track == null or bpm <= 0.0:
			continue
		if "loop" in track:
			track.set("loop", true)
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = key.to_pascal_case()
		player.stream = track
		player.bus = calm_player.bus
		player.volume_db = SILENT_DB
		add_child(player)
		_tracks.append({"player": player, "db": ResourcePack.music_volume(key), "bpm": bpm, "offset": 0.0})


## Rungs of the ladder (1 when the pack has only the calm track).
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


## Reports the tallest stack in play (rows, incoming garbage included).
func update_pressure(rows: int) -> void:
	_target = level_for_rows(rows, _target)


## The rung for a stack of `rows`, coming from rung `current`: up as soon as a
## rung's height is reached, down only once the stack is a whole rung lower,
## so a stack hovering at a boundary does not make the music waver.
func level_for_rows(rows: int, current: int) -> int:
	var top: int = _tracks.size() - 1
	if top <= 0:
		return 0
	var want: float = float(rows - CALM_ROWS) / float(DANGER_ROWS - CALM_ROWS) * float(top)
	if floori(want) > current:
		return mini(top, floori(want))
	if want <= float(current - 1):
		return maxi(0, ceili(want))
	return current


func _process(delta: float) -> void:
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
	if _target != _level and _fade >= 1.0:
		# Wait for the bar line the playing track is about to reach.
		var bar: float = 60.0 * BEATS_PER_BAR / float(_tracks[_level]["bpm"])
		_switch_in = bar - fposmod(_tune_position(_level), bar)


## Where track `index` is in the tune, in its own seconds past its intro.
func _tune_position(index: int) -> float:
	var playing: AudioStreamPlayer = _tracks[index]["player"]
	if not playing.playing:
		return 0.0
	var position: float = playing.get_playback_position() + AudioServer.get_time_since_last_mix()
	return maxf(0.0, position - float(_tracks[index]["offset"]))


## The stream position in track `to` of the point of the tune that is
## `position` seconds past the intro of track `from`.
func mapped_position(position: float, from: int, to: int) -> float:
	var offset: float = float(_tracks[to]["offset"])
	var target: float = position * float(_tracks[from]["bpm"]) / float(_tracks[to]["bpm"])
	var stream: AudioStream = (_tracks[to]["player"] as AudioStreamPlayer).stream
	var body: float = (stream.get_length() if stream != null else 0.0) - offset
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
	var incoming: Dictionary = _tracks[_level]
	var outgoing: Dictionary = _tracks[_previous]
	var turn: float = _fade * PI / 2.0
	(incoming["player"] as AudioStreamPlayer).volume_db = maxf(SILENT_DB, float(incoming["db"]) + linear_to_db(maxf(sin(turn), 0.0001)))
	if _previous == _level:
		return
	(outgoing["player"] as AudioStreamPlayer).volume_db = maxf(SILENT_DB, float(outgoing["db"]) + linear_to_db(maxf(cos(turn), 0.0001)))
	if _fade >= 1.0:
		_rest(_previous)


## Silences a rung that is no longer heard. The faster tracks stop; the calm
## one keeps its place in the scene as the stream that never stops.
func _rest(index: int) -> void:
	var resting: AudioStreamPlayer = _tracks[index]["player"]
	resting.volume_db = SILENT_DB
	if index > 0:
		resting.stop()
