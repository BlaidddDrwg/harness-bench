import os, pty, sys, time, re, select
cmd, outf = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"]="xterm-256color"; os.environ["COLUMNS"]="160"; os.environ["LINES"]="50"
    os.execvp("bash", ["bash", "-ic", cmd])
buf = b""
def pump(sec):
    global buf
    end = time.time() + sec
    while time.time() < end:
        r,_,_ = select.select([fd],[],[],0.5)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return
            if not d: return
            buf += d
pump(float(os.environ.get("PTY_START","20")))
if b"trust this folder" in buf.replace(b"\x1b[1C",b" ") or b"trust" in buf:
    os.write(fd,b"\x1b[B"); time.sleep(0.5); os.write(fd,b"\r"); pump(15)
os.write(fd, os.environ.get("PTY_INPUT","hi").encode())
time.sleep(1); os.write(fd, b"\r")
pump(int(os.environ.get("PTY_WAIT","120")))
os.write(fd, b"\x03"); time.sleep(0.5); os.write(fd, b"\x03")
pump(3)
txt = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[()][A-Z0-9]|\r", b"", buf).decode("utf-8","replace")
open(outf,"w").write(txt)
