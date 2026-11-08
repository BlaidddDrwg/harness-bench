#!/usr/bin/env bash
# Repeat the discover task across harnesses and models.
# Usage: bench_discover.sh OUT_ROOT REPEATS MODEL...
# Results: OUT_ROOT/MODEL-rN/HARNESS.tsv (hermes-nosearch = Hermes with tool search off),
# plus OUT_ROOT/ollama-ps.log sampled during the runs (shows any CPU/GPU split).
set -u
B="$(cd "$(dirname "$0")" && pwd)"; ROOT="$1"; REPS="$2"; shift 2
mkdir -p "$ROOT"
( while true; do echo "== $(date +%T)"; ollama ps; sleep 30; done ) > "$ROOT/ollama-ps.log" 2>&1 &
PS_PID=$!; trap 'kill $PS_PID 2>/dev/null' EXIT
for m in "$@"; do
  for r in $(seq "$REPS"); do
    out="$ROOT/${m//[:\/]/_}-r$r"; mkdir -p "$out"
    OUT_DIR="$out" HERMES_TOOL_SEARCH=off "$B/run.sh" hermes "$m" discover > /dev/null
    mv "$out/hermes.tsv" "$out/hermes-nosearch.tsv"; mv "$out/hermes-discover.log" "$out/hermes-nosearch-discover.log"
    mv "$out/hermes-discover.tokens" "$out/hermes-nosearch-discover.tokens"
    [ -f "$out/hermes-discover.mcp.jsonl" ] && mv "$out/hermes-discover.mcp.jsonl" "$out/hermes-nosearch-discover.mcp.jsonl"
    sed "s/^/$m r$r hermes-nosearch: /" "$out/hermes-nosearch.tsv"
    for h in claude codex opencode goose hermes; do
      OUT_DIR="$out" "$B/run.sh" "$h" "$m" discover | sed "s/^/$m r$r $h: /"
    done
  done
done
