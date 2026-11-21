**分支**：`003-macos27-permissions` | **输入**：[spec.md](spec.md)、[plan.md](plan.md)、[research.md](research.md)、[data-model.md](data-model.md)、[contracts/guidance-targets.md](contracts/guidance-targets.md)、[contracts/permission-report.schema.json](contracts/permission-report.schema.json)、[quickstart.md](quickstart.md)

**格式**：`- [ ] TNNN [P?] [US?] 动作 + 文件路径`。[P] = 不同文件、无未完成依赖，可并行；未标 [P] 的任务必须按编号顺序做。

**关于测试**：工程没有 XCTest target 且本 feature 不新增（plan「复杂度跟踪」已论证）。本文件不含「先写失败测试」任务；验证按 `research.md` R10 的三层：① `scripts/build-debug.sh` 编译与签名；② `scripts/check_permission_model.sh`（`awk` 抽取真实源码函数 + 断言 + 不变量 grep，见 R15）；③ `scripts/permission-smoke.sh` 运行期日志断言。需要真实 TCC 授权与 GUI 的部分走 `quickstart.md` 手动矩阵。

**写作用域纪律**：`MacsyZones/App.swift` 被 US1（T017–T018）、US2（T021–T025）、US4（T034–T036）共用，这三个故事**必须串行**；`MacsyZones/SettingsView.swift` 被 T024（横幅）与 T029（诊断 section）先后修改，顺序固定。并行只在标注 [P] 且文件不重叠时进行。

# 阶段 1：准备

**目的**：建立可对比的基线，并产出能反复启动的验证副本（`scripts/build-debug.sh` 会删掉派生数据，不能用于需要多次启动的验证）。

- [x] T001 确认起点：`git status --short` 为空、当前分支为 `custom`；跑 `bash scripts/build-debug.sh`，记录 `warning:` 计数与末 20 行到 `/tmp/m003-warnings-baseline.txt`
- [x] T002 新建 `scripts/build-permission-artifact.sh`（`research.md` R14）：`xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones -configuration Debug -derivedDataPath /tmp/m003-debug CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=C7C84AAA3B67FACEA73042570A0BA2FC3D19E613 DEVELOPMENT_TEAM=74FR87HYTH build` → `rm -rf ~/Applications/MacsyZones-dbg.app` → `cp -R /tmp/m003-debug/Build/Products/Debug/MacsyZones.app ~/Applications/MacsyZones-dbg.app` → `bash scripts/verify-signing.sh ~/Applications/MacsyZones-dbg.app` → 打印 `PASS: 验证副本已生成（~/Applications/MacsyZones-dbg.app）`；执行一次确认产物可启动
- [x] T003 [P] 抓现有权限行为基线：启动 `~/Applications/MacsyZones-dbg.app`，`log show --last 5m --predicate 'process == "tccd" AND eventMessage CONTAINS "MeowingCat.MacsyZones"'` 与 `log show --last 5m --predicate 'subsystem == "MeowingCat.MacsyZones"'` 存 `/tmp/m003-permission-baseline.log`，并记下当前是否弹模态框、是否要求重启（后续回归对比用）
- [x] T004 [P] 记录边界基线到 `/tmp/m003-boundary-baseline.txt`：`grep -rn "#available" MacsyZones --include=*.swift`（当前 9 处：SettingsView.swift:915/941/950、Onboarding.swift:263、Layout.swift:56/916/937/968/985）、`grep -rn "hasAccessibilityPermission" MacsyZones`（当前 4 处：`App.swift:38/627/742/746`）、`grep -rn "AXIsProcessTrustedWithOptions" MacsyZones`（当前 1 处：`App.swift:742`）、`grep -rn "checkAccessibilityPermission\|requestAccessibilityPermissions" MacsyZones`（定义 `App.swift:740`/`:745`，调用 `:554`/`:555`）、`ls scripts/`（当前 5 个脚本 + `scripts/tests/` 仅 002 的 lazy 文件）

# 阶段 2：基础（阻塞所有用户故事）

**目的**：权限中心、引导表、日志与验证脚本。完成后各用户故事才有可依赖的模型与断言。

