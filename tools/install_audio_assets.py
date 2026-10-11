#!/usr/bin/env python3
"""Installer for the pinned audio assets of the modern-tetris audio slice.

Frozen CLI (binding record section 3):

    python tools/install_audio_assets.py \
        [--manifest assets/assets-manifest.json] \
        [--dest-root <project-root>] \
        [--records-root <project-root>] \
        [--cache-dir <temp-dir>] \
        [--offline]

Pipeline: pinned HTTPS download -> per-file SHA-256 verification (fail closed
on mismatch) -> safe temp unpack (traversal/symlink/absolute-path archive
members rejected) -> ffmpeg/ffprobe re-measurement of candidates -> threshold
selection (>= 3 seamless BGM loops, 2 crisp replacement SFX) -> staged
additions-only install into assets/audio/bgm/ and assets/audio/digital/ ->
per-file .import settings written for the BGM tiers (loop=true) followed by
one headless editor import pass with the pinned Godot executable so load()
returns AudioStreamOggVorbis with loop == true (replacement SFX stay
non-looping) -> license files plus manifest/provenance/measurement records
written under --records-root/assets/.

Fail-closed contract: any hash mismatch, unsafe archive member, threshold
shortfall, pre-existing same-name destination file with different content, or
failed import verification exits non-zero with the destination and records
trees byte-identical to the pre-run state (stage then commit; additions made
before a failed import pass are removed again). Re-run is idempotent: the
cache is reused when hashes match, identical bytes are skipped, and records
are rewritten identically (no timestamps in any record). The default cache
directory lives under the system temp directory and files are discovered by
their content SHA-256, so an offline cache can be re-seeded by placing any
file whose SHA-256 matches a pinned archive into the cache directory.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

DEFAULT_MANIFEST = "assets/assets-manifest.json"
BGM_DIR_REL = "assets/audio/bgm"
DIGITAL_DIR_REL = "assets/audio/digital"
INTERFACE_DIR_REL = "assets/audio/interface"

PROJECT_GODOT_NAME = "project.godot"
DEFAULT_GODOT = r"E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
EDITOR_PASS_TIMEOUT_S = 900

# The six Phase 0 consumed pinned archives (evidence/phase-0-audio.md).
# The two probe-only URLs (deadly_contracts, Loop Box #4) are deliberately
# excluded per controller decision 1 recorded in the test manifest.
PINNED_SOURCES = [
    {
        "name": "shadow_operations-loop1.ogg (Magory Music Pack for Fast Paced Games)",
        "url": "https://opengameart.org/sites/default/files/shadow_operations-loop1.ogg",
        "sha256": "ebb851285015e9454a23d3d1ce814642f56a5a37e48c8a6425a88b20c0cc6d95",
        "kind": "bgm-loop",
    },
    {
        "name": "the_price_of_freedom-loop1.ogg (Magory Music Pack for Fast Paced Games)",
        "url": "https://opengameart.org/sites/default/files/the_price_of_freedom-loop1.ogg",
        "sha256": "906e61d2e0d75268c27eb5b8db088fd9b33c897725368564e2ef3c4e8d67fa07",
        "kind": "bgm-loop",
    },
    {
        "name": "hostile_territory-loop1.ogg (Magory Music Pack for Fast Paced Games)",
        "url": "https://opengameart.org/sites/default/files/hostile_territory-loop1.ogg",
        "sha256": "835fe07e18c44b70e00a8e1b350aecd3f512eba8617caacaa6ffb69115fd74a6",
        "kind": "bgm-loop",
    },
    {
        "name": "going_undercover-loop1.ogg (Magory Music Pack for Fast Paced Games)",
        "url": "https://opengameart.org/sites/default/files/going_undercover-loop1.ogg",
        "sha256": "07b33265c6ed89adbc5098424c348e9e415089ad0e9dd96e9a3dfb1d7e7cd893",
        "kind": "bgm-loop",
    },
    {
        "name": "kenney_digital-audio.zip (digital-audio)",
        "url": "https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip",
        "sha256": "24e6ce28b76a6d8c89cff4d331e0965ff5c3de8a73c612028e9d363cc64e4f06",
        "kind": "sfx-archive",
    },
    {
        "name": "kenney_interface-sounds.zip (interface-sounds)",
        "url": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
        "sha256": "f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232",
        "kind": "sfx-archive",
    },
]
PINNED_BY_URL = {entry["url"]: entry for entry in PINNED_SOURCES}

# Deterministic crisp replacement picks for the tetris/resume remap
# (Kenney Interface Sounds, CC0). Re-measured at install time; a missing or
# non-crisp pick aborts fail-closed instead of substituting a source.
SFX_SELECTION = ["maximize_009.ogg", "confirmation_003.ogg"]

# The nine pre-existing mapped SFX paths (tetris/resume are remapped onto the
# two new digital replacements by the integration step). The measurement
# record must cover all eleven so the suites stay hash-bound.
PREEXISTING_MAPPED_SFX = [
    "res://assets/audio/interface/tick_002.ogg",
    "res://assets/audio/interface/switch_004.ogg",
    "res://assets/audio/interface/toggle_003.ogg",
    "res://assets/audio/interface/drop_003.ogg",
    "res://assets/audio/interface/drop_001.ogg",
    "res://assets/audio/interface/glass_004.ogg",
    "res://assets/audio/interface/confirmation_002.ogg",
    "res://assets/audio/interface/error_004.ogg",
    "res://assets/audio/interface/minimize_002.ogg",
]

BGM_MIN_DURATION_S = 20.0
MAX_ONSET_MS = 30.0
MAX_HALF_AMPLITUDE_MS = 30.0
MAX_HEAD_TAIL_DELTA_DB = 12.0
MAX_BOUNDARY_STEP_DBFS = -35.0
MIN_BGM_PASS = 3

CACHE_MIN_BYTES = 100 * 1024
CACHE_MAX_BYTES = 80 * 1024 * 1024

BGM_LICENSE_NAME = "LICENSE-bgm-magory-fast-paced.txt"
DIGITAL_LICENSE_NAME = "LICENSE-digital-kenney.txt"

BGM_FAMILY_SOURCE = "https://opengameart.org/sites/default/files/shadow_operations-loop1.ogg"
DIGITAL_FAMILY_SOURCE = (
    "https://kenney.nl/media/pages/assets/interface-sounds/"
    "fa43c1dd4d-1677589452/kenney_interface-sounds.zip"
)

HTTP_TIMEOUT_S = 120


class InstallError(Exception):
    """Fail-closed abort: nothing has been committed, or the additions made
    before the failure were removed again."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# Measurement: identical definitions to the frozen V-01 byte-level authority
