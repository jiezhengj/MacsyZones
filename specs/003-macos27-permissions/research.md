# 研究报告：macOS 27 权限模型适配

**Feature**: `003-macos27-permissions` | **Date**: 2026-11-21

## R0：上游是否已有可复用实现（章程原则一）

**决策**：不复用上游，本 feature 自研。

**核查过程**：`git grep -n "AXIsProcessTrusted\|CGPreflight\|Accessibility" upstream/main -- '*.swift'` 命中 `upstream/main:MacsyZones/App.swift:518-533`（`checkAccessibilityPermission` + `showAccessibilityPermissionPopover`）与 `upstream/main:MacsyZones/Info.swift:15-95`（旧引导文案 + 旧截图），与 fork 同构，均为 macOS 26 及更早的做法；上游 `Info.plist` 为空字典，无权限说明键。

**理由**：上游 v3.1.1（2026-09-15）尚未适配 macOS 27.3 的面板拆分与「不可主动弹框」；无可回移代码。章程原则一要求「先查上游」，未要求「上游没有也照抄」，此处记录核查结论以证明例外成立。

**备选**：等待上游适配（不可控，用户当前已无法使用）；只改文案不改检测（用户仍会被模态框卡死）。

## R1：权限状态模型——三态、分能力

**决策**：用 `PermissionStatus { granted, denied, unknown, notRequired }` 与 `PermissionCapability { windowControl, inputMonitoring, eventPosting }` 的组合，替代全局布尔 `hasAccessibilityPermission`。`eventPosting` 当前取值为 `notRequired`（本项目不 post CGEvent，只用 AX 写窗口属性）；`notRequired` 与三态并列，语义是「该能力不适用」，UI 不提示、不参与 `overall` 汇总。

**理由**：
- macOS 27.3 起 `AXIsProcessTrustedWithOptions(prompt: true)` 不再能弹框（`tccd` 内 `Service kTCCServiceAccessibility does not allow prompting; returning preflight_unknown`），返回值可能是「未知」而非「未授权」，二值模型无法表达。
- 输入监听（ListenEvent）与窗口控制是两个独立授权（服务表里 `kTCCServiceListenEvent` 与 `kTCCServiceAccessibility` 分开，且新增了各自的 PerTarget 变体），合并成一个布尔会误导用户。

**备选**：继续单一布尔（无法区分「未知」→ 用户被无意义地挡住）；三态但只保留窗口控制（输入监听缺失时仍是静默失败）。

## R2：判定方式——API 结果 + 真实 AX 探针

**决策**：窗口控制能力由两条真实 AX 探针推导（`frontmost` = 当前前台 app，`finder` = `com.apple.finder`，各读一次 `kAXWindowsAttribute`），另记一条 `api` 探针（`AXIsProcessTrusted()`）仅作诊断参考、不参与判定。汇总规则（与 `data-model.md`「窗口控制汇总规则」逐格一致）：

| frontmost | finder | 汇总 |
|---|---|---|
| success | success | `granted` |
| success | apiDisabled | `granted`（部分目标受控，记 `partialTargets`） |
| apiDisabled | success | `granted`（部分目标受控，记 `partialTargets`） |
| apiDisabled | apiDisabled | `denied` |
| success | unknown | `granted`（另一目标无法判定，不据此降级） |
| apiDisabled | unknown | `unknown` + `lastError`（无法确认是全局拒绝还是目标侧问题） |
| unknown | unknown | `unknown` + `lastError` |

即：**任一探针 success → granted；没有任何 success 且全部已完成的探针都是 apiDisabled → denied；其余（超时、`-25204`、目标 app 不存在）→ unknown。**「部分目标受控」只影响诊断 `notes`，不影响 `granted` 判定（与 FR-014 一致：不得把部分失败报成未授权）。输入监听直接用 `CGPreflightListenEventAccess()`，只需一条探针。

**理由**：
- 只有真实 AX 读操作能证明「系统认为这个进程可以控制其他 app」；espanso 的案例（`tccutil list` 报已授权、`AXIsProcessTrustedWithOptions` 仍 false）说明单一 API 会误判。
- 选前台 app 是因为吸附的对象就是它；选 Finder 是因为它几乎总在运行、且不受 WebKit 已知问题影响（27.3 beta 2 已知问题：拿到 Override 授权的 app 可能无法与 Safari 等 WebKit app 交互）。分别记录两个目标的结果，才能在诊断里表达「部分目标可控」。
- 只读 `kAXWindowsAttribute`，不做任何写操作，探针无副作用。

