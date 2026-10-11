extends SceneTree
## LAN versus (2026-10-12): the battle snapshot a host sends, the mirrored
## replica the joining player sees, and the LAN page of the setup screen.
## The link itself needs two processes: tools/lan_smoke.gd runs it over
## localhost.

const MODULE_NAME: String = "lan"
const MODE_SELECT_PATH: String = "res://scenes/menus/mode_select/mode_select.tscn"
const VERSUS_SCENE_PATH: String = "res://scenes/versus/versus.tscn"
const TICK: float = 1.0 / 60.0


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d lan cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("LAN TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_replica_shows_the_host_battle_mirrored(ctx)
	await _case_lan_page_gates_rules_and_start(ctx)
	await _case_versus_scene_without_a_link_is_a_cpu_match(ctx)
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


static func _cells(board: Board) -> Array[int]:
	var cells: Array[int] = []
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			cells.append(board.get_cell(Vector2i(x, y)))
	return cells


# The host's battle after some play, sent as a snapshot: the replica shows the
# same battle with the sides traded, so the joining player's own board (the
# host's right one) is on the left.
static func _case_replica_shows_the_host_battle_mirrored(ctx: Dictionary) -> void:
	var host: VersusBattle = VersusBattle.new()
	host.setup(VersusBattle.Rules.RISING, 1, VersusBattle.MatchFormat.BEST_OF_3, 20261012)
	var replica: VersusBattle = VersusBattle.new()
	replica.setup(VersusBattle.Rules.FIXED, 5, VersusBattle.MatchFormat.SINGLE, 1)
	# The two sides play differently: the left one drops in place, the right
	# one moves, rotates and holds first.
	host.tap(VersusBattle.Side.AI, VersusBattle.ACTION_HOLD)
	for step: int in 150:
		if step % 50 == 0:
			host.tap(VersusBattle.Side.PLAYER, VersusBattle.ACTION_HARD_DROP)
		if step % 30 == 10:
			host.tap(VersusBattle.Side.AI, VersusBattle.ACTION_MOVE_LEFT)
			host.tap(VersusBattle.Side.AI, VersusBattle.ACTION_ROTATE)
		if step % 30 == 20:
			host.tap(VersusBattle.Side.AI, VersusBattle.ACTION_HARD_DROP)
		host.tick(TICK)
	var events: Array[Dictionary] = host.drain_events()
	var first_piece: Tetromino = replica.current_piece(0)
	replica.apply_snapshot(host.snapshot(), events, true)
	var ok: bool = host.phase() == VersusBattle.Phase.PLAYING and host.pieces_placed(0) >= 3 and host.pieces_placed(1) >= 4 and host.pieces_placed(0) != host.pieces_placed(1)
	for side: int in 2:
		var other: int = 1 - side
		ok = ok and _cells(replica.board(side)) == _cells(host.board(other))
		ok = ok and replica.pieces_placed(side) == host.pieces_placed(other) and replica.hold_type(side) == host.hold_type(other)
		ok = ok and replica.next_queue(side) == host.next_queue(other) and replica.piece_pos(side) == host.piece_pos(other)
		ok = ok and replica.current_piece(side).piece_type == host.current_piece(other).piece_type \
			and replica.current_piece(side).rotation == host.current_piece(other).rotation
		ok = ok and replica.ghost_pos(side) == host.ghost_pos(other) and replica.level(side) == host.level(other)
	ok = ok and replica.hold_type(0) >= 0 and replica.hold_type(1) < 0
	ok = ok and replica.phase() == host.phase() and replica.match_format() == VersusBattle.MatchFormat.BEST_OF_3 \
		and replica.rules() == VersusBattle.Rules.RISING
	# Events arrive with their side traded too.
	var copied: Array[Dictionary] = replica.drain_events()
	ok = ok and copied.size() == events.size() and not events.is_empty()
	for i: int in mini(copied.size(), events.size()):
		ok = ok and copied[i]["type"] == events[i]["type"] and int(copied[i]["side"]) == 1 - int(events[i]["side"])
	# Without the mirror the sides stay where they are.
	var plain: VersusBattle = VersusBattle.new()
	plain.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, 2)
	plain.apply_snapshot(host.snapshot())
	ok = ok and _cells(plain.board(0)) == _cells(host.board(0)) and plain.pieces_placed(1) == host.pieces_placed(1)
	# The same piece keeps its object between snapshots (the scene tells a
	# move from a spawn by it); a new piece is a new object.
	var shown: Tetromino = replica.current_piece(0)
	host.tap(VersusBattle.Side.AI, VersusBattle.ACTION_MOVE_RIGHT)
	host.tick(TICK)
	replica.apply_snapshot(host.snapshot(), [], true)
	ok = ok and replica.current_piece(0) == shown and shown != first_piece
	host.tap(VersusBattle.Side.AI, VersusBattle.ACTION_HARD_DROP)
	host.tick(TICK)
	replica.apply_snapshot(host.snapshot(), [], true)
	ok = ok and replica.current_piece(0) != shown
	# A lost round reaches the replica with the winner on the right side.
	for step: int in 2400:
		if host.phase() != VersusBattle.Phase.PLAYING:
			break
		host.tap(VersusBattle.Side.PLAYER, VersusBattle.ACTION_HARD_DROP)
		host.tick(TICK)
	replica.apply_snapshot(host.snapshot(), [], true)
	ok = ok and host.phase() == VersusBattle.Phase.ROUND_OVER and host.round_winner() == VersusBattle.Side.AI \
		and replica.round_winner() == VersusBattle.Side.PLAYER and replica.round_wins(0) == 1 and replica.round_wins(1) == 0
	_case(ctx, "replica_shows_the_host_battle_with_the_sides_traded", ok)


