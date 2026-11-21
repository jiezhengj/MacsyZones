# 研究报告：macOS 27 权限模型适配

**Feature**: `003-macos27-permissions` | **Date**: 2026-11-21

## R0：上游是否已有可复用实现（章程原则一）

**决策**：不复用上游，本 feature 自研。

**核查过程**：`git grep -n "AXIsProcessTrusted\|CGPreflight\|Accessibility" upstream/main -- '*.swift'` 命中 `upstream/main:MacsyZones/App.swift:518-533`（`checkAccessibilityPermission` + `showAccessibilityPermissionPopover`）与 `upstream/main:MacsyZones/Info.swift:15-95`（旧引导文案 + 旧截图），与 fork 同构，均为 macOS 26 及更早的做法；上游 `Info.plist` 为空字典，无权限说明键。

**理由**：上游 v3.1.1（2026-09-15）尚未适配 macOS 27.3 的面板拆分与「不可主动弹框」；无可回移代码。章程原则一要求「先查上游」，未要求「上游没有也照抄」，此处记录核查结论以证明例外成立。

**备选**：等待上游适配（不可控，用户当前已无法使用）；只改文案不改检测（用户仍会被模态框卡死）。

## R1：权限状态模型——三态、分能力

**决策**：用 `PermissionStatus { granted, denied, unknown }` 与 `PermissionCapability { windowControl, inputMonitoring, eventPosting }` 的组合，替代全局布尔 `hasAccessibilityPermission`。`eventPosting` 当前标记为 `notRequired`（本项目不 post CGEvent，只用 AX 写窗口属性）。

**理由**：
- macOS 27.3 起 `AXIsProcessTrustedWithOptions(prompt: true)` 不再能弹框（`tccd` 内 `Service kTCCServiceAccessibility does not allow prompting; returning preflight_unknown`），返回值可能是「未知」而非「未授权」，二值模型无法表达。
- 输入监听（ListenEvent）与窗口控制是两个独立授权（服务表里 `kTCCServiceListenEvent` 与 `kTCCServiceAccessibility` 分开，且新增了各自的 PerTarget 变体），合并成一个布尔会误导用户。

**备选**：继续单一布尔（无法区分「未知」→ 用户被无意义地挡住）；三态但只保留窗口控制（输入监听缺失时仍是静默失败）。

## R2：判定方式——API 结果 + 真实 AX 探针

**决策**：窗口控制能力按以下顺序判定：① `AXIsProcessTrusted()` 为 false 时先不直接下结论；② 对「前台 app」与 `com.apple.finder` 各做一次 `AXUIElementCopyAttributeValue(kAXWindowsAttribute)`：两次都 `.success`（含空数组）→ `granted`；任一返回 `kAXErrorAPIDisabled (-25211)` → `denied`；全部为 `.cannotComplete`/`-25204`/其他错误 → `unknown`。输入监听直接用 `CGPreflightListenEventAccess()`。

**理由**：
- 只有真实 AX 读操作能证明「系统认为这个进程可以控制其他 app」；espanso 的案例（`tccutil list` 报已授权、`AXIsProcessTrustedWithOptions` 仍 false）说明单一 API 会误判。
- 选前台 app 是因为吸附的对象就是它；选 Finder 是因为它几乎总在运行、且不受 WebKit 已知问题影响（27.3 beta 2 已知问题：拿到 Override 授权的 app 可能无法与 Safari 等 WebKit app 交互）。分别记录两个目标的结果，才能在诊断里表达「部分目标可控」。
- 只读 `kAXWindowsAttribute`，不做任何写操作，探针无副作用。

**备选**：只用 `AXIsProcessTrusted()`（误判率高）；用 `AXUIElementSetAttributeValue` 写窗口位置验证（会真的移动用户窗口，不可接受）。

**风险与兜底**：探针目标 app 可能未运行（Finder 被替换）→ 目标缺失时记为 `unknown` 并降级为纯 API 判定；探针耗时异常（> 1s）→ 中断并记 `unknown`，不阻塞。

## R3：面板与深链映射（27.0–27.2 vs 27.3+）

**决策**：

| 系统形态 | 面板路径 | 深链 |
|---|---|---|
| 27.0–27.2 | 隐私与安全性 → Device Control and Data Access（旧名「辅助功能」） | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` |
| 27.3+ | 隐私与安全性 → **System & App Protection Override**（主）；若其中没有本 app，再看 **无障碍**（`Accessibility`） | 主：`...?Privacy_Accessibility`；备：`...?Privacy_AccessibilityApps` |

**理由**：本机 `SecurityPrivacyExtension` 仍以 `Privacy_Accessibility` / `Privacy_AccessibilityApps` 作为锚点（`revealElementKeyName`），说明深链在 27.3 上继续有效；面板标题则分别被本地化为 `System & App Protection Override` 与 `无障碍`。版本判定用 `ProcessInfo.processInfo.operatingSystemVersion.minor >= 3`，不用 `#available`（章程禁降级分支）。

