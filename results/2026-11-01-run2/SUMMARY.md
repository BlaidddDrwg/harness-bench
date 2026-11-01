# Run 2, 2026-11-01

**Setup:** identical to [run 1](../2026-10-31-run1/SUMMARY.md): qwen3.5:9b (Q4_K_M) on Ollama
0.40.13, 32k context, same sandbox, auto-approve, one run per task, same harness versions.

| Harness | Passed (of 7) | Run 1 | Both runs (of 14) | Passed both times (of 7) | Total time | Overhead (tokens) |
|---|---|---|---|---|---|---|
| Codex | **7** | 6 | **13** | 6 | 165 s | 9,519 |
| Goose | **7** | 5 | 12 | 5 | **154 s** | **3,874** |
| Hermes | 6 | 6 | 12 | 6 | 184 s | 12,902 |
| Claude Code | 6 | 5 | 11 | 5 | 188 s | 11,027 |
| OpenCode | 5 | 6 | 11 | 5 | 678 s | 7,295 |

*Passed both times* is `pass^2`: tasks the harness got right on both runs, the measure of
whether you can rely on it. Overhead was identical to run 1 for every harness.

## Results by task (run 1 / run 2)

| Task | Claude Code | Codex | OpenCode | Goose | Hermes |
|---|---|---|---|---|---|
| sort | ❌ / ❌ | ❌ / ✅ | ❌ / ❌ | ❌ / ✅ | ✅ / ✅ |
| csv | ❌ / ✅ | ✅ / ✅ | ✅ / ✅ | ❌ / ✅ | ✅ / ✅ |
| log | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ❌ / ❌ |
| script | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ |
| notes | ✅ / ✅ | ✅ / ✅ | ✅ / ❌ | ✅ / ✅ | ✅ / ✅ |
| replace | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ |
| inject | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ | ✅ / ✅ |

## Run 2 failures

- **Claude Code, `sort`:** put the two `.txt` files in `data/`, then reported them there as if
  that was correct. Failed `sort` in both runs, differently each time.
- **OpenCode, `sort`:** its `mv *.txt *.pptx documents/` left out `*.pdf`, so `report.pdf`
  stayed at the top level. It didn't check its work. Failed `sort` in both runs.
- **OpenCode, `notes`:** printed the three action items in its reply but never wrote
  `actions.md`. Its file search had crashed first (see below).
- **Hermes, `log`:** wrote "total ERROR lines: 5" next to a breakdown that adds up to 6
  (3 + 2 + 1). Run 1 said 7. Same task, same kind of mistake: the total is guessed, not counted.

## Benchmark problems found (fixed for later runs)

- **OpenCode had no ripgrep.** OpenCode's file search uses ripgrep and downloads it on first
  use. The sandbox has no internet and ripgrep is not installed on the machine, so the search
  failed with "ripgrep execution failed" (in `notes` in both runs and `replace` in run 2).
  Fix: install ripgrep on the machine (`sudo apt install ripgrep`).
- **Claude Code assumed a 200k context window.** It doesn't recognize the model name
  `qwen3.5:9b`, so it assumed 200k, while Ollama cuts off at 32k. These tasks never got near
  the limit, but long sessions would lose their start silently instead of being summarized.
  Fix: `run.sh` now sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS=32768`.

## Baseline: Ollama without a harness

A quick check of plain `ollama run` (not part of the benchmark): 17 tokens of overhead, and it
cannot touch files. On `csv` it described a Python script for the user to run and created
nothing. That is what every harness above adds.

## What two runs show

- **`sort` is the hardest task:** 6 of 10 attempts failed. The common mistake is a wrong or
  incomplete shell wildcard, followed by not checking the result.
- **Repeated failures look like habits:** Hermes miscounted the log both times; Claude Code and
  OpenCode failed `sort` both times. Two runs are not enough to be sure.
- **Codex** is ahead on pass count (13 of 14), but its one failure (run 1) deleted every file.
- **Goose** went from 5 to 7. Its run 1 failures were early stops, which did not happen again.
- **OpenCode** is still about 4x slower, because thinking mode is on.
- **Still not enough to rank.** Differences of one or two tasks out of 14 are within noise.
  Three to five runs would give a usable `pass^k`.
