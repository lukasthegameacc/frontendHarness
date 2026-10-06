#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/glitchtip-forward.sh"
SANDBOX="$(mktemp -d)"
STUB_BIN="$SANDBOX/bin"
mkdir -p "$STUB_BIN"
CALL_LOG="$SANDBOX/calls.log"; : > "$CALL_LOG"
PIDFILE="$SANDBOX/state/lukas-plugin/glitchtip-forward.pid"

run() { XDG_STATE_HOME="$SANDBOX/state" CURL_OK="$1" PATH="$STUB_BIN:$PATH" "$SCRIPT" "$2"; }
trap 'run 0 stop || true; rm -rf "$SANDBOX"' EXIT

# kubectl stub: port-forward blocks like the real one; curl stub: port served iff CURL_OK=1.
cat > "$STUB_BIN/kubectl" <<STUB
#!/usr/bin/env bash
echo "kubectl \$*" >> "$CALL_LOG"
[[ "\$*" == *port-forward* ]] && exec sleep 300
echo test-ctx
STUB
cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
[ "$CURL_OK" = 1 ]
STUB
chmod +x "$STUB_BIN"/*

wait_for() { for _ in $(seq 50); do eval "$1" && return 0; sleep 0.1; done; echo "timeout: $1" >&2; exit 1; }

# Port not served: starts a pinned-context port-forward, and a second start is a no-op.
run 0 start
pid="$(cat "$PIDFILE")"
wait_for 'grep -q "port-forward" "$CALL_LOG"'
grep -q -- "--context test-ctx -n glitchtip port-forward svc/glitchtip-web 38088:80" "$CALL_LOG"
run 0 start
[[ "$(cat "$PIDFILE")" == "$pid" ]]

# stop takes the port-forward child down with the supervisor.
run 0 stop
wait_for '! kill -0 "$pid" 2>/dev/null'
wait_for '! pgrep -fx "sleep 300" >/dev/null'
[[ ! -e "$PIDFILE" ]]

# Port already served by someone else: just watch, never spawn a competing port-forward.
: > "$CALL_LOG"
run 1 start
sleep 1
! grep -q "port-forward" "$CALL_LOG"
run 1 stop

echo "ok"
