class_name VersusAI
extends RefCounted
## Versus AI: four tiers that differ in how well AND how fast they play.
##
## It drives VersusBattle through the same press/release/tap surface a player
## uses, at most one input per frame, so it runs the exact lock/clear/send/
## garbage chain. Per piece it plans once (placement search below), waits a
## think beat, then issues its keys (rotate / move / hard drop) one key beat
## apart.
##
## Speed: every tier has a target pieces-per-second (`pps`). A piece's time
## budget 1/pps is split into the think beat (`think_share`) and evenly spaced
## key beats. The keys are compressed when gravity would carry the piece
## below the stack's peaks first (GRAVITY_SAFETY of that time), so no tier
## locks pieces mid-plan at high speed levels; the hard drop still waits for
## the piece's full budget, so a squeezed plan does not make a slow tier fast.
##
## Skill: the placement search enumerates every rotation x landing column,
## simulates the drop on a copy of the board and scores it with the tier's
## weights (_score_placement): holes and the cells burying them, height,
## bumpiness, a reserved well column, the garbage rows the placement really
## sends (VersusBattle.attack_for_event with the live B2B/combo state) and a
## per-line-count value that makes the upper tiers decline cheap singles while
## the stack is low. When the stack plus the incoming garbage is high the tier's
## danger values take over and it digs down instead. Lethal landings (lock out,
## blocked next spawn) are filtered out on every tier; `error_rate` makes a
## tier play a random lower-ranked candidate from its `error_pool`. The decision
## RNG derives from the battle seed, so one seed reproduces a whole match.
## Hold: every tier swaps when the current piece has no non-lethal landing or
## when the hold piece (the next piece, with an empty slot) beats the current
## best score by `hold_gain_margin` (easy needs a big gain, lunatic a small
## one); the tiers that keep a well also stash an I piece they cannot score a
## Tetris with yet. With no landing spot and no hold
## it still hard drops, so it can never stall.
##
## Lookahead (`lookahead_depth` >= 2): a placement's score is its reward (line
## value, attack, landing depth) plus the value of the board it leaves. The
## top `follow_candidates` placements by that 1-ply score are searched deeper
## through the queued pieces (beam FOLLOW_BEAM per level): each path is worth
## the rewards collected along it plus the value of its final board, and the
## root placement with the best path is played. The search is deterministic -
## fixed enumeration order, explicit tie-breaks, a per-plan simulation budget
## (no wall clock anywhere in a decision). The hold comparison and the mistake
## roll stay on the 1-ply ranking.
##
## T-Spins (`tspin_policy`): hard (&"constructive") and lunatic (&"advanced")
## build them on purpose.
## - Finding the spin: _reachable_t_spins() searches how the T can actually
##   get somewhere - any column drop, then grounded moves (slides under an
##   overhang, rotations either way through the real SRS kick order) - and
##   keeps the finals that rest right after a rotation and pass the 3-corner
##   rule. That covers T-Spin Doubles from either side, Triples through the
##   fifth kick, and the kick-based entries (Fin, Neo, Iso).
## - Wanting the setup: _tslot_value() recognises T-Spin Double slots (and,
##   for lunatic, Triple slots) on a board and pays for them in stages - the
##   notch, the overhang that makes it spinnable, and every cell that fills
##   the rows the spin will clear. The search can therefore climb toward a
##   setup piece by piece instead of only being paid when it is complete. The
##   hole under a slot's overhang is not charged as a hole.
## - Keeping the T: with a slot under construction a T that cannot spin goes
##   to the hold slot (or costs `t_waste_penalty` when placed flat), and a
##   held T is pulled back out when a spin is on.
## Setups are only built while the stack is safely low; in danger the tiers
## fall back to plain survival.
## (Earlier design, kept for the record:) a spin candidate was
## enumerated from the current board: every resting pre-rotation position
## the T can reach by a plain vertical drop, rotated once CW through the
## SRS kick table - the FIRST fitting kick is exactly what the battle will
## execute, so the simulated final is the executed lock. The classic shape
## this unlocks: a T resting flat across a 1-wide shaft rotates its bar
## down into the shaft (the (0,+2) kick) and locks as a Full T-Spin. The
## battle only counts a T-Spin when the lock's last move was a rotation, so
## the executor finishes a spin plan by soft-dropping the aligned piece
## onto its rest position, rotating once and hard dropping with zero
## travel - the executed lock cells are exactly the simulated candidate
## (world model stays exact, BD-02) and every spin final passed the same
## lethal filter as any other candidate BEFORE its bonus was applied, so
## spin greed can never pick a deadly landing. easy/normal (&"none")
## short-circuit every new code path and keep their exact S3b behaviour.

## Fastest key repeat the AI may reach when gravity compresses a plan.
const MIN_KEY_INTERVAL: float = 1.0 / 60.0
## Even the fastest piece (a burst, right after a hold) is looked at for a
## moment before its first key.
const MIN_THINK_INTERVAL: float = 0.04
## Share of the time-to-touch-down a plan may spend before its hard drop.
const GRAVITY_SAFETY: float = 0.7
## Per-piece tempo variation (fraction of the piece budget), seeded.
const PACE_JITTER: float = 0.15
## The reserved well column (rightmost).
const WELL_COLUMN: int = Board.BOARD_WIDTH - 1
## Tier profiles (calibrated with tools/ai_arena.gd; see tests/test_ai_tiers.gd
## for the ladder they must keep).
##   pps / think_share     speed (see the header)
##   error_rate            chance per piece to play a worse candidate, drawn
##                         from ranks 2..error_pool of the 1-ply ranking, as
##                         long as it loses at most error_max_drop points
##                         (never while in danger)
##   attack_weight         points per garbage row the placement sends
##   clear_values          points for clearing 0..4 lines while safe
##   danger_clear_values   same while in danger (stack + incoming garbage
##                         above danger_rows): digging beats setting up
##   well_weight           cost per cell in the reserved well column (0 = no well)
##   hole_weight / cover_weight   cost per hole / per cell stacked above a hole
##   lookahead_depth, follow_candidates, plan_sim_budget   search effort
##   hold_policy, hold_gain_margin, tspin_policy, tspin_bonus
##   tslot_notch / tslot_ready / tslot_fill   value of a T-slot under
##                         construction: the notch, the overhang that makes
##                         it spinnable, each filled cell of the rows it clears
##   tslot_armed           extra value once those rows are full (the spin
##                         is ready to fire)
##   tslot_triples         also build T-Spin Triple slots
##   tslot_cap             slots paid for at once
##   tslot_t_horizon       a T this near in the queue keeps slots at full value
##   t_waste_penalty       cost of laying a T flat while a slot is being built
##   style_noise           seeded +-jitter on every candidate's score: two AIs
##                         of one tier on the same piece order play differently
## An empty profile resolves to the normal entry.
const DIFFICULTY_PROFILES: Dictionary = {
	&"easy": {
		"pps": 0.55,
		"think_share": 0.5,
		"error_rate": 0.15,
		"error_pool": 6,
		"error_max_drop": 250,
		"attack_weight": 0,
		"clear_values": [0, 1000, 2000, 3000, 4000],
		"danger_clear_values": [0, 1000, 2000, 3000, 4000],
		"danger_rows": 9,
		"well_weight": 0,
		"hole_weight": 60,
		"cover_weight": 6,
		"lookahead_depth": 1,
		"hold_policy": &"regular",
		"hold_gain_margin": 600,
		"style_noise": 30,
		"tspin_policy": &"none",
		"tspin_bonus": 0,
		"plan_sim_budget": 96,
		"follow_candidates": 0,
		"danger_soft_rows": 12,
	},
	&"normal": {
		"pps": 0.9,
		"think_share": 0.4,
		"error_rate": 0.08,
		"error_pool": 3,
		"error_max_drop": 300,
		"attack_weight": 150,
		"clear_values": [0, 150, 350, 600, 1500],
		"danger_clear_values": [0, 800, 1600, 2400, 3600],
		"danger_rows": 9,
		"well_weight": 12,
		"hole_weight": 60,
		"cover_weight": 8,
		"lookahead_depth": 2,
		"hold_policy": &"regular",
		"hold_gain_margin": 350,
		"style_noise": 30,
		"tspin_policy": &"none",
		"tspin_bonus": 0,
		"plan_sim_budget": 320,
		"follow_candidates": 5,
		"danger_soft_rows": 12,
	},
	&"hard": {
		"pps": 1.4,
		"think_share": 0.35,
		"error_rate": 0.02,
		"error_pool": 2,
		"error_max_drop": 300,
		"attack_weight": 300,
		"clear_values": [0, 40, 120, 300, 1200],
		"danger_clear_values": [0, 800, 1600, 2400, 3600],
		"danger_rows": 11,
		"well_weight": 25,
		"hole_weight": 70,
		"cover_weight": 12,
		"lookahead_depth": 3,
		"hold_policy": &"regular",
		"hold_gain_margin": 200,
		"style_noise": 30,
		"tspin_policy": &"constructive",
		"tspin_bonus": 300,
		"tslot_notch": 60,
		"tslot_ready": 220,
		"tslot_fill": 40,
		"tslot_armed": 500,
		"tslot_triples": false,
		"tslot_cap": 1,
		"tslot_t_horizon": 4,
		"t_waste_penalty": 250,
		"plan_sim_budget": 640,
		"follow_candidates": 4,
		"danger_soft_rows": 12,
	},
	&"lunatic": {
		# 2.5 on average: about 2.2 between bursts, 5 inside them (see
		# _schedule_beats).
		"pps": 2.5,
		"burst_pps": 5.0,
		"burst_share": 0.2,
		"burst_pieces": [6, 10],
		"think_share": 0.3,
		"error_rate": 0.0,
		"error_pool": 2,
		"error_max_drop": 0,
		"attack_weight": 350,
		"clear_values": [0, 20, 100, 300, 1400],
		"danger_clear_values": [0, 800, 1600, 2400, 3600],
		"danger_rows": 12,
		"well_weight": 30,
		"hole_weight": 80,
		"cover_weight": 15,
		"lookahead_depth": 4,
		"hold_policy": &"regular",
		"hold_gain_margin": 150,
		"style_noise": 35,
		"tspin_policy": &"advanced",
		"tspin_bonus": 450,
		"tslot_notch": 60,
		"tslot_ready": 220,
		"tslot_fill": 40,
		"tslot_armed": 500,
		"tslot_triples": false,
		"tslot_cap": 1,
		"tslot_t_horizon": 4,
		"t_waste_penalty": 900,
		"plan_sim_budget": 1024,
		"follow_candidates": 4,
		"danger_soft_rows": 12,
	},
}
## Safety valve: an unreachable plan (walled-in piece) forces a hard drop
## after this many queued actions instead of retrying forever.
const MAX_EXECUTE_STEPS: int = 40
## Bounded wait for a hold tap to swap the piece in (measured in AI action
## steps). The swap normally arrives on the next battle frame; the bound only
## exists so a degenerate no-op tap can never stall the AI - past the limit
## the S2 hard-drop fallback plan resumes.
const HOLD_MAX_WAIT_STEPS: int = 20
const HEIGHT_WEIGHT: int = 10
const BUMPINESS_WEIGHT: int = 20
## Cost per row of a 1-wide shaft deeper than DEEP_WELL_FREE_ROWS outside the
## reserved well: only an I piece fills those.
const DEEP_WELL_WEIGHT: int = 20
const DEEP_WELL_FREE_ROWS: int = 2
## Landing depth: low landings fill notches instead of topping towers.
const LOW_PLACEMENT_WEIGHT: int = 6
## Lookahead (see the header). The follow search shares the plan's simulation
## budget minus HOLD_EVAL_RESERVE, so the hold evaluation always keeps room
## to run. FOLLOW_DEAD_END is the path value of a queued piece with no
## non-lethal landing anywhere.
const FOLLOW_BEAM: int = 2
const FOLLOW_DEAD_END: int = -100000
const HOLD_EVAL_RESERVE: int = 64
## A root candidate whose after-board reaches more than the profile's
## `danger_soft_rows` above the floor loses FOLLOW_DANGER_STEP points per row
## beyond that, so a promising setup can never walk the stack into the spawn.
const FOLLOW_DANGER_STEP: int = 200
## TSPIN_B2B_MULT lifts the profiled `tspin_bonus` while the side's B2B chain
## is active - constructive (lunatic) only.
const TSPIN_B2B_MULT: float = 1.25
## Digging (see _build_plan) ends once the stack plus the incoming garbage is
## this many rows under the tier's danger_rows.
const DANGER_RELEASE_ROWS: int = 4
## While digging: cost per row of the tallest column, and the share of the
## usual time a piece gets (a player in trouble plays faster).
const DANGER_PEAK_WEIGHT: int = 60
const DANGER_PACE: float = 0.8
## A burst is this much likelier to start on a piece planned under pressure.
const BURST_PRESSURE_FACTOR: float = 3.0
## Pieces the pace is averaged over, the share of the time lost (or gained)
## over them that one piece makes up for, and the largest share of a piece's
## time that may change.
## Share of the plan's simulation budget a piece inside a burst gets: played
## on instinct, and planned fast enough to keep the burst's pace on screen.
const BURST_SIM_SHARE: float = 0.5
const PACE_WINDOW: int = 24
const PACE_CORRECTION: float = 0.25
const PACE_CORRECTION_MAX: float = 0.3
## Upper bound of the constructive shaping term (S3c): at most this many
## spin-ready shapes are paid for per after-board, so rewarding ragged
## terrain can never out-bribe the height/hole survival terms.
## Grounded moves (slides, rotations) tried after the drop when looking for a
## spin entry.
const SPIN_GROUND_DEPTH: int = 3
## Cells a T-Spin Double / Triple slot needs filled in the rows it clears.
const TSD_FILL_CELLS: int = 16
const TST_FILL_CELLS: int = 26
## A slot whose T is beyond the profile's horizon is worth this share.
const TSLOT_FAR_FACTOR: float = 0.5
## Pacing journal ring capacity (S2): deep enough to hold a full pacing-test
## run (tens of blocks with all their keys) without evicting its first blocks.
const ACTION_LOG_CAPACITY: int = 2048

