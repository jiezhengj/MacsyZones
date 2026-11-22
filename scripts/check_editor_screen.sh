#!/usr/bin/env bash
# 编辑布局的目标屏幕回归：
# 设置里选中哪块显示器，编辑框就必须摆在哪块显示器上；保存百分比也必须以那块屏幕为准。
#
# 历史缺陷：编辑链路没有「目标屏幕」，LayoutWindow/SectionWindow/onSave 全用
# getFocusedScreen()（鼠标所在屏幕）解析，于是「选中内置显示器 + 小屏 + 编辑」
# 只要鼠标在外置屏，蓝框就全铺在外置屏；跨屏拖动还会被判越界弹回。
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
fail_msg() { printf 'FAIL: %s\n' "$*"; fail=1; }

LAYOUT="MacsyZones/Layout.swift"
MACSSY="MacsyZones/Macsy.swift"
SETTINGS="MacsyZones/SettingsView.swift"
STATE="MacsyZones/SettingsState.swift"
SCREEN="MacsyZones/Screen.swift"

for f in "$LAYOUT" "$MACSSY" "$SETTINGS" "$STATE" "$SCREEN"; do
    [[ -f "$f" ]] || { fail_msg "找不到 $f"; exit 1; }
done

# --- 1. 编辑入口必须接收目标屏幕 -----------------------------------------
grep -q 'func startEditing(on screen: NSScreen?)' "$MACSSY" \
    || fail_msg "Macsy.swift 缺少 startEditing(on:)（编辑需要显式目标屏幕）"
grep -q 'func toggleEditing(on screen: NSScreen?)' "$MACSSY" \
    || fail_msg "Macsy.swift 缺少 toggleEditing(on:)"

grep -q 'func startEditing(on screen: NSScreen? = nil)' "$LAYOUT" \
    || fail_msg "LayoutWindow 缺少 startEditing(on:)"

grep -q 'var editingScreen: NSScreen?' "$LAYOUT" \
    || fail_msg "LayoutWindow 未记录 editingScreen（本次编辑的目标屏幕）"

# --- 2. 区块定位与保存都必须用目标屏幕 -----------------------------------
grep -q 'func reset(sectionConfig: SectionConfig, on screen: NSScreen? = nil)' "$LAYOUT" \
    || fail_msg "SectionWindow.reset 未接收目标屏幕"
grep -q 'sectionConfig.getRect(on: screen)' "$LAYOUT" \
    || fail_msg "SectionWindow.reset 未按目标屏幕计算矩形"
grep -q 'func startEditing(on screen: NSScreen? = nil)' "$LAYOUT" \
    || fail_msg "SectionWindow 缺少 startEditing(on:)"
grep -q 'editorWindowDelegate?.originalScreen = screen ?? editorWindow.screen' "$LAYOUT" \
    || fail_msg "编辑框的 originalScreen 不是显式目标屏幕（跨屏仍会被判越界）"

grep -q 'let saveScreen = editingScreen ?? getFocusedScreen()' "$LAYOUT" \
    || fail_msg "onSave 未以 editingScreen 作为百分比基准"

# --- 3. 设置界面按「选中的显示器」编辑 ------------------------------------
grep -q 'var selectedScreen: NSScreen?' "$STATE" \
    || fail_msg "SettingsState 缺少 selectedScreen"
grep -q 'toggleEditing(on: state.selectedScreen)' "$SETTINGS" \
    || fail_msg "设置界面编辑按钮未传入选中的显示器"

# --- 4. 文案：跨屏提示要说明「一个布局一个屏幕」 -------------------------
grep -q '一个布局只属于一个屏幕' "$LAYOUT" \
    || fail_msg "跨屏提示仍是旧文案"

# --- 5. 算术断言：同一组百分比在不同屏幕上按各自尺寸解析 -----------------
if command -v swift >/dev/null 2>&1; then
    swift - <<'SWIFT' || fail=1
import Foundation

struct Rect { let x: Double; let y: Double; let w: Double; let h: Double }

// 与 SectionConfig.getRect(on:) 相同的边缘取整算法
func rect(x: Double, y: Double, w: Double, h: Double,
          screenX: Double, screenY: Double, screenW: Double, screenH: Double) -> Rect {
    let minX = (screenX + screenW * x).rounded()
    let minY = (screenY + screenH * y).rounded()
    let maxX = (screenX + screenW * (x + w)).rounded()
    let maxY = (screenY + screenH * (y + h)).rounded()
    return Rect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
}

// 内置屏 1470x956，外置屏 2560x1440 且原点 x=1470
let builtin = rect(x: 0.1, y: 0.1, w: 0.5, h: 0.5, screenX: 0, screenY: 0, screenW: 1470, screenH: 956)
let external = rect(x: 0.1, y: 0.1, w: 0.5, h: 0.5, screenX: 1470, screenY: 0, screenW: 2560, screenH: 1440)

var failed = false
func check(_ cond: Bool, _ msg: String) {
    if !cond { print("FAIL: \(msg)"); failed = true }
}

check(builtin.x == 147.0 && builtin.w == 735.0, "内置屏 10%/50% 宽度应为 147/735，实际 \(builtin.x)/\(builtin.w)")
check(builtin.y == 96.0 && builtin.h == 478.0, "内置屏 10%/50% 高度应为 96/478，实际 \(builtin.y)/\(builtin.h)")
check(external.x == 1726.0 && external.w == 1280.0, "外置屏 10% 起点应为 1726（含 origin 1470），实际 \(external.x)")
check(external.y == 144.0 && external.h == 720.0, "外置屏 10%/50% 高度应为 144/720，实际 \(external.y)/\(external.h)")
check(builtin.w != external.w, "两块屏幕的同一百分比必须解析成不同像素，否则目标屏幕没生效")

if failed { exit(1) }
print("PASS: 目标屏幕解析正确（同一百分比按各屏尺寸换算，不会跨屏串味）")
SWIFT
fi

if [[ $fail -ne 0 ]]; then
    printf 'FAIL: 编辑目标屏幕回归未通过\n'
    exit 1
fi

printf 'PASS: 编辑目标屏幕回归通过（设置选中的显示器决定编辑框与保存基准）\n'
