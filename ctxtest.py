"""Find the largest context size a local model can use on this GPU.

Usage: python3 -I ctxtest.py MODEL SIZE [SIZE...]   e.g. ctxtest.py qwen3.5:9b 65536 131072

For each size, loads the model with that context, fills about 90% of it with filler text
that hides one fact a quarter of the way in, and asks for the fact back. Reports whether
the model stayed fully on the GPU, GPU memory used, reading and writing speed, and recall.
"""
import json
import random
import subprocess
import sys
import time
import urllib.request

URL = "http://127.0.0.1:11434"
NEEDLE = "The access code for the Lisbon office is 7319."
QUESTION = "What is the access code for the Lisbon office? Answer with just the number."
TOKENS_PER_SENTENCE = None  # measured by calibrate() before the first test


def post(path, body, timeout=1800):
    req = urllib.request.Request(URL + path, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def haystack(n_tokens):
    rnd = random.Random(42)
    cities = ["Oslo", "Lima", "Perth", "Quito", "Dakar", "Hanoi", "Turin", "Cork"]
    n = int(n_tokens / TOKENS_PER_SENTENCE)
    lines = [f"Shipment {i} left {rnd.choice(cities)} with {rnd.randint(2, 900)} crates on day "
             f"{rnd.randint(1, 365)}." for i in range(n)]
    lines.insert(n // 4, NEEDLE)
    return "\n".join(lines)


def calibrate(model):
    """Measure tokens per filler sentence: a prompt longer than the context is silently cut."""
    global TOKENS_PER_SENTENCE
    TOKENS_PER_SENTENCE = 1
    d = post("/api/generate", {"model": model, "prompt": haystack(800), "stream": False,
                               "think": False, "options": {"num_ctx": 32768, "num_predict": 1}})
    TOKENS_PER_SENTENCE = d["prompt_eval_count"] / 801


def gpu_used_mib():
    out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                         capture_output=True, text=True).stdout
    return int(out.split()[0])


def processor(model):
    for m in json.load(urllib.request.urlopen(URL + "/api/ps")).get("models", []):
        if m["name"] == model:
            vram, size = m.get("size_vram", 0), m.get("size", 1)
            return f"{100 * vram / size:.0f}% GPU"
    return "not loaded"


def test(model, size):
    post("/api/generate", {"model": model, "keep_alive": 0})  # unload, start clean
    time.sleep(3)
    prompt = haystack(int(size * 0.9)) + "\n\n" + QUESTION  # 90%: room for the reply
    t = time.time()
    try:
        d = post("/api/chat", {"model": model, "stream": False, "think": False,
                               "options": {"num_ctx": size, "num_predict": 20},
                               "messages": [{"role": "user", "content": prompt}]})
    except Exception as e:  # out of memory or timeout
        return {"size": size, "error": str(e)[:120]}
    answer = d["message"]["content"].strip()
    return {
        "size": size,
        "prompt_tokens": d["prompt_eval_count"],
        "where": processor(model),
        "gpu_mib": gpu_used_mib(),
        "read_tok_s": round(d["prompt_eval_count"] / (d["prompt_eval_duration"] / 1e9)),
        "write_tok_s": round(d["eval_count"] / (d["eval_duration"] / 1e9), 1),
        "secs": round(time.time() - t),
        "fits": d["prompt_eval_count"] > 0.8 * size,  # a cut prompt is about half the size
        "recall": "7319" in answer,
        "answer": answer[:40],
    }


if __name__ == "__main__":
    model, sizes = sys.argv[1], [int(s) for s in sys.argv[2:]]
    calibrate(model)
    print(f"tokens per filler sentence: {TOKENS_PER_SENTENCE:.1f}", flush=True)
    for s in sizes:
        r = test(model, s)
        print(json.dumps(r), flush=True)
        if r.get("where") != "100% GPU":
            print("stopping: model no longer fits on the GPU", flush=True)
            break
    post("/api/generate", {"model": model, "keep_alive": 0})  # unload