## Time one plan may take out of a single frame, in microseconds. 0 (the
## default, and what the headless tools and tests use) plans each piece in one
## go; the versus scene sets it so a long search is spread over several frames
## instead of freezing one. The frames spent count as thinking time, and the
## search itself - every simulation, score and choice - is the same either way.
var frame_budget_usec: int = 0
var _slice_start: int = 0
var _planning: bool = false
var _planning_time: float = 0.0
## Keeps an AI whose plan is suspended alive until the plan has finished.
static var _suspended_plans: Dictionary = {}

var _battle: VersusBattle
var _side: int
## Pacing state: `_beat_timer` accumulates frame delta inside the active beat,
## `_awaiting_think` selects the think beat (before a piece's first key) versus
## the key beat (between keys). Both intervals are set per piece by
## _schedule_beats. tick() issues at most one action per frame.
var _beat_timer: float = 0.0
var _pps: float = 0.9
## Bursts (profile keys burst_pps, burst_share, burst_pieces): a run of pieces
## played at burst_pps. `pps` stays the average, so the pace between bursts
## (_cruise_pps) is a little under it. 0 = the tier never bursts.
var _burst_pps: float = 0.0
var _cruise_pps: float = 0.9
var _burst_chance: float = 0.0
var _burst_pieces: Array = [6, 10]
var _burst_left: int = 0
var _bursts_started: int = 0
var _burst_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## When the last PACE_WINDOW pieces were planned: a bursting tier steers its
## cruise pace by them, so its average holds at `pps` whatever the bursts,
## the hold swaps and the frame rate did to it.
var _pace_marks: Array[float] = []
var _think_share: float = 0.4
var _think_interval: float = 0.4
var _key_interval: float = 0.15
## Simulated second before which the current piece is not hard dropped: when
## gravity squeezed the keys, the aligned piece rides down (or locks by
## itself) instead of turning a slow tier into a fast one.
var _drop_at: float = 0.0
var _awaiting_think: bool = true
## Bounded pacing journal (S2 read surface, `action_log()`): one `&"piece"`
## entry per planned block (its decision beat start) and one `&"action"` entry
## per issued input, each stamped with the simulated second. The ring keeps
## the most recent ACTION_LOG_CAPACITY entries.
var _sim_time: float = 0.0
var _action_log: Array = []
var _profile: Dictionary = {}
var _planned_piece: Tetromino = null
var _plan_rotation: int = 0
var _plan_x: int = 0
var _execute_steps: int = 0
## Decision RNG (S2): seeded from the battle seed, one roll per planned piece,
## so the same seed reproduces the exact decision sequence.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Playing-style RNG: its own stream (derived from the same seed) so the
## decision stream above keeps its fixed draws per piece.
var _style_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _style_noise: int = 0
var _error_rate: float = 0.0
var _error_pool: int = 2
var _error_max_drop: int = 300
var _attack_weight: int = 0
var _clear_values: Array = [0, 1000, 2000, 3000, 4000]
var _danger_clear_values: Array = [0, 1000, 2000, 3000, 4000]
var _danger_rows: int = 99
var _well_weight: int = 0
var _hole_weight: int = 60
var _cover_weight: int = 0
## Per-plan scoring context: the side's live B2B/combo state, whether the
## board is in danger, and whether the scorer is inside the follow search
## (whose pieces do not continue the current combo).
var _ctx_b2b: bool = false
var _ctx_combo: int = 0
var _ctx_danger: bool = false
var _panic: bool = false
var _ctx_follow: bool = false
## Board-value half of the most recent _score_placement result (the other
## half is the placement's reward).
var _last_board_value: int = 0
var _lookahead_depth: int = 1
var _follow_candidates: int = 0
var _danger_soft_rows: int = 12
var _pieces_planned: int = 0
var _mistakes_made: int = 0
## Hold state (S3a). `_held_this_drop` debounces one hold per drop (reset when
## a fresh drop's piece is planned, set when the AI taps hold, kept across the
## swap so the swapped-in piece cannot re-trigger); `_hold_swap_pending` marks
## that the next planned piece is the swap result of our own hold tap;
## `_awaiting_hold_swap` pauses plan execution until the swapped piece shows
## up (bounded by HOLD_MAX_WAIT_STEPS).
var _hold_policy: StringName = &"none"
var _hold_gain_margin: int = 0
var _plan_sim_budget: int = 320
var _full_sim_budget: int = 320
var _held_this_drop: bool = false
var _hold_swap_pending: bool = false
var _awaiting_hold_swap: bool = false
var _hold_wait_steps: int = 0
var _holds_made: int = 0
var _bottom_out_holds: int = 0
## Deterministic simulation accounting (BC-02): every
## _simulate_placement+_score_placement pair is one sim. Reset when a plan
## starts and never reset until the next plan, so the accumulated value at
## plan end IS this plan's consumption and `last_plan_sims()` stays readable
## for tests until the next plan overwrites it.
var _plan_sims: int = 0
## T-Spin strategy state. `_spin_plan` marks a chosen spin candidate: tick()
## aligns the piece to the entry's drop column and rotation, soft-drops it to
## rest, plays the entry's grounded moves (`_ground_moves`, waiting for the
## piece to settle between them) and finishes with a zero-travel hard drop.
## `_spin_phase`: 0 = aligning, 1 = grounded moves, 2 = last move issued.
## `_tspin_policy` gates every T-Spin code path (none = inert).
var _tspin_policy: StringName = &"none"
var _tspin_bonus: int = 0
var _tslot_notch: int = 0
var _tslot_ready: int = 0
var _tslot_fill: int = 0
var _tslot_armed: int = 0
var _tslot_triples: bool = false
var _tslot_cap: int = 1
## Column and bottom row of the armed Double slot the last _tslot_value call
## saw (both rows full, the T can come in); -1 without one.
var _armed_col: int = -1
var _armed_row: int = -1
var _tslot_t_horizon: int = 4
var _t_waste_penalty: int = 0
var _spin_plan: bool = false
var _spin_phase: int = 0
var _ground_moves: Array = []
## Per-plan context: a T is at hand (piece, hold or near in the queue), and
## the board being planned on already holds a T-slot under construction.
var _ctx_t_near: bool = false
var _ctx_slot_started: bool = false
var _spins_planned: int = 0
var _slot_plans: int = 0
## Set by the slot scan when it found a spinnable (overhang in place) slot.
var _slot_is_ready: bool = false
## Calibration counters (see tools): plans that started on a board with a
## spinnable slot, how full its rows were, and how often the piece was a T.
var _slot_fill_seen: int = 0
var _ready_plans: int = 0
var _ready_fill_sum: int = 0
var _ready_t_plans: int = 0


func _init(battle: VersusBattle, side: int, profile: Dictionary = {}, rng_seed: int = 0) -> void:
	_battle = battle
	_side = side
	# Empty/missing profile = the normal entry, so default-constructed AIs
	# (and every pre-difficulty call site) keep their exact tick rhythm.
	_profile = DIFFICULTY_PROFILES[&"normal"] if profile.is_empty() else profile
	_pps = maxf(0.05, float(_profile.get("pps", 0.9)))
	_think_share = clampf(float(_profile.get("think_share", 0.4)), 0.05, 0.9)
	_burst_pps = float(_profile.get("burst_pps", 0.0))
	_cruise_pps = _pps
	if _burst_pps > _pps:
		# `share` of the pieces at burst_pps and the rest at the cruise pace
		# average out to `pps`; a burst starts on a cruise piece with the
		# chance that makes bursts that share of all pieces.
		var share: float = clampf(float(_profile.get("burst_share", 0.2)), 0.0, 0.9)
		_burst_pieces = _profile.get("burst_pieces", _burst_pieces)
		var mean_length: float = (float(_burst_pieces[0]) + float(_burst_pieces[1])) / 2.0
		_cruise_pps = (1.0 - share) / (1.0 / _pps - share / _burst_pps)
		_burst_chance = share / ((1.0 - share) * mean_length)
	_error_rate = float(_profile.get("error_rate", 0.0))
	_error_pool = int(_profile.get("error_pool", 2))
	_error_max_drop = int(_profile.get("error_max_drop", 300))
	_attack_weight = int(_profile.get("attack_weight", 0))
	_clear_values = _profile.get("clear_values", _clear_values)
	_danger_clear_values = _profile.get("danger_clear_values", _clear_values)
	_danger_rows = int(_profile.get("danger_rows", 99))
	_well_weight = int(_profile.get("well_weight", 0))
	_hole_weight = int(_profile.get("hole_weight", 60))
	_cover_weight = int(_profile.get("cover_weight", 0))
	_lookahead_depth = int(_profile.get("lookahead_depth", 1))
	_follow_candidates = int(_profile.get("follow_candidates", 0))
	_danger_soft_rows = int(_profile.get("danger_soft_rows", 12))
	_hold_policy = StringName(_profile.get("hold_policy", &"none"))
	_hold_gain_margin = int(_profile.get("hold_gain_margin", 0))
	_plan_sim_budget = int(_profile.get("plan_sim_budget", 320))
	_full_sim_budget = _plan_sim_budget
	_tspin_policy = StringName(_profile.get("tspin_policy", &"none"))
	_tspin_bonus = int(_profile.get("tspin_bonus", 0))
	_tslot_notch = int(_profile.get("tslot_notch", 0))
	_tslot_ready = int(_profile.get("tslot_ready", 0))
	_tslot_fill = int(_profile.get("tslot_fill", 0))
	_tslot_armed = int(_profile.get("tslot_armed", 0))
	_tslot_triples = bool(_profile.get("tslot_triples", false))
	_tslot_cap = int(_profile.get("tslot_cap", 1))
	_tslot_t_horizon = int(_profile.get("tslot_t_horizon", 4))
	_t_waste_penalty = int(_profile.get("t_waste_penalty", 0))
	_style_noise = int(_profile.get("style_noise", 0))
	_rng.seed = rng_seed
	_style_rng.seed = hash([rng_seed, "style"])
	_burst_rng.seed = hash([rng_seed, "burst"])


