# Bug Assessment: 编辑布局时蓝框出现在错误的显示器，拖到目标显示器被弹回

- **Slug**: editor-window-wrong-screen
- **Created**: 2026-11-22
- **Source**: pasted text（用户口述复现）
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

> 还有 bug。比如我现在“小屏”方案是针对内置显示器的，但设置界面里选中内置显示器，再选中“小屏”方案，再点编辑，蓝色的框却永远出现在外置大屏显示器，还没法拖到内置显示器里，拖过去就会被弹回来，还会出现一个莫名其妙的对话框里写了一些我看不懂的文案。

## Symptom

在「设置 → 布局」里选中内置显示器与「小屏」布局后点击编辑，蓝色区块编辑框出现在鼠标所在的另一块显示器（外置大屏）上；用户试图把它拖到内置显示器时，窗口被强制挪回原显示器，并弹出「布局设计 / 布局可以在一个屏幕上设计。」对话框。期望：编辑「小屏」时，编辑框出现在设置里选中的那块显示器上。

## Reproduction

1. 接两块显示器（内置 1470×956、外置 2560×1440，外置在右侧）。
2. 打开 MacsyZones 设置 → 「布局」，上方选中「内置显示器」，下拉选中「小屏」。
3. 把鼠标移到外置显示器上，点击该区的「编辑」。
4. 观察：蓝色编辑框出现在外置显示器；把它拖向内置显示器 → 弹「布局设计」对话框，编辑框被挪回外置显示器。

补充：同样的操作在鼠标位于内置显示器时，编辑框会正确出现在内置显示器，说明结果取决于**点击那一刻鼠标在哪块屏幕上**。

## Suspected Code Paths

- `MacsyZones/Screen.swift:15-33` — `getFocusedScreen()` 返回**鼠标指针所在的屏幕**（找不到时回退 `lastFocusedScreen` / `NSScreen.main`）。这是整个问题的源头：编辑路径没有真正的「目标屏幕」参数，全部退化成「鼠标屏」。
- `MacsyZones/UserData.swift:731-754` — `SectionConfig.getRect(on targetScreen: NSScreen? = nil)`：不传屏幕时用 `getFocusedScreen()` 计算区块矩形。
- `MacsyZones/Layout.swift:792-793` — `SectionWindow.init` 用 `sectionConfig.getRect()`（即鼠标屏）作为窗口与编辑框的 contentRect。
- `MacsyZones/Layout.swift:1064-1066` — `LayoutWindow.init` 用 `getFocusedScreen()` 决定整张布局窗口的尺寸。
- `MacsyZones/Layout.swift:1823-1846` — `LayoutWindow.startEditing()` 用 `getFocusedScreen().visibleFrame` 铺设编辑层，并在 `reset` 时再次按鼠标屏重算每个区块。
- `MacsyZones/Layout.swift:708` — `EditorSectionWindowDelegate.init` 把 `originalScreen` 记为 `editorWindow.screen`（创建时的鼠标屏），而不是布局应所属的屏幕。
- `MacsyZones/Layout.swift:724-747` — `windowDidChangeScreen`：跨屏时弹提示并把窗口挪回 `originalScreen`（这就是「拖过去被弹回来」）。
- `MacsyZones/Layout.swift:552-611` — `ScreenChangeWarningView`：那段「看不懂的文案」（布局设计 / 布局可以在一个屏幕上设计 / 您可以… / 提示：…）。
- `MacsyZones/Layout.swift:1565-1612` — `onSave()` 里百分比以 `editorWindow.screen`（或鼠标屏）为基准，编辑框若在错误屏幕上，保存的百分比也会按错误屏幕归一化。
- `MacsyZones/SettingsView.swift:280-286` — 编辑按钮直接调用全局 `stopEditing()` / `toggleEditing()`，**没有把设置里选中的屏幕传进去**。
- `MacsyZones/SettingsState.swift:105-127` — `getLayoutForCurrentScreen()` / `setLayoutForCurrentScreen(_:)` 已经按 `selectedScreenIndex` 工作，但这个「选中的屏幕」只用于下拉框，没有进入编辑链路。
- `MacsyZones/Macsy.swift:348-371` — `startEditing()` / `stopEditing()` / `toggleEditing()` 只操作 `userLayouts.currentLayout`，无屏幕参数。

## Root Cause Hypothesis

