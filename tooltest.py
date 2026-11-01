"""Direct tool-calling tests against a local Ollama model.

Usage: python3 -I tooltest.py MODEL WORKDIR
Tools only touch files inside WORKDIR.
"""
import json
import pathlib
import sys
import time
import urllib.request

MODEL, WORK = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
URL = "http://localhost:11434/api/chat"

TOOLS = [
    {"type": "function", "function": {
        "name": "list_dir", "description": "List files in a directory",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "read_file", "description": "Read a text file",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "write_file", "description": "Write text to a file, replacing it",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                       "required": ["path", "content"]}}},
    {"type": "function", "function": {
        "name": "get_weather", "description": "Get current weather for a city",
        "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}},
]


def chat(messages):
    body = json.dumps({"model": MODEL, "messages": messages, "tools": TOOLS, "stream": False}).encode()
    req = urllib.request.Request(URL, body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def safe(p):
    q = (WORK / p).resolve() if not pathlib.Path(p).is_absolute() else pathlib.Path(p).resolve()
    if WORK not in q.parents and q != WORK:
        raise ValueError("outside workdir")
    return q


def run_tool(name, args):
    try:
        if name == "list_dir":
            return "\n".join(sorted(x.name for x in safe(args["path"]).iterdir()))
        if name == "read_file":
            return safe(args["path"]).read_text()
        if name == "write_file":
            safe(args["path"]).write_text(args["content"])
            return "ok"
        if name == "get_weather":
            return "15C, cloudy"
    except Exception as e:  # report tool errors back to the model
        return f"error: {e}"
    return "error: unknown tool"


def single(prompt, expect_tool, check):
    t = time.time()
    m = chat([{"role": "user", "content": prompt}])["message"]
    calls = m.get("tool_calls") or []
    got = [(c["function"]["name"], c["function"]["arguments"]) for c in calls]
    if expect_tool is None:
        ok = not calls
    else:
        ok = bool(got) and got[0][0] == expect_tool and check(got[0][1])
    print(f"{'PASS' if ok else 'FAIL'}  {time.time()-t:5.1f}s  {prompt[:60]!r} -> {got or (m.get('content') or '')[:60]!r}")
    return ok


def multistep():
    msgs = [{"role": "user", "content":
             f"In {WORK}, read every .txt file, add up the numbers they contain, "
             f"and write only the total to {WORK}/total.out. Use the tools."}]
    t, steps = time.time(), 0
    for steps in range(1, 16):
        m = chat(msgs)["message"]
        msgs.append(m)
        calls = m.get("tool_calls") or []
        if not calls:
            break
        for c in calls:
            msgs.append({"role": "tool", "tool_name": c["function"]["name"],
                         "content": run_tool(c["function"]["name"], c["function"]["arguments"])})
    out = WORK / "total.out"
    ok = out.exists() and out.read_text().strip() == "60"
    print(f"{'PASS' if ok else 'FAIL'}  {time.time()-t:5.1f}s  multi-step task, {steps} model turns, "
          f"total.out={out.read_text().strip() if out.exists() else None!r}")
    return ok


def speed():
    body = json.dumps({"model": MODEL, "prompt": "Write three sentences about the ocean.",
                       "stream": False, "think": False}).encode()
    req = urllib.request.Request("http://localhost:11434/api/generate", body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
    print(f"speed: {d['eval_count']/(d['eval_duration']/1e9):.1f} tokens/s writing, "
          f"{d['prompt_eval_count']/(d['prompt_eval_duration']/1e9):.1f} tokens/s reading")


if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    for name, val in {"a.txt": "10", "b.txt": "20", "c.txt": "30", "notes.md": "999"}.items():
        (WORK / name).write_text(val)
    (WORK / "total.out").unlink(missing_ok=True)
    speed()
    results = [
        single(f"List the files in {WORK}", "list_dir", lambda a: WORK.name in a.get("path", "")),
        single(f"What does {WORK}/a.txt say?", "read_file", lambda a: a.get("path", "").endswith("a.txt")),
        single("What's the weather in Paris right now?", "get_weather", lambda a: "paris" in a.get("city", "").lower()),
        single(f"Save the word hello into {WORK}/greet.txt", "write_file",
               lambda a: a.get("path", "").endswith("greet.txt") and "hello" in a.get("content", "").lower()),
        single("What is 7 times 8?", None, None),
        multistep(),
    ]
    print(f"score: {sum(results)}/{len(results)}")