## Read-only view of the active difficulty profile (versus.gd and the tests
## read it back; callers must not mutate it).
func profile() -> Dictionary:
	return _profile


## True while the AI plays a burst (pieces at the profile's burst_pps).
func in_burst() -> bool:
	return _burst_left > 0


## Bursts started so far.
func bursts_started() -> int:
	return _bursts_started


## Number of new pieces this AI has planned (one per _build_plan call).
func pieces_planned() -> int:
	return _pieces_planned


## Number of executed mistakes: plans switched to a lower-ranked non-lethal
## candidate by the error_rate roll.
func mistakes_made() -> int:
	return _mistakes_made


## Number of hold taps issued by this AI (S3a): both bottom-out and regular
## trigger reasons count.
func holds_made() -> int:
	return _holds_made


## Number of hold taps whose trigger was "the current piece has no non-lethal
## landing" (normal's bottom_out policy; the hard/lunatic regular policy
## counts its bottom-out holds here too).
func bottom_out_holds() -> int:
	return _bottom_out_holds


## Deterministic simulations consumed by the most recent plan (BC-02): one
## per _simulate_placement+_score_placement pair, hold-swap evaluation
## included. Sampled by tests any time before the next plan starts (the value
## is not reset until the next _build_plan).
func last_plan_sims() -> int:
	return _plan_sims


## Copy of the bounded pacing journal (S2 read surface). Each entry is
## {"t": simulated seconds, "kind": &"piece"|&"action", "action": name};
## `&"piece"` marks the tick a new block was planned (its decision beat
## starts), `&"action"` marks one issued input (rotate / move_left /
## move_right / hard_drop / hold / soft_drop). `_sim_time` accumulates in
## tick(), so the stamps are exact simulated time, never wall clock.
func action_log() -> Array:
	return _action_log.duplicate()


func _log_piece() -> void:
	_append_log(&"piece", &"")


func _log_action(action: StringName) -> void:
	_append_log(&"action", action)


func _append_log(kind: StringName, action: StringName) -> void:
	_action_log.append({"t": _sim_time, "kind": kind, "action": action})
	if _action_log.size() > ACTION_LOG_CAPACITY:
		_action_log.pop_front()


func tick(delta: float) -> void:
	if _battle == null:
		return
	if _battle.phase() != VersusBattle.Phase.PLAYING or _battle.is_paused():
		return
	_sim_time += delta
	if _planning:
		_planning_time += delta
		return
	var piece: Tetromino = _battle.current_piece(_side)
	if piece == null:
		_planned_piece = null
		return
	# A new piece instance must be planned exactly once before it acts (S1
	# compared only the piece TYPE, so a same-type successor reused a stale
	# plan the lethal filter never saw - that hole let the AI kill itself,
	# BD-02). Spawns always create fresh Tetromino instances, so identity is
	# the exact "new piece" test and also keeps one RNG roll per piece. S2
	# pacing: the plan opens the block's decision beat - the piece entry is
	# journaled and the think timer starts empty, so the first key can only
	# fire after `_think_interval` (the plan-time hold tap below is the one
	# decision-level input and is journaled on this same beat).
	if piece != _planned_piece:
		_log_piece()
		var swapped_in: bool = _hold_swap_pending
		_planning = true
		_planning_time = 0.0
		_slice_start = Time.get_ticks_usec()
		await _build_plan(piece)
		_planning = false
		_suspended_plans.erase(get_instance_id())
		var spread: bool = _planning_time > 0.0
		if spread and _battle.current_piece(_side) != piece:
			# The piece went away while its plan was spread over frames.
			return
		_execute_steps = 0
		_awaiting_think = true
		_beat_timer = _planning_time
		_schedule_beats(piece, swapped_in)
		if spread:
			# This call's frame is long over; the next tick carries on.
			return
	_beat_timer += delta
	if _awaiting_think:
		if _beat_timer < _think_interval:
			return
		# Decision beat done: the first key issues on this same frame (one
		# action per frame), and the leftover carries into the key phase so
		# successive keys keep the key interval without losing a frame.
		_awaiting_think = false
		_beat_timer -= _think_interval
	else:
		if _beat_timer < _key_interval:
			return
		_beat_timer -= _key_interval
	if _awaiting_hold_swap:
		# A hold tap is in flight: wait for the swapped-in piece instead of
		# executing the current (all-lethal fallback) plan, which would throw
		# the piece away before the hold could help (BD-07 hold layer). The
		# wait is measured in AI action beats, so it stays bounded by
		# HOLD_MAX_WAIT_STEPS exactly like the v1 rhythm.
		_hold_wait_steps += 1
		if _hold_wait_steps <= HOLD_MAX_WAIT_STEPS:
			return
	# Defensive: the swap never arrived - resume the fallback plan below.
	_awaiting_hold_swap = false
	_hold_wait_steps = 0
	# Spin finish phases (S3c): once the soft descent started, the alignment
	# ladder is bypassed - the at-rest rotation below INTENTIONALLY leaves
	# piece.rotation != _plan_rotation (plan rotation is the PRE state), and
	# the ladder must not "correct" it back or the zero-travel hard drop
	# never fires.
	if _spin_plan and _spin_phase >= 1:
		if _spin_phase == 1:
			if _battle.piece_pos(_side) == _battle.ghost_pos(_side):
				# At rest: play the next grounded move. The soft drop stays
				# held between moves so the piece settles again after each;
				# before the last one it is released, because nothing may
				# move the piece between that rotation and the lock.
				var move: StringName = _ground_moves.pop_front() if not _ground_moves.is_empty() else VersusBattle.ACTION_ROTATE
				if _ground_moves.is_empty():
					_battle.release(_side, VersusBattle.ACTION_SOFT_DROP)
					_spin_phase = 2
				_log_action(move)
				_battle.tap(_side, move)
			elif _consume_step():
				_battle.release(_side, VersusBattle.ACTION_SOFT_DROP)
			return
		_spin_phase = 0
		_spin_plan = false
		_log_action(VersusBattle.ACTION_HARD_DROP)
		_battle.tap(_side, VersusBattle.ACTION_HARD_DROP)
		return
	if piece.rotation != _plan_rotation:
		if _consume_step():
			return
		var rotate_action: StringName = VersusBattle.ACTION_ROTATE
		if (_plan_rotation - piece.rotation + 4) % 4 == 3:
			rotate_action = VersusBattle.ACTION_ROTATE_CCW
		_log_action(rotate_action)
		_battle.tap(_side, rotate_action)
		return
	var x: int = _battle.piece_pos(_side).x
	if x < _plan_x:
		if _consume_step():
			return
		_log_action(VersusBattle.ACTION_MOVE_RIGHT)
		_battle.tap(_side, VersusBattle.ACTION_MOVE_RIGHT)
		return
	if x > _plan_x:
		if _consume_step():
			return
		_log_action(VersusBattle.ACTION_MOVE_LEFT)
		_battle.tap(_side, VersusBattle.ACTION_MOVE_LEFT)
		return
	# Aligned. A spin plan (S3c) first soft-drops the piece onto its rest
	# position: the battle only classifies a T-Spin when the lock's last move
	# was a rotation, and every successful move - including the hard drop's
	# own travel - clears that flag, so only a zero-travel hard drop after
	# the at-rest rotation keeps it set through the lock. The rotation's
	# first fitting SRS kick is the one the plan enumerated, and the planned
	# final rests, so the hard drop travels zero and the lock is counted.
	# The step-budget fallback degrades to a plain uncounted lock. No
	# landing spot was found -> _spin_plan is false -> plain hard drop.
	if _spin_plan:
		_spin_phase = 1
		_log_action(VersusBattle.ACTION_SOFT_DROP)
		_battle.press(_side, VersusBattle.ACTION_SOFT_DROP)
		return
	if _sim_time < _drop_at:
		return
	_log_action(VersusBattle.ACTION_HARD_DROP)
	_battle.tap(_side, VersusBattle.ACTION_HARD_DROP)


## Sets this piece's think and key beats from the tier's pps (see the header).
## `swapped_in` marks the piece our own hold tap brought in: the decision was
## already paid for, so it gets half a budget.
func _schedule_beats(piece: Tetromino, swapped_in: bool) -> void:
	var pos: Vector2i = _battle.piece_pos(_side)
	var turn: int = (_plan_rotation - piece.rotation + 4) % 4
	var keys: int = (1 if turn == 3 else turn) + absi(_plan_x - pos.x) + 1
	var pace: float = _cruise_pps
	if _burst_chance > 0.0 and not swapped_in:
		# Bursts have their own random stream: the plan's stays aligned.
		if _burst_left > 0:
			_burst_left -= 1
			pace = _burst_pps
		elif _burst_rng.randf() < _burst_chance * (BURST_PRESSURE_FACTOR if _ctx_danger else 1.0):
			_burst_left = _burst_rng.randi_range(int(_burst_pieces[0]), int(_burst_pieces[1])) - 1
			_bursts_started += 1
			pace = _burst_pps
	elif _burst_left > 0:
		pace = _burst_pps
	var budget: float = (1.0 / pace) * (1.0 + _rng.randf_range(-PACE_JITTER, PACE_JITTER))
	if _burst_chance > 0.0:
		# A piece swapped in by hold is the same placement as the one it replaced.
		if not swapped_in:
			_pace_marks.append(_sim_time)
		if _pace_marks.size() > PACE_WINDOW:
			_pace_marks.pop_front()
		if pace < _burst_pps and _pace_marks.size() >= 4:
			var late: float = _sim_time - _pace_marks[0] - float(_pace_marks.size() - 1) / _pps
			budget -= clampf(late * PACE_CORRECTION, -PACE_CORRECTION_MAX * budget, PACE_CORRECTION_MAX * budget)
			budget = maxf(budget, 1.0 / _burst_pps)
	if swapped_in:
		budget *= 0.5
	if _ctx_danger and pace < _burst_pps:
		budget *= DANGER_PACE
	var key: float = maxf(MIN_KEY_INTERVAL, budget * (1.0 - _think_share) / float(keys))
	var think: float = maxf(MIN_THINK_INTERVAL, budget - key * float(keys - 1))
	# Sideways moves must finish while the piece is still above every column,
	# or the stack's peaks wall it in.
	var bottom: int = pos.y
	for cell: Vector2i in piece.get_cells():
		bottom = maxi(bottom, pos.y + cell.y)
	var top_row: int = _battle.board(_side).highest_occupied_row()
	var free_rows: int = (top_row if top_row >= 0 else Board.BOARD_HEIGHT) - bottom - 1
	var allowed: float = GRAVITY_SAFETY * float(maxi(0, free_rows)) * VersusBattle.gravity_interval(_battle.level(_side))
	var planned: float = think + key * float(keys - 1)
	_drop_at = 0.0
	if planned > allowed:
		var squeeze: float = allowed / planned
		think *= squeeze
		key = maxf(MIN_KEY_INTERVAL, key * squeeze)
		_drop_at = _sim_time + budget
	_think_interval = think
	_key_interval = key


