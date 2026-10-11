#!/usr/bin/env python3
"""Synthesizes the game's music: a playlist of old Russian tunes, every one in
the same "Cold War Synth" arrangement and every one as a ladder of six tracks
from calm to danger.

The arrangement is original: a 1980s synth score - a sixteenth-note bass whose
filter breathes with the beat, pads chopped by a rhythmic gate, kick ducking,
a gated snare, a delayed saw lead. The tunes are public domain (SONGS names
each one's origin and where its notes were checked).

  <song>-120.ogg ... <song>-180.ogg   one song at 120, 132, 144, 156, 168 and
                                      180 BPM: bar for bar the same music, a
                                      little harder each time (more hats, an
                                      alarm on the off-beats, the tune
                                      doubled).

A track is the song once through - a short vamp in its key, then the tune -
followed by three seconds in which its reverb and echo ring out. The game
(scripts/bgm_director.gd) starts the next song of the playlist exactly where
the bars end, so the ringing lies over the next song's vamp: going from one
song to another, or round the same one, is the same as playing on. As a stack
grows it steps from one track of the ladder to the next at a bar line and
carries on at the same point of the tune.

    python tools/make_bgm.py             render everything, write the playlist
                                         into packs/default/pack.json
    python tools/make_bgm.py kalinka     render only the songs named
    python tools/make_bgm.py --records   only refresh the asset records (run
                                         it after Godot has imported the files)

Needs numpy, scipy and ffmpeg. The files go to assets/audio/bgm/;
assets/assets-measurements.json binds their sha256 (tests/test_music.gd checks
it). Deterministic: the same script always renders the same audio.
"""

from __future__ import annotations

import json
import multiprocessing
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
# The ladder: (BPM, heat 0..1).
LADDER = [(120.0, 0.0), (132.0, 0.2), (144.0, 0.4), (156.0, 0.6), (168.0, 0.8), (180.0, 1.0)]
TAIL = SR * 3
ROOT = Path(__file__).resolve().parent.parent
BGM_DIR = ROOT / "assets" / "audio" / "bgm"
PACK = ROOT / "packs" / "default" / "pack.json"
VOLUME_DB = -13.0
# The level a calm track is played at VOLUME_DB; louder ones are turned down.
LEVEL_DB = -13.0

# Set by render() for the song and the tempo being rendered.
S16 = 0   # one sixteenth, in samples
SPB = 16  # sixteenths in a bar (12 in 3/4)
BAR = 0
rng = np.random.default_rng(1986)

# What plays in a section.
PULSE = {"drums": 1, "lead": "pulse", "arp": 0.5, "fill": 1}
SAW = {"drums": 1, "lead": "saw", "arp": 1.0, "fill": 1}
WIDE = {"drums": "half", "lead": "saw", "long": 1, "arp": 0.6, "fill": 1}
FULL = {"drums": 1, "lead": "saw", "arp": 1.0, "harmony": 1, "open": 1, "fill": 1}
GRAND = {"drums": 1, "lead": "saw", "long": 1, "arp": 1.0, "harmony": 1, "fill": 1}
VAMP = {"drums": 1, "arp": 0.5, "fill": 1}

# The tunes. A melody is bars divided by "|", a bar is notes "E5:2" (pitch,
# length in eighths; "-" is a rest) and must fill the bar; chords are one per
# bar, or two ("A/Dm") for its two halves. `transpose` moves the whole song.
KOROBEINIKI_A = "E5:2 B4:1 C5:1 D5:2 C5:1 B4:1 | A4:2 A4:1 C5:1 E5:2 D5:1 C5:1 | B4:3 C5:1 D5:2 E5:2 | C5:2 A4:2 A4:2 -:2 | " \
    "-:1 D5:2 F5:1 A5:2 G5:1 F5:1 | E5:3 C5:1 E5:2 D5:1 C5:1 | B4:2 B4:1 C5:1 D5:2 E5:2 | C5:2 A4:2 A4:2 -:2"
