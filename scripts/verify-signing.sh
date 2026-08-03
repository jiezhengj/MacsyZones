#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "用法: $0 /path/to/MacsyZones.app" >&2
    exit 2
fi

appPath="$1"
expectedBundleIdentifier="MeowingCat.MacsyZones"
expectedCodeSignIdentity="Apple Development: jie.zhengj@qq.com (8SDSF987N2)"
expectedCertificateSHA1="C7C84AAA3B67FACEA73042570A0BA2FC3D19E613"
expectedDevelopmentTeam="74FR87HYTH"

certificateDirectory="$(mktemp -d /private/tmp/MacsyZones-signing-cert.XXXXXX)"
cleanup() {
    rm -rf "$certificateDirectory"
}
trap cleanup EXIT

if [[ ! -d "$appPath" ]]; then
    echo "App 不存在: $appPath" >&2
    exit 1
fi

signingInfo="$(codesign --display --verbose=4 "$appPath" 2>&1)"
designatedRequirement="$(codesign -d -r- "$appPath" 2>&1)"

echo "$signingInfo"
echo "$designatedRequirement"

requireSigningInfo() {
    local expected="$1"
    if ! grep -Fq "$expected" <<< "$signingInfo"; then
        echo "签名元数据缺少预期字段: $expected" >&2
        exit 1
    fi
}

requireSigningInfo "Identifier=$expectedBundleIdentifier"
requireSigningInfo "Authority=$expectedCodeSignIdentity"
requireSigningInfo "TeamIdentifier=$expectedDevelopmentTeam"
if ! codesign -d --extract-certificates="$certificateDirectory/certificate" "$appPath" >/dev/null 2>&1; then
    echo "签名中没有可提取的 Apple Development 证书；禁止使用 ad-hoc 签名。" >&2
    exit 1
fi

leafCertificate="$(find "$certificateDirectory" -maxdepth 1 -type f \( -name 'certificate0' -o -name 'certificate.0' \) -print -quit)"
if [[ -z "$leafCertificate" ]]; then
    echo "签名中没有找到叶子证书；禁止使用 ad-hoc 签名。" >&2
    exit 1
fi

actualCertificateSHA1="$(shasum -a 1 "$leafCertificate" | awk '{print toupper($1)}')"
if [[ "$actualCertificateSHA1" != "$expectedCertificateSHA1" ]]; then
    echo "证书 SHA-1 不匹配: $actualCertificateSHA1" >&2
    echo "预期证书 SHA-1: $expectedCertificateSHA1" >&2
    exit 1
fi

if ! grep -Fq "anchor apple generic" <<< "$designatedRequirement" || \
   ! grep -Fq "identifier \"$expectedBundleIdentifier\"" <<< "$designatedRequirement" || \
   ! grep -Fq "certificate leaf[subject.CN] = \"$expectedCodeSignIdentity\"" <<< "$designatedRequirement"; then
    echo "designated requirement 不符合正式签名要求。" >&2
    exit 1
fi
codesign --verify --deep --strict "$appPath"

echo "PASS: 正式签名身份、证书 SHA-1、Bundle ID、Team ID、designated requirement 和完整性均一致"
