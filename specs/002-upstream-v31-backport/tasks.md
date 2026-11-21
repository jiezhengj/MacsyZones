**分支**：`002-upstream-v31-backport` | **输入**：[spec.md](spec.md)、[plan.md](plan.md)、[research.md](research.md)、[data-model.md](data-model.md)、[contracts/app-settings-data.md](contracts/app-settings-data.md)、[quickstart.md](quickstart.md)

**格式**：`- [ ] TNNN [P?] [US?] 动作 + 文件路径`。[P] = 不同文件、无未完成依赖，可并行。

**关于测试**：工程没有 XCTest target 且本 feature 不新增（plan「复杂度跟踪」已论证）。spec 未要求 TDD，因此本文件不含「先写失败测试」任务；每层验证按 `research.md` R12 的顺序执行：构建 → 脚本断言 → `quickstart.md` 手工场景。唯一自动化断言来自 US5 移植的上游脚本。

# 阶段 1：准备

**目的**：确认起点干净、拿到回移对照物。

- [x] T001 确认起点：`git status --short` 为空、当前分支为 `custom`、`bash scripts/build-debug.sh` 在未改动代码上构建通过；把构建输出末 20 行与退出码记入笔记，作为后续对比基线
- [x] T002 [P] 导出回移对照物：`git fetch upstream main`（只 fetch，禁止推送），再把 `b83b923`、`08a028a`、`b77e366`、`ada5b51`、`7719891` 五个提交的 diff 逐个写入 `/tmp/upstream-ref/<hash>.diff`，供 T005–T027 逐处比对

# 阶段 2：基础（阻塞全部用户故事）

**目的**：建立三层验证的可执行前提，否则后面的「通过/未通过」没有口径。

- [x] T003 确认命令行工具链可用：`/usr/bin/swift --version` 能输出版本（T027/T028 的脚本断言依赖它）；失败则先 `xcode-select --install` 或记录该环境缺口
- [x] T004 [P] 采集警告基线：`bash scripts/build-debug.sh 2>&1 | grep -E "warning:" | sort | uniq -c > /tmp/warnings-baseline.txt`，重点记录 5 处 `onChange(of:perform:)` 弃用警告的现有条数，作为 T028 的对比依据

**检查点**：构建基线、警告基线、`swift` 可执行三件齐备。

# 阶段 3：用户故事 1 — 快速吸附只切区域布局（P1，MVP）

**目标**：← / → 循环默认只遍历区域布局，空集安全返回，网格布局中的当前态能正常离开；行为可由设置项 `quickSnapperZoneLayoutsOnly` 关闭。

**独立验收**：`quickstart.md` 场景 A 的 4 条（网格存在时跳过、仅一个区域布局时原地、关闭开关后全量循环、设置即时生效）。

