extends SceneTree
## Versus AI tiers (scripts/versus_ai.gd): the four difficulties must differ in
## both speed and skill, in the right order, on the real VersusBattle model.
##
## Added 2026-10-10. It replaces test_ai_pacing / test_ai_difficulty /
## test_ai_realmatch, which froze the previous design (one evaluation for all
## tiers, separated only by a 150-300 ms per-key beat). Owner feedback on that
## design: the AI's strength was unreadable - an unkillable stacker that
## barely attacked, and one that locked pieces mid-plan at high speed levels.
## The old key-beat bands are deliberately gone; what is asserted now:
##   - the profile ladder's shape,
##   - each tier's measured pieces per second against its profile, with a
##     think beat before a piece's first key and never two keys in one tick,
##   - no tier tops out on its own, at level 1 or at level 10, and high
##     gravity does not turn a slow tier into a fast one,
##   - attack output per minute rises tier by tier,
##   - every tier beats the one below it in direct duels,
##   - lunatic really lands T-Spins, easy never does,
##   - one seed reproduces a duel exactly.
## tools/ai_arena.gd provides the duel/solo drivers (also the calibration
## tool the profiles are tuned with).

const MODULE_NAME: String = "ai_tiers"

const ARENA: GDScript = preload("res://tools/ai_arena.gd")
const TIERS: Array[StringName] = [&"easy", &"normal", &"hard", &"lunatic"]
const SEED: int = 20261010
const TICK: float = 1.0 / 30.0
const SOLO_SECONDS: float = 90.0
const DUEL_SECONDS: float = 150.0
const DUEL_SEEDS: int = 2
## Measured pps may sit this far from the profile (tempo jitter, hold swaps).
const PPS_TOLERANCE: float = 0.2
## Each tier must out-attack the one below it by at least this factor.
const ATTACK_STEP: float = 1.2


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d ai tier cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("AI TIERS TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	_case_profile_ladder_shape(ctx)
	var solo: Dictionary = {}
	var second: Dictionary = {}
	var fast: Dictionary = {}
	for tier: StringName in TIERS:
		solo[tier] = ARENA.solo(tier, 1, SEED, SOLO_SECONDS, TICK)
		second[tier] = ARENA.solo(tier, 1, SEED + 1, SOLO_SECONDS, TICK)
		fast[tier] = ARENA.solo(tier, 10, SEED, SOLO_SECONDS, TICK)
	_case_measured_speed_matches_profile(ctx, solo)
	_case_lunatic_bursts_to_twice_its_average(ctx, solo)
	_case_every_tier_uses_hold(ctx, solo)
	_case_seed_gives_each_cpu_its_own_game(ctx)
	_case_keys_follow_a_think_beat_one_per_tick(ctx, solo)
	_case_no_tier_tops_out_alone(ctx, solo, fast)
	_case_high_gravity_does_not_make_slow_tiers_fast(ctx, solo, fast)
	_case_attack_per_minute_rises_with_tier(ctx, solo, second)
	_case_tspins_belong_to_the_top_tiers(ctx, solo)
	_case_higher_tier_wins_duels(ctx)
	_case_same_seed_reproduces_duel(ctx)
	await (Engine.get_main_loop() as SceneTree).process_frame
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _profile(tier: StringName) -> Dictionary:
	return VersusAI.DIFFICULTY_PROFILES[tier]


static func _pps(run: Dictionary) -> float:
	return float(run["pieces"]) / float(run["seconds"])


## Rows sent per minute over two runs (one 90 s run is too few clears to rank
## neighbouring tiers reliably).
static func _attack_per_minute(run: Dictionary, other: Dictionary) -> float:
	return float(int(run["sent"]) + int(other["sent"])) * 60.0 / (float(run["seconds"]) + float(other["seconds"]))


static func _case_profile_ladder_shape(ctx: Dictionary) -> void:
	var ok: bool = VersusAI.DIFFICULTY_PROFILES.size() == TIERS.size()
	for i: int in TIERS.size():
		var profile: Dictionary = _profile(TIERS[i])
		for key: String in ["pps", "think_share", "error_rate", "error_pool", "error_max_drop", "attack_weight",
				"clear_values", "danger_clear_values", "danger_rows", "well_weight", "hole_weight", "cover_weight",
				"lookahead_depth", "hold_policy", "tspin_policy", "plan_sim_budget", "follow_candidates"]:
			ok = ok and profile.has(key)
		ok = ok and (profile["clear_values"] as Array).size() == 5 and (profile["danger_clear_values"] as Array).size() == 5
		if i == 0:
			continue
		var below: Dictionary = _profile(TIERS[i - 1])
		ok = ok and float(profile["pps"]) > float(below["pps"])
		ok = ok and float(profile["error_rate"]) < float(below["error_rate"])
		ok = ok and int(profile["lookahead_depth"]) > int(below["lookahead_depth"])
		ok = ok and int(profile["attack_weight"]) > int(below["attack_weight"])
		ok = ok and int(profile["well_weight"]) > int(below["well_weight"])
		# Revised 2026-10-10 (owner: every CPU uses hold): each tier holds, and a
		# better tier needs a smaller gain to swap.
		ok = ok and profile["hold_policy"] == &"regular" and int(profile["hold_gain_margin"]) < int(below["hold_gain_margin"])
	# The ends of the ladder: easy neither attacks on purpose nor looks ahead;
	# lunatic never slips and builds T-Spins.
	var easy: Dictionary = _profile(&"easy")
	var lunatic: Dictionary = _profile(&"lunatic")
	ok = ok and int(easy["attack_weight"]) == 0 and easy["hold_policy"] == &"regular" and int(easy["lookahead_depth"]) == 1
	ok = ok and float(lunatic["error_rate"]) == 0.0 and lunatic["tspin_policy"] == &"advanced" and _profile(&"hard")["tspin_policy"] == &"constructive"
	# The speed spread is something a player can feel, and stays human.
	ok = ok and float(lunatic["pps"]) >= 3.0 * float(easy["pps"]) and float(lunatic["pps"]) <= 2.5
	# An empty profile is the normal tier.
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
	ok = ok and VersusAI.new(battle, 1).profile() == _profile(&"normal")
	_case(ctx, "profile_ladder_speed_and_skill_strictly_ordered", ok)


## Hold is part of every tier's play (a few swaps for easy, a regular tool
## for the tiers above it).
static func _case_every_tier_uses_hold(ctx: Dictionary, solo: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in TIERS:
		var run: Dictionary = solo[tier]
		ok = ok and int(run["holds"]) >= 2 and int(run["holds"]) * 3 <= int(run["pieces"])
	ok = ok and float(solo[&"lunatic"]["holds"]) / float(solo[&"lunatic"]["pieces"]) \
		> float(solo[&"easy"]["holds"]) / float(solo[&"easy"]["pieces"])
	_case(ctx, "every_tier_uses_hold", ok)


## Board of one tier after `pieces` pieces alone on a fixed piece order.
static func _board_after(tier: StringName, ai_seed: int, pieces: int) -> Array[int]:
	var battle: VersusBattle = VersusBattle.new()
	battle.setup(VersusBattle.Rules.FIXED, 1, VersusBattle.MatchFormat.SINGLE, SEED)
	battle.debug_freeze_side(0, true)
	var ai: VersusAI = VersusAI.new(battle, 1, _profile(tier), ai_seed)
	var steps: int = 0
	while battle.phase() == VersusBattle.Phase.PLAYING and battle.pieces_placed(1) < pieces and steps < 30 * 120:
		battle.tick(TICK)
		ai.tick(TICK)
		steps += 1
	var cells: Array[int] = []
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			cells.append(battle.board(1).get_cell(Vector2i(x, y)))
	return cells


## Two CPUs of one tier on the same piece order do not mirror each other: the
## AI seed shapes the play (even for lunatic, which never slips), while one
## seed still reproduces the same game.
static func _case_seed_gives_each_cpu_its_own_game(ctx: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in TIERS:
		var first: Array[int] = _board_after(tier, SEED, 12)
		ok = ok and first == _board_after(tier, SEED, 12)
		ok = ok and first != _board_after(tier, SEED + 7919, 12)
	_case(ctx, "ai_seed_gives_each_cpu_its_own_game_and_stays_reproducible", ok)


static func _case_measured_speed_matches_profile(ctx: Dictionary, solo: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in TIERS:
		var target: float = float(_profile(tier)["pps"])
		ok = ok and absf(_pps(solo[tier]) - target) <= PPS_TOLERANCE * target
	_case(ctx, "measured_pieces_per_second_match_the_profile", ok)


## Lunatic (2026-10-12, owner: 2.5 on average, 5 at its fastest): the tier
## plays runs of pieces at its burst pace and still averages its profile pps;
## no other tier bursts.
static func _case_lunatic_bursts_to_twice_its_average(ctx: Dictionary, solo: Dictionary) -> void:
	var profile: Dictionary = _profile(&"lunatic")
	var ok: bool = is_equal_approx(float(profile["pps"]), 2.5) and is_equal_approx(float(profile["burst_pps"]), 5.0)
	for tier: StringName in [&"easy", &"normal", &"hard"]:
		ok = ok and not _profile(tier).has("burst_pps")
	ok = ok and absf(_pps(solo[&"lunatic"]) - 2.5) <= 0.25
	# The fastest run of eight pieces, from the journal's piece entries. The
	# tests tick at 30 Hz, where a key costs a whole tick: on a 60 Hz screen
	# the same burst is faster.
	var stamps: Array[float] = []
	for entry: Dictionary in solo[&"lunatic"]["log"]:
		if entry["kind"] == &"piece":
			stamps.append(float(entry["t"]))
	var best: float = 0.0
	for i: int in range(8, stamps.size()):
		best = maxf(best, 8.0 / (stamps[i] - stamps[i - 8]))
	ok = ok and best >= 4.0
	_case(ctx, "lunatic_averages_2_5_and_bursts_far_above_it", ok)


## Per piece: the first key comes after a think beat, never in the tick the
## piece appeared, and the AI never issues two inputs in one tick. The
## plan-time hold tap is the one decision-level input and is exempt.
static func _case_keys_follow_a_think_beat_one_per_tick(ctx: Dictionary, solo: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in TIERS:
		var log: Array = solo[tier]["log"]
		var piece_time: float = -1.0
		var first_key_seen: bool = true
		var last_key_time: float = -1.0
		var pieces: int = 0
		var think_total: float = 0.0
		for entry: Dictionary in log:
			var stamp: float = float(entry["t"])
			if entry["kind"] == &"piece":
				piece_time = stamp
				first_key_seen = false
				pieces += 1
				continue
			if entry["action"] == VersusBattle.ACTION_HOLD:
				continue
			ok = ok and stamp - last_key_time >= TICK - 0.0001
			last_key_time = stamp
			if not first_key_seen and piece_time >= 0.0:
				first_key_seen = true
				ok = ok and stamp > piece_time
				think_total += stamp - piece_time
		# On average the think beat is a real share of the piece budget.
		var budget: float = 1.0 / float(_profile(tier)["pps"])
		ok = ok and pieces > 10 and think_total / float(pieces) >= 0.15 * budget
	_case(ctx, "keys_follow_a_think_beat_and_never_share_a_tick", ok)


static func _case_no_tier_tops_out_alone(ctx: Dictionary, solo: Dictionary, fast: Dictionary) -> void:
	var ok: bool = true
	for tier: StringName in TIERS:
		ok = ok and not bool(solo[tier]["died"]) and not bool(fast[tier]["died"])
		ok = ok and int(solo[tier]["pieces"]) > 30 and int(fast[tier]["pieces"]) > 30
	_case(ctx, "no_tier_tops_out_alone_at_level_1_or_level_10", ok)


## Level 10 gravity forces a minimum pace (a piece that is not placed locks),
## but it must neither stall a tier nor hand the slow tiers a fast one's speed:
## the speed order survives and easy stays well under normal's profile pace.
static func _case_high_gravity_does_not_make_slow_tiers_fast(ctx: Dictionary, solo: Dictionary, fast: Dictionary) -> void:
	var ok: bool = true
	for i: int in TIERS.size():
		var target: float = float(_profile(TIERS[i])["pps"])
		ok = ok and _pps(fast[TIERS[i]]) >= (1.0 - PPS_TOLERANCE) * target
		if i > 0:
			ok = ok and _pps(fast[TIERS[i]]) > _pps(fast[TIERS[i - 1]])
	ok = ok and _pps(fast[&"easy"]) < float(_profile(&"normal")["pps"])
	ok = ok and _pps(fast[&"lunatic"]) <= (1.0 + PPS_TOLERANCE) * float(_profile(&"lunatic")["pps"])
	_case(ctx, "level_10_keeps_the_speed_order_without_speeding_up_slow_tiers", ok)


static func _case_attack_per_minute_rises_with_tier(ctx: Dictionary, solo: Dictionary, second: Dictionary) -> void:
	var rates: Array[float] = []
	for tier: StringName in TIERS:
		rates.append(_attack_per_minute(solo[tier], second[tier]))
	var ok: bool = rates[0] > 0.0
	for i: int in range(1, TIERS.size()):
		ok = ok and rates[i] >= ATTACK_STEP * rates[i - 1]
	# Easy is beatable by a beginner: well under a Tetris per ten seconds.
	ok = ok and rates[0] <= 12.0
	_case(ctx, "attack_per_minute_rises_tier_by_tier", ok)


static func _case_tspins_belong_to_the_top_tiers(ctx: Dictionary, solo: Dictionary) -> void:
	var ok: bool = int(solo[&"easy"]["tspins"]) == 0 and int(solo[&"normal"]["tspins"]) == 0
	ok = ok and int(solo[&"lunatic"]["tspins"]) >= 1
	_case(ctx, "easy_and_normal_never_tspin_lunatic_does", ok)


## Adjacent tiers, seats swapped between seeds so neither owns a side: the
## higher tier takes every match.
static func _case_higher_tier_wins_duels(ctx: Dictionary) -> void:
	var ok: bool = true
	for i: int in range(1, TIERS.size()):
		var wins: int = 0
		for s: int in DUEL_SEEDS:
			var flip: bool = s % 2 == 1
			var first: StringName = TIERS[i] if flip else TIERS[i - 1]
			var second: StringName = TIERS[i - 1] if flip else TIERS[i]
			var result: Dictionary = ARENA.duel(first, second, 1, SEED + s, TICK, DUEL_SECONDS)
			if int(result["winner"]) == (0 if flip else 1):
				wins += 1
		ok = ok and wins == DUEL_SEEDS
	_case(ctx, "each_tier_beats_the_tier_below_in_duels", ok)


static func _case_same_seed_reproduces_duel(ctx: Dictionary) -> void:
	var first: Dictionary = ARENA.duel(&"normal", &"hard", 3, SEED, TICK, 40.0)
	var second: Dictionary = ARENA.duel(&"normal", &"hard", 3, SEED, TICK, 40.0)
	var other: Dictionary = ARENA.duel(&"normal", &"hard", 3, SEED + 1, TICK, 40.0)
	var ok: bool = str(first) == str(second) and str(first) != str(other)
	_case(ctx, "same_seed_reproduces_the_duel_exactly", ok)
