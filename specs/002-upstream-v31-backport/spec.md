**Feature Branch**: `002-upstream-v31-backport`
**Created**: 2026-11-21
**Status**: Draft
**Input**: 用户请求：对比上游 `rohanrhu/MacsyZones`（当前 v3.1.1，tip `2d5ce44`）与本 fork `jiezhengj/MacsyZones`（改造基线 v3.0.4，分支 `custom`），把上游仍有效、值得保留的改进回移进 fork。

# 用户场景与独立验收测试

## 用户故事 1：快速吸附里只切区域布局（优先级：P1）

使用快速吸附（QuickSnapper）时，用户在屏幕中按下快捷键唤出快捷吸附面板，用 ← / → 在「布局」之间循环，用 1–9 直接吸附到编号分区。

当前 fork 的布局循环遍历全部布局（`MacsyZones/QuickSnapper.swift:561`、`:581`），会切进网格布局（grid）；而网格布局没有编号分区，切进去之后 1–9 全部失效（`MacsyZones/QuickSnapper.swift:41` 按号查分区必然落空），但界面提示只在区域布局下才显示 1–9（`:138`），用户看到的是提示与行为互相矛盾。上游 v3.1 把循环限定为区域布局，v3.1.1 又把「是否包含网格布局」做成用户可选项。

**为何值得保留**：这是用户可感知的功能失效，不是内部重构；上游实现只改两个闭包，与 fork 该文件基线逐字节一致，回移代价低。

**独立验收测试**：

1. **网格布局存在时循环跳过**：创建 1 个区域布局 + 1 个网格布局，唤出快速吸附反复按 ← / → 各 10 次，循环只落在区域布局上，1–9 在任一停留的布局里都有效。
2. **仅剩一个区域布局**：只有 1 个区域布局（另 1 个网格布局）时循环停在原地，不闪烁、不报错。
3. **开关关闭后恢复全量循环**：在设置里关闭「仅区域布局」后，网格布局重新参与循环；当前布局为网格布局时按 ← / → 能正常离开网格布局，不卡死、不崩溃。
4. **设置即时生效**：切换开关后无需重启 App，下一次唤出快速吸附即按新行为循环。

---

## 用户故事 2：悬停吸附调整器显示正确方向的光标（优先级：P1）

用户把鼠标悬停在两个窗口之间的吸附调整条（snap resizer）上时，光标形状应提示可拖拽的方向：竖向调整条（拖动改变左右宽度）显示左右箭头，横向调整条（拖动改变上下高度）显示上下箭头。

当前 fork 的 `SnapResizerView` 没有方向属性（`MacsyZones/Layout.swift:2079-2081`），构造时也不传方向（`:1921-1922`），悬停一律 `NSCursor.resizeUpDown.push()`（`:2102`），横向调整条也显示上下箭头，与实际拖动方向相反。

**为何值得保留**：一个光标方向直接决定用户是否敢拖；修复点集中在一个视图类，冲突面低。

**独立验收测试**：

1. 悬停竖向调整条 → 左右箭头光标；悬停横向调整条 → 上下箭头光标；移开后光标恢复。
2. 布局编辑器里创建的同类调整条同样按方向显示，不出现「编辑器内正确、桌面错误」的分裂。

---

## 用户故事 3：休眠布局不被意外唤醒，编辑器警告面板按需创建（优先级：P2）

v2.0.0 已实现布局窗口的惰性物化（`MacsyZones/UserData.swift:170-200`）：未显示的布局不创建 NSWindow。现在还剩三处漏口，会让惰性物化形同虚设或造成常驻内存：

1. 全局鼠标移动监视器（`MacsyZones/Layout.swift:1119`）在每次 `mouseMoved` 时用 `userLayouts.currentLayout.layoutWindow === self` 做身份比较（`MacsyZones/Layout.swift:1292`）。这个 getter 会为了比较而把休眠布局物化出来——只是滑一下鼠标，就可能把当前布局的窗口创建出来。
2. 进入布局编辑器时，每个分区（section）在 `EditorSectionWindowDelegate.init()` 里立即构造 `ScreenChangeWarningDialog`（`MacsyZones/Layout.swift:710-714`），即每个分区常驻一个 380×340 的 NSPanel + NSHostingView，哪怕永远不会跨屏。
3. 该对话框的 `onDismiss: { self.dismiss() }`（`MacsyZones/Layout.swift:656-660`）是强引用环（dialog → panel → view → 闭包 → dialog），dialog 与 panel 永不释放。

