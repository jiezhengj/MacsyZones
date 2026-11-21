# 研究结论与实施决策

本文件回答 plan 的 Phase 0 问题：每一项回移怎么落、落在哪里、为什么不用更省事的做法。所有行号均指本仓库当前 `custom` 分支。

## R1 回移方式：手工移植，不做 cherry-pick

**决策**：逐项读上游提交 diff，按 fork 现有结构手工落地，每项标注上游提交哈希作为溯源；提交粒度按切片而非按上游提交。

**理由**：

- 上游已重写历史，旧 tag `v3.0.4` 与上游新 tag 对象不兼容，`git cherry-pick` 的 base 与实际祖先不一致（`custom...upstream/main` = 246 ahead / 213 behind，merge-base 停在 `5e92007`，2024-10-14）。
- 目标文件结构不同：设置界面 fork 是 `MacsyZones/SettingsView.swift`（暂存式 `SettingsState`），上游是 `Popover.swift`（直连 `appSettings.save()`）；`Switcher.swift` 已被 fork 的 `ee31dbc` 删除；`App.swift` 的观察器实现两套并存（fork 用 `entries[pid].windows` 注册表 + 双移动通知，上游用 `observedWindowIDs` 集合 + `scheduleObserveRetry`）。
- `git patch`/`git apply` 在 `QuickSnapper.swift` 之外的所有切片都会大面积冲突，冲突解决成本高于直接重写局部。

**替代方案**：`git cherry-pick b83b923 08a028a b77e366 ada5b51 7719891` —— 在 `QuickSnapper.swift`（逐字节一致）上可行，但其余四个提交冲突，且会把上游的 `Popover.swift` 绑定强行带进来。

## R2 对账的落点：`WindowObserverManager.reconcile(pid:axWindows:)`

**决策**：在 `MacsyZones/App.swift` 的 `WindowObserverManager` 内新增 `reconcile(pid:axWindows:)`，用 fork 已有注册表计算差集，不做第二套状态。

- 差集来源：`entries[pid]?.windows.keys`（`[UInt32: WindowEntry]`，`WindowEntry` 持有 `element` 与 `notifications`）已经是「已观察集合」，无需新增 `observedWindowIDs`。
- CG 侧：`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` 取 `kCGWindowOwnerPID == pid`、`kCGWindowLayer == 0` 的窗口号；只处理差集，空差集直接返回。
- 元素补偿：先 `MacsyZones/Macsy.swift:1036` 的 `retrieveFreshWindowElement(for:pid:)`；失败再按 `kCGWindowName` 走 `MacsyZones/Macsy.swift:1068` 的 `retrieveFreshWindowElementByTitle`；两者都失败就放弃（不回退成死循环）。标题为空时跳过标题狩猎（对应边界条件）。
- 补注册走 fork 现有 `observeWindow(pid:element:)`，它已包含 `AXUIElementSetMessagingTimeout(0.75)`、`windowID != 0` 校验、CFEqual 元素替换与通知登记，天然满足 FR-015/FR-016。
- 线程：CG 列表在后台队列读取；注册表写入统一 `Task { @MainActor }`，与 `refreshApplication`（`MacsyZones/App.swift:263-307`）一致。

**替代方案**：把上游 `reconcile` 原样搬进 fork 并在 `observedWindowIDs` 上记账 —— 会在同一管理器里出现「集合 + 字典」双份真相，且与 CFEqual 替换路径脱节，直接违反 FR-016。

## R3 定时重扫：`DispatchWorkItem` 句柄 + 退出取消

**决策**：新增 `scheduleWindowScans(forPid:delays:)`，全局重扫 `[2, 6, 12]` 秒、新启动 App `[1, 3, 7]` 秒；每个延迟创建一个 `DispatchWorkItem` 存进 `pendingScanWorkItems`，`applicationWillTerminate`（`MacsyZones/App.swift:828-836` 现有 monitor 清理处）统一 `cancel()` 并清空。

**理由**：上游用裸 `asyncAfter(deadline:)` 无法取消，App 退出后仍有排队任务；fork 已有退出清理约定（5 个 monitor），FR-013 明确要求退出时取消。工作项内部再 `Task { @MainActor }` 回到主线程，避免 AX/AppKit 跨线程。

**替代方案**：`DispatchSourceTimer` 一次性调度 —— 三档延迟需要三个 timer 或一个要重算的 timer，代码量更大，可取消性没有收益。