- [x] T005 [US1] 在 `MacsyZones/QuickSnapper.swift:561-573`（上一个布局）的两个循环闭包里加入区域过滤、空集提前返回与索引回退，按 `data-model.md` 的 `LayoutCycleSet.候选集合`、`LayoutCycleSet.空集处理`、`LayoutCycleSet.当前位置` 实现；注意 `hideAllWindows()` 与索引计算的先后顺序，不得留下「已隐藏未显示」的中间态（`LayoutCycleSet.状态迁移`）
- [x] T006 [US1] 在 `MacsyZones/QuickSnapper.swift:581-593`（下一个布局）落同样的三件事，保持与 T005 对称；两处过滤条件必须一致，避免上下循环走到不同集合
- [x] T007 [P] [US1] 在 `MacsyZones/Settings.swift` 六处同步 `quickSnapperZoneLayoutsOnly`：`AppSettingsData`（`:15-22`，`Bool?`）、`private static let default…`（`:26-60`，`true`）、`@Published`（`:63-82`）、`load()`（`:88-118`，`?? defaultQuickSnapperZoneLayoutsOnly`）、`save()`（`:121-152`）、`resetToDefaults()`（`:154-188`）；字段定义以 `data-model.md` 的 `AppSettingsData.quickSnapperZoneLayoutsOnly` 为准，禁止强解包（章程原则五）
- [x] T008 [US1] 在 `MacsyZones/SettingsState.swift` 三处纳入同一字段：`areSettingsEqual`（`:136-157`）、`saveAll`（`:161-205`）、`refresh()` 的 `AppSettingsData(...)` 构造（`:208-236`）。判定口径见 `data-model.md` 的 `AppSettingsData.quickSnapperZoneLayoutsOnly`（参与脏检测）——漏掉任一处的后果是「开关能点但不保存」或「保存了但保存按钮不亮」，这是 fork 暂存式架构特有的坑
- [x] T009 [US1] 在 `MacsyZones/SettingsView.swift` 的 `QuickSnapperSettingsSection`（`:701` 起）插入中文开关：位置在 `ShortcutInputView`（`:723`）之后、`Divider`（`:731`）之前；绑定 `state.tempAppSettings.quickSnapperZoneLayoutsOnly ?? true`，变更后调用 `state.checkForChanges()`；说明文字讲清「关闭后网格布局也会进入循环」。不得改成上游 `Popover.swift` 的直连绑定写法（`research.md` R6）
- [ ] T010 [US1] 验证用户故事 1：`bash scripts/build-debug.sh` 通过；按 `quickstart.md` 场景 A 逐条走 4 个用例并记录实际结果（含 1–9 在每次停留布局里都生效）（自动化部分通过：构建 PASS；场景 A 四条待授权安装副本人工执行）

**检查点**：场景 A 全通过即可独立交付，MVP 到此成立。

# 阶段 4：用户故事 2 — 调整器光标方向（P1）

**目标**：竖向调整条显示左右箭头、横向显示上下箭头，桌面与布局编辑器一致。

**独立验收**：`quickstart.md` 场景 B 两条（方向正确、编辑器内无分裂）。

- [x] T011 [US2] 在 `MacsyZones/Layout.swift:1921-1922` 的 `NSHostingView(rootView: SnapResizerView(...))` 调用处补传 `mode:`，值取自宿主 `SnapResizer` 已保存的 `self.mode`（`:1902`、`:1910` 已存在，不要改构造签名或新建枚举——`research.md` R7）
- [x] T012 [US2] 在 `MacsyZones/Layout.swift:2078-2080` 的 `SnapResizerView` 增加 `var mode: SnapResizerMode = .vertical`，保持默认值与现有调用兼容
- [x] T013 [US2] 改写 `MacsyZones/Layout.swift:2102` 的悬停光标逻辑：`mode == .vertical` → `NSCursor.resizeLeftRight.push()`，否则 `NSCursor.resizeUpDown.push()`；移出/释放时的 pop 配对关系必须仍然平衡，不得泄漏 cursor stack
- [ ] T014 [US2] 验证用户故事 2：构建通过；场景 B 两条；额外确认编辑器内的调整条走同一路径（`:1671` 传 `.vertical`、`:1721` 传 `.horizontal`）时行为与桌面一致（自动化部分通过：构建 PASS；场景 B 两条待人工执行）

# 阶段 5：用户故事 3 — 惰性物化收口（P2）

**目标**：鼠标移动不再物化休眠布局；编辑器警告面板按需创建并可释放。

**独立验收**：`quickstart.md` 场景 C 三条（60 秒鼠标移动物化 0 次、未跨屏时面板实例 0、关闭编辑器后 dialog 与 panel 均 deinit）。