# (tools/check_audio_assets.py) so records bind exactly to the installed
# bytes: onset at -60 dBFS, half-amplitude at 0.5 * peak, 10 ms head/tail RMS
# with a -100 dBFS floor, loop-boundary sample step with a -120 dBFS floor.
# ---------------------------------------------------------------------------

def ffprobe_stream(path: Path) -> dict:
    cmd = ["ffprobe", "-v", "error", "-select_streams", "a:0",
           "-show_entries", "stream=sample_rate,channels:format=duration",
           "-of", "json", str(path)]
    proc = subprocess.run(cmd, capture_output=True, timeout=120)
    if proc.returncode != 0:
        raise InstallError("ffprobe failed on %s: %s"
                           % (path.name, (proc.stderr or b"").decode("utf-8", "replace").strip()[:300]))
    try:
        data = json.loads((proc.stdout or b"").decode("utf-8", "replace") or "{}")
    except ValueError as exc:
        raise InstallError("ffprobe produced unparseable output for %s: %s" % (path.name, exc))
    streams = data.get("streams") or []
    if not streams:
        raise InstallError("ffprobe found no audio stream in %s" % path.name)
    return dict(streams[0])


def decode_f32(path: Path) -> array.array:
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
           "-f", "f32le", "-acodec", "pcm_f32le", "-"]
    proc = subprocess.run(cmd, capture_output=True, timeout=600)
    if proc.returncode != 0:
        raise InstallError("ffmpeg decode failed on %s: %s"
                           % (path.name, (proc.stderr or b"").decode("utf-8", "replace").strip()[:300]))
    samples = array.array("f")
    samples.frombytes(proc.stdout)
    return samples


