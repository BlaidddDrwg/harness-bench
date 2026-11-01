#!/usr/bin/env bash
# Run every task through one harness and score it.
# Usage: run.sh HARNESS MODEL   (HARNESS: claude | codex | opencode | goose | hermes)
# Results go to results/latest/HARNESS.tsv; token use per request to
# results/latest/HARNESS-TASK.tokens. Needs tokenproxy.py running on port 11435.
set -u
B="$(cd "$(dirname "$0")" && pwd)"
H="$1"; M="$2"
RUNS="$B/runs/$H"; OUT="$B/results/latest"; mkdir -p "$RUNS" "$OUT" "$B/state/claude-config"
PROXY="http://127.0.0.1:11435"
: > "$OUT/$H.tsv"

run_agent() {  # $1 = workdir, $2 = prompt
  local w="$1" p="$2"
  cd "$w" || return 1
  case "$H" in
    claude)
      # A clean config dir keeps the user's own CLAUDE.md, plugins and MCP servers out of the test.
      CLAUDE_CONFIG_DIR="$B/state/claude-config" ANTHROPIC_BASE_URL=$PROXY ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY= \
      CLAUDE_CODE_AUTO_MODE_SERVER=0 ANTHROPIC_MODEL=$M ANTHROPIC_DEFAULT_OPUS_MODEL=$M \
      ANTHROPIC_DEFAULT_SONNET_MODEL=$M ANTHROPIC_DEFAULT_HAIKU_MODEL=$M \
      ANTHROPIC_SMALL_FAST_MODEL=$M CLAUDE_CODE_SUBAGENT_MODEL=$M \
      claude -p "$p" --model "$M" --permission-mode acceptEdits \
        --settings '{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true}}' ;;
    codex)
      CODEX_OSS_BASE_URL=$PROXY/v1 codex exec --oss --local-provider ollama -m "$M" \
        --skip-git-repo-check -s workspace-write -C "$w" "$p" ;;
    opencode)
      opencode run --model "ollama-proxy/$M" "$p" ;;
    goose)
      OLLAMA_HOST=$PROXY GOOSE_PROVIDER=ollama GOOSE_MODEL="$M" goose run --no-session -t "$p" ;;
    hermes)
      hermes chat -q "$p" ;;
  esac
}

for t in $(python3 -I "$B/tasks.py" list); do
  w="$RUNS/$t"
  python3 -I "$B/tasks.py" setup "$w" "$t"
  prompt="$(python3 -I "$B/tasks.py" prompt "$w" "$t")"
  : > "$B/tokens.jsonl"
  start=$(date +%s)
  timeout 900 bash -c "$(declare -f run_agent); B='$B' H='$H' M='$M' PROXY='$PROXY' run_agent '$w' \"\$0\"" "$prompt" \
    > "$OUT/$H-$t.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  cp "$B/tokens.jsonl" "$OUT/$H-$t.tokens"
  read -r reqs peak < <(python3 -I -c '
import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
p=[x["prompt_tokens"] for x in r if x["prompt_tokens"]]
print(len(r), max(p) if p else 0)' "$B/tokens.jsonl")
  verdict="$(python3 -I "$B/tasks.py" check "$w" "$t")"
  [ $rc -eq 124 ] && verdict="${verdict/PASS/PASS(late)}	[timed out]"
  printf '%s\t%ss\treqs=%s\tpeak_ctx=%s\n' "$verdict" "$secs" "$reqs" "$peak" | tee -a "$OUT/$H.tsv"
done
