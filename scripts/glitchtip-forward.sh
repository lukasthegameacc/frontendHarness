#!/usr/bin/env bash
# Keeps `kubectl port-forward` to GlitchTip alive while the glitchtip MCP (scripts/mcp.sh) is enabled.
# `start` is run by the SessionStart hook on every Claude/Codex session; no-op if disabled or already running.
set -u
PORT=38088  # uncommon on purpose: 8088 collides with dev servers and manual port-forwards
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lukas-plugin"
PIDFILE="$STATE_DIR/glitchtip-forward.pid"
LOG="$STATE_DIR/glitchtip-forward.log"

# Enabled in either tool's user config (see scripts/mcp.sh).
enabled() {
  jq -e '.mcpServers.glitchtip' "$HOME/.claude.json" >/dev/null 2>&1 ||
    grep -q '^\[mcp_servers\.glitchtip\]' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null
}
running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }
serving() { curl -s -o /dev/null --max-time 5 "http://localhost:$PORT/"; }

supervise() {
  # Pin the context so a later `kubectl config use-context` can't retarget a reconnect.
  local ctx pid=""
  ctx="$(kubectl config current-context)"
  trap 'kill $pid 2>/dev/null; exit 0' TERM INT
  while true; do
    # Someone else (e.g. a manual port-forward) already serves the port: just watch it.
    if serving; then sleep 10 & wait $!; continue; fi
    kubectl --context "$ctx" -n glitchtip port-forward svc/glitchtip-web "$PORT:80" &
    pid=$!
    sleep 5 & wait $!
    # port-forward often outlives "lost connection to pod" while forwarding nothing, so probe instead of trusting the process.
    while kill -0 "$pid" 2>/dev/null && serving; do sleep 10 & wait $!; done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    sleep 2 & wait $!
  done
}

case "${1:-}" in
  start)
    enabled || exit 0
    running && exit 0
    mkdir -p "$STATE_DIR"
    nohup "$0" supervise >>"$LOG" 2>&1 </dev/null &
    echo $! > "$PIDFILE"
    ;;
  stop)
    running && kill "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    ;;
  enabled) enabled ;;
  supervise) supervise ;;
  *) echo "usage: $(basename "$0") <start|stop|enabled>" >&2; exit 1 ;;
esac