- [x] T005 新建 `MacsyZones/PermissionCenter.swift`，定义 `PermissionCapability`、`PermissionStatus`（含 `notRequired`）、`PermissionProbe`、`CapabilityState`、`PermissionSnapshot`，并**显式定义** `SystemInfo`（`productVersion`/`build`/`arch`）与 `AppInfo`（`marketingVersion`/`build`/`bundleID`/`teamID`/`path`/`isTranslocated`/`isLoginItem`）；字段与不变式严格按 `data-model.md` 的 `PermissionCapability`、`PermissionStatus`、`PermissionProbe`、`CapabilityState`、`PermissionSnapshot`、`SystemInfo`、`AppInfo` 小节，字段名与 `contracts/permission-report.schema.json` 的 `system.*`/`app.*` 一致；`PermissionCenter` 暴露 `@Published private(set) var hasCompletedFirstCheck: Bool` 与 `var onStatusChange: ((PermissionCapability, PermissionStatus, PermissionStatus) -> Void)?`
- [x] T006 在 `MacsyZones/PermissionCenter.swift` 实现窗口控制探针：`frontmost`（`NSWorkspace.shared.frontmostApplication`）与 `finder`（`com.apple.finder`）各读一次 `AXUIElementCopyAttributeValue(kAXWindowsAttribute)`，另记 `api`（`AXIsProcessTrusted()`）仅作诊断；单探针 1 秒超时，在 `DispatchQueue(label: "MeowingCat.MacsyZones.permissions.probe", qos: .utility)` 执行；汇总函数**逐格实现** `data-model.md`「窗口控制汇总规则」的 7 行（含 `partialTargets` 的两种方向与两种 `unknown` 组合），即以「任一 success → granted；无 success 且全部已完成探针均 apiDisabled → denied；其余 → unknown」
- [x] T007 在 `MacsyZones/PermissionCenter.swift` 实现输入监听探针（`CGPreflightListenEventAccess()`，id `preflight`）、`eventPosting` 固定 `notRequired`，以及 `PermissionSnapshot.overall`（取窗口控制状态；`inputMonitoring` 单独展示，`notRequired` 不参与汇总）
- [x] T008 在 `MacsyZones/PermissionCenter.swift` 实现复核调度：`start()`/`stop()`/`recheck(trigger:)`，同 trigger 1 秒去重；`trigger` 取值 `launch`/`activate`/`wake`/`ax-failure`/`manual`/`poll`；`granted` 后 30s 轮询、非 `granted` 时 5s × 最多 24 次；首轮完成后置 `hasCompletedFirstCheck = true`；所有 `Timer`/`DispatchWorkItem` 记录在册并可取消
- [x] T009 在 `MacsyZones/PermissionCenter.swift` 实现宽限状态机（`data-model.md`「状态机」与四条不变式）：**仅当**「上一次 `granted`、本次探针 `denied`、距进程启动 < 60 秒」时进入可疑态（对外仍报 `granted`、只记日志）；60 秒内恢复则视为抖动，否则切 `denied` 并提示；**距启动 ≥ 60 秒的 `granted → denied` 立即生效**
- [x] T010 [P] 在 `MacsyZones/Utils.swift` 增加权限日志设施：`os.Logger(subsystem: "MeowingCat.MacsyZones", category: "permissions")`，固定字段 `capability`/`status`/`probe`/`target`/`error`/`latencyMs`/`trigger`，路径类字段用 `.private`（需 `import os`）；`debugLog` 保持原样
- [x] T011 [P] 新建 `MacsyZones/PermissionGuidance.swift`：`GuidanceTarget`（`pane`/`url`/`panelTitle`/`steps`）与版本判定 `ProcessInfo.processInfo.operatingSystemVersion.minor >= 3`（**禁止 `#available`**）；pane 与文案按 `contracts/guidance-targets.md` 的「深链契约」「文案契约」；`NSWorkspace.shared.open` 返回 false 时按「行为契约」兜底到 `privacyRoot`，再失败只给文字路径；提供 `func open() -> Bool` 供 UI 调用
- [x] T012 [P] 新建 `scripts/tests/permission-stubs.swift`：提供 `PermissionStatus`/`PermissionProbe`/`CapabilityState` 的纯值桩与断言宏（不 `import AppKit`），供 T013 拼装抽取出来的真实函数
- [x] T013 [P] 新建 `scripts/tests/permission-assertions.swift`：逐格断言 `data-model.md` 汇总表 7 行、`-25211`→denied、`-25204`/超时/目标缺失→unknown、宽限 60 秒三条边界（59s/60s/61s）、`minor<3`→`legacyAccessibility` 且兜底 `privacyRoot`、`minor>=3`→`systemProtectionOverride` 且兜底 `accessibilityApps`
- [x] T014 新建 `scripts/check_permission_model.sh`：① 用 `awk` 从 `MacsyZones/PermissionCenter.swift` 与 `MacsyZones/PermissionGuidance.swift` 抽取真实函数（汇总函数、宽限计算、pane 选择），与 `scripts/tests/permission-stubs.swift` 拼成临时文件后用 `swiftc -parse`/`swift` 执行 `scripts/tests/permission-assertions.swift`（抽取失败则 `MODE=source-grep` 退化为 grep 分支断言并打印警告，禁止静默跳过）；② 不变量 grep：`MacsyZones/PermissionCenter.swift`、`MacsyZones/PermissionGuidance.swift`、`MacsyZones/PermissionDiagnosticsView.swift` 不出现 `#available`、`AXUIElementSetAttributeValue`、`exit(`；`MacsyZones/Info.swift` 不再出现 `exit(0)`；③ 全仓 `#available` 计数不得高于 T004 记录的基线 9 处（防改造 `App/Info/SettingsView` 时新增），输出 `PASS: 权限模型断言通过（<N> assertions）`

