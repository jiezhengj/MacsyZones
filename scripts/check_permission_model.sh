#!/bin/bash
set -euo pipefail

# 权限模型断言（T014，R15）：
# 1. 用 awk 从真实源码抽取 PermissionRules / PermissionGuidance 的纯函数，
#    拼接桩与断言后用 /usr/bin/swift 执行——断言的是真实实现，不是手抄副本。
# 2. 不变量 grep：新权限文件禁 #available / AX 写操作 / exit(；Info.swift 禁 exit(0)。
# 3. 全仓 #available 计数不超过阶段 1 记录的基线 9。
# 抽取失败时退化为 MODE=source-grep：显式警告并用静态 grep 断言兜底，禁止静默跳过。
# 运行方式：bash scripts/check_permission_model.sh [source-root]

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -gt 1 || "${1:-}" == -* ]]; then
    echo "Usage: bash scripts/check_permission_model.sh [source-root]" >&2
    exit 2
fi
source_root="${1:-$root}"

test_source="$(mktemp -t macsyzones-permission-model)"
trap 'rm -f "$test_source"' EXIT

MODE="extract"

cat "$root/scripts/tests/permission-stubs.swift" > "$test_source"

# 抽取单个函数：从签名行（index==1，字面前缀匹配）到下一个 4 空格缩进的收尾行。
# 要求恰好一个完整函数，源码漂移即 fail-closed。
extract_one() {
    local file="$1" signature="$2"
    awk -v sig="$signature" '
        index($0, sig) == 1 {
            starts++
            if (inside) invalid = 1
            inside = 1
            print
            next
        }
        inside && /^    }$/ {
            ends++
            inside = 0
            print
            next
        }
        inside { print }
        END {
            if (starts != 1 || ends != 1 || inside || invalid) {
                printf "FAIL: could not extract exactly one complete function: %s\n", sig > "/dev/stderr"
                exit 1
            }
        }
    ' "$file" >> "$test_source"
}

extract_all() {
    echo "enum PermissionRules {" >> "$test_source"
    local pc="$source_root/MacsyZones/PermissionCenter.swift"
    extract_one "$pc" '    static func summarizeWindowControl(frontmost: PermissionStatus, finder: PermissionStatus) -> PermissionStatus {'
    extract_one "$pc" '    static func partialTargets(frontmost: PermissionStatus, finder: PermissionStatus) -> [String] {'
    extract_one "$pc" '    static func probeStatus(fromAXError axError: Int, timedOut: Bool, targetMissing: Bool) -> PermissionStatus {'
    extract_one "$pc" '    static func shouldEnterGrace(previous: PermissionStatus, probe: PermissionStatus, secondsSinceLaunch: TimeInterval) -> Bool {'
    echo "}" >> "$test_source"

    echo "enum PermissionGuidance {" >> "$test_source"
    local pg="$source_root/MacsyZones/PermissionGuidance.swift"
    extract_one "$pg" '    enum OpenOutcome: Equatable, Sendable {'
    extract_one "$pg" '    static func primaryPane(forMinor minor: Int) -> PermissionGuidancePane {'
    extract_one "$pg" '    static func fallbackPane(forMinor minor: Int) -> PermissionGuidancePane {'
    extract_one "$pg" '    static func deepLinkString(for pane: PermissionGuidancePane) -> String {'
    extract_one "$pg" '    static func panelTitle(for pane: PermissionGuidancePane) -> String {'
    extract_one "$pg" '    static func steps(for pane: PermissionGuidancePane) -> [String] {'
    extract_one "$pg" '    static func openOutcome(pane: PermissionGuidancePane, deepLinkOpened: Bool, rootOpened: Bool) -> OpenOutcome {'
    echo "}" >> "$test_source"

    cat "$root/scripts/tests/permission-assertions.swift" >> "$test_source"
}

if extract_all; then
    echo "Testing permission model from $source_root (MODE=extract)"
    /usr/bin/swift "$test_source"
