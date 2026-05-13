---
name: dev-workflow
description: "GitHub Issue 기반 개발 실행 워크플로우. 이슈를 선택하고 Status 변경 → 구현 → 리뷰 → 완료까지의 전체 흐름을 자동으로 따릅니다. '이슈 진행해줘', '다음 이슈 처리해줘', '#번호 작업해줘', '이슈 시작', '이슈 해줘', '개발 시작', 'Phase 진행' 등의 키워드가 있으면 이 스킬을 사용하세요."
---

# 개발 실행 워크플로우

GitHub Project의 이슈를 선택하고 개발을 진행하는 실행 프로세스. 이슈 작업 요청 시 반드시 이 흐름을 따른다.

## 사전 준비 (매 세션 초기 1회)

```bash
OWNER=$(git remote get-url origin | sed -E 's/.*[:/]([^/]+)\/[^/]+\.git/\1/')
REPO=$(git remote get-url origin | sed -E 's/.*\/([^/]+)\.git/\1/')

# 프로젝트 ID + 번호
gh project list --owner "$OWNER" --format json

# Status 필드 ID + 옵션 ID (In Progress, Done)
gh project field-list {PROJECT_NUMBER} --owner "$OWNER" --format json
```

---

## Step 1: 작업할 이슈 확인

사용자가 특정 이슈 번호를 지정하지 않은 경우, 프로젝트 현황을 조회하여 다음 작업할 이슈를 제안한다.

```bash
gh project item-list {PROJECT_NUMBER} --owner "$OWNER" --format json
```

- Phase 번호 순 → Priority (High > Medium > Low) 순으로 추천
- Status가 Todo인 이슈만 대상

---

## Step 2: Status → In Progress

구현 시작 **전에 반드시** Status를 변경한다. 이 단계를 건너뛰지 않는다.

```bash
# 이슈번호로 아이템 ID 조회
gh project item-list {PROJECT_NUMBER} --owner "$OWNER" --format json
# → content.number == {ISSUE_NUMBER} 인 아이템의 id 추출

# Status 변경
gh project item-edit \
  --project-id "{PROJECT_ID}" \
  --id "{ITEM_ID}" \
  --field-id "{STATUS_FIELD_ID}" \
  --single-select-option-id "{IN_PROGRESS_OPTION_ID}"
```

사용자에게 "Issue #{번호} Status를 In Progress로 변경했습니다" 확인 메시지 출력.

---

## Step 3: 구현

이슈 body의 작업 내용 체크리스트를 기준으로 개발을 진행한다. 구현하다가 개발자에게 문의할 것이 있으면 이슈에 댓글로 문의 후 답변을 기다린다.

```bash
# 이슈 내용 확인
gh issue view {ISSUE_NUMBER} --repo {OWNER}/{REPO}
```

### 이슈 체크리스트 실시간 동기화

이슈 body는 항상 **현재 구현 상태의 진실 공급원(single source of truth)**이다. 다음 상황에서 즉시 이슈를 업데이트한다:

**1. 작업 항목 완료 시** — 해당 체크박스를 `[x]`로 변경

**2. 사용자 요청으로 구현 내용이 변경될 때** — 이슈 body도 함께 수정
- 새로운 요구사항 추가 → 체크리스트에 항목 추가
- 기존 요구사항 변경 → 체크리스트 항목 문구 수정
- 요구사항 삭제/축소 → 불필요한 항목 제거
- 구현 방식 변경 → `## 개요` 또는 `## 참고` 섹션도 업데이트

**3. 검증 내용 변경 시** — `## 검증` 섹션도 갱신

```bash
# 이슈 body 업데이트
gh issue edit {ISSUE_NUMBER} --repo {OWNER}/{REPO} \
  --body "$(gh issue view {ISSUE_NUMBER} --repo {OWNER}/{REPO} --json body -q .body | sed 's/- \[ \] 작업 항목 1/- [x] 작업 항목 1/')"
```

