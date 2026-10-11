#!/usr/bin/env python3
"""Synthesizes the "Cold War Synth" arrangement of Korobeiniki as a ladder of
six tracks, from calm to danger.

Korobeiniki is a public-domain Russian folk song; the arrangement here is
original: a 1980s synth score in A harmonic minor - a sixteenth-note bass
whose filter breathes with the beat, pads chopped by a rhythmic gate, kick
ducking, a gated snare, a delayed saw lead.

  korobeiniki-coldwar-synth.ogg    the game's BGM: 120 BPM, a 4-bar intro
                                   (8 s) and a 40-bar body (80 s). The body
                                   is the loop: its reverb and delay tails
                                   are folded onto its own first bar, and the
                                   game restarts the stream at the end of the
                                   intro (loop offset 8 s), so the intro is
                                   heard once and the body goes round forever.
  korobeiniki-coldwar-rise-1.ogg   the same 40 bars, a little faster and a
  ... rise-2, rise-3, rise-4       little harder each time: 126, 132, 138 and
                                   144 BPM.
  korobeiniki-coldwar-danger.ogg   the top of the ladder: 150 BPM (64 s),
                                   sixteenth-note hats, an alarm on the
                                   off-beats, the tune doubled all the way.

Bar for bar the six are the same music, so the game can step from one to the
next at a bar line and carry on at the same point of the tune
(scripts/bgm_director.gd): as a stack grows the music speeds up one small step
at a time instead of jumping.

    python tools/make_coldwar_bgm.py

Needs numpy, scipy and ffmpeg. The files go to assets/audio/bgm/;
assets/assets-measurements.json binds their sha256 (tests/test_music.gd checks
it), so update those records after re-rendering. Deterministic: the same
script always renders the same audio.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
# The ladder: (file, BPM, heat 0..1, has the intro).
TRACKS = [
    ("korobeiniki-coldwar-synth.ogg", 120.0, 0.0, True),
    ("korobeiniki-coldwar-rise-1.ogg", 126.0, 0.2, False),
    ("korobeiniki-coldwar-rise-2.ogg", 132.0, 0.4, False),
    ("korobeiniki-coldwar-rise-3.ogg", 138.0, 0.6, False),
    ("korobeiniki-coldwar-rise-4.ogg", 144.0, 0.8, False),
    ("korobeiniki-coldwar-danger.ogg", 150.0, 1.0, False),
]
INTRO_BARS = 4
BODY_BARS = 40
TAIL = SR * 3
BGM_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "bgm"

# Set by render() for the tempo being rendered.
S16 = 0  # one sixteenth, in samples
BAR = 0
rng = np.random.default_rng(1986)


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


# The tune on an eighth-note grid (None = rest); bars 1-8 are the A strain,
# bars 9-16 the B strain. Every bar sums to eight eighths.
MELODY = [
    [(76, 2), (71, 1), (72, 1), (74, 2), (72, 1), (71, 1)],
    [(69, 2), (69, 1), (72, 1), (76, 2), (74, 1), (72, 1)],
    [(71, 3), (72, 1), (74, 2), (76, 2)],
    [(72, 2), (69, 2), (69, 2), (None, 2)],
    [(None, 1), (74, 2), (77, 1), (81, 2), (79, 1), (77, 1)],
    [(76, 3), (72, 1), (76, 2), (74, 1), (72, 1)],
    [(71, 2), (71, 1), (72, 1), (74, 2), (76, 2)],
    [(72, 2), (69, 2), (69, 2), (None, 2)],
    [(76, 4), (72, 4)],
    [(74, 4), (71, 4)],
    [(72, 4), (69, 4)],
    [(68, 4), (71, 4)],
    [(76, 4), (72, 4)],
    [(74, 4), (71, 4)],
    [(72, 2), (76, 2), (81, 4)],
    [(80, 8)],
]
# Harmony per bar: (bass root, chord tones). E is the dominant with its G#.
AM = (45, (57, 60, 64))
E = (40, (56, 59, 64))
DM = (38, (57, 62, 65))
F = (41, (57, 60, 65))
C = (36, (55, 60, 64))
CHORDS_A = [E, AM, E, AM, DM, AM, E, AM]
CHORDS_A2 = [E, AM, E, AM, DM, F, E, AM]
CHORDS_B = [AM, E, AM, E, F, C, DM, E]
SCALE = {9, 11, 0, 2, 4, 5, 7, 8}  # A minor plus the leading tone
# The pads' gate: which sixteenths of a bar let them through.
GATE = [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1]


class Bus:
    """A stereo bus with a reverb send; everything is added by sample offset."""

    def __init__(self, n: int) -> None:
        self.n = n
        self.dry = np.zeros((2, n))
        self.send = np.zeros((2, n))

    def add(self, at: int, mono: np.ndarray, gain: float = 1.0, pan: float = 0.0, send: float = 0.0) -> None:
        end = min(self.n, at + len(mono))
        if end <= at:
            return
        part = mono[: end - at] * gain
        left = np.sqrt(0.5 * (1.0 - pan))
        right = np.sqrt(0.5 * (1.0 + pan))
        self.dry[0, at:end] += part * left
        self.dry[1, at:end] += part * right
        if send > 0.0:
            self.send[0, at:end] += part * left * send
            self.send[1, at:end] += part * right * send


def envelope(n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    env = np.full(n + r, sustain)
    env[:a] = np.linspace(0.0, 1.0, a)
    d = max(1, int(decay * SR))
    stop = min(n, a + d)
    if stop > a:
        env[a:stop] = np.linspace(1.0, sustain, stop - a)
    env[n:] = np.linspace(env[n - 1] if n > 0 else sustain, 0.0, r)
    return env


def shaped(length: int, n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    """envelope() cut or zero-padded to `length` samples."""
    env = envelope(n, attack, decay, sustain, release)
    if len(env) >= length:
        return env[:length]
    return np.concatenate([env, np.zeros(length - len(env))])


def saws(freq: float, n: int, cents: tuple[float, ...]) -> np.ndarray:
    t = np.arange(n) / SR
    out = np.zeros(n)
    for cent in cents:
        f = freq * 2.0 ** (cent / 1200.0)
        out += signal.sawtooth(2.0 * np.pi * (f * t + rng.random()))
    return out / len(cents)


def lowpass(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, min(cutoff, SR * 0.45), btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, cutoff, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def sweep(x: np.ndarray, position: np.ndarray, cutoffs: tuple[float, ...]) -> np.ndarray:
    """A moving low-pass: `position` (0..1 per sample) slides between the
    cutoffs, by cross-fading copies of `x` filtered at each of them."""
    place = np.clip(position, 0.0, 1.0) * (len(cutoffs) - 1)
    out = np.zeros_like(x)
    for index, cutoff in enumerate(cutoffs):
        weight = np.clip(1.0 - np.abs(place - index), 0.0, 1.0)
        out += lowpass(x, cutoff, 4) * weight
    return out


def bass_note(midi: int, n: int) -> np.ndarray:
    """Saw over a square an octave down; the filter is the bus's job."""
    length = n + int(0.03 * SR)
    t = np.arange(length) / SR
    f = hz(midi)
    raw = 0.7 * signal.sawtooth(2 * np.pi * f * t) + 0.3 * signal.square(2 * np.pi * f * 0.5 * t, duty=0.4) \
        + 0.35 * signal.sawtooth(2 * np.pi * f * 1.006 * t + 1.0)
    return raw * shaped(length, n, 0.003, 0.08, 0.6, 0.03)


