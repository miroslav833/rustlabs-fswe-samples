#!/usr/bin/env bash
# Verifier entry point. All logic is in grade.py.
set -u
mkdir -p /logs/verifier 2>/dev/null || true
# Guarantee a reward exists even if python dies unexpectedly.
echo 0.0 > /logs/verifier/reward.txt 2>/dev/null || true
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/grade.py"