원칙:
- 코드가 변경되면 이슈도 변경된다 — 둘의 불일치를 허용하지 않는다
- 모아서 한번에 하지 않고 변경 발생 시 즉시 반영한다
- Step 4로 넘어가기 전에 이슈 body가 최종 구현 상태와 일치하는지 확인

### 문제 발생 시 기록 (필수)

구현 중 문제(에러, 버그, 예상치 못한 동작, 설계 변경 등)가 발생하면 **두 곳에 기록**한다:

**1. 이슈 댓글** — 문제 발생 사실을 즉시 이슈에 댓글로 남긴다.

```bash
gh issue comment {ISSUE_NUMBER} --repo {OWNER}/{REPO} \
  --body "$(cat <<'EOF'
## ⚠️ 문제 발생
- **증상**: {무엇이 문제인지}
- **원인**: {왜 발생했는지}
- **해결**: {어떻게 해결했는지}
EOF
)"
```

**2. Discussion 자동 기록** — 원인-해결 형식으로 Discussion에 트러블슈팅 기록을 남긴다.

```bash
gh api graphql -f query='
mutation {
  createDiscussion(input: {
    repositoryId: "{REPO_ID}",
    categoryId: "{GENERAL_CATEGORY_ID}",
    title: "[트러블슈팅] #{ISSUE_NUMBER} {문제 요약}",
    body: "## 배경\n- 관련 이슈: #{ISSUE_NUMBER}\n- 작업 내용: {작업 설명}\n\n## 문제\n{증상 상세}\n\n## 원인\n{근본 원인 분석}\n\n## 해결\n{해결 방법과 적용한 코드/설정 변경}\n\n## 교훈\n{같은 문제를 방지하기 위한 참고사항}"
  }) {
    discussion { url }
  }
}'
```

- 사소한 오타/린트 에러는 제외. **디버깅에 시간이 소요된 문제만 기록**한다.
- Discussion 제목은 `[트러블슈팅] #{이슈번호} {문제 요약}` 형식
- 같은 이슈에서 여러 문제가 발생하면 각각 별도 Discussion으로 기록

### 구현 규칙
- `@/` 경로 별칭 사용 (tsconfig paths)
- Tailwind CSS 클래스 + shadcn/ui 컴포넌트로 스타일링
- 커밋 메시지에 claude/AI 관련 언급 금지, Co-Authored-By 미포함
- 패키지 설치 시 `npm install` 사용
- DB/폼 백엔드는 Supabase MCP 사용
- Next.js App Router 컨벤션 준수 (서버 컴포넌트 기본, 'use client' 필요시만)

---

## Step 4: Feature Branch 커밋 & 푸시

구현 완료 후 린트 확인 → feature branch 생성 → 커밋 → 푸시.

```bash
# feature branch 생성 (이미 있으면 생략)
git checkout -b feat/{ISSUE_NUMBER}-{slug}

# 린트 확인
npm run lint

# 타입 체크
npx tsc --noEmit

# 커밋 & 푸시
git add {수정한_파일들}
git commit -m "feat: 커밋 메시지"
git push origin feat/{ISSUE_NUMBER}-{slug}
```

- `{slug}`는 이슈 제목에서 핵심 키워드를 kebab-case로 축약 (예: `feat/42-push-notification`)
- main에 직접 푸시하지 않는다

---

## Step 5: 빌드 및 검증

구현한 기능이 정상 동작하는지 검증한다. **이 단계를 건너뛰지 않는다.**

### 5-1. 빌드 검증

Next.js SSG 빌드가 성공하는지 확인한다.

```bash
npm run build
```

- 빌드 에러가 있으면 반드시 수정 후 재빌드
- 빌드 경고(warning)도 가능한 한 해결

### 5-2. 린트 & 타입 체크

```bash
# ESLint
npm run lint

# TypeScript 타입 체크
npx tsc --noEmit
```

### 5-3. 브라우저 검증 (Chrome DevTools MCP) — 필수

Chrome DevTools MCP를 사용하여 실제 브라우저에서 구현 결과를 검증한다. **이 단계를 건너뛰지 않는다.**

#### 절차

**1. 개발 서버 시작**

