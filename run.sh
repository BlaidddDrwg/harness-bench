#!/usr/bin/env bash
# Run every task through one harness, inside the sandbox, and score it.
#
# Usage: run.sh HARNESS MODEL [TASK...]
#   HARNESS: claude | codex | opencode | goose | hermes
#   TASK:    optional subset of tasks (default: all, see `tasks.py list`)
#
# Each harness gets a fresh fake home folder (state/home-HARNESS) holding only the config
# needed to reach the local model, and auto-approves its own tool calls. Containment comes
# from sandbox.sh, which is the same for every harness.
# Results: results/latest/HARNESS.tsv, plus per-task .log and .tokens files.
set -u
B="$(cd "$(dirname "$0")" && pwd)"
H="$1"; M="$2"; shift 2
TASKS=("$@"); [ ${#TASKS[@]} -eq 0 ] && read -r -a TASKS <<< "$(python3 -I "$B/tasks.py" list)"
RUNS="$B/runs/$H"; OUT="$B/results/latest"; FH="$B/state/home-$H"
SOCK="$B/state/sock/relay.sock"; PROXY="http://127.0.0.1:11435"
mkdir -p "$RUNS" "$OUT" "$(dirname "$SOCK")"
: > "$OUT/$H.tsv"

# --- Start the token relay and the socket bridge into the sandbox, if not running.
if ! curl -s -m 2 "$PROXY/api/version" >/dev/null; then
  nohup python3 -I "$B/tokenproxy.py" "$B/tokens.jsonl" 11435 >"$B/state/proxy.err" 2>&1 &
  sleep 1
elif ! ps -eo args | grep -q "^python3 -I .*tokenproxy.py $B/tokens.jsonl"; then
  echo "Port 11435 is in use by something other than this project's relay; stop it first." >&2
  exit 1
fi
if [ ! -S "$SOCK" ]; then
  nohup socat UNIX-LISTEN:"$SOCK",fork TCP:127.0.0.1:11435 >"$B/state/bridge.err" 2>&1 &
  sleep 1
fi

# --- Fresh fake home with only the settings needed to reach the local model.
rm -rf "$FH"; mkdir -p "$FH"
case "$H" in
  opencode)
    mkdir -p "$FH/.config/opencode"
    cat > "$FH/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "share": "disabled",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Ollama via relay",
      "options": {"baseURL": "$PROXY/v1"},
      "models": {"$M": {"name": "$M", "tools": true}}
    }
  },
  "model": "local/$M",
  "permission": {"edit": "allow", "bash": "allow", "webfetch": "allow"}
}
EOF
    ;;
  hermes)
    mkdir -p "$FH/.hermes"
    # Hermes needs a writable copy of its dependency environment (it takes lock files there).
    cp -a --reflink=auto "$HOME/.hermes/installs" "$FH/.hermes/installs"
    cat > "$FH/.hermes/config.yaml" <<EOF
model:
  default: "$M"
  provider: "custom"
  base_url: "$PROXY/v1"
EOF
    ;;
esac

# --- One non-interactive agent run in the current folder. Prompt is $1.
agent_cmd() {
  case "$H" in
    claude)
      env ANTHROPIC_BASE_URL=$PROXY ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY= \
        CLAUDE_CODE_AUTO_MODE_SERVER=0 ANTHROPIC_MODEL="$M" ANTHROPIC_DEFAULT_OPUS_MODEL="$M" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$M" ANTHROPIC_DEFAULT_HAIKU_MODEL="$M" \
        ANTHROPIC_SMALL_FAST_MODEL="$M" CLAUDE_CODE_SUBAGENT_MODEL="$M" \
        claude -p "$1" --model "$M" --permission-mode bypassPermissions ;;
    codex)
      env CODEX_OSS_BASE_URL=$PROXY/v1 codex exec --oss --local-provider ollama -m "$M" \
        --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "$1" ;;
    opencode)
      opencode run --model "local/$M" "$1" ;;
    goose)
      env GOOSE_PROVIDER=ollama GOOSE_MODEL="$M" OLLAMA_HOST=$PROXY GOOSE_MODE=auto \
        GOOSE_DISABLE_KEYRING=1 goose run --no-session --with-builtin developer -t "$1" ;;
    hermes)
      hermes -z "$1" --yolo ;;
  esac
}

for t in "${TASKS[@]}"; do
  w="$RUNS/$t"
  python3 -I "$B/tasks.py" setup "$w" "$t"
  prompt="$(python3 -I "$B/tasks.py" prompt "$w" "$t")"
  : > "$B/tokens.jsonl"
  start=$(date +%s)
  # The sandbox can write only to $RUNS (so a canary in the parent folder is detectable).
  timeout 900 "$B/sandbox.sh" "$FH" "$RUNS" "$SOCK" -- bash -c \
    "cd '$w' && $(declare -f agent_cmd) && H='$H' M='$M' PROXY='$PROXY' agent_cmd \"\$0\"" \
    "$prompt" > "$OUT/$H-$t.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  cp "$B/tokens.jsonl" "$OUT/$H-$t.tokens"
  read -r reqs peak < <(python3 -I -c '
import json, sys
r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
p = [x["prompt_tokens"] for x in r if x["prompt_tokens"]]  # model calls only
print(len(p), max(p) if p else 0)' "$B/tokens.jsonl")
  verdict="$(python3 -I "$B/tasks.py" check "$w" "$t")"
  [ $rc -eq 124 ] && verdict="$verdict [timed out]"
  printf '%s\t%ss\treqs=%s\tpeak_ctx=%s\trc=%s\n' "$verdict" "$secs" "$reqs" "$peak" "$rc" \
    | tee -a "$OUT/$H.tsv"
done
