#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "用法: $0 x.y.z major|minor|patch" >&2
    exit 2
fi

releaseVersion="$1"
releaseBumpLevel="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
if [[ ! "$releaseVersion" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "版本号必须是 x.y.z 格式: $releaseVersion" >&2
    exit 2
fi
if [[ "$releaseBumpLevel" != "major" && "$releaseBumpLevel" != "minor" && "$releaseBumpLevel" != "patch" ]]; then
    echo "版本级别必须是 major、minor 或 patch: $2" >&2
    exit 2
fi

projectRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$projectRoot"

expectedVersion="$({ rg -o 'MARKETING_VERSION = [^;]+' MacsyZones.xcodeproj/project.pbxproj || true; } | sed 's/.*= //' | sort -u)"
if [[ "$expectedVersion" != "$releaseVersion" ]]; then
    echo "项目 MARKETING_VERSION 为 [$expectedVersion]，与请求版本 [$releaseVersion] 不一致。" >&2
    echo "请先更新 MacsyZones.xcodeproj/project.pbxproj，再重新执行。" >&2
    exit 1
fi

scripts/check-version.sh "$releaseVersion" "$releaseBumpLevel"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

expectedCodeSignIdentity="Apple Development: jie.zhengj@qq.com (8SDSF987N2)"
expectedCertificateSHA1="C7C84AAA3B67FACEA73042570A0BA2FC3D19E613"
expectedDevelopmentTeam="74FR87HYTH"
if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "$expectedCodeSignIdentity" && "${CODE_SIGN_IDENTITY}" != "$expectedCertificateSHA1" ]]; then
    echo "禁止使用非正式签名身份构建 Release: ${CODE_SIGN_IDENTITY}" >&2
    echo "正式签名身份必须是: $expectedCodeSignIdentity" >&2
    exit 1
fi
if [[ -n "${DEVELOPMENT_TEAM:-}" && "${DEVELOPMENT_TEAM}" != "$expectedDevelopmentTeam" ]]; then
    echo "禁止使用非正式 Team ID 构建 Release: ${DEVELOPMENT_TEAM}" >&2
    echo "正式 Team ID 必须是: $expectedDevelopmentTeam" >&2
    exit 1
fi
codeSignIdentity="$expectedCertificateSHA1"
developmentTeam="$expectedDevelopmentTeam"
bundleIdentifier="MeowingCat.MacsyZones"
derivedDataPath="/tmp/MacsyZones-release-${releaseVersion}-$$"
stagingPath="/tmp/MacsyZones-dmg-${releaseVersion}-$$"
dmgPath="/tmp/MacsyZones-v${releaseVersion}.dmg"
dmgTempPath="/tmp/MacsyZones-v${releaseVersion}-$$.dmg"
appPath="${derivedDataPath}/Build/Products/Release/MacsyZones.app"

cleanup() {
    local exitStatus=$?
    rm -rf "$derivedDataPath" "$stagingPath"
    if [[ $exitStatus -ne 0 ]]; then
        rm -f "$dmgPath" "$dmgTempPath"
    fi
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
    -configuration Release \
    -derivedDataPath "$derivedDataPath" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$codeSignIdentity" \
    DEVELOPMENT_TEAM="$developmentTeam" \
    clean build

if [[ ! -d "$appPath" ]]; then
    echo "Release App 不存在: $appPath" >&2
    exit 1
fi

signingInfo="$(codesign -dv --verbose=4 "$appPath" 2>&1)"
echo "$signingInfo"
grep -Fq "Identifier=$bundleIdentifier" <<< "$signingInfo"
grep -Fq "Authority=$expectedCodeSignIdentity" <<< "$signingInfo"
grep -Fq "TeamIdentifier=$developmentTeam" <<< "$signingInfo"

designatedRequirement="$(codesign -d -r- "$appPath" 2>&1)"
echo "$designatedRequirement"
grep -Fq "anchor apple generic" <<< "$designatedRequirement"
grep -Fq "identifier \"$bundleIdentifier\"" <<< "$designatedRequirement"
grep -Fq "certificate leaf[subject.CN] = \"$expectedCodeSignIdentity\"" <<< "$designatedRequirement"

codesign --verify --deep --strict "$appPath"

mkdir -p "$stagingPath"
ditto "$appPath" "$stagingPath/MacsyZones.app"
ln -s /Applications "$stagingPath/Applications"
rm -f "$dmgPath" "$dmgTempPath"
hdiutil create \
    -volname "MacsyZones" \
    -srcfolder "$stagingPath" \
    -ov \
    -format UDZO \
    "$dmgTempPath"
mv "$dmgTempPath" "$dmgPath"
hdiutil imageinfo "$dmgPath" >/dev/null

echo "已生成并验证: $dmgPath"