```bash
# run_in_background로 실행
npm run dev
```

서버가 준비될 때까지 대기한 후 다음 단계를 진행한다.

**2. 페이지 접근 & 데스크톱 스크린샷**

```
mcp__chrome-devtools__navigate_page → http://localhost:3000
mcp__chrome-devtools__take_screenshot → 데스크톱 레이아웃 확인
```

- 스크린샷을 확인하여 레이아웃 깨짐, 텍스트 잘림, 요소 겹침 등을 체크
- 이슈에서 요구한 UI가 올바르게 렌더링되는지 확인

**3. 반응형 검증 (3 뷰포트)**

```
mcp__chrome-devtools__resize_page → 375×812 (모바일)
mcp__chrome-devtools__take_screenshot → 모바일 레이아웃 확인

mcp__chrome-devtools__resize_page → 768×1024 (태블릿)
mcp__chrome-devtools__take_screenshot → 태블릿 레이아웃 확인

mcp__chrome-devtools__resize_page → 1280×800 (데스크톱)
mcp__chrome-devtools__take_screenshot → 데스크톱 레이아웃 확인
```

- 각 뷰포트에서 레이아웃이 정상적으로 전환되는지 확인
- 모바일에서 가로 스크롤이 발생하지 않는지 확인

**4. 콘솔 에러 확인**

```
mcp__chrome-devtools__list_console_messages
```

- Error 레벨 메시지가 있으면 **반드시 수정** 후 재검증
- Warning은 가능한 해결하되, 외부 라이브러리 경고는 허용

**5. 접근성 트리 확인**

```
mcp__chrome-devtools__take_snapshot
```

- heading 계층 (h1 → h2 → h3) 이 올바른지 확인
- landmark 역할 (banner, navigation, main, contentinfo) 이 존재하는지 확인
- 주요 인터랙티브 요소에 aria-label이 있는지 확인

**6. 인터랙션 검증 (해당 시)**

구현한 컴포넌트에 인터랙션이 있는 경우 실제 동작을 검증한다.

```
mcp__chrome-devtools__click → 버튼, 링크, 메뉴 등 클릭 동작 확인
mcp__chrome-devtools__hover → 호버 효과 확인
mcp__chrome-devtools__evaluate_script → 스크롤 위치, 상태 변화 등 JS 동작 확인
```

- 예: Header 스크롤 효과, 모바일 메뉴 열기/닫기, 앵커 네비게이션 등

**7. 개발 서버 종료**

검증 완료 후 개발 서버 프로세스를 종료한다.

#### 검증 실패 기준 (수정 필수)

- 콘솔에 Error 레벨 메시지가 있는 경우
- 스크린샷에서 레이아웃 깨짐이 발견된 경우
- 접근성 트리에서 heading 계층이 누락된 경우
- 인터랙션이 기대대로 동작하지 않는 경우

### 5-4. Lighthouse 검증 (선택)

Chrome DevTools MCP의 Lighthouse 감사를 실행하여 성능, 접근성, SEO 점수를 확인한다.

```
mcp__chrome-devtools__lighthouse_audit
```

- Performance, Accessibility, SEO 각 90점 이상 목표
- Best Practices 확인
- 점수가 낮은 항목은 개선 권고사항을 참고하여 수정

### 5-5. 실패 시 필수 수정 루프

빌드, 린트, 타입 체크, **브라우저 검증**이 실패하면 **반드시 원인을 분석하고 수정한 후 재실행**한다. 성공할 때까지 이 루프를 반복한다.

```
빌드/린트/타입체크/브라우저 검증 실행 → 실패 → 원인 분석 → 코드 수정 → 추가 커밋 → 재실행 → ... → 성공
```

- 실패를 무시하고 다음 단계로 넘어가지 않는다
- "나중에 고치겠다", "MVP에서 허용" 등으로 스킵하지 않는다

---

## Step 6: 코드 리뷰

빌드 검증 통과 후 외부 모델에 리뷰를 요청한다.

