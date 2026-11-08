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
# Results: results/latest/HARNESS.tsv (or $OUT_DIR), plus per-task .log and .tokens files.
# Tasks listed by `tasks.py mcp` also get the warehouse MCP server (warehouse_mcp.py).
set -u
B="$(cd "$(dirname "$0")" && pwd)"
H="$1"; M="$2"; shift 2
TASKS=("$@"); [ ${#TASKS[@]} -eq 0 ] && read -r -a TASKS <<< "$(python3 -I "$B/tasks.py" list)"
RUNS="$B/runs/$H"; OUT="${OUT_DIR:-$B/results/latest}"; FH="$B/state/home-$H"
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
rm -rf "$FH"; mkdir -p "$FH/.hb"
# The sandbox hides this project folder, so the MCP server is copied into the fake home.
cp "$B/warehouse_mcp.py" "$FH/.hb/warehouse_mcp.py"
if [ "$H" = hermes ]; then
  # Hermes needs a writable copy of its dependency environment (it takes lock files there).
  mkdir -p "$FH/.hermes"; cp -a --reflink=auto "$HOME/.hermes/installs" "$FH/.hermes/installs"
fi

# Write the harness config for one task. $1 = MCP server log file, or empty for no server.
# Paths are the same inside the sandbox: the fake home is mounted at the real home path.
write_config() {
  local log="$1" srv="$HOME/.hb/warehouse_mcp.py"
  MCP_ARGS=""
  [ -n "$log" ] && MCP_ARGS="python3 -I $srv $log"
  case "$H" in
    claude)
      if [ -n "$log" ]; then
        printf '{"mcpServers": {"warehouse": {"command": "python3", "args": ["-I", "%s", "%s"]}}}\n' \
          "$srv" "$log" > "$FH/.hb/mcp.json"
      else rm -f "$FH/.hb/mcp.json"; fi ;;
    codex)
      mkdir -p "$FH/.codex"
      if [ -n "$log" ]; then
        printf '[mcp_servers.warehouse]\ncommand = "python3"\nargs = ["-I", "%s", "%s"]\n' \
          "$srv" "$log" > "$FH/.codex/config.toml"
      else rm -f "$FH/.codex/config.toml"; fi ;;
    opencode)
      local mcp=""
      [ -n "$log" ] && mcp=',
  "mcp": {"warehouse": {"type": "local", "command": ["python3", "-I", "'"$srv"'", "'"$log"'"], "enabled": true}}'
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
      "models": {"$M": {"name": "$M", "tools": true, "limit": {"context": 81920, "output": 8192}}}
    }
  },
  "model": "local/$M",
  "permission": {"edit": "allow", "bash": "allow", "webfetch": "allow"}$mcp
}
EOF
      ;;
    hermes)
      cat > "$FH/.hermes/config.yaml" <<EOF
model:
  default: "$M"
  provider: "custom"
  base_url: "$PROXY/v1"
EOF
      # HERMES_TOOL_SEARCH=off turns off Hermes's tool search (default: Hermes's own default).
      [ -n "${HERMES_TOOL_SEARCH:-}" ] && printf 'tools:\n  tool_search:\n    enabled: "%s"\n' \
        "$HERMES_TOOL_SEARCH" >> "$FH/.hermes/config.yaml"
      [ -n "$log" ] && cat >> "$FH/.hermes/config.yaml" <<EOF
mcp_servers:
  warehouse:
    command: python3
    args: ["-I", "$srv", "$log"]
EOF
      ;;
  esac
}

# --- One non-interactive agent run in the current folder. Prompt is $1.
agent_cmd() {
  case "$H" in
    claude)
      env ANTHROPIC_BASE_URL=$PROXY ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY= \
        CLAUDE_CODE_MAX_CONTEXT_TOKENS=81920 CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192 \
        CLAUDE_CODE_AUTO_MODE_SERVER=0 ANTHROPIC_MODEL="$M" ANTHROPIC_DEFAULT_OPUS_MODEL="$M" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$M" ANTHROPIC_DEFAULT_HAIKU_MODEL="$M" \
        ANTHROPIC_SMALL_FAST_MODEL="$M" CLAUDE_CODE_SUBAGENT_MODEL="$M" \
        claude -p "$1" --model "$M" --permission-mode bypassPermissions \
          ${MCP_ARGS:+--mcp-config "$HOME/.hb/mcp.json" --strict-mcp-config} ;;
    codex)
      env CODEX_OSS_BASE_URL=$PROXY/v1 codex exec --oss --local-provider ollama -m "$M" \
        --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "$1" ;;
    opencode)
      opencode run --model "local/$M" "$1" ;;
    goose)
      env GOOSE_PROVIDER=ollama GOOSE_MODEL="$M" OLLAMA_HOST=$PROXY GOOSE_MODE=auto \
        GOOSE_DISABLE_KEYRING=1 goose run --no-session --with-builtin developer \
        ${MCP_ARGS:+--with-extension "warehouse:$MCP_ARGS"} -t "$1" ;;
    hermes)
      hermes -z "$1" --yolo ;;
  esac
}

for t in "${TASKS[@]}"; do
  w="$RUNS/$t"
  python3 -I "$B/tasks.py" setup "$w" "$t"
  prompt="$(python3 -I "$B/tasks.py" prompt "$w" "$t")"
  if python3 -I "$B/tasks.py" mcp "$t"; then write_config "$RUNS/$t.mcp.jsonl"; else write_config ""; fi
  : > "$B/tokens.jsonl"
  start=$(date +%s)
  # The sandbox can write only to $RUNS (so a canary in the parent folder is detectable).
  timeout 900 "$B/sandbox.sh" "$FH" "$RUNS" "$SOCK" -- bash -c \
    "cd '$w' && $(declare -f agent_cmd) && H='$H' M='$M' PROXY='$PROXY' MCP_ARGS='$MCP_ARGS' agent_cmd \"\$0\"" \
    "$prompt" > "$OUT/$H-$t.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  cp "$B/tokens.jsonl" "$OUT/$H-$t.tokens"
  [ -f "$RUNS/$t.mcp.jsonl" ] && cp "$RUNS/$t.mcp.jsonl" "$OUT/$H-$t.mcp.jsonl"  # keep the tool-call log
  read -r reqs peak tin tout < <(python3 -I -c '
import json, sys
r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
r = [x for x in r if x["prompt_tokens"]]  # model calls only
p = [x["prompt_tokens"] for x in r]
print(len(p), max(p) if p else 0, sum(p), sum(x["output_tokens"] or 0 for x in r))' "$B/tokens.jsonl")
  verdict="$(python3 -I "$B/tasks.py" check "$w" "$t")"
  [ $rc -eq 124 ] && verdict="$verdict [timed out]"
  printf '%s\t%ss\treqs=%s\tpeak_ctx=%s\tin=%s\tout=%s\trc=%s\n' "$verdict" "$secs" "$reqs" "$peak" "$tin" "$tout" "$rc" \
    | tee -a "$OUT/$H.tsv"
done
