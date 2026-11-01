#!/usr/bin/env bash
# Run a command inside the benchmark sandbox (bubblewrap).
#
# Usage: sandbox.sh FAKE_HOME RW_DIR SOCKET -- COMMAND [ARGS...]
#
# Inside the sandbox:
#   - $HOME is FAKE_HOME: the user's real home folder (dotfiles, keys, documents) is hidden.
#   - Harness programs are visible read-only at their usual paths (see RO_PATHS).
#   - RW_DIR (the task folders) is the only other writable place; /tmp is private.
#   - There is no network except 127.0.0.1:11435, which is bridged through SOCKET to the
#     token relay outside. Set SANDBOX_NET=host to share the host network instead
#     (used only for one-time harness warm-up, never for scored runs).
set -eu
FH="$(realpath -m "$1")"; RW="$(realpath -m "$2")"; SOCK="$(realpath -m "$3")"
shift 3; [ "$1" = "--" ] && shift
REAL_HOME="${REAL_HOME:-$HOME}"

# Harness install locations, mounted read-only when they exist.
RO_PATHS=(
  "$REAL_HOME/.nvm"                 # node, codex, opencode
  "$REAL_HOME/.local/bin"           # claude, goose, hermes launchers
  "$REAL_HOME/.local/share/claude"  # claude versions
  "$REAL_HOME/.hermes/hermes-agent" # hermes code
  "$REAL_HOME/.hermes/tools"        # hermes python runtime
  # ~/.hermes/installs is copied into the fake home by run.sh: Hermes writes lock files there.
)

mkdir -p "$FH" "$RW"
args=(--ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run
      --bind "$FH" "$REAL_HOME")
for p in "${RO_PATHS[@]}"; do [ -e "$p" ] && args+=(--ro-bind "$p" "$p"); done
args+=(--bind "$RW" "$RW" --setenv HOME "$REAL_HOME" --chdir "$RW"
       --die-with-parent --new-session)

if [ "${SANDBOX_NET:-none}" = "host" ]; then
  exec bwrap "${args[@]}" --unshare-all --share-net -- "$@"
fi
args+=(--bind "$(dirname "$SOCK")" /run/hb --unshare-all)
# Inside: listen on 127.0.0.1:11435 and forward to the relay socket, then run the command.
exec bwrap "${args[@]}" -- bash -c '
  socat TCP-LISTEN:11435,bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:/run/hb/'"$(basename "$SOCK")"' &
  for i in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/11435) 2>/dev/null && break; sleep 0.1; done
  exec "$@"' bash "$@"