KOROBEINIKI_B = "E5:4 C5:4 | D5:4 B4:4 | C5:4 A4:4 | G#4:4 B4:4 | E5:4 C5:4 | D5:4 B4:4 | C5:2 E5:2 A5:4 | G#5:8"

KALINKA_REFRAIN = "G4:2 E4:1 F4:1 G4:2 E4:1 F4:1 | G4:2 F4:1 E4:1 D4:2 A4:1 A4:1 | G4:1.5 F4:.5 E4:1 F4:1 G4:2 E4:1 F4:1 | "
KALINKA_VERSE = "A4:1 C5:1 Bb4:1 A4:.5 G4:.5 F4:2 C4:2 | A4:1 C5:1 Bb4:1 A4:.5 G4:.5 F4:2 C4:2 | D4:2 D4:1 E4:1 G4:1 F4:1 E4:1 D4:1 | C4:2 C4:2 C4:2 C5:2 | " \
    "A4:1 C5:1 G4:1 A4:1 F4:2 C4:2 | A4:1 C5:1 G4:1 A4:1 F4:2 C4:2 | D4:2 D4:1 E4:1 G4:1 F4:1 E4:1 D4:1 | C5:2 Bb4:2 A4:4"

LONG_ROAD_VERSE = "D5:1 D5:1 E5:1 F5:1 G5:1 F5:1 E5:1 D5:1 | F5:1 D5:7 | A4:1 A4:1 Bb4:1 C5:1 D5:1 A4:1 Bb4:1 A4:1 | G4:8 | " \
    "D5:1 D5:1 E5:1 F5:1 G5:1 F5:1 E5:1 D5:1 | F5:1 D5:7 | E5:1 E5:1 E5:1 F5:1 E5:1 B4:1 C#5:1 D5:1 | E5:2 F5:2 F5:2 E5:2"
LONG_ROAD_REFRAIN = "E5:1.5 D5:.5 D5:3 D5:1 D5:1 C5:1 | C5:1.5 Bb4:.5 Bb4:3 G4:1 A4:1 Bb4:1 | C5:3 D5:1 E5:1.5 D5:.5 C5:1 Bb4:1 | A4:5 F4:1 G4:1 A4:1 | " \
    "C5:1.5 Bb4:.5 Bb4:3 D5:1 D5:1 Bb4:1 | A4:1.5 A4:.5 A4:3 D5:1 E5:1 F5:1 | A5:3 G5:1 F5:1 E5:1 D5:1 C#5:1 | "

TSAR = "C5:4 D5:2 D5:2 | C5:3 A4:1 F4:4 | F5:4 E5:2 D5:2 | C5:4 D5:4 | Bb4:4 C5:2 C5:2 | A4:4 A4:2 B4:2 | C5:4 B4:4 | A4:8 | " \
    "Bb4:4 A4:2 G4:2 | A4:4 A4:4 | F5:3 E5:1 D5:2 C#5:2 | D5:4 C5:4 | F5:4 E5:2 D5:2 | C5:4 C5:2 Bb4:2 | A4:4 G4:4 | F4:8"
TSAR_CHORDS = "F F Bb F/D Gm/C F/G Am/E Am C F Bb/A Dm/C F/Bb F/Gm F/C F"

GATE = "Eb5:8 | F5:8 | G5:4 Eb5:2 G5:2 | F5:4 Bb4:4 | G5:2 Bb5:2 F5:2 Eb5:2 | D5:4 Bb4:4 | G5:2 Bb5:2 F5:2 Eb5:2 | D5:4 Bb4:4"
GATE_CHORDS = "Eb Bb Eb/Cm Bb Eb Bb/Gm Eb Bb/Eb"

BOATMEN = "G4:2 E4:2 A4:4 | E4:8 | G4:2 E4:2 A4:4 | E4:8 | G4:4 C5:4 | B4:4 A4:4 | G4:2 E4:2 A4:4 | E4:8"
BOATMEN_CHORDS = "Em/Am Em Em/Am Em C B Em/Am Em"