def measure(path: Path) -> dict:
    info = ffprobe_stream(path)
    sample_rate = int(info.get("sample_rate") or 0)
    channels = max(1, int(info.get("channels") or 1))
    if sample_rate <= 0:
        raise InstallError("ffprobe reported no sample rate for %s" % path.name)
    samples = decode_f32(path)
    frames = len(samples) // channels
    if frames <= 0:
        raise InstallError("decode produced no frames for %s" % path.name)
    if channels == 1:
        mono = samples
    else:
        mono = array.array("f", bytes(4 * frames))
        for i in range(frames):
            base = i * channels
            acc = 0.0
            for c in range(channels):
                acc += samples[base + c]
            mono[i] = acc / channels
    peak = 0.0
    for value in mono:
        magnitude = abs(value)
        if magnitude > peak:
            peak = magnitude
    onset_threshold = 10.0 ** (-60.0 / 20.0)
    half_threshold = 0.5 * peak
    onset_index = None
    half_index = None
    for i in range(frames):
        magnitude = abs(mono[i])
        if onset_index is None and magnitude >= onset_threshold:
            onset_index = i
        if half_index is None and peak > 0.0 and magnitude >= half_threshold:
            half_index = i
        if onset_index is not None and half_index is not None:
            break

    def rms_db(start: int, end: int) -> float:
        count = max(1, end - start)
        acc = 0.0
        for i in range(start, end):
            value = mono[i]
            acc += value * value
        rms = math.sqrt(acc / count)
        if rms <= 0.0:
            return -100.0
        return max(-100.0, 20.0 * math.log10(rms))

    edge_n = min(frames, max(1, sample_rate // 100))
    head_rms_db = rms_db(0, edge_n)
    tail_rms_db = rms_db(frames - edge_n, frames)
    step = abs(float(mono[frames - 1]) - float(mono[0]))
    boundary_step_db = -120.0 if step <= 0.0 else max(-120.0, 20.0 * math.log10(step))
    ms_per_frame = 1000.0 / float(sample_rate)
    return {
        "duration_s": frames / float(sample_rate),
        "onset_ms": 1.0e9 if onset_index is None else onset_index * ms_per_frame,
        "half_amplitude_ms": 1.0e9 if half_index is None else half_index * ms_per_frame,
        "head_rms_db": head_rms_db,
        "tail_rms_db": tail_rms_db,
        "boundary_step_db": boundary_step_db,
    }


def bgm_passes(m: dict) -> bool:
    return (m["duration_s"] >= BGM_MIN_DURATION_S
            and m["onset_ms"] <= MAX_ONSET_MS
            and abs(m["head_rms_db"] - m["tail_rms_db"]) <= MAX_HEAD_TAIL_DELTA_DB
            and m["boundary_step_db"] <= MAX_BOUNDARY_STEP_DBFS)


def sfx_passes(m: dict) -> bool:
    return m["onset_ms"] <= MAX_ONSET_MS and m["half_amplitude_ms"] <= MAX_HALF_AMPLITUDE_MS


# ---------------------------------------------------------------------------
# Cache: content-addressed by SHA-256 so an offline cache can be re-seeded by
# dropping any file whose hash matches a pinned archive into the cache dir.
# ---------------------------------------------------------------------------

def find_in_cache(cache_dir: Path, digest: str) -> Path | None:
    if not cache_dir.is_dir():
        return None
    budget = 15000
    for dirpath, dirnames, filenames in os.walk(cache_dir):
        depth = len(Path(dirpath).parts) - len(cache_dir.parts)
        if depth >= 4:
            dirnames[:] = []
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            budget -= 1
            if budget <= 0:
                return None
            candidate = Path(dirpath) / name
            try:
                size = candidate.stat().st_size
            except OSError:
                continue
            if size < CACHE_MIN_BYTES or size > CACHE_MAX_BYTES:
                continue
            try:
                actual = sha256_file(candidate)
            except OSError:
                continue
            if actual == digest:
                return candidate
    return None


def download_to_cache(url: str, digest: str, cache_dir: Path) -> Path:
    target = cache_dir / url.rsplit("/", 1)[-1]
    part = target.with_name(target.name + ".part")
    print("DOWNLOAD %s" % url)
    request = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) install_audio_assets/1.0",
    })
    hasher = hashlib.sha256()
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_S) as response:
            with open(part, "wb") as handle:
                while True:
                    chunk = response.read(1024 * 256)
                    if not chunk:
                        break
                    hasher.update(chunk)
                    handle.write(chunk)
    except Exception as exc:
        part.unlink(missing_ok=True)
        raise InstallError("download failed for %s: %s" % (url, exc))
    actual = hasher.hexdigest()
    if actual != digest:
        part.unlink(missing_ok=True)
        raise InstallError("SHA-256 mismatch for %s: expected %s, got %s"
                           % (url, digest, actual))
    if target.exists() and sha256_file(target) != digest:
        part.unlink(missing_ok=True)
        raise InstallError("cache name collision with different content: %s" % target)
    part.replace(target)
    return target


# ---------------------------------------------------------------------------
# Safe archive handling
# ---------------------------------------------------------------------------