**备选**：只打开「隐私与安全性」首页（用户仍需自己找）；写死新标题（27.0–27.2 用户看到不存在的条目）。

**兜底**：`NSWorkspace.open(url)` 返回 false 时退化为打开 `com.apple.preference.security` 首页 + 文本路径提示，不静默失败。

## R4：复核时机与失败宽限

**决策**：
- 硬触发：启动完成后 `+0s`；`NSWorkspace.didActivateApplicationNotification`；`NSWorkspace.didWakeNotification`；`NSApplication.didBecomeActiveNotification`；任何 AX 调用返回 `-25211` 时立刻复核；用户在诊断面板点「重新检测」。
- 软触发：状态非 `granted` 时每 5 秒重试，最多 24 次（2 分钟）；`granted` 后降为每 30 秒一次（只读探针，成本可忽略）。
- 宽限：若上一次为 `granted`、本次变为 `denied`，启动 60 秒宽限窗口：期间只记日志与内部状态，不弹任何提示；宽限结束后仍 `denied` 才提示（对应社区定位的登录时 `tccd` 文件描述符耗尽导致的瞬时误判）。

**理由**：当前实现只在 `applicationDidFinishLaunching` 检测一次（`MacsyZones/App.swift:554`），正是 BTT 社区帖里被判定会翻车的模式；宽限期避免把 1–2 秒的系统抖动变成用户可见的阻挡框。

**备选**：只加一个 30 秒定时器（唤醒/激活场景响应慢）；不做宽限（复现社区误报）。

## R5：UI 形态——去掉模态阻挡，改为非模态引导与常驻状态

**决策**：
- 删除「未授权 → 弹 `AccessibilityDialog` 模态」的路径；改为：菜单栏图标附加权限状态（可选的小圆点/角标）+ 设置窗口顶部非模态横幅 + 首次启动的引导面板（可关闭、不抢焦点、`orderFrontRegardless` 但 `isFloatingPanel`）。
- 引导面板保留现有 `AccessibilityPermissionView` 的骨架，替换文案与步骤：明确写出 27.3 的面板名、说明「本 app 通常不在无障碍列表」、提供「打开系统设置」按钮（R3 深链）、以及「已授权，重新检测」按钮；不再要求重启。
- 旧截图（`MacsyZones/Tutorial.xcassets/Accessibility-Permission-Tutorial-1/2`）不再直接使用；若保留图片，必须换成 27.3 实机截图，否则只保留文字步骤（本 feature 选后者，避免用旧图误导）。

**理由**：spec FR-004/FR-009/FR-010 要求不阻塞；现有 `AccessibilityDialog` 是 `.screenSaver` 级别且「取消即退出 app」（`MacsyZones/Info.swift:214-222` 的 `onCancel` 调用 `exit(0)`），在新系统下等于把用户直接劝退。

**备选**：保留模态框只改文案（仍挡住主界面）；完全静默（用户不知道要授权）。

## R6：Release 可观测性

**决策**：新增 `os.Logger(subsystem: "MeowingCat.MacsyZones", category: "permissions")`，固定字段：`capability`、`status`、`probe`、`target`、`error`、`latencyMs`、`trigger`。`debugLog` 保持原样（DEBUG 下 print），权限相关日志一律走 `Logger`（Release 可见）。日志用 `privacy: .public` 输出非敏感字段，路径用 `.private`。

**理由**：现在 Release 零日志（`MacsyZones/Utils.swift:17` 仅在 `#if DEBUG` 下 print），用户报「权限开着却不能用」时无法定位；`log show --predicate 'subsystem == "MeowingCat.MacsyZones"'` 是标准取证方式。

**备选**：自写日志文件（引入磁盘写入与轮转负担，违反「不新增存储」的取舍）；只在诊断面板展示（用户未必打开）。

## R7：诊断面板的位置与内容

**决策**：在 `SettingsView` 的 `AdvancedSettingsSection` 之后新增 `PermissionDiagnosticsSection`（新文件 `PermissionDiagnosticsView.swift`），内容：三能力的当前状态与最近检测时间、探针目标与结果、App 路径 / 是否在 `/tmp` / 是否登录项、macOS 版本与 Build、App 版本与 Build；底部两个按钮：「重新检测」「复制报告」。

