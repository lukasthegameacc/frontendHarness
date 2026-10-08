---
name: mcp-setup
description: lukas-plugin이 제공하는 MCP 서버(gcloud, observability, notion, glitchtip, aws-api, aws-docs, aws-eks, terraform)를 목록으로 보여주고 켜고 끈다. 이 서버들은 기본으로 꺼져 있어서 /mcp에 보이지 않는다. 사용자가 "MCP 켜줘", "gcloud MCP 쓰고 싶어", "notion 연결해줘", "어떤 MCP 있어?", "glitchtip MCP 꺼줘", "aws mcp 활성화" 라고 하거나, 위 서버의 도구가 필요한데 세션에 없을 때 반드시 이 스킬을 사용한다.
---

# MCP 켜고 끄기

lukas-plugin의 MCP 서버는 기본으로 꺼져 있다. Claude Code는 플러그인 MCP를 전역으로 꺼둘 수 없어서, 서버 정의를 자동으로 로드되지 않는 카탈로그(`mcp/servers.json`)에 두고 필요한 것만 사용자 설정(user scope)에 추가한다. 그래서 `/mcp` 목록에 없는 것이 정상이고, 켜고 끄는 일은 전부 `scripts/mcp.sh`가 한다.

## 스크립트 위치

이 스킬 디렉터리에서 두 단계 위가 플러그인 루트다: `<이 스킬의 base directory>/../../scripts/mcp.sh`.

```
mcp.sh <claude|codex> list                  # 서버별 on/off
mcp.sh <claude|codex> enable <server...>
mcp.sh <claude|codex> disable [server...]   # 이름 없이 쓰면 카탈로그 전체 끄기
```

첫 인자는 지금 실행 중인 도구다. Claude Code 안이면 `claude`, Codex 안이면 `codex`(Claude Code는 환경변수 `CLAUDECODE=1`을 설정한다). 사용자가 "둘 다"라고 하면 두 번 실행한다. 설정은 도구마다 따로 저장되기 때문이다.

## 진행 순서

1. **현재 상태 보기**: `list`를 실행해 아래 표의 설명과 함께 on/off를 보여준다. 사용자가 이미 서버 이름을 말했으면 이 단계는 짧게 끝낸다.
2. **켜기/끄기**: 사용자가 고른 서버로 `enable` 또는 `disable`을 실행한다. 모르는 이름이면 스크립트가 에러를 내니, 비슷한 카탈로그 이름을 제안한다.
3. **결과 확인**: 다시 `list`를 실행해 바뀐 것을 보여준다.
4. **다음 할 일 안내**: 아래 "켠 뒤 필요한 것"에서 해당 서버 항목만 알려준다. MCP 도구는 세션을 시작할 때 연결되므로, 지금 세션에서 바로 쓰려면 Claude는 `/mcp`에서 다시 연결해야 하고 Codex는 새 세션을 열어야 한다.

## 서버 목록

| 서버 | 용도 |
|---|---|
| gcloud | gcloud CLI 명령 실행 (GCP 리소스 조회와 조작) |
| observability | GCP Cloud Logging, Monitoring, Trace 조회 |
| notion | Notion 공식 MCP (`mcp.notion.com`), 자체 OAuth라서 어떤 Notion 계정이든 붙을 수 있다 |
| glitchtip | GlitchTip 이슈와 이벤트 조회 (`glitchtip-issue` 스킬이 사용) |
| aws-api | AWS CLI 명령 실행 |
| aws-docs | AWS 공식 문서 검색 |
| aws-eks | EKS 클러스터 조회와 조작 (쓰기 권한 포함) |
| terraform | Terraform Registry의 provider와 module 정보 조회 (docker 필요) |

## 켠 뒤 필요한 것

- **notion**: 처음 쓸 때 Claude는 `/mcp`에서 notion을 골라 OAuth 인증을 한다. 브라우저가 다른 Notion 계정에 로그인돼 있으면 그 계정으로 붙으니, 원하는 계정으로 로그인하라고 알려준다. claude.ai Notion 커넥터는 플러그인이 막아두어서 중복되지 않는다.
- **glitchtip**: 셸에 `GLITCHTIP_MCP_TOKEN`이 export돼 있어야 한다. 켜면 `kubectl port-forward`(localhost:38088)가 자동으로 뜨고, 끊기면 다시 붙는다. 현재 kube context로 클러스터에 접근할 수 있어야 한다.
- **aws-api / aws-eks**: `AWS_PROFILE`이 필요하고, aws-eks는 `AWS_REGION`도 필요하다. Codex에서는 이 값들을 실행 환경에서 그대로 물려받는다.
- **gcloud / observability**: `gcloud auth login`과 `gcloud auth application-default login`이 되어 있어야 한다.
- **terraform**: docker가 실행 중이어야 한다.

## 끌 때

`disable`은 사용자 설정에서 서버를 제거한다. 저장돼 있던 OAuth 토큰도 함께 사라질 수 있으니, notion을 끄려 하면 나중에 다시 인증해야 한다고 알려준다. glitchtip은 Claude와 Codex 양쪽에서 모두 꺼졌을 때만 port-forward를 내린다.
