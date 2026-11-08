"""Recording relay to Ollama: logs each /v1/messages request's tool shape and the reply.

Usage: python3 -I recproxy.py OUTDIR PORT
Writes OUTDIR/log.jsonl (one summary per request) and OUTDIR/req-N.json / resp-N.txt.
"""
import http.client, http.server, json, os, re, socketserver, sys, threading, time

OUT, PORT = sys.argv[1], int(sys.argv[2])
os.makedirs(OUT, exist_ok=True)
HOP = {"connection", "keep-alive", "transfer-encoding", "content-length", "host"}
N = [0]
LOCK = threading.Lock()


class Relay(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _relay(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        up = http.client.HTTPConnection("127.0.0.1", 11434, timeout=900)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        up.request(self.command, self.path, body=body or None, headers=headers)
        r = up.getresponse()
        self.send_response(r.status)
        for k, v in r.getheaders():
            if k.lower() not in HOP:
                self.send_header(k, v)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        seen = b""
        while True:
            chunk = r.read1(65536)
            if not chunk:
                break
            seen += chunk
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        if self.command != "POST" or "/v1/messages" not in self.path:
            return
        with LOCK:
            N[0] += 1
            n = N[0]
        try:
            j = json.loads(body)
        except ValueError:
            j = {}
        tools = j.get("tools") or []
        msgs = json.dumps(j.get("messages", []))
        entry = {
            "n": n, "t": round(time.time(), 1), "path": self.path, "status": r.status,
            "model": j.get("model"),
            "tools": len(tools),
            "deferred": sum(1 for t in tools if t.get("defer_loading")),
            "toolsearch": any(t.get("name") == "ToolSearch" for t in tools),
            "beta": self.headers.get("anthropic-beta", ""),
            "tool_reference_in_msgs": msgs.count('"tool_reference"'),
            "called": re.findall(rb'"type":\s*"tool_use",\s*"id":\s*"[^"]*",\s*"name":\s*"([^"]+)"', seen)
                      and [x.decode() for x in re.findall(
                          rb'"type":\s*"tool_use",\s*"id":\s*"[^"]*",\s*"name":\s*"([^"]+)"', seen)],
            "error": seen[:300].decode("utf-8", "replace") if r.status >= 400 else None,
        }
        with open(f"{OUT}/req-{n}.json", "wb") as f:
            f.write(body)
        with open(f"{OUT}/resp-{n}.txt", "wb") as f:
            f.write(seen)
        with open(f"{OUT}/log.jsonl", "a") as f:
            f.write(json.dumps(entry) + "\n")

    do_GET = do_POST = do_HEAD = do_DELETE = _relay

    def log_message(self, *a):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


Server(("127.0.0.1", PORT), Relay).serve_forever()