**为何值得保留**：这是 v2.0.0 已承诺能力的收口，属于「做完一半」的补齐；三处都只改局部，不触碰架构。

**独立验收测试**：

1. **鼠标移动不物化**：冷启动后只移动鼠标 60 秒（不触发吸附、不打开布局），休眠布局的物化计数保持 0（通过调试计数或 `materializedLayoutWindow` 断言）。
2. **编辑器面板计数**：打开只有一个分区的布局编辑器，未发生跨屏时 `ScreenChangeWarningDialog` 实例数为 0；真正跨屏时才创建，且只创建一次。
3. **可释放**：关闭编辑器后触发 deinit 日志，dialog 与 panel 都被释放（无强引用环残留）。

---

## 用户故事 4：屏幕上有、AX 里看不到的窗口也能被观察（优先级：P2）

拖动窗口吸附依赖两个来源：AX 的窗口移动通知（带精确新位置）与鼠标位移。v2.0.0 的 PR #102 加强了 AX 侧（注册校验 + 指数退避、双移动通知、CFEqual 元素替换、按 windowID 节流、>5pt 鼠标位移兜底），但有一个真实缺口：如果某个窗口在屏幕上存在，而 AX 从来没把它返回过（启动初期 `kAXErrorCannotComplete`、App 在后台建窗、AX 列表短暂不全），这个窗口就永远不会被注册观察。它仍然能被拖拽吸附（鼠标兜底），但所有依赖 AX 移动通知的功能——跨屏切换、摇一摇吸附、吸附目标更新——对它失效。

上游 `7719891` 的做法是用 CGWindowList 做对账：取该进程 `layer == 0` 的屏上窗口集合，减去已观察的 AX 窗口集合，对差集窗口按 windowID（必要时按 `kCGWindowName` 标题狩猎）重新取 AX 元素并注册观察；另外补了启动后的定时重扫（全局 [2, 6, 12] 秒，每个新启动 App [1, 3, 7] 秒）与「标准窗口」判定的三态重试（indeterminate 不再被当成永久否）。

**为何值得保留**：这是上游这一版唯一的实质行为改进，且与 fork 已有实现互补而非替换——fork 的双通知、CFEqual、节流、鼠标兜底保留，只补对账入口。

**独立验收测试**：

1. **延迟建窗**：脚本化制造「窗口在屏幕上但 AX 初始不返回」的场景（启动期不可达 / 后台建窗），窗口在 12 秒内被观察，之后拖动可触发依赖 AX 移动通知的行为（跨屏、摇一摇）。
2. **激活即对账**：切换应用激活时立即对账一次，无需等到下一轮定时扫描。
3. **不空转**：闲置 5 分钟，`ps`/`top` 测得 CPU 占用 ≤ 2%，主线程无 > 50ms 阻塞。
4. **权限缺失不刷屏**：未授予辅助功能权限时，对账与重扫不进入无限重试，日志按退避降频。

---

## 用户故事 5：构建清单与代码健康跟上 Xcode 27（优先级：P3）

- `MacsyZones.xcodeproj/project.pbxproj:102` 的 `LastUpgradeCheck = 2600`，scheme 的 `LastUpgradeVersion` 同为 2600，Xcode 27 打开即提示「推荐设置」。
- 仍有 5 处 `onChange` 单参数写法（`MacsyZones/QuickSnapper.swift:189`、`:193`、`MacsyZones/SettingsView.swift:905`、`MacsyZones/ShortcutInputView.swift:70`、`:73`），在新 SDK 下产生弃用警告。
- 布局惰性物化没有自动化回归防线（`scripts/` 下只有 4 个构建脚本）。

**为何值得保留**：低风险、纯增量，避免每次打开工程都出现噪音警告，也为 P2 的惰性物化收口留一道回归闸门。

**独立验收测试**：

