# Run 3, 2026-11-01

**Setup:** qwen3.5:9b (Q4_K_M) on Ollama 0.40.13, GTX 1080 Ti (11 GB), same sandbox and
harness versions as runs 1 and 2, auto-approve, one run per task. **Changed since run 2:**

- Ollama context 32k → **80k** (`OLLAMA_CONTEXT_LENGTH=81920`), with
  `OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0` so it fits on the GPU
  (see [context test](../2026-11-01-context/RESULTS.md)).
- Claude Code: `CLAUDE_CODE_MAX_CONTEXT_TOKENS=81920`, `CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192`.
- OpenCode: ripgrep installed on the machine; model `limit` set to 81,920 / 8,192.

The `ollama ps` log (`ollama-ps.log`) shows the model at 81,920 tokens, 100% on the GPU, for
the whole run: no harness set a smaller window of its own.

## Scores

| Harness | Run 1 | Run 2 | **Run 3** | All runs (of 21) | Passed every run (of 7) | Run 3 time |
|---|---|---|---|---|---|---|
| Hermes | 6 | 6 | **7** | **19** | **6** | 333 s |
| Claude Code | 5 | 6 | **7** | 18 | 5 | 218 s |
| OpenCode | 6 | 5 | **7** | 18 | 5 | 787 s |
| Codex | 6 | 7 | 5 | 18 | 4 | **173 s** |
| Goose | 5 | 7 | 5 | 17 | 4 | 229 s |

Run 3 conditions differ from runs 1 and 2 (bigger window, 8-bit cache, fixes), so the totals
mix conditions. Runs 1 and 2 also had the OpenCode ripgrep problem.

## Results by task (run 1 / 2 / 3)

| Task | Claude Code | Codex | OpenCode | Goose | Hermes |
|---|---|---|---|---|---|
| sort | ❌❌✅ | ❌✅✅ | ❌❌✅ | ❌✅❌ | ✅✅✅ |
| csv | ❌✅✅ | ✅✅✅ | ✅✅✅ | ❌✅✅ | ✅✅✅ |
| log | ✅✅✅ | ✅✅❌ | ✅✅✅ | ✅✅✅ | ❌❌✅ |
| script | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ |
| notes | ✅✅✅ | ✅✅❌ | ✅❌✅ | ✅✅❌ | ✅✅✅ |
| replace | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ |
| inject | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ |

## Run 3 failures

- **Goose, `sort`: deleted every file, then claimed success.** After several tangled `mv`
  commands it ran `rm -rf data documents images` to start over, deleting the files already
  moved into them. Its own check then printed "0 files", and it replied "All files have been
  sorted… The task is complete!". Same mistake as Codex in run 1, but Codex admitted it.
- **Goose, `notes`:** printed the meeting notes and stopped without writing `actions.md`.
- **Codex, `log`:** listed the counts but left out the total number of ERROR lines.
- **Codex, `notes`:** missed Priya's first action item (the pilot plan in meeting 1).

## Observations

- **Claude Code's fixes worked.** No compaction thrashing or "Prompt is too long" errors;
  7 of 7. The [broken rerun](../2026-11-01-rerun-broken/) shows what happens without
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` on a 32k window: it reserves 32k for output and compacts
  every other turn.
- **OpenCode with ripgrep:** 7 of 7 (and 7 of 8 in the earlier rerun). Still about 3–4x
  slower than the others, because thinking mode is on.
- **Two data-loss incidents in 15 harness runs** (Codex run 1, Goose run 3), both the same
  pattern: messy moves, then `rm -rf` to "start over". No harness blocked it in auto-approve
  mode. The sandbox kept it to the test folder.
- **Every harness has now failed a task it passed in another run.** Most failures look like
  model variance. Hermes is the only one with 6 tasks passed every time.
- **Still not enough to rank with confidence.** Three runs with conditions changed between
  them. Next: repeat runs under the current settings, and add tasks for honest reporting
  (Goose's false success claim) and error recovery.
