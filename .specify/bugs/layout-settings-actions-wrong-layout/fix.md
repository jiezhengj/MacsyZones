# Bug Fix: 设置里的布局操作永远作用于当前活动布局

- **Slug**: layout-settings-actions-wrong-layout
- **Fixed**: 2026-11-22
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

设置窗口的「布局」区改为只认一个选中布局（`selectedLayoutName`），四个按钮与下拉共用它；`UserLayouts` 补上按名字的 `renameLayout`/`removeLayout`/`duplicateLayout`，并在改名/删除时同步修正屏幕与空间偏好。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `MacsyZones/SettingsView.swift` | modified | `LayoutSettingsSection` 增加 `selectedLayoutName`/`selectedLayout`，Picker、编辑、删除、网格信息统一读它；`RenameView`/`DuplicateView` 改为接收 `sourceLayoutName` |
| `MacsyZones/UserData.swift` | modified | 新增 `renameLayout(named:to:)`、`removeLayout(named:) -> String?`、`duplicateLayout(named:newName:)`；旧 current 版改为薄包装；改名/删除会修正 `spaceLayoutPreferences.spaces` |
| `MacsyZones/SettingsState.swift` | modified | 新增 `syncLayoutReference(from:to:)`、`syncLayoutRemoval(named:fallback:)`，同时更新 `tempSpacePreferences` 与 `originalSpacePreferences` |
| `scripts/check_layout_selection.sh` | added | 断言设置区不再调用 current 版 API、下拉与按钮共用 `selectedLayoutName`、按名字实现与偏好修正存在 |

## Diff Highlights

```swift
// SettingsView.swift：下拉与按钮共用同一个名字
var selectedLayoutName: String { state.getLayoutForCurrentScreen() ?? layouts.currentLayoutName }
var selectedLayout: UserLayout { layouts.layouts[selectedLayoutName] ?? layouts.defaultLayout }
```

```swift
// UserData.swift：改名时同步偏好，避免下拉悬空
for (pair, name) in spaceLayoutPreferences.spaces where name == oldName {
    spaceLayoutPreferences.spaces[pair] = newName
}
```

## Tests Added or Updated

- `scripts/check_layout_selection.sh` — 断言 `renameCurrentLayout(`/`removeCurrentLayout(`/`duplicateCurrentLayout(` 在 `SettingsView.swift` 中零命中；断言 `selectedLayoutName`、`removeLayout(named: removedName)`、`sourceLayoutName: selectedLayoutName`、`layouts.selectLayout(selectedLayoutName)` 存在；断言 `UserData.swift` 三个新签名与 `spaceLayoutPreferences.spaces[pair] = newName` / `= fallbackLayout`；断言 `SettingsState.swift` 两个 sync 函数存在。

## Local Verification

- Commands run: `bash scripts/check_layout_selection.sh` → `PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）`。
- Commands run: `bash scripts/check_lazy_lifecycle.sh` → `PASS: 139 assertions ...`（布局增删改仍走惰性物化路径）。
- Commands run: `bash scripts/build-debug.sh` → `BUILD SUCCEEDED`、签名校验 PASS，警告仅基线一条。
- Commands run: `bash scripts/build-permission-artifact.sh` → 正式版已替换并启动稳定，权限探针 `windowControl`/`inputMonitoring` 均 `granted`。
- Manual checks: 无点击级复现（TCC 阻断自动化），仅静态与构建证据。

## Deviations from Assessment

评估只点名设置区与 `UserLayouts`；实现时发现仅改设置区不够——偏好在 `spaceLayoutPreferences` 里也存了布局名，改名/删除后会留下悬空引用并被写回磁盘，因此扩展了 `MacsyZones/SettingsState.swift` 与 `UserData.swift` 的偏好修正（范围扩张已记录于此）。

## Follow-ups

- 人工验收：设置 → 布局下拉选 `小屏` → 重命名/复制/删除，确认作用于 `小屏`，下拉随之更新。
- 布局增删改会立即写盘，不进入「保存/取消」暂存模型；若希望可撤销，需要另立 feature。
- 重命名同名布局现为提示而非静默覆盖，属行为变化，需在发布说明里提及。