# 阶段 3：US1 首次引导指向真正需要的开关（P1，MVP）

**独立验收**：`quickstart.md` 场景 A —— 撤销授权后启动，引导出现、文案含正确面板名、按钮跳到对应面板、app 不退出、主界面可用。

- [x] T015 [US1] 改造 `MacsyZones/Info.swift` 的 `AccessibilityPermissionView`：按 `GuidanceTarget` 输出步骤（27.3+ 先 System & App Protection Override、再看无障碍），按钮改为「打开系统设置」「重新检测」，删除旧截图引用（`Accessibility-Permission-Tutorial-1/2.imageset` 不再被引用；资源目录保留不删，删除属清理项不作要求），删除「重启后继续」主路径文案（FR-006/FR-007/FR-008/FR-009）
- [x] T016 [US1] 在 `MacsyZones/Info.swift` 把 `AccessibilityDialog` 改为非模态：去掉 `.screenSaver` 级别（`:197`、`:228`）、去掉 `onCancel` 闭包里的 `exit(0)`（`:221-224`，`exit(0)` 在 `:223`）、移除 `show()` 里的 `NSApplication.shared.activate(ignoringOtherApps: true)`（`:247-251`），保留 `orderFrontRegardless()` 但不抢焦点（FR-004/FR-010）
- [x] T017 [US1] 改造 `MacsyZones/App.swift`：删除 `hasAccessibilityPermission`（`:38`）、`checkAccessibilityPermission()`（`:740`）、`requestAccessibilityPermissions()`（`:745`）及其调用（`:554`/`:555`），改为 `PermissionCenter.shared.start()`；`showAccessibilityPermissionPopover()`（`:753`）改为非模态引导入口；用 `grep -rn "hasAccessibilityPermission" MacsyZones` 确认无残留
- [x] T018 [US1] 在 `MacsyZones/App.swift` 接线引导展示：**必须** `PermissionCenter.shared.hasCompletedFirstCheck == true` 且 `snapshot.overall != .granted` 才展示；首轮探测完成前不显示任何未授权提示（避免已授权用户每次启动闪引导）
- [x] T019 [US1] 构建并执行 `quickstart.md` 场景 A：`bash scripts/build-permission-artifact.sh` → 撤销授权 → 启动 `~/Applications/MacsyZones-dbg.app`，记录文案、按钮落点、日志、是否崩溃
- [x] T020 [US1] 把实测结果回填 `specs/003-macos27-permissions/quickstart.md`（场景 A 实测列）与 `research.md` R12 第 2 条：本 app 实际出现在哪个面板、`Privacy_Accessibility`/`Privacy_AccessibilityApps` 深链是否落点正确；若实际不符，同步修正 `contracts/guidance-targets.md`

# 阶段 4：US2 权限状态持续复核（P1）

