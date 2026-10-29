#!/usr/bin/env python3
"""Grader for json-agg-opt.

Builds the agent's program and a pristine baseline (from tests/baseline_agg.c),
checks output equality on a correctness battery, then measures wall-clock
speedup on a large input and maps it to a score.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = Path("/app/agg")
BUILD = Path("/tmp/aggbuild")
REWARD = Path("/logs/verifier/reward.txt")

CORRECTNESS_CASES = [
    # (name, argv-for-gen) ; argv passed to gen_input.py
    ("empty",            ["0", "1", "1", "1"]),
    ("one_record",       ["1", "1", "1", "2"]),
    ("dup_keys",         ["2000", "3", "2", "3"]),
    ("many_users",       ["5000", "800", "40", "4"]),
    ("blanks",           ["3000", "50", "10", "5", "1"]),
    ("no_trailing_nl",   ["1500", "20", "8", "6", "0", "1"]),
    ("big_bytes",        ["4000", "10", "5", "7"]),
    ("single_user",      ["3000", "1", "6", "8"]),
    ("single_action",    ["3000", "25", "1", "9"]),
]

PERF_INPUT = ["400000", "2000", "60", "100"]  # large, many distinct keys
PERF_RUNS = 3


def write_reward(x: float) -> None:
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    REWARD.write_text(f"{x:.6f}\n")
    print(f"reward {x:.6f}")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def gen(args) -> bytes:
    r = run([sys.executable, str(HERE / "gen_input.py"), *args], timeout=120)
    return r.stdout


def build_agent() -> Path | None:
    binp = APP / "agg"
    try:
        if binp.exists():
            binp.unlink()
    except Exception:
        pass
    if not APP.is_dir():
        print("no /app/agg"); return None
    r = run(["make", "-C", str(APP)], timeout=300)
    print("agent make rc", r.returncode)
    if r.stderr:
        sys.stderr.write(r.stderr.decode(errors="replace")[-1500:])
    if not binp.is_file() or not os.access(binp, os.X_OK):
        print("agent build produced no ./agg"); return None
    return binp


def build_baseline() -> Path | None:
    BUILD.mkdir(parents=True, exist_ok=True)
    out = BUILD / "baseline"
    r = run(["cc", "-O2", "-std=c11", "-o", str(out), str(HERE / "baseline_agg.c")], timeout=300)
    if r.returncode != 0:
        sys.stderr.write(r.stderr.decode(errors="replace")); return None
    return out


def output_of(binp: Path, data: bytes) -> tuple[int, bytes]:
    r = subprocess.run([str(binp)], input=data, capture_output=True, timeout=600)
    return r.returncode, r.stdout


def best_time(binp: Path, data: bytes, runs: int) -> float:
    best = float("inf")
    for _ in range(runs):
        t0 = time.perf_counter()
        subprocess.run([str(binp)], input=data, capture_output=True, timeout=600)
        best = min(best, time.perf_counter() - t0)
    return best


def main() -> int:
    agent = build_agent()
    baseline = build_baseline()
    if baseline is None:
        print("FATAL: baseline failed to build"); write_reward(0.0); return 0
    if agent is None:
        write_reward(0.0); return 0

    # Correctness gate
    for name, args in CORRECTNESS_CASES:
        data = gen(args)
        try:
            arc, aout = output_of(agent, data)
        except subprocess.TimeoutExpired:
            print(f"correctness[{name}]: agent TIMEOUT"); write_reward(0.0); return 0
        brc, bout = output_of(baseline, data)
        if arc != 0:
            print(f"correctness[{name}]: agent exit {arc}"); write_reward(0.0); return 0
        if aout != bout:
            print(f"correctness[{name}]: MISMATCH ({len(aout)} vs {len(bout)} bytes)")
            write_reward(0.0); return 0
        print(f"correctness[{name}]: ok")

    # Speed
    perf = gen(PERF_INPUT)
    # verify correctness on the perf input too
    _, ap = output_of(agent, perf)
    _, bp = output_of(baseline, perf)
    if ap != bp:
        print("perf-input correctness MISMATCH"); write_reward(0.0); return 0
    bt = best_time(baseline, perf, PERF_RUNS)
    at = best_time(agent, perf, PERF_RUNS)
    speedup = bt / at if at > 0 else 0.0
    print(f"baseline {bt:.4f}s  agent {at:.4f}s  speedup {speedup:.2f}x")

    if speedup >= 8.0:
        score = 1.0
    elif speedup >= 4.0:
        score = 0.7
    elif speedup >= 2.0:
        score = 0.4
    else:
        score = 0.0
    try:
        (REWARD.parent / "detail.json").write_text(json.dumps(
            {"baseline_s": bt, "agent_s": at, "speedup": speedup, "score": score}, indent=2))
    except Exception:
        pass
    write_reward(score)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
