"""Synthesizes the default resource pack's sound effects (stdlib only).

    python tools/make_default_sfx.py

Writes 44.1 kHz 16-bit mono WAV files to packs/default/sounds/. Every sound is
generated from the recipes below (no samples, no downloads), so the set is
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


def recipes():
    r = {}
    # --- piece handling: short, soft, never tiring ---------------------------
    r["move"] = tone(0.035, 1150, 900, "tri", attack=0.001, decay=0.010)
    r["rotate"] = mix((0.0, tone(0.03, 720, shape="tri", attack=0.001, decay=0.012)),
                      (0.022, tone(0.05, 1080, shape="tri", attack=0.001, decay=0.016)))
    r["hold"] = mix((0.0, tone(0.11, 480, 960, "sine", decay=0.05)),
                    (0.0, noise(0.11, 900, 4000, attack=0.02, decay=0.05, gain=0.25, seed=3)))
    r["lock"] = mix((0.0, tone(0.09, 170, 85, "sine", attack=0.001, decay=0.03)),
                    (0.0, noise(0.03, 2500, 600, attack=0.0005, decay=0.008, gain=0.35, seed=4)))
    r["hard_drop"] = mix((0.0, tone(0.16, 150, 48, "sine", attack=0.001, decay=0.05, curve=0.5)),
                         (0.0, noise(0.09, 5000, 300, attack=0.0005, decay=0.02, gain=0.55, seed=5)),
                         (0.0, tone(0.03, 900, 300, "tri", attack=0.0005, decay=0.008, gain=0.3)))
    # --- clears ---------------------------------------------------------------
    r["clear"] = mix((0.0, notes(["C6", "E6", "G6"], 0.045, 0.22, "tri", decay=0.07)),
                     (0.0, noise(0.12, 6000, 9000, attack=0.002, decay=0.03, gain=0.12, seed=6)))
    r["tetris"] = mix((0.0, notes(["C5", "E5", "G5", "C6"], 0.06, 0.3, "square", decay=0.09, gain=0.8)),
                      (0.24, chord(["C6", "E6", "G6"], 0.5, "tri", decay=0.16, gain=1.6)),
                      (0.24, noise(0.3, 7000, 3000, attack=0.002, decay=0.08, gain=0.15, seed=7)))
    r["tspin"] = mix((0.0, tone(0.16, 330, 1320, "saw", attack=0.004, decay=0.09, gain=0.5, vibrato=0.03)),
                     (0.12, chord(["E5", "G#5", "B5", "E6"], 0.36, "tri", decay=0.12, gain=1.8)))
    r["perfect_clear"] = mix((0.0, notes(["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6", "C7"], 0.055, 0.3, "tri", decay=0.1)),
                             (0.55, chord(["C6", "E6", "G6", "C7"], 0.6, "sine", decay=0.2, gain=2.2)))
    # One pluck; the game raises its pitch with the combo count.
    r["combo"] = mix((0.0, tone(0.14, hz("G5"), shape="tri", attack=0.001, decay=0.045)),
                     (0.0, tone(0.14, hz("G6"), shape="sine", attack=0.001, decay=0.03, gain=0.35)))
    r["level_up"] = mix((0.0, notes(["G5", "C6", "E6", "G6"], 0.075, 0.28, "square", decay=0.09, gain=0.7)),
                        (0.225, tone(0.4, hz("C7"), shape="sine", decay=0.14, gain=0.5)))
    # --- versus ---------------------------------------------------------------
    r["attack"] = mix((0.0, tone(0.2, 1700, 420, "saw", attack=0.002, decay=0.06, gain=0.6, curve=0.6)),
                      (0.0, noise(0.12, 8000, 1500, attack=0.001, decay=0.03, gain=0.2, seed=8)))
    r["garbage"] = mix((0.0, tone(0.28, 95, 55, "sine", attack=0.004, decay=0.09)),
                       (0.0, noise(0.28, 700, 180, attack=0.004, decay=0.08, gain=0.9, seed=9)))
    r["countdown"] = tone(0.14, 660, shape="sine", attack=0.003, decay=0.05)
    r["go"] = mix((0.0, tone(0.4, 1320, shape="sine", attack=0.003, decay=0.14)),
                  (0.0, tone(0.4, 1980, shape="sine", attack=0.003, decay=0.09, gain=0.3)))
    r["ko"] = mix((0.0, tone(0.7, 420, 50, "saw", attack=0.003, decay=0.25, gain=0.7, curve=0.7)),
                  (0.0, noise(0.6, 3000, 150, attack=0.002, decay=0.18, gain=0.6, seed=10)))
    r["win"] = mix((0.0, notes(["C5", "E5", "G5", "C6", "E6"], 0.09, 0.32, "square", decay=0.1, gain=0.7)),
                   (0.45, chord(["C5", "G5", "C6", "E6", "G6"], 0.8, "tri", decay=0.28, gain=2.4)))
    r["lose"] = mix((0.0, notes(["A4", "F4", "D4"], 0.17, 0.4, "tri", decay=0.14)),
                    (0.51, tone(0.7, hz("A3"), hz("A3") * 0.94, "tri", decay=0.25)))
    r["game_over"] = mix((0.0, notes(["E5", "C5", "A4", "F4"], 0.15, 0.4, "square", decay=0.13, gain=0.7)),
                         (0.6, chord(["D4", "F4", "A4"], 0.8, "tri", decay=0.28, gain=2.0)))
    # --- interface ------------------------------------------------------------
    r["pause"] = mix((0.0, tone(0.07, 880, shape="tri", decay=0.025)), (0.06, tone(0.1, 660, shape="tri", decay=0.035)))
    r["resume"] = mix((0.0, tone(0.07, 660, shape="tri", decay=0.025)), (0.06, tone(0.1, 880, shape="tri", decay=0.035)))
    r["ui_focus"] = tone(0.03, 1500, 1300, "sine", attack=0.001, decay=0.008)
    r["ui_press"] = mix((0.0, tone(0.05, 900, shape="tri", attack=0.001, decay=0.018)),
                        (0.035, tone(0.08, 1350, shape="tri", attack=0.001, decay=0.028)))
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
