#!/bin/bash
# 发版脚本：构建 -> 打包 -> 创建 GitHub Release -> 上传 zip 附件
#
# 用法:
#   ./Scripts/release.sh set-token    # 首次：把 token 存进 macOS 钥匙串
#   ./Scripts/release.sh v1.0.0      # 发版
#
# token 需要 repo 权限：https://github.com/settings/tokens
# 读取优先级：GH_TOKEN 环境变量 > macOS 钥匙串 > ~/.gh_token
set -euo pipefail
cd "$(dirname "$0")/.."

KEYCHAIN_SERVICE="handsout-github-token"

# 子命令：把 token 存进钥匙串（read -s 不回显，也不会进命令行历史）
if [ "${1:-}" = "set-token" ]; then
  printf "请输入 GitHub token（输入不回显，回车结束）: "
  read -rs TOKEN_INPUT || true
  printf "\n"
  if [ -z "$TOKEN_INPUT" ]; then
    echo "token 为空，未写入"
    exit 1
  fi
  security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -U -w "$TOKEN_INPUT"
  echo "已存入钥匙串: service=$KEYCHAIN_SERVICE"
  exit 0
fi

VERSION="${1:?用法: ./Scripts/release.sh v1.0.0  （首次先跑 ./Scripts/release.sh set-token）}"
REPO="yanshui177/handsout"
NOTES_FILE="${2:-docs/release-notes.md}"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  TOKEN="$(security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ] && [ -f "$HOME/.gh_token" ]; then
  TOKEN="$(tr -d '[:space:]' < "$HOME/.gh_token")"
fi
if [ -z "$TOKEN" ]; then
  echo "找不到 GitHub token。请先执行: ./Scripts/release.sh set-token"
  exit 1
fi

echo "==> 构建并打包 $VERSION"
./build.sh
ZIP="dist/Handsout-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/Handsout.app "$ZIP"
echo "    打包完成: $ZIP"

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "==> tag $VERSION 已存在，跳过创建"
else
  echo "==> 创建并推送 tag $VERSION"
  git tag -a "$VERSION" -m "Handsout $VERSION"
  git push origin "$VERSION"
fi

echo "==> 创建 Release"
python3 - "$VERSION" "$NOTES_FILE" <<'PY' > /tmp/handsout_release_payload.json
import json, sys
version, notes_file = sys.argv[1], sys.argv[2]
try:
    body = open(notes_file, encoding="utf-8").read()
except OSError:
    body = "Handsout " + version
print(json.dumps({"tag_name": version, "name": version, "body": body,
                  "draft": False, "prerelease": False}, ensure_ascii=False))
PY

RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases" \
  --data-binary @/tmp/handsout_release_payload.json)

UPLOAD=$(printf '%s' "$RESP" | python3 -c \
  "import sys,json;print(json.load(sys.stdin).get('upload_url','').split('{')[0])" 2>/dev/null || true)
if [ -z "$UPLOAD" ]; then
  echo "创建 Release 失败，API 返回："
  printf '%s\n' "$RESP" | head -20
  exit 1
fi

echo "==> 上传附件"
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/zip" \
  --data-binary @"$ZIP" \
  "$UPLOAD?name=Handsout-${VERSION}.zip" > /dev/null

HTML=$(printf '%s' "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin)['html_url'])")
echo "==> 发布完成: $HTML"
