# 数据模型与状态机

本文件描述本 feature 涉及的数据结构与状态迁移。这里的「模型」不指新增类型文件，而是既有结构要扩出的字段、要遵守的校验规则与生命周期。

## 1. AppSettingsData（扩展）

`MacsyZones/Settings.swift:15-22` 的 `Codable` 结构体，落盘为 `AppSettings.json`。

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `quickSnapperZoneLayoutsOnly` | `Bool?` | `true`（`defaultQuickSnapperZoneLayoutsOnly`） | 新增。`true` 时快速吸附的 ← / → 只在区域布局（`layoutType == .zone`）之间循环 |

**校验与迁移规则**：

- 解码：`settings.quickSnapperZoneLayoutsOnly ?? quickSnapperZoneLayoutsOnly`（即 `??` 到默认 `true`），与其余 20 个字段同构。
- 不允许强解包；`AppSettingsData` 解码失败时保留当前内存值并记 `debugLog`（既有 catch 分支）。
- 缺字段 → 默认 `true`（老用户升级后行为等于上游 v3.1 的默认）；多余字段由 `Codable` 自动忽略。
- 重置：`resetToDefaults()` 必须把它写回 `true`。
- 参与脏检测：`SettingsState.areSettingsEqual` 必须比较该字段，否则用户在设置窗口切换后「保存」按钮不亮。

**关联的持久化入口（必须同步的六 + 三处）**：

- `MacsyZones/Settings.swift`：结构体字段、`private static let default…`、`@Published`、`load()`、`save()` 的 `AppSettingsData(...)`、`resetToDefaults()`
- `MacsyZones/SettingsState.swift`：`areSettingsEqual`、`saveAll`、`refresh()` 的 `AppSettingsData(...)`

## 2. 布局循环集合（LayoutCycleSet）

由 `userLayouts.layouts`（`[String: UserLayout]`）按当前设置投影出的有序键序列，供 `prevLayoutHotkey` / `nextLayoutHotkey` 的两个闭包使用（`MacsyZones/QuickSnapper.swift:561-573`、`:581-593`）。

| 概念 | 定义 |
|---|---|
| 候选集合 | `quickSnapperZoneLayoutsOnly == true` 时 `layouts.filter { $0.value.layoutType == .zone }`，否则全集 `layouts` |
| 排序 | `.keys.sorted()`（字典稳定序，保持与现状一致） |
| 空集处理 | 立即 `return`，不改当前布局、不调用 `show()` / `setCurrent()` |
| 当前位置 | `sortedKeys.firstIndex(of: userLayouts.currentLayoutName) ?? 0`；当前布局不在集合内（如当前是网格布局）时从第一个元素起步 |
| 步进 | 上：`(index - 1 + count) % count`；下：`(index + 1) % count` |

**状态迁移**：`currentLayoutName ∈ 候选集合` → 按步进切换；`∉` → 落到 `sortedKeys[0]`（`layoutType == .zone` 时即「从第一个区域布局起步」）。任何一条路径都不得留下「已 `hideAllWindows()` 但新布局未 `show()`」的中间态——现有代码先 `hideAllWindows()` 再算索引，空集分支必须在这之前返回，或改为先算后隐藏（实现时二选一，以不闪烁为准）。

## 3. 窗口观察登记（WindowObservationRegistry）

既有结构（`MacsyZones/App.swift`），本 feature 只新增「对账」这个写入路径，不改结构。

```text
WindowObserverManager
└── entries: [pid_t: AppEntry]
    AppEntry
    ├── observer: AXObserver
    ├── appElement: AXUIElement
    ├── observesWindowCreation: Bool
    ├── shouldRetryWindowCreation: Bool
    └── windows: [UInt32: WindowEntry]
        WindowEntry
        ├── element: AXUIElement
        └── notifications: [CFString]     # kAXMoved / kAXWindowMoved / kAXUIElementDestroyed
```

**不变量**：

