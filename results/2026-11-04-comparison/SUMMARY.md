# Harness comparison, all tests to date (2026-11-04)

Combines [runs 3–5 and the new tasks](../2026-11-02-summary/SUMMARY.md),
[tool discovery](../2026-11-03-discover/SUMMARY.md) and
[Claude Code interactive tool search](../2026-11-04-claude-interactive-toolsearch/RESULTS.md).

**Setup throughout:** Ollama 0.40.13, 80k context, flash attention, 8-bit KV cache,
GTX 1080 Ti (11 GB), model fully on the GPU, sandboxed, auto-approve. Main model
qwen3.5:9b; gemma4:latest on `discover` only. Token figures come from a relay in front of
the real Ollama, which records the prompt size Ollama reports for each request.

## Ranking (qwen3.5:9b)

| Rank | Harness | Original 7 tasks (of 21) | recover + honest (of 4) | discover (of 3) | **Total (of 28)** | discover on gemma4 (of 3) |
|---|---|---|---|---|---|---|
| 1 | **Claude Code** | **21** | 4 | 3 | **28** | 1 |
| 2 | Hermes | 20 | 4 | 3 | 27 | 3 |
| 3 | OpenCode | 19 | 4 | 3 | 26 | 3 |
| 4= | Codex | 16 | 4 | 3 | 23 | 3 |
| 4= | Goose | 17 | 3 | 3 | 23 | 3 |

The new task did not change the order: every harness passed `discover` on qwen. The gap
between the top three and the bottom two (3–5 tasks of 28) is the clearest result; the
order within the top three is not significant. Claude Code's only failures anywhere are
on gemma4, where it twice wrote `0` after a failed lookup instead of saying it could not
find the number.

## How each harness handles tools

This is the part the new information changes. Earlier notes said Claude Code sends every
tool in full to a local server; that came from a faulty measurement and is wrong.

| Harness | Built-in overhead (empty task) | MCP tools | Cost of 30 extra MCP tools | Extra model calls to use one |
|---|---|---|---|---|
| Claude Code | 11.0k | **Deferred by default** (names listed; `ToolSearch` loads one) | **+0.3k** | +1 |
| Hermes | 12.9k | Deferred (`tool_search` / `tool_describe` / `tool_call`, setting `auto`) | +1.7k | +1 to +4 |
| OpenCode | 7.3k | Sent in full | +2.5k | 0 |
| Codex | 9.5k | Sent in full | +3.0k | 0 |
| Goose | **3.9k** | Sent in full | +2.5k | 0 |

What this means in practice:

- **With few MCP tools, the full-send harnesses are cheaper.** On `discover` (30 small
  tools), Goose read 20k tokens per run, Codex 38k and OpenCode 30k, against 81k for
  Claude Code and 82k for Hermes on qwen. Their small built-in overhead outweighs
  deferral, and they need no search step.
- **As MCP tools grow, deferral wins.** Every tool sent in full is paid for on every
  request. The warehouse tools cost about 75 tokens each; real servers are often larger
  (Playwright's 25 tools are about 7k). Claude Code and Hermes pay roughly a name per
  tool instead. *Estimate, not measured:* with 100 such tools, a full-send harness's
  prompt grows by about 7–10k per request, and Claude Code's by about 1k.
- **Measured on a real setup:** interactive `locallama` with Playwright plus the 30
  warehouse tools (55 MCP tools) starts at 17.7k tokens with tool search, 34.3k without
  (`ENABLE_TOOL_SEARCH=false`), and a run read 72k vs 103k tokens.
- **Hermes's search costs more calls than Claude Code's.** Claude Code needed exactly one
  `ToolSearch` call each time; Hermes needed 1–4 (search, sometimes search again, then
  describe, then call). With search off, Hermes read slightly fewer tokens on qwen at this
  tool count.

## Speed and size (qwen3.5:9b)

| Harness | Avg time, original 7 tasks | `discover` time | `discover` tokens read | `discover` largest prompt |
|---|---|---|---|---|
| Codex | **158 s** | **14 s** | 38k | 12.9k |
| Goose | 169 s | 16 s | **20k** | **6.6k** |
| Claude Code | 215 s | 61 s | 81k (47–148k) | 13.0k |
| Hermes | 298 s | 38 s | 82k (61–109k) | 15.9k |
| OpenCode | 753 s | 164 s | 30k | 10.0k |

OpenCode's slowness is qwen's thinking mode (5–8k output tokens per `discover` run); on
gemma4 it ran `discover` in 34 s.

## Which to use

- **Most reliable:** Claude Code (28 of 28 on qwen), then Hermes. Both also scale best to
  many MCP tools.
- **Leanest and fast:** Goose, if you can live with occasional silent stops (it is the
  only harness to fail `honest`, and its 4 misses on the original tasks were mostly
  silent stops).
- **Fastest:** Codex, but it failed `log` in every run.
- **OpenCode:** accurate; turn thinking off or use a model that thinks less.

## Limits

One GPU, mostly one model, 10 small tasks, 2–3 runs each. The 100-tool figure above is an
extrapolation. Auto-approve throughout, so nothing here covers how each harness behaves
when it asks before acting.