**备选**：只用 `AXIsProcessTrusted()`（误判率高）；用 `AXUIElementSetAttributeValue` 写窗口位置验证（会真的移动用户窗口，不可接受）。

**风险与兜底**：探针目标 app 可能未运行（Finder 被替换）→ 该目标记 `unknown`，按汇总表得出 `unknown` 或 `granted`，**不降级为纯 API 判定**（espanso 案例证明 API 结论可能与真实可用性相反）；探针耗时异常（> 1s）→ 中断并记 `unknown`，不阻塞。

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
- 硬触发：启动完成后 `+0s`；`NSWorkspace.didActivateApplicationNotification`（注册在 `NSWorkspace.shared.notificationCenter`）；`NSWorkspace.didWakeNotification`（同一通知中心）；设置窗口 `NSWindow.didBecomeKeyNotification`（注册在 `NotificationCenter.default`）；用户点击菜单栏图标（`toggleSettings` 回调内）；任何 AX 调用返回 `-25211` 时立刻复核；诊断面板「重新检测」。`NSApplication.didBecomeActiveNotification` 因 `NSApp.setActivationPolicy(.prohibited)`（`MacsyZones/App.swift:550`）可能永不触发，**只作可选补充，不作为依赖**；实机若确认不触发则删除该注册。
- 软触发：状态非 `granted` 时每 5 秒重试，最多 24 次（2 分钟），最坏收敛时间 ≈ 5s 间隔 + 1s 探针超时 = 6s，满足 SC-002 的 10 秒上限；`granted` 后降为每 30 秒一次（只读探针，成本可忽略）。
- 宽限：**只用于登录期的瞬时误判**——当「上一次为 `granted`、本次探针为 `denied`、且距本进程启动 < 60 秒」时进入可疑态：期间对外仍报 `granted`、只记日志、不弹提示；60 秒内恢复 `granted` 即当作抖动，超时仍 `denied` 才切到 `denied` 并提示。**运行期（距启动 ≥ 60 秒）的 `granted → denied` 立即生效**：用户在系统设置里主动关掉权限，属于确定性操作，应立即降级提示，不进宽限（对应 `quickstart.md` 场景 C）。

**理由**：当前实现只在 `applicationDidFinishLaunching` 检测一次（`MacsyZones/App.swift:554`），正是 BTT 社区帖里被判定会翻车的模式；宽限期避免把 1–2 秒的系统抖动变成用户可见的阻挡框。

**备选**：只加一个 30 秒定时器（唤醒/激活场景响应慢）；不做宽限（复现社区误报）。

## R5：UI 形态——去掉模态阻挡，改为非模态引导与常驻状态

**决策**：
- 删除「未授权 → 弹 `AccessibilityDialog` 模态」的路径；改为：菜单栏图标附加权限状态（可选的小圆点/角标）+ 设置窗口顶部非模态横幅 + 首次启动的引导面板（可关闭、不抢焦点、`orderFrontRegardless` 但 `isFloatingPanel`）。
- 引导面板保留现有 `AccessibilityPermissionView` 的骨架，替换文案与步骤：明确写出 27.3 的面板名、说明「本 app 通常不在无障碍列表」、提供「打开系统设置」按钮（R3 深链）、以及「已授权，重新检测」按钮；不再要求重启。
- 旧截图（`MacsyZones/Tutorial.xcassets/Accessibility-Permission-Tutorial-1/2`）不再直接使用；若保留图片，必须换成 27.3 实机截图，否则只保留文字步骤（本 feature 选后者，避免用旧图误导）。

**理由**：spec FR-004/FR-009/FR-010 要求不阻塞；现有 `AccessibilityDialog` 是 `.screenSaver` 级别且「取消即退出 app」（`MacsyZones/Info.swift:221-224` 的 `onCancel` 闭包调用 `exit(0)`，`exit(0)` 在 `:223`），在新系统下等于把用户直接劝退。

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

**理由**：这三处是现有代码里唯一依赖「权限」的地方（调用点 `MacsyZones/App.swift:554`/`:555`、onboarding 读取 `:627`、引导展示判定 `:746`），集中替换后其余功能自然按状态降级。

**备选**：保留旧函数并在内部转发（多一层无意义抽象）；不改 onboarding（未授权用户永远看不到引导）。

## R9：权限不全时的降级矩阵

**决策**：

