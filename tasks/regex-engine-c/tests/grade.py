#!/usr/bin/env python3
"""Grader for regex-engine-c. Builds the agent's engine, runs the hidden
cases, and writes the fraction of correct exit codes to the reward file."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cases  # noqa: E402
import expected  # noqa: E402

APP = Path("/app/regex")
PER_CASE_TIMEOUT = 5.0


def reward_path() -> Path:
    d = Path("/logs/verifier")
    if d.is_dir() or True:
        try:
            d.mkdir(parents=True, exist_ok=True)
            return d / "reward.txt"
        except Exception:
            pass
    return HERE / "reward.txt"


def write_reward(score: float) -> None:
    p = reward_path()
    p.write_text(f"{score:.6f}\n")
    print(f"reward {score:.6f} -> {p}")


def build() -> Path | None:
    """make in /app/regex, expect ./rgx. Never trust a pre-existing binary:
    remove it first so a stale/committed rgx cannot stand in for a build."""
    rgx = APP / "rgx"
    try:
        if rgx.exists():
            rgx.unlink()
    except Exception:
        pass
    if not APP.is_dir():
        print("no /app/regex directory")
        return None
    try:
        r = subprocess.run(
            ["make", "-C", str(APP)],
            capture_output=True, text=True, timeout=300,
        )
        print("make rc:", r.returncode)
        if r.stdout:
            print(r.stdout[-2000:])
        if r.stderr:
            print(r.stderr[-2000:], file=sys.stderr)
    except Exception as e:  # noqa: BLE001
        print(f"build failed: {e}")
        return None
    if not rgx.is_file() or not os.access(rgx, os.X_OK):
        print("build did not produce an executable ./rgx")
        return None
    return rgx


def run_case(rgx: Path, pat: str, s: str) -> int | None:
    try:
        r = subprocess.run(
            [str(rgx), pat, s],
            capture_output=True, text=True, timeout=PER_CASE_TIMEOUT,
        )
        return r.returncode
    except subprocess.TimeoutExpired:
        return None
    except Exception:  # noqa: BLE001
        return None


def main() -> int:
    total = len(cases.CASES)
    rgx = build()
    if rgx is None:
        write_reward(0.0)
        return 0
    correct = 0
    details = []
    for pat, s in cases.CASES:
        want = expected.expected_exit(pat, s)
        got = run_case(rgx, pat, s)
        # Only exit codes 0,1,2 are meaningful; any other (incl. crash/timeout)
        # cannot be correct.
        ok = (got == want)
        if ok:
            correct += 1
        details.append({"pattern": pat, "string": s, "want": want, "got": got, "ok": ok})
    score = correct / total if total else 0.0
    print(f"correct {correct}/{total}")
    try:
        (Path("/logs/verifier") / "detail.json").write_text(json.dumps(details, indent=2))
    except Exception:
        pass
    write_reward(score)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
