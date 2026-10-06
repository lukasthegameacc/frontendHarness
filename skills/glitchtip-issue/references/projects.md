# 프로젝트별 GlitchTip 값

비밀값(토큰, DSN, API 키)은 여기에 적지 않는다.

## 공통

- 인스턴스: `https://glitchtip.thegame-sam.com`
- 조직 slug: `thegame`
- 이슈 URL 형식: `https://glitchtip.thegame-sam.com/thegame/issues/<issue_id>`
- MCP: `http://localhost:38088/mcp`, bearer 토큰 env `GLITCHTIP_MCP_TOKEN` (플러그인 `.mcp.json`의 `glitchtip`). 포트는 SessionStart 훅의 `scripts/glitchtip-forward.sh`가 `kubectl port-forward`로 열어 두고 끊기면 다시 붙는다

## samcommon-labeling-ai (backend)

- GlitchTip project: `samcommon-labeling-ai-backend`, ID `19`
- 환경: `staging` → 호스트 `labeling.stg.thegame-sam.com`
- 레포: `THEGAME-TECH-AI/samcommon-monorepo-ai`, PR base `dev`
- 소스: `services/samcommon-labeling-ai/service-backend/src/` (예: `tasks.ts`, `transcriber.ts`)
  - 스택의 빌드 경로 `dist-service-backend/service-backend/src/*.js` → 위 TS로 함수명 기준 매핑
- 이벤트 `server_name`: `samcommon-labeling-ai-…` pod 이름
- 앱 env 키: `GLITCHTIP_DSN_BACKEND`(전송용 DSN), `GLITCHTIP_ENVIRONMENT_BACKEND`, `GLITCHTIP_RELEASE_BACKEND`
- release: Helm `stamp-release`가 `APP_COMMIT_SHA`로 채움. 이벤트에는 원시 커밋 SHA로 표시됐음 (항상 실제 태그 값을 먼저 확인)
- 로그 필드: #297–299 당시 release(`51931abf…`)의 `upstreamFailure`는 `{ requestId, dependency, failureType, errorName }`. PR #691 이후 `request_id`, `failure_type`, `stt_stage` 등. Loki JSON 필드 검색 전에 release별로 확인한다.
- 테스트 (`services/samcommon-labeling-ai`에서 실행, 통합 테스트는 DB/env 필요 여부를 먼저 확인, 테스트 개수를 합격 기준으로 쓰지 않음):
  - `npm test`
  - `npm run build:frontend`
  - `npx vitest run service-backend/integration-tests/http/tasks.integration.test.ts --maxWorkers=1`
  - `npx vitest run --config service-frontend/vite.config.ts service-frontend/src/screens/work-screens.test.tsx`
- PR: 레포 `.github/PULL_REQUEST_TEMPLATE.md` (Risk Level, Understanding Check 포함)를 유지한다.
- 외부 의존성: Soniox STT(`api.soniox.com`, 설정 `STT_PROVIDER`, `STT_API_KEY`, `STT_API_TIMEOUT_MS`, `STT_BASE_URL`), S3 오디오 버킷 `thegame-samcommon-labeling-ai-stg`

### 과거 사례: #297–299 (녹음 STT 실패, PR #691)

- #297, #298: `empty_stt` — Soniox transcript GET 200인데 사용할 글자가 없음. #297은 재녹음 경로(전사 후 저장 → 기존 데이터 보존), #298은 첫 녹음 경로(저장 후 전사 → 실패 파일이 저장·조회 가능했음. 이는 코드 순서와 통합 테스트로 확인한 것이며, S3 PUT 200만으로 판단한 것이 아님). 같은 에러 코드, 다른 데이터 상태.
- #299: `dependency_transport` — 상태 GET 200 뒤 transcript GET 없이 DELETE. 포괄 catch 라벨이라 네트워크 장애로 단정 불가. 진단 필드(`stt_stage`, `stt_reason`, HTTP 상태, poll count, elapsed ms 등)를 추가하는 것으로 대응.
- 수정 계약: 빈 전사 → `400 VALIDATION_FAILED`(재녹음 안내), 실제 제공자/전송 오류 → `503 SERVICE_UNAVAILABLE`.
