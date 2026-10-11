#!/usr/bin/env python3
"""O-10 isolated delivery check for the modern-tetris menu/modes refresh.

Frozen CLI (goal card O-10 verification command):

    python tools/isolated_delivery_check.py --godot "<godot executable>"

The check proves the delivered source is a self-contained offline project:

1. Copy the delivery source into a unique staging directory under the system
   temp directory (excluded: .godot/, .opencode/, __pycache__/, .git/, *.pyc).
   The delivered workspace itself is never written to.
2. In the copy, run a headless import: --headless --path . --editor --quit.
   Per README, a fresh import may crash once in Godot 4.7.2 while
   re-importing Ogg audio; that one command may be rerun once (and only once).
3. In the copy, run the full headless suite:
   --headless --path . --script res://tests/run_all.gd
4. Both stages must exit 0 and the suite stdout must contain
   "ALL TESTS PASSED".

stdout/stderr, exit codes, timestamps, durations and the conclusion are
written to <staging>/evidence/. On success the script prints
ISOLATED DELIVERY CHECK PASSED and exits 0; on any failure it prints the
failure reasons and exits non-zero. The staging directory is kept and its
path printed as the evidence location.

Standard library only; all subprocesses use argument lists (no shell
concatenation), so Windows paths with spaces or non-ASCII characters are
handled verbatim.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PASSED_MARKER = "ISOLATED DELIVERY CHECK PASSED"
FAILED_MARKER = "ISOLATED DELIVERY CHECK FAILED"
SUITE_MARKER = "ALL TESTS PASSED"

EXCLUDED_DIR_NAMES = (".godot", ".opencode", "__pycache__", ".git")
EXCLUDED_FILE_PATTERNS = ("*.pyc",)

IMPORT_ARGS = ["--headless", "--path", ".", "--editor", "--quit"]
SUITE_ARGS = ["--headless", "--path", ".", "--script", "res://tests/run_all.gd"]

IMPORT_TIMEOUT_S = 400
SUITE_TIMEOUT_S = 700
STAGING_PREFIX = "isolated-delivery-check-"

EVIDENCE_DIR_NAME = "evidence"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def print_safe(line: str) -> None:
    print(line)


def copy_delivery(source: Path, staging: Path) -> None:
    """Copy the delivered tree, ignoring regenerated/cache/tooling-only dirs."""
    ignore = shutil.ignore_patterns(*EXCLUDED_DIR_NAMES, *EXCLUDED_FILE_PATTERNS)
    shutil.copytree(source, staging, ignore=ignore, dirs_exist_ok=True)


def run_godot(godot: str, cwd: Path, args: list, timeout_s: int) -> dict:
    """Run one Godot command in the copy; never raises on engine failure."""
    cmd = [godot] + list(args)
    started_at = utc_now()
    start = time.monotonic()
    timed_out = False
    try:
        proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True,
                              timeout=timeout_s)
        stdout = proc.stdout or b""
        stderr = proc.stderr or b""
        exit_code = proc.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
        exit_code = None
        timed_out = True
    duration_s = round(time.monotonic() - start, 3)
    text = stdout.decode("utf-8", "replace")
    marker_lines = [line.strip() for line in text.splitlines()
                    if SUITE_MARKER in line]
    return {
        "command": cmd,
        "started_at": started_at,
        "finished_at": utc_now(),
        "duration_s": duration_s,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "stdout_bytes": stdout,
        "stderr_bytes": stderr,
        "suite_marker_found": bool(marker_lines),
        "suite_marker_line": marker_lines[-1] if marker_lines else None,
    }


def record_run(result: dict, evidence_dir: Path, name: str) -> dict:
    """Persist raw streams for one run and return the JSON-safe summary."""
    (evidence_dir / (name + ".stdout.txt")).write_bytes(result["stdout_bytes"])
    (evidence_dir / (name + ".stderr.txt")).write_bytes(result["stderr_bytes"])
    summary = {key: value for key, value in result.items()
               if not key.endswith("_bytes")}
    summary["stdout_file"] = name + ".stdout.txt"
    summary["stderr_file"] = name + ".stderr.txt"
    return summary


def describe_run(result: dict) -> str:
    if result["timed_out"]:
        return "timed out after %ss" % result["duration_s"]
    return "exited with code %s after %ss" % (result["exit_code"], result["duration_s"])


def main(argv=None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        # Windows consoles may not encode every path character; never crash
        # while reporting a failure.
        sys.stdout.reconfigure(errors="replace")
        sys.stderr.reconfigure(errors="replace")

    parser = argparse.ArgumentParser(
        description="O-10 isolated delivery check (copy, import, run the suite)")
    parser.add_argument("--godot", required=True,
                        help="path to the Godot 4.7.x executable")
    parser.add_argument("--project-root", default=None,
                        help="delivery root (default: the tools/ parent directory)")
    args = parser.parse_args(argv)

    if args.project_root:
        root = Path(args.project_root).resolve()
    else:
        root = Path(__file__).resolve().parent.parent
    godot_path = Path(args.godot).expanduser()
    godot = str(godot_path.resolve()) if godot_path.exists() else args.godot

    failures = []
    staging = None
    evidence_dir = None
    evidence = {
        "schema_version": 1,
        "check": "isolated_delivery_check",
        "started_at": utc_now(),
        "godot": godot,
        "source_root": str(root),
        "staging_dir": None,
        "evidence_dir": None,
        "excluded_names": list(EXCLUDED_DIR_NAMES),
        "excluded_files": list(EXCLUDED_FILE_PATTERNS),
        "import_stage": None,
        "suite_stage": None,
        "failure_reasons": failures,
        "conclusion": None,
    }

    try:
        if not (root / "project.godot").is_file():
            failures.append("delivery root has no project.godot: " + str(root))
        if not godot_path.is_file():
            failures.append("godot executable not found: " + str(godot_path))

        if failures:
            evidence["finished_at"] = utc_now()
            print_safe("source root: %s" % root)
            for reason in failures:
                print_safe("isolated delivery check: " + reason)
            print_safe(FAILED_MARKER)
            return 1

        staging = Path(tempfile.mkdtemp(prefix=STAGING_PREFIX))
        evidence_dir = staging / EVIDENCE_DIR_NAME
        evidence_dir.mkdir()
        evidence["staging_dir"] = str(staging)
        evidence["evidence_dir"] = str(evidence_dir)

        copy_delivery(root, staging)
        if not (staging / "project.godot").is_file():
            failures.append("copy did not produce project.godot in staging")

        import_attempts = []
        import_passed = False
        if not failures:
            attempt = run_godot(godot, staging, IMPORT_ARGS, IMPORT_TIMEOUT_S)
            import_attempts.append(
                record_run(attempt, evidence_dir, "import-attempt-1"))
            import_passed = attempt["exit_code"] == 0 and not attempt["timed_out"]
            if not import_passed:
                # Documented engine limitation (README): the first fresh
                # import may crash once; the same command may be rerun once.
                retry = run_godot(godot, staging, IMPORT_ARGS, IMPORT_TIMEOUT_S)
                import_attempts.append(
                    record_run(retry, evidence_dir, "import-attempt-2"))
                import_passed = (retry["exit_code"] == 0
                                 and not retry["timed_out"])
            evidence["import_stage"] = {
                "command": [godot] + IMPORT_ARGS,
                "attempts": import_attempts,
                "retry_used": len(import_attempts) > 1,
                "passed": import_passed,
            }
            if not import_passed:
                last = import_attempts[-1]
                failures.append(
                    "isolated import failed: final attempt %s"
                    % describe_run(last))

        if not failures:
            suite = run_godot(godot, staging, SUITE_ARGS, SUITE_TIMEOUT_S)
            suite_summary = record_run(suite, evidence_dir, "suite")
            evidence["suite_stage"] = suite_summary
            if suite["exit_code"] != 0 or suite["timed_out"]:
                failures.append("isolated suite run %s" % describe_run(suite))
            elif not suite["suite_marker_found"]:
                failures.append(
                    "isolated suite stdout is missing %r" % SUITE_MARKER)

        evidence["conclusion"] = "passed" if not failures else "failed"
        evidence["finished_at"] = utc_now()
        (evidence_dir / "evidence.json").write_text(
            json.dumps(evidence, indent=2, ensure_ascii=False), encoding="utf-8")

        print_safe("source root: %s" % root)
        print_safe("staging directory: %s" % staging)
        print_safe("evidence directory: %s" % evidence_dir)
        if evidence["import_stage"] is not None:
            import_stage = evidence["import_stage"]
            print_safe("import: %s (attempts=%d, retry_used=%s)"
                       % ("passed" if import_stage["passed"] else "failed",
                          len(import_stage["attempts"]),
                          import_stage["retry_used"]))
        if evidence["suite_stage"] is not None:
            suite_summary = evidence["suite_stage"]
            print_safe("suite: %s%s"
                       % (suite_summary["suite_marker_line"] or "marker missing",
                          " (exit=%s)" % suite_summary["exit_code"]
                          if suite_summary["exit_code"] is not None else ""))

        if failures:
            for reason in failures:
                print_safe("isolated delivery check: " + reason)
            print_safe(FAILED_MARKER)
            return 1

        print_safe(PASSED_MARKER)
        return 0
    except Exception as exc:  # fail closed with a clear reason
        failures.append("unexpected error: %r" % exc)
        evidence["conclusion"] = "failed"
        evidence["finished_at"] = utc_now()
        if evidence_dir is not None and evidence_dir.is_dir():
            try:
                (evidence_dir / "evidence.json").write_text(
                    json.dumps(evidence, indent=2, ensure_ascii=False),
                    encoding="utf-8")
            except Exception:
                pass
        if staging is not None:
            print_safe("staging directory: %s" % staging)
        for reason in failures:
            print_safe("isolated delivery check: " + reason)
        print_safe(FAILED_MARKER)
        return 1


if __name__ == "__main__":
    sys.exit(main())