- [x] T015 [US3] 在 `MacsyZones/Layout.swift:1292` 把身份比较从 `userLayouts.currentLayout.layoutWindow === self` 改为 `userLayouts.currentLayout.materializedLayoutWindow === self`，确保比较本身不触发物化（`research.md` R8；该 guard 由 `:1119` 的全局 `mouseMoved` 监视器驱动）
- [x] T016 [US3] 把 `MacsyZones/Layout.swift:706-715` 的 `EditorSectionWindowDelegate.init()` 改为只赋值 `sectionWindow`、`originalScreen`；`ScreenChangeWarningDialog` 移入 `showScreenChangeWarning()` 内首次调用时创建，生命周期按 `data-model.md` 的 `ScreenChangeWarningDialog.warningDialog`（唯一创建点）与 `ScreenChangeWarningDialog.hasShownWarning`（dismiss 后复位）实现
- [x] T017 [US3] 把 `MacsyZones/Layout.swift:653-660` 的 `onDismiss: { self.dismiss() }` 改为 `onDismiss: { [weak self] in self?.dismiss() }`，断开 dialog → panel → hosting view → 闭包 → dialog 的环（`data-model.md` 的 `ScreenChangeWarningDialog.onDismiss` 不变量）
- [ ] T018 [US3] 验证用户故事 3：构建通过；场景 C 三条；用 Instruments 或临时 `debugLog("deinit")` 确认 dialog 与 panel 的 deinit 真的触发，然后撤掉临时日志（自动化部分通过：构建 PASS；deinit 证据待 Instruments 人工确认）

# 阶段 6：用户故事 4 — 窗口观察对账（P2）

**目标**：屏上有、AX 列表里缺的窗口在 12 秒内被补注册；激活即对账；三态判定与退避重试；退出时取消定时任务；fork 既有增强零回归。

**独立验收**：`quickstart.md` 场景 D 四条（延迟建窗 12 秒内被观察、激活即对账、闲置 CPU ≤ 2%、权限缺失不刷屏）。

- [x] T019 [US4] 在 `MacsyZones/App.swift` 把 `:309-319` 的布尔 `isStandardWindow(_:)` 换成私有枚举 `StandardWindowCheck`（`.standard` / `.notStandard` / `.indeterminate`）与 `checkStandardWindow(_:)`：`role`/`subrole` 任一 `AXError != .success` → `.indeterminate`，读到但不匹配 → `.notStandard`；状态迁移严格按 `data-model.md` 的 `StandardWindowCheck`（indeterminate 才能重试，notStandard 永不重试）
- [x] T020 [US4] 在 `MacsyZones/App.swift` 的 `observeWindow`（`:169`）入口接入三态：`.indeterminate` → `scheduleObserveRetry(pid:element:attempt:)`，延迟 `150ms × (attempt + 1)`、`attempt < 3`，超限只记一条日志；`.notStandard` → 返回 false；`.standard` 继续走现有注册流程（`research.md` R4）
- [x] T021 [US4] 在 `MacsyZones/App.swift` 的 `WindowObserverManager` 新增 `reconcile(pid:axWindows:)`：差集来自 `entries[pid]?.windows.keys` 与 `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` 过滤 `ownerPID == pid && layer == 0` 的结果，只注册 `!observedIDs.contains(id)` 的窗口；元素获取先 `MacsyZones/Macsy.swift:1036`，失败再按 `kCGWindowName` 走 `:1068`，标题为空则跳过；补注册复用现有 `observeWindow`。字段口径见 `data-model.md` 的 `ReconcileView.missingIDs` 与 `ReconcileView.hunted`；CG 读取在后台、注册表写入 `Task { @MainActor }`（`research.md` R2）
- [x] T022 [US4] 在 `MacsyZones/App.swift` 新增 `scheduleWindowScans(forPid:delays:)`：全局 `[2, 6, 12]`、新启动 App `[1, 3, 7]`；每个延迟的 `DispatchWorkItem` 存入 `pendingScanWorkItems`，在 `applicationWillTerminate` 的现有清理处（`:828-836`）统一 `cancel()` 并清空（`research.md` R3）
- [x] T023 [US4] 接入触发路径：`scanAllRunningApplications()` / `scheduleWindowScans(delays: [2, 6, 12])` 接在启动流程、`didActivateApplicationNotification` 里接 `reconcile`、新 App 启动接 `[1, 3, 7]` 重扫；确认与 `forgetWindow`（`:242-255`）共用同一份注册表，不出现第二套状态（FR-012）
- [ ] T024 [US4] 验证用户故事 4 与零回归：构建通过；场景 D 四条；另做 FR-016 保留清单核对——双移动通知（`MacsyZones/App.swift:193-205`）、CFEqual 替换（`:180-188`）、按 windowID 节流（`MacsyZones/Macsy.swift:417-433`）、`.regular` 过滤（`App.swift:300-304`、`:384-386`）、5 个 monitor 退出清理（`App.swift:828-836`）、`DragSessionState` + >5pt 鼠标兜底（`MacsyZones/Macsy.swift:1180-1185`）在 diff 中均未被删改（自动化部分通过：构建 PASS、FR-016 清单未删改；场景 D 四条待授权安装副本人工执行）