MANCHURIA_A = "E4:6 | E4:2 C4:2 D4:2 | E4:6 | E4:6 | D4:2 E4:2 G#4:2 | C5:4 B4:2 | A4:6 | A4:6 | " \
    "E4:2 A4:2 C5:2 | G#4:4 A4:2 | B4:2 A4:2 F4:2 | B4:4 A4:2 | E4:2 A4:2 B4:2 | C5:4 B4:2 | A4:6 | A4:2 E4:1 D#4:1 E4:1 F4:1"
MANCHURIA_B = "E4:3 B3:1 B3:2 | -:2 C4:2 D4:2 | E4:6 | E4:2 G4:1 F#4:1 G4:1 A4:1 | G4:3 D4:1 D4:2 | -:2 E4:2 F4:2 | G4:6 | G4:2 G4:2 G#4:2 | " \
    "A4:3 E4:1 E4:2 | E4:1 F4:.5 E4:.5 D#4:2 E4:2 | G4:4 F4:2 | F4:2 C4:2 D4:2 | E4:2 D4:2 C4:2 | B3:4 C4:2 | A3:6 | A3:2 A4:2 G#4:2"
MANCHURIA_C = "A4:4 Bb4:2 | A4:4 G4:2 | G4:4 F4:2 | F4:2 E4:2 D4:2 | G4:4 A4:2 | G4:4 F4:2 | F4:2 E4:2 D#4:2 | E4:6 | " \
    "A3:2 C4:2 E4:2 | A4:2 C5:3 B4:1 | A4:2 G4:2 F4:2 | A4:4 F4:2 | C4:2 E4:2 D4:2 | B3:4 C4:2 | A3:6 | A3:6"

