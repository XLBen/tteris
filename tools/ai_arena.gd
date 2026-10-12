extends SceneTree
## AI calibration arena (headless): pits the versus AI tiers against each other
## on the real VersusBattle model and prints the numbers the tier profiles in
## scripts/versus_ai.gd are tuned against.
##
##   godot --headless --path . --script res://tools/ai_arena.gd -- [key=value ...]
##     seeds=6      matches per pairing
##     level=1      fixed speed level of the duels
##     solo=1       also run the unpressured survival runs (levels 1/5/10)
##     pairs=all    "all" for the full matrix, "ladder" for adjacent tiers only
##     style=tier   only the style report of one tier (or "all"): mirror
##                  matches, with what the attacks were made of
##     ab=tier      only the A/B report of one tier: the tier against itself
##                  with one profile key changed (AB_VARIANTS), so each
##                  behaviour can be judged on its own (first=n: only the
##                  first n of them)
##
## Duel: side 0 plays the row tier, side 1 the column tier; a match that is
## still running after MATCH_SECONDS goes to the side that sent more garbage.
## Solo: the tier plays alone against a frozen opponent for SOLO_SECONDS; a
## top-out there is a suicide. The solo lines also report how many T-Spin
## Doubles / Triples the tier lands per 100 pieces.

const TIERS: Array[StringName] = [&"easy", &"normal", &"hard", &"lunatic"]
const TICK: float = 1.0 / 30.0
const MATCH_SECONDS: float = 240.0
const SOLO_SECONDS: float = 180.0
const SOLO_LEVELS: Array[int] = [1, 5, 10]
const BASE_SEED: int = 20261010
## Profile changes the A/B report tries, one at a time.
const AB_VARIANTS: Array[Dictionary] = [
	{"hold_lookahead": false},
	{"hold_lookahead_attack": true},
	{"tuck_depth": 0},
	{"hold_lookahead": false, "tuck_depth": 0},
	{"pc_pieces": 0},
	{"tspin_patience": 0},
	{"empty_spins": true},
]


func _initialize() -> void:
	var options: Dictionary = {"seeds": "6", "level": "1", "solo": "1", "pairs": "all"}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=")
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var seeds: int = int(options["seeds"])
	var level: int = int(options["level"])
	if options.has("ab"):
		var tier: StringName = StringName(String(options["ab"]))
		for change: Dictionary in AB_VARIANTS.slice(0, int(options.get("first", "99"))):
			var other: Dictionary = (VersusAI.DIFFICULTY_PROFILES[tier] as Dictionary).duplicate()
			other.merge(change, true)
			var wins: Array[int] = [0, 0]
			var sent: Array[float] = [0.0, 0.0]
			var seconds: float = 0.0
			for i: int in seeds:
				var flip: bool = i % 2 == 1
				var result: Dictionary = duel(other if flip else tier, tier if flip else other, level, BASE_SEED + i)
				var winner: int = int(result["winner"])
				if winner >= 0:
					wins[(1 - winner) if flip else winner] += 1
				for side: int in 2:
					sent[(1 - side) if flip else side] += float(result["sent"][side])
				seconds += float(result["seconds"])
			print("%-8s as is vs %s  wins %d:%d  aps %.3f/%.3f  avg %.0fs" % [tier, change, wins[0], wins[1], sent[0] / seconds, sent[1] / seconds, seconds / float(seeds)])
		quit(0)
		return
	if options.has("style"):
		for tier: StringName in TIERS:
			if String(options["style"]) == "all" or String(options["style"]) == String(tier):
				print(style_line(tier, level, seeds))
		quit(0)
		return
	print("== duels: level %d, %d seeds, %.0fs cap ==" % [level, seeds, MATCH_SECONDS])
	for a: int in TIERS.size():
		for b: int in TIERS.size():
			if b <= a:
				continue
			if String(options["pairs"]) == "ladder" and b != a + 1:
				continue
			var wins: Array[int] = [0, 0]
			var app: Array[float] = [0.0, 0.0]
			var pps: Array[float] = [0.0, 0.0]
			var seconds: float = 0.0
			for i: int in seeds:
				# Alternate the seats so neither tier owns a side.
				var flip: bool = i % 2 == 1
				var first: StringName = TIERS[b] if flip else TIERS[a]
				var second: StringName = TIERS[a] if flip else TIERS[b]
				var result: Dictionary = duel(first, second, level, BASE_SEED + i)
				var winner: int = int(result["winner"])
				if winner >= 0:
					wins[(1 - winner) if flip else winner] += 1
				for side: int in 2:
					var who: int = (1 - side) if flip else side
					app[who] += float(result["app"][side]) / float(seeds)
					pps[who] += float(result["pps"][side]) / float(seeds)
				seconds += float(result["seconds"]) / float(seeds)
			print("%-8s vs %-8s  wins %d:%d  app %.2f/%.2f  pps %.2f/%.2f  avg %.0fs" % [
				TIERS[a], TIERS[b], wins[0], wins[1], app[0], app[1], pps[0], pps[1], seconds,
			])
	if int(options["solo"]) != 0:
		print("== solo survival: %.0fs, %d seeds ==" % [SOLO_SECONDS, seeds])
		for tier: StringName in TIERS:
			for solo_level: int in SOLO_LEVELS:
				var deaths: int = 0
				var pieces: int = 0
				var sent: int = 0
				var doubles: int = 0
				var triples: int = 0
				for i: int in seeds:
					var result: Dictionary = solo(tier, solo_level, BASE_SEED + i, SOLO_SECONDS)
					deaths += 1 if bool(result["died"]) else 0
					pieces += int(result["pieces"])
					sent += int(result["sent"])
					doubles += int(result["tsd"])
					triples += int(result["tst"])
				print("%-8s level %2d  suicides %d/%d  app %.2f  pps %.2f  per 100 pieces: TSD %.1f  TST %.1f  T used for them %.0f%%" % [
					tier, solo_level, deaths, seeds,
					float(sent) / maxf(1.0, float(pieces)),
					float(pieces) / (SOLO_SECONDS * float(seeds)),
					100.0 * float(doubles) / maxf(1.0, float(pieces)),
					100.0 * float(triples) / maxf(1.0, float(pieces)),
					# One piece in seven is a T.
					100.0 * float(doubles + triples) / maxf(1.0, float(pieces) / 7.0),
				])
	quit(0)


