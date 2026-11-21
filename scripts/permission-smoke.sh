#!/bin/bash
# 003-macos27-permissions T031 冒烟脚本（R10 第三层）：
# 启动正式版（/Applications/MacsyZones.app）20 秒 → 抓取 permissions 日志 → 断言固定字段、launch 触发、
# 探针耗时 < 1000ms、进程存活、无 fatal error → 结束进程。
# 输出 PASS: 权限日志与进程状态正常（<N> 条权限记录）；任何断言失败输出 FAIL: 并 exit 1。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACT="/Applications/MacsyZones.app"
BIN="$ARTIFACT/Contents/MacOS/MacsyZones"

# 正式版不存在或需要刷新时先按 T002 流程构建并替换。
if [ ! -x "$BIN" ]; then
    echo "正式版不存在或需要刷新，先执行 build-permission-artifact.sh…"
    bash "$SCRIPT_DIR/build-permission-artifact.sh" || { echo "FAIL: 构建并替换正式版失败"; exit 1; }
fi

# 若已有同产物实例在跑，先结束，避免日志混淆。
pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null && sleep 1

START_EPOCH=$(date +%s)
open "$ARTIFACT" || { echo "FAIL: 启动正式版失败"; exit 1; }
sleep 20

PID=$(pgrep -f "MacsyZones.app/Contents/MacOS/MacsyZones" | head -1)
if [ -z "${PID:-}" ]; then
    echo "FAIL: 20 秒后进程不存在（启动即崩或被系统拒绝）"
    exit 1
fi

# 进程启动时刻（本地时间，秒级精度）。
PROC_START=$(ps -o lstart= -p "$PID" 2>/dev/null)
PROC_START_EPOCH=$(date -j -f "%a %b %d %H:%M:%S %Y" "$PROC_START" +%s 2>/dev/null)
if [ -z "${PROC_START_EPOCH:-}" ]; then
    echo "FAIL: 无法解析进程启动时间（lstart=$PROC_START）"
    pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
    exit 1
fi

LOG_FILE=$(mktemp -t m003-smoke-log)
trap 'rm -f "$LOG_FILE"' EXIT

log show --last 1m --style syslog \
    --predicate 'subsystem == "MeowingCat.MacsyZones" AND category == "permissions"' \
    > "$LOG_FILE" 2>&1

RECORD_COUNT=$(grep -c "capability=" "$LOG_FILE" || true)
if [ "$RECORD_COUNT" -eq 0 ]; then
    echo "FAIL: 未抓到任何权限日志（1 分钟窗口内 0 条 capability= 记录）"
    pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
    exit 1
fi

# 断言：窗口控制能力、launch 触发、固定字段齐全、探针耗时 < 1000ms。
grep -q "capability=windowControl" "$LOG_FILE" || { echo "FAIL: 缺 capability=windowControl"; pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones"; exit 1; }
grep -q "trigger=launch" "$LOG_FILE" || { echo "FAIL: 缺 trigger=launch"; pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones"; exit 1; }
grep -q "status=" "$LOG_FILE" || { echo "FAIL: 缺 status= 字段"; pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones"; exit 1; }
grep -q "latencyMs=" "$LOG_FILE" || { echo "FAIL: 缺 latencyMs= 字段"; pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones"; exit 1; }

SLOWEST=$(grep -o "latencyMs=[0-9]*" "$LOG_FILE" | cut -d= -f2 | sort -n | tail -1)
if [ "${SLOWEST:-9999}" -ge 1000 ]; then
    echo "FAIL: 探针耗时 ${SLOWEST}ms ≥ 1000ms（冒烟契约上限）"
    pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
    exit 1
fi

# 断言：首条 trigger=launch 与进程启动时间差 ≤ 10 秒。
FIRST_LAUNCH_TS=$(grep "trigger=launch" "$LOG_FILE" | head -1 | cut -c1-19)
FIRST_LAUNCH_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$FIRST_LAUNCH_TS" +%s 2>/dev/null)
if [ -z "${FIRST_LAUNCH_EPOCH:-}" ]; then
    echo "FAIL: 无法解析首条 launch 日志时间戳（$FIRST_LAUNCH_TS）"
    pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
    exit 1
fi
DELTA=$(( FIRST_LAUNCH_EPOCH - PROC_START_EPOCH ))
if [ "$DELTA" -lt 0 ] || [ "$DELTA" -gt 10 ]; then
    echo "FAIL: 首条 launch 日志与进程启动时间差 ${DELTA}s > 10s"
    pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
    exit 1
fi

# 断言：窗口期内无致命错误。
if log show --last 1m --predicate 'subsystem == "MeowingCat.MacsyZones" AND (eventMessage CONTAINS[c] "fatal error" OR eventMessage CONTAINS[c] "crash")' 2>/dev/null | grep -q "MacsyZones"; then
    echo "FAIL: 日志中发现疑似 fatal/crash"
    pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
    exit 1
fi

pkill -f "MacsyZones.app/Contents/MacOS/MacsyZones" 2>/dev/null
echo "PASS: 权限日志与进程状态正常（${RECORD_COUNT} 条权限记录，最慢探针 ${SLOWEST}ms，launch 差 ${DELTA}s）"
exit 0