## Returns true when the action budget was exhausted and a hard-drop fallback
## was issued instead of the planned step.
## True once this frame's share of the plan is used up (see frame_budget_usec).
func _frame_spent() -> bool:
	return frame_budget_usec > 0 and Time.get_ticks_usec() - _slice_start >= frame_budget_usec


## Suspends the plan until the next frame.
func _next_frame() -> void:
	_suspended_plans[get_instance_id()] = self
	await (Engine.get_main_loop() as SceneTree).process_frame
	_slice_start = Time.get_ticks_usec()


func _consume_step() -> bool:
	_execute_steps += 1
	if _execute_steps <= MAX_EXECUTE_STEPS:
		return false
	_execute_steps = 0
	_log_action(VersusBattle.ACTION_HARD_DROP)
	_battle.tap(_side, VersusBattle.ACTION_HARD_DROP)
	return true


## Plans one piece: every candidate landing is simulated and scored; lethal
## landings (see _is_lethal_landing) are excluded on every tier. Tiers that
## look ahead re-rank the near-best candidates by their follow value. With
## probability `error_rate` the plan switches to a lower-ranked candidate (see
## the profile keys). When every candidate is lethal the plain best is kept as
## the fallback - but the hold policy gets the first response (_evaluate_hold).
## Exactly two RNG draws are consumed per planned piece (plus one in
## _schedule_beats), so the decision stream stays aligned across tiers.
## Simulations share the profile's plan_sim_budget; the lookahead leaves
## HOLD_EVAL_RESERVE sims for the hold evaluation.
func _build_plan(piece: Tetromino) -> void:
	_planned_piece = piece
	_plan_rotation = piece.rotation
	_plan_x = _battle.piece_pos(_side).x
	_pieces_planned += 1
	_plan_sims = 0
	_plan_sim_budget = int(float(_full_sim_budget) * (BURST_SIM_SHARE if _burst_left > 0 else 1.0))
	_awaiting_hold_swap = false
	_hold_wait_steps = 0
	_spin_plan = false
	_spin_phase = 0
	if _tspin_policy != &"none":
		# A stale soft-drop hold from an interrupted spin descent must never
		# leak into the next piece (the held flag survives pieces).
		_battle.release(_side, VersusBattle.ACTION_SOFT_DROP)
	# The swap result of our own hold tap keeps `_held_this_drop` set (the
	# same drop continues, so the swapped piece cannot re-trigger a hold);
	# any other new piece instance starts a fresh drop.
	if _hold_swap_pending:
		_hold_swap_pending = false
	else:
		_held_this_drop = false
	var mistake_roll: float = _rng.randf()
	var mistake_pick: float = _rng.randf()
	var grid: Array = _copy_board_grid(_battle.board(_side))
	_ctx_b2b = _battle.b2b_active(_side)
	_ctx_combo = _battle.combo(_side)
	_ctx_follow = false
	# Near death the AI switches to digging: clear lines now, keep the peak
	# down, no setups - and it stays that way until the stack is well clear of
	# the line again, instead of flipping back the moment one row is gone.
	var pressure: int = _max_height(grid) + _battle.pending_garbage(_side)
	if pressure > _danger_rows:
		_panic = true
	elif pressure <= _danger_rows - DANGER_RELEASE_ROWS:
		_panic = false
	_ctx_danger = _panic
	_ctx_t_near = _t_at_hand(piece.piece_type)
	_slot_is_ready = false
	_slot_fill_seen = 0
	_ctx_slot_started = _tslot_ready > 0 and not _ctx_danger and _tslot_value(grid, _column_heights(grid)) > 0
	if _slot_is_ready:
		_ready_plans += 1
		_ready_fill_sum += _slot_fill_seen
		if piece.piece_type == Tetromino.PieceType.T:
			_ready_t_plans += 1
	_ground_moves = []
	var next_type: int = _next_piece_type()
	# Absolute-cell dedup: only rotation pairs whose ABSOLUTE resting cells
	# are bit-identical collapse (O all four; most other pieces keep 2-4
	# distinct entries - see _unique_rotations). Only the first occurrence is
	# simulated. The placement SET is unchanged and duplicates were no-ops
	# in the strict-greater races, so every score, tie-break and outcome stays
	# bit-identical while the simulation count drops.
	var seen_placements: Dictionary = {}
	# Non-lethal candidates in enumeration order.
	var cand_scores: Array[int] = []
	var cand_rotations: Array[int] = []
	var cand_xs: Array[int] = []
	var cand_afters: Array = []
	var cand_boards: Array[int] = []
	# Parallel "this candidate is a S3c spin entry" flag (T pieces only).
	var cand_is_spin: Array[bool] = []
	# The spin entry behind a spin candidate ({} for a plain landing).
	var cand_spin: Array[Dictionary] = []
	var collect: bool = true
	var best_score: int = 0
	var best_rotation: int = 0
	var best_x: int = 0
	var found: bool = false
	var safe_best_score: int = 0
	var safe_best_rotation: int = 0
	var safe_best_x: int = 0
	var found_safe: bool = false
	var safe_best_is_spin: bool = false
	var safe_best_spin: Dictionary = {}
	var safe_best_cleared: int = 0
	# S3c spin-entry enumeration (T pieces, opportunistic/constructive only;
	# runs BEFORE the plain enumeration on purpose). The battle counts a
	# T-Spin only when the lock's last move was a rotation, so a spin
	# candidate is planned as the rotation's PRE state: every pre-rotation
	# rest position a plain vertical drop can reach is rotated once CW
	# through the SRS kick table - the FIRST fitting kick is exactly the one
	# the battle's _handle_rotation executes, so the final placement
	# simulated here is bit-exact the executed lock. Only finals that REST
	# (the zero-travel hard drop afterwards must not travel) and classify as
	# a spin (>=3 filled corners, same rule as Scoring.classify_t_spin)
	# become candidates; the lethal filter still runs BEFORE any bonus is
	# applied, so spin greed can never select a deadly landing (BD-02).
	# Probe-verified on the calibration seeds, EVERY kick final is also
	# reachable by a plain vertical drop, so the spin entries register their
	# placement keys first and the dedup swallows the plain twin of each
	# entry instead of the other way round: the placement set (and the
	# candidate count) never exceeds the plain enumeration's, a follow-set
	# is never polluted by duplicate twins, and a spin-reachable placement
	# is always judged and executed as the spin it can be. The final
	# rotation uniquely determines the pre state, so at most one spin entry
	# exists per final placement. Enumeration order, dedup and the shared
	# simulation budget are inherited from the main race (BC-02).
	if _tspin_policy != &"none" and piece.piece_type == Tetromino.PieceType.T:
		for entry: Dictionary in _reachable_t_spins(grid):
			if _plan_sims >= _plan_sim_budget:
				break
			var final_rotation: int = int(entry["rotation"])
			var spin_x: int = int(entry["x"])
			var spin_y: int = int(entry["y"])
			var spin_probe: Tetromino = Tetromino.new(piece.piece_type)
			spin_probe.rotation = final_rotation
			var final_cells: Array[Vector2i] = spin_probe.get_cells()
			var spin_key: int = _placement_key(final_cells, spin_x, spin_y)
			seen_placements[spin_key] = true
			_plan_sims += 1
			var spin_simulation: Dictionary = _simulate_placement(grid, final_cells, spin_x, spin_y)
			var spin_kind: int = _tspin_landing_kind(grid, piece.piece_type, final_rotation, spin_x, spin_y, int(entry["kick_index"]))
			var spin_candidate: int = _score_placement(spin_simulation["after"], int(spin_simulation["cleared"]), spin_y, spin_kind)
			var spin_board: int = _last_board_value
			# The spin bonus is for the spins worth building for: with a slot
			# under construction a single is not one of them.
			if spin_kind != Scoring.TSpinKind.NONE and (int(spin_simulation["cleared"]) >= 2 or not _ctx_slot_started):
				spin_candidate += _tspin_candidate_bonus(int(spin_simulation["cleared"]), spin_kind)
			spin_candidate += _style_jitter()
			entry["cleared"] = int(spin_simulation["cleared"])
			# Spinning into a slot before its rows are full throws the T away
			# just like laying it flat does.
			if _ctx_slot_started and int(spin_simulation["cleared"]) < 2:
				spin_candidate -= _t_waste_penalty
			var spin_exec_x: int = int(entry["pre_x"])
			if not found or spin_candidate > best_score:
				found = true
				best_score = spin_candidate
				best_rotation = final_rotation
				best_x = spin_exec_x
			if _is_lethal_landing(final_cells, spin_x, spin_y, spin_simulation["after"], next_type):
				continue
			if collect:
				cand_scores.append(spin_candidate)
				cand_rotations.append(final_rotation)
				# The execution column of a spin entry is its PRE-rotation
				# drop column; the rotation's kick carries the piece to the
				# final column at lock time (see tick()).
				cand_xs.append(spin_exec_x)
				cand_afters.append(spin_simulation["after"])
				cand_boards.append(spin_board)
				cand_is_spin.append(true)
				cand_spin.append(entry)
			if not found_safe or spin_candidate > safe_best_score:
				found_safe = true
				safe_best_score = spin_candidate
				safe_best_rotation = final_rotation
				safe_best_x = spin_exec_x
				safe_best_is_spin = true
				safe_best_spin = entry
				safe_best_cleared = int(spin_simulation["cleared"])
	var tops: PackedInt32Array = _column_tops(grid)
	var scan_from: int = Board.BOARD_HEIGHT
	for top: int in tops:
		scan_from = mini(scan_from, top)
	for rotation: int in 4:
		if _plan_sims >= _plan_sim_budget:
			break
		var probe: Tetromino = Tetromino.new(piece.piece_type)
		probe.rotation = rotation
		var cells: Array[Vector2i] = probe.get_cells()
		for x: int in range(-3, Board.BOARD_WIDTH):
			if _plan_sims >= _plan_sim_budget:
				break
			if _frame_spent():
				await _next_frame()
			var y: int = _drop_y_fast(grid, cells, x, tops)
			if y < 0:
				continue
			var placement_key: int = _placement_key(cells, x, y)
			if seen_placements.has(placement_key):
				continue
			seen_placements[placement_key] = true
			_plan_sims += 1
			var simulation: Dictionary = _simulate_placement(grid, cells, x, y)
			var candidate: int = _score_placement(simulation["after"], int(simulation["cleared"]), y, Scoring.TSpinKind.NONE, mini(scan_from, y))
			var candidate_board: int = _last_board_value
			candidate += _style_jitter()
			# A T laid flat while a slot is waiting for it is a T wasted.
			if _ctx_slot_started and piece.piece_type == Tetromino.PieceType.T:
				candidate -= _t_waste_penalty
			if not found or candidate > best_score:
				found = true
				best_score = candidate
				best_rotation = rotation
				best_x = x
			if _is_lethal_landing(cells, x, y, simulation["after"], next_type):
				continue
			if collect:
				cand_scores.append(candidate)
				cand_rotations.append(rotation)
				cand_xs.append(x)
				cand_afters.append(simulation["after"])
				cand_boards.append(candidate_board)
				cand_is_spin.append(false)
				cand_spin.append({})
			if not found_safe or candidate > safe_best_score:
				found_safe = true
				safe_best_score = candidate
				safe_best_rotation = rotation
				safe_best_x = x
				safe_best_is_spin = false
				safe_best_spin = {}
				safe_best_cleared = int(simulation["cleared"])
	# Final ranking. `pre` is the 1-ply ranking (ties keep the enumeration
	# order). Depth 1 plays its head. Depth >= 2 searches the top
	# `follow_candidates` of it deeper and plays the best path (see the
	# header); when the budget ran out before a candidate's follow search could
	# start, its own board value stands in. Mistakes are drawn from the 1-ply
	# ranking, so they stay perturbations of the obvious move.
	var pre: Array = []
	for index: int in cand_scores.size():
		pre.append({
			"score": cand_scores[index],
			"index": index,
		})
	pre.sort_custom(_pre_scores_beats)
	var chosen_rotation: int = safe_best_rotation
	var chosen_x: int = safe_best_x
	var chosen_is_spin: bool = safe_best_is_spin
	var chosen_spin: Dictionary = safe_best_spin
	if _lookahead_depth >= 2 and found_safe and cand_scores.size() >= 2:
		var queue: Array[int] = _battle.next_queue(_side)
		var best_total: int = 0
		var have_total: bool = false
		for rank: int in mini(_follow_candidates, pre.size()):
			var index: int = int(pre[rank]["index"])
			var reward: int = cand_scores[index] - cand_boards[index]
			var total: int = reward + await _beam_follow_value(cand_afters[index], queue, 0, _lookahead_depth - 1, cand_boards[index],
				_battle.hold_type(_side) == Tetromino.PieceType.T)
			total -= _follow_danger(cand_afters[index])
			if not have_total or total > best_total:
				have_total = true
				best_total = total
				chosen_rotation = cand_rotations[index]
				chosen_x = cand_xs[index]
				chosen_is_spin = cand_is_spin[index]
				chosen_spin = cand_spin[index]
	if found_safe:
		_plan_rotation = chosen_rotation
		_plan_x = chosen_x
		# Nobody plays loose with the stack near the top.
		if mistake_roll < _error_rate and not _ctx_danger and pre.size() >= 2:
			var pool: int = mini(_error_pool, pre.size()) - 1
			var slip: int = int(pre[1 + mini(int(mistake_pick * float(pool)), pool - 1)]["index"])
			if safe_best_score - cand_scores[slip] <= _error_max_drop:
				chosen_rotation = cand_rotations[slip]
				chosen_is_spin = cand_is_spin[slip]
				chosen_spin = cand_spin[slip]
				_plan_rotation = chosen_rotation
				_plan_x = cand_xs[slip]
				_mistakes_made += 1
	elif found:
		# Every landing is lethal: the board is already pressed into a lost
		# position, so keep the plain best (BD-02: death comes from pressure).
		_plan_rotation = best_rotation
		_plan_x = best_x
	# Handoff: a chosen spin entry is executed as its drop (column and
	# rotation of the entry's start) followed by its grounded moves; tick()
	# finishes with the zero-travel hard drop (see the spin phases there).
	_spin_plan = chosen_is_spin and not chosen_spin.is_empty()
	if _spin_plan:
		_plan_rotation = int(chosen_spin["pre_rotation"])
		_plan_x = int(chosen_spin["pre_x"])
		_ground_moves = (chosen_spin["moves"] as Array).duplicate()
		_spins_planned += 1
	# The profiled hold policy answers BEFORE the fallback plan above is ever
	# executed: it either taps hold (the plan waits for the swap) or leaves
	# the fallback in place (hold unavailable / easy). The margin comparison
	# stays 1-ply (safe_best_score), deliberately unaffected by the lookahead
	# re-ranking above (S3a calibration, BD-07).
	if _frame_spent():
		await _next_frame()
	if _battle.current_piece(_side) != piece:
		# Spread over frames, and the piece is gone: nothing left to decide.
		return
	_evaluate_hold(grid, piece, found_safe, safe_best_score, safe_best_cleared,
		_spin_plan and int(chosen_spin.get("cleared", 0)) >= 2)
	if _ctx_slot_started:
		_slot_plans += 1


