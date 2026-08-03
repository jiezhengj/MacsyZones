#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "用法: $0 <x.y.z> <major|minor|patch>" >&2
    exit 2
fi

targetVersion="$1"
requestedLevel="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
projectRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$projectRoot"

if [[ ! "$targetVersion" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "目标版本必须是 x.y.z 格式: $targetVersion" >&2
    exit 2
fi

case "$requestedLevel" in
    major|minor|patch) ;;
    *)
        echo "版本级别必须是 major、minor 或 patch: $2" >&2
        exit 2
        ;;
esac

projectVersions="$({ rg -o 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' MacsyZones.xcodeproj/project.pbxproj || true; } | sed 's/.*= //' | sort -u)"
if [[ -z "$projectVersions" ]]; then
    echo "找不到 MARKETING_VERSION" >&2
    exit 1
fi
if [[ "$projectVersions" == *$'\n'* ]]; then
    echo "不同 Build Configuration 使用了不同的 MARKETING_VERSION: $projectVersions" >&2
    exit 1
fi
if [[ "$projectVersions" != "$targetVersion" ]]; then
    echo "项目 MARKETING_VERSION 为 [$projectVersions]，目标版本为 [$targetVersion]。" >&2
    exit 1
fi

currentVersion="$({ rg -o '^当前已发布版本：`v[0-9]+\.[0-9]+\.[0-9]+`' RELEASES.md || true; } | sed -E 's/.*`v([^`]*)`.*/\1/' | head -n 1)"
if [[ -z "$currentVersion" ]]; then
    echo "RELEASES.md 缺少当前已发布版本记录" >&2
    exit 1
fi

nextVersion="$({ rg -o '^下一发布目标：`v[0-9]+\.[0-9]+\.[0-9]+`' RELEASES.md || true; } | sed -E 's/.*`v([^`]*)`.*/\1/' | head -n 1)"
nextLevel="$({ rg -o '^下一发布级别：`(Major|Minor|Patch)`' RELEASES.md || true; } | sed -E 's/.*`([^`]*)`.*/\1/' | tr '[:upper:]' '[:lower:]' | head -n 1)"

IFS=. read -r currentMajor currentMinor currentPatch <<< "$currentVersion"
IFS=. read -r targetMajor targetMinor targetPatch <<< "$targetVersion"

if (( targetMajor < currentMajor )) || \
   (( targetMajor == currentMajor && targetMinor < currentMinor )) || \
   (( targetMajor == currentMajor && targetMinor == currentMinor && targetPatch <= currentPatch )); then
    echo "目标版本 [$targetVersion] 必须高于当前已发布版本 [$currentVersion]。" >&2
    exit 1
fi

case "$requestedLevel" in
    major)
        expectedVersion="$((currentMajor + 1)).0.0"
        ;;
    minor)
        expectedVersion="${currentMajor}.$((currentMinor + 1)).0"
        ;;
    patch)
        expectedVersion="${currentMajor}.${currentMinor}.$((currentPatch + 1))"
        ;;
esac

if [[ "$targetVersion" != "$expectedVersion" ]]; then
    echo "[$requestedLevel] 发布必须使用 [$expectedVersion]，实际目标为 [$targetVersion]。" >&2
    exit 1
fi

if [[ -n "$nextVersion" && "$targetVersion" != "$nextVersion" ]]; then
    echo "RELEASES.md 登记的下一发布目标为 [$nextVersion]，不能发布 [$targetVersion]。" >&2
    exit 1
fi
if [[ -n "$nextLevel" && "$requestedLevel" != "$nextLevel" ]]; then
    echo "RELEASES.md 登记的下一发布级别为 [$nextLevel]，不能声明 [$requestedLevel]。" >&2
    exit 1
fi

printf 'PASS: 版本校验通过：当前 v%s -> 目标 v%s（%s）\n' \
    "$currentVersion" "$targetVersion" "$requestedLevel"