SONGS = [
    {
        "slug": "korobeiniki", "title": "Korobeiniki", "key": "Am",
        "origin": "Russian folk song (19th century)",
        "checked": "the score of the English Wikipedia article",
        "vamp": "Am E",
        "sections": [
            (KOROBEINIKI_A, "E Am E Am Dm Am E Am", PULSE),
            (KOROBEINIKI_A, "E Am E Am Dm F E Am", SAW),
            (KOROBEINIKI_B, "Am E Am E F C Dm E", WIDE),
            (KOROBEINIKI_A, "E Am E Am Dm F E Am", FULL),
        ],
    },
    {
        "slug": "kalinka", "title": "Kalinka", "key": "Dm", "transpose": 7,
        "origin": "Ivan Larionov, 1860",
        "checked": "John Chambers' ABC collection (trillian.mit.edu/~jc/music/abc/Russia/Kalinka.abc)",
        "vamp": "Dm A", "pickup": "-:6 A4:2",
        "sections": [
            (KALINKA_REFRAIN + "G4:2 F4:1 E4:1 D4:2 A4:2 | " + KALINKA_REFRAIN + "G4:2 F4:1 E4:1 D4:4", "A A/Dm A A/Dm A A/Dm A A/Dm", PULSE),
            (KALINKA_VERSE, "F F Bb/G C F F Bb/G C/A", WIDE),
            (KALINKA_REFRAIN + "G4:2 F4:1 E4:1 D4:2 A4:2 | " + KALINKA_REFRAIN + "G4:2 F4:1 E4:1 D4:4", "A A/Dm A A/Dm A A/Dm A A/Dm", FULL),
        ],
    },
    {
        "slug": "long-road", "title": "By the Long Road", "key": "Dm",
        "origin": "Boris Fomin, 1924 (Dorogoi dlinnoyu)",
        "checked": "John Chambers' ABC collection (trillian.mit.edu/~jc/music/abc/Russia/DorogoyDalnoyu.abc)",
        "vamp": "Dm A",
        "sections": [
            (LONG_ROAD_VERSE, "Dm Dm D Gm Dm Dm E A", PULSE),
            (LONG_ROAD_REFRAIN + "D5:2 F5:2 F5:2 E5:2", "Dm/D Gm C F/D Gm Dm A Dm/A", SAW),
            (LONG_ROAD_REFRAIN + "D5:8", "Dm/D Gm C F/D Gm Dm A Dm", FULL),
        ],
    },
    {
        "slug": "god-save-the-tsar", "title": "God Save the Tsar!", "key": "F",
        "origin": "Alexei Lvov, 1833",
        "checked": "the score of the English Wikipedia article and The Everyday Song Book (1927) in John Chambers' ABC collection",
        "vamp": "F C",
        "sections": [
            (TSAR, TSAR_CHORDS, dict(PULSE, long=1)),
            (TSAR, TSAR_CHORDS, GRAND),
        ],
    },
    {
        "slug": "great-gate", "title": "The Great Gate of Kiev", "key": "Eb",
        "origin": "Modest Mussorgsky, Pictures at an Exhibition, 1874",
        "checked": "the score of the English Wikipedia article (the opening eight bars)",
        "vamp": "Eb Bb",
        "sections": [
            (GATE, GATE_CHORDS, dict(PULSE, long=1)),
            (GATE, GATE_CHORDS, GRAND),
            (GATE, GATE_CHORDS, dict(GRAND, open=1)),
        ],
    },
    {
        "slug": "volga-boatmen", "title": "Song of the Volga Boatmen", "key": "Em", "transpose": 5,
        "origin": "Russian folk song, published by Mily Balakirev in 1866",
        "checked": "an ABC transcription mirrored in John Chambers' collection (musicaviva.com, the refrain)",
        "vamp": "Em B",
        "sections": [
            (BOATMEN, BOATMEN_CHORDS, dict(PULSE, long=1)),
            (BOATMEN, BOATMEN_CHORDS, GRAND),
            (BOATMEN, BOATMEN_CHORDS, dict(GRAND, open=1)),
        ],
    },
    {
        "slug": "manchuria", "title": "On the Hills of Manchuria", "key": "Am", "transpose": 12, "beats": 3,
        "origin": "Ilya Shatrov, 1906",
        "checked": "John Chambers' ABC collection (trillian.mit.edu/~jc/music/abc/Russia/ManchurianHills.abc)",
        "vamp": "Am Am E E", "pickup": "-:2 A3:1 B3:1 C4:1 D4:1",
        "sections": [
            (MANCHURIA_A, "Am Am E E E E Am Am Am Am Dm Dm Am E Am Am", PULSE),
            (MANCHURIA_B, "E E Am Am G G C C Am Am Dm Dm Am E Am Am", SAW),
            (MANCHURIA_C, "A A Dm Dm G G C E Am Am Dm Dm Am E Am Am", FULL),
        ],
    },
]

STEPS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
MINOR = (0, 2, 3, 5, 7, 8, 10, 11)  # natural minor plus the leading tone
MAJOR = (0, 2, 4, 5, 7, 9, 11)
# The pads' gate: which sixteenths of a bar let them through.
GATES = {16: [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1], 12: [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1]}


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


def pitch_class(name: str) -> int:
    return (STEPS[name[0]] + name.count("#") - name[1:].count("b")) % 12


def note(name: str) -> int:
    """MIDI number of "E5", "G#4", "Bb3"."""
    match = re.fullmatch(r"([A-G][#b]?)(\d)", name)
    if match is None:
        raise ValueError("not a note: " + name)
    return pitch_class(match.group(1)) + 12 * (int(match.group(2)) + 1)


def chord(name: str, shift: int) -> tuple[int, tuple[int, ...]]:
    """(bass root, chord tones) of "Am", "E", "Bb": the root in the octave
    from C2, the triad in the octave from G3."""
    minor = name.endswith("m")
    root = (pitch_class(name[:-1] if minor else name) + shift) % 12
    tones = sorted(55 + (root + step - 55) % 12 for step in (0, 3 if minor else 4, 7))
    return 36 + root, tuple(tones)


def near(pitch_cls: int, target: int) -> int:
    """The note of that pitch class closest to `target`."""
    return target + (pitch_cls - target + 6) % 12 - 6


