extends SceneTree
## Plays the end of every song of the playlist in real time and reports how
## the change to the next song went: when the next one started against the
## end of the bars, and that the old track was left to ring out.
##
##   godot --script res://tools/bgm_smoke.gd
##
## Run it with a window: the timing is that of the real audio driver (the
## dummy driver of --headless mixes in much larger blocks). It is silent.

const LEAD_SECONDS: float = 0.6


func _initialize() -> void:
	await process_frame
	# Nothing is heard: the master bus is shut for the run.
	AudioServer.set_bus_volume_db(0, -80.0)
	var director: BgmDirector = BgmDirector.new()
	root.add_child(director)
	director.setup(&"Master")
	var worst: float = 0.0
	for _i: int in director.song_count():
		# One rung up on every other song, so both a calm and a faster track end.
		director.update_pressure(BgmDirector.CALM_ROWS + (2 if director.song() % 2 == 1 else 0))
		for _j: int in 300:
			await process_frame
			if director.level() == director.target_level() and director._fade >= 1.0:
				break
		var level: int = director.level()
		var title: String = director.song_title()
		var ending: AudioStreamPlayer = director.current()
		var body: float = director.body_seconds(level)
		ending.seek(body - LEAD_SECONDS)
		var playing: int = director.song()
		var left: float = LEAD_SECONDS
		while director.song() == playing:
			left = body - (ending.get_playback_position() + AudioServer.get_time_since_last_mix())
			await process_frame
			if left < -1.0:
				break
		var late: float = (ending.get_playback_position() + AudioServer.get_time_since_last_mix()) - body \
			- (director.current().get_playback_position() + AudioServer.get_time_since_last_mix())
		worst = maxf(worst, absf(late))
		print("%-28s rung %d  ->  %-28s rung %d   started %+.1f ms from the bar line, old track ringing: %s" % [
			title, level, director.song_title(), director.level(), late * 1000.0, str(is_instance_valid(ending) and ending.playing)])
		for _j: int in 20:
			await process_frame
	print("worst %.1f ms" % (worst * 1000.0))
	# The ringing ends and the old players are gone.
	await create_timer(3.5).timeout
	print("players left: %d" % director.get_child_count())
	director.free()
	quit(0)