## R4 标准窗口三态：`checkStandardWindow(_:) -> StandardWindowCheck`

**决策**：把 `MacsyZones/App.swift:309-319` 的布尔 `isStandardWindow(_:)` 换成私有枚举三态：

- `role` 与 `subrole` 都读到且匹配 → `standard`
- 读到但不匹配 → `notStandard`（永不重试）
- AX 调用失败（`kAXErrorCannotComplete` 等）→ `indeterminate` → `scheduleObserveRetry(attempt:)`，延迟 `150ms × (attempt + 1)`，最多 3 次，超限只记一条日志

**理由**：这正是「窗口在屏上但 AX 初始看不到」的主因；fork 现有布尔判定把 `indeterminate` 直接当 `notStandard` 丢弃，窗口再也不会被观察。重试必须在 `observeWindow` 入口做，而不是在 `refreshApplication`，因为 `refreshApplication` 的窗口列表可能整份取不到。

**替代方案**：只在 `refreshApplication` 失败时重试整个进程 —— 粒度太粗，一个坏窗口会拖住同进程其它窗口的注册进度。

## R5 `quickSnapperZoneLayoutsOnly` 的持久化

**决策**：`AppSettingsData` 增加 `var quickSnapperZoneLayoutsOnly: Bool?`，默认 `true`；`MacsyZones/Settings.swift` 六处同步（结构体字段、`private static let default…`、`@Published`、`load()` 的 `?? 默认值`、`save()` 的构造参数、`resetToDefaults()`）；`MacsyZones/SettingsState.swift` 三处同步（`areSettingsEqual`、`saveAll`、`refresh()` 的 `AppSettingsData(...)` 构造）。

**理由**：与现有 20 个字段完全同构（全部 `Bool?` / `String?` / `CGFloat?`），解码缺字段回退默认值，旧 `AppSettings.json` 不会解码失败（FR-006、边界条件「旧配置升级」）。`SettingsState` 三处漏一处就会出现「开关能点但不保存」或「保存了但脏检测不亮」，这是 fork 自研架构特有的坑。

**替代方案**：用 `@AppStorage` 单独存 —— 绕过 `AppSettings.json` 与 `SettingsState` 暂存/放弃机制，「取消设置」时开关不还原，行为不一致。

## R6 开关落在 `QuickSnapperSettingsSection`

**决策**：在 `MacsyZones/SettingsView.swift` 的 `QuickSnapperSettingsSection`（`:701` 起，「快速吸附」标题在 `:707`）里，`ShortcutInputView`（`:723`）之后、`Divider`（`:731`）之前插入 `Toggle("仅切换区域布局", isOn: ...)`，绑定 `state.tempAppSettings.quickSnapperZoneLayoutsOnly ?? true`，变更后调 `state.checkForChanges()`；说明文字写在 Toggle 的 footer，讲清「关闭后网格布局也会进入 ← / → 循环」。

**理由**：FR-005 指定了位置与暂存式写法；上游 `Popover.swift` 不存在于 fork，直接搬 Toggle 会破坏「取消不生效」的暂存语义。

## R7 光标方向：只补视图层的三个断点

**决策**：

- `SnapResizerMode` 已存在（`MacsyZones/Layout.swift:1878-1881`，`vertical` / `horizontal`），`SnapResizer.init(…, mode:isMouseOverResizer:)` 已接收并保存 `mode`（`:1902`、`:1910`），**不需要新建枚举或改构造签名**。
- 三处断点：`NSHostingView(rootView:)` 补传 `mode:`（`:1921-1922`）；`SnapResizerView` 增加 `var mode: SnapResizerMode = .vertical`（`:2078-2080`）；悬停回调按方向 `push` 光标（`:2102`）。
- 映射沿用上游语义：`mode == .vertical`（竖向细条，拖动改变左右宽度）→ `NSCursor.resizeLeftRight`；`mode == .horizontal` → `NSCursor.resizeUpDown`。

**理由**：编辑器里的调整条走同一 `SnapResizer` 构造（`:1671` 传 `.vertical`、`:1721` 传 `.horizontal`），所以桌面与编辑器自动一致（用户故事 2 的验收点 2 不需要额外改动）。

## R8 惰性物化三处收口

**决策**：