## Seeded score jitter of one candidate (see the profile's style_noise).
func _style_jitter() -> int:
	if _style_noise <= 0:
		return 0
	return _style_rng.randi_range(-_style_noise, _style_noise)


## Height danger of a candidate's after-board: rows of maximum stack height
## beyond the profile's danger_soft_rows, times FOLLOW_DANGER_STEP. Zero on
## healthy boards, so only near-top play is re-weighted (deterministic, no
## simulations).
func _follow_danger(after: Array) -> int:
	return maxi(0, _max_height(after) - _danger_soft_rows) * FOLLOW_DANGER_STEP


## Tallest column of a grid, in rows above the floor.
static func _max_height(grid: Array) -> int:
	for row: int in Board.BOARD_HEIGHT:
		for col: int in Board.BOARD_WIDTH:
			if int(grid[row * Board.BOARD_WIDTH + col]) != Board.EMPTY:
				return Board.BOARD_HEIGHT - row
	return 0


## Cheap deterministic T-Spin classification for a planned landing (S3c).
## Same corner rule as Scoring.classify_t_spin: the four corners of the T's
## 3x3 matrix (center = pos + (1,1)) are split into front/back pairs by
## rotation; >=3 filled corners make the spin and front==2 with back<2 is a
## MINI - unless the lock came through the fifth SRS kick (kick_index 4),
## the exception Scoring applies as well. Out-of-board corners count as
## filled (identical wall rule to Scoring's _count_filled). The rule's
## other premise - "the last move was a rotation" - is guaranteed by the
## executor for spin entries (the lock is the at-rest rotation followed by a
## zero-travel hard drop, see tick()), so the battle's own classification at
## the lock agrees with this planning verdict.
static func _tspin_landing_kind(grid: Array, piece_type: int, rotation: int, x: int, y: int, kick_index: int) -> int:
	if piece_type != Tetromino.PieceType.T:
		return Scoring.TSpinKind.NONE
	var center: Vector2i = Vector2i(x, y) + Vector2i(1, 1)
	var front: Array[Vector2i] = []
	var back: Array[Vector2i] = []
	match rotation % 4:
		0:
			front = [center + Vector2i(-1, -1), center + Vector2i(1, -1)]
			back = [center + Vector2i(-1, 1), center + Vector2i(1, 1)]
		1:
			front = [center + Vector2i(1, -1), center + Vector2i(1, 1)]
			back = [center + Vector2i(-1, -1), center + Vector2i(-1, 1)]
		2:
			front = [center + Vector2i(-1, 1), center + Vector2i(1, 1)]
			back = [center + Vector2i(-1, -1), center + Vector2i(1, -1)]
		_:
			front = [center + Vector2i(-1, -1), center + Vector2i(-1, 1)]
			back = [center + Vector2i(1, -1), center + Vector2i(1, 1)]
	var front_filled: int = _count_filled_corners(grid, front)
	var back_filled: int = _count_filled_corners(grid, back)
	if front_filled + back_filled < 3:
		return Scoring.TSpinKind.NONE
	if front_filled == 2 or kick_index == 4:
		return Scoring.TSpinKind.FULL
	return Scoring.TSpinKind.MINI


## Occupied-corner count on a grid array; out-of-board corners count as
## occupied (same wall rule as Scoring._count_filled).
static func _count_filled_corners(grid: Array, corners: Array[Vector2i]) -> int:
	var count: int = 0
	for corner: Vector2i in corners:
		if corner.x < 0 or corner.x >= Board.BOARD_WIDTH \
				or corner.y < 0 or corner.y >= Board.BOARD_HEIGHT \
				or int(grid[corner.y * Board.BOARD_WIDTH + corner.x]) != Board.EMPTY:
			count += 1
	return count


## Spin entries the T can actually reach on `grid`. The T first drops
## straight down in any rotation and column (a "start"), then makes up to
## SPIN_GROUND_DEPTH grounded moves: a slide left/right or a rotation either
## way through the SRS kick list, where the FIRST fitting kick is the one the
## battle executes. After every move the piece settles (the executor keeps the
## soft drop held). An entry is a final that rests right where a rotation put
## it - a fall after the rotation would clear the battle's "last move was a
## rotation" flag - and passes the 3-corner rule. One entry per final
## placement (the shortest way in). Each entry: the final "rotation" / "x" /
## "y" / "kick_index", the start "pre_rotation" / "pre_x", and "moves", the
## grounded actions to play.
func _reachable_t_spins(grid: Array) -> Array:
	var shapes: Array = _t_shapes()
	var seen: Dictionary = {}
	var frontier: Array = []
	for rotation: int in 4:
		for x: int in range(-1, Board.BOARD_WIDTH):
			var y: int = _drop_y(grid, shapes[rotation], x)
			if y < 0:
				continue
			seen[_state_key(x, y, rotation)] = true
			frontier.append({"x": x, "y": y, "rotation": rotation, "pre_x": x, "pre_rotation": rotation, "moves": []})
	var finals: Dictionary = {}
	for depth: int in SPIN_GROUND_DEPTH:
		var next_frontier: Array = []
		for state: Dictionary in frontier:
			var x: int = int(state["x"])
			var y: int = int(state["y"])
			var rotation: int = int(state["rotation"])
			for direction: int in [1, -1]:
				var action: StringName = VersusBattle.ACTION_ROTATE if direction == 1 else VersusBattle.ACTION_ROTATE_CCW
				var to_rotation: int = (rotation + direction + 4) % 4
				var kicks: Array[Vector2i] = SRS.get_grid_kicks(Tetromino.PieceType.T, rotation, direction)
				for kick_index: int in kicks.size():
					var final_x: int = x + kicks[kick_index].x
					var final_y: int = y + kicks[kick_index].y
					if not _can_place(grid, shapes[to_rotation], final_x, final_y):
						continue
					var moves: Array = (state["moves"] as Array) + [action]
					if not _can_place(grid, shapes[to_rotation], final_x, final_y + 1):
						var final_key: int = _state_key(final_x, final_y, to_rotation)
						if not finals.has(final_key) and _tspin_landing_kind(grid, Tetromino.PieceType.T, to_rotation, final_x, final_y, kick_index) != Scoring.TSpinKind.NONE:
							finals[final_key] = {
								"rotation": to_rotation, "x": final_x, "y": final_y, "kick_index": kick_index,
								"pre_x": state["pre_x"], "pre_rotation": state["pre_rotation"], "moves": moves,
							}
					_push_ground_state(grid, shapes, seen, next_frontier, state, final_x, final_y, to_rotation, moves)
					break
			for step: int in [-1, 1]:
				if _can_place(grid, shapes[rotation], x + step, y):
					var slide: StringName = VersusBattle.ACTION_MOVE_LEFT if step < 0 else VersusBattle.ACTION_MOVE_RIGHT
					_push_ground_state(grid, shapes, seen, next_frontier, state, x + step, y, rotation, (state["moves"] as Array) + [slide])
		frontier = next_frontier
	return finals.values()