## One AI-vs-AI single match. Returns winner (side, -1 for a dead heat), the
## per-side attack per piece and pieces per second, and the match length.
## `first` and `second` are tier names or whole profiles.
static func duel(first: Variant, second: Variant, level: int, match_seed: int, tick: float = TICK, cap_seconds: float = MATCH_SECONDS) -> Dictionary:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, level, VersusBattle.MatchFormat.SINGLE, match_seed)
	var ais: Array[VersusAI] = [
		VersusAI.new(battle, 0, first if first is Dictionary else VersusAI.DIFFICULTY_PROFILES[first], match_seed),
		VersusAI.new(battle, 1, second if second is Dictionary else VersusAI.DIFFICULTY_PROFILES[second], match_seed + 7919),
	]
	var elapsed: float = 0.0
	var pieces: Array[int] = [0, 0]
	var sent: Array[int] = [0, 0]
	while battle.phase() == VersusBattle.Phase.PLAYING and elapsed < cap_seconds:
		battle.tick(tick)
		for side: int in 2:
			if battle.phase() == VersusBattle.Phase.PLAYING:
				pieces[side] = battle.pieces_placed(side)
				sent[side] = battle.attack_sent(side)
		ais[0].tick(tick)
		ais[1].tick(tick)
		elapsed += tick
	var winner: int = battle.match_winner()
	if battle.phase() == VersusBattle.Phase.PLAYING and sent[0] != sent[1]:
		winner = 0 if sent[0] > sent[1] else 1
	return {
		"winner": winner,
		"seconds": elapsed,
		"sent": sent,
		"app": [float(sent[0]) / maxf(1.0, float(pieces[0])), float(sent[1]) / maxf(1.0, float(pieces[1]))],
		"pps": [float(pieces[0]) / maxf(0.001, elapsed), float(pieces[1]) / maxf(0.001, elapsed)],
	}


