# rustLabs FrontierSWE sample tasks

Three self-contained Harbor tasks in the FrontierSWE format: two long-horizon
software-engineering tasks and one web-security red-team task. Each task is one
folder under `tasks/`, with `instruction.md`, `task.toml`, `environment/`, a
verifier under `tests/`, and a reference solution at `solution/solve.sh`.

Every task has been verified locally:

- the rustLabs checker (`tools/frontierswe-check.py`) ends `FSWE-CHECK v1 PASS`
- `harbor run -a oracle` scores Mean 1.000
- `harbor run -a nop` scores Mean 0.000

See `SUBMISSION.md` for the per-task write-up, scores and checker fingerprints.

## Tasks

| Folder | Kind |
|---|---|
| `tasks/regex-engine-c` | SWE — implement a regex engine in C |
| `tasks/json-agg-opt` | SWE — optimize a C log aggregator |
| `tasks/web-authz-exploit` | Security — web authorization bypass |

## Reproduce

```bash
python3 tools/frontierswe-check.py tasks/<task>
harbor run -p tasks/<task> -a oracle
harbor run -p tasks/<task> -a nop
```
