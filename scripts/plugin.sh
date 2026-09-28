#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <codex|claude> <install|remove|reload>" >&2
  exit 1
}

TOOL="${1:-}"
ACTION="${2:-}"
[ -n "$TOOL" ] && [ -n "$ACTION" ] || usage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/plugin.json")"
MARKETPLACE_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/marketplace.json")"
PLUGIN_ID="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

case "$TOOL" in
  codex)
    case "$ACTION" in
      install)
        codex plugin marketplace add "$ROOT_DIR" --json
        codex plugin add "$PLUGIN_ID" --json
        codex plugin list | grep "$PLUGIN_NAME"
        ;;
      remove)
        codex plugin remove "$PLUGIN_ID" --json
        ;;
      reload)
        codex plugin remove "$PLUGIN_ID" --json || true
        rm -rf "$HOME/.codex/plugins/cache/${MARKETPLACE_NAME}/${PLUGIN_NAME}"
        codex plugin marketplace add "$ROOT_DIR" --json
        codex plugin add "$PLUGIN_ID" --json
        ;;
      *) usage ;;
    esac
    ;;
  claude)
    case "$ACTION" in
      install)
        claude plugin marketplace add "$ROOT_DIR"
        claude plugin install "$PLUGIN_ID"
        claude plugin enable "$PLUGIN_ID"
        claude plugin details "$PLUGIN_ID"
        ;;
      remove)
        claude plugin disable "$PLUGIN_ID"
        ;;
      reload)
        claude plugin marketplace update "$MARKETPLACE_NAME" || true
        claude plugin update "$PLUGIN_ID" || true
        claude plugin details "$PLUGIN_ID"
        ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
