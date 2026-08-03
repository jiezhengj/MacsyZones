#!/usr/bin/env bash

set -euo pipefail

projectRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$projectRoot"

expectedCodeSignIdentity="Apple Development: jie.zhengj@qq.com (8SDSF987N2)"
expectedCertificateSHA1="C7C84AAA3B67FACEA73042570A0BA2FC3D19E613"
if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "$expectedCodeSignIdentity" && "${CODE_SIGN_IDENTITY}" != "$expectedCertificateSHA1" ]]; then
    echo "禁止使用非正式签名身份构建 Debug: ${CODE_SIGN_IDENTITY}" >&2
    exit 1
fi
if [[ -n "${DEVELOPMENT_TEAM:-}" && "${DEVELOPMENT_TEAM}" != "74FR87HYTH" ]]; then
    echo "禁止使用非正式 Team ID 构建 Debug: ${DEVELOPMENT_TEAM}" >&2
    exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

codeSignIdentity="$expectedCertificateSHA1"
developmentTeam="74FR87HYTH"
derivedDataPath="/private/tmp/MacsyZones-debug-$$"
appPath="${derivedDataPath}/Build/Products/Debug/MacsyZones.app"

cleanup() {
    local exitStatus=$?
    rm -rf "$derivedDataPath"
    exit "$exitStatus"
}
trap cleanup EXIT

if ! security find-identity -v -p codesigning | grep -Fq "$expectedCertificateSHA1"; then
    echo "找不到预期的可用签名证书: $expectedCodeSignIdentity" >&2
    echo "预期证书 SHA-1: $expectedCertificateSHA1" >&2
    echo "请在 Xcode 中登录正确 Apple 账户，并确认钥匙串中存在该 Apple Development 证书。" >&2
    exit 1
fi

xcodebuild \
    -project MacsyZones.xcodeproj \
    -scheme MacsyZones \
    -configuration Debug \
    -derivedDataPath "$derivedDataPath" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$codeSignIdentity" \
    DEVELOPMENT_TEAM="$developmentTeam" \
    clean build

scripts/verify-signing.sh "$appPath"
echo "PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）"