1. Xcode 27 打开工程不再提示升级推荐设置；Debug 与 Release 均构建通过。
2. 五个文件不再产生 `onChange(of:perform:)` 弃用警告，构建日志无新增警告。
3. （可选）`scripts/check_lazy_lifecycle.sh` 可在本地无 Xcode 界面的情况下跑通并通过，断言与真实源码片段保持同步。

---

## 边界与异常情况

- **过滤后集合为空**：库里只有网格布局时，快速吸附的布局循环必须直接返回，不崩溃、不清空面板。
- **当前布局是网格且开启「仅区域布局」**：循环从排序后的第一个区域布局起步，而不是停在原地无响应。
- **旧配置升级**：老用户的 `AppSettingsData` 里没有新字段，读取时必须回退到默认值（默认开启），不能因解码失败丢失全部设置。
- **标题缺失**：`kCGWindowName` 为空（部分 App 不上报标题）时，标题狩猎跳过，只按 windowID 匹配，不允许因此崩溃或无限循环。
- **多显示器 / 全屏空间 / Stage Manager**：对账使用的屏上窗口列表必须能覆盖这些场景；窗口刚被销毁时差集里出现的失效条目必须被丢弃，不注册观察。
- **辅助功能权限被撤销**：运行中权限撤销后，对账与重扫按退避降频，不形成日志风暴。
- **布局编辑器多分区**：多个分区时只有真正跨屏才创建警告面板，关闭编辑器后全部释放。

# 功能需求

## 快速吸附布局循环

- **FR-001**：快速吸附的「上一个布局 / 下一个布局」循环必须只遍历区域布局（`layoutType == .zone`），默认行为与上游 `b83b923` 一致。溯源：`MacsyZones/QuickSnapper.swift:561-573`、`:581-593`。
- **FR-002**：过滤后集合为空时必须提前返回，不改变当前布局、不崩溃（`guard !sortedKeys.isEmpty`）。
- **FR-003**：当前布局不在过滤后集合中时（例如当前是网格布局），循环必须从排序后的第一个元素起步（`firstIndex(...) ?? 0`）。
- **FR-004**：新增布尔设置项 `quickSnapperZoneLayoutsOnly`（默认 `true`），控制网格布局是否参与循环；关闭后恢复「全部布局」语义。溯源：上游 `08a028a`。
- **FR-005**：设置界面必须在「快速吸附」分区（`MacsyZones/SettingsView.swift:701` 的 `QuickSnapperSettingsSection`）提供中文开关，位置在快捷键输入与分隔线之间（`:723`、`:731`），复用 fork 的暂存式设置写法（`state.tempAppSettings.*` + `state.checkForChanges()`），不使用上游 `Popover.swift` 的直连绑定。
- **FR-006**：`MacsyZones/Settings.swift` 必须在 `AppSettingsData` 字段、默认值、`@Published`、load、save、reset 六处同步该字段；`MacsyZones/SettingsState.swift` 必须在 `areSettingsEqual`（`:136-157`）、`saveAll`（`:180`）、`refresh()` 的 `AppSettingsData(...)` 构造（`:210-233`）三处纳入该字段，确保脏检测与持久化不被新字段绕过。

## 吸附调整器光标

- **FR-007**：`SnapResizerView` 必须携带方向属性（竖向 / 横向），构造处（`MacsyZones/Layout.swift:1921-1922`）按实际方向传入；悬停时光标与拖动方向一致（`:2102` 不再无条件 `resizeUpDown`）。溯源：上游 `b77e366`。

## 惰性物化收口

- **FR-008**：窗口身份比较必须使用已物化窗口（`materializedLayoutWindow`），且比较行为本身不得触发物化；全局鼠标移动路径（`MacsyZones/Layout.swift:1119` → `:1292`）必须满足这一约束。溯源：上游 `ada5b51` 残余部分。
- **FR-009**：`ScreenChangeWarningDialog` 必须改为按需创建（首次 `showScreenChangeWarning()` 时），不再在 `EditorSectionWindowDelegate.init()` 里预先构造（`MacsyZones/Layout.swift:710-714`）。
- **FR-010**：该对话框的关闭回调必须弱引用自身（`MacsyZones/Layout.swift:656-660` 改为 `[weak self]`），保证 dialog 与 panel 可释放。

