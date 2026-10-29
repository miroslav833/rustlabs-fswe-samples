#!/usr/bin/env bash
set -u
mkdir -p /logs/verifier 2>/dev/null || true
echo 0.0 > /logs/verifier/reward.txt 2>/dev/null || true
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/grade.py"
