# Loki로 GlitchTip 이벤트 교차 확인

**확인된 값 (2026-09-30, #307 조사):** `logcli` 기본 주소 `http://localhost:3100`, 테넌트 지정 없이 조회됨. label: `namespace`(`staging`/`develop`), `pod`, `container`(`backend`/`frontend`), `node_name`, `filename` 등. labeling-ai backend selector: `{namespace="staging", pod=~"samcommon-labeling-ai-.*", container="backend"}`. 요청 로그는 pino JSON(`requestId`, `path`, `status`, `durationMs`)이고 5xx 오류 줄은 `errorName`만 남고 원래 예외 메시지는 없다. `--output=raw | jq`로 집계한다.

Loki 없이도 이벤트와 당시 코드로 앱 결함 범위는 정할 수 있다. Loki 접근을 해결하는 동안 분석을 멈추지 않는다.

## 접속 수단 찾기 (추측 금지)

1. 현재 세션에 연결된 MCP 도구, 설정 파일, 레포 문서를 확인한다.
2. `logcli`(`/usr/local/bin/logcli`): 기본 주소는 `http://localhost:3100`이다. 원격 Loki는 `--addr` 또는 env(`LOKI_ADDR`, `LOKI_BEARER_TOKEN`/`LOKI_BEARER_TOKEN_FILE`, `LOKI_USERNAME`/`LOKI_PASSWORD`, `LOKI_ORG_ID`)로 지정한다.
3. `gcx` CLI(Grafana CLI, `/opt/homebrew/bin/gcx`): 설치·인증되어 있으면 `gcx logs`로 조회할 수 있다. #297–299 조사에서는 쓰지 않았다.
4. Loki가 결론에 꼭 필요한데 주소나 권한이 정말 없을 때만, 무엇이 막혀 있는지 구체적으로 사용자에게 묻는다. 엔드포인트나 토큰을 추측하지 않는다.

## 순서

1. **label부터 확인한다.** pod 이름이나 앱 JSON 필드가 Loki label이라는 보장은 없다.
2. **시간 범위**: 이벤트 `dateCreated` UTC ±2분 → 없으면 ±10분, 인접 pod까지. 여러 번 발생한 이슈는 firstSeen~lastSeen 전체를 본다.
3. **상관키 우선순위**: `request_id` 정확 일치 → 양쪽에 모두 있을 때만 trace ID → UTC 시각 + pod(`server_name`) + 엔드포인트 → 도메인 ID(task ID 등). `x-amzn-trace-id`와 Sentry `trace_id`를 같은 값으로 가정하지 않는다.
4. **로그 필드 이름은 release마다 다를 수 있다.** 사건 당시 코드(`git show <release>:...`)에서 확인한다. 예를 들어 labeling-ai는 PR #691 이전에는 `requestId`, 이후에는 `request_id`를 쓴다. 필드 이름과 상관없이 먹히는 문자열 매칭(`|= "<UUID>"`)을 먼저 시도한다.

## 템플릿

아래는 자리표시자가 있는 **템플릿**이다. 실행 전에 UTC RFC3339 시각과 label 조회로 확인한 selector로 교체한다.

```bash
logcli labels --timezone=UTC --from='<START>' --to='<END>'
logcli labels <label_name> --timezone=UTC --from='<START>' --to='<END>'

# 문자열 매칭 (필드 이름과 무관, 먼저 시도)
logcli query --timezone=UTC --from='<START>' --to='<END>' --limit=200 \
  '{<확인된 selector>} |= "<request_id UUID>"'

# JSON 필드 매칭 (당시 코드의 필드 이름을 확인한 경우에만)
logcli query --timezone=UTC --from='<START>' --to='<END>' --limit=200 \
  '{<확인된 selector>} | json | requestId="<UUID>"'
```

채운 예시 (#299, 2026-09-28T07:10:49Z; selector는 여전히 미확인):

```bash
logcli query --timezone=UTC --from='2026-09-28T07:08:49Z' --to='2026-09-28T07:12:49Z' --limit=200 \
  '{<확인된 selector>} |= "dc0a1197-044c-45a5-be2a-36c7dc2f1f9d"'
```

## 기록

실행한 명령, 시간 범위, 결과 요약(건수, 핵심 줄)을 **실행 즉시** 보고서에 적는다. **접속 불가, 권한 오류, 해당 selector·시간에서 0건**은 서로 다른 결과이므로 구분해서 적는다.
