# Bug Assessment: 设置里的布局操作永远作用于当前活动布局

- **Slug**: layout-settings-actions-wrong-layout
- **Created**: 2026-11-22
- **Source**: pasted text（用户 m02025 报告第二条）
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim)

> 第二，设置界面的“布局”，选择“大屏”“小屏”方案，下面的修改、修改名称等按钮，点击后永远都是只针对大屏的哪个方案。

## Symptom

设置窗口「布局」下拉里选中 `小屏` 后，点「编辑布局」「重命名布局」「复制布局」「删除布局」，实际作用的仍是全局活动布局（用户这里是 `大屏`），下拉框的选择对按钮无效。

## Reproduction

1. 准备两个以上布局（如 `大屏`、`小屏`），当前活动布局是 `大屏`。
2. 打开设置 → 布局，把下拉切到 `小屏`。
3. 点「重命名布局」：弹窗预填的是 `大屏`（`RenameView.onAppear` 读 `layouts.currentLayoutName`）；确认后 `大屏` 被改名，`小屏` 不变。
4. 点「复制布局」「删除布局」同样作用于 `大屏`；点「编辑布局」进入的也是 `大屏` 的编辑模式。

## Suspected Code Paths

- `MacsyZones/SettingsView.swift:232-234` — `currentLayoutName` 取的是「当前屏幕 + 当前空间的首选布局」：`state.getLayoutForCurrentScreen() ?? layouts.currentLayoutName`。
- `MacsyZones/SettingsView.swift:255-259` — Picker 的 `set` 只写偏好：`state.setLayoutForCurrentScreen($0)`。
- `MacsyZones/SettingsState.swift:118-127` — `setLayoutForCurrentScreen` 只改 `tempSpacePreferences[pair]` + `checkForChanges()`，不碰 `userLayouts.currentLayoutName`。
- `MacsyZones/SettingsView.swift:262-302` — 四个按钮全部走 `layouts.currentLayout` / `layouts.renameCurrentLayout(to:)` / `layouts.removeCurrentLayout()` / `layouts.duplicateCurrentLayout(newName:)`，即全局 `currentLayoutName`。
- `MacsyZones/UserData.swift:614` / `:639` / `:660` — 三个变更函数都以 `currentLayoutName` 为准。
- `MacsyZones/SettingsView.swift:352-359`、`:409` — 重命名/复制弹窗也用 `layouts.currentLayoutName`。

## Root Cause Hypothesis

置信度：high。

「显示哪个布局」和「操作哪个布局」用了两套来源：Picker 显示的是「屏幕 + 空间偏好」（`tempSpacePreferences`），按钮读的是全局活动布局（`UserLayouts.currentLayoutName`）。两者只在「当前屏幕的偏好恰好等于全局活动布局」时一致，因此用户切换下拉后按钮行为不变。

## Proposed Remediation

**Preferred**：让本 section 只有一个「选中布局」事实——`selectedLayoutName = state.getLayoutForCurrentScreen() ?? layouts.currentLayoutName`，Picker 与四个按钮都读它。

- `UserLayouts` 增加按名字操作的实现：`renameLayout(named:to:)`、`removeLayout(named:)`、`duplicateLayout(named:newName:)`；原有 `renameCurrentLayout`/`removeCurrentLayout`/`duplicateCurrentLayout` 改为薄包装（保持其它调用点与上游语义不变）。
- 重命名/删除时同步修正 `spaceLayoutPreferences.spaces` 与 `SettingsState.tempSpacePreferences` 中指向旧名字的键值，避免设置窗口里出现悬空名字（`SpaceLayoutPreferences.get` 的兜底会把悬空名静默换成「第一个布局」，用户会看到下拉自己跳走）。
- 「编辑布局」在选中项不是活动布局时先 `layouts.selectLayout(selectedName)` 再进入编辑；网格布局判断也改看选中项。
- `RenameView` / `DuplicateView` 接收 `layoutName` 参数，弹窗预填与提交都按选中项。

**Alternatives**：
- Picker 的 `set` 直接调用 `layouts.selectLayout(...)` 顺带改全局活动布局——会立刻重排当前屏幕窗口，把「首选项」变成「切换布局」，副作用超出用户预期。
- 只给按钮传名字、不改偏好同步——重命名后下拉会显示旧名字（悬空），问题只修一半。

**Files likely to change**：
- `MacsyZones/SettingsView.swift`
- `MacsyZones/UserData.swift`
- `MacsyZones/SettingsState.swift`
- `scripts/check_layout_selection.sh`（新增静态断言）

**Tests to add or update**：
- 静态断言：`LayoutSettingsSection` 的按钮与弹窗不再直接调用 `renameCurrentLayout`/`removeCurrentLayout`/`duplicateCurrentLayout`。
- 静态断言：`renameLayout(named:to:)` 与 `removeLayout(named:)` 会更新 `spaceLayoutPreferences.spaces` 与 `tempSpacePreferences`。
- 手工验收：下拉选 `小屏` → 重命名 → 只有 `小屏` 改名，下拉跟着变成新名字；删除 → 删除的是 `小屏`。

## Risks & Considerations

- 删除布局时若被多个屏幕/空间偏好引用，需把这些引用改指向兜底布局，否则 `SpaceLayoutPreferences.get` 返回第一个布局的行为会让用户困惑。
- 重命名会写盘（`save()`），与设置窗口「暂存后统一保存」的模型略有出入；但布局增删改本来就是即时生效的既有行为（`createLayout`/`removeCurrentLayout` 也是立刻 `save()`），保持一致性。
- 不影响 002 引入的「布局循环只包含区域布局」开关。

## Open Questions

- 无。