def validate_zip_members(zf: zipfile.ZipFile, url: str) -> None:
    for info in zf.infolist():
        name = info.filename
        normalized = name.replace("\\", "/")
        parts = [p for p in normalized.split("/")]
        if normalized.startswith("/"):
            raise InstallError("archive member is an absolute path: %r in %s" % (name, url))
        if re.match(r"^[A-Za-z]:", normalized):
            raise InstallError("archive member carries a drive letter: %r in %s" % (name, url))
        for part in parts:
            if part == "..":
                raise InstallError("archive member escapes the unpack root: %r in %s" % (name, url))
        mode = (info.external_attr >> 16) & 0o170000
        if mode == 0o120000:
            raise InstallError("archive member is a symlink: %r in %s" % (name, url))


def safe_extract(zf: zipfile.ZipFile, root: Path) -> list[Path]:
    extracted = []
    resolved_root = root.resolve()
    for info in zf.infolist():
        if info.is_dir():
            continue
        normalized = info.filename.replace("\\", "/")
        target = (root / normalized).resolve()
        if target != resolved_root and resolved_root not in target.parents:
            raise InstallError("archive member resolved outside the unpack root: %r" % info.filename)
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info) as source, open(target, "wb") as handle:
            shutil.copyfileobj(source, handle)
        extracted.append(target)
    return extracted


# ---------------------------------------------------------------------------
# Godot import sidecars
# ---------------------------------------------------------------------------

def import_body(res_path: str, loop: bool) -> str:
    return (
        "[remap]\n"
        "\n"
        'importer="oggvorbisstr"\n'
        'type="AudioStreamOggVorbis"\n'
        "\n"
        "[deps]\n"
        "\n"
        'source_file="%s"\n'
        "dest_files=[]\n"
        "\n"
        "[params]\n"
        "\n"
        "loop=%s\n"
        "loop_offset=0.0\n"
        "bpm=0.0\n"
        "beat_count=0\n"
        "bar_beats=4\n"
    ) % (res_path, "true" if loop else "false")