## Lets the piece settle from (x, y) and queues the resting state once.
func _push_ground_state(grid: Array, shapes: Array, seen: Dictionary, frontier: Array, from: Dictionary, x: int, y: int, rotation: int, moves: Array) -> void:
	var rest_y: int = y
	while _can_place(grid, shapes[rotation], x, rest_y + 1):
		rest_y += 1
	var key: int = _state_key(x, rest_y, rotation)
	if seen.has(key):
		return
	seen[key] = true
	frontier.append({"x": x, "y": rest_y, "rotation": rotation, "pre_x": from["pre_x"], "pre_rotation": from["pre_rotation"], "moves": moves})


static func _state_key(x: int, y: int, rotation: int) -> int:
	return (x + 4) + 32 * (y + 4) + 2048 * rotation


static var _t_shape_cache: Array = []

## The T's cells in its four rotations.
static func _t_shapes() -> Array:
	if _t_shape_cache.is_empty():
		for rotation: int in 4:
			var probe: Tetromino = Tetromino.new(Tetromino.PieceType.T)
			probe.rotation = rotation
			_t_shape_cache.append(probe.get_cells())
	return _t_shape_cache


## Column heights of a grid (rows above the floor of each column's top block).
static func _column_heights(grid: Array) -> Array[int]:
	var heights: Array[int] = []
	for col: int in Board.BOARD_WIDTH:
		var height: int = 0
		for row: int in Board.BOARD_HEIGHT:
			if int(grid[row * Board.BOARD_WIDTH + col]) != Board.EMPTY:
				height = Board.BOARD_HEIGHT - row
				break
		heights.append(height)
	return heights


static func _filled(grid: Array, col: int, row: int) -> bool:
	if col < 0 or col >= Board.BOARD_WIDTH or row >= Board.BOARD_HEIGHT:
		return true
	return row >= 0 and int(grid[row * Board.BOARD_WIDTH + col]) != Board.EMPTY


## Filled cells of `row`, not counting the columns in `skip`.
static func _row_fill(grid: Array, row: int, skip: Array[int]) -> int:
	var count: int = 0
	for col: int in Board.BOARD_WIDTH:
		if not skip.has(col) and int(grid[row * Board.BOARD_WIDTH + col]) != Board.EMPTY:
			count += 1
	return count


## Value of the T-slots under construction on a board (added to the board
## value, so every search depth sees it).
##
## T-Spin Double slot at column c, bottom row r (c is open to the sky):
##     # . .      row r-2: one side filled = the overhang; the other side
##     . . .      row r-1: three empty cells           stays open to the sky
##     # . #      row r:   the hole between two blocks
## T-Spin Triple slot (tiers with tslot_triples), nub on side s (drawn s = +1):
##     # . .      row r-4: the roof, right over the shaft
##   # . . .      row r-3: the turning room; the T slides in from the s side
##   # . # #      row r-2 \
##   # . . #      row r-1  > a 3-deep shaft with a 1-cell nub pocket
##   # . # #      row r   /
## The T lies flat in the turning room and the rotation's fifth kick drops it
## down the shaft.
## Stages: the notch alone is worth `tslot_notch`; with the overhang / roof in
## place and the entry open it is worth `tslot_ready` (twice that for a
## Triple); either way each filled cell of the rows the spin will clear adds
## `tslot_fill`. The holes a finished overhang leaves under it are refunded
## (they are the setup, not damage). The best `tslot_cap` slots count, at
## TSLOT_FAR_FACTOR when no T is near.
func _tslot_value(grid: Array, heights: Array[int]) -> int:
	var values: Array[int] = []
	_armed_col = -1
	_armed_row = -1
	for col: int in range(1, Board.BOARD_WIDTH - 1):
		# An open column's slot starts at the first empty cell over its stack.
		var open_row: int = Board.BOARD_HEIGHT - heights[col] - 1
		var value: int = 0
		if open_row >= 4:
			value = _tsd_slot_value(grid, heights, col, open_row)
			if _tslot_triples:
				value = maxi(value, maxi(_tst_slot_value(grid, heights, col, open_row, 1, false), _tst_slot_value(grid, heights, col, open_row, -1, false)))
		# A roofed Triple shaft: four empty cells right under the column's top block.
		if _tslot_triples and heights[col] >= 5:
			var roof_row: int = Board.BOARD_HEIGHT - heights[col]
			var shaft_bottom: int = roof_row + 4
			var shaft: bool = _filled(grid, col, shaft_bottom + 1)
			for depth: int in range(1, 5):
				shaft = shaft and not _filled(grid, col, roof_row + depth)
			if shaft:
				value = maxi(value, maxi(_tst_slot_value(grid, heights, col, shaft_bottom, 1, true), _tst_slot_value(grid, heights, col, shaft_bottom, -1, true)))
		if value > 0:
			values.append(value)
	if values.is_empty():
		return 0
	values.sort()
	var total: int = 0
	for i: int in mini(_tslot_cap, values.size()):
		total += values[values.size() - 1 - i]
	return total if _ctx_t_near else int(float(total) * TSLOT_FAR_FACTOR)


## The board after a T fires the armed Double slot of `grid` ("after", and
## the "y" of the T's matrix); empty when no slot is armed.
func _slot_fire(grid: Array) -> Dictionary:
	_tslot_value(grid, _column_heights(grid))
	if _armed_col < 0:
		return {}
	var shapes: Array = _t_shapes()
	var down: int = 0
	for rotation: int in 4:
		if (shapes[rotation] as Array).has(Vector2i(1, 2)) and not (shapes[rotation] as Array).has(Vector2i(1, 0)):
			down = rotation
	var x: int = _armed_col - 1
	var y: int = _armed_row - 2
	if not _can_place(grid, shapes[down], x, y):
		return {}
	var simulation: Dictionary = _simulate_placement(grid, shapes[down], x, y)
	if int(simulation["cleared"]) != 2:
		return {}
	return {"after": simulation["after"], "y": y}


func _tsd_slot_value(grid: Array, heights: Array[int], col: int, row: int) -> int:
	if not _filled(grid, col - 1, row) or not _filled(grid, col + 1, row):
		return 0
	if _filled(grid, col - 1, row - 1) or _filled(grid, col + 1, row - 1):
		return 0
	var left_roof: bool = _filled(grid, col - 1, row - 2)
	var right_roof: bool = _filled(grid, col + 1, row - 2)
	if left_roof and right_roof:
		return 0
	var fill: int = _row_fill(grid, row, [col]) + _row_fill(grid, row - 1, [col - 1, col, col + 1])
	if not left_roof and not right_roof:
		var platform: bool = false
		for side: int in [-2, 2]:
			var far: int = col + side
			platform = platform or (far >= 0 and far < Board.BOARD_WIDTH and heights[far] >= Board.BOARD_HEIGHT - (row - 2))
		return _tslot_notch * (2 if platform else 1) + _tslot_fill * fill / 2
	# Spinnable only while the T can still come down on the open side.
	var open_col: int = col + 1 if left_roof else col - 1
	if heights[open_col] != Board.BOARD_HEIGHT - row:
		return _tslot_notch / 2
	var roof_col: int = col - 1 if left_roof else col + 1
	var roof_cover: int = heights[roof_col] - (Board.BOARD_HEIGHT - row + 1)
	_slot_is_ready = true
	_slot_fill_seen = maxi(_slot_fill_seen, fill)
	var armed: int = _tslot_armed if fill == TSD_FILL_CELLS else 0
	if armed > 0:
		_armed_col = col
		_armed_row = row
	return _tslot_ready + armed + _tslot_fill * fill + _hole_weight + _cover_weight * maxi(1, roof_cover)


## See _tslot_value. `row` is the shaft's bottom row, `nub` the side (+1 / -1)
## of the nub pocket, `roofed` whether the roof over the shaft is in place.
func _tst_slot_value(grid: Array, heights: Array[int], col: int, row: int, nub: int, roofed: bool) -> int:
	var wall: int = col - nub
	var nub_col: int = col + nub
	var far_col: int = col + 2 * nub
	if far_col < 0 or far_col >= Board.BOARD_WIDTH or row < 5:
		return 0
	# The wall runs from the shaft's bottom up past the turning room.
	for depth: int in 4:
		if not _filled(grid, wall, row - depth):
			return 0
	# Nub pocket between two blocks; the turning room over it is open and its
	# two outer columns reach the sky (that is where the T comes down).
	if not _filled(grid, nub_col, row) or not _filled(grid, nub_col, row - 2) or _filled(grid, nub_col, row - 1):
		return 0
	if _filled(grid, col, row - 3) or heights[nub_col] != Board.BOARD_HEIGHT - (row - 2) or heights[far_col] > Board.BOARD_HEIGHT - (row - 2):
		return 0
	var fill: int = _row_fill(grid, row, [col]) + _row_fill(grid, row - 1, [col, nub_col]) + _row_fill(grid, row - 2, [col])
	if not roofed:
		return _tslot_notch + _tslot_fill * fill / 2 + _hole_weight + _cover_weight
	_slot_is_ready = true
	# Refund: the four shaft cells and the nub pocket all sit under blocks.
	var armed: int = _tslot_armed * 2 if fill == TST_FILL_CELLS else 0
	return _tslot_ready * 2 + armed + _tslot_fill * fill + 5 * (_hole_weight + _cover_weight)


## A T is at hand: the piece being planned, the hold slot, or one of the next
## `tslot_t_horizon` pieces.
func _t_at_hand(piece_type: int) -> bool:
	if piece_type == Tetromino.PieceType.T or _battle.hold_type(_side) == Tetromino.PieceType.T:
		return true
	var queue: Array[int] = _battle.next_queue(_side)
	for i: int in mini(_tslot_t_horizon, queue.size()):
		if queue[i] == Tetromino.PieceType.T:
			return true
	return false


## Best score a T-Spin entry reaches on `grid` (the hold comparison uses it:
## the plain landing enumeration never sees a spin). FOLLOW_DEAD_END when
## there is none.
func _best_spin_score(grid: Array) -> int:
	var best: int = FOLLOW_DEAD_END
	var shapes: Array = _t_shapes()
	for entry: Dictionary in _reachable_t_spins(grid):
		if _plan_sims >= _plan_sim_budget:
			break
		_plan_sims += 1
		var rotation: int = int(entry["rotation"])
		var simulation: Dictionary = _simulate_placement(grid, shapes[rotation], int(entry["x"]), int(entry["y"]))
		var kind: int = _tspin_landing_kind(grid, Tetromino.PieceType.T, rotation, int(entry["x"]), int(entry["y"]), int(entry["kick_index"]))
		var score: int = _score_placement(simulation["after"], int(simulation["cleared"]), int(entry["y"]), kind)
		# With a slot under construction only the spin it is built for counts.
		if _ctx_slot_started and int(simulation["cleared"]) < 2:
			continue
		score += _tspin_candidate_bonus(int(simulation["cleared"]), kind)
		best = maxi(best, score)
	return best


## Spins planned so far (calibration read).
func spins_planned() -> int:
	return _spins_planned


## Pieces planned while a T-slot was under construction (calibration read).
func slot_plans() -> int:
	return _slot_plans


## Calibration read: [plans on a board with a spinnable slot, the summed row
## fill of those slots (16 = both rows full), how many of those plans had a T].
func ready_slot_stats() -> Array[int]:
	return [_ready_plans, _ready_fill_sum, _ready_t_plans]