| 能力状态 | 行为 |
|---|---|
| 窗口控制 granted | 全部功能可用 |
| 窗口控制 unknown | 先按已安装启动（FR-013 不在未判定前自废功能）；首轮判定后由 1 次 `onStatusChange` 纠正；横幅显示「检测中」，不报警 |
| 窗口控制 denied | 不安装全局鼠标监听：拖动、悬停高亮、右键菜单暂停；布局编辑器可打开但保存时提示只读；菜单栏图标显示「未授权」；不崩溃 |
| 输入监听 granted | 全局键盘监听（`keyDown`/`flagsChanged`）正常 |
| 输入监听 unknown | 同窗口控制：先安装，首轮判定后纠正，不报警 |
| 输入监听 denied | 不安装全局键盘监听：修饰键+吸附键驱动的布局切换与吸附键组合暂停并标注；鼠标拖动/吸附不受影响（属窗口控制）；Carbon 全局热键仍工作 |
| 部分目标可控（per-target） | 诊断面板显示「部分应用受控」；吸附失败时提示一次「该系统授权按应用区分」 |

**理由**：spec FR-012/FR-014 要求按能力降级且可解释。两个能力对应两组不同监视器：窗口控制 denied 时鼠标拖动不可用但 Carbon 热键仍可用；输入监听 denied 时只丢键盘驱动的布局切换，鼠标拖动完全不受影响。`unknown` 一律先按已安装启动（FR-013），首轮判定后由 `onStatusChange` 纠正。

**备选**：任一权限缺失就整体停用（体验倒退）；假装可用（用户看到无响应）。

## R10：验证方式

**决策**：三层：
1. 构建：`bash scripts/build-debug.sh`（正式签名 + `verify-signing.sh`）。
2. 静态与桩断言：`bash scripts/check_permission_model.sh` —— 用 `awk` 从真实源码抽取汇总/宽限/pane 选择函数（R15），拼进 `scripts/tests/permission-stubs.swift` 后执行 `scripts/tests/permission-assertions.swift`，断言汇总表 7 行、`-25211`、`.cannotComplete`、探针缺失、宽限三条边界与两套 pane 映射；同时 grep 断言关键不变量（三个新增源文件无 `#available`、无 `AXUIElementSetAttributeValue`、无 `exit(`；`Info.swift` 无 `exit(0)`）。
3. 运行期：`bash scripts/permission-smoke.sh` —— 启动构建产物 20 秒，`log show` 断言出现权限日志、无 `fatal error`/崩溃报告、进程存活。

**理由**：与 002 的验证体系一致（无 XCTest target）；权限的真实授权状态只能由人操作，故 `quickstart.md` 保留手动矩阵。

**备选**：新增 XCTest target（改 pbxproj、影响签名流程，成本大于收益）。

## R11：不持久化决定

**决策**：权限状态与「已提示过」标记只存内存，不写 `AppSettings.json`/`UserDefaults`。

**理由**：章程五要求配置兼容且禁止强解包；权限是系统事实，不该由 app 缓存，缓存反而会制造「系统已撤销但 app 以为有权限」的错位。内存标记在重启后重置，最多多提示一次，无害。

**备选**：持久化「不再提示」（会在用户重新授权失败时静默，违背 FR-005）。

## R13：输入监听监视器按状态迁移「装/卸」

**决策**：全局 `NSEvent` 监视器不在启动时一次性决定，而是**按事件类型分别绑定对应能力**：
- 鼠标类（`leftMouseDown`/`leftMouseDragged`/`leftMouseUp`/`rightMouseDown` 在 `MacsyZones/App.swift:607/611/615/984`，`mouseMoved` 在 `MacsyZones/Layout.swift:1123`）→ 绑 `windowControl`（它们本就依赖辅助功能授权，现有实现即如此）；
- 键盘类（`keyDown`/`flagsChanged`，`MacsyZones/App.swift:866`）→ 绑 `inputMonitoring`；
- 启动安装规则：对应能力 `!= .denied` 时安装（`unknown` 也安装——FR-013 只禁止「假定已可用」，不要求在未判定前自废功能）；
- 状态迁移：`PermissionCenter.onStatusChange` 观察到某个能力变为 `granted` 时补装该类、变为 `denied` 时卸载（`NSEvent.removeMonitor`），两类互不牵连；
- 卸载点：`stop()` 与 `applicationWillTerminate` 统一卸载，避免重复安装导致同一事件被处理多次。

