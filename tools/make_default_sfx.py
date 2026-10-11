"""Synthesizes the default resource pack's sound effects (stdlib only).

    python tools/make_default_sfx.py

Writes 44.1 kHz 16-bit mono WAV files to packs/default/sounds/. The set is a
casino floor - chips and cards for the pieces, bells for the clears, a reel
spinning up for a T-spin, a cash register for Back-to-Back, coins paying out
for the big ones. Every sound is generated from the recipes below (no samples, no downloads), so the set is
ours to ship and anybody can retune it: edit a recipe, rerun, reimport.
The output is deterministic (the noise generator is seeded).
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "packs", "default", "sounds")

NOTE = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}


def hz(name):
    """'A4' -> 440.0"""
    return 440.0 * 2.0 ** ((NOTE[name[:-1]] + 12 * (int(name[-1]) - 4)) / 12.0)


def wave_at(shape, phase):
    x = phase % 1.0
    if shape == "sine":
        return math.sin(2.0 * math.pi * x)
    if shape == "tri":
        return 4.0 * abs(x - 0.5) - 1.0
    if shape == "square":
        # Softened square: fundamental plus two odd harmonics.
        return (math.sin(2 * math.pi * x) + math.sin(6 * math.pi * x) / 3.0 + math.sin(10 * math.pi * x) / 5.0) * 0.9
    if shape == "saw":
        return sum(math.sin(2 * math.pi * k * x) / k for k in range(1, 7)) * 0.6
    raise ValueError(shape)


def tone(seconds, f0, f1=None, shape="sine", attack=0.004, decay=None, gain=1.0, curve=1.0, vibrato=0.0):
    """One voice gliding f0 -> f1 with a linear attack and an exponential decay."""
    n = int(seconds * RATE)
    f1 = f0 if f1 is None else f1
    decay = seconds / 4.0 if decay is None else decay
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        k = (i / max(1, n - 1)) ** curve
        freq = f0 * (f1 / f0) ** k
        if vibrato:
            freq *= 1.0 + vibrato * math.sin(2 * math.pi * 14.0 * t)
        phase += freq / RATE
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out.append(wave_at(shape, phase) * env * gain)
    return out


def noise(seconds, cutoff0, cutoff1=None, attack=0.002, decay=None, gain=1.0, seed=1):
    """White noise through a one-pole low-pass whose cutoff glides."""
    rng = random.Random(seed)
    n = int(seconds * RATE)
    cutoff1 = cutoff0 if cutoff1 is None else cutoff1
    decay = seconds / 4.0 if decay is None else decay
    out = []
    y = 0.0
    for i in range(n):
        t = i / RATE
        cutoff = cutoff0 * (cutoff1 / cutoff0) ** (i / max(1, n - 1))
        a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
        y += a * (rng.uniform(-1.0, 1.0) - y)
        out.append(y * min(1.0, t / attack) * math.exp(-t / decay) * gain)
    return out


def mix(*layers):
    """Layers are (start_seconds, samples)."""
    length = max(int(start * RATE) + len(samples) for start, samples in layers)
    out = [0.0] * length
    for start, samples in layers:
        offset = int(start * RATE)
        for i, value in enumerate(samples):
            out[offset + i] += value
    return out


def notes(names, step, length, shape="tri", decay=None, gain=1.0):
    """Arpeggio: one note every `step` seconds."""
    return mix(*[(i * step, tone(length, hz(name), shape=shape, decay=decay, gain=gain)) for i, name in enumerate(names)])


def chord(names, length, shape="tri", decay=None, gain=1.0):
    return mix(*[(0.0, tone(length, hz(name), shape=shape, decay=decay, gain=gain / len(names))) for name in names])


def finish(samples, peak=0.7):
    """Normalizes to `peak` and fades the last 8 ms so nothing clicks."""
    top = max(1e-9, max(abs(v) for v in samples))
    fade = int(0.008 * RATE)
    out = []
    for i, value in enumerate(samples):
        gain = peak / top
        tail = len(samples) - i
        if tail < fade:
            gain *= tail / fade
        out.append(value * gain)
    return out


# --- the casino floor: bells, coins, chips, reels ---------------------------
def bell(seconds, f, decay=None, gain=1.0, bright=1.0):
    """A struck bell: inharmonic partials, the high ones dying first."""
    decay = seconds / 3.0 if decay is None else decay
    partials = [(1.0, 1.0, 1.0), (2.0, 0.55, 0.7), (2.76, 0.4, 0.5), (5.4, 0.22 * bright, 0.3), (8.93, 0.1 * bright, 0.18)]
    return mix(*[(0.0, tone(seconds, f * ratio, shape="sine", attack=0.001, decay=decay * life, gain=gain * level))
                 for ratio, level, life in partials if f * ratio < 18000.0])


def bells(names, step, length, decay=None, gain=1.0):
    """A run of bells, one every `step` seconds."""
    return mix(*[(i * step, bell(length, hz(name), decay=decay, gain=gain)) for i, name in enumerate(names)])


def trill(names, step, count, gain=1.0):
    """The win bell: two notes hammered in turn."""
    return mix(*[(i * step, bell(step * 3.0, hz(names[i % len(names)]), decay=step * 0.9, gain=gain)) for i in range(count)])


def coin(f=4200.0, gain=1.0):
    """One coin on metal: three high partials that ring for a moment."""
    return mix((0.0, tone(0.14, f, shape="sine", attack=0.0005, decay=0.035, gain=gain)),
               (0.0, tone(0.14, f * 1.48, shape="sine", attack=0.0005, decay=0.026, gain=gain * 0.7)),
               (0.0, tone(0.1, f * 2.31, shape="sine", attack=0.0005, decay=0.014, gain=gain * 0.4)))


def coins(count, span, seed, gain=1.0):
    """A payout: `count` coins falling over `span` seconds, thinning out."""
    rng = random.Random(seed)
    return mix(*[(span * rng.random() ** 1.6, coin(rng.uniform(3300.0, 5600.0), gain * rng.uniform(0.5, 1.0))) for _ in range(count)])


def click(f, gain=1.0):
    """A chip, a card edge, one tooth of a reel."""
    return tone(0.014, f, f * 0.6, "tri", attack=0.0005, decay=0.0035, gain=gain)


def reel(seconds, f0, f1, gain=1.0):
    """A reel spinning up: clicks that get closer and higher."""
    layers = []
    t = 0.0
    while t < seconds:
        k = t / seconds
        layers.append((t, click(f0 * (f1 / f0) ** k, gain * (0.5 + 0.5 * k))))
        t += 0.026 - 0.014 * k
    return mix(*layers)


def recipes():
    r = {}
    # --- piece handling: chips and cards, short and dry ------------------------
    r["move"] = mix((0.0, click(2600)), (0.0, tone(0.03, 1300, shape="sine", attack=0.0005, decay=0.008, gain=0.4)))
    r["rotate"] = mix((0.0, noise(0.04, 7000, 2500, attack=0.0005, decay=0.01, gain=0.5, seed=2)),
                      (0.012, click(1900, 0.9)))
    r["hold"] = mix((0.0, noise(0.1, 2000, 7000, attack=0.004, decay=0.04, gain=0.35, seed=3)),
                    (0.05, bell(0.12, hz("E6"), decay=0.03, gain=0.5)))
    r["lock"] = mix((0.0, click(1500)), (0.018, click(2300, 0.8)),
                    (0.0, tone(0.07, 160, 90, "sine", attack=0.001, decay=0.025, gain=0.6)))
    r["hard_drop"] = mix((0.0, tone(0.16, 140, 45, "sine", attack=0.001, decay=0.05, curve=0.5)),
                         (0.0, noise(0.07, 4000, 400, attack=0.0005, decay=0.018, gain=0.5, seed=5)),
                         (0.02, click(2100, 0.5)), (0.045, click(1700, 0.4)), (0.075, click(2400, 0.3)))
    # --- clears: every kind of win has its own bell -----------------------------
    r["clear"] = mix((0.0, bell(0.3, hz("C6"), decay=0.08)), (0.05, bell(0.3, hz("E6"), decay=0.08, gain=0.8)),
                     (0.08, coin(4400, 0.5)))
    r["tetris"] = mix((0.0, bells(["C6", "E6", "G6", "C7"], 0.05, 0.3, decay=0.09)),
                      (0.2, trill(["G6", "C7"], 0.045, 10, gain=0.9)),
                      (0.22, coins(14, 0.55, seed=11, gain=0.45)))
    r["tspin_mini"] = bells(["E6", "A6"], 0.06, 0.24, decay=0.07)
    r["tspin"] = mix((0.0, reel(0.14, 900, 2400, 0.6)),
                     (0.1, bells(["E6", "G#6", "B6"], 0.05, 0.32, decay=0.1)))
    r["tspin_double"] = mix((0.0, reel(0.16, 900, 2600, 0.6)),
                            (0.12, bells(["E6", "G#6", "B6", "E7"], 0.05, 0.34, decay=0.1)),
                            (0.32, chord(["E6", "G#6", "B6"], 0.4, "tri", decay=0.13, gain=1.2)),
                            (0.32, coins(8, 0.35, seed=12, gain=0.4)))
    r["tspin_triple"] = mix((0.0, reel(0.18, 900, 2900, 0.6)),
                            (0.14, bells(["E6", "G#6", "B6", "E7", "G#7"], 0.05, 0.34, decay=0.1)),
                            (0.38, trill(["B6", "E7"], 0.045, 12, gain=0.9)),
                            (0.38, chord(["E6", "G#6", "B6", "E7"], 0.6, "tri", decay=0.2, gain=1.3)),
                            (0.4, coins(18, 0.7, seed=13, gain=0.45)))
    # The cash register: played on top of a clear that keeps Back-to-Back going.
    r["b2b"] = mix((0.0, noise(0.03, 5000, 1500, attack=0.0005, decay=0.008, gain=0.5, seed=14)), (0.0, click(900)),
                   (0.05, bell(0.35, hz("B6"), decay=0.1)), (0.11, bell(0.4, hz("E7"), decay=0.12)),
                   (0.15, coin(5000, 0.5)))
    r["perfect_clear"] = mix((0.0, bells(["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6", "C7"], 0.05, 0.3, decay=0.1)),
                             (0.5, trill(["C7", "E7"], 0.04, 22, gain=0.9)),
                             (0.5, chord(["C6", "E6", "G6", "C7"], 0.9, "tri", decay=0.3, gain=1.5)),
                             (0.45, coins(32, 1.2, seed=15, gain=0.45)))
    # One coin; the game raises its pitch with the combo count.
    r["combo"] = mix((0.0, bell(0.16, hz("G6"), decay=0.04)), (0.0, coin(4800, 0.5)))
    r["level_up"] = mix((0.0, bells(["G5", "C6", "E6", "G6", "C7"], 0.06, 0.3, decay=0.09)),
                        (0.3, trill(["G6", "C7"], 0.04, 8, gain=0.8)))
    # --- versus -------------------------------------------------------------------
    r["attack"] = mix((0.0, noise(0.16, 6000, 1500, attack=0.002, decay=0.045, gain=0.5, seed=8)),
                      (0.02, coins(4, 0.12, seed=16, gain=0.6)))
    r["garbage"] = mix((0.0, tone(0.28, 95, 55, "sine", attack=0.004, decay=0.09)),
                       (0.0, noise(0.28, 700, 180, attack=0.004, decay=0.08, gain=0.8, seed=9)),
                       (0.03, click(1300, 0.5)), (0.07, click(1700, 0.45)), (0.1, click(1100, 0.4)),
                       (0.15, click(1500, 0.3)), (0.2, click(1250, 0.25)))
    r["countdown"] = mix((0.0, tone(0.08, 880, shape="tri", attack=0.001, decay=0.02)), (0.0, click(1760, 0.7)))
    r["go"] = mix((0.0, bell(0.5, hz("C7"), decay=0.16)), (0.0, bell(0.5, hz("G7"), decay=0.12, gain=0.5)))
    r["ko"] = mix((0.0, mix(*[(i * 0.11, tone(0.3, hz(name), hz(name) * 0.94, "tri", decay=0.09, vibrato=0.02))
                              for i, name in enumerate(["E5", "D#5", "D5", "C#5"])])),
                  (0.44, tone(0.4, 120, 45, "sine", attack=0.002, decay=0.14, gain=1.2)),
                  (0.44, noise(0.3, 2500, 200, attack=0.002, decay=0.09, gain=0.5, seed=10)))
    r["win"] = mix((0.0, bells(["C5", "E5", "G5", "C6", "E6", "G6"], 0.07, 0.34, decay=0.11)),
                   (0.45, chord(["C5", "G5", "C6", "E6", "G6"], 1.0, "tri", decay=0.32, gain=2.0)),
                   (0.45, trill(["C7", "E7"], 0.04, 18, gain=0.8)),
                   (0.45, coins(28, 1.0, seed=17, gain=0.45)))
    r["lose"] = mix((0.0, bells(["A5", "F5", "D5", "A4"], 0.16, 0.5, decay=0.16, gain=0.9)))
    r["game_over"] = mix((0.0, bells(["E5", "C5", "A4", "F4"], 0.15, 0.45, decay=0.14)),
                         (0.62, bell(0.9, hz("D4"), decay=0.3, gain=1.2)),
                         (0.62, tone(0.3, 110, 50, "sine", attack=0.002, decay=0.1, gain=0.8)))
    # --- interface ------------------------------------------------------------------
    r["pause"] = mix((0.0, bell(0.1, hz("A5"), decay=0.03)), (0.06, bell(0.14, hz("E5"), decay=0.04)))
    r["resume"] = mix((0.0, bell(0.1, hz("E5"), decay=0.03)), (0.06, bell(0.14, hz("A5"), decay=0.04)))
    r["ui_focus"] = click(2400)
    r["ui_press"] = mix((0.0, click(1600)), (0.02, bell(0.1, hz("E6"), decay=0.03, gain=0.8)))
    return r


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, samples in sorted(recipes().items()):
        data = finish(samples)
        path = os.path.join(OUT_DIR, name + ".wav")
        with wave.open(path, "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in data))
        print("%-14s %5.2fs" % (name, len(data) / RATE))


if __name__ == "__main__":
    main()
