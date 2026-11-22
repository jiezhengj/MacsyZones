# Bug Fix: 设置里的布局操作永远作用于当前活动布局

- **Slug**: layout-settings-actions-wrong-layout
- **Fixed**: 2026-11-22
- **Assessment**: ./assessment.md

## 变更摘要

让设置窗口「布局」区只有一个「选中布局」事实，并补齐按名字操作的实现。

- `MacsyZones/SettingsView.swift`
  - `LayoutSettingsSection` 新增 `selectedLayoutName`（`state.getLayoutForCurrentScreen() ?? layouts.currentLayoutName`）与 `selectedLayout`；Picker 与四个按钮、网格信息全部改读它。
  - 编辑按钮：选中项不是活动布局时先 `layouts.selectLayout(selectedLayoutName)`，再进入编辑模式，编辑目标因此是下拉里的那个布局。
  - 删除按钮：`layouts.removeLayout(named: selectedLayoutName)`，并用返回的兜底名同步暂存偏好。
  - `RenameView` / `DuplicateView` 改为接收 `sourceLayoutName`；重命名弹窗预填选中布局，提交调用 `renameLayout(named:to:)`，并新增「已存在同名布局」提示（旧实现会静默覆盖同名布局）。
- `MacsyZones/UserData.swift`
  - 新增 `renameLayout(named:to:)`、`removeLayout(named:) -> String?`（`@discardableResult`）、`duplicateLayout(named:newName:)`；`renameCurrentLayout`/`removeCurrentLayout`/`duplicateCurrentLayout` 变成薄包装，其它调用点与上游语义不变。
  - 重命名/删除会修正 `spaceLayoutPreferences.spaces` 里指向旧名字的项（重命名改指新名字，删除改指兜底布局）并 `spaceLayoutPreferences.save()`，否则下拉会显示悬空名字、保存时又把悬空名字写回磁盘。
- `MacsyZones/SettingsState.swift`
  - 新增 `syncLayoutReference(from:to:)`、`syncLayoutRemoval(named:fallback:)`：同时修正 `tempSpacePreferences` 与 `originalSpacePreferences`，再 `checkForChanges()`，避免「改动已落盘但设置窗口仍显示脏状态」。
- 新增 `scripts/check_layout_selection.sh`：断言设置区不再直接调用三个 current 版 API、四个按钮共用 `selectedLayoutName`、`UserLayouts` 提供按名字的实现与偏好修正、`SettingsState` 提供暂存偏好同步。

## 验证

```
bash scripts/check_layout_selection.sh
# PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）

bash scripts/build-debug.sh
# PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）
```

## 行为变化

- 重命名不再静默覆盖同名布局，改为提示。
- 删除非活动布局时，屏幕/空间偏好改指兜底布局（不再留下悬空引用）。
- 下拉切换本身仍只改「首选布局」，不会立刻重排窗口（保持原语义）。