```bash
# Codex 리뷰 (기본)
omc ask codex "Review the implementation of Issue #{ISSUE_NUMBER}. {구체적 리뷰 포인트}"

# Gemini 리뷰 (선택)
omc ask gemini "Review the implementation of Issue #{ISSUE_NUMBER}. {구체적 리뷰 포인트}"
```

리뷰가 불가능한 경우 (CLI 미설치 등) Claude Opus 모델을 사용하여 자체 리뷰로 대체.

리뷰 피드백 처리:
- 수정이 필요한 항목은 **사용자에게 확인 후** 바로 반영
- "MVP에서 허용" 등으로 임의 스킵하지 않는다
- 수정 후 추가 커밋 → 빌드 재검증

---

## Step 7: PR 생성 & Merge

리뷰 반영까지 완료된 후 PR을 생성하고 merge한다.

### 7-1. PR 생성

```bash
gh pr create \
  --title "feat: #{ISSUE_NUMBER} {이슈 제목 요약}" \
  --body "$(cat <<'EOF'
## Summary
- {구현 내용 1~3줄 요약}

## Changes
- {주요 변경 파일/모듈 목록}

## Test plan
- [ ] `npm run build` 빌드 성공
- [ ] `npm run lint` 린트 통과
- [ ] `npx tsc --noEmit` 타입 체크 통과
- [ ] 시각적 검증 완료 (반응형, 접근성)

Closes #{ISSUE_NUMBER}
EOF
)"
```

- `Closes #{ISSUE_NUMBER}`로 merge 시 이슈 자동 close 연결
- PR body에 빌드/린트/타입체크 결과와 시각적 검증 사항을 명시

PR 생성 권한을 따로 언급하지 않았으면, PR 생성 후 사용자에게 **PR URL과 요약을 보고**하고 merge 승인을 기다린다. 자동으로 merge하지 않는다.

### 7-2. PR Merge (사용자 승인 후)

사용자가 merge를 승인하면 실행한다.

```bash
# squash merge (커밋 히스토리 정리)
gh pr merge --squash --delete-branch
```

### 7-3. 로컬 정리

```bash
git checkout main
git pull origin main
```

---

## Step 8: Status → Done + Close

PR merge 후 Status를 변경하고 이슈를 닫는다 (Closes 키워드로 자동 close된 경우 Status만 변경).

```bash
# Status를 Done으로 변경
gh project item-edit \
  --project-id "{PROJECT_ID}" \
  --id "{ITEM_ID}" \
  --field-id "{STATUS_FIELD_ID}" \
  --single-select-option-id "{DONE_OPTION_ID}"

# 이슈가 아직 열려있으면 close
gh issue close {ISSUE_NUMBER} --repo {OWNER}/{REPO}
```

사용자에게 "Issue #{번호} 완료 처리했습니다" 확인 메시지 출력.

---

## Step 9: Context 정리 (compact) — 필수

이슈 완료 즉시 `/compact` 명령어를 실행한다. **진행 현황 테이블이나 다음 이슈 제안보다 먼저 실행한다.**

이슈 하나를 처리하면 구현, 디버깅, 테스트, 리뷰 등으로 컨텍스트가 누적되므로, 다음 이슈를 깨끗한 상태에서 시작하기 위해 반드시 이 단계를 수행한다.

순서: Done + Close → **즉시 `/compact` 실행** → 다음 이슈 제안

진행 현황 테이블, 남은 이슈 목록 등의 요약은 compact 이후에 출력한다.

---

## Step 10: 다음 이슈

compact 완료 후 Step 1로 돌아가서 다음 Phase/Priority 이슈를 제안한다.

---

## 요약

```
이슈 선택 → In Progress → 구현 → 린트 → Feature Branch 커밋 & 푸시
→ 빌드 및 검증 (빌드/린트/타입체크/브라우저 검증, 성공까지 반복) → 코드 리뷰 → PR 생성 & Merge → Done + Close → Compact → 다음 이슈
```

이 흐름의 어떤 단계도 건너뛰지 않는다. 특히 **빌드 검증 통과 없이 PR을 생성하지 않는다.**