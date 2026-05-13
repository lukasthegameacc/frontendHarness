---
name: github-dev-process
description: "GitHub 기반 개발 프로세스 관리. 이슈 생성, Project 보드 관리, Discussion 작성을 수행합니다. '이슈 만들어', '프로젝트 셋업', 'github 정리', '개발 계획 세워', 'discussion 만들어', 'github에 등록', '보드에 추가', '라벨 만들어', '이슈 등록' 등의 키워드가 있으면 이 스킬을 사용하세요. 개발 작업을 GitHub Issues/Project/Discussions로 체계적으로 관리할 때 사용합니다."
---

# GitHub 개발 프로세스 관리

GitHub Issues, Project Board, Discussions를 활용한 범용 개발 프로세스 관리 스킬. 어떤 GitHub 레포에서든 사용 가능.

## 사전 준비: 컨텍스트 수집

스킬 실행 시 가장 먼저 현재 레포의 정보를 수집한다. 이 정보는 모든 워크플로우에서 사용된다.

```bash
# 1. 현재 레포의 owner/repo 확인
git remote -v
# origin git@github.com:{OWNER}/{REPO}.git 에서 추출

# 2. Repository ID 조회 (Discussion 생성에 필요)
gh api graphql -f query='
{
  repository(owner: "{OWNER}", name: "{REPO}") {
    id
  }
}'

# 3. 기존 Project 목록 확인
gh project list --owner {OWNER}

# 4. Project가 있으면 필드/옵션 ID 조회
gh project field-list {PROJECT_NUMBER} --owner {OWNER} --format json

# 5. Discussion 카테고리 조회
gh api graphql -f query='
{
  repository(owner: "{OWNER}", name: "{REPO}") {
    discussionCategories(first: 20) {
      nodes { id, name, emoji, description }
    }
  }
}'

# 6. 기존 라벨 목록 확인
gh label list
```

수집된 값들을 이후 명령어의 `{OWNER}`, `{REPO}`, `{PROJECT_NUMBER}`, `{PROJECT_ID}`, `{REPO_ID}` 등에 대입하여 사용.

---

## 워크플로우 1: 이슈 생성

개발 작업을 이슈로 등록하고 Project Board에 연결.

### Step 1: 이슈 생성

```bash
gh issue create \
  --title "[FEAT] 이슈 제목" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## 개요
[작업 배경과 목표]

## 작업 내용
- [ ] 작업 항목 1
- [ ] 작업 항목 2
- [ ] 빌드/린트/타입체크 검증 통과

## 검증
- **빌드**: `npm run build` 성공
- **린트**: `npm run lint` 통과
- **타입 체크**: `npx tsc --noEmit` 통과
- **시각적 검증**: [확인할 페이지/컴포넌트와 검증 시나리오]
- **성공 기준**: [빌드 성공 + 시각적 확인 완료]

> 빌드 검증을 통과하기 전까지 이 이슈를 완료 처리하지 않는다.

## 참고
- [관련 파일, 의존성 등]
EOF
)"
```

제목 접두사 규칙:
- `[FEAT]` — 새 기능
- `[BUG]` — 버그 수정
- `[REFACTOR]` — 리팩터링
- `[INFRA]` — 인프라/배포
- `[DOCS]` — 문서

### Step 2: Project에 추가

```bash
gh project item-add {PROJECT_NUMBER} --owner {OWNER} \
  --url "https://github.com/{OWNER}/{REPO}/issues/{ISSUE_NUMBER}"
```

### Step 3: 커스텀 필드 설정

아이템 ID와 필드/옵션 ID를 조회한 후 설정.

```bash
# 아이템 목록에서 방금 추가한 이슈의 item ID 확인
gh project item-list {PROJECT_NUMBER} --owner {OWNER} --format json

# 필드 설정 (Phase, Priority, Status 등)
gh project item-edit \
  --project-id "{PROJECT_ID}" \
  --id "{ITEM_ID}" \
  --field-id "{FIELD_ID}" \
  --single-select-option-id "{OPTION_ID}"
```

### 이슈 생성 원칙