## 窗口观察对账

- **FR-011**：必须实现 CG ↔ AX 对账：输入进程 PID 与已观察窗口集合，用 `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)` 取 `layer == 0` 的屏上窗口，差集窗口按 windowID 重新获取 AX 元素；windowID 取不到时按 `kCGWindowName` 标题狩猎。溯源：上游 `7719891`，可复用 fork 已有 `MacsyZones/Macsy.swift:1036 retrieveFreshWindowElement(for:pid:)`、`:1068 retrieveFreshWindowElementByTitle`。
- **FR-012**：对账必须在应用激活路径（`didActivateApplicationNotification`）与启动后定时扫描后触发，且与 fork 已有的注册表（`MacsyZones/App.swift:242-255` 的 `forgetWindow`）共用同一份观察状态，不得出现两套重复注册。
- **FR-013**：启动后必须安排全局重扫 [2, 6, 12] 秒；每个新启动的 App 按 [1, 3, 7] 秒重扫。定时任务必须在 App 退出时取消。
- **FR-014**：窗口「是否标准窗口」判定必须区分 standard / notStandard / indeterminate 三态；indeterminate 必须进入重试队列而不是被判死（`MacsyZones/App.swift:309-319` 现为布尔）。
- **FR-015**：对账与重扫必须带退避与上限，AX 权限缺失或进程消失时不得无限重试、不得日志风暴；对已失效窗口元素必须走 fork 现有的 CFEqual 替换路径（`MacsyZones/App.swift:180-188`）。
- **FR-016**：必须保留 fork 已有的观察增强，不得因回移被覆盖或削弱：双移动通知（`MacsyZones/App.swift:193-205`）、按 windowID 节流（`MacsyZones/Macsy.swift:417-433`）、`.regular` 激活策略过滤（`MacsyZones/App.swift:300-304`、`:384-386`）、5 个监视器退出清理（`MacsyZones/App.swift:828-836`）、`DragSessionState` 与 >5pt 鼠标位移兜底（`MacsyZones/Macsy.swift:1180-1185`）。

## 构建与代码健康

- **FR-017**：`LastUpgradeCheck` 与 scheme 的 `LastUpgradeVersion` 更新为 2700（`MacsyZones.xcodeproj/project.pbxproj:102`）。
- **FR-018**：五处 `onChange` 单参数写法改为双参数（`MacsyZones/QuickSnapper.swift:189`、`:193`、`MacsyZones/SettingsView.swift:905`、`MacsyZones/ShortcutInputView.swift:70`、`:73`）；语义必须保持不变。
- **FR-019**：（可选）提供 `scripts/check_lazy_lifecycle.sh`：从真实源码抽取 `UserLayout`（`MacsyZones/UserData.swift:152`）与物化相关片段做编译级断言；若抽取方案不可行，plan 阶段必须写明替代的回归手段而不是静默跳过。

## 治理与范围边界

- **FR-020**：所有提交只推 `jiezhengj/MacsyZones` 的 `custom` 分支；`upstream` 远程只允许 `fetch`，禁止向上游推送或开 PR。
- **FR-021**：不得引入上游已回滚或不适用的改动：`e41e327` / `43d28e2`（macOS 27 右键接管，上游已整段回滚）、`f660129`（目标文件 `Switcher.swift` 已被 fork 的 `ee31dbc` 删除）、PR #105 的支持提醒（fork 已移除捐赠/ProLock）、`d93890a` 中除升级检查号以外的项（`MACOSX_DEPLOYMENT_TARGET=$(RECOMMENDED_MACOSX_DEPLOYMENT_TARGET)`、`STRING_CATALOG_GENERATE_SYMBOLS`、Automatic 签名）、`9b0f2dd` 中的纯风格去重。
- **FR-022**：不得改动 fork 已有的工程约束：`MACOSX_DEPLOYMENT_TARGET = 27.0`、Manual 签名与 Team 配置、`SWIFT_VERSION = 5.0`、`scripts/verify-signing.sh` 的校验口径。
- **FR-023**：本 feature 不预判、不登记下一发布的版本级别与性质；版本号与级别留到实际发布时按 `VERSIONING.md` 的判定规则确定。