- `MacsyZones/Layout.swift:1292` 的 guard 从 `userLayouts.currentLayout.layoutWindow === self` 改为 `userLayouts.currentLayout.materializedLayoutWindow === self`（前者是物化 getter，比较行为本身就会创建窗口）。
- `EditorSectionWindowDelegate.init()`（`:706-715`）只保留 `sectionWindow` / `originalScreen` 赋值；`warningDialog` 首次 `showScreenChangeWarning()` 时才创建（对齐上游 `upstream/main:MacsyZones/Layout.swift:591-606`）。
- `ScreenChangeWarningDialog.init()`（`:653-660`）的 `onDismiss` 改为 `{ [weak self] in self?.dismiss() }`，断开 dialog → panel → hosting view → 闭包 → dialog 的环。

**理由**：`UserData.swift:170-200` 已提供 `materializedLayoutWindow` 与 `layoutWindow` 两个访问器，语义分工本就存在，改调用点即可；面板懒建与弱引用是上游已采用的写法，无新设计。

## R9 惰性物化回归脚本：原样移植，已验证

**决策**：把上游 `scripts/check_lazy_lifecycle.sh` 与 `scripts/tests/{README.md,lazy-stubs.swift,lazy-assertions.swift}` 原文移植，零改动；脚本用 `awk` 从真实源码抽片段，再用 `/usr/bin/swift` 编译运行 139 条断言。不额外编写 grep 式检查脚本。

**证据**：在 `/tmp/lazyprobe` 里用上游脚本对 fork 源码试跑：`PASS: 139 assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source`。抽取锚点在 fork 全部命中：`MacsyZones/UserData.swift:152`（`^class UserLayout {`）、`:307`（`^struct UpdateStateData:`）、`MacsyZones/Macsy.swift:348`（`startEditing`）、`:354`（`stopEditing`）、`:361`（`toggleEditing`）、`:372`（`getMenuBarHeight`）。

**理由**：脚本自带「锚点漂移即 fail closed」设计（要求恰好一对起止标记），比 grep 断言可靠；运行不需要 Xcode 界面，符合 SC-004 的客观闸门要求。

**风险**：脚本依赖 `/usr/bin/swift`（命令行工具链），未安装 Xcode CLI tools 时失败——README 里注明前置条件即可，不影响构建脚本。

## R10 构建清单：只取升级检查号

**决策**：`MacsyZones.xcodeproj/project.pbxproj:102` 的 `LastUpgradeCheck = 2600` → `2700`；`MacsyZones.xcodeproj/xcshareddata/xcschemes/MacsyZones.xcscheme:3` 的 `LastUpgradeVersion = "2600"` → `"2700"`。`d93890a` 的其余三项不采纳：`STRING_CATALOG_GENERATE_SYMBOLS`（fork 无字符串目录，加了是空操作）、`MACOSX_DEPLOYMENT_TARGET=$(RECOMMENDED_MACOSX_DEPLOYMENT_TARGET)`（fork 必须固定 27.0）、工程级 Automatic 签名（fork 固定 Manual + Team `74FR87HYTH`）。

## R11 `onChange` 双参数改造（5 处，语义不变）

**决策**：闭包参数改为 `(oldValue, newValue)`，旧值一律 `_`：

| 位置 | 现状 | 目标 |
|---|---|---|
| `MacsyZones/QuickSnapper.swift:189` | `{ index in }` | `{ _, index in }` |
| `MacsyZones/QuickSnapper.swift:193` | `{ newIndex in }` | `{ _, newIndex in }` |
| `MacsyZones/SettingsView.swift:905` | `{ _ in }` | `{ _, _ in }` |
| `MacsyZones/ShortcutInputView.swift:70` | `{ newValue in }` | `{ _, newValue in }` |
| `MacsyZones/ShortcutInputView.swift:73` | `{ shouldStop in }` | `{ _, shouldStop in }` |

**理由**：单参数 `onChange(of:perform:)` 在新 SDK 已弃用；双参数闭包的第二个参数就是原来的值，行为等价。改写后必须重新构建确认无新增警告（SC-008）。

## R12 验证顺序

**决策**：实现阶段每完成一个切片，按「构建 → 脚本断言 → 手工场景」递增验证；`scripts/check-version.sh` 与 `scripts/verify-signing.sh` 只在准备交付给用户验收前跑一次（版本号未变，`check-version.sh` 会以「目标版本必须高于已发布 v2.0.0」为前提，因此本 feature 内不执行发布校验，仅确认脚本本身可用）。

**理由**：用户已裁定不提前登记版本（FR-023），若在实现中途跑发布门禁会产生「必须改 MARKETING_VERSION」的假冲突。