def parse_song(song: dict) -> dict:
    """The song as the renderer wants it: sections of (melody bars, chords per
    bar, parts), the vamp first; a chord entry is a list of (first sixteenth,
    sixteenths, chord)."""
    shift = int(song.get("transpose", 0))
    beats = int(song.get("beats", 4))
    spb = beats * 4

    def chords(text: str) -> list:
        bars = []
        for name in text.split():
            parts = name.split("/")
            if len(parts) == 1:
                bars.append([(0, spb, chord(parts[0], shift))])
            else:
                bars.append([(0, spb // 2, chord(parts[0], shift)), (spb // 2, spb // 2, chord(parts[1], shift))])
        return bars

    def melody(text: str) -> list:
        bars = []
        for index, bar in enumerate(text.split("|")):
            notes = []
            for token in bar.split():
                name, length = token.split(":")
                notes.append((None if name == "-" else note(name) + shift, float(length)))
            if abs(sum(length for _, length in notes) - beats * 2) > 1e-9:
                raise ValueError("%s: bar %d holds %g eighths, not %d" % (song["slug"], index + 1, sum(length for _, length in notes), beats * 2))
            bars.append(notes)
        return bars

    vamp = chords(song["vamp"])
    lead_in = [[] for _ in vamp]
    if song.get("pickup"):
        lead_in[-1] = melody(song["pickup"])[0]
    sections = [(lead_in, vamp, VAMP)]
    for tune, harmony, parts in song["sections"]:
        section = (melody(tune), chords(harmony), parts)
        if len(section[0]) != len(section[1]):
            raise ValueError("%s: %d bars of melody over %d chords" % (song["slug"], len(section[0]), len(section[1])))
        sections.append(section)
    tonic = (pitch_class(song["key"].rstrip("m")) + shift) % 12
    scale = {(tonic + step) % 12 for step in (MINOR if song["key"].endswith("m") else MAJOR)}
    return {"sections": sections, "beats": beats, "spb": spb, "tonic": tonic, "scale": scale,
            "bars": sum(len(section[1]) for section in sections)}


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


def harmony_under(midi: int, scale: set) -> int:
    """The scale tone a third (or fourth) under a melody note."""
    for step in (3, 4, 5):
        if (midi - step) % 12 in scale:
            return midi - step
    return midi - 12


def render(song: dict, bpm: float, heat: float) -> np.ndarray:
    """One track of a song: its bars and then the tail that rings out.

    `heat` (0 calm .. 1 danger) hardens the arrangement step by step."""
    global S16, SPB, BAR, rng
    rng = np.random.default_rng(1986)
    plan = parse_song(song)
    S16 = int(round(SR * 60.0 / bpm / 4.0))
    SPB = plan["spb"]
    BAR = S16 * SPB
    waltz = SPB == 12
    bars = plan["bars"]
    n = bars * BAR + TAIL
    drums, bass, pad, music = Bus(n), Bus(n), Bus(n), Bus(n)
    kick_times: list[int] = []
    k, s, hc, ho = kick(), snare(), hat(False), hat(True)
    alarm = (near((plan["tonic"] + 7) % 12, 88), near((plan["tonic"] + 2) % 12, 83))

    bar_index = 0
    for melody, chords, parts in plan["sections"]:
        length = len(chords)
        for local in range(length):
            start = (bar_index + local) * BAR
            last = local == length - 1
            # The half-time strain goes four-on-the-floor in the hot tracks.
            half = parts.get("drums") == "half" and heat < 0.6
            full = parts.get("drums") == 1 or (parts.get("drums") == "half" and not half)

            for first, steps, (root, tones) in chords[local]:
                # Bass: sixteenths on the root, every fourth one an octave up.
                if half:
                    for step in range(first, first + steps, 2):
                        bass.add(start + step * S16, bass_note(root + (12 if step % 8 == 6 else 0), S16 * 2 - 200), 0.3)
                else:
                    for step in range(first, first + steps):
                        accent = 1.0 if step % 4 == 0 else 0.8
                        bass.add(start + step * S16, bass_note(root + (12 if step % 4 == 3 else 0), S16 - 300), 0.3 * accent)

                # Pad: the chord (gated later, on the bus).
                left, right = pad_chord(tones, steps * S16)
                pad.add(start + first * S16, left, 0.3, -1.0, 0.45)
                pad.add(start + first * S16, right, 0.3, 1.0, 0.45)

                # Arpeggio: chord tones in sixteenths, up and back over two octaves.
                if parts.get("arp"):
                    ladder = [tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[0] + 24, tones[1] + 24, tones[0] + 24, tones[2] + 12, tones[1] + 12]
                    # Its filter opens over the section and closes again.
                    where = (local + 0.5) / length
                    bright = 1400.0 + 3600.0 * np.sin(np.pi * where) ** 2 * float(parts["arp"])
                    for step in range(first, first + steps):
                        plucked = lowpass(pluck(ladder[step % 8], S16), bright)
                        music.add(start + step * S16, plucked, 0.2 * (0.6 + 0.4 * float(parts["arp"])), -0.6 if step % 2 == 0 else 0.6, 0.35)

            # Drums: four on the floor, or one-two-three in a waltz.
            if full:
                for step in ((0,) if waltz else (0, 4, 8, 12)):
                    kick_times.append(start + step * S16)
                    drums.add(start + step * S16, k, 0.66)
                if heat >= 0.4:
                    drums.add(start + (SPB - 1) * S16, k, 0.4 * heat)
                for step, level in (((4, 0.5), (8, 0.7)) if waltz else ((4, 0.75), (12, 0.75))):
                    drums.add(start + step * S16, s, level, 0.0, 0.25)
                if heat >= 0.4:
                    drums.add(start + (SPB - 5) * S16, s, 0.3 * heat, 0.2, 0.2)
            if half:
                for at, level in ((0, 0.66), (8, 0.66), (10, 0.45)):
                    kick_times.append(start + at * S16)
                    drums.add(start + at * S16, k, level)
                drums.add(start + 8 * S16, s, 0.8, 0.0, 0.35)
            if full or half:
                for step in range(SPB):
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
                    for step in (7, SPB - 1):
                        drums.add(start + step * S16, hc, 0.15, -0.3)
            # Into the next section: snare roll, falling toms, a noise swell.
            if last and parts.get("fill"):
                for i, step in enumerate(range(SPB - 8, SPB - 4)):
                    drums.add(start + step * S16, s, 0.25 + 0.07 * i, 0.0, 0.2)
                low = 40 + (plan["tonic"] - 40) % 12
                for i, fall in enumerate((12, 9, 5, 0)):
                    drums.add(start + (SPB - 4 + i) * S16, tom(low + fall), 0.6, -0.5 + 0.33 * i, 0.3)
                music.add(start, riser(BAR), 0.09, 0.0, 0.3)

            # As it gets hot an alarm answers on the off-beats, louder each step.
            if heat > 0.2:
                for step in range(2, SPB, 4):
                    music.add(start + step * S16, lowpass(pluck(alarm[0] if step % 8 == 2 else alarm[1], S16), 5000.0), 0.13 * (heat - 0.2) / 0.8, 0.0, 0.4)

            # Lead: the tune, with a harmony voice under it in the later sections.
            voice = "saw" if heat >= 0.6 else parts.get("lead", "pulse")
            under = 1.0 if parts.get("harmony") else heat
            below = 1.0 if parts.get("long") else heat
            at = start
            for midi, eighths in melody[local]:
                count = int(round(eighths * 2)) * S16
                if midi is not None:
                    gap = 500 if eighths <= 2 else 1500
                    music.add(at, lead_note(midi, count - gap, voice), 0.44 if voice == "pulse" else 0.42, 0.0, 0.35)
                    if under > 0.0:
                        music.add(at, lead_note(harmony_under(midi, plan["scale"]), count - gap, "saw"), 0.14 * under, 0.35, 0.3)
                    if below > 0.0:
                        music.add(at, lead_note(midi - 12, count - gap, "saw"), 0.12 * below, -0.35, 0.3)
                at += count
        bar_index += length

    t_bar = np.arange(n) / BAR                  # time in bars
    beat_phase = (t_bar * plan["beats"]) % 1.0  # position inside the beat

    # The bass filter breathes: shut on the beat, wide open on the off-beat,
    # and the whole motion rises and falls over four bars.
    breath = 0.5 - 0.5 * np.cos(2 * np.pi * beat_phase)
    tide = 0.55 + 0.45 * np.sin(2 * np.pi * t_bar / 4.0 - np.pi / 2)
    bass_position = np.clip(0.12 + breath * (0.45 + 0.4 * tide), 0.0, 1.0)
    for channel in range(2):
        bass.dry[channel] = sweep(bass.dry[channel], bass_position, (180.0, 500.0, 1400.0, 3800.0))
    bass.dry = np.tanh(bass.dry * 1.4) * 0.8

    # The pads are chopped by a sixteenth-note gate and swept over two bars.
    step_index = np.minimum((t_bar * SPB).astype(int) % SPB, SPB - 1)
    gate = np.array(GATES[SPB], dtype=float)[step_index]
    smooth = int(0.006 * SR)
    gate = np.convolve(gate, np.ones(smooth) / smooth, mode="same")
    pad_gain = 0.22 + 0.78 * gate
    pad_position = 0.35 + 0.4 * (0.5 - 0.5 * np.cos(2 * np.pi * t_bar / 2.0)) + 0.15 * heat
    for channel in range(2):
        pad.dry[channel] = sweep(pad.dry[channel], pad_position, (500.0, 1300.0, 3200.0, 7000.0)) * pad_gain
        pad.send[channel] *= pad_gain

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

    mix = drums.dry + bass.dry + pad.dry + music.dry + wet * 0.5
    mix = highpass(mix, 28.0)
    mix = np.tanh(mix * 1.2)
    # What is left of the ringing after three seconds is faded away.
    fade = int(0.5 * SR)
    mix[:, n - fade:] *= np.linspace(1.0, 0.0, fade)
    return mix / np.max(np.abs(mix[:, : bars * BAR])) * 0.89


def write(audio: np.ndarray, name: str) -> None:
    pcm = (np.clip(audio, -1.0, 1.0).T * 32767.0).astype("<i2")
    BGM_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "track.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(SR)
            wav.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "3", str(BGM_DIR / name)], check=True)


def file_name(song: dict, bpm: float) -> str:
    return "%s-%d.ogg" % (song["slug"], int(bpm))


def render_track(job: tuple[int, int]) -> dict:
    """Renders and writes one track (run in a worker process)."""
    song = SONGS[job[0]]
    bpm, heat = LADDER[job[1]]
    audio = render(song, bpm, heat)
    write(audio, file_name(song, bpm))
    body = audio[:, : audio.shape[1] - TAIL]
    return {"song": job[0], "rung": job[1], "bpm": SR * 15.0 / S16, "seconds": audio.shape[1] / SR,
            "level": 20.0 * np.log10(np.sqrt(np.mean(body ** 2)))}


def playlist_entry(song: dict, tracks: list[dict]) -> str:
    """The song's line of the pack's playlist; its volume evens out how loud
    the calm tracks of the songs are."""
    plan = parse_song(song)
    entry = {
        "title": song["title"], "beats": plan["beats"], "bars": plan["bars"],
        "volume_db": round(VOLUME_DB + LEVEL_DB - tracks[0]["level"], 1),
        "tracks": [{"file": "res://assets/audio/bgm/" + file_name(song, LADDER[track["rung"]][0]), "bpm": round(track["bpm"], 4)} for track in tracks],
    }
    return json.dumps(entry, ensure_ascii=False)


def write_playlist(lines: dict[str, str]) -> None:
    """Rewrites the "playlist" of the default pack in place, keeping the lines
    of songs that were not rendered this time."""
    text = PACK.read_text(encoding="utf-8")
    block = re.search(r'\t"playlist": \[\n(.*?)\n\t\]', text, re.S)
    if block is None:
        raise SystemExit('packs/default/pack.json has no "playlist" block to rewrite')
    for old in block.group(1).split("\n"):
        title = json.loads(old.strip().rstrip(","))["title"] if old.strip() else ""
        for song in SONGS:
            if song["title"] == title and song["slug"] not in lines:
                lines[song["slug"]] = old.strip().rstrip(",")
    body = ",\n".join("\t\t" + lines[song["slug"]] for song in SONGS if song["slug"] in lines)
    PACK.write_text(text[: block.start()] + '\t"playlist": [\n' + body + "\n\t]" + text[block.end():], encoding="utf-8", newline="\n")


def write_records() -> None:
    """Binds every file of the BGM folder in assets/assets-measurements.json
    and lists the tracks in assets/assets-provenance.json."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import check_audio_assets as check

    path = ROOT / "assets" / "assets-measurements.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    prefix = "res://assets/audio/bgm/"
    kept = [entry for entry in data["files"] if not entry["path"].startswith(prefix)]
    made = []
    for file in sorted(BGM_DIR.iterdir()):
        entry = {"path": prefix + file.name, "sha256": check.sha256_file(file)}
        if file.suffix == ".ogg":
            measured = check.measure(file)
        else:
            measured = {"onset_ms": 1.0e9, "half_amplitude_ms": 1.0e9, "duration_s": 0.0, "head_rms_db": -100.0, "tail_rms_db": -100.0, "boundary_step_db": -120.0}
        for key in ("onset_ms", "half_amplitude_ms", "duration_s", "head_rms_db", "tail_rms_db", "boundary_step_db"):
            entry[key] = measured[key]
        made.append(entry)
    data["files"] = made + kept
    path.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")

    path = ROOT / "assets" / "assets-provenance.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    for record in data["families"]:
        if record.get("dest") != "res://assets/audio/bgm":
            continue
        record["source"] = "tools/make_bgm.py (rendered locally, no download)"
        record["license"] = "original arrangement and synthesis made for this project; the underlying melodies are in the public domain: " \
            + "; ".join("%s (%s)" % (song["title"], song["origin"]) for song in SONGS)
        record["modifications"] = [
            {"file": prefix + file_name(song, bpm),
             "note": "%s, 1980s-synth arrangement at %d BPM (rung %d of the six-track ladder from calm to danger): the song once through and three seconds of ringing; notes checked against %s" % (song["title"], int(bpm), rung, song["checked"])}
            for song in SONGS for rung, (bpm, _) in enumerate(LADDER)
        ]
    path.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print("records written for %d files" % len(made))


def main() -> int:
    arguments = sys.argv[1:]
    if arguments == ["--records"]:
        write_records()
        return 0
    wanted = [index for index, song in enumerate(SONGS) if not arguments or song["slug"] in arguments]
    if not wanted:
        raise SystemExit("no such song; known: " + ", ".join(song["slug"] for song in SONGS))
    for index in wanted:
        parse_song(SONGS[index])
    jobs = [(index, rung) for index in wanted for rung in range(len(LADDER))]
    with multiprocessing.Pool(min(6, multiprocessing.cpu_count())) as pool:
        done = pool.map(render_track, jobs, chunksize=1)
    lines = {}
    for index in wanted:
        tracks = sorted((track for track in done if track["song"] == index), key=lambda track: track["rung"])
        lines[SONGS[index]["slug"]] = playlist_entry(SONGS[index], tracks)
        for track in tracks:
            print("%s: %.3f s, %.4f BPM, mean %.1f dB" % (file_name(SONGS[index], LADDER[track["rung"]][0]), track["seconds"], track["bpm"], track["level"]))
    write_playlist(lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
