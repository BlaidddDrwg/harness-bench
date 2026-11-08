#!/bin/bash
# Interactive locallama + warehouse MCP through the recording proxy.
# Usage: itest.sh LABEL [EXTRA_ENV...]   e.g. itest.sh off1 ENABLE_TOOL_SEARCH=false
S="${SCRATCH:?set SCRATCH to a work folder}"
B=$HOME/Projects/AI/harness-bench
L=$1; shift
W=$B/runs/itest-$L
rm -rf "$W" "$S/rec_$L" "$S/$L.mcp.jsonl"; mkdir -p "$W"
cat > "$S/$L.mcp.json" <<EOF
{"mcpServers":{"warehouse":{"command":"python3","args":["-I","$B/warehouse_mcp.py","$S/$L.mcp.jsonl"]}}}
EOF
pkill -f "recproxy.py" ; sleep 0.5
nohup python3 -I "$S/recproxy.py" "$S/rec_$L" 11498 >"$S/recproxy.err" 2>&1 &
PX=$!; sleep 1
P="In $W, find out how many units of part HX-4471 are in stock right now at the Reno warehouse, using the company's warehouse system, and write just the number into stock.txt."
EXTRA="$*"
start=$(date +%s)
cd "$W"
PTY_START=25 PTY_WAIT=${PTY_WAIT:-300} PTY_INPUT="$P" timeout 450 python3 -I "$S/pty_drive3.py" \
  "unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SSE_PORT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_EXECPATH CLAUDE_PID CLAUDE_CODE_SESSION_ATTENDED CLAUDE_EFFORT; cd '$W'; ${EXTRA:+export $EXTRA;} OLLAMA_HOST=127.0.0.1:11498 locallama --mcp-config '$S/$L.mcp.json' --allowedTools mcp__warehouse,Write,Read" \
  "$S/$L.out.txt"
kill $PX
python3 -I - "$S/rec_$L/log.jsonl" "$W/stock.txt" "$S/$L.mcp.jsonl" "$L" <<'EOF'
import json, sys, os, glob, re
log, stock, mcp, label = sys.argv[1:5]
rows = [json.loads(l) for l in open(log)] if os.path.exists(log) else []
d = os.path.dirname(log)
toks = []
for e in rows:
    resp = open(f"{d}/resp-{e['n']}.txt", errors="replace").read()
    ins = [int(x) for x in re.findall(r'"input_tokens":\s*(\d+)', resp)]
    toks.append(max(ins) if ins else 0)
calls = [json.loads(l) for l in open(mcp)] if os.path.exists(mcp) else []
calls = [(c["tool"], c["args"].get("sku")) for c in calls if c["event"] == "call"]
val = open(stock).read().strip() if os.path.exists(stock) else None
print(json.dumps({
    "label": label, "stock": val, "pass": val == "3817" and ("inventory_on_hand", "HX-4471") in calls,
    "reqs": len(rows), "statuses": sorted({e["status"] for e in rows}),
    "first_prompt": toks[0] if toks else None, "peak": max(toks or [0]), "total_in": sum(toks),
    "tools_sent_first": rows[0]["tools"] if rows else None,
    "toolsearch_offered": rows[0]["toolsearch"] if rows else None,
    "model_calls": [c for e in rows for c in (e["called"] or [])],
    "mcp_calls": calls}))
EOF