# 阶段 7：用户故事 5 — 构建清单与代码健康（P3）

**目标**：Xcode 27 不再提示推荐设置，`onChange` 弃用警告清零，惰性物化有命令行回归闸门。

**独立验收**：`quickstart.md` 场景 E 三条。

- [x] T025 [P] [US5] 更新 `MacsyZones.xcodeproj/project.pbxproj:102` 的 `LastUpgradeCheck` 与 `MacsyZones.xcodeproj/xcshareddata/xcschemes/MacsyZones.xcscheme:3` 的 `LastUpgradeVersion` 为 `2700`；只改这两个数字，不引入 `d93890a` 的其余三项（`research.md` R10）
- [x] T026 [P] [US5] 五处 `onChange` 改双参数（旧值统一 `_`）：`MacsyZones/QuickSnapper.swift:189`、`:193`，`MacsyZones/SettingsView.swift:905`，`MacsyZones/ShortcutInputView.swift:70`、`:73`；映射表见 `research.md` R11，语义必须与改动前一致
- [x] T027 [P] [US5] 原样移植上游回归脚本：`scripts/check_lazy_lifecycle.sh`（65 行）与 `scripts/tests/{README.md,lazy-stubs.swift,lazy-assertions.swift}`；脚本以 `awk` 抽取 `MacsyZones/UserData.swift:152`、`:307` 与 `MacsyZones/Macsy.swift:348`、`:354`、`:361`、`:372` 片段，锚点已确认在 fork 命中（`research.md` R9），保持文件以 LF 保存、脚本 `chmod +x`
- [x] T028 [US5] 验证用户故事 5：`bash scripts/check_lazy_lifecycle.sh` 输出 `PASS: 139 assertions …` 且退出码 0；`bash scripts/build-debug.sh` 通过且 `warning:` 集合同 `/tmp/warnings-baseline.txt` 相比只减不增（5 条 `onChange` 弃用警告消失）；Xcode 打开工程不再出现升级推荐

# 阶段 8：收尾与交付

- [x] T029 跑完整构建矩阵：`bash scripts/build-debug.sh` + `bash scripts/build-release-dmg.sh`，两条均记录退出码与产物路径
- [ ] T030 按 `quickstart.md` 全量走查：场景 A–G 逐条勾选，把实测结果（含 CPU 采样与 deinit 证据）写回 `quickstart.md` 的对应小节之外的新增「实测记录」段落，不改原验收标准（已完成的自动化项与未执行项见「实现记录」）
- [x] T031 复核章程与范围边界：`git diff` 中 `MACOSX_DEPLOYMENT_TARGET`、`SWIFT_VERSION`、签名/Team、`scripts/verify-signing.sh` 均无变化（FR-022）；未引入 `e41e327`/`43d28e2`、`f660129`、PR #105、`STRING_CATALOG_GENERATE_SYMBOLS`、Automatic 签名（FR-021）
- [x] T032 提交实现：按切片拆成 5 个提交（US1、US2、US3、US4、US5），每个提交信息标注上游溯源哈希；只提交到本地 `custom`，**不推送**，推送与发布由用户决定
- [x] T033 更新本文件：勾选已完成任务，在「实现记录」小节写下每个切片的提交哈希与实际偏差（若有），供后续 `speckit-converge` 与发布台账使用