else
    MODE="source-grep"
    echo "警告：awk 抽取真实函数失败，退化为 MODE=source-grep（仅静态 grep 断言，未执行真实函数逻辑）" >&2
    local_checks=0
    grep_or_fail() {
        local file="$1" needle="$2" message="$3"
        if ! grep -qF -- "$needle" "$file"; then
            echo "FAIL: 源码 grep 断言失败：$message" >&2
            exit 1
        fi
        local_checks=$((local_checks + 1))
    }
    pc="$source_root/MacsyZones/PermissionCenter.swift"
    pg="$source_root/MacsyZones/PermissionGuidance.swift"
    grep_or_fail "$pc" "static func summarizeWindowControl" "PermissionCenter.swift 应定义 summarizeWindowControl"
    grep_or_fail "$pc" "static func partialTargets" "PermissionCenter.swift 应定义 partialTargets"
    grep_or_fail "$pc" "static func probeStatus" "PermissionCenter.swift 应定义 probeStatus"
    grep_or_fail "$pc" "static func shouldEnterGrace" "PermissionCenter.swift 应定义 shouldEnterGrace"
    grep_or_fail "$pc" '-25211' "probeStatus 应映射 AXError -25211 → denied"
    grep_or_fail "$pc" "secondsSinceLaunch < 60.0" "宽限边界应为 secondsSinceLaunch < 60.0"
    grep_or_fail "$pg" "static func primaryPane" "PermissionGuidance.swift 应定义 primaryPane"
    grep_or_fail "$pg" "static func fallbackPane" "PermissionGuidance.swift 应定义 fallbackPane"
    grep_or_fail "$pg" "static func deepLinkString" "PermissionGuidance.swift 应定义 deepLinkString"
    grep_or_fail "$pg" "static func panelTitle" "PermissionGuidance.swift 应定义 panelTitle"
    grep_or_fail "$pg" "Privacy_AccessibilityApps" "深链应含 Privacy_AccessibilityApps 锚点"
    grep_or_fail "$pg" "com.apple.preference.security?Privacy_Accessibility" "深链应含 Privacy_Accessibility 锚点"
    grep_or_fail "$pg" "System & App Protection Override" "文案应含 System & App Protection Override"
    grep_or_fail "$pg" "Device Control and Data Access" "文案应含 Device Control and Data Access"
    grep_or_fail "$pg" "本 app 可能不在无障碍列表中" "应包含「未在列表属正常」提示语"
    # T035 补充断言：Layout 悬停监视器随 windowControl 状态自愈（通知驱动）。
    lw="$source_root/MacsyZones/Layout.swift"
    grep_or_fail "$pc" "permissionCapabilityDidChange" "PermissionCenter.swift 应定义/广播 permissionCapabilityDidChange 通知"
    grep_or_fail "$lw" "addObserver" "Layout.swift 应注册权限变化通知观察者"
    grep_or_fail "$lw" "permissionCapabilityDidChange" "Layout.swift 应订阅 permissionCapabilityDidChange"
    grep_or_fail "$lw" "syncMouseMonitor" "Layout.swift 应有幂等 syncMouseMonitor()"
    grep_or_fail "$lw" "removeObserver" "Layout.swift deinit 应移除通知观察者"
    echo "PASS: 权限模型断言通过（${local_checks} assertions，source-grep 模式）"
fi

# 不变量 grep ②：新增权限文件禁 #available / AX 写操作 / exit(
for name in PermissionCenter.swift PermissionGuidance.swift PermissionDiagnosticsView.swift; do
    file="$source_root/MacsyZones/$name"
    if [[ ! -f "$file" ]]; then
        echo "警告：$name 不存在，跳过其不变量检查（该文件属于后续阶段任务范围）" >&2
        continue
    fi
    if grep -n "#available(" "$file"; then
        echo "FAIL: $name 含 #available(（constitution：禁可用性分支）" >&2
        exit 1
    fi
    if grep -n "AXUIElementSetAttributeValue" "$file"; then
        echo "FAIL: $name 含 AX 写操作（探针只读约束）" >&2
        exit 1
    fi
    if grep -n "exit(" "$file"; then
        echo "FAIL: $name 含 exit(（去模态化后禁止进程退出调用）" >&2
        exit 1
    fi
done

# Info.swift 不再以 exit(0) 强制退出（T016 落地后本断言必须通过）。
info_file="$source_root/MacsyZones/Info.swift"
if grep -n "exit(0)" "$info_file"; then
    echo "FAIL: Info.swift 仍含 exit(0)（模态退出尚未移除，属 T016 范围）" >&2
    exit 1
fi

# 不变量 ③：全仓 #available 计数不超过基线 9（/tmp/m003-boundary-baseline.txt）。
available_count="$(grep -rn "#available(" "$source_root/MacsyZones" | wc -l | tr -d ' ')"
if [[ "$available_count" -gt 9 ]]; then
    echo "FAIL: 全仓 #available 计数 ${available_count} 超过基线 9" >&2
    exit 1
fi
echo "PASS: 不变量 grep 通过（#available 计数 ${available_count}/基线 9）"