**理由**：`NSEvent.addGlobalMonitorForEvents` 没有「暂停」语义，只能增删；若只做启动时一次性判定，已授权用户一旦在首轮探测完成前启动（`unknown` → 不装）就会整场失去对应功能且不会自愈（评审指出的 BLOCKER）。另外必须按类型分开绑定：把鼠标监视器绑到 `inputMonitoring` 会让「只开窗口控制、没开输入监控」的用户反而失去拖动（评审 MAJOR）。

**备选**：启动时无脑安装（未授权时监听不生效但不崩溃，代价是「静默失灵」不可见）；定时重装（会重复注册，事件被处理多次）。

## R12：未决风险与后续观察

1. **`NSApplication.didBecomeActiveNotification` 在 `.prohibited` 激活策略下可能永不触发**：应用启动即 `NSApp.setActivationPolicy(.prohibited)`（`MacsyZones/App.swift:550`），不会成为前台应用。因此复核触发不能只依赖它，必须补可触发的时机（点击状态栏图标、设置窗口 `didBecomeKey`、30 秒轮询）。若实机验证发现该通知确实不触发，从实现中移除并记录。

2. **面板归属不确定**：本 app 是否出现在 `System & App Protection Override` 还是 `无障碍`，需实机授权时确认；引导按「先主后备」措辞，验证时记录实测结果并回填 `quickstart.md`。实测进展（2026-11-21）：本机为 macOS 27.3（Build 26C5047e），但当前本 bundle 处于未授权态（探针 `axError=-25211`，`preflight` denied），系统设置面板归属须在真实授权流程中由用户确认（未授权状态下无面板条目可查）；引导文案已按「先 Override 后无障碍」实现，深链落点验证留待场景 A 人工部分与场景 B。
3. **per-target 授权范围**：27.3 beta 2 已知问题（Override app 无法控制 Safari/WebKit app）可能让部分用户「部分窗口不可吸附」；诊断面板需如实呈现，不在本 feature 内绕过。
4. **27.3 不在 SDK 内**：无法编译新符号，若苹果后续提供 `AXIsProcessTrusted` 的替代 API 或 entitlement，需另立 feature。
5. **升级路径无法在本机自动化**：本机已升级到 27.3，27.2→27.3 的「已授权保持不变」只能在用户机器上手工验证，quickstart 给出步骤。

## R14：可反复启动的构建产物

**决策**：新增 `scripts/build-permission-artifact.sh`：`xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones -configuration Debug -derivedDataPath /tmp/m003-debug CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=C7C84AAA3B67FACEA73042570A0BA2FC3D19E613 DEVELOPMENT_TEAM=74FR87HYTH build` → `rm -rf ~/Applications/MacsyZones-dbg.app` → `cp -R /tmp/m003-debug/Build/Products/Debug/MacsyZones.app ~/Applications/MacsyZones-dbg.app` → `bash scripts/verify-signing.sh ~/Applications/MacsyZones-dbg.app`。

**理由**：`scripts/build-debug.sh` 末尾 `trap cleanup EXIT` 会删除派生数据，跑完没有可启动产物；而 TCC 授权按「已签名 app 的固定路径」记录，反复用 `/tmp` 路径或每次重新构建都会让授权记录失效。冒烟脚本与手动矩阵都需要一个路径稳定、签名正式的副本。**注意**：重新构建会改变二进制哈希，授权可能失效，手动矩阵前应重新执行本轮构建并在系统设置里确认条目。

**备选**：改 `build-debug.sh` 保留产物（会影响 002 的既有流程与清理语义）；直接用 Xcode 的 DerivedData（路径含随机哈希，不可控）。

## R15：断言针对真实源码，而不是复刻品

**决策**：`scripts/check_permission_model.sh` 用 `awk` 从 `MacsyZones/PermissionCenter.swift` 与 `MacsyZones/PermissionGuidance.swift` **抽取真实函数体**（如窗口控制汇总函数、pane 选择函数），拼到 `scripts/tests/permission-stubs.swift` 提供的纯值类型上下文里编译执行，断言表由 `permission-assertions.swift` 给出。沿用 002 `scripts/check_lazy_lifecycle.sh` 的既有做法（抽取 `UserLayout`/`startEditing` 真实片段，139 条断言）。

**理由**：只断言「复刻的桩」会在真实实现漂移时照样通过（这正是首次评审指出的缺陷）。抽取真实源码后，改坏真实分支会让断言失败。

**兜底**：若某函数抽取困难（依赖 AppKit 类型），退化为对该函数所在文件的 `grep -A/-B` 分支断言，并在脚本输出中标注 `MODE=source-grep`，不得静默跳过。
