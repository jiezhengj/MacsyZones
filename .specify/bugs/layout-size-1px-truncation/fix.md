# Bug Fix: 区块尺寸按百分比往返后少 1 点

- **Slug**: layout-size-1px-truncation
- **Fixed**: 2026-11-22
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

把「百分比 → 点」的换算改为按屏幕边界的四条边取整，`830` 存成 `0.5763888888888888` 后回乘不再是 `829.9999999999999` 而是 `830`；持久化格式仍是百分比，`onSave` 的换算方式未动。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `MacsyZones/UserData.swift` | modified | `SectionConfig.getRect(on:)` 改为 `minX/minY/maxX/maxY` 各自 `.rounded()` 后由边相减求宽高 |
| `MacsyZones/UserData.swift` | modified | `SectionConfig.getAXRect(on:)` 同一策略，AX 写入不再拿到亚像素尺寸 |
| `scripts/check_layout_geometry.sh` | added | 静态断言取整实现 + 算术回归（829.9999 → 830、1100 不变、相邻共享边不错缝） |

## Diff Highlights

```swift
// getRect(on:)：边缘取整
let minX = (screen.frame.origin.x + screen.frame.width * xPercentage).rounded()
let maxX = (screen.frame.origin.x + screen.frame.width * (xPercentage + widthPercentage)).rounded()
let minY = (screen.frame.origin.y + screen.frame.height * yPercentage).rounded()
let maxY = (screen.frame.origin.y + screen.frame.height * (yPercentage + heightPercentage)).rounded()
return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
```

## Tests Added or Updated

- `scripts/check_layout_geometry.sh` — 断言两个换算函数必须包含 `maxX`/`maxY`/`minX` 的取整行且不再出现裸 `let width = screen.frame.width * widthPercentage`；内嵌 Swift 断言固定 `1440 × (830/1440) = 830`、`2560 × (1100/2560) = 1100`、1470 与 1100×690 保持不变、左右相邻区块 `left.maxX == right.minX`。

## Local Verification

- Commands run: `bash scripts/check_layout_geometry.sh` → `PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）`，输出行 `reported zone legacy height=829.9999999999999 fixed height=830.0`。
- Commands run: `bash scripts/build-debug.sh` → `** BUILD SUCCEEDED **`、`PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）`，警告仅基线一条。
- Commands run: `bash scripts/build-permission-artifact.sh` → 正式版 `/Applications/MacsyZones.app` 已替换为新构建，`open -a` 启动后进程稳定。
- Manual checks: 用用户实机 `UserLayouts.json` 的真实百分比做算术复核（`/tmp/geom.swift`）：zone1 `1470×830`、zone2 `1100×690`、坐标不变。未做点击级「拖到 830 → 保存 → 重进」的目视确认，本机 GUI 自动化被 TCC 阻断。

## Deviations from Assessment

无。实现与评估的 Preferred 方案一致；`getAXRect` 同样按四边取整（评估已列出该文件，未限制具体函数）。

## Follow-ups

- 人工验收一次拖拽保存，确认窗口实际高度显示 830。
- 若将来持久化格式改为整点像素，可移除这层取整（当前不改格式）。
- 网格布局不走 `SectionConfig`，`scripts/check_lazy_lifecycle.sh` 仍 PASS，无回归。
