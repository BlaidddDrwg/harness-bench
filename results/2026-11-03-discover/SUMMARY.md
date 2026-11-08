# Tool discovery (`discover`), 2026-11-03

**Setup:** two models, three runs each, five harnesses, plus Hermes with tool search
turned off (`hermes-nosearch`). Same as the 2026-11-02 runs otherwise: Ollama, 80k
context, flash attention, 8-bit KV cache, GTX 1080 Ti (11 GB), sandboxed, auto-approve.
The `ollama ps` log ([ollama-ps.log](ollama-ps.log)) shows both models 100% on the GPU at
81,920 tokens throughout (qwen3.5:9b 7.3 GB, gemma4:latest 3.6 GB).

The task connects a fake warehouse MCP server with 30 tools to the harness and asks for
the stock of one part, without naming the tool. See the README ("Tool discovery") for the
task and pass rule. Raw lines: [../2026-11-03-discover.progress](../2026-11-03-discover.progress).

## Result

**34 of 36 runs passed.** Every harness found and used `inventory_on_hand` on both
models, and none called the stock-changing decoy `inventory_adjust`. The two failures
were Claude Code on gemma4.

## Harness × model (averages of 3 runs)

"Input" is the total prompt tokens over all model calls in the run; "peak" is the
largest single prompt.

| Harness | Model | Passed | Time | Model calls | Peak prompt | Input total | Output |
|---|---|---|---|---|---|---|---|
| Goose | qwen3.5:9b | 3/3 | 16 s | 4 | 6.6k | **20.1k** | 0.2k |
| Goose | gemma4 | 3/3 | 22 s | 4 | 5.7k | **17.4k** | 0.8k |
| Codex | qwen3.5:9b | 3/3 | **14 s** | 3 | 12.9k | 38.3k | 0.3k |
| Codex | gemma4 | 3/3 | 24 s | 3 | 13.6k | 40.1k | 0.5k |
| OpenCode | qwen3.5:9b | 3/3 | 164 s | 4 | 10.0k | 30.4k | 6.6k |
| OpenCode | gemma4 | 3/3 | 34 s | 4 | 9.1k | 27.8k | 1.3k |
| Hermes (search on) | qwen3.5:9b | 3/3 | 38 s | 6 (5–8) | 15.9k | 82.3k (61–109k) | 0.5k |
| Hermes (search on) | gemma4 | 3/3 | 48 s | 5 | 15.1k | 58.7k | 1.0k |
| Hermes (search off) | qwen3.5:9b | 3/3 | 31 s | 4 | 21.6k | 64.5k | 0.3k |
| Hermes (search off) | gemma4 | 3/3 | 39 s | 4 | 20.7k | 61.5k | 0.5k |
| Claude Code | qwen3.5:9b | 3/3 | 61 s | 7 (4–13) | 13.0k | 80.5k (47–148k) | 0.8k |
| Claude Code | gemma4 | **1/3** | 35 s | 4 | 12.4k | 47.6k | 1.1k |

Each harness's runs were very consistent except Claude Code and Hermes with search on,
on qwen (ranges shown).

## Findings

- **Goose is the most efficient by far:** about half Codex's input and a quarter of
  Claude Code's or Hermes's, on both models, with no failures on this task.
- **Codex is the fastest** on qwen (14 s) and second-leanest.
- **OpenCode is lean in tokens but slow on qwen** because qwen's thinking mode produces
  5–8k of output per run. On gemma4 it thinks far less and is 5x faster.
- **Hermes tool search: smaller prompts, not fewer tokens.** With 30 MCP tools, search
  cuts each prompt by about 5.7k tokens (15.9k vs 21.6k on qwen), but the model needs
  1–4 extra calls to search, describe and then call the tool. Net, total input was about
  the same (gemma4: 58.7k vs 61.5k) or higher (qwen: 82.3k vs 64.5k), and runs took
  7–9 s longer. Search pays off when tool definitions would otherwise not fit the window,
  or when there are many more tools than here; at this size it is roughly break-even.
- **Two harnesses defer tools; three do not.** Adding the 30 tools grew the first prompt
  by about 2.5–3k tokens for Codex, OpenCode and Goose (every definition sent in full),
  by 1.7k for Hermes (search on; 8.2k with it off), and by only 0.3k for Claude Code,
  which lists MCP tools by name and loads them through its `ToolSearch` tool. Checked by
  capturing a request: Claude Code `-p` against a local server sends 12 tools in full
  and defers the rest; with `ENABLE_TOOL_SEARCH=false` it sends 53. Interactive mode
  does the same (see `../2026-11-04-claude-interactive-toolsearch/`). On qwen, one Claude
  Code run looped to 13 calls and 148k input.
- **Claude Code + gemma4 failed 2 of 3 runs the same way:** the stock lookup returned
  "no part", then a catalog search returned nothing, and it wrote `0` to `stock.txt`
  ("Assuming that 'no records found' means zero units are in stock"). The check shows
  the lookup was not made with sku `HX-4471`, so the arguments were wrong. The exact
  arguments were not kept (the call log was overwritten by the next run; `run.sh` now
  saves it per run). Writing a guess presented as a fact is the kind of failure the
  `honest` task looks for.
- **Models:** gemma4 is half qwen's size on the GPU and matched it everywhere except
  Claude Code. Neither model chose a decoy tool.

## Limits

One task, three runs per cell, one GPU. The fake server has 30 small tools; a real setup
with several MCP servers would have more and larger definitions, which favours search.
Auto-approve throughout.
