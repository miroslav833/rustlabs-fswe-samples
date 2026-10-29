#!/usr/bin/env python3
"""Deterministic input generators for grading. Standard library only."""
import random
import sys


def gen(n, n_users, n_actions, seed, blanks=False):
    rng = random.Random(seed)
    users = [f"user_{i:04d}" for i in range(n_users)]
    actions = [f"act-{i}" for i in range(n_actions)]
    out = []
    for i in range(n):
        if blanks and i % 997 == 0:
            out.append("")
            continue
        u = rng.choice(users)
        a = rng.choice(actions)
        b = rng.randint(0, 1_000_000)
        ts = 1_600_000_000 + i
        out.append(f'{{"ts": {ts}, "user": "{u}", "action": "{a}", "bytes": {b}}}')
    return "\n".join(out)


if __name__ == "__main__":
    # args: n n_users n_actions seed [blanks] [no_trailing_newline]
    n = int(sys.argv[1]); nu = int(sys.argv[2]); na = int(sys.argv[3]); seed = int(sys.argv[4])
    blanks = len(sys.argv) > 5 and sys.argv[5] == "1"
    no_nl = len(sys.argv) > 6 and sys.argv[6] == "1"
    s = gen(n, nu, na, seed, blanks)
    sys.stdout.write(s if no_nl else (s + "\n"))
