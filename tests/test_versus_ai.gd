extends SceneTree
## Versus AI (T-07b2): the greedy AI (scripts/versus_ai.gd) drives the real
## VersusBattle model through its public input surface (tap only) for a whole
## single match. The fixed seed 20260917 reproduces the bag order and the
## garbage hole columns; nothing here mocks the model.
##
## Cases: a FIXED level-3 match must finish inside the tick budget without
## stalling, the AI must clear lines and score, its attack must really reach the
## player side (pending garbage or GARBAGE cells on the player board), a CLASSIC
## match must also finish with the level tracking Scoring.level_for_score, and
## the same seed + same tick rhythm must reproduce the identical final state.

const MODULE_NAME: String = "versus_ai"

## Fixed seed: the same seed and tick rhythm must reproduce the exact match.
const SEED: int = 20260917
## Budget for one single match at 0.05s per tick (20000 ticks = 1000s sim time).
const MAX_TICKS: int = 20000
const TICK_DELTA: float = 0.05
## The attacker's clear queues garbage; the defender inserts it on their next
## lock, so a periodic board scan is a cheap extra probe next to the pending
## garbage read.
const GARBAGE_SCAN_INTERVAL: int = 10

const SIDE_PLAYER: int = VersusBattle.Side.PLAYER
const SIDE_AI: int = VersusBattle.Side.AI


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d versus ai cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("VERSUS AI TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	var fixed_run: Dictionary = _run_ai_match(VersusBattle.Rules.FIXED, 3, SEED)
	_case(ctx, "fixed_level3_single_match_ends_within_20000_ticks", _ended_within_budget(fixed_run))
	_case(ctx, "fixed_level3_ai_clears_lines_and_scores", int(fixed_run["ai_lines"]) > 0 and int(fixed_run["ai_score"]) > 0)
	_case(ctx, "fixed_level3_ai_attack_reaches_player_side", bool(fixed_run["player_attacked"]))
	# Revised 2026-10-10: the versus "classic" rules became RISING (one shared
	# level driven by the round clock).
	var classic_run: Dictionary = _run_ai_match(VersusBattle.Rules.RISING, 1, SEED)
	_case(ctx, "rising_single_match_ends_within_budget_and_ai_scores", _ended_within_budget(classic_run) and int(classic_run["ai_score"]) > 0)
	_case(ctx, "rising_ai_level_matches_lines_cleared", _classic_level_ok(classic_run))
	var replay_run: Dictionary = _run_ai_match(VersusBattle.Rules.FIXED, 3, SEED)
	_case(ctx, "same_seed_same_tick_rhythm_identical_final_snapshot", str(_final_snapshot(fixed_run)) == str(_final_snapshot(replay_run)))
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


# ---------------------------------------------------------------------------
# One real match: the battle frame advances first, then the AI issues at most
# one action through VersusBattle's tap surface. The loop stops on round settle
# or when the tick budget is exhausted, and every fact is read back from the
# public read surface.
static func _run_ai_match(rules: int, fixed_level: int, seed: int) -> Dictionary:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(rules, fixed_level, VersusBattle.MatchFormat.SINGLE, seed)
	var ai: VersusAI = VersusAI.new(battle, SIDE_AI)
	var ticks: int = 0
	var player_attacked: bool = false
	while battle.phase() == VersusBattle.Phase.PLAYING and ticks < MAX_TICKS:
		battle.tick(TICK_DELTA)
		ai.tick(TICK_DELTA)
		if battle.pending_garbage(SIDE_PLAYER) > 0:
			player_attacked = true
		if ticks % GARBAGE_SCAN_INTERVAL == 0 and _board_has_garbage(battle.board(SIDE_PLAYER)):
			player_attacked = true
		ticks += 1
	return {
		"ticks": ticks,
		"ended": battle.phase() != VersusBattle.Phase.PLAYING,
		"phase": battle.phase(),
		"round_winner": battle.round_winner(),
		"match_winner": battle.match_winner(),
		"round_wins": [battle.round_wins(SIDE_PLAYER), battle.round_wins(SIDE_AI)],
		"player_attacked": player_attacked,
		"ai_score": battle.score(SIDE_AI),
		"ai_lines": battle.lines(SIDE_AI),
		"player_lines": battle.lines(SIDE_PLAYER),
		"ai_level": battle.level(SIDE_AI),
		"elapsed": battle.elapsed(),
	}


static func _ended_within_budget(run: Dictionary) -> bool:
	return bool(run["ended"]) and int(run["ticks"]) < MAX_TICKS


## Rising speed (revised 2026-10-10): the level is 1 plus one per
## RISING_LINES_PER_LEVEL lines cleared by both sides together, capped at
## RISING_MAX_LEVEL.
static func _classic_level_ok(run: Dictionary) -> bool:
	var lines: int = int(run["ai_lines"]) + int(run["player_lines"])
	return int(run["ai_level"]) == mini(VersusBattle.RISING_MAX_LEVEL, 1 + lines / VersusBattle.RISING_LINES_PER_LEVEL)


## Final facts named by the reproducibility contract: phase + winner, round
## wins and the AI lines/score (plus the tick count the rhythm produced).
static func _final_snapshot(run: Dictionary) -> Array:
	return [
		run["phase"],
		run["round_winner"],
		run["match_winner"],
		run["round_wins"],
		run["ai_lines"],
		run["ai_score"],
		run["ticks"],
	]


static func _board_has_garbage(board: Board) -> bool:
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			if board.get_cell(Vector2i(x, y)) == Board.GARBAGE:
				return true
	return false