def import_loop_flag(path: Path) -> str | None:
    """Return the loop= value from the [params] section, or None."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    if "[params]" not in text:
        return None
    params = text.split("[params]", 1)[1]
    for line in params.splitlines():
        stripped = line.strip()
        if stripped.startswith("loop="):
            return stripped[len("loop="):].strip()
    return None


def resolve_godot() -> Path:
    exe = os.environ.get("GODOT_BIN", DEFAULT_GODOT)
    path = Path(exe)
    if not path.is_file():
        raise InstallError("pinned Godot executable not found: %s "
                           "(set GODOT_BIN to override)" % exe)
    return path


# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------

def write_json(path: Path, data) -> None:
    text = json.dumps(data, indent="\t", ensure_ascii=True) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    tmp.replace(path)


def measurement_entry(res_path: str, digest: str, m: dict) -> dict:
    return {
        "path": res_path,
        "sha256": digest,
        "onset_ms": m["onset_ms"],
        "half_amplitude_ms": m["half_amplitude_ms"],
        "duration_s": m["duration_s"],
        "head_rms_db": m["head_rms_db"],
        "tail_rms_db": m["tail_rms_db"],
        "boundary_step_db": m["boundary_step_db"],
    }


def import_entry(res_path: str, import_path: Path) -> dict:
    # .import sidecars are Godot import metadata, not audio: measurement
    # fields carry the checker's own "nothing measurable" sentinels while the
    # sha256 binds the record to the post-import-pass sidecar bytes.
    return {
        "path": res_path,
        "sha256": sha256_file(import_path),
        "onset_ms": 1.0e9,
        "half_amplitude_ms": 1.0e9,
        "duration_s": 0.0,
        "head_rms_db": -100.0,
        "tail_rms_db": -100.0,
        "boundary_step_db": -120.0,
    }


def license_text_bgm(selected: list[dict]) -> str:
    lines = [
        "BGM loops installed by tools/install_audio_assets.py",
        "=====================================================",
        "",
        "Work:     Music Pack for Fast Paced Games (free loop tracks)",
        "Composer: Tomasz Kucza, published by Magory",
        "Source:   OpenGameArt.org (official file mirror)",
        "License:  Creative Commons Attribution 4.0 International (CC-BY 4.0)",
        "          https://creativecommons.org/licenses/by/4.0/",
        "",
        "Attribution required: \"Music Pack for Fast Paced Games\" by Tomasz",
        "Kucza (Magory), licensed under CC-BY 4.0.",
        "",
        "Pinned sources (each verified against its SHA-256 at install time):",
    ]
    for entry in selected:
        lines.append("- %s" % entry["url"])
        lines.append("  sha256 %s" % entry["sha256"])
    lines += [
        "",
        "Modifications: the loop files were copied verbatim into",
        "assets/audio/bgm/ without content changes. Per-file Godot import",
        "metadata (*.ogg.import) was added beside them so the engine imports",
        "the loops with loop=true; the audio bytes themselves are unmodified.",
        "",
    ]
    return "\n".join(lines)


def license_text_digital(selected: list[dict]) -> str:
    lines = [
        "Replacement SFX installed by tools/install_audio_assets.py",
        "===========================================================",
        "",
        "Work:     Kenney Interface Sounds (selected crisp replacements)",
        "Author:   Kenney (https://kenney.nl)",
        "License:  Creative Commons Zero (CC0); see License.txt inside the",
        "          pinned archive. Attribution is not required; this notice is",
        "          kept as a courtesy record.",
        "",
        "Pinned source (verified against its SHA-256 at install time):",
    ]
    for entry in selected:
        lines.append("- %s" % entry["url"])
        lines.append("  sha256 %s" % entry["sha256"])
    lines += [
        "",
        "Modifications: the sound files were copied verbatim into",
        "assets/audio/digital/ without content changes. Per-file Godot",
        "import metadata (*.ogg.import) was added beside them (non-looping);",
        "the audio bytes themselves are unmodified.",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run(args) -> int:
    manifest_path = Path(args.manifest).resolve()
    dest_root = Path(args.dest_root).resolve()
    records_root = Path(args.records_root).resolve()
    if args.cache_dir:
        cache_dir = Path(args.cache_dir).resolve()
    else:
        cache_dir = Path(tempfile.gettempdir()) / "audio-install-cache"

    if not manifest_path.is_file():
        raise InstallError("manifest not found: %s" % manifest_path)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise InstallError("manifest unparseable: %s" % exc)
    sources = manifest.get("sources")
    if not isinstance(sources, list):
        raise InstallError("manifest has no sources[] list")

    # Staged manifest: existing entries preserved, missing pinned entries
    # appended in pinned order. Nothing is written before the commit phase.
    staged_sources = [dict(entry) for entry in sources if isinstance(entry, dict)]
    existing_urls = {str(entry.get("url")) for entry in staged_sources}
    for pinned in PINNED_SOURCES:
        if pinned["url"] not in existing_urls:
            staged_sources.append({"name": pinned["name"], "url": pinned["url"],
                                   "sha256": pinned["sha256"]})

    cache_dir.mkdir(parents=True, exist_ok=True)
    bgm_candidates = []
    sfx_members = {}
    unpack_dirs = []
    verified = []

    try:
        # 1. Acquire + verify every pinned archive named by the manifest.
        for src in staged_sources:
            url = str(src.get("url", ""))
            pinned = PINNED_BY_URL.get(url)
            if pinned is None:
                continue
            digest = str(src.get("sha256", "")).strip().lower()
            if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
                raise InstallError("manifest source has an invalid sha256 for %s: %r" % (url, src.get("sha256")))
            local = find_in_cache(cache_dir, digest)
            if local is None and not args.offline:
                local = download_to_cache(url, digest, cache_dir)
            if local is None:
                raise InstallError(
                    "pinned archive not in cache (sha256=%s) and --offline forbids download: %s"
                    % (digest, url))
            if sha256_file(local) != digest:
                raise InstallError("SHA-256 mismatch for cached %s: expected %s"
                                   % (local, digest))
            verified.append((pinned, url, digest, local))
            print("VERIFIED %s (%d bytes)" % (local.name, local.stat().st_size))

            if pinned["kind"] == "bgm-loop":
                bgm_candidates.append({"pinned": pinned, "url": url,
                                       "sha256": digest, "path": local})
                continue
            with open(local, "rb") as handle:
                magic = handle.read(4)
            if not magic.startswith(b"PK"):
                raise InstallError("pinned archive %s is not a zip container" % local.name)
            with zipfile.ZipFile(local) as zf:
                validate_zip_members(zf, url)
                unpack = Path(tempfile.mkdtemp(prefix="audio-install-unpack-"))
                unpack_dirs.append(unpack)
                for extracted in safe_extract(zf, unpack):
                    if extracted.suffix.lower() == ".ogg":
                        sfx_members.setdefault(extracted.name, []).append(
                            {"path": extracted, "pack": pinned})

        # 2. Re-measure BGM candidates and select the seamless loops.
        selected_bgm = []
        rejected_bgm = []
        for entry in bgm_candidates:
            m = measure(entry["path"])
            entry["measure"] = m
            if bgm_passes(m):
                selected_bgm.append(entry)
            else:
                rejected_bgm.append(entry)
        print("MEASURED bgm_candidates=%d selected=%d rejected=%d"
              % (len(bgm_candidates), len(selected_bgm), len(rejected_bgm)))
        if len(selected_bgm) < MIN_BGM_PASS:
            detail = "; ".join(
                "%s dur=%.2fs onset=%.2fms head=%.1fdB tail=%.1fdB step=%.1fdB"
                % (e["path"].name, e["measure"]["duration_s"], e["measure"]["onset_ms"],
                   e["measure"]["head_rms_db"], e["measure"]["tail_rms_db"],
                   e["measure"]["boundary_step_db"])
                for e in bgm_candidates)
            raise InstallError("only %d of >= %d required BGM loops pass the seam "
                               "thresholds (measured: %s)"
                               % (len(selected_bgm), MIN_BGM_PASS, detail))
        for entry in rejected_bgm:
            print("REJECTED(bgm) %s" % entry["path"].name)

        # 3. Re-measure and select the crisp replacement SFX.
        selected_sfx = []
        for base in SFX_SELECTION:
            found = sfx_members.get(base)
            if not found:
                available = ", ".join(sorted(sfx_members)) or "(none)"
                raise InstallError("selected replacement SFX %r not found in the "
                                   "unpacked pinned archives; available: %s" % (base, available))
            pick = found[0]
            m = measure(pick["path"])
            if not sfx_passes(m):
                raise InstallError("selected replacement SFX %s is not crisp: "
                                   "onset=%.2fms half_amplitude=%.2fms (limits %g/%g ms)"
                                   % (base, m["onset_ms"], m["half_amplitude_ms"],
                                      MAX_ONSET_MS, MAX_HALF_AMPLITUDE_MS))
            selected_sfx.append({"name": base, "path": pick["path"], "measure": m,
                                 "url": pick["pack"]["url"],
                                 "sha256": pick["pack"]["sha256"]})
            print("SELECTED(sfx) %s onset=%.2fms half=%.2fms"
                  % (base, m["onset_ms"], m["half_amplitude_ms"]))

        # 4. Stage the destination plan and scan for conflicts before any write.
        godot = resolve_godot()
        if not (dest_root / PROJECT_GODOT_NAME).is_file():
            raise InstallError("dest-root is not a Godot project (missing %s): %s"
                               % (PROJECT_GODOT_NAME, dest_root))

        plan = []           # (target, payload, kind) kind in {bytes, path, import}
        for entry in selected_bgm:
            target = dest_root / BGM_DIR_REL / entry["path"].name
            plan.append((target, entry["path"], "path"))
        for entry in selected_sfx:
            target = dest_root / DIGITAL_DIR_REL / entry["name"]
            plan.append((target, entry["path"], "path"))
        import_targets = []
        for entry in selected_bgm:
            res_path = "res://%s/%s" % (BGM_DIR_REL, entry["path"].name)
            target = dest_root / BGM_DIR_REL / (entry["path"].name + ".import")
            import_targets.append((target, res_path, True))
        for entry in selected_sfx:
            res_path = "res://%s/%s" % (DIGITAL_DIR_REL, entry["name"])
            target = dest_root / DIGITAL_DIR_REL / (entry["name"] + ".import")
            import_targets.append((target, res_path, False))

        for target, source, kind in plan:
            if target.exists():
                if sha256_file(target) != sha256_file(Path(source)):
                    raise InstallError("pre-existing destination file has different "
                                       "content (additions-only policy): %s" % target)
                print("SKIP identical %s" % target.relative_to(dest_root))
        for target, _res, need_loop in import_targets:
            if target.exists():
                current = import_loop_flag(target)
                required = "true" if need_loop else "false"
                if current == required:
                    continue
                # Pipeline-owned sidecar with a stale loop flag: rewritten at
                # commit; the editor pass then refreshes the imported resource.

        # Pre-validate the record inputs that live outside the staged plan so
        # the records phase can never fail after the destination commit.
        for res_path in PREEXISTING_MAPPED_SFX:
            if not (dest_root / res_path[len("res://"):]).is_file():
                raise InstallError("pre-existing mapped SFX missing: %s"
                                   % (dest_root / res_path[len("res://"):]))

        # 5. Commit destination bytes, then the loop imports + editor pass.
        committed = []
        try:
            for target, source, kind in plan:
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists():
                    continue
                shutil.copyfile(source, target)
                committed.append(target)
                print("INSTALLED %s" % target.relative_to(dest_root))
            for target, res_path, need_loop in import_targets:
                if target.exists() and import_loop_flag(target) == ("true" if need_loop else "false"):
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(import_body(res_path, need_loop), encoding="utf-8",
                                  newline="\n")
                committed.append(target)
                print("IMPORT-SETTINGS %s (loop=%s)"
                      % (target.relative_to(dest_root), "true" if need_loop else "false"))
        except Exception:
            # Restore the destination tree before failing.
            for path in reversed(committed):
                try:
                    path.unlink()
                except OSError:
                    pass
            raise

        # Copy integrity: committed bytes must equal the verified candidates.
        for target, source, _kind in plan:
            if target.exists() and sha256_file(target) != sha256_file(Path(source)):
                raise InstallError("post-copy integrity check failed for %s" % target)

        try:
            _finish_install(selected_bgm, selected_sfx, dest_root, records_root,
                            godot, staged_sources, committed)
        except Exception:
            _rollback(committed, dest_root)
            raise

        print("INSTALL COMPLETE bgm=%d digital=%d sources=%d"
              % (len(selected_bgm), len(selected_sfx), len(staged_sources)))
        return 0
    finally:
        for unpack in unpack_dirs:
            shutil.rmtree(unpack, ignore_errors=True)


def _finish_install(selected_bgm, selected_sfx, dest_root: Path, records_root: Path,
                    godot: Path, staged_sources: list, committed: list) -> None:
    """Editor import pass, import verification and record writing. Any failure
    lets the caller roll the committed destination additions back."""
    print("EDITOR-PASS %s --headless --editor --quit" % godot.name)
    proc = subprocess.run(
        [str(godot), "--headless", "--path", str(dest_root), "--editor", "--quit"],
        cwd=str(dest_root), capture_output=True, timeout=EDITOR_PASS_TIMEOUT_S)
    if proc.returncode != 0:
        tail = ((proc.stderr or b"") + (proc.stdout or b"")).decode("utf-8", "replace")[-800:]
        raise InstallError("editor import pass failed (exit %d): %s"
                           % (proc.returncode, tail))

    # Verify the import results: BGM loops must carry loop=true and the
    # replacement SFX must stay non-looping.
    for rel_dir, loop_needed in ((BGM_DIR_REL, True), (DIGITAL_DIR_REL, False)):
        required = "true" if loop_needed else "false"
        directory = dest_root / rel_dir
        for ogg in sorted(p for p in directory.iterdir() if p.suffix.lower() == ".ogg"):
            target = ogg.with_name(ogg.name + ".import")
            flag = import_loop_flag(target)
            text = target.read_text(encoding="utf-8", errors="replace") if target.exists() else ""
            if flag != required or 'importer="oggvorbisstr"' not in text:
                raise InstallError("import verification failed for %s: loop=%r (want %r)"
                                   % (target, flag, required))
            print("IMPORT-OK %s loop=%s" % (target.relative_to(dest_root), flag))

    # Records: measurements, provenance, manifest, licenses.
    measurements_path = records_root / "assets" / "assets-measurements.json"
    existing_measurements = {"files": []}
    if measurements_path.is_file():
        try:
            parsed = json.loads(measurements_path.read_text(encoding="utf-8"))
            if isinstance(parsed, dict) and isinstance(parsed.get("files"), list):
                existing_measurements = parsed
        except Exception:
            pass
    # Keep foreign-family entries only: the two audio family dirs and the
    # mapped SFX set are always rebuilt fresh from the current bytes below,
    # which also collapses any stale duplicate entries by normalized path.
    keep_by_path = {}
    fresh_paths = {"assets/audio/interface/" + p.rsplit("/", 1)[-1]
                   for p in PREEXISTING_MAPPED_SFX}
    for e in existing_measurements["files"]:
        if not isinstance(e, dict):
            continue
        normalized = str(e.get("path", "")).replace("res://", "").replace("\\", "/")
        if normalized.startswith((BGM_DIR_REL + "/", DIGITAL_DIR_REL + "/")):
            continue
        if normalized in fresh_paths:
            continue
        keep_by_path[normalized] = e
    entries = list(keep_by_path.values())
    for entry in selected_bgm:
        name = entry["path"].name
        entries.append(measurement_entry("res://%s/%s" % (BGM_DIR_REL, name),
                                         entry["sha256"], entry["measure"]))
        entries.append(import_entry("res://%s/%s.import" % (BGM_DIR_REL, name),
                                    dest_root / BGM_DIR_REL / (name + ".import")))
    for entry in selected_sfx:
        digest = sha256_file(entry["path"])
        entries.append(measurement_entry("res://%s/%s" % (DIGITAL_DIR_REL, entry["name"]),
                                         digest, entry["measure"]))
        entries.append(import_entry("res://%s/%s.import" % (DIGITAL_DIR_REL, entry["name"]),
                                    dest_root / DIGITAL_DIR_REL / (entry["name"] + ".import")))
    for res_path in PREEXISTING_MAPPED_SFX:
        path = dest_root / res_path[len("res://"):]
        digest = sha256_file(path)
        m = measure(path)
        entries.append(measurement_entry(res_path, digest, m))
    entries.sort(key=lambda e: str(e["path"]))
    write_json(measurements_path, {"files": entries})
    print("RECORDS %s (%d files)" % (measurements_path.relative_to(records_root), len(entries)))

    provenance_path = records_root / "assets" / "assets-provenance.json"
    provenance = {"families": []}
    if provenance_path.is_file():
        try:
            parsed = json.loads(provenance_path.read_text(encoding="utf-8"))
            if isinstance(parsed, dict) and isinstance(parsed.get("families"), list):
                provenance = parsed
        except Exception as exc:
            raise InstallError("existing provenance record unparseable: %s" % exc)
    families = [f for f in provenance["families"]
                if isinstance(f, dict) and str(f.get("dest", "")) not in
                ("res://" + BGM_DIR_REL, "res://" + DIGITAL_DIR_REL)]
    bgm_mods = [
        {"file": "res://%s/%s" % (BGM_DIR_REL, e["path"].name),
         "note": "copied verbatim from pinned source %s (sha256 %s); loop import flag enabled"
                 % (e["url"], e["sha256"])}
        for e in selected_bgm]
    digital_mods = [
        {"file": "res://%s/%s" % (DIGITAL_DIR_REL, e["name"]),
         "note": "copied verbatim from pinned source %s (sha256 %s); kept non-looping"
                 % (e["url"], e["sha256"])}
        for e in selected_sfx]
    families.append({"source": BGM_FAMILY_SOURCE,
                     "author": "Magory (music by Tomasz Kucza)",
                     "license": "CC-BY 4.0",
                     "dest": "res://" + BGM_DIR_REL,
                     "modifications": bgm_mods})
    families.append({"source": DIGITAL_FAMILY_SOURCE,
                     "author": "Kenney",
                     "license": "CC0",
                     "dest": "res://" + DIGITAL_DIR_REL,
                     "modifications": digital_mods})
    write_json(provenance_path, {"families": families})
    print("RECORDS %s (%d families)" % (provenance_path.relative_to(records_root), len(families)))

    manifest_path_out = records_root / "assets" / "assets-manifest.json"
    write_json(manifest_path_out, {"sources": staged_sources})
    print("RECORDS %s (%d sources)" % (manifest_path_out.relative_to(records_root),
                                       len(staged_sources)))

    (records_root / "assets" / BGM_LICENSE_NAME).write_text(
        license_text_bgm(selected_bgm), encoding="utf-8", newline="\n")
    (records_root / "assets" / DIGITAL_LICENSE_NAME).write_text(
        license_text_digital([dict(PINNED_BY_URL[DIGITAL_FAMILY_SOURCE])]),
        encoding="utf-8", newline="\n")
    print("RECORDS assets/%s" % BGM_LICENSE_NAME)
    print("RECORDS assets/%s" % DIGITAL_LICENSE_NAME)


def _rollback(committed: list[Path], dest_root: Path) -> None:
    """Best-effort removal of the additions made before a failed import pass."""
    for path in reversed(committed):
        try:
            path.unlink()
            print("ROLLBACK removed %s" % path)
        except OSError:
            pass
    for folder in sorted({path.parent for path in committed}, reverse=True):
        try:
            if folder != dest_root and not any(folder.iterdir()):
                folder.rmdir()
        except OSError:
            pass


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Install the pinned audio assets (download, verify, measure, "
                    "select, install with loop imports, write records)")
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST,
                        help="path to assets/assets-manifest.json (default: %(default)s)")
    parser.add_argument("--dest-root", default=".",
                        help="base directory for installed asset paths (default: .)")
    parser.add_argument("--records-root", default=".",
                        help="base directory for assets/*.json and assets/LICENSE-*.txt (default: .)")
    parser.add_argument("--cache-dir", default=None,
                        help="download cache directory (default: <system temp>/audio-install-cache)")
    parser.add_argument("--offline", action="store_true",
                        help="forbid network access; every pinned archive must already be "
                             "cached with a matching SHA-256")
    args = parser.parse_args(argv)
    try:
        return run(args)
    except InstallError as exc:
        sys.stderr.write("ABORT: %s\n" % exc)
        return 2
    except subprocess.TimeoutExpired as exc:
        sys.stderr.write("ABORT: subprocess timeout: %s\n" % exc)
        return 2


if __name__ == "__main__":
    sys.exit(main())
