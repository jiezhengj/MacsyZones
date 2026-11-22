# Bug Fix: 编辑布局时按设置里选中的显示器摆放编辑框

- **Slug**: editor-window-wrong-screen
- **Fixed**: 2026-11-22
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

编辑链路里新增「目标屏幕」：设置界面把当前选中的显示器传给 `startEditing(on:)`，布局窗口、每个区块编辑框、新建区块、以及保存时的百分比换算都以这块屏幕为准；跨屏提示文案也改写成「一个布局只属于一个屏幕」的解释。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `MacsyZones/Macsy.swift` | modified | 新增 `startEditing(on:)` / `toggleEditing(on:)`；无参版本委托为 `nil`（菜单栏、快捷键仍按鼠标所在屏幕） |
| `MacsyZones/Layout.swift` | modified | `LayoutWindow` 记录 `editingScreen`；`startEditing(on:)` 用它铺窗口与每个区块；`SectionWindow.init`/`reset`/`startEditing` 接受屏幕；`EditorSectionWindowDelegate.originalScreen` 改为显式目标屏幕；`onNewSection` 让新加区块落在目标屏幕；`onSave` 百分比一律按 `editingScreen` 归一化；编辑条在目标屏幕上居中；跨屏提示文案重写 |
| `MacsyZones/Screen.swift` | modified | 新增 `centerWindowOnScreen(_:screen:)` |
| `MacsyZones/SettingsState.swift` | modified | 新增 `selectedScreen`（按 `selectedScreenIndex` 取屏幕，越界回退鼠标屏） |
| `MacsyZones/SettingsView.swift` | modified | 编辑按钮改为 `toggleEditing(on: state.selectedScreen)` |
| `scripts/check_editor_screen.sh` | added | 静态断言 + 双屏百分比算术断言 |
| `scripts/tests/lazy-stubs.swift` | modified | 桩补 `NSScreen`、`startEditing(on:)`、`reset(sectionConfig:on:)` 签名 |

## Diff Highlights

```swift
// MacsyZones/SettingsView.swift —— 编辑按设置里选中的显示器
toggleEditing(on: state.selectedScreen)

// MacsyZones/Layout.swift —— 目标屏幕贯穿到窗口与区块
func startEditing(on screen: NSScreen? = nil) {
    isEditing = true
    let targetScreen = screen ?? getFocusedScreen()
    editingScreen = targetScreen
    ...
    sectionWindow.startEditing(on: targetScreen)
    sectionWindow.reset(sectionConfig: sectionWindow.sectionConfig, on: targetScreen)
}

// MacsyZones/Layout.swift —— 保存按目标屏幕归一化
let saveScreen = editingScreen ?? getFocusedScreen()
```

## Tests Added or Updated

- `scripts/check_editor_screen.sh` — 编辑入口必须带屏幕参数、`reset` 走 `getRect(on:)`、`originalScreen` 来自显式屏幕、`onSave` 以 `editingScreen` 为基准、设置界面传 `state.selectedScreen`、提示文案为新版；并断言同一组百分比在内置屏（1470×956）与外置屏（2560×1440，origin x=1470）上换算成不同像素。
- `scripts/tests/lazy-stubs.swift` — 让 `check_lazy_lifecycle.sh` 抽取真实源码后仍可编译（139 断言保持通过）。

## Local Verification

- `bash scripts/build-debug.sh` → `** BUILD SUCCEEDED **` + `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）`。
- `bash scripts/check_editor_screen.sh` → `PASS: 目标屏幕解析正确（同一百分比按各屏尺寸换算，不会跨屏串味）` + `PASS: 编辑目标屏幕回归通过（设置选中的显示器决定编辑框与保存基准）`。
- `bash scripts/check_layout_selection.sh` / `check_layout_geometry.sh` / `check_lazy_lifecycle.sh` → 全部 PASS（139 断言）。
- GUI 实测（`agent-desktop`/AXUIElement 驱动 `/Applications/MacsyZones.app`，pid 21136）：
  - 设置里选 **内置显示器**（`Built-in Retina Display`）+ 布局 `小屏` → 点编辑：`Macsy Layout` 窗口落在 `(0,33) 1470×923`（内置屏），编辑条落在 `(735,495)`（内置屏居中）。
  - 点「新建区域」：新蓝框 `735×478 at (368,239)`，完整落在内置屏 `0…1470 × 33…956` 内。
  - 保存后 `UserLayouts.json`：`w=0.5 h=0.5 x=0.250340 y=0.25` → 按内置屏换算为 `1470×829?`… 实际 `735×478 at (368,239)`，与蓝框一致（说明百分比以目标屏幕为基准）。
  - 切到 **外置显示器**（`U27N3G6R4B`）再编辑：`Macsy Layout` 变为 `(1470,-454) 2560×1361`，区块窗口同步落在外置屏；证明目标屏幕跟随设置选择。
  - 测试产生的临时区块已删除、`小屏` 恢复为 0 个区块，应用已重启（pid 21442）。
- 未能自动化：用合成 `CGEvent` 拖拽编辑框跨屏（合成事件未驱动窗口移动），因此「拖到别的屏被弹回 + 新文案」仅做了源码级验证，需人工确认一次。

## Deviations from Assessment

- 评估只写到 `SectionWindow.reset` 需要目标屏幕；实测发现**新建区块**（`onNewSection` → `SectionWindow.init`）同样会用鼠标屏，若不改则「编辑空布局、点 +」仍会把蓝框放到外置屏。已把 `init` 与 `onNewSection` 一并纳入目标屏幕。
- 另外补了编辑条居中到目标屏幕（否则编辑条仍跑到鼠标屏），评估未列出。
- 更新了 `scripts/tests/lazy-stubs.swift`（评估未提到），因为该回归脚本抽取真实源码编译，签名变化必须同步桩。

## Follow-ups

- 人工确认一次跨屏拖拽：应看到「一个布局只属于一个屏幕」提示并被移回。
- 可考虑：布局没有任何区块时不显示该提示（避免空布局下拖拽被弹回却无从下手）。
- 单屏用户行为未变（`editingScreen` 回退 `getFocusedScreen()`）。