- `windows` 的键是 `getWindowID(from:)` 的非零结果；`0` 一律拒绝注册（`MacsyZones/App.swift:173-176`）。
- 同一 windowID 再注册时按 `CFEqual` 判定：相同元素直接复用，不同元素先移除旧通知再替换（`:180-188`）。
- 所有写入都在主 actor 上完成；读取（对账时的差集计算）也在主 actor 上，CG 扫描在后台。

## 4. 对账视图（ReconcileView）

一次 `reconcile(pid:axWindows:)` 调用的输入输出快照，用于日志与自测断言。

| 字段 | 来源 | 说明 |
|---|---|---|
| `pid` | 调用方 | 目标进程 |
| `axWindows` | `AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute)` | AX 侧窗口元素列表（可能为空/不全） |
| `axIDs` | `axWindows.map(getWindowID)` | AX 侧可见的窗口号集合 |
| `observedIDs` | `entries[pid].windows.keys` | 已登记的窗口号集合 |
| `cgWindows` | `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)` 过滤 `ownerPID == pid && layer == 0` | 屏上实际存在的窗口（含 title、bounds） |
| `missingIDs` | `cgWindows.keys - axIDs` | 需要补偿注册的窗口号（空集 → 直接返回） |
| `hunted` | 每个 missing 的补偿结果 | `.byWindowID` / `.byTitle(title)` / `.failed` |

**规则**：

- 只处理 `missingIDs`，且只对 `!observedIDs.contains(id)` 的窗口做注册尝试（已是 `observedIDs` 的跳过，防止抢掉既有精准元素）。
- `title` 为空或狩猎失败 → 记一条 debug 日志，不重试（对应边界条件「标题缺失」）。
- 一次对账的窗口数上限沿用屏上窗口自然规模，不做额外截断；但同一 PID 的对账不得并发（用 `Task { @MainActor }` 串行化）。

## 5. 标准窗口判定状态机（StandardWindowCheck）

```text
        role/subrole 读取成功且匹配
初始 ───────────────────────────────► standard ──► 注册观察
  │
  ├── 读取成功但不匹配 ──────────────► notStandard ──► 丢弃，永不重试
  │
  └── AX 调用失败 ──────────────────► indeterminate ──► 重试队列
                                          │  attempt < 3：150ms × (attempt+1) 后再判
                                          └─ attempt == 3：记日志放弃
```

**规则**：`indeterminate` 只来自 AX 调用失败（`roleStatus != .success` 或 `subroleStatus != .success`），不包含「元素已销毁」（销毁走 `kAXUIElementDestroyed` → `forgetWindow`）。

## 6. 屏幕变更警告对话框生命周期

`MacsyZones/Layout.swift` 的 `ScreenChangeWarningDialog`，从「编辑开始时每分区一个常驻面板」改为按需。

```text
EditorSectionWindowDelegate.init()     : warningDialog = nil
        │  首次跨屏（windowDidChangeScreen 且 hasShownWarning == false）
        ▼
showScreenChangeWarning()              : if warningDialog == nil { 创建 }；show(on: originalScreen)
        │  用户点「知道了」→ dismiss() → panel.orderOut → onDismiss
        ▼
hasShownWarning = false（可再次触发）
        │  编辑器关闭 / delegate 释放
        ▼
dialog 与 panel 释放（onDismiss 为 [weak self]，无环）
```

**不变量**：

- `warningDialog` 的唯一创建点是 `showScreenChangeWarning()`；`init()` 里只赋值 `sectionWindow` 与 `originalScreen`。
- `ScreenChangeWarningDialog.init()` 内部的 `ScreenChangeWarningView(onDismiss:)` 必须是 `[weak self]`。
- `hasShownWarning` 每次 `dismiss` 后复位，保证同一分区第二次跨屏仍会提示。
- 编辑器关闭路径清除 `sectionWindow` 的强引用后，delegate → dialog → panel 整链应可 deinit（SC-005）。
