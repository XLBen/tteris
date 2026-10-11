extends SceneTree
## T-Spin lab (headless): fixed boards taken from the usual teaching diagrams.
## The AI gets a T and must find its way into the slot; the lab reports what
## the lock actually was and the keys the AI pressed.
##
##   godot --headless --path . --script res://tools/tspin_lab.gd -- [tier=lunatic]
##
## Board rows are written top to bottom, '#' filled, '.' empty; the last row
## is the floor row.

const TICK: float = 1.0 / 60.0
const SCENARIOS: Dictionary = {
	# Overhang on the left, the T comes down on the right.
	"tsd_left_overhang": {
		"rows": [
			"####......",
			"###...####",
			"####.#####",
		],
		"lines": 2,
	},
	# Mirror image.
	"tsd_right_overhang": {
		"rows": [
			".....#####",
			"###...####",
			"####.#####",
		],
		"lines": 2,
	},
	# The slot hugs the left wall.
	"tsd_at_the_wall": {
		"rows": [
			"..########",
			"...#######",
			"#.########",
		],
		"lines": 2,
	},
	# T-Spin Triple: the T slides under the roof and the rotation's fifth kick
	# drops it down the shaft (nub pocket on the right).
	"tst_right_nub": {
		"rows": [
			"#####.....",
			"####......",
			"####.#####",
			"####..####",
			"####.#####",
		],
		"lines": 3,
	},
	"tst_left_nub": {
		"rows": [
			".....#####",
			"......####",
			"#####.####",
			"####..####",
			"#####.####",
		],
		"lines": 3,
	},
}


func _initialize() -> void:
	var tier: StringName = &"lunatic"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("tier="):
			tier = StringName(arg.trim_prefix("tier="))
	var failed: int = 0
	for scenario: String in SCENARIOS:
		var result: Dictionary = run_scenario(scenario, tier)
		var ok: bool = bool(result["ok"])
		failed += 0 if ok else 1
		print("%s %-20s %s  lines %d  spin %d  keys: %s" % [
			"PASS" if ok else "FAIL", scenario, tier, int(result["lines"]), int(result["t_spin"]), " ".join(result["keys"]),
		])
	print("T-SPIN LAB: %d of %d found" % [SCENARIOS.size() - failed, SCENARIOS.size()])
	quit(1 if failed > 0 else 0)


## Plays one scenario with the given tier. Returns ok (a full T-Spin clearing
## the expected lines), the lines and spin kind of the lock, and the keys.
static func run_scenario(scenario: String, tier: StringName, seed_value: int = 7) -> Dictionary:
	var spec: Dictionary = SCENARIOS[scenario]
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, seed_value)
	battle.debug_freeze_side(0, true)
	var board: Board = battle.board(1)
	var rows: Array = spec["rows"]
	for i: int in rows.size():
		var y: int = Board.BOARD_HEIGHT - rows.size() + i
		for x: int in Board.BOARD_WIDTH:
			if String(rows[i])[x] == "#":
				board.set_cell(Vector2i(x, y), Board.GARBAGE)
	# The AI's piece is a T at the spawn position.
	battle.debug_force_piece(1, Tetromino.PieceType.T, 0, battle.piece_pos(1), false, -1)
	battle.drain_events()
	var ai: VersusAI = VersusAI.new(battle, 1, VersusAI.DIFFICULTY_PROFILES[tier], seed_value)
	var lines: int = 0
	var t_spin: int = Scoring.TSpinKind.NONE
	var locked: bool = false
	var steps: int = 0
	while not locked and steps < 60 * 20 and battle.phase() == VersusBattle.Phase.PLAYING:
		battle.tick(TICK)
		ai.tick(TICK)
		steps += 1
		for event: Dictionary in battle.drain_events():
			if int(event["side"]) != 1:
				continue
			match event["type"]:
				&"clear":
					lines = int(event["lines"])
					t_spin = int(event["t_spin"])
				&"spin":
					t_spin = int(event["t_spin"])
				&"lock":
					locked = true
	var keys: Array[String] = []
	for entry: Dictionary in ai.action_log():
		if entry.get("kind") == &"action":
			keys.append(String(entry["action"]).trim_prefix("move_").trim_suffix("_drop"))
	return {
		"ok": locked and t_spin == Scoring.TSpinKind.FULL and lines == int(spec["lines"]),
		"lines": lines,
		"t_spin": t_spin,
		"keys": keys,
	}