**独立验收**：`quickstart.md` 场景 B（授权后 10 秒内、主动触发 2 秒内变 `granted`）与场景 C（运行期撤销 10 秒内降级，无 60 秒静默）。

- [x] T021 [US2] 在 `MacsyZones/App.swift` 注册复核触发，注册中心必须正确：`NSWorkspace.didActivateApplicationNotification`、`NSWorkspace.didWakeNotification` 用 `NSWorkspace.shared.notificationCenter`；`NSWindow.didBecomeKeyNotification` 用 `NotificationCenter.default`；菜单栏点击在 `toggleSettings` 回调内触发；`NSApplication.didBecomeActiveNotification` 只作可选补充（`.prohibited` 下可能不触发，`MacsyZones/App.swift:550`），不依赖；所有触发回调 `Task { @MainActor in PermissionCenter.shared.recheck(trigger:) }`（FR-003）
- [x] T022 [US2] 让 AX 失败可上报：`MacsyZones/App.swift:485` 的 `checkStandardWindow(_:)` 在 `roleStatus`/`subroleStatus` 失败时携带原始 `AXError`（或新增 `checkStandardWindowWithError` 供 `observeWindow` 使用），失败分支调用 `PermissionCenter.shared.reportAXFailure(error)`；`MacsyZones/Macsy.swift` 的 6 处 `AXUIElementSetAttributeValue`（`:857`/`:875`/`:885`/`:907`/`:912`/`:1022`）失败时同样上报（FR-003）
- [x] T023 [US2] 在 `MacsyZones/App.swift` 的 `createTrayIcon()`（`:702`）按状态刷新菜单栏标记：不得破坏 `image.isTemplate` 的深浅色着色（用 `attributedTitle` 或叠加 template 图），并因 `createTrayIcon()` 早于首轮探测完成，在 `hasCompletedFirstCheck` 变 true 后异步刷新一次（FR-004）
- [x] T024 [US2] 在 `MacsyZones/SettingsView.swift` **新建**权限横幅视图（`private struct PermissionStatusBanner`），插入到 `body` 的 `ScrollView` 内第一个 section（`LayoutSettingsSection`，`:77`）之前；按 `snapshot` 显示「未授权/未知/缺少输入监听」与「打开系统设置」「重新检测」按钮（FR-004/FR-010）
- [x] T025 [US2] 在 `MacsyZones/App.swift:627` 把 onboarding 条件由 `hasAccessibilityPermission` 改为 `PermissionCenter.shared.snapshot.overall == .granted`（依赖 T017 已删除旧符号），并保证未授权时引导优先于 onboarding（FR-009）
- [x] T026 [US2] 构建并执行 `quickstart.md` 场景 B、C：记录「授权 → granted」实际耗时（要求 ≤ 10 秒，主动触发 ≤ 2 秒）与「运行期撤销 → 降级」实际耗时（要求 ≤ 10 秒，不得出现 60 秒静默）
- [x] T027 [US2] 把 T026 的实测数值与新发现写入 `specs/003-macos27-permissions/quickstart.md` 的实测记录段落

# 阶段 5：US3 诊断面板与 Release 可观测性（P2）

**独立验收**：设置里能看到三能力状态与探针明细；「复制报告」产出能通过 `quickstart.md` 五 的逐字段校验；`log show` 能按子系统过滤到权限日志。

