#!/usr/bin/env bash
# 布局几何回归：百分比 ↔ 点 的往返不能丢点（830 存盘后不能变成 829）。
#
# 三层验证（项目无 XCTest target，沿用 002/003 的脚本断言做法）：
#   1. 静态断言：SectionConfig.getRect/getAXRect 必须按「边缘取整」换算；
#   2. 算术断言：830/1440 这类无法精确表示的比值，取整后必须回到整数；
#   3. 反例断言：如果哪天有人把取整改回直接相乘，脚本必须失败。
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { printf '%s\n' "$*"; }
fail_msg() { printf 'FAIL: %s\n' "$*"; fail=1; }

USERDATA="MacsyZones/UserData.swift"

[[ -f "$USERDATA" ]] || { fail_msg "找不到 $USERDATA"; exit 1; }

# --- 1. 静态断言 ---------------------------------------------------------
if ! grep -q 'let maxX = (screen.frame.origin.x + screen.frame.width \* (xPercentage + widthPercentage)).rounded()' "$USERDATA"; then
    fail_msg "getRect/getAXRect 未按边缘取整计算 maxX（恢复成直接相乘会让 830 变回 829）"
fi
if ! grep -q 'let maxY = (screen.frame.origin.y + screen.frame.height \* (yPercentage + heightPercentage)).rounded()' "$USERDATA"; then
    fail_msg "getRect 未按边缘取整计算 maxY"
fi
if ! grep -q 'let minX = (screen.frame.origin.x + screen.frame.width \* xPercentage).rounded()' "$USERDATA"; then
    fail_msg "getRect/getAXRect 未对 minX 取整"
fi
if grep -q 'let width = screen.frame.width \* widthPercentage' "$USERDATA"; then
    fail_msg "仍存在未取整的 width 计算（回归风险）"
fi

# --- 2. 算术断言 ---------------------------------------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/geometry.swift" <<'SWIFT'
import CoreGraphics

struct Zone {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}

let screenOrigin = CGPoint(x: 0, y: 0)
let screenSize = CGSize(width: 2560, height: 1440)

// 修复前：直接相乘
func legacyRect(_ zone: Zone) -> CGRect {
    CGRect(x: screenOrigin.x + screenSize.width * zone.x,
           y: screenOrigin.y + screenSize.height * zone.y,
           width: screenSize.width * zone.w,
           height: screenSize.height * zone.h)
}

// 修复后：边缘取整（与 SectionConfig.getRect 同构）
func roundedRect(_ zone: Zone) -> CGRect {
    let minX = (screenOrigin.x + screenSize.width * zone.x).rounded()
    let minY = (screenOrigin.y + screenSize.height * zone.y).rounded()
    let maxX = (screenOrigin.x + screenSize.width * (zone.x + zone.w)).rounded()
    let maxY = (screenOrigin.y + screenSize.height * (zone.y + zone.h)).rounded()
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

var failed = false

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        failed = true
        print("FAIL: \(message)")
    }
}

// 用户报告的用例：830 点存盘后回乘
let reported = Zone(x: 0, y: 0.4027777777777778, w: 0.57421875, h: 0.5763888888888888)
let legacyHeight = legacyRect(reported).height
let fixedHeight = roundedRect(reported).height
print("reported zone legacy height=\(legacyHeight) fixed height=\(fixedHeight)")
expect(legacyHeight < 830 && legacyHeight > 829.9, "修复前的算术应当复现 829.9999999999999（证明缺陷真实存在），实际 \(legacyHeight)")
expect(fixedHeight == 830, "修复后高度必须是 830，实际 \(fixedHeight)")
expect(roundedRect(reported).width == 1470, "修复后宽度必须仍是 1470")

// 1100 宽的区块：本来就整除，修复后不能改变
let integral = Zone(x: 0.5703125, y: 0.05486111111111111, w: 0.4296875, h: 0.4791666666666667)
expect(roundedRect(integral).width == 1100, "1100 宽区块取整后必须仍是 1100")
expect(roundedRect(integral).height == 690, "690 高区块取整后必须仍是 690")

// 830/1440 直接输入
expect(roundedRect(Zone(x: 0, y: 0.1, w: 0.5, h: 830.0 / 1440.0)).height == 830,
       "830/1440 比值的区块取整后必须是 830")

// 相邻区块共享边不能错缝：左块 maxX 必须等于右块 minX
let left = Zone(x: 0.25, y: 0, w: 0.3333333333333333, h: 1)
let right = Zone(x: 0.25 + 0.3333333333333333, y: 0, w: 0.4166666666666667, h: 1)
let leftRect = roundedRect(left)
let rightRect = roundedRect(right)
expect(leftRect.maxX == rightRect.minX,
       "相邻区块共享边必须落在同一条整点线：left.maxX=\(leftRect.maxX) right.minX=\(rightRect.minX)")

exit(failed ? 1 : 0)
SWIFT

if ! /usr/bin/swift "$tmpdir/geometry.swift"; then
    fail_msg "几何算术回归失败"
fi

# --- 3. 结果 -------------------------------------------------------------
if [[ "$fail" -ne 0 ]]; then
    echo "FAIL: 布局几何回归未通过"
    exit 1
fi

echo "PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）"
