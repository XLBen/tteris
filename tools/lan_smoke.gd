extends SceneTree
## LAN link check over localhost. Run it twice, at the same time, with the
## environment variable SMOKE_ROLE set to "host" in one process and "client"
## in the other:
##
##   godot --headless --path . --script res://tools/lan_smoke.gd
##
## Both open the versus scene through the LAN path and hard-drop for a few
## seconds; each prints what it saw (pieces placed on both boards, the name
## tags). The client's line shows the host's battle mirrored.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var role: String = OS.get_environment("SMOKE_ROLE")
	var link: Node = root.get_node(^"LanSession")
	var session: Node = root.get_node(^"GameSession")
	var error: Error = link.host() if role == "host" else link.join("127.0.0.1")
	print(role, " open: ", error)
	var waited: float = 0.0
	while not link.has_peer() and waited < 15.0:
		await process_frame
		waited += 1.0 / 60.0
	print(role, " peer: ", link.has_peer())
	if not link.has_peer():
		quit(1)
		return
	session.start_versus(&"rising", 1, &"single", &"normal", &"", StringName(role))
	change_scene_to_file("res://scenes/versus/versus.tscn")
	await process_frame
	await process_frame
	var scene: Node = current_scene
	var model: VersusBattle = scene.get("_model")
	var start: int = Time.get_ticks_msec()
	var next_drop: int = start + 3500
	while Time.get_ticks_msec() - start < 9000:
		await process_frame
		if not is_instance_valid(scene):
			# The other side hung up: the scene went back to the LAN page.
			print(role, ": the other player left")
			quit(0)
			return
		model = scene.get("_model")
		if Time.get_ticks_msec() >= next_drop:
			next_drop += 300
			if role == "host":
				model.tap(0, VersusBattle.ACTION_HARD_DROP)
			else:
				link.send_input(VersusBattle.ACTION_HARD_DROP, link.INPUT_TAP)
	var rows: Array = []
	for side: int in 2:
		var top: int = model.board(side).highest_occupied_row()
		rows.append(Board.BOARD_HEIGHT - top if top >= 0 else 0)
	print("%s: lan=%s phase %d  placed left %d right %d  stack rows left %d right %d  pending %d/%d  tags %s | %s" % [role, scene.get("_lan"), model.phase(),
		model.pieces_placed(0), model.pieces_placed(1), rows[0], rows[1], model.pending_garbage(0), model.pending_garbage(1),
		(scene.find_child("PlayerTag", true, false) as Label).text, (scene.find_child("AITag", true, false) as Label).text])
	quit(0)
