# Claude Code tool search in interactive mode against Ollama, 2026-11-04

**Question:** does interactive Claude Code (`locallama`, i.e. `ollama launch claude` with
the local settings) use its tool search with a local model, the way `claude -p` did in the
`discover` runs?

**Answer: yes, by default.** No setting is needed. Claude Code's debug log shows
`[ToolSearch:optimistic] mode=tst, ENABLE_TOOL_SEARCH=undefined, result=true`, and Ollama
0.40.13 accepts the requests (every request returned 200).

## Method

`itest.sh` runs the real `locallama` shell function in a pseudo-terminal (`pty_drive3.py`),
with `OLLAMA_HOST` pointed at `recproxy.py`, a relay to Ollama that saves every request and
reply. The warehouse MCP server (`warehouse_mcp.py`, 30 tools) is added with `--mcp-config`
on top of the normal locallama plugins (so Playwright's 25 MCP tools are present too). The
prompt is the `discover` task. Model qwen3.5:9b, 80k context. Three runs with defaults, two
with `ENABLE_TOOL_SEARCH=false`. Raw: [results.jsonl](results.jsonl).

## Result

| | Tool search on (default) | Tool search off |
|---|---|---|
| Passed | 3/3 | 2/2 |
| Tools sent in full | 13 | 85 |
| MCP tools | listed by name only (55) | all in full |
| First prompt | **17.7k tokens** | 34.3k tokens |
| Model calls | 4 (ToolSearch, lookup, Write, reply) | 3 (lookup, Write, reply) |
| Total input per run | **71.7k** | 103.2k |

Tool search halves the prompt and saves about 31k input tokens per run here, at the cost of
one extra call. With fewer MCP tools connected the saving is smaller.

## Correction to an earlier finding

On 2026-11-03 I reported that Claude Code never turns tool search on with a non-Anthropic
base URL and that interactive locallama sends 55 tools in full. That came from the
measurement: the capture server answered every request with HTTP 400 and kept only the
last request. Claude Code's first request did use deferred tools; on the 400 it retried
without them (it does this by design), and the retry was what got saved. Measured through a
relay to the real Ollama, tool search is on.