- [x] T028 [US3] 新建 `MacsyZones/PermissionDiagnosticsView.swift`：展示各能力状态、最近检测时间、探针明细（`id`/`target`/`axError`/`latencyMs`）、`AppInfo`（含 `path`/`isTranslocated`/`isLoginItem`）与 `SystemInfo`，底部「重新检测」「复制报告」（FR-016）
- [x] T029 [US3] 在 `MacsyZones/SettingsView.swift` 的 `AdvancedSettingsSection`（`:798`）之后插入 `PermissionDiagnosticsSection`（依赖 T024 已改过该文件，顺序固定）
- [x] T030 [US3] 在 `MacsyZones/PermissionCenter.swift` 实现 `PermissionDiagnosticReport`（`Codable`，`schemaVersion = 1`）并复制到 `NSPasteboard`：字段严格按 `data-model.md`「DiagnosticReport」与 `contracts/permission-report.schema.json` 的 `required` 列表（`schemaVersion`/`generatedAt`/`app`/`system`/`capabilities`/`notes`），`capabilities[].probes[]` 逐条带 `id`/`target`/`status`/`latencyMs`（`axError` 可空）；不采集窗口标题与个人数据（FR-017/FR-018）
- [x] T031 [US3] 新建 `scripts/permission-smoke.sh`：确保 `~/Applications/MacsyZones-dbg.app` 存在（不存在则先调 `scripts/build-permission-artifact.sh`）→ 启动 20 秒 → `log show --last 1m --predicate 'subsystem == "MeowingCat.MacsyZones" AND category == "permissions"'` → 断言至少一条含 `capability=windowControl`、`status=`、`trigger=launch`、`latencyMs=` 且 `latencyMs < 1000` 的记录，且**首条 `trigger=launch` 记录与进程启动时间戳相差 ≤ 10 秒**（契约 clause），进程存活、无 `fatal error` → 结束进程；输出 `PASS: 权限日志与进程状态正常（<N> 条权限记录）`（契约见 `contracts/guidance-targets.md`「演示/冒烟契约」）
- [x] T032 [US3] 从诊断面板复制报告，按 `quickstart.md`「五、诊断报告」的校验脚本执行，要求输出 `PASS: 报告结构符合契约`；把失败字段修正到通过为止
- [x] T033 [US3] 执行 `quickstart.md` 场景 H（`/tmp` 运行与 translocation）：确认 `app.path`/`isTranslocated` 如实呈现、状态允许 `denied` 但面板解释清楚、不崩溃；结论回填 `quickstart.md`

# 阶段 6：US4 全局输入监听单独检测与降级（P2）

**独立验收**：`quickstart.md` 场景 F 的两个方向——F1 只关输入监控（拖动必须照常、仅键盘功能暂停、快捷键保留）、F2 只关窗口控制（拖动/悬停/右键暂停、快捷键保留、不崩溃），外加两者「重新打开后不重启即恢复」的路径。

- [x] T034 [US4] 在 `MacsyZones/App.swift` 抽出「安装/卸载全局监视器」函数，并**按事件类型分别绑定能力**：鼠标类 `leftMouseDown`（`:607`）、`leftMouseDragged`（`:611`）、`leftMouseUp`（`:615`）、`rightMouseDown`（`:984`）与 `MacsyZones/Layout.swift:1123` 的 `mouseMoved` 绑 `windowControl`；键盘类 `keyDown`+`flagsChanged`（`:866`）绑 `inputMonitoring`；对应能力 `!= .denied` 时安装（`unknown` 也安装，FR-013 只禁止假定可用、不要求未判定前自废功能）；不得把鼠标监视器绑到 `inputMonitoring`
- [x] T035 [US4] 通过 `PermissionCenter.onStatusChange` 实现按类型的状态迁移：`windowControl` → `granted` 补装鼠标类、→ `denied` 卸载鼠标类；`inputMonitoring` 同理只作用于键盘类，两类互不牵连；`PermissionCenter.stop()` 与 `applicationWillTerminate`（`MacsyZones/App.swift`）统一卸载并防重复安装（`research.md` R13、`data-model.md` 状态机）
- [x] T036 [US4] 实现降级矩阵（FR-012/FR-013/FR-014）：缺窗口控制 → 鼠标拖动/悬停高亮/右键菜单暂停、布局保存提示只读、横幅注明原因；缺输入监听 → 仅修饰键/吸附键驱动的布局切换暂停、鼠标拖动照常；Carbon 快捷键两者都保留；per-target 部分可控 → 诊断面板 `notes` 标注「部分目标受控」，不刷错误日志、不整体报未授权
- [x] T037 [US4] 构建并执行 `quickstart.md` 场景 F1/F2 与场景 B 的恢复路径（重新打开对应权限后不重启即恢复），把降级行为与恢复时间回填 `quickstart.md` 实测记录

# 阶段 7：US5 跨 27.x 子版本与升级路径（P3）

**独立验收**：桩断言覆盖两套 pane 映射与两级兜底；新增文件无 `#available`；升级与多次登录有书面结论。