## Extra pull toward T-Spin candidates on top of their attack value (which
## _score_placement already pays through attack_weight): clearing spins get
## `tspin_bonus` per sent row, zero-clear spins a token sixth of it - enough
## to prefer a snug spin nook over a bad flat placement, never enough to
## hoard nooks. Constructive (lunatic) only: an active B2B chain multiplies
## the bonus (TSPIN_B2B_MULT).
func _tspin_candidate_bonus(cleared: int, spin_kind: int) -> int:
	var rows: int = VersusBattle.attack_for_event(cleared, spin_kind, false, 0, false)
	var bonus: int = _tspin_bonus * rows
	if _tspin_policy == &"advanced" and _battle.b2b_active(_side):
		bonus = int(float(bonus) * TSPIN_B2B_MULT)
	return bonus


## Deterministic 1-ply pre-rank order: higher score first, ties by the
## original enumeration index.
static func _pre_scores_beats(a: Dictionary, b: Dictionary) -> bool:
	var score_a: int = int(a["score"])
	var score_b: int = int(b["score"])
	if score_a != score_b:
		return score_a > score_b
	return int(a["index"]) < int(b["index"])


## Deterministic follow-row order: higher score first, ties by enumeration.
static func _row_scores_beats(a: Dictionary, b: Dictionary) -> bool:
	var score_a: int = int(a["score"])
	var score_b: int = int(b["score"])
	if score_a != score_b:
		return score_a > score_b
	return int(a["order"]) < int(b["order"])


## The queued piece type at `index`, or -1 past the queue's end.
static func _queue_type(queue: Array[int], index: int) -> int:
	return queue[index] if index < queue.size() else -1


## Canonical key for an absolute landing placement (sorted absolute cells):
## equivalent rotations of a piece collapse into one key.
static func _placement_key(cells: Array[Vector2i], x: int, y: int) -> int:
	# Ten bits per cell (column and row, both offset to stay positive), the
	# four cells in sorted order.
	var parts: Array[int] = []
	for cell: Vector2i in cells:
		parts.append((x + cell.x + 8) * 64 + (y + cell.y + 8))
	parts.sort()
	var key: int = 0
	for part: int in parts:
		key = key * 1024 + part
	return key


## Best path value from `board` through the queued pieces starting at
## `queue[queue_index]`, `levels` pieces deep: the rewards collected along the
## path plus the value of its final board. Each level expands only its top
## FOLLOW_BEAM placements. `fallback` (the value of `board` itself) is
## returned when there is nothing to search: no levels left, the queue ended,
## or the shared budget was spent before a single simulation. A piece with no
## non-lethal landing is a FOLLOW_DEAD_END.
func _beam_follow_value(board: Array, queue: Array[int], queue_index: int, levels: int, fallback: int, held_t: bool = false) -> int:
	if levels <= 0:
		return fallback
	var piece_type: int = _queue_type(queue, queue_index)
	if piece_type < 0 or piece_type >= Tetromino.SHAPES.size():
		return fallback
	var follower_index: int = queue_index + 1
	var usable: int = _plan_sim_budget - HOLD_EVAL_RESERVE
	var sims_at_entry: int = _plan_sims
	var rows: Array = []
	var seen_placements: Dictionary = {}
	_ctx_follow = true
	# The Double: the queued T, or the held one swapped in for this piece
	# (which then waits in the hold slot), fires an armed slot. Without this
	# the search would see no reason to arm a slot now rather than later.
	var is_t: bool = piece_type == Tetromino.PieceType.T
	if _tslot_ready > 0 and not _ctx_danger and (is_t or held_t) and _plan_sims < usable:
		var fired: Dictionary = _slot_fire(board)
		if not fired.is_empty():
			_plan_sims += 1
			var fire_score: int = _score_placement(fired["after"], 2, int(fired["y"]), Scoring.TSpinKind.FULL)
			var fire_board: int = _last_board_value
			rows.append({
				# Half the bonus: a Double later is never worth more than the
				# same Double now.
				"score": fire_score + _tspin_candidate_bonus(2, Scoring.TSpinKind.FULL) / 2,
				"board": fire_board,
				"after": fired["after"],
				"order": 0,
				"held_t": held_t and is_t,
			})
	var tops: PackedInt32Array = _column_tops(board)
	var scan_from: int = Board.BOARD_HEIGHT
	for top: int in tops:
		scan_from = mini(scan_from, top)
	for cells: Array[Vector2i] in _unique_rotations(piece_type):
		if _plan_sims >= usable:
			break
		for x: int in range(-3, Board.BOARD_WIDTH):
			if _plan_sims >= usable:
				break
			if _frame_spent():
				await _next_frame()
				_ctx_follow = true
			var y: int = _drop_y_fast(board, cells, x, tops)
			if y < 0:
				continue
			var placement_key: int = _placement_key(cells, x, y)
			if seen_placements.has(placement_key):
				continue
			seen_placements[placement_key] = true
			_plan_sims += 1
			var simulation: Dictionary = _simulate_placement(board, cells, x, y)
			var candidate: int = _score_placement(simulation["after"], int(simulation["cleared"]), y, Scoring.TSpinKind.NONE, mini(scan_from, y))
			if is_t and _ctx_slot_started:
				candidate -= _t_waste_penalty
			if _is_lethal_landing(cells, x, y, simulation["after"], _queue_type(queue, follower_index)):
				continue
			rows.append({
				"score": candidate,
				"board": _last_board_value,
				"after": simulation["after"],
				"order": rows.size(),
				"held_t": held_t,
			})
	_ctx_follow = false
	if rows.is_empty():
		return FOLLOW_DEAD_END if _plan_sims > sims_at_entry else fallback
	rows.sort_custom(_row_scores_beats)
	if levels == 1:
		return int(rows[0]["score"])
	var best: int = FOLLOW_DEAD_END
	for index: int in mini(FOLLOW_BEAM, rows.size()):
		var row: Dictionary = rows[index]
		var reward: int = int(row["score"]) - int(row["board"])
		best = maxi(best, reward + await _beam_follow_value(row["after"], queue, follower_index, levels - 1, int(row["board"]), bool(row["held_t"])))
	return best


## Distinct landing cell sets over the four rotations of `piece_type`
## (only bit-identical absolute cell sets collapse - O's four rotations, and
## any rotation pair that mirrors into the same matrix window; most pieces
## keep 2-4 distinct entries. Hypothetical pieces only: the resting absolute
## cells are identical, so every simulated board is unchanged). Cached per
## type: the shapes are frozen constants.
static var _unique_rotation_cache: Dictionary = {}

static func _unique_rotations(piece_type: int) -> Array:
	if _unique_rotation_cache.has(piece_type):
		return _unique_rotation_cache[piece_type]
	var out: Array = []
	for rotation: int in 4:
		var probe: Tetromino = Tetromino.new(piece_type)
		probe.rotation = rotation
		var cells: Array[Vector2i] = probe.get_cells()
		var min_v: Vector2i = cells[0]
		for cell: Vector2i in cells:
			min_v = Vector2i(mini(min_v.x, cell.x), mini(min_v.y, cell.y))
		var normalized: Array = []
		for cell: Vector2i in cells:
			normalized.append(cell - min_v)
		normalized.sort()
		if not out.any(func(existing: Array[Vector2i]) -> bool: return _same_cells(existing, normalized)):
			out.append(cells)
	_unique_rotation_cache[piece_type] = out
	return out


static func _same_cells(a: Array[Vector2i], b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] != b[i]:
			return false
	return true


## Profiled hold decision (S3a, BD-07/O-02). easy (&"none") never holds.
## normal (&"bottom_out") holds only when the current piece has no non-lethal
## landing. hard/lunatic (&"regular") also hold when the hold slot piece (or,
## with an empty slot, the queued next piece) beats the current piece's best
## non-lethal score on the SAME board by more than `hold_gain_margin`.
## Guards: one hold per drop (`_held_this_drop`), no re-evaluation while a
## swap is already in flight, and the swap-in type must differ from the
## current piece (a same-type swap is a no-op). The decision is fully
## deterministic: no RNG draw, no wall clock.
func _evaluate_hold(grid: Array, piece: Tetromino, found_safe: bool, safe_best_score: int, safe_best_cleared: int = 0, spin_planned: bool = false) -> void:
	if _hold_policy == &"none" or _held_this_drop or _awaiting_hold_swap:
		return
	var bottom_out: bool = not found_safe
	var regular_gain: bool = false
	if not bottom_out and _hold_policy == &"regular":
		regular_gain = _stash_i_piece(piece.piece_type, safe_best_cleared) or _stash_t_piece(piece.piece_type, spin_planned)
		if not regular_gain and _plan_sims < _plan_sim_budget:
			regular_gain = _hold_swap_beats_current(grid, piece.piece_type, safe_best_score)
	if not bottom_out and not regular_gain:
		return
	_log_action(VersusBattle.ACTION_HOLD)
	_battle.tap(_side, VersusBattle.ACTION_HOLD)
	_held_this_drop = true
	_hold_swap_pending = true
	_awaiting_hold_swap = true
	_hold_wait_steps = 0
	_holds_made += 1
	if bottom_out:
		_bottom_out_holds += 1


## Well keepers save the I piece: an I that cannot score a Tetris right now
## goes into the hold slot (unless one is already there, the swap would only
## bring another I, or the stack is in danger and needs every clear).
func _stash_i_piece(piece_type: int, safe_best_cleared: int) -> bool:
	if _well_weight <= 0 or _ctx_danger or _ctx_slot_started or piece_type != Tetromino.PieceType.I or safe_best_cleared >= 4:
		return false
	var stored: int = _battle.hold_type(_side)
	if stored == Tetromino.PieceType.I:
		return false
	if stored < 0:
		var queue: Array[int] = _battle.next_queue(_side)
		return not queue.is_empty() and queue[0] != Tetromino.PieceType.I
	return true


## Slot builders save the T piece: a T that has no spin to make right now goes
## into the hold slot while a slot is under construction (unless a T is
## already there, or the swap would only bring another T).
func _stash_t_piece(piece_type: int, spin_planned: bool) -> bool:
	if _tslot_ready <= 0 or _ctx_danger or spin_planned or not _ctx_slot_started or piece_type != Tetromino.PieceType.T:
		return false
	var stored: int = _battle.hold_type(_side)
	if stored == Tetromino.PieceType.T:
		return false
	if stored < 0:
		var queue: Array[int] = _battle.next_queue(_side)
		return not queue.is_empty() and queue[0] != Tetromino.PieceType.T
	return true


## Regular-trigger score comparison: best non-lethal score of the piece the
## hold swap would bring in versus the current piece's best non-lethal score,
## both on the current board. `next_type` (the queue head for the CURRENT
## piece) is intentionally not used here: the lethal filter of the swap
## candidate needs the piece that will follow the swap, which is queue[0]
## when the slot is filled and queue[1] when the swap consumes queue[0].
func _hold_swap_beats_current(grid: Array, piece_type: int, safe_best_score: int) -> bool:
	var queue: Array[int] = _battle.next_queue(_side)
	var stored: int = _battle.hold_type(_side)
	var swap_type: int = stored
	var after_swap_next: int = queue[0] if not queue.is_empty() else -1
	if stored < 0:
		# Empty slot: holding stores the current piece and spawns queue[0],
		# so the evaluated piece is queue[0] and its follower is queue[1].
		if queue.is_empty():
			return false
		swap_type = queue[0]
		after_swap_next = queue[1] if queue.size() > 1 else -1
	if swap_type < 0 or swap_type == piece_type:
		return false
	var swap_best: Dictionary = _best_non_lethal(grid, swap_type, after_swap_next)
	var swap_score: int = int(swap_best["score"]) if bool(swap_best["found"]) else FOLLOW_DEAD_END
	# A held T is worth what it can spin for, not what it scores laid flat.
	if swap_type == Tetromino.PieceType.T and _tspin_policy != &"none":
		var spin_score: int = _best_spin_score(grid)
		# The T kept for a slot comes out to spin, not to be laid flat.
		swap_score = spin_score if _ctx_slot_started else maxi(swap_score, spin_score)
	return swap_score > FOLLOW_DEAD_END and swap_score > safe_best_score + _hold_gain_margin


