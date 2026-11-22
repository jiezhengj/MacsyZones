#!/usr/bin/env bash
# 设置界面「布局」区的选择一致性回归：
# 下拉选中哪个布局，编辑/重命名/复制/删除就必须作用于哪个布局。
#
# 历史缺陷：Picker 显示的是「屏幕 + 空间的首选布局」，按钮却读全局
# UserLayouts.currentLayoutName，于是永远操作活动布局（用户看到的「只针对大屏」）。
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
fail_msg() { printf 'FAIL: %s\n' "$*"; fail=1; }

SETTINGS="MacsyZones/SettingsView.swift"
USERDATA="MacsyZones/UserData.swift"
STATE="MacsyZones/SettingsState.swift"

for f in "$SETTINGS" "$USERDATA" "$STATE"; do
    [[ -f "$f" ]] || { fail_msg "找不到 $f"; exit 1; }
done

# --- 1. 设置区不得再直接操作「当前活动布局」 ------------------------------
for api in renameCurrentLayout removeCurrentLayout duplicateCurrentLayout; do
    if grep -q "\b${api}(" "$SETTINGS"; then
        fail_msg "SettingsView 仍在调用 ${api}（应作用于下拉选中的布局）"
    fi
done

if ! grep -q 'var selectedLayoutName: String' "$SETTINGS"; then
    fail_msg "LayoutSettingsSection 缺少 selectedLayoutName（下拉与按钮必须共用同一个名字）"
fi
if ! grep -q 'removeLayout(named: removedName)' "$SETTINGS"; then
    fail_msg "删除按钮未按选中布局名删除"
fi
if ! grep -q 'sourceLayoutName: selectedLayoutName' "$SETTINGS"; then
    fail_msg "重命名/复制弹窗未接收选中布局名"
fi
if ! grep -q 'layouts.selectLayout(selectedLayoutName)' "$SETTINGS"; then
    fail_msg "编辑按钮未先切到选中布局"
fi

# --- 2. UserLayouts 提供按名字操作的实现 ----------------------------------
for fn in 'func renameLayout(named oldName: String, to newName: String)' \
          'func removeLayout(named name: String) -> String?' \
          'func duplicateLayout(named name: String, newName: String)'; do
    if ! grep -q "$fn" "$USERDATA"; then
        fail_msg "UserLayouts 缺少实现：$fn"
    fi
done

# 旧名字的屏幕/空间偏好必须被修正，否则下拉显示悬空名字
if ! grep -q 'spaceLayoutPreferences.spaces\[pair\] = newName' "$USERDATA"; then
    fail_msg "重命名未修正屏幕/空间偏好里的旧名字"
fi
if ! grep -q 'spaceLayoutPreferences.spaces\[pair\] = fallbackLayout' "$USERDATA"; then
    fail_msg "删除未把屏幕/空间偏好改指向兜底布局"
fi

# --- 3. 设置窗口的暂存偏好也要同步 ----------------------------------------
if ! grep -q 'func syncLayoutReference(from oldName: String, to newName: String)' "$STATE"; then
    fail_msg "SettingsState 缺少 syncLayoutReference（暂存偏好会保留旧名字）"
fi
if ! grep -q 'func syncLayoutRemoval(named removedName: String, fallback: String)' "$STATE"; then
    fail_msg "SettingsState 缺少 syncLayoutRemoval"
fi

# --- 结果 ----------------------------------------------------------------
if [[ "$fail" -ne 0 ]]; then
    echo "FAIL: 布局选择一致性回归未通过"
    exit 1
fi

echo "PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）"
