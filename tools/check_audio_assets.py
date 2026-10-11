#!/usr/bin/env python3
"""V-01 acceptance check for the modern-tetris audio-overhaul slice.

Frozen CLI (binding record section 4):

    python tools/check_audio_assets.py [--project-root .]

Fail-closed: exits 0 and prints AUDIO ASSET CHECKS PASSED only when every
check passes. ffmpeg/ffprobe from PATH are the byte-level measurement
authority: every installed audio file is re-decoded and re-measured, and a
mismatch against the recorded values in assets/assets-measurements.json
beyond the documented tolerances fails the run.

Measurement definitions (deterministic, computed on decoded f32 audio,
mixed to mono by averaging channels per frame):
  onset_ms           first sample index with |x| >= -60 dBFS, in milliseconds
  half_amplitude_ms  first sample index with |x| >= 0.5 * peak|x|, in ms
  duration_s         decoded frame count / sample rate
  head_rms_db        20*log10 RMS of the first 10 ms, floor -100 dBFS
  tail_rms_db        20*log10 RMS of the last 10 ms, floor -100 dBFS
  boundary_step_db   20*log10(|x[last] - x[0]|), floor -120 dBFS

Sandbox fail-closed branches run in isolated temp directories through the
frozen tools/install_audio_assets.py CLI (binding record section 3) with
--offline; they never write inside the project.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PASSED_MARKER = "AUDIO ASSET CHECKS PASSED"

MEASUREMENTS_REL = "assets/assets-measurements.json"
MANIFEST_REL = "assets/assets-manifest.json"
PROVENANCE_REL = "assets/assets-provenance.json"
BGM_DIR_REL = "assets/audio/bgm"
DIGITAL_DIR_REL = "assets/audio/digital"
ASSETS_ROOT_REL = "assets"

# Pinned install sources. The four Magory OGA loop URLs were dropped by the
# korobeiniki-hud-input freeze (binding record §A.5, contract P-01): those
# files and their manifest entries are removed by S-I01-base-01 and are no
# longer pinned. The two Kenney SFX pins stay.
PINNED_SOURCES = {
    "https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip":
        "24e6ce28b76a6d8c89cff4d331e0965ff5c3de8a73c612028e9d363cc64e4f06",
    "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip":
        "f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232",
}

BGM_MIN_DURATION_S = 20.0
MAX_ONSET_MS = 30.0
MAX_HALF_AMPLITUDE_MS = 30.0
MAX_HEAD_TAIL_DELTA_DB = 12.0
MAX_BOUNDARY_STEP_DBFS = -35.0
MIN_BGM_PASS = 3
MIN_DIGITAL_PASS = 2

# Tolerances for record-vs-remeasure comparison (V-01 is the byte-level
# measurement authority; the record must track the bytes it binds).
TOL_DURATION_S = 0.05
TOL_MS = 2.0
TOL_DB = 0.5
TOL_STEP_DB = 1.0

REQUIRED_MEASUREMENT_KEYS = (
    "path", "sha256", "onset_ms", "half_amplitude_ms",
    "duration_s", "head_rms_db", "tail_rms_db", "boundary_step_db",
)

# CR-01 (defect A) threshold filter semantics: re-measurement covers real
# audio files only. Godot import sidecars (*.import, e.g. x.ogg.import) are
# step-mandated metadata and are skip-listed; any other unexpected extension
# fails closed instead of being silently ignored. list_audio_files and
# check_records_and_bytes are deliberately untouched: their records/bytes
# set-equality keeps covering every file in the family dirs, sidecars included.
AUDIO_SIDECAR_SUFFIX = ".import"
AUDIO_EXTENSIONS = (".ogg",)

TRAVERSAL_MEMBER = "../v01_traversal_evil.txt"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ffprobe_stream(path: Path) -> dict:
    cmd = ["ffprobe", "-v", "error", "-select_streams", "a:0",
           "-show_entries", "stream=sample_rate,channels:format=duration",
           "-of", "json", str(path)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("ffprobe failed: " + (proc.stderr or "").strip()[:300])
    data = json.loads(proc.stdout or "{}")
    streams = data.get("streams") or []
    if not streams:
        raise RuntimeError("ffprobe found no audio stream")
    info = dict(streams[0])
    fmt = data.get("format") or {}
    if fmt.get("duration") is not None:
        info["container_duration"] = float(fmt["duration"])
    return info


def decode_f32(path: Path) -> array.array:
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
           "-f", "f32le", "-acodec", "pcm_f32le", "-"]
    proc = subprocess.run(cmd, capture_output=True, timeout=600)
    if proc.returncode != 0:
        raise RuntimeError("ffmpeg decode failed: "
                           + (proc.stderr or b"").decode("utf-8", "replace").strip()[:300])
    samples = array.array("f")
    samples.frombytes(proc.stdout)
    return samples


def measure(path: Path) -> dict:
    info = ffprobe_stream(path)
    sample_rate = int(info.get("sample_rate") or 0)
    channels = max(1, int(info.get("channels") or 1))
    if sample_rate <= 0:
        raise RuntimeError("ffprobe reported no sample rate")
    samples = decode_f32(path)
    frames = len(samples) // channels
    if frames <= 0:
        raise RuntimeError("decode produced no frames")
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


def list_audio_files(root: Path, rel_dir: str) -> list:
    directory = root / rel_dir
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.iterdir() if p.is_file())


def check_records_and_bytes(root: Path, fail) -> dict:
    path = root / MEASUREMENTS_REL
    if not path.is_file():
        fail("measurements_record", MEASUREMENTS_REL + " missing")
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail("measurements_record", "unparseable: %s" % exc)
        return {}
    files = data.get("files") if isinstance(data, dict) else None
    if not isinstance(files, list) or not files:
        fail("measurements_record", "files[] missing or empty")
        return {}
    records = {}
    for entry in files:
        if not isinstance(entry, dict):
            fail("measurements_record", "non-object entry in files[]")
            continue
        missing = [k for k in REQUIRED_MEASUREMENT_KEYS if k not in entry]
        if missing:
            fail("measurements_record", "entry missing keys %s" % missing)
            continue
        rel = str(entry["path"]).replace("\\", "/")
        if rel.startswith("res://"):
            rel = rel[len("res://"):]
        records[rel] = entry
    installed = {}
    for p in list_audio_files(root, BGM_DIR_REL):
        installed[BGM_DIR_REL + "/" + p.name] = p
    for p in list_audio_files(root, DIGITAL_DIR_REL):
        installed[DIGITAL_DIR_REL + "/" + p.name] = p
    if not installed:
        fail("installed_assets",
             "no installed audio files under %s or %s" % (BGM_DIR_REL, DIGITAL_DIR_REL))
    for rel in sorted(installed):
        if rel not in records:
            fail("record_covers_installed", rel + " has no measurement record")
            continue
        recorded = str(records[rel].get("sha256", "")).lower()
        if recorded != sha256_file(installed[rel]):
            fail("byte_matches_record", rel + " sha256 mismatch against record")
    for rel in sorted(records):
        if rel.startswith((BGM_DIR_REL + "/", DIGITAL_DIR_REL + "/")) and rel not in installed:
            fail("record_covers_installed", "recorded file missing on disk: " + rel)
    return records


def check_pinned_sources(root: Path, fail) -> None:
    path = root / MANIFEST_REL
    if not path.is_file():
        fail("manifest_record", MANIFEST_REL + " missing")
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail("manifest_record", "unparseable: %s" % exc)
        return
    sources = data.get("sources") if isinstance(data, dict) else None
    if not isinstance(sources, list) or not sources:
        fail("manifest_record", "sources[] missing or empty")
        return
    by_url = {}
    for entry in sources:
        if isinstance(entry, dict) and entry.get("url") is not None:
            by_url[str(entry["url"])] = entry
    for url, digest in sorted(PINNED_SOURCES.items()):
        entry = by_url.get(url)
        if entry is None:
            fail("pinned_source_present", "missing pinned source " + url)
            continue
        recorded = str(entry.get("sha256", "")).lower()
        if recorded != digest:
            fail("pinned_source_hash", "%s record=%s pinned=%s" % (url, recorded, digest))


def check_thresholds(root: Path, records: dict, rel_dir: str, is_bgm: bool, fail) -> int:
    # CR-01 defect A fix: filter to real audio files for re-measurement only
    # (skip-list .import sidecars, fail closed on unexpected extensions).
    audio_paths = []
    for path in list_audio_files(root, rel_dir):
        if path.name.endswith(AUDIO_SIDECAR_SUFFIX):
            continue
        if not path.name.lower().endswith(AUDIO_EXTENSIONS):
            fail("unexpected_asset_file",
                 "%s/%s: unexpected extension, not measured" % (rel_dir, path.name))
            continue
        audio_paths.append(path)
    if not audio_paths:
        fail("installed_assets", "no installed audio files under " + rel_dir)
    passing = 0
    for path in audio_paths:
        rel = rel_dir + "/" + path.name
        try:
            m = measure(path)
        except Exception as exc:
            fail("remeasure", "%s: %s" % (rel, exc))
            continue
        if is_bgm:
            passes = (m["duration_s"] >= BGM_MIN_DURATION_S
                      and m["onset_ms"] <= MAX_ONSET_MS
                      and abs(m["head_rms_db"] - m["tail_rms_db"]) <= MAX_HEAD_TAIL_DELTA_DB
                      and m["boundary_step_db"] <= MAX_BOUNDARY_STEP_DBFS)
        else:
            passes = (m["onset_ms"] <= MAX_ONSET_MS
                      and m["half_amplitude_ms"] <= MAX_HALF_AMPLITUDE_MS)
        if passes:
            passing += 1
        record = records.get(rel)
        if record is None:
            fail("remeasure_record_binding", rel + ": no measurement record to compare")
            continue
        tolerances = (("duration_s", TOL_DURATION_S), ("onset_ms", TOL_MS),
                      ("half_amplitude_ms", TOL_MS), ("head_rms_db", TOL_DB),
                      ("tail_rms_db", TOL_DB), ("boundary_step_db", TOL_STEP_DB))
        for key, tol in tolerances:
            try:
                recorded = float(record[key])
            except Exception:
                fail("remeasure_record_binding", "%s: record field %s invalid" % (rel, key))
                continue
            if abs(recorded - m[key]) > tol:
                fail("remeasure_record_binding",
                     "%s: %s record=%.4f measured=%.4f (tol %.2f)" % (rel, key, recorded, m[key], tol))
    return passing


def check_family_records(root: Path, fail) -> None:
    path = root / PROVENANCE_REL
    if not path.is_file():
        fail("provenance_record", PROVENANCE_REL + " missing")
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail("provenance_record", "unparseable: %s" % exc)
        return
    families = data.get("families") if isinstance(data, dict) else None
    if not isinstance(families, list) or not families:
        fail("provenance_record", "families[] missing or empty")
        return
    covered = set()
    for entry in families:
        if not isinstance(entry, dict):
            fail("provenance_record", "non-object family entry")
            continue
        for field in ("source", "author", "license", "dest"):
            value = entry.get(field)
            if not isinstance(value, str) or not value:
                fail("provenance_record", "family field %s empty" % field)
        source = entry.get("source")
        # A family rendered by one of the project's own tools names that tool.
        if not isinstance(source, str) or not (source.startswith("http://") or source.startswith("https://")
                                               or source.startswith("tools/")):
            fail("provenance_record", "family source is not a URL")
        dest = entry.get("dest")
        if isinstance(dest, str):
            normalized = dest.replace("res://", "").replace("\\", "/").rstrip("/")
            covered.add(normalized)
    for needed in (BGM_DIR_REL, DIGITAL_DIR_REL):
        if needed not in covered:
            fail("provenance_family", "no provenance family covers " + needed)
            continue
        keyword = "bgm" if "bgm" in needed else "digital"
        licensed = False
        assets_dir = root / ASSETS_ROOT_REL
        if assets_dir.is_dir():
            for p in assets_dir.iterdir():
                if p.is_file() and p.name.startswith("LICENSE") and keyword in p.name.lower():
                    licensed = True
        family_dir = root / needed
        if family_dir.is_dir():
            for p in family_dir.iterdir():
                if p.is_file() and p.name.startswith("LICENSE"):
                    licensed = True
        if not licensed:
            fail("license_record", "no license record found for " + needed)


def check_no_remote(root: Path, fail) -> None:
    targets = [root / "project.godot"]
    for sub, pattern in (("scenes", "*.tscn"), ("scripts", "*.gd")):
        directory = root / sub
        if directory.is_dir():
            targets.extend(sorted(directory.glob(pattern)))
    assets_dir = root / ASSETS_ROOT_REL
    if assets_dir.is_dir():
        targets.extend(sorted(assets_dir.rglob("*.import")))
    checked = 0
    for target in targets:
        if not target.is_file():
            fail("no_remote_runtime_reference", "missing expected file " + str(target))
            continue
        try:
            text = target.read_text(encoding="utf-8", errors="replace")
        except Exception as exc:
            fail("no_remote_runtime_reference", "%s unreadable: %s" % (target, exc))
            continue
        checked += 1
        if "http://" in text or "https://" in text:
            fail("no_remote_runtime_reference",
                 "remote URL in " + str(target.relative_to(root)))
    if checked == 0:
        fail("no_remote_runtime_reference", "no runtime resource files were scanned")


def discover_pinned_archives(needed: dict) -> dict:
    """Locate local copies of the pinned archives by content hash.

    The sandbox branches run --offline, so the installer cache must be
    seeded from whatever local copy exists (phase-0 cache or a previous
    install run's temp cache). Discovery is bounded and read-only.
    """
    found = {}
    temp_root = Path(tempfile.gettempdir())
    candidates = []
    p0 = temp_root / "opencode" / "p0-audio"
    if p0.is_dir():
        candidates.append(p0)
    candidates.append(temp_root)
    budget = 15000
    seen = set()
    for base in candidates:
        try:
            resolved = base.resolve()
        except OSError:
            continue
        if resolved in seen or not base.is_dir():
            continue
        seen.add(resolved)
        for dirpath, dirnames, filenames in os.walk(base):
            depth = len(Path(dirpath).parts) - len(resolved.parts)
            if depth >= 4:
                dirnames[:] = []
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for name in filenames:
                budget -= 1
                if budget <= 0:
                    return found
                candidate = Path(dirpath) / name
                try:
                    if candidate.stat().st_size > 80 * 1024 * 1024:
                        continue
                    if candidate.stat().st_size < 100 * 1024:
                        continue
                    digest = sha256_file(candidate)
                except OSError:
                    continue
                if digest in needed.values() and digest not in found:
                    found[digest] = candidate
                    if len(found) == len(needed):
                        return found
    return found


def run_installer(project_root: Path, manifest: Path, dest: Path, records: Path, cache: Path):
    script = project_root / "tools" / "install_audio_assets.py"
    if not script.is_file():
        raise RuntimeError("tools/install_audio_assets.py is missing (I-01 artifact)")
    cmd = [sys.executable, str(script),
           "--manifest", str(manifest),
           "--dest-root", str(dest),
           "--records-root", str(records),
           "--cache-dir", str(cache),
           "--offline"]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=600)


def snapshot_tree(base: Path) -> dict:
    state = {}
    if not base.exists():
        return state
    for p in sorted(base.rglob("*")):
        rel = str(p.relative_to(base)).replace("\\", "/")
        if p.is_dir():
            state[rel + "/"] = "dir"
        else:
            state[rel] = sha256_file(p)
    return state


def load_manifest(root: Path, fail):
    path = root / MANIFEST_REL
    if not path.is_file():
        fail("sandbox_setup", MANIFEST_REL + " missing")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail("sandbox_setup", "manifest unparseable: %s" % exc)
        return None


def write_sandbox_manifest(data: dict, sandbox: Path) -> Path:
    manifest_path = sandbox / "assets-manifest.json"
    manifest_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return manifest_path


def sandbox_branch_a(project_root: Path, fail, discovered: dict) -> None:
    """Tampered manifest hash aborts with destination tree byte-identical."""
    label = "sandbox_a_tampered_hash"
    if not discovered:
        fail(label, "no pinned archive discovered for offline cache seeding")
        return
    data = load_manifest(project_root, fail)
    if data is None:
        return
    sources = data.get("sources")
    if not isinstance(sources, list) or not sources:
        fail(label, "manifest sources[] missing")
        return
    target_index = None
    for i, entry in enumerate(sources):
        if isinstance(entry, dict) and str(entry.get("sha256", "")).lower() in discovered:
            target_index = i
            break
    if target_index is None:
        fail(label, "no manifest source has a discovered local archive")
        return
    target = sources[target_index]
    real_sha = str(target["sha256"]).lower()
    tampered = ("0" if real_sha[0] != "0" else "1") + real_sha[1:]
    target["sha256"] = tampered
    sources.insert(0, sources.pop(target_index))
    sandbox = Path(tempfile.mkdtemp(prefix="v01-sandbox-a-"))
    try:
        cache = sandbox / "cache"
        cache.mkdir()
        shutil.copyfile(discovered[real_sha], cache / discovered[real_sha].name)
        dest = sandbox / "dest"
        records = sandbox / "records"
        dest.mkdir()
        records.mkdir()
        manifest_path = write_sandbox_manifest(data, sandbox)
        pre = {**snapshot_tree(dest), **snapshot_tree(records)}
        proc = run_installer(project_root, manifest_path, dest, records, cache)
        post = {**snapshot_tree(dest), **snapshot_tree(records)}
        if proc.returncode == 0:
            fail(label, "installer exited 0 on a tampered manifest hash")
        if pre != post:
            fail(label, "destination/records trees changed on abort")
        (sandbox / "installer-output.txt").write_text(
            (proc.stdout or "") + "\n--- stderr ---\n" + (proc.stderr or ""), encoding="utf-8")
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def sandbox_branch_b(project_root: Path, fail, discovered: dict) -> None:
    """Crafted traversal archive member is rejected."""
    label = "sandbox_b_traversal_member"
    if not discovered:
        fail(label, "no pinned archive discovered for offline cache seeding")
        return
    data = load_manifest(project_root, fail)
    if data is None:
        return
    sources = data.get("sources")
    if not isinstance(sources, list) or not sources:
        fail(label, "manifest sources[] missing")
        return
    target_index = None
    for i, entry in enumerate(sources):
        if isinstance(entry, dict) and str(entry.get("sha256", "")).lower() in discovered:
            target_index = i
            break
    if target_index is None:
        fail(label, "no manifest source has a discovered local archive")
        return
    target = sources[target_index]
    real_sha = str(target["sha256"]).lower()
    zip_path = Path(tempfile.gettempdir()) / "v01-traversal-zip.tmp"
    with zipfile.ZipFile(zip_path, "w") as zf:
        info = zipfile.ZipInfo(TRAVERSAL_MEMBER, date_time=(1980, 1, 1, 0, 0, 0))
        zf.writestr(info, b"v01-traversal-probe")
    zip_bytes = zip_path.read_bytes()
    zip_path.unlink()
    traversal_sha = hashlib.sha256(zip_bytes).hexdigest()
    target["sha256"] = traversal_sha
    sources.insert(0, sources.pop(target_index))
    sandbox = Path(tempfile.mkdtemp(prefix="v01-sandbox-b-"))
    try:
        cache = sandbox / "cache"
        cache.mkdir()
        shutil.copyfile(discovered[real_sha], cache / discovered[real_sha].name)
        (cache / discovered[real_sha].name).write_bytes(zip_bytes)
        dest = sandbox / "dest"
        records = sandbox / "records"
        dest.mkdir()
        records.mkdir()
        manifest_path = write_sandbox_manifest(data, sandbox)
        pre = {**snapshot_tree(dest), **snapshot_tree(records)}
        proc = run_installer(project_root, manifest_path, dest, records, cache)
        post = {**snapshot_tree(dest), **snapshot_tree(records)}
        if proc.returncode == 0:
            fail(label, "installer exited 0 on a traversal archive member")
        if pre != post:
            fail(label, "destination/records trees changed on abort")
        for base in (dest, records, sandbox):
            if any(base.rglob("v01_traversal_evil.txt")):
                fail(label, "traversal member content escaped into the destination tree")
                break
        (sandbox / "installer-output.txt").write_text(
            (proc.stdout or "") + "\n--- stderr ---\n" + (proc.stderr or ""), encoding="utf-8")
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def sandbox_branch_c(project_root: Path, fail, discovered: dict, records_index: dict) -> None:
    """Pre-existing same-name destination file with different content stays
    byte-identical after install and rollback (install aborts, stage+commit)."""
    label = "sandbox_c_same_name_conflict"
    missing = [d for d in PINNED_SOURCES.values() if d not in discovered]
    if missing:
        fail(label, "offline cache seeding incomplete: %d of %d pinned archives found"
             % (len(PINNED_SOURCES) - len(missing), len(PINNED_SOURCES)))
        return
    fixture_rel = None
    for rel in sorted(records_index):
        if rel.startswith(BGM_DIR_REL + "/"):
            fixture_rel = rel
            break
    if fixture_rel is None:
        fail(label, "no installed BGM asset available for the hash-bound conflict fixture")
        return
    fixture_path = project_root / fixture_rel
    if not fixture_path.is_file():
        fail(label, "fixture source missing on disk: " + fixture_rel)
        return
    real_bytes = fixture_path.read_bytes()
    conflict_bytes = real_bytes[:-1] + bytes([real_bytes[-1] ^ 0xFF])
    data = load_manifest(project_root, fail)
    if data is None:
        return
    sandbox = Path(tempfile.mkdtemp(prefix="v01-sandbox-c-"))
    try:
        cache = sandbox / "cache"
        cache.mkdir()
        for digest, path in discovered.items():
            shutil.copyfile(path, cache / path.name)
        dest = sandbox / "dest"
        records = sandbox / "records"
        (dest / Path(fixture_rel).parent).mkdir(parents=True)
        (dest / fixture_rel).write_bytes(conflict_bytes)
        records.mkdir()
        manifest_path = write_sandbox_manifest(data, sandbox)
        pre = {**snapshot_tree(dest), **snapshot_tree(records)}
        proc = run_installer(project_root, manifest_path, dest, records, cache)
        post = {**snapshot_tree(dest), **snapshot_tree(records)}
        if proc.returncode == 0:
            fail(label, "installer exited 0 although the destination file differed")
        if pre != post:
            fail(label, "destination/records trees changed: the conflicting file was not preserved byte-identical")
        (sandbox / "installer-output.txt").write_text(
            (proc.stdout or "") + "\n--- stderr ---\n" + (proc.stderr or ""), encoding="utf-8")
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="V-01 audio asset acceptance check")
    parser.add_argument("--project-root", default=".",
                        help="project root containing assets/ and tools/ (default: .)")
    args = parser.parse_args(argv)
    root = Path(args.project_root).resolve()

    failures = []

    def fail(name: str, reason: str) -> None:
        line = "FAIL %s: %s" % (name, reason)
        print(line)
        failures.append(line)

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            fail("environment", tool + " not on PATH")

    bgm_pass = 0
    digital_pass = 0
    records = {}
    if not any(f.startswith("FAIL environment") for f in failures):
        try:
            records = check_records_and_bytes(root, fail)
        except Exception as exc:
            fail("measurements_record", "unexpected: %s" % exc)
        try:
            check_pinned_sources(root, fail)
        except Exception as exc:
            fail("pinned_sources", "unexpected: %s" % exc)
        try:
            bgm_pass = check_thresholds(root, records, BGM_DIR_REL, True, fail)
        except Exception as exc:
            fail("bgm_thresholds", "unexpected: %s" % exc)
        if bgm_pass < MIN_BGM_PASS:
            fail("bgm_thresholds", "only %d of >= %d required BGM loops pass" % (bgm_pass, MIN_BGM_PASS))
        try:
            digital_pass = check_thresholds(root, records, DIGITAL_DIR_REL, False, fail)
        except Exception as exc:
            fail("digital_thresholds", "unexpected: %s" % exc)
        if digital_pass < MIN_DIGITAL_PASS:
            fail("digital_thresholds", "only %d of >= %d required replacement SFX pass"
                 % (digital_pass, MIN_DIGITAL_PASS))
        try:
            check_family_records(root, fail)
        except Exception as exc:
            fail("family_records", "unexpected: %s" % exc)
        try:
            check_no_remote(root, fail)
        except Exception as exc:
            fail("no_remote_runtime_reference", "unexpected: %s" % exc)
        try:
            discovered = discover_pinned_archives(PINNED_SOURCES)
        except Exception as exc:
            discovered = {}
            fail("sandbox_cache_discovery", "unexpected: %s" % exc)
        try:
            sandbox_branch_a(root, fail, discovered)
        except Exception as exc:
            fail("sandbox_a_tampered_hash", "unexpected: %s" % exc)
        try:
            sandbox_branch_b(root, fail, discovered)
        except Exception as exc:
            fail("sandbox_b_traversal_member", "unexpected: %s" % exc)
        try:
            sandbox_branch_c(root, fail, discovered, records)
        except Exception as exc:
            fail("sandbox_c_same_name_conflict", "unexpected: %s" % exc)

    if failures:
        print("AUDIO ASSET CHECKS FAILED (%d)" % len(failures))
        return 1
    print("%s (bgm_loops_passing=%d digital_sfx_passing=%d sandbox_branches=3)"
          % (PASSED_MARKER, bgm_pass, digital_pass))
    return 0


if __name__ == "__main__":
    sys.exit(main())