## Best non-lethal score for one piece type on `grid` (hold-swap evaluation,
## S3a). Same candidate enumeration/scoring/lethal filter as the main plan,
## sharing the per-plan sim counter and budget: stops expanding candidates
## once the budget is exhausted (BC-02 hard cap).
func _best_non_lethal(grid: Array, piece_type: int, next_type: int) -> Dictionary:
	var best_score: int = 0
	var found: bool = false
	var tops: PackedInt32Array = _column_tops(grid)
	var scan_from: int = Board.BOARD_HEIGHT
	for top: int in tops:
		scan_from = mini(scan_from, top)
	for rotation: int in 4:
		if _plan_sims >= _plan_sim_budget:
			break
		var probe: Tetromino = Tetromino.new(piece_type)
		probe.rotation = rotation
		var cells: Array[Vector2i] = probe.get_cells()
		for x: int in range(-3, Board.BOARD_WIDTH):
			if _plan_sims >= _plan_sim_budget:
				break
			var y: int = _drop_y_fast(grid, cells, x, tops)
			if y < 0:
				continue
			_plan_sims += 1
			var simulation: Dictionary = _simulate_placement(grid, cells, x, y)
			var candidate: int = _score_placement(simulation["after"], int(simulation["cleared"]), y, Scoring.TSpinKind.NONE, mini(scan_from, y))
			if _is_lethal_landing(cells, x, y, simulation["after"], next_type):
				continue
			if not found or candidate > best_score:
				found = true
				best_score = candidate
	return {"found": found, "score": best_score}


## The queued piece that will spawn after the current lock; -1 when the
## queue is unexpectedly empty (the blocked-spawn check then skips).
func _next_piece_type() -> int:
	var queue: Array[int] = _battle.next_queue(_side)
	return queue[0] if not queue.is_empty() else -1


## Lethal landing (observable definition, mirrored by tests/test_ai_difficulty.gd):
## a) lock-out - every placed cell ends up in the hidden area (wy <
##    HIDDEN_HEIGHT), the same all-hidden condition VersusBattle treats as an
##    immediate loss;
## b) blocked next spawn - on the post-clear board the queued next piece
##    cannot be placed at its spawn position in its spawning rotation 0.
##    VersusBattle spawns exactly there and loses immediately when the spot is
##    occupied, so this single check is the simplest exact proxy for "the
##    placement leaves the next piece no landing spot at all" (an I-piece
##    refresh point being occupied is the canonical case).
func _is_lethal_landing(cells: Array[Vector2i], x: int, y: int, after: Array, next_type: int) -> bool:
	var all_hidden: bool = true
	for cell: Vector2i in cells:
		if y + cell.y >= Board.HIDDEN_HEIGHT:
			all_hidden = false
			break
	if all_hidden:
		return true
	if next_type < 0 or next_type >= Tetromino.SHAPES.size():
		return false
	return not _can_place(after, _spawn_cells(next_type), _spawn_x(next_type), Board.HIDDEN_HEIGHT - 2)


static var _spawn_cell_cache: Dictionary = {}

## The cells of a freshly spawned piece (rotation 0), cached per type.
static func _spawn_cells(type: int) -> Array[Vector2i]:
	if not _spawn_cell_cache.has(type):
		_spawn_cell_cache[type] = Tetromino.new(type).get_cells()
	return _spawn_cell_cache[type]


## Spawn column, mirroring VersusBattle._spawn_specific's computation.
func _spawn_x(type: int) -> int:
	return (Board.BOARD_WIDTH - Tetromino.MATRIX_SIZES[type]) / 2


func _copy_board_grid(board: Board) -> Array:
	var grid: Array = []
	grid.resize(Board.BOARD_WIDTH * Board.BOARD_HEIGHT)
	for y: int in Board.BOARD_HEIGHT:
		for x: int in Board.BOARD_WIDTH:
			grid[y * Board.BOARD_WIDTH + x] = board.get_cell(Vector2i(x, y))
	return grid


func _can_place(grid: Array, cells: Array[Vector2i], x: int, y: int) -> bool:
	for cell: Vector2i in cells:
		var wx: int = x + cell.x
		var wy: int = y + cell.y
		if wx < 0 or wx >= Board.BOARD_WIDTH or wy < 0 or wy >= Board.BOARD_HEIGHT:
			return false
		if int(grid[wy * Board.BOARD_WIDTH + wx]) != Board.EMPTY:
			return false
	return true


## The top filled row of every column (BOARD_HEIGHT for an empty column).
static func _column_tops(grid: Array) -> PackedInt32Array:
	var tops: PackedInt32Array = PackedInt32Array()
	tops.resize(Board.BOARD_WIDTH)
	for col: int in Board.BOARD_WIDTH:
		var top: int = Board.BOARD_HEIGHT
		for row: int in Board.BOARD_HEIGHT:
			if int(grid[row * Board.BOARD_WIDTH + col]) != Board.EMPTY:
				top = row
				break
		tops[col] = top
	return tops


## _drop_y with the grid's column tops at hand: a piece that enters freely at
## the top comes to rest on the highest block under any of its cells, which
## the tops give without stepping down row by row. Anything else (the stack
## reaches the entry rows) takes the stepping path.
func _drop_y_fast(grid: Array, cells: Array[Vector2i], x: int, tops: PackedInt32Array) -> int:
	var y: int = Board.BOARD_HEIGHT
	for cell: Vector2i in cells:
		var wx: int = x + cell.x
		if wx < 0 or wx >= Board.BOARD_WIDTH:
			return -1
		if tops[wx] <= cell.y:
			return _drop_y(grid, cells, x)
		y = mini(y, tops[wx] - 1 - cell.y)
	return y


func _drop_y(grid: Array, cells: Array[Vector2i], x: int) -> int:
	# Simulate the real hard drop: enter the column from the TOP and descend
	# while the next step fits. Scanning bottom-up instead would treat the
	# cavities under overhangs as reachable landings, so every plan made on a
	# holey board simulated a resting spot the real drop can never reach - the
	# S1 world-model divergence behind its self-top-outs (BD-02).
	var y: int = -1
	for entry: int in range(0, Board.BOARD_HEIGHT):
		if _can_place(grid, cells, x, entry):
			y = entry
			break
	if y < 0:
		return -1
	while y + 1 < Board.BOARD_HEIGHT and _can_place(grid, cells, x, y + 1):
		y += 1
	return y


## Simulates one placement on the grid copy: returns the post-clear board
## ("after") and the number of cleared lines. Shared by scoring and the
## lethal-landing filter so neither duplicates the clear simulation.
func _simulate_placement(grid: Array, cells: Array[Vector2i], x: int, y: int) -> Dictionary:
	var placed: Array = grid.duplicate()
	for cell: Vector2i in cells:
		placed[(y + cell.y) * Board.BOARD_WIDTH + (x + cell.x)] = 1
	# Only the rows the piece touched can have filled up.
	var cleared: int = 0
	var touched: Array[int] = []
	for cell: Vector2i in cells:
		var row: int = y + cell.y
		if not touched.has(row):
			touched.append(row)
			if _row_full(placed, row):
				cleared += 1
	if cleared == 0:
		return {"after": placed, "cleared": 0}
	var after: Array = []
	after.resize(Board.BOARD_WIDTH * Board.BOARD_HEIGHT)
	after.fill(Board.EMPTY)
	var write_row: int = Board.BOARD_HEIGHT - 1
	for row: int in range(Board.BOARD_HEIGHT - 1, -1, -1):
		if _row_full(placed, row):
			continue
		for col: int in Board.BOARD_WIDTH:
			after[write_row * Board.BOARD_WIDTH + col] = placed[row * Board.BOARD_WIDTH + col]
		write_row -= 1
	return {"after": after, "cleared": cleared}


## Scores a post-clear board for the active tier (see the profile keys).
## `scan_from` is a row above which `after` is known to be empty (the caller
## has the column tops of the board the piece went onto); 0 scans everything.
func _score_placement(after: Array, cleared: int, y: int, spin_kind: int = Scoring.TSpinKind.NONE, scan_from: int = 0) -> int:
	var heights: Array[int] = []
	var holes: int = 0
	var cover: int = 0
	for col: int in Board.BOARD_WIDTH:
		var height: int = 0
		var filled_above: int = 0
		for row: int in range(maxi(0, scan_from), Board.BOARD_HEIGHT):
			if int(after[row * Board.BOARD_WIDTH + col]) != Board.EMPTY:
				if filled_above == 0:
					height = Board.BOARD_HEIGHT - row
				filled_above += 1
			elif filled_above > 0:
				holes += 1
				cover += filled_above
		heights.append(height)
	var aggregate: int = 0
	for height: int in heights:
		aggregate += height
	# T-slots under construction (see _tslot_value). While one is being built
	# the Tetris well is not reserved: the rows a spin clears must be filled
	# wall to wall, so the well column is stacked like any other.
	var slot_value: int = 0
	if _tslot_ready > 0 and not _ctx_danger and aggregate <= _danger_soft_rows * Board.BOARD_WIDTH:
		slot_value = _tslot_value(after, heights)
	# The reserved well stays out of the bumpiness sum: it is supposed to be
	# a cliff.
	var well: bool = _well_weight > 0 and not _ctx_danger and slot_value == 0
	var bumpiness: int = 0
	for col: int in range(Board.BOARD_WIDTH - (2 if well else 1)):
		bumpiness += absi(heights[col] - heights[col + 1])
	var shafts: int = 0
	for col: int in Board.BOARD_WIDTH:
		if well and col == WELL_COLUMN:
			continue
		var left: int = heights[col - 1] if col > 0 else Board.BOARD_HEIGHT
		var right: int = heights[col + 1] if col < Board.BOARD_WIDTH - 1 else Board.BOARD_HEIGHT
		shafts += maxi(0, mini(left, right) - heights[col] - DEEP_WELL_FREE_ROWS)
	var values: Array = _danger_clear_values if _ctx_danger else _clear_values
	var score: int = int(values[mini(cleared, 4)])
	if cleared > 0 and _attack_weight > 0:
		var perfect_clear: bool = aggregate == 0
		var combo_count: int = 1 if _ctx_follow else _ctx_combo + 1
		score += _attack_weight * VersusBattle.attack_for_event(cleared, spin_kind, _ctx_b2b, combo_count, perfect_clear)
	score += LOW_PLACEMENT_WEIGHT * y
	_last_board_value = - _hole_weight * holes \
		- _cover_weight * cover \
		- HEIGHT_WEIGHT * aggregate \
		- BUMPINESS_WEIGHT * bumpiness \
		- DEEP_WELL_WEIGHT * shafts
	_last_board_value += slot_value
	if _ctx_danger:
		var peak: int = 0
		for height: int in heights:
			peak = maxi(peak, height)
		_last_board_value -= DANGER_PEAK_WEIGHT * peak
	if well:
		_last_board_value -= _well_weight * heights[WELL_COLUMN]
	return score + _last_board_value


func _row_full(grid: Array, row: int) -> bool:
	for col: int in Board.BOARD_WIDTH:
		if int(grid[row * Board.BOARD_WIDTH + col]) == Board.EMPTY:
			return false
	return true




