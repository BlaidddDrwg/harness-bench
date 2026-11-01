"""Relay between an agent harness and Ollama that logs prompt size per request.

Usage: python3 -I tokenproxy.py LOGFILE [PORT]   (default port 11435 -> Ollama on 11434)
Each request appends: path, request bytes, prompt tokens, output tokens.
"""
import http.client
import http.server
import json
import re
import socketserver
import sys
import time

LOG, PORT = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 11435
IN_RE = re.compile(rb'"(?:input_tokens|prompt_tokens|prompt_eval_count)"\s*:\s*(\d+)')
OUT_RE = re.compile(rb'"(?:output_tokens|completion_tokens|eval_count)"\s*:\s*(\d+)')
HOP = {"connection", "keep-alive", "transfer-encoding", "content-length", "host"}


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
        ins = [int(x) for x in IN_RE.findall(seen)]
        outs = [int(x) for x in OUT_RE.findall(seen)]
        if self.command == "POST":
            with open(LOG, "a") as f:
                f.write(json.dumps({"t": round(time.time(), 1), "path": self.path, "req_bytes": len(body),
                                    "prompt_tokens": max(ins) if ins else None,
                                    "output_tokens": max(outs) if outs else None}) + "\n")

    do_GET = do_POST = do_HEAD = do_DELETE = _relay

    def log_message(self, *a):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    Server(("127.0.0.1", PORT), Relay).serve_forever()