# 依赖与执行顺序

## 阶段依赖

- 阶段 1 → 阶段 2 → 阶段 3 起的所有用户故事
- 用户故事之间**没有代码依赖**：US1（QuickSnapper/Settings*/SettingsView）、US2（Layout 光标段）、US3（Layout 物化段）、US4（App.swift/Macsy.swift）、US5（工程文件/onChange/scripts）互不共享文件，只是 US2 与 US3 都改 `MacsyZones/Layout.swift`（不同区域，需串行或同一人顺序改）
- 阶段 8 依赖 US1–US5 全部完成

## 用户故事内部顺序

- US1：T005/T006（循环）与 T007→T008→T009（设置链，必须按序，否则脏检测不亮）可并行；T010 最后
- US2：T011→T012→T013 顺序执行（视图属性先存在才能传值），T014 最后
- US3：T015、T016、T017 互不依赖但同文件，顺序执行；T018 最后
- US4：T019→T020（三态先落地）、T021、T022、T023 顺序执行（对账依赖三态判定，调度依赖对账入口）；T024 最后
- US5：T025/T026/T027 三路并行；T028 最后

## 并行示例

```bash
# 阶段 3 可与阶段 6 同时开工（不同文件、不同 owner）
Task: "T005/T006 改 QuickSnapper.swift 两个循环闭包 + T007-T009 设置链"
Task: "T019/T020/T021 改 App.swift 的 WindowObserverManager"

# 阶段 7 三路并行
Task: "T025 改 pbxproj 与 scheme 的升级检查号"
Task: "T026 改 5 处 onChange"
Task: "T027 移植 check_lazy_lifecycle.sh 与 scripts/tests/"
```

# 实施策略

## MVP 优先

1. 阶段 1 + 阶段 2
2. 阶段 3（US1）→ **停下按场景 A 验收**，此时行为已可独立交付
3. 若要最小可用增量，US1 单独提交即可交付给用户试用

## 增量交付

1. US1（P1）→ 验收 → 提交
2. US2（P1）→ 验收 → 提交
3. US3（P2）→ 验收 → 提交
4. US4（P2，风险最高）→ 验收 → 提交；若对账行为异常，先回退 US4 不影响前三项
5. US5（P3）→ 验收 → 提交
6. 阶段 8 全量验收后再决定是否推送与发布

## 风险与回退

- US4 是唯一可能影响拖拽主链路的切片：改动集中在 `WindowObserverManager` 与启动/激活触发点，回退方式为 `git revert` 单个提交，不影响 US1–US3
- 脚本断言（T027/T028）依赖 `/usr/bin/swift`，缺失时记为环境缺口并在交付说明中注明，不阻塞其余切片

# 实现记录

实现日期：2026-11-21。按切片拆成 5 个提交（均在本地 `custom`，未推送）。

| 切片 | 提交 | 上游溯源 |
|---|---|---|
| US1 布局循环只遍历区域布局 | `ca0f9ce` | b83b923、08a028a |
| US2 调整条光标方向 | `ec8c656` | b77e366 |
| US3 惰性物化与警告面板生命周期 | `afe1165` | ada5b51（PR #106） |
| US4 三态判定、退避重试与 CG↔AX 对账 | `0666090` | 7719891 |
| US5 升级检查号、onChange 双参与回归脚本 | `d1d21a7` | d93890a、9b0f2dd、ada5b51（测试资产） |

## 已完成的验证

