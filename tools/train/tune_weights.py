"""Self-play tuning of the versus AI's evaluation weights.

The game itself is the simulator: every match is played by a headless Godot
process (tools/ai_arena.gd job=...), several of them side by side. An
evolution strategy (a Gaussian per weight, the best candidates of a generation
move its mean and width) looks for the profile numbers that beat the tier it
starts from - and the champion of ten generations ago, so that it does not
only learn one opponent.

    python tools/train/tune_weights.py                 # run, or carry on a run
    python tools/train/tune_weights.py --gens 100 --procs 14
    python tools/train/tune_weights.py --validate 200  # champion against the base tier
    python tools/train/tune_weights.py --show          # the champion's numbers

State, log and champion live in dist/train/weights/ (not in the repository).
The result is never written into scripts/versus_ai.gd by this tool.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT", r"E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")
OUT = ROOT / "dist" / "train" / "weights"

# The numbers of the base tier, as in VersusAI.DIFFICULTY_PROFILES and the
# shared constants. (key, kind, value, low, high): "log" weights move by
# factors, "lin" numbers by steps of (high - low).
BASES = {
    "lunatic": [
        ("hole_weight", "log", 80, 10, 600),
        ("cover_weight", "log", 15, 1, 200),
        ("height_weight", "log", 10, 1, 100),
        ("bumpiness_weight", "log", 20, 2, 200),
        ("deep_well_weight", "log", 20, 2, 200),
        ("low_placement_weight", "log", 6, 1, 60),
        ("danger_peak_weight", "log", 60, 5, 600),
        ("follow_danger_step", "log", 200, 20, 2000),
        ("well_weight", "log", 30, 3, 300),
        ("tetris_well_weight", "log", 60, 6, 600),
        ("attack_weight", "log", 350, 35, 3500),
        ("clear_values.1", "log", 20, 2, 2000),
        ("clear_values.2", "log", 100, 10, 3000),
        ("clear_values.3", "log", 300, 30, 4000),
        ("clear_values.4", "log", 1400, 140, 8000),
        ("danger_clear_values.1", "log", 800, 80, 8000),
        ("danger_clear_values.2", "log", 1600, 160, 12000),
        ("danger_clear_values.3", "log", 2400, 240, 16000),
        ("danger_clear_values.4", "log", 3600, 360, 20000),
        ("tspin_bonus", "log", 450, 45, 4500),
        ("tslot_notch", "log", 60, 6, 600),
        ("tslot_ready", "log", 220, 22, 2200),
        ("tslot_fill", "log", 40, 4, 400),
        ("tslot_armed", "log", 500, 50, 5000),
        ("t_waste_penalty", "log", 900, 90, 9000),
        ("tuck_cost", "log", 60, 6, 600),
        ("danger_rows", "lin", 12, 8, 16),
        ("attack_rows", "lin", 6, 3, 9),
        ("danger_soft_rows", "lin", 12, 8, 16),
        ("tspin_patience", "lin", 14, 6, 30),
        ("tetris_share", "lin", 0.4, 0.0, 1.0),
    ],
}
ARRAYS = {"clear_values": 5, "danger_clear_values": 5}
FLOATS = {"tetris_share"}


def to_x(spec):
    _key, kind, value, low, high = spec
    return math.log(value) if kind == "log" else (value - low) / (high - low)


def from_x(spec, x):
    _key, kind, _value, low, high = spec
    value = math.exp(x) if kind == "log" else low + x * (high - low)
    return min(high, max(low, value))


def profile_changes(specs, xs):
    """The `set` of an arena job: the profile keys a vector stands for."""
    out = {}
    arrays = {name: [0] * size for name, size in ARRAYS.items()}
    for spec, x in zip(specs, xs):
        key = spec[0]
        value = from_x(spec, x)
        value = round(value, 3) if key in FLOATS else int(round(value))
        if "." in key:
            name, index = key.split(".")
            arrays[name][int(index)] = value
        else:
            out[key] = value
    out.update(arrays)
    # Digging has to end with room left to build in.
    out["attack_rows"] = max(2, min(out["attack_rows"], out["danger_rows"] - 3))
    return out


def run_job(job, tag):
    """One Godot process; returns its list of [a won, a sent, b sent, seconds]."""
    path = OUT / "jobs" / f"{tag}.json"
    path.write_text(json.dumps(job), encoding="utf-8")
    done = subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--script", "res://tools/ai_arena.gd", "--", f"job={path}"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in done.stdout.splitlines():
        if line.startswith("RESULT "):
            return json.loads(line[7:])
    raise RuntimeError(f"job {tag} gave no result:\n{done.stdout[-2000:]}\n{done.stderr[-2000:]}")


def match_score(result):
    won, sent, taken, _seconds = result
    return won + 0.25 * math.tanh((sent - taken) / 15.0)


def evaluate(pool, tier, sides, opponents, seeds, cap, tag):
    """Mean match score and win rate of every side in `sides` (profile changes)
    against every opponent, on the same seeds."""
    jobs = []
    for index, changes in enumerate(sides):
        for which, opponent in enumerate(opponents):
            job = {"a": {"tier": tier, "set": changes}, "b": {"tier": tier, "set": opponent}, "seeds": seeds, "cap": cap}
            jobs.append((index, pool.submit(run_job, job, f"{tag}-{index}-{which}")))
    scores = [[] for _ in sides]
    wins = [[] for _ in sides]
    for index, future in jobs:
        for result in future.result():
            scores[index].append(match_score(result))
            wins[index].append(result[0])
    return [sum(s) / len(s) for s in scores], [sum(w) / len(w) for w in wins]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tier", default="lunatic")
    parser.add_argument("--gens", type=int, default=100, help="generations to run in this call")
    parser.add_argument("--pop", type=int, default=24)
    parser.add_argument("--elite", type=int, default=6)
    parser.add_argument("--games", type=int, default=12, help="matches per candidate and opponent")
    parser.add_argument("--procs", type=int, default=14)
    parser.add_argument("--cap", type=float, default=180.0, help="seconds of game time a match may take")
    parser.add_argument("--sigma", type=float, default=0.25)
    parser.add_argument("--validate", type=int, default=0, metavar="MATCHES")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args()

    specs = BASES[args.tier]
    (OUT / "jobs").mkdir(parents=True, exist_ok=True)
    state_path = OUT / f"{args.tier}.json"
    if state_path.exists():
        state = json.loads(state_path.read_text(encoding="utf-8"))
    else:
        state = {"generation": 0, "mean": [to_x(s) for s in specs], "sigma": [args.sigma] * len(specs), "history": [], "log": []}

    if args.show:
        print(json.dumps(profile_changes(specs, state["mean"]), indent=1))
        return
    pool = ThreadPoolExecutor(max_workers=args.procs)
    if args.validate:
        # Fresh seeds, never used in a generation (those start at 1000000).
        per_job = 4
        seeds = [5000 + i for i in range(args.validate)]
        changes = profile_changes(specs, state["mean"])
        futures = [pool.submit(run_job, {"a": {"tier": args.tier, "set": changes}, "b": {"tier": args.tier}, "seeds": seeds[i:i + per_job], "cap": 240},
                               f"validate-{i}") for i in range(0, len(seeds), per_job)]
        results = [r for f in futures for r in f.result()]
        wins = sum(r[0] for r in results)
        n = len(results)
        rate = wins / n
        error = 1.96 * math.sqrt(max(rate * (1 - rate), 1e-9) / n)
        print(f"generation {state['generation']} champion against {args.tier}: {wins:g} of {n} ({rate:.1%} +- {error:.1%}), "
              f"rows sent {sum(r[1] for r in results) / n:.1f} : {sum(r[2] for r in results) / n:.1f}")
        return

    rng = random.Random(20261012 + state["generation"])
    for _ in range(args.gens):
        generation = state["generation"]
        started = time.time()
        mean, sigma = state["mean"], state["sigma"]
        # Candidate 0 is the mean itself: its score is the run's progress.
        xs = [list(mean)] + [[m + s * rng.gauss(0, 1) for m, s in zip(mean, sigma)] for _ in range(args.pop - 1)]
        sides = [profile_changes(specs, x) for x in xs]
        opponents = [{}]
        if len(state["history"]) >= 10:
            opponents.append(profile_changes(specs, state["history"][-10]))
        seeds = [1000000 + generation * 1000 + i for i in range(args.games)]
        scores, wins = evaluate(pool, args.tier, sides, opponents, seeds, args.cap, f"g{generation}")
        order = sorted(range(len(xs)), key=lambda i: -scores[i])
        elite = [xs[i] for i in order[:args.elite]]
        weights = [math.log(args.elite + 0.5) - math.log(rank + 1) for rank in range(args.elite)]
        total = sum(weights)
        for d in range(len(specs)):
            target = sum(w * e[d] for w, e in zip(weights, elite)) / total
            spread = math.sqrt(sum(w * (e[d] - target) ** 2 for w, e in zip(weights, elite)) / total)
            mean[d] += 0.5 * (target - mean[d])
            sigma[d] = min(0.4, max(0.03, 0.8 * sigma[d] + 0.2 * 1.3 * spread))
        state["history"].append(list(mean))
        state["history"] = state["history"][-30:]
        state["generation"] = generation + 1
        entry = {"generation": generation, "mean_score": round(scores[0], 3), "mean_wins": round(wins[0], 3),
                 "best_score": round(scores[order[0]], 3), "best_wins": round(wins[order[0]], 3),
                 "population_wins": round(sum(wins) / len(wins), 3), "seconds": round(time.time() - started)}
        state["log"].append(entry)
        state_path.write_text(json.dumps(state), encoding="utf-8")
        (OUT / f"{args.tier}-champion.json").write_text(json.dumps(profile_changes(specs, mean), indent=1), encoding="utf-8")
        print(json.dumps(entry), flush=True)


if __name__ == "__main__":
    sys.exit(main())