- [ ] T038 [US5] 补强 T013 的两套形态断言并跑通：`minor < 3` → `legacyAccessibility`、打开失败 → `privacyRoot`；`minor >= 3` → `systemProtectionOverride`、打开失败 → `accessibilityApps`、再失败 → 仅文字路径；断言必须取自 `MacsyZones/PermissionGuidance.swift` 的真实函数（R15），并在 `scripts/check_permission_model.sh` 输出断言条数（FR-019）
- [ ] T039 [US5] 执行并记录升级路径（FR-020，`quickstart.md` 场景 D）：本机已升级到 27.3，无法回退复现「27.2 授权 → 升级」；若无法执行，在 `quickstart.md` 场景 D 与 `research.md` R12 明确标注「未实机验证」及原因，禁止写成已验证
- [ ] T040 [US5] 执行边界断言并写入验证记录：`git diff HEAD -- MacsyZones.xcodeproj`（含工作区改动；**不要**用 `custom...HEAD` 三点式——当前分支就是 `custom`，merge-base 等于 HEAD，diff 恒为空）中 `MACOSX_DEPLOYMENT_TARGET`/`SWIFT_VERSION`/`CODE_SIGN_STYLE`/`DEVELOPMENT_TEAM`/`PRODUCT_BUNDLE_IDENTIFIER` 均未变；另用 `grep -n` 直接比对五项现值与 T004 记录的基线；`grep -rn "com.apple.private\|sqlite3\|TCC.db" MacsyZones scripts` 无命中；新增或修改的用户可见文案逐条为中文（`git diff -U0 | grep '^+'` 检查 `Text(`/`Button(` 字符串）（FR-021/FR-022/FR-023）
- [ ] T041 [US5] 执行 SC-003 的场景：授权有效前提下连续 5 次重新登录（`quickstart.md` 场景 G），每次观察 30 秒；确认权限日志中 `trigger=launch` 且 `status=denied` 记录为 0；若某次误判，记录 `tccd` 日志是否伴随 `Too many open files`，并据此判断 60 秒宽限是否足够
- [ ] T042 [US5] 执行 SC-004 与 SC-005：`quickstart.md` 场景 I（登录项启动，`isLoginItem=true`）与场景 J（`sample` 确认探针不在主线程栈、`top` 闲置 CPU ≤ 2%）；再执行 SC-006（场景 K：27.0–27.2 旧形态，无可用机器则明确标注「未实机验证」）；任一项无法在本机完成时标注原因

# 阶段 8：收尾与交付

**目的**：跨故事验证、文档回填与切片提交。

- [ ] T043 构建矩阵双 PASS：`bash scripts/build-debug.sh`（Debug + `verify-signing.sh`）与 `xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones -configuration Release -derivedDataPath /tmp/m003-release CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=C7C84AAA3B67FACEA73042570A0BA2FC3D19E613 DEVELOPMENT_TEAM=74FR87HYTH clean build` + `bash scripts/verify-signing.sh /tmp/m003-release/Build/Products/Release/MacsyZones.app`；`warning:` 计数为 0
- [ ] T044 执行 `quickstart.md` 场景 A–K 全量手动矩阵，逐项回填实测记录表（无法自动化的项注明原因与替代证据，不得留空）
- [ ] T045 章程与文档复核：无新增配置字段（章程五）、三个新增源文件无 `#available`（额外约束）、探针在 `.utility` 队列且结果回主线程（主线程纪律）、诊断视图只在设置窗口打开时构建（惰性物化）、评估是否需要在 `AGENTS.md` 增「权限排障」段落
- [ ] T046 分切片提交（准备与基础 / US1 / US2 / US3 / US4 / US5 / 文档）并在本文件末尾写「实现记录」：提交哈希、验证结果、与计划的偏差、未完成项与原因

## 依赖关系

- 阶段 1（T001–T004）→ 阶段 2（T005–T014）→ 各用户故事。
- `MacsyZones/App.swift` 串行链：US1（T017–T018）→ US2（T021–T025）→ US4（T034–T036）；T025 依赖 T017，T034 依赖 T006。
- US3（T028–T033）可与 US1 并行（文件不重叠），但 T029 依赖 T024（同文件先后修改）。
- 阶段 7（T038–T042）依赖阶段 2 的 T011/T013 与阶段 4/6 完成（场景 G–J 需要稳定状态）。
- 阶段 8（T043–T046）依赖全部用户故事。

## 实现记录

（实现完成后填写：提交哈希、验证结果、与计划的偏差、未完成项。）