**理由**：设置窗口已有滚动布局与「高级设置」分组（`MacsyZones/SettingsView.swift:62-105`、`:798+`），插入成本最低；用户排障的自然入口就是设置。

**备选**：独立窗口（新增窗口生命周期与惰性物化约束）；菜单栏菜单项（信息密度不足）。

## R8：与 onboarding、WindowObserverManager 的接线

**决策**：
- `onboarding` 条件由 `hasAccessibilityPermission` 改为 `permissionCenter.windowControl == .granted`（`MacsyZones/App.swift:627`）；未授权时先展示权限引导，引导关闭后再判断。
- `WindowObserverManager` 的 AX 调用失败路径（`observeWindow` 返回 false、`kAXErrorAPIDisabled`）上报 `PermissionCenter.reportAXFailure()`，触发 R4 的即时复核，而不是静默 continue。
- 启动时不再调用 `checkAccessibilityPermission()`/`requestAccessibilityPermissions()`，改为 `permissionCenter.start()`。

**理由**：这三处是现有代码里唯一依赖「权限」的地方（`MacsyZones/App.swift:554-555`、`:627`、`:745`），集中替换后其余功能自然按状态降级。

**备选**：保留旧函数并在内部转发（多一层无意义抽象）；不改 onboarding（未授权用户永远看不到引导）。

## R9：权限不全时的降级矩阵

**决策**：

| 能力状态 | 行为 |
|---|---|
| 窗口控制 granted | 全部功能可用 |
| 窗口控制 denied/unknown | 不注册吸附/拖动处理；布局编辑器可打开但保存时提示；菜单栏图标显示「未授权」；不崩溃 |
| 输入监听 granted | 全局鼠标/键盘监听正常 |
| 输入监听 denied | 不安装全局监听；快捷键（Carbon `RegisterEventHotKey`）仍工作；拖动吸附暂停并在横幅标注原因 |
| 部分目标可控（per-target） | 诊断面板显示「部分应用受控」；吸附失败时提示一次「该系统授权按应用区分」 |

**理由**：spec FR-012/FR-014 要求按能力降级且可解释；Carbon 全局热键不依赖 Input Monitoring，所以「拖动不可用但快捷键可用」是可实现且诚实的状态。

**备选**：任一权限缺失就整体停用（体验倒退）；假装可用（用户看到无响应）。

## R10：验证方式

**决策**：三层：
1. 构建：`bash scripts/build-debug.sh`（正式签名 + `verify-signing.sh`）。
2. 静态与桩断言：`bash scripts/check_permission_model.sh`，用 `scripts/tests/permission-stubs.swift` 复刻 `PermissionStatus`/探针判定表，断言状态映射（含 `-25211`、`.cannotComplete`、探针缺失、宽限期计算）；同时 grep 断言关键不变量（无 `#available`、无 `AXUIElementSetAttributeValue` 出现在探针代码、无 `exit(0)` 在权限路径）。
3. 运行期：`bash scripts/permission-smoke.sh` —— 启动构建产物 20 秒，`log show` 断言出现权限日志、无 `fatal error`/崩溃报告、进程存活。

**理由**：与 002 的验证体系一致（无 XCTest target）；权限的真实授权状态只能由人操作，故 `quickstart.md` 保留手动矩阵。

**备选**：新增 XCTest target（改 pbxproj、影响签名流程，成本大于收益）。

## R11：不持久化决定

**决策**：权限状态与「已提示过」标记只存内存，不写 `AppSettings.json`/`UserDefaults`。

**理由**：章程五要求配置兼容且禁止强解包；权限是系统事实，不该由 app 缓存，缓存反而会制造「系统已撤销但 app 以为有权限」的错位。内存标记在重启后重置，最多多提示一次，无害。

**备选**：持久化「不再提示」（会在用户重新授权失败时静默，违背 FR-005）。

## R12：未决风险与后续观察

1. **面板归属不确定**：本 app 是否出现在 `System & App Protection Override` 还是 `无障碍`，需实机授权时确认；引导按「先主后备」措辞，验证时记录实测结果并回填 `quickstart.md`。
2. **per-target 授权范围**：27.3 beta 2 已知问题（Override app 无法控制 Safari/WebKit app）可能让部分用户「部分窗口不可吸附」；诊断面板需如实呈现，不在本 feature 内绕过。
3. **27.3 不在 SDK 内**：无法编译新符号，若苹果后续提供 `AXIsProcessTrusted` 的替代 API 或 entitlement，需另立 feature。
4. **升级路径无法在本机自动化**：本机已升级到 27.3，27.2→27.3 的「已授权保持不变」只能在用户机器上手工验证，quickstart 给出步骤。
