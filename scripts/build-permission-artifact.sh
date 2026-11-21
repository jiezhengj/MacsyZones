#!/usr/bin/env bash
# 003-macos27-permissions（research.md R14）：产出可反复启动的正式签名验证副本。
#
# scripts/build-debug.sh 末尾的 trap cleanup 会删除派生数据，跑完没有可启动产物；
# 而 TCC 按「已签名 app 的固定路径」记录授权，冒烟脚本与手动矩阵都需要一个
# 路径稳定、签名正式的副本。本脚本把 Debug 产物固定复制到 ~/Applications/MacsyZones-dbg.app。
#
# 用法：bash scripts/build-permission-artifact.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="/tmp/m003-debug"
APP_BUNDLE="$HOME/Applications/MacsyZones-dbg.app"

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

echo "==> 复制到验证副本（${APP_BUNDLE}）"
rm -rf "$APP_BUNDLE"
mkdir -p "$HOME/Applications"
cp -R "$BUILT_APP" "$APP_BUNDLE"

echo "==> 校验签名"
bash scripts/verify-signing.sh "$APP_BUNDLE"

if [[ ! -x "$APP_BUNDLE/Contents/MacOS/MacsyZones" ]]; then
  echo "FAIL: 验证副本缺少可执行文件" >&2
  exit 1
fi

echo "PASS: 验证副本已生成（~/Applications/MacsyZones-dbg.app）"