def pad_chord(notes: tuple[int, ...], n: int) -> tuple[np.ndarray, np.ndarray]:
    length = n + int(0.5 * SR)
    left = np.zeros(length)
    right = np.zeros(length)
    for note in notes:
        left += saws(hz(note), length, (-9.0, 0.0, 6.0)) + 0.5 * saws(hz(note + 12), length, (-4.0, 5.0))
        right += saws(hz(note), length, (-5.0, 3.0, 11.0)) + 0.5 * saws(hz(note + 12), length, (-7.0, 2.0))
    env = shaped(length, n, 0.05, 0.3, 0.85, 0.5)
    return left * env / len(notes), right * env / len(notes)


def lead_note(midi: int, n: int, voice: str) -> np.ndarray:
    length = n + int(0.12 * SR)
    t = np.arange(length) / SR
    vibrato = 1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.18) / 0.2, 0.0, 1.0)
    phase = 2 * np.pi * np.cumsum(hz(midi) * vibrato) / SR
    if voice == "pulse":
        # Pulse width drifting back and forth: the slow shimmer of the era.
        width = 0.5 + 0.3 * np.sin(2 * np.pi * 0.9 * t + 1.3)
        raw = np.sign(signal.sawtooth(phase) + (1.0 - 2.0 * width)) * 0.7 + np.sin(phase) * 0.3
        tone = lowpass(raw, 3600.0)
        env = shaped(length, n, 0.008, 0.12, 0.7, 0.1)
    else:
        raw = np.zeros(length)
        for cent in (-14.0, -6.0, 0.0, 7.0, 13.0):
            raw += signal.sawtooth(phase * 2.0 ** (cent / 1200.0) + rng.random() * 6.28)
        raw = raw / 5.0 + 0.25 * signal.sawtooth(phase * 0.5)
        tone = lowpass(raw, 6000.0)
        env = shaped(length, n, 0.012, 0.2, 0.8, 0.12)
    return tone * env


