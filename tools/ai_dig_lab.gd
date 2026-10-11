extends SceneTree
## Digging benchmark (headless): every tier starts on a board buried in
## garbage and plays alone against a frozen opponent. Prints how long and how
## many pieces it takes to bring the stack down, and how often it dies trying.
##
##   godot --headless --path . --script res://tools/ai_dig_lab.gd -- [key=value ...]
##     seeds=8     boards per tier
##     rows=13     garbage rows the board starts with
##     level=1     speed level
##     tiers=hard,lunatic

const TICK: float = 1.0 / 30.0
const CAP_SECONDS: float = 90.0
const BASE_SEED: int = 20261011
const TARGETS: Array[int] = [8, 6, 4]


func _initialize() -> void:
	var options: Dictionary = {"seeds": "8", "rows": "13", "level": "1", "tiers": "hard,lunatic"}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=")
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var seeds: int = int(options["seeds"])
	print("== digging out of %d garbage rows: level %s, %d boards ==" % [int(options["rows"]), options["level"], seeds])
	for tier: String in String(options["tiers"]).split(","):
		var deaths: int = 0
		var reached: Array[int] = [0, 0, 0]
		var seconds: Array[float] = [0.0, 0.0, 0.0]
		var pieces: Array[float] = [0.0, 0.0, 0.0]
		var sent: int = 0
		for i: int in seeds:
			var result: Dictionary = dig(StringName(tier), int(options["level"]), BASE_SEED + i, int(options["rows"]))
			deaths += 1 if bool(result["died"]) else 0
			sent += int(result["sent"])
			for target: int in TARGETS.size():
				if float(result["seconds"][target]) >= 0.0:
					reached[target] += 1
					seconds[target] += float(result["seconds"][target])
					pieces[target] += float(result["pieces"][target])
		var line: String = "%-8s died %d/%d  rows sent %.1f" % [tier, deaths, seeds, float(sent) / float(seeds)]
		for target: int in TARGETS.size():
			line += "   to %d rows: %d/%d, %.1f s, %.0f pieces" % [TARGETS[target], reached[target], seeds,
				seconds[target] / maxf(1.0, float(reached[target])), pieces[target] / maxf(1.0, float(reached[target]))]
		print(line)
	quit(0)


## One tier on side 1, buried under `rows` rows of garbage (in batches of one
## to four rows, each batch with its own hole), against a frozen side 0.
## "seconds" / "pieces": when the stack first came down to each of TARGETS
## (-1 when it never did before the cap or the top-out).
static func dig(tier: StringName, level: int, match_seed: int, rows: int, tick: float = TICK) -> Dictionary:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, level, VersusBattle.MatchFormat.SINGLE, match_seed)
	battle.debug_freeze_side(0, true)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = match_seed
	var left: int = rows
	while left > 0:
		var batch: int = mini(left, random.randi_range(1, 4))
		battle.board(1).insert_garbage_rows(batch, random.randi_range(0, Board.BOARD_WIDTH - 1))
		left -= batch
	var ai: VersusAI = VersusAI.new(battle, 1, VersusAI.DIFFICULTY_PROFILES[tier], match_seed)
	var elapsed: float = 0.0
	var seconds: Array[float] = [-1.0, -1.0, -1.0]
	var pieces: Array[int] = [-1, -1, -1]
	var placed: int = 0
	var sent: int = 0
	while battle.phase() == VersusBattle.Phase.PLAYING and elapsed < CAP_SECONDS and seconds[-1] < 0.0:
		battle.tick(tick)
		ai.tick(tick)
		elapsed += tick
		if battle.phase() != VersusBattle.Phase.PLAYING:
			break
		placed = battle.pieces_placed(1)
		sent = battle.attack_sent(1)
		var top: int = battle.board(1).highest_occupied_row()
		var height: int = Board.BOARD_HEIGHT - top if top >= 0 else 0
		for target: int in TARGETS.size():
			if seconds[target] < 0.0 and height <= TARGETS[target]:
				seconds[target] = elapsed
				pieces[target] = placed
	return {"died": battle.phase() != VersusBattle.Phase.PLAYING, "seconds": seconds, "pieces": pieces, "sent": sent}
