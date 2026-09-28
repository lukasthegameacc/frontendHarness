# Custom Plugin

- 개인 특화 Harness 관리용 Plugin 원격 개발 저장소 입니다.
- 자세한 정보는 @AGENTS.md 를 읽어주세요

---

# Setup

```
mkdir -p plugins
ln -sfn .. plugins/my-plugin
```

# Enroll Plugin

```bash
# Codex
PLUGIN_ROOT="$(pwd)"
PLUGIN_ID="my-plugin@my-plugin-local"

codex plugin marketplace add "$PLUGIN_ROOT" --json
codex plugin add "$PLUGIN_ID" --json
codex plugin list

## Remove Plugin
# codex plugin remove "$PLUGIN_ID" --json

## Reload after updating
# claude plugin marketplace update my-plugin-local || true
# claude plugin update $PLUGIN_ID || true
# claude plugin details $PLUGIN_ID
```

```bash
# Claude
PLUGIN_ROOT="$(pwd)"
PLUGIN_ID="my-plugin@my-plugin-local"

claude plugin marketplace add "$PLUGIN_ROOT"
claude plugin install "$PLUGIN_ID"
claude plugin enable "$PLUGIN_ID"
claude plugin details "$PLUGIN_ID"

## Disable plugin
# claude plugin disable "$PLUGIN_ID"

## Reload after updating
# codex plugin remove my-plugin@my-plugin-local --json || true
# rm -rf "$HOME/.codex/plugins/cache/my-plugin-local/my-plugin"
# codex plugin marketplace add "$PLUGIN_ROOT" --json
# codex plugin add "$PLUGIN_ID" --json
```