- Debug 构建：`bash scripts/build-debug.sh` → `** BUILD SUCCEEDED **`，签名校验 `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）`。
- 警告基线对比：改动前 5 条 `'onChange(of:perform:)' was deprecated`，改动后 `warning:` 计数 0（只减不增）。
- Release 配置构建（T029 替代项，见偏差 3）：`xcodebuild -configuration Release … CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=C7C84AAA… DEVELOPMENT_TEAM=74FR87HYTH clean build` → BUILD SUCCEEDED；`scripts/verify-signing.sh` → `PASS: 正式签名身份、证书 SHA-1、Bundle ID、Team ID、designated requirement 和完整性均一致`。
- 惰性物化脚本：`bash scripts/check_lazy_lifecycle.sh` → `PASS: 139 assertions … source; no AppKit or application launch`。
- 启动冒烟：用 `/tmp/mz-debug` 的 Debug 产物运行 18 秒后 kill——进程无崩溃，日志有 13 条 `AX app observer ready`、`All apps are being observed for window movement.`、`Preferences loaded successfully.`、正常布局切换与更新检查（2.0.0 已是版本），无 `Failed to register AX notifications` 刷屏、无 `Giving up on pid` 刷屏、无残留进程。
- 边界复核（T031）：`git diff` 中 `MACOSX_DEPLOYMENT_TARGET`、`SWIFT_VERSION`、`CODE_SIGN*`、`DEVELOPMENT_TEAM`、`PRODUCT_BUNDLE_IDENTIFIER`、`STRING_CATALOG_GENERATE_SYMBOLS` 均无改动；未引入 `e41e327`/`43d28e2`、`f660129`、PR #105、Automatic 签名。

## 与计划的偏差

1. **`SettingsState.swift` 改 4 处而非 3 处**：`init()` 里的 `AppSettingsData(...)` 也要补 `quickSnapperZoneLayoutsOnly`，否则暂存副本缺字段、开关保存后被 `refresh()` 覆盖回默认值。plan 与 T008 的「三处」应为四处，已按代码实际情况执行。
2. **US4 的落点与计划不同**：`scanWindows`/`scanAllRunningApplications`/`scheduleWindowScans`/`cancelPendingScans` 放在 `WindowObserverManager`（`@MainActor`）内，`AppDelegate` 只负责四处触发（启动 `[2,6,12]`、新启动 App `[1,3,7]`、激活 `[0]`、退出 `cancel`）；避免了 `AppDelegate` 承担状态。首版实现中 `DispatchWorkItem` 闭包直接引用自身导致 `MacsyZones/App.swift:356` 编译错误 `use of local variable 'workItem' before its declaration`，改为 `var scheduledItem` 占位后消失。
3. **T029 的 `scripts/build-release-dmg.sh` 未运行**：脚本要求传入版本等于 `MARKETING_VERSION`，且 `check-version.sh` 要求该版本高于已发布 `v2.0.0`（当前 `MARKETING_VERSION=2.0.0`）。这与「不预设下一个版本」的策略直接冲突——跑它就必须先决定版本号。改用 Release 配置构建 + `verify-signing.sh` 作为等价门禁（均通过），DMG 打包留给真正发版时做。

## 未完成的人工验证

临时构建里 AX 注册全部返回 `-25211`（`kAXErrorAPIDisabled`，该构建未获辅助功能 TCC 授权），因此以下场景无法由代理代跑，需要在**已授权的安装副本**上人工确认：

- T010 场景 A（快速吸附只切区域布局 4 条）。
- T014 场景 B（调整条光标方向）。
- T018 场景 C（60 秒鼠标移动不物化；未跨屏时无面板；关闭编辑器后 dialog/panel 的 deinit 证据）。
- T024 场景 D（延迟建窗 12 秒内被观察、激活即对账、闲置 CPU ≤ 2%、撤销权限后不刷屏）。
- T030 场景 A–G 全量走查与「实测记录」回填。

自动化可覆盖的部分（构建、签名、脚本断言、启动冒烟、边界差异核对）均已通过，记录见上。