# The LAN page: no CPU cards, the start locked until a player joined a host,
# the rules locked for a joined player, and Back hangs up.
static func _case_lan_page_gates_rules_and_start(ctx: Dictionary) -> void:
	var session: Node = _tree().root.get_node_or_null(^"GameSession")
	var link: Node = _tree().root.get_node_or_null(^"LanSession")
	var ok: bool = session != null and link != null
	if ok:
		session.versus_page = &"lan"
		session.open_versus_setup = true
		session.lan_notice = "LAN_PEER_LEFT"
		var select = (load(MODE_SELECT_PATH) as PackedScene).instantiate()
		_tree().root.add_child(select)
		await _tree().process_frame
		var stub: LoaderStub = LoaderStub.new()
		select.scene_loader_node = stub
		var setup: VersusSetup = select._setup
		ok = select.page() == &"lan" and setup.lan_card.visible and not setup.left_card.visible and not setup.right_card.visible
		# The notice the versus scene left (the other player is gone) is shown once.
		ok = ok and setup.lan_status.text == select.tr("LAN_PEER_LEFT") and session.lan_notice == ""
		ok = ok and link.role() == link.ROLE_NONE and setup.start_button.disabled \
			and not setup.lan_host_button.disabled and not setup.button("rules", &"fixed").disabled
		# Start does nothing without a joined player.
		setup.start_button.pressed.emit()
		ok = ok and stub.loaded.is_empty() and not session.is_versus()
		# Joining needs an address.
		setup.lan_join_pressed.emit("  ")
		ok = ok and link.role() == link.ROLE_NONE and setup.lan_status.text == select.tr("LAN_STATUS_NO_ADDRESS")
		# What a host sends is what the page shows.
		select._on_lan_settings_received({"rules": &"fixed", "level": 7, "format": &"best_of_3"})
		ok = ok and select._versus_rules == &"fixed" and select._versus_level == 7 and select._versus_format == &"best_of_3" \
			and setup.button("level", 7).button_pressed and setup.level_row.visible
		# A host: the connection controls lock, the rules stay open, the start
		# waits for the guest.
		setup.lan_host_pressed.emit()
		if link.role() == link.ROLE_HOST:
			ok = ok and setup.lan_host_button.disabled and not setup.lan_address.editable \
				and not setup.button("rules", &"rising").disabled and setup.start_button.disabled
		else:
			# The port is taken on this machine (a running game): the page says so.
			ok = ok and setup.lan_status.text == select.tr("LAN_STATUS_FAILED")
		# The joined player's page: everything but leaving is locked.
		setup.show_lan("", false, false, false)
		ok = ok and setup.button("rules", &"rising").disabled and setup.button("format", &"single").disabled and setup.start_button.disabled
		# Back leaves the page for the list - and hangs up.
		(select.find_child("BackButton", true, false) as Button).pressed.emit()
		ok = ok and select.page() == &"menu" and stub.loaded.is_empty() and link.role() == link.ROLE_NONE
		(select.find_child("BackButton", true, false) as Button).pressed.emit()
		ok = ok and stub.loaded.size() == 1
		select.free()
		await _tree().process_frame
		session.versus_page = &"pve"
	_case(ctx, "lan_page_locks_start_and_rules_until_they_apply", ok)


# A session that says "LAN" without a live link (a scene opened directly)
# falls back to a match against the CPU instead of a board nobody plays.
static func _case_versus_scene_without_a_link_is_a_cpu_match(ctx: Dictionary) -> void:
	var session: Node = _tree().root.get_node_or_null(^"GameSession")
	var link: Node = _tree().root.get_node_or_null(^"LanSession")
	var ok: bool = session != null and link != null
	if ok:
		link.close()
		session.start_versus(session.VERSUS_RULES_RISING, 1, session.VERSUS_FORMAT_SINGLE, session.VERSUS_DIFFICULTY_NORMAL, &"", &"host")
		var scene: Node = (load(VERSUS_SCENE_PATH) as PackedScene).instantiate()
		_tree().root.add_child(scene)
		await _tree().process_frame
		ok = scene.get("_lan") == &"" and scene.get("_ai") != null
		scene.free()
		await _tree().process_frame
		session.start_mode(session.MODE_NONE)
		ok = ok and session.versus_lan == &""
	_case(ctx, "versus_scene_without_a_link_is_a_cpu_match", ok)


class LoaderStub:
	extends RefCounted

	var loaded: Array[String] = []

	func load_scene(path: String, _in_background: bool = false) -> void:
		loaded.append(path)
