#!/usr/bin/env bash
# 비공개/공개 테스트 트랙에 테스터 Google Group을 연결한다.
# Play Console을 브라우저로 조작하는 대신 Play Developer API를 직접 호출한다.
#
# 사용법:
#   ./scripts/play-testers.sh <track> <group-email> [<group-email> ...]
#   DRY_RUN=1 ./scripts/play-testers.sh <track> <group-email>   # 커밋 생략 + 트랙 목록 출력
#
# 처음 쓸 때는 반드시 DRY_RUN=1 로 실행해 실제 track ID를 확인할 것.
# Play Console의 표시 라벨("비공개 테스트 - Alpha")과 API track ID는 별개이며,
# 커스텀 클로즈드 트랙이면 ID가 전혀 다르다. 틀린 track으로 커밋하면
# 엉뚱한 트랙의 테스터 설정을 덮어쓴다.
#
# 주의: Testers 리소스는 Google Group만 지원한다. Play Console UI에 있는
#       개별 이메일 목록(email list)은 API로 다룰 수 없다.
set -euo pipefail

PACKAGE="com.geonganghaejim.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="$REPO_ROOT/android/play-service-account.json"
API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PACKAGE"

if [[ $# -lt 2 ]]; then
  echo "사용법: $0 <track> <group-email> [<group-email> ...]" >&2
  exit 2
fi
if [[ ! -f "$KEY" ]]; then
  echo "자격증명이 없다: $KEY" >&2
  echo "docs/play-deploy.md 의 '1회 준비: 서비스 계정' 절차를 먼저 수행할 것." >&2
  exit 1
fi

TRACK="$1"; shift
# 그룹 이메일들을 {"googleGroups":["a","b"]} 형태로 만든다.
BODY=$(printf '%s\n' "$@" | jq -R . | jq -sc '{googleGroups: .}')

# gcloud 전역 설정을 오염시키지 않도록 임시 config 디렉토리에서 인증한다.
CLOUDSDK_CONFIG="$(mktemp -d)"
export CLOUDSDK_CONFIG
trap 'rm -rf "$CLOUDSDK_CONFIG"' EXIT

gcloud auth activate-service-account --key-file="$KEY" --quiet >/dev/null
TOKEN="$(gcloud auth print-access-token)"
AUTH=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

# 편집(edit)은 계정당 한 번에 하나만 열 수 있다. 새로 열면 기존 편집은 무효화된다.
EDIT_ID=$(curl -sS -X POST "${AUTH[@]}" "$API/edits" | jq -er .id)
echo "edit 생성: $EDIT_ID"

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "--- 이 앱의 실제 track ID 목록 ---"
  curl -sS "${AUTH[@]}" "$API/edits/$EDIT_ID/tracks" | jq -r '.tracks[]?.track'
fi

echo "트랙 '$TRACK' 테스터 그룹 설정: $BODY"
curl -sS -X PUT "${AUTH[@]}" -d "$BODY" "$API/edits/$EDIT_ID/testers/$TRACK" | jq .

# 커밋해야 실제 반영된다. 커밋하지 않은 edit의 변경은 그대로 버려진다.
if [[ -n "${DRY_RUN:-}" ]]; then
  echo "DRY_RUN: 커밋을 생략했다. 위 track 목록에서 ID를 확인한 뒤 DRY_RUN 없이 다시 실행할 것."
  exit 0
fi

curl -sS -X POST "${AUTH[@]}" "$API/edits/$EDIT_ID:commit" | jq .
echo "커밋 완료. 반영에는 수 시간 걸릴 수 있다."
