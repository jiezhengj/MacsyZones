#!/usr/bin/env bash
# 003-macos27-permissions（research.md R14）：构建并就地替换正式版，用于权限验证。
#
# scripts/build-debug.sh 末尾的 trap cleanup 会删除派生数据，跑完没有可启动产物；
# 而 TCC 按 app 身份与路径记录授权。这里直接把 Debug 产物装到正式路径
# /Applications/MacsyZones.app（与用户日常使用的 app 同名同路径，不产生额外副本），
# 避免「验证用一个名字、正式版用另一个名字」导致 TCC 里出现多条互不相干的记录。
#
# 用法：bash scripts/build-permission-artifact.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="/tmp/m003-debug"
APP_BUNDLE="/Applications/MacsyZones.app"

cd "$REPO_ROOT"

echo "==> 构建 Debug 产物（派生数据：${DERIVED}）"
xcodebuild \
  -project MacsyZones.xcodeproj \
  -scheme MacsyZones \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=C7C84AAA3B67FACEA73042570A0BA2FC3D19E613 \
  DEVELOPMENT_TEAM=74FR87HYTH \
  build

BUILT_APP="$DERIVED/Build/Products/Debug/MacsyZones.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "FAIL: 构建产物不存在（${BUILT_APP}）" >&2
  exit 1
fi

echo "==> 退出正在运行的 MacsyZones"
pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null || true
sleep 1

echo "==> 替换正式版（${APP_BUNDLE}）"
if [[ -w "$(dirname "$APP_BUNDLE")" ]]; then
  rm -rf "$APP_BUNDLE"
  cp -R "$BUILT_APP" "$APP_BUNDLE"
else
  echo "FAIL: 没有写权限，无法替换 ${APP_BUNDLE}" >&2
  exit 1
fi

echo "==> 校验签名"
bash scripts/verify-signing.sh "$APP_BUNDLE"

if [[ ! -x "$APP_BUNDLE/Contents/MacOS/MacsyZones" ]]; then
  echo "FAIL: ${APP_BUNDLE} 缺少可执行文件" >&2
  exit 1
fi

echo "PASS: 正式版已替换为当前构建（/Applications/MacsyZones.app）；如需授权，请在系统设置里为它打开权限"
