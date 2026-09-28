#!/usr/bin/env python3
# Mirrors codex-rs hook_hash + version_for_toml (verified on codex-cli 0.157.1).
# usage: codex-trust-hooks.py <hooks.json> <plugin_id>:<hooks_rel_path> <config.toml>
import hashlib
import json
import os
import re
import sys


def snake(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def hook_entries(hooks_file, key_prefix):
    with open(hooks_file) as f:
        events = json.load(f)["hooks"]
    for event, groups in events.items():
        ev = snake(event)
        for gi, group in enumerate(groups):
            for hi, hook in enumerate(group.get("hooks", [])):
                # ponytail: command hooks only; mcp_tool / additionalContextLimit hashing not mirrored.
                if hook.get("type") != "command":
                    continue
                if ev in ("session_end", "interrupt"):
                    timeout = min(max(hook.get("timeout", 1), 1), 3)
                else:
                    timeout = max(hook.get("timeout", 600), 1)
                handler = {
                    "type": "command",
                    "command": hook["command"],
                    "timeout": timeout,
                    "async": hook.get("async", False),
                }
                if hook.get("statusMessage") is not None:
                    handler["statusMessage"] = hook["statusMessage"]
                ident = {"event_name": ev, "hooks": [handler]}
                if group.get("matcher") is not None:
                    ident["matcher"] = group["matcher"]
                payload = json.dumps(ident, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
                digest = hashlib.sha256(payload.encode()).hexdigest()
                yield f"{key_prefix}:{ev}:{gi}:{hi}", f"sha256:{digest}"


def write_trust(config, entries):
    try:
        with open(config) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []
    for key, digest in entries:
        header = f'[hooks.state."{key}"]'
        line = f'trusted_hash = "{digest}"'
        if header in lines:
            start = lines.index(header) + 1
            end = next((j for j in range(start, len(lines)) if lines[j].startswith("[")), len(lines))
            for j in range(start, end):
                if lines[j].startswith("trusted_hash"):
                    lines[j] = line
                    break
            else:
                lines.insert(start, line)
        else:
            lines += ["", header, line]
        print(f"trusted {key}")
    os.makedirs(os.path.dirname(config), exist_ok=True)
    with open(config, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    hooks_file, key_prefix, config = sys.argv[1:]
    write_trust(config, list(hook_entries(hooks_file, key_prefix)))