def pluck(midi: int, n: int) -> np.ndarray:
    length = n + int(0.05 * SR)
    t = np.arange(length) / SR
    raw = signal.square(2 * np.pi * hz(midi) * t, duty=0.25) + 0.5 * signal.sawtooth(2 * np.pi * hz(midi) * 1.004 * t)
    return raw * np.exp(-t / 0.1) * np.minimum(1.0, t / 0.002)


def kick() -> np.ndarray:
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    freq = 46.0 + 120.0 * np.exp(-t / 0.028)
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.15)
    click = highpass(rng.standard_normal(n), 2500.0) * np.exp(-t / 0.004) * 0.25
    return np.tanh((body + click) * 1.6)


def snare() -> np.ndarray:
    """Noise crack plus the era's gated room: a loud tail that is cut off."""
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    crack = signal.sosfilt(signal.butter(2, (900.0, 7000.0), btype="band", fs=SR, output="sos"), noise) * np.exp(-t / 0.06)
    tone = np.sin(2 * np.pi * (185.0 + 60.0 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.07)
    gate_len = int(0.2 * SR)
    room = lowpass(rng.standard_normal(n), 3800.0)
    gate = np.zeros(n)
    gate[:gate_len] = 1.0
    gate[gate_len:gate_len + 400] = np.linspace(1.0, 0.0, 400)
    return crack * 1.0 + tone * 0.6 + room * gate * 0.22


def hat(open_: bool) -> np.ndarray:
    n = int((0.22 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    return highpass(rng.standard_normal(n), 7500.0, 4) * np.exp(-t / (0.07 if open_ else 0.014))


def tom(midi: float) -> np.ndarray:
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    freq = hz(midi) * (1.0 + 0.5 * np.exp(-t / 0.04))
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.13)


def riser(n: int) -> np.ndarray:
    """Filtered noise swelling into the next section."""
    t = np.linspace(0.0, 1.0, n)
    return sweep(rng.standard_normal(n), t ** 2, (400.0, 1500.0, 5000.0, 11000.0)) * t ** 2


def harmony_under(midi: int) -> int:
    """The scale tone a third (or fourth) under a melody note."""
    for step in (3, 4, 5):
        if (midi - step) % 12 in SCALE:
            return midi - step
    return midi - 12


# The body's sections: (name, bars, melody bars, chords, what plays).
BODY = [
    ("a1", 8, MELODY[:8], CHORDS_A, {"drums": 1, "lead": "pulse", "arp": 0.5}),
    ("a2", 8, MELODY[:8], CHORDS_A2, {"drums": 1, "lead": "saw", "arp": 1.0, "fill": 1}),
    ("b1", 8, MELODY[8:], CHORDS_B, {"drums": "half", "lead": "saw", "long": 1, "arp": 0.6, "fill": 1}),
    ("a3", 8, MELODY[:8], CHORDS_A2, {"drums": 1, "lead": "saw", "arp": 1.0, "harmony": 1, "open": 1}),
    ("b2", 8, MELODY[8:], CHORDS_B, {"drums": 1, "lead": "saw", "long": 1, "arp": 1.0, "harmony": 1, "fill": 1}),
]
INTRO = ("intro", INTRO_BARS, None, [AM, AM, E, E], {"kick_from": 2, "fill": 1, "arp": 0.4})


def render(bpm: float, heat: float, intro: bool) -> tuple[np.ndarray, float]:
    """The finished stereo track and the length of its intro in seconds.

    `heat` (0 calm .. 1 danger) hardens the arrangement step by step."""
    global S16, BAR, rng
    rng = np.random.default_rng(1986)
    S16 = int(round(SR * 60.0 / bpm / 4.0))
    BAR = S16 * 16
    sections = [INTRO] + list(BODY) if intro else list(BODY)
    bars = sum(section[1] for section in sections)
    n = bars * BAR + TAIL
    drums, bass, pad, music = Bus(n), Bus(n), Bus(n), Bus(n)
    kick_times: list[int] = []
    k, s, hc, ho = kick(), snare(), hat(False), hat(True)

    bar_index = 0
    for name, length, melody, chords, parts in sections:
        for local in range(length):
            start = (bar_index + local) * BAR
            root, tones = chords[local % len(chords)]
            last = local == length - 1
            # The half-time strain goes four-on-the-floor in the hot tracks.
            half = parts.get("drums") == "half" and heat < 0.6
            full = parts.get("drums") == 1 or (parts.get("drums") == "half" and not half)

            # Bass: sixteenths on the root, every fourth one an octave up.
            if half:
                for step in range(0, 16, 2):
                    bass.add(start + step * S16, bass_note(root + (12 if step % 8 == 6 else 0), S16 * 2 - 200), 0.3)
            else:
                for step in range(16):
                    accent = 1.0 if step % 4 == 0 else 0.8
                    bass.add(start + step * S16, bass_note(root + (12 if step % 4 == 3 else 0), S16 - 300), 0.3 * accent)

            # Pad: the chord (gated later, on the bus).
            left, right = pad_chord(tones, BAR)
            pad.add(start, left, 0.3, -1.0, 0.45)
            pad.add(start, right, 0.3, 1.0, 0.45)

            # Drums.
            intro_kick = "kick_from" in parts and local >= parts["kick_from"]
            if full or intro_kick:
                for beat in range(4):
                    kick_times.append(start + beat * 4 * S16)
                    drums.add(start + beat * 4 * S16, k, 0.66)
                if heat >= 0.4:
                    drums.add(start + 15 * S16, k, 0.4 * heat)
            if half:
                for at, level in ((0, 0.66), (8, 0.66), (10, 0.45)):
                    kick_times.append(start + at * S16)
                    drums.add(start + at * S16, k, level)
            if full:
                for beat in (1, 3):
                    drums.add(start + beat * 4 * S16, s, 0.75, 0.0, 0.25)
                if heat >= 0.4:
                    drums.add(start + 11 * S16, s, 0.3 * heat, 0.2, 0.2)
            if half:
                drums.add(start + 8 * S16, s, 0.8, 0.0, 0.35)
            if full or half or intro_kick:
                for step in range(16):
                    off = step % 4 == 2
                    if step % 2 == 1:
                        # The sixteenths in between come up with the heat.
                        if heat > 0.0:
                            drums.add(start + step * S16, hc, 0.13 * heat, 0.3)
                    elif off and (parts.get("open") or heat >= 0.6):
                        drums.add(start + step * S16, ho, 0.3, 0.3)
                    else:
                        drums.add(start + step * S16, hc, 0.36 if off else 0.22, 0.3)
                if full and heat < 0.5:
                    for step in (7, 15):
                        drums.add(start + step * S16, hc, 0.15, -0.3)
            # Into the next section: snare roll, falling toms, a noise swell.
            if last and parts.get("fill"):
                for i, step in enumerate(range(8, 12)):
                    drums.add(start + step * S16, s, 0.25 + 0.07 * i, 0.0, 0.2)
                for i, (step, note) in enumerate(((12, 57), (13, 54), (14, 50), (15, 45))):
                    drums.add(start + step * S16, tom(note), 0.6, -0.5 + 0.33 * i, 0.3)
                music.add(start, riser(BAR), 0.09, 0.0, 0.3)

            # Arpeggio: chord tones in sixteenths, up and back over two octaves.
            if parts.get("arp"):
                ladder = [tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[0] + 24, tones[1] + 24, tones[0] + 24, tones[2] + 12, tones[1] + 12]
                # Its filter opens over the section and closes again.
                where = (local + 0.5) / length
                bright = 1400.0 + 3600.0 * np.sin(np.pi * where) ** 2 * float(parts["arp"])
                for step in range(16):
                    note = lowpass(pluck(ladder[step % 8], S16), bright)
                    music.add(start + step * S16, note, 0.2 * (0.6 + 0.4 * float(parts["arp"])), -0.6 if step % 2 == 0 else 0.6, 0.35)

            # As it gets hot an alarm answers on the off-beats, louder each step.
            if heat > 0.2:
                for step in (2, 6, 10, 14):
                    music.add(start + step * S16, lowpass(pluck(88 if step % 8 == 2 else 83, S16), 5000.0), 0.13 * (heat - 0.2) / 0.8, 0.0, 0.4)

            # Lead: the tune, with a harmony voice under it in the later sections.
            if melody is not None:
                voice = "saw" if heat >= 0.6 else parts["lead"]
                under = 1.0 if parts.get("harmony") else heat
                below = 1.0 if parts.get("long") else heat
                at = start
                for midi, eighths in melody[local]:
                    count = eighths * 2 * S16
                    if midi is not None:
                        gap = 500 if eighths <= 2 else 1500
                        music.add(at, lead_note(midi, count - gap, voice), 0.44 if voice == "pulse" else 0.42, 0.0, 0.35)
                        if under > 0.0:
                            music.add(at, lead_note(harmony_under(midi), count - gap, "saw"), 0.14 * under, 0.35, 0.3)
                        if below > 0.0:
                            music.add(at, lead_note(midi - 12, count - gap, "saw"), 0.12 * below, -0.35, 0.3)
                    at += count
        bar_index += length

    t_bar = np.arange(n) / BAR          # time in bars
    beat_phase = (t_bar * 4.0) % 1.0    # position inside the beat

    # The bass filter breathes: shut on the beat, wide open on the off-beat,
    # and the whole motion rises and falls over four bars.
    breath = 0.5 - 0.5 * np.cos(2 * np.pi * beat_phase)
    tide = 0.55 + 0.45 * np.sin(2 * np.pi * t_bar / 4.0 - np.pi / 2)
    bass_position = np.clip(0.12 + breath * (0.45 + 0.4 * tide), 0.0, 1.0)
    for channel in range(2):
        bass.dry[channel] = sweep(bass.dry[channel], bass_position, (180.0, 500.0, 1400.0, 3800.0))
    bass.dry = np.tanh(bass.dry * 1.4) * 0.8

    # The pads are chopped by a sixteenth-note gate and swept over two bars.
    step_index = np.minimum((t_bar * 16.0).astype(int) % 16, 15)
    gate = np.array(GATE, dtype=float)[step_index]
    smooth = int(0.006 * SR)
    gate = np.convolve(gate, np.ones(smooth) / smooth, mode="same")
    pad_gain = 0.22 + 0.78 * gate
    pad_position = 0.35 + 0.4 * (0.5 - 0.5 * np.cos(2 * np.pi * t_bar / 2.0)) + 0.15 * heat
    for channel in range(2):
        pad.dry[channel] = sweep(pad.dry[channel], pad_position, (500.0, 1300.0, 3200.0, 7000.0)) * pad_gain
        pad.send[channel] *= pad_gain
    if intro:
        # The intro grows out of nothing.
        rise = np.clip(np.arange(n) / (INTRO_BARS * BAR), 0.0, 1.0)
        bass.dry *= 0.25 + 0.75 * rise ** 1.5
        pad.dry *= 0.5 + 0.5 * rise

    # The kick pumps the bass and the pads.
    pump = np.ones(n)
    dip_len = int(0.26 * SR)
    dip = 1.0 - 0.8 * np.exp(-np.arange(dip_len) / (0.08 * SR))
    for at in kick_times:
        end = min(n, at + dip_len)
        pump[at:end] = np.minimum(pump[at:end], dip[: end - at])
    for bus in (bass, pad):
        bus.dry *= pump
        bus.send *= pump

    # Dotted-eighth echo on the lead and the arpeggio, bouncing left to right.
    echo = np.zeros_like(music.dry)
    delay = S16 * 3
    for tap, gain in enumerate((0.34, 0.2, 0.11), start=1):
        shifted = np.zeros_like(music.dry)
        shifted[:, delay * tap:] = music.dry[:, : n - delay * tap]
        if tap % 2 == 1:
            shifted = shifted[::-1]
        echo += shifted * gain
    music.dry += lowpass(echo, 3500.0)

    # One hall for everything that asked for it.
    send = drums.send + bass.send + pad.send + music.send
    hall_len = int(2.2 * SR)
    t = np.arange(hall_len) / SR
    wet = np.zeros_like(send)
    for channel in range(2):
        impulse = lowpass(rng.standard_normal(hall_len), 5200.0) * np.exp(-t / 0.55)
        impulse[: int(0.012 * SR)] = 0.0
        impulse /= np.sqrt(np.sum(impulse ** 2))
        wet[channel] = signal.fftconvolve(send[channel], impulse)[:n]

    full_mix = drums.dry + bass.dry + pad.dry + music.dry + wet * 0.5
    # The loop is the body: fold what rings on past its last bar onto its
    # first bar, so going round is the same as playing on.
    intro_len = INTRO_BARS * BAR if intro else 0
    end = bars * BAR
    looped = full_mix[:, :end].copy()
    looped[:, intro_len:intro_len + TAIL] += full_mix[:, end:end + TAIL]
    looped = highpass(looped, 28.0)
    looped = np.tanh(looped * 1.2)
    return looped / np.max(np.abs(looped)) * 0.89, intro_len / SR


def write(audio: np.ndarray, name: str) -> None:
    pcm = (audio.T * 32767.0).astype("<i2")
    BGM_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "track.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(SR)
            wav.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "6", str(BGM_DIR / name)], check=True)


def main() -> int:
    for name, bpm, heat, has_intro in TRACKS:
        audio, intro = render(bpm, heat, has_intro)
        write(audio, name)
        level = 20.0 * np.log10(np.sqrt(np.mean(audio ** 2)))
        print("%s: %.5f s, intro %.5f s, %g BPM (exactly %.4f), mean %.1f dB" % (name, audio.shape[1] / SR, intro, bpm, SR * 15.0 / S16, level))
    return 0


if __name__ == "__main__":
    sys.exit(main())