# 核心实体模型

- **AppSettingsData（扩展）**：新增 `quickSnapperZoneLayoutsOnly: Bool?`，缺省 `true`；随现有设置快照一起参与脏检测、保存与重置。
- **布局循环集合（LayoutCycleSet）**：由「全部布局键」按 `quickSnapperZoneLayoutsOnly` 过滤（仅 `layoutType == .zone`）后排序得到的键序列，以及当前布局在该序列中的位置回退规则。
- **窗口观察登记（WindowObservationRegistry）**：现有 fork 结构（PID → AX 窗口元素，按 windowID 索引）；对账的输出是「需新增观察的窗口」与「需丢弃的失效窗口」。
- **对账视图（ReconcileView）**：一次对账的输入输出快照——PID、屏上 CG 窗口列表（windowID、title、bounds、layer）、已观察窗口 ID 集合、差集结果。
- **屏幕变更警告对话框（ScreenChangeWarningDialog）**：生命周期从「编辑器初始化时每分区常驻」改为「首次需要时创建、随编辑器关闭释放」。

# 可度量验收准则

- **SC-001**：存在网格布局时，快速吸附的 ← / → 循环 100% 落在区域布局上（默认设置），且停留的每个布局里 1–9 都有效。
- **SC-002**：关闭「仅区域布局」开关后，循环包含网格布局，切换 50 次无卡死、无崩溃、无「切不动」。
- **SC-003**：竖向 / 横向调整条各悬停 10 次，光标方向 20/20 正确。
- **SC-004**：冷启动后仅移动鼠标 60 秒，休眠布局物化次数为 0。
- **SC-005**：单分区编辑器未跨屏时警告面板实例数为 0；关闭编辑器后 dialog 与 panel 的 deinit 均被触发。
- **SC-006**：「窗口在屏上但 AX 初始不可见」场景下，窗口被观察的时间 ≤ 12 秒（多次运行的 P95）。
- **SC-007**：闲置 5 分钟 CPU 占用 ≤ 2%，激活路径主线程无 > 50ms 阻塞。
- **SC-008**：Debug、Release 构建通过，构建日志无新增弃用警告；`scripts/check-version.sh` 与 `scripts/verify-signing.sh` 通过。
- **SC-009**：v2.0.0 已有功能零回归：冷启动首次拖拽吸附、多屏 / Space 切换、多分区联合吸附、右键取消、修饰键 + 拖拽，全部通过。
- **SC-010**：仓库中不存在任何向上游 `rohanrhu/MacsyZones` 的提交、PR 或标签变更。

# 实施假设与环境基准

- **上游基线**：fork 基线为旧 tag `v3.0.4`，上游当前 `v3.1.1`（tip `2d5ce44`，2026-09-15）。本 feature 只回移 `v3.0.4..v3.1.1` 中仍然有效的改进，逐项按「上游是否仍然保留该行为」判定。
- **已完成项不重复实现**：PR #104（`43e01d5`，空提交，等价改动已由 fork 吸收）、PR #107（`ee2b624`，fork 的 `MacsyZones/QuickSnapper.swift` 与该版本逐字节一致）不再作为实现任务，仅在验收中确认无回归。
- **明确排除**：`e41e327` / `43d28e2`（上游最终回滚）、`f660129`（fork 无 `Switcher.swift`）、PR #105 支持提醒、`d93890a` 中除升级检查号外的工程设置、`9b0f2dd` 的纯风格去重。
- **fork 自研结构必须继承**：`SettingsView.swift`（替代上游 `Popover.swift`）的中文化设置界面、`SettingsState` 的暂存式设置与脏检测、`DragSessionState` 拖拽状态机、`Macsy.swift` 的窗口元素获取与节流实现。
- **构建环境**：macOS 27 + Xcode 27，Swift 5 语言模式；工程由 `scripts/build-debug.sh` / `scripts/build-release-dmg.sh` 驱动。
- **版本策略**：不预判版本级别（FR-023）。项目台账已改为只在 Release 创建后记录，`RELEASES.md` 与 `VERSIONING.md` 均不再要求提前登记下一版本；本 feature 因此不承担任何版本登记动作。
