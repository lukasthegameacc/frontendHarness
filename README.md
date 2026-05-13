# frontendHarness
- 우리가 설정한 하네스 사용 방법
- 프로젝트 이해를 위해서 AGENTS.md 를 읽으세요

## 컨셉
- 어떤 Model 로도 호환되는 Frontend Harness

# 셋업 방법
```bash
set -a && source .env && set +a
envsubst < .mcp.json.template > .mcp.json
```

# 알아봐야하는거
- Codex plugin 사용 시 이전 피쳐들에 대한 리뷰 및 처리 메모리가 있는지