**置信度：高。** 布局编辑链路里根本没有「本次编辑的目标屏幕」这一概念：`LayoutWindow`、`SectionWindow`、`SectionConfig.getRect()`、`onSave()` 全部在调用当刻用 `getFocusedScreen()`（鼠标所在屏幕）解析屏幕；设置界面里的 `selectedScreenIndex`（以及屏幕→布局的 `spaceLayoutPreferences`）只影响下拉框显示，从未传给编辑链路。于是「选内置显示器 + 小屏 + 编辑」时，只要鼠标在外置屏上，编辑框就全铺在外置屏；`EditorSectionWindowDelegate` 又把外置屏记成 `originalScreen`，跨屏拖动被判定为越界，触发提示并弹回。

## Proposed Remediation

**Preferred**：给编辑链路增加显式的目标屏幕，并让设置里的选择决定它。

1. 新增编辑入口带屏幕参数：`MacsyZones/Macsy.swift` 增加 `startEditing(on screen: NSScreen?)`，内部把它交给 `LayoutWindow.startEditing(on:)`；原无参 `startEditing()` / `toggleEditing()` 保留（取 `getFocusedScreen()`）以兼容菜单栏点击。
2. `MacsyZones/Layout.swift`：`LayoutWindow` 记录 `editingScreen: NSScreen?`，`startEditing(on:)` 用该屏幕铺窗口与编辑层；`SectionWindow.reset` 增屏幕参数、内部用 `sectionConfig.getRect(on: screen)`；`EditorSectionWindowDelegate.originalScreen` 改为显式传入的 `editingScreen`（而不是 `editorWindow.screen`）。
3. `MacsyZones/Layout.swift` `onSave()`：百分比一律按 `editingScreen`（回退 `editorWindow.screen`）归一化，避免编辑框被拖到别的屏幕后把错误尺寸写回。
4. `MacsyZones/SettingsView.swift:280-286`：编辑按钮改为 `startEditing(on: state.availableScreens[safe: state.selectedScreenIndex])`（越界回退 `getFocusedScreen()`），从而「设置里选哪块屏，就在哪块屏编辑」。
5. 重写 `ScreenChangeWarningView` 文案，说明「一个布局只对应一个屏幕；想给另一块屏幕排布，请回到设置选中该屏幕后编辑，或新建布局」，按钮改为「知道了」。

**Alternatives**：
- 允许跨屏编辑：放弃「一个布局一个屏幕」的模型，需重做百分比基准与屏幕切换，改动与回归风险大，不采纳。

**Files likely to change**：
- `MacsyZones/Screen.swift`（可能加 `availableScreens[safe:]` 或屏幕解析辅助）
- `MacsyZones/Layout.swift`
- `MacsyZones/Macsy.swift`
- `MacsyZones/SettingsView.swift`
- `MacsyZones/SettingsState.swift`（暴露「当前选中屏幕」的 `NSScreen`）
- `scripts/check_editor_screen.sh`（新增静态回归）
- `specs/` 无关；`.specify/bugs/STATUS.md` 需登记

**Tests to add or update**：
- `scripts/check_editor_screen.sh`：断言 `startEditing(on:)` 签名存在、`SettingsView` 编辑按钮传屏、`SectionWindow.reset(sectionConfig:on:)` 使用 `getRect(on:)`、`onSave` 使用 `editingScreen`、`Layout.swift` 编辑路径不再出现无屏参数的 `getRect()`。
- 人工/GUI 验收：按复现步骤在两块屏场景下确认蓝框跟随设置所选屏幕；跨屏拖动仍弹提示且弹回；保存后百分比与该屏幕匹配（用 `defaults read`/`UserLayouts.json` 核对）。

## Risks & Considerations

- 单屏用户不受影响（回退到 `getFocusedScreen()`）。
- 多屏且布局之间共享 `sectionConfigs` 的场景需确认不会把 A 屏的百分比按 B 屏尺寸归一化（`onSave` 必须只用一个屏幕基准）。
- 屏幕热插拔：`editingScreen` 需在 `NSApplication.didChangeScreenParametersNotification` 后失效回退。
- 右键菜单/快捷键触发的编辑没有「设置选中屏幕」上下文，保持 `getFocusedScreen()` 语义。

## Open Questions

- 无阻塞问题；文案措辞可在实现时按用户偏好再调。