## What a tier's attacks are made of, over `seeds` mirror matches: attack per
## second and per piece, the share of the rows sent in each AI mode, T-Spin
## clears, spins that cleared nothing, Perfect Clears.
static func style_line(tier: StringName, level: int, seeds: int, cap_seconds: float = MATCH_SECONDS) -> String:
	var total: Dictionary = {}
	for i: int in seeds:
		var one: Dictionary = style(tier, level, BASE_SEED + i, cap_seconds)
		for key: String in one:
			total[key] = float(total.get(key, 0.0)) + float(one[key])
	var sent: float = maxf(1.0, float(total["sent"]))
	var line: String = "%-8s aps %.3f  app %.3f  pps %.2f |" % [tier, float(total["sent"]) / float(total["seconds"]), float(total["sent"]) / maxf(1.0, float(total["pieces"])), float(total["pieces"]) / float(total["seconds"])]
	for name: String in VersusAI.MODE_NAMES:
		line += " %s %.0f%% of pieces, %.0f%% of rows;" % [name, 100.0 * float(total.get("pieces_" + name, 0.0)) / maxf(1.0, float(total["pieces"])), 100.0 * float(total.get("sent_" + name, 0.0)) / sent]
	line += " | per 100 pieces: tetris %.2f  spin clears %.2f  empty spins %.2f  perfect clears %.2f" % [
		100.0 * float(total["tetris"]) / float(total["pieces"]), 100.0 * float(total["spin_clears"]) / float(total["pieces"]),
		100.0 * float(total["empty_spins"]) / float(total["pieces"]), 100.0 * float(total["perfect"]) / float(total["pieces"]),
	]
	return line


## One mirror match of `tier`, both sides summed.
static func style(tier: StringName, level: int, match_seed: int, cap_seconds: float = MATCH_SECONDS, tick: float = TICK) -> Dictionary:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, level, VersusBattle.MatchFormat.SINGLE, match_seed)
	var ais: Array[VersusAI] = [
		VersusAI.new(battle, 0, VersusAI.DIFFICULTY_PROFILES[tier], match_seed),
		VersusAI.new(battle, 1, VersusAI.DIFFICULTY_PROFILES[tier], match_seed + 7919),
	]
	var out: Dictionary = {"sent": 0, "pieces": 0, "seconds": 0.0, "tetris": 0, "spin_clears": 0, "empty_spins": 0, "perfect": 0}
	var elapsed: float = 0.0
	while battle.phase() == VersusBattle.Phase.PLAYING and elapsed < cap_seconds:
		battle.tick(tick)
		for event: Dictionary in battle.drain_events():
			var mode: String = ais[int(event["side"])].mode_name()
			match event["type"]:
				&"lock":
					out["pieces"] += 1
					out["pieces_" + mode] = int(out.get("pieces_" + mode, 0)) + 1
				&"spin":
					out["empty_spins"] += 1
				&"clear":
					out["sent"] += int(event["attack"])
					out["sent_" + mode] = int(out.get("sent_" + mode, 0)) + int(event["attack"])
					if int(event["t_spin"]) != Scoring.TSpinKind.NONE:
						out["spin_clears"] += 1
					elif int(event["lines"]) >= 4:
						out["tetris"] += 1
					if bool(event["perfect_clear"]):
						out["perfect"] += 1
		ais[0].tick(tick)
		ais[1].tick(tick)
		elapsed += tick
	# Two sides played for `elapsed` each.
	out["seconds"] = 2.0 * elapsed
	return out


## One tier alone on side 1 against a frozen side 0.
static func solo(tier: StringName, level: int, match_seed: int, seconds: float, tick: float = TICK) -> Dictionary:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, level, VersusBattle.MatchFormat.SINGLE, match_seed)
	battle.debug_freeze_side(0, true)
	var ai: VersusAI = VersusAI.new(battle, 1, VersusAI.DIFFICULTY_PROFILES[tier], match_seed)
	var elapsed: float = 0.0
	var pieces: int = 0
	var sent: int = 0
	var tspins: int = 0
	while battle.phase() == VersusBattle.Phase.PLAYING and elapsed < seconds:
		battle.tick(tick)
		if battle.phase() == VersusBattle.Phase.PLAYING:
			pieces = battle.pieces_placed(1)
			sent = battle.attack_sent(1)
			tspins = battle.tspins(1)
		ai.tick(tick)
		elapsed += tick
	return {
		"died": battle.phase() != VersusBattle.Phase.PLAYING,
		"pieces": pieces,
		"sent": sent,
		"tspins": tspins,
		"holds": ai.holds_made(),
		"tsd": battle.tspin_clears(1, 2),
		"tst": battle.tspin_clears(1, 3),
		"seconds": elapsed,
		"log": ai.action_log(),
	}