- body에 `## 개요`, `## 작업 내용` (체크리스트), `## 검증`, `## 참고` 섹션 포함
- `## 작업 내용` 체크리스트 마지막에 항상 `- [ ] 빌드/린트/타입체크 검증 통과` 항목 포함
- `## 검증` 섹션에 빌드/린트/타입체크 명령어와 시각적 검증 시나리오, 성공 기준 명시
- 빌드 검증을 통과하기 전까지 이슈를 완료 처리하지 않는다
- 이슈 body에는 HEREDOC(`<<'EOF'`)을 사용하여 마크다운 포맷 유지
- 이슈 생성 후 반드시 Project에 추가하고 커스텀 필드 설정
- 라벨이 존재하지 않으면 이슈 생성 전에 먼저 `gh label create`

---

## 워크플로우 2: Project 관리

Project Board를 새로 만들거나 확장할 때 사용.

### 프로젝트 생성

```bash
gh project create --owner {OWNER} --title "프로젝트명" --format json
```

응답에서 `id` (글로벌 Project ID)와 `number`를 기록.

### 커스텀 필드 추가

프로젝트에 Phase, Priority 등 커스텀 필드를 추가하여 대시보드로 활용.

```bash
gh project field-create {PROJECT_NUMBER} --owner {OWNER} \
  --name "Phase" \
  --data-type "SINGLE_SELECT" \
  --single-select-options "Phase 1,Phase 2,Phase 3"

gh project field-create {PROJECT_NUMBER} --owner {OWNER} \
  --name "Priority" \
  --data-type "SINGLE_SELECT" \
  --single-select-options "High,Medium,Low"
```

### 라벨 생성

```bash
gh label create "라벨명" --color "FF0000" --description "설명"
```

### 대량 이슈 처리

여러 이슈를 한꺼번에 만들 때:
1. 병렬 bash 호출로 이슈 다건 생성
2. 각 이슈 URL로 프로젝트에 일괄 추가
3. 아이템 목록 조회 후 필드 일괄 설정

### ID 조회 레퍼런스

```bash
# 필드 목록 (필드 ID, 옵션 ID 포함)
gh project field-list {PROJECT_NUMBER} --owner {OWNER} --format json

# 아이템 목록 (아이템 ID 포함)
gh project item-list {PROJECT_NUMBER} --owner {OWNER} --format json
```

주의: `gh project item-edit`는 `--project-id`에 글로벌 ID (`PVT_...`)를 사용. project number가 아님.

---

## 워크플로우 3: Discussion 생성

브레인스토밍, 기술 토론, 아이디어 공유 시 사용.

### Discussions 활성화 (최초 1회)

```bash
gh repo edit {OWNER}/{REPO} --enable-discussions
```

### Discussion 생성 (GraphQL API)

```bash
gh api graphql -f query='
mutation {
  createDiscussion(input: {
    repositoryId: "{REPO_ID}",
    categoryId: "{CATEGORY_ID}",
    title: "Discussion 제목",
    body: "본문 내용 (마크다운)"
  }) {
    discussion {
      url
      number
    }
  }
}'
```

### 카테고리 선택 기준

| 상황 | 카테고리 |
|------|---------|
| 새 기능 아이디어, 브레인스토밍 | Ideas |
| 자유 토론, 기술 논의, 회의록 | General |
| 기술 질문, 구현 방법 | Q&A |
| 공지, 릴리즈 노트 | Announcements |
| 투표가 필요한 결정 | Polls |
| 구현 결과 데모 공유 | Show and tell |

카테고리 ID는 사전 준비 단계에서 조회한 값을 사용.

### Discussion 본문 템플릿

```markdown
## 배경
[왜 이 논의가 필요한지]

## 논의 사항
- [ ] 질문/검토 항목 1
- [ ] 질문/검토 항목 2

## 관련 이슈
- #이슈번호

## 결정 사항
> 여기에 결론을 정리하고, 필요시 Issue로 전환합니다.
```

### Discussion → Issue 전환

Discussion에서 결론이 나면 GitHub 웹 UI에서 "Convert to Issue" 버튼으로 전환 가능. CLI에서는 결론을 바탕으로 새 이슈를 직접 생성.

---

## 개발 실행은 dev-workflow 스킬 참조

이슈 작업 실행(Status 변경 → 구현 → 리뷰 → 완료)은 `.claude/skills/dev-workflow` 스킬에서 관리.
이 스킬은 GitHub 관리 도구(이슈 생성, 프로젝트 셋업, Discussion)에 집중.