**Feature Branch**: `003-macos27-permissions`
**Created**: 2026-11-21
**Status**: Draft
**Input**: 用户请求（m00934）：本机已升级到 macOS 27 beta，系统权限管理（尤其是辅助功能）发生变化；先查官方文档、再在本机系统内检测、再看开发者社区普遍的应对方式，然后判断本项目该如何改进，最后开一个新的 feature。

# 研究依据与现状

本节记录本 feature 的需求来源：本机实测、Apple 官方说明与开发者社区的既有案例。

1. **本机环境**：macOS 27.3（Build `26C5047e`）。`tccd` 日志显示 `AXIsProcessTrustedWithOptions` 底层调用 `TCCAccessRequest for kTCCServiceAccessibility` 时缺少 `com.apple.private.tcc.manager.check-by-audit-token` entitlement；`tccd` 二进制中含 `Service kTCCServiceAccessibility does not allow prompting; returning preflight_unknown` —— 即**程序已不能再主动弹出辅助功能授权框**。
2. **面板被拆开**：本机 `SecurityPrivacyExtension` 的服务表新增 `TCCServiceAccessibility` 与 `TCCServiceAccessibilityApps` 两个面板；本地化字符串把前者标题定为 **System & App Protection Override**（「覆盖系统与 App 保护」，`Override System Protections` 按钮、同意文案 `Allow “%@” to override system protections so it can control your Mac and apps?`），把后者定名 **Accessibility / 无障碍**，并写明「Only apps with an Accessibility designation, such as screen readers and voice control tools, appear here」。也就是说：用 AX 控制其他 app 的通用工具通常走前者；后者只收系统认定的辅助技术 app。本 app 实际归属需在实机上确认（列表里出现与否），引导不得单方面假定。
3. **per-target 记录**：`tccd` 新增 `kTCCServiceAccessibilityPerTarget`、`kTCCServiceListenEventPerTarget`、`kTCCServicePostEventPerTarget` 三组服务，错误串含 `Message is missing the target audit token`；官方 27.3 beta 2 release notes 亦写明「单一授权方式：从列表中选择发起请求的 app」「允许用户把 app 配置为每次都询问」。
4. **官方 27.3 beta 2 说明**：要求开发者「adjust how you onboard users」并「gracefully handle having access to only a limited set of folders or apps」；已知问题包括「拿到覆盖授权的 app 可能无法与 Safari 等 WebKit app 交互」；`macOS 27 Release Notes` 的 TCC 段唯一 Deprecation 是 `Apps can no longer access the local TCC database directly.`。
5. **社区现状**：Deskflow 需同时把 `App.app` 与 `Contents/MacOS/core` 加入授权；espanso 出现 `tccutil list` 报已授权、但 `AXIsProcessTrustedWithOptions` 仍返回 false 的卡死；BetterTouchTool 用户定位到登录时 15–20 个登录项在一秒内集中触发 TCC 校验，`tccd system` 撞上 256 文件描述符上限（`Too many open files`），对**已授权**服务也返回 denied，导致 app 误判。

本项目现状（`/Users/jiezhengj/Documents/Project/MacsyZones`）：

- 权限只在 `MacsyZones/App.swift:554` 启动时检测一次，用 `AXIsProcessTrustedWithOptions(prompt: true)`（`:740-742`）；之后 `hasAccessibilityPermission`（`:38`）再不刷新。
- 未授权时弹模态 `AccessibilityDialog`（`MacsyZones/Info.swift:210`），文案指向「隐私与安全性 → 辅助功能」（`MacsyZones/Info.swift:55`），配图是 macOS 26 时代的旧面板截图（`MacsyZones/Tutorial.xcassets/Accessibility-Permission-Tutorial-1/2`）；对话框没有「打开系统设置」按钮，只能「取消」或「重启应用」。
- 引导流程用 `!onboardingState.hasCompletedOnboarding && hasAccessibilityPermission`（`MacsyZones/App.swift:627`）判定，权限判定为 false 时引导永远不启动。
- 全局事件监听全部走 `NSEvent.addGlobalMonitorForEvents`（`MacsyZones/Layout.swift:1123`、`MacsyZones/App.swift:607/611/615/866/984`），但从未检测 ListenEvent/Input Monitoring 授权，也没有 `CGPreflightListenEventAccess` 调用。
- `debugLog` 只在 `#if DEBUG` 下 `print`（`MacsyZones/Utils.swift:17`），Release 无任何权限诊断输出。

# 用户场景与独立验收测试

## 用户故事 1：首次授权引导指向 macOS 27 真正需要的开关（优先级：P1）

用户在一台全新安装 macOS 27.3 的 Mac 上装好 MacsyZones，首次启动时 App 没有窗口控制权限。用户需要知道：系统设置里该打开哪一项、为什么「无障碍」列表里找不到 MacsyZones、打开后是否需要重启。

当前行为会让用户走错路：`AXIsProcessTrustedWithOptions(prompt: true)` 在新系统上不再弹框，对话框却把用户指向「辅助功能/无障碍」面板，而窗口管理器不在那个列表里，用户找不到就卡死。

**为何必须做**：这是新系统上「装了就用不了」的第一道门；引导指错面板等于把用户永久挡在门外，与本项目「开箱即用」的定位直接冲突。

**独立验收测试**：

1. **指引正确**：首次启动未授权时展示的引导文案，明确写出面板路径「系统设置 → 隐私与安全性 → System & App Protection Override」（本机中文系统上该标题可能仍显示英文，以实际面板为准），并说明「若该面板里没有 MacsyZones，再检查『无障碍』；窗口管理器通常归入前者而非后者」。文案不假设系统一定把本 app 放在哪个列表，避免再次指错。
2. **一键直达**：引导里提供按钮直接打开该面板，点一次即落在正确位置（不是笼统打开「隐私与安全性」首页）。
3. **授权后免重启**：用户在该面板添加并开启 MacsyZones 后，App 在数秒内自行识别为已授权并继续（无需点「重启应用」）；只有在检测到进程级状态确实需要重启时才提示重启。
4. **配图与系统一致**：引导不再展示与新系统面板不符的旧截图；27.0–27.2（面板尚未拆分）与 27.3+（拆分后）两种形态下，用户看到的措辞与截屏都和本机实际面板一致。

## 用户故事 2：权限状态持续复核，不再「一次误判定终身」（优先级：P1）

用户把 MacsyZones 设为登录项。登录瞬间系统 `tccd` 可能因集中校验而短暂把已授权服务判成 denied（社区已定位到 256 文件描述符上限），App 若只在启动时检测一次，就会把这次瞬时失败当成永久未授权，弹出模态框并挡住主功能。

**为何必须做**：本项目当前正是「启动时检测一次 + 模态框」的做法（`MacsyZones/App.swift:554`、`MacsyZones/Info.swift:210`），在 macOS 27 上属于已知会翻车的模式；不修，用户会反复遇到「权限明明开着却用不了」。

**独立验收测试**：

1. **启动后复核**：冷启动、从睡眠唤醒、切换回前台三种时机都重新检测权限；检测到状态变化时更新界面，不需要用户重启。
2. **瞬时失败不误报**：模拟一次「TCC 校验返回 denied 但授权实际存在」的失败（可通过批量启动多个登录项或注入失败路径复现），App 在宽限期内静默重试，**不得**弹出模态阻挡框；重试恢复后功能自动可用。
3. **真实撤销立即响应**：运行中在系统设置里关掉权限，App 在数秒内识别，降级为「只读/暂停吸附」并提示，而不是继续静默失败。
4. **三态可区分**：界面与日志能区分「未授权」「已授权」「未知（校验不可用）」三种状态；「未知」不当作「未授权」处理，不弹阻挡框。

## 用户故事 3：权限诊断面板与 Release 可观测性（优先级：P2）

用户反馈「我明明开了权限但还是不能用」，开发者需要在不装 Xcode、不加日志的情况下定位：是窗口控制权限、输入监听权限、还是别的东西没开。

**独立验收测试**：

1. **诊断面板**：设置里可查看每项能力（窗口控制 AX、全局输入监听、事件投递）的当前状态、最近检测时间、检测所用 API 与耗时、App 自身路径、登录项状态。
2. **可复制报告**：一键复制结构化报告（JSON 纯文本，字段见 `contracts/permission-report.schema.json`：macOS 版本与 Build、App 版本与 Build、Bundle ID、可执行文件路径、是否位于 `/tmp` 或已 translocation、各能力状态与探针明细），粘贴即完整、可被契约校验。
3. **Release 有日志**：Release 构建把权限判定、状态变化、失败重试写入统一日志（可通过 `log show` 按子系统过滤查看），不依赖 `#if DEBUG`。

## 用户故事 4：全局输入监听单独检测与降级（优先级：P2）

拖动吸附依赖全局鼠标事件，快捷键依赖全局键盘事件。macOS 27.3 把输入监听（ListenEvent）与窗口控制分开治理，还引入了 per-target 授权；用户可能只开了其中一项。

**独立验收测试**：

1. **分别检测**：窗口控制权限与输入监听权限分别检测、分别提示，不再用单一布尔代表全部权限。
2. **精确提示**：只缺输入监听时，提示文案指明「输入监控」面板与缺少它的具体后果（拖动吸附/快捷键失效），不误导用户去改窗口控制开关。
3. **部分授权可用**：在只有窗口控制权限、没有输入监听权限时，不崩溃；能用键盘/菜单触发的功能保持可用，依赖全局鼠标的功能明确显示为暂停。
4. **per-target 场景有解释**：当系统把授权按目标 app 区分（用户选择「每次都询问」或只授权部分目标）时，App 说明「部分窗口可控、部分会弹询问」，不把部分失败报成完全未授权。

## 用户故事 5：跨 27.x 子版本与升级路径的稳定性（优先级：P3）

同一份构建要能在 macOS 27.0–27.2（面板名为 Device Control and Data Access、未拆分）与 27.3+（拆成 System & App Protection Override + 无障碍）上给出各自正确的指引；从 27.2 升级到 27.3 后，已授予的权限按官方说法「保持不变」，App 不应把升级后的用户重新挡在引导页。

**独立验收测试**：

1. **双形态指引**：在 27.0–27.2 和 27.3+ 上分别手工验证引导文案与打开的面板都正确。
2. **升级不倒退**：在旧版本已授权的前提下升级到 27.3，首次启动直接可用，不出现阻挡框，不要求重新授权（以本机 tccd 日志与实机操作记录为准）。
3. **未知面板容错**：当系统面板标题/层级再次变化、深链无法精确落位时，退化为打开「隐私与安全性」首页并给出文字路径，不报错、不空转。

## 边界与异常情况

- 用户在面板里选择「每次都询问」：每次控制窗口可能弹一次系统询问；被拒绝时 App 不崩、不改窗口、给出一次性提示并可重试。
- 权限刚授予但进程尚未刷新：以「数秒内自动识别」为准，不要求用户点重启；确实需要重启时（如 TCC 缓存未生效），给出明确的一次性提示，不反复弹。
- 系统完整性保护（SIP）关闭或企业 MDM 下发默认值：诊断面板显示「由系统策略管理」，不与用户设置混淆。
- 从 `/tmp` 或 translocation 路径运行：提示权限归属可能记在父进程/实际路径上，诊断报告标出真实路径；不把这种场景下的失败报成「用户没开权限」。
- 屏幕阅读器等辅助技术同时运行：不与其争抢焦点，引导面板不抢走 VoiceOver 的焦点。

# 功能需求

## 权限检测与状态模型

- **FR-001**：必须建立显式的权限状态模型，至少包含：窗口控制（AX）、全局输入监听、事件投递三类能力；每类状态取值为「已授权」「未授权」「未知」，另加「本 feature 不需要」（`notRequired`，仅事件投递使用）。
- **FR-002**：检测不得只依赖 `AXIsProcessTrustedWithOptions(prompt: true)`；必须包含一次真实 AX 读操作作为可用性探针（例如对已知可访问目标读取窗口列表），以区分「API 报告已授权但调用仍失败」与「确实未授权」。
- **FR-003**：启动后、从睡眠唤醒后、应用重新激活后、以及每次检测到 AX 调用返回 `kAXErrorAPIDisabled` 时，重新评估状态。
- **FR-004**：状态变化必须在界面上反映；未授权不得阻塞 App 启动、不得使用模态对话框挡住主功能。
- **FR-005**：对「未知」状态设宽限期与退避重试；宽限期内静默重试，不弹提示；超限后以非模态方式提示并提供「重新检测」。

## 引导与系统面板对接

- **FR-006**：引导文案必须按本机实际面板结构给出路径，且能直接打开窗口控制权限所在面板；27.0–27.2 与 27.3+ 两种形态分别正确；对 27.3+ 需同时给出「System & App Protection Override」与「无障碍」的先后检查顺序，不假定本 app 一定出现在某一边。
- **FR-007**：引导必须解释「本 app 不会出现在『无障碍』列表」的原因，避免用户在错误面板里反复寻找。
- **FR-008**：引导中不得再出现与新系统不一致的旧面板截图；截图与措辞需与本机面板一致，或改为不依赖截图的文字步骤。
- **FR-009**：权限授权后自动继续，不把「重启应用」作为唯一出路；必须重启时只提示一次并说明原因。
- **FR-010**：引导与对话框不抢焦点、不阻塞输入、可随时关闭；关闭后主界面以非模态横幅继续提示。

## 输入监听与事件投递

- **FR-011**：必须单独检测全局输入监听（`CGPreflightListenEventAccess`）并在缺失时给出针对性的面板路径与后果说明。
- **FR-012**：权限不全时功能按能力降级：缺输入监听 → 依赖全局鼠标/键盘的功能暂停并可见地标注；缺窗口控制 → 只保留只读展示。
- **FR-013**：不得在未检测的情况下假定全局监听已可用；不得因为监听缺失而崩溃或陷入忙循环。
- **FR-014**：对 per-target 授权（部分目标可用）必须能表达「部分可控」，不得整体报成未授权。

## 诊断与可观测性

- **FR-015**：Release 构建必须输出权限相关统一日志（判定结果、状态变化、重试、失败原因），可通过系统日志工具按子系统过滤查看。
- **FR-016**：设置里提供权限诊断面板，展示每项能力的状态、最近检测时间、检测方式与耗时、App 路径、是否登录项。
- **FR-017**：诊断面板支持一键复制结构化报告，内容足以让维护者在没有本机环境的情况下判断权限归属问题。
- **FR-018**：诊断报告不得包含用户隐私内容（窗口标题、文件路径以外的个人数据不采集）。

## 兼容、升级与范围边界

- **FR-019**：同一构建必须同时适配 macOS 27.0–27.2 与 27.3+ 的面板差异；差异通过运行时检测处理，不引入以 `#available` 分支实现的降级路径。
- **FR-020**：从旧子版本升级后，已授权用户首次启动不得被重新挡在引导页（以实机升级验证为准）。
- **FR-021**：不申请、不依赖任何需要苹果审批的私有 entitlement；不修改签名方式、Bundle ID、Team ID 与部署目标。
- **FR-022**：不得读取或写入 TCC 数据库，不得尝试用 `sqlite3` 绕过系统权限模型；只使用公开 API 与系统设置深链。
- **FR-023**：引导与诊断的文案保持中文，风格与现有设置界面一致；不新增英文硬编码提示。

# 核心实体模型

- **PermissionCapability**：窗口控制（AX）、全局输入监听（ListenEvent）、事件投递（PostEvent）；每项带「是否本 app 需要」的判定（当前不需要事件投递）。
- **PermissionStatus**：已授权 / 未授权 / 未知 / 本项目不需要（`notRequired`）；带来源（API 探针 / 真实调用失败 / 用户操作）与时间戳。
- **PermissionProbe**：一次检测的记录，含能力、使用的方法、耗时、原始返回（错误码如 `kAXErrorAPIDisabled = -25211`）。
- **GuidanceTarget**：按系统版本选择的面板标识、深链 URL、显示标题与步骤文案。
- **DiagnosticReport**：系统版本与 Build、App 版本与 Build、路径与登录项状态、各能力状态与最近检测时间。

# 可度量验收准则

- **SC-001**：全新安装、未授权状态下，用户从看到引导到完成授权并成功吸附一个窗口，操作步骤不超过「打开面板 → 添加/开启 → 回到 app」三步，且在实机上可复现。
- **SC-002**：授权生效后，App 在 10 秒内识别为已授权（不重启进程）；用户主动触发时（切换回 app、点「重新检测」）应在 2 秒内收敛。
- **SC-003**：在授权有效的前提下连续使用 7 天（含至少 5 次登录启动），不出现「误报未授权」的阻挡提示；验证方式为连续 5 次重新登录后检查权限日志（`trigger=launch` 且 `status=denied` 的记录为 0）与人工确认无引导弹出。
- **SC-004**：诊断面板在六种场景下状态正确：已授权、已撤销、未知、从 `/tmp` 运行、translocation、登录项启动。
- **SC-005**：权限检测与探针不得造成主线程超过 50ms 的阻塞；闲置 5 分钟 CPU 占用 ≤ 2%。验证方式：`sample <pid> 30` 采样主线程栈确认无探针同步执行，`top -pid <pid> -l 5` 观察闲置 CPU。
- **SC-006**：27.0–27.2 与 27.3+ 两个形态各手工验证通过（引导文案、打开的面板、授权后行为）。

# 实施假设与环境基准

- 本机为 macOS 27.3（Build `26C5047e`，Apple Silicon）；Xcode 27.2，SDK 为 `MacOSX27.2.sdk`，**无 27.3 SDK**，因此该 feature 只能用既有 API + 运行时探测实现，不能依赖 27.3 新增符号。
- 官方说明「Additional entitlement details will be available soon」，本轮不等待该 entitlement；若后续开放，再单独立项。
- App 保持现有身份：Bundle ID `MeowingCat.MacsyZones`、Team `74FR87HYTH`、手动签名；部署目标维持 27.0。
- 新系统的授权以用户显式操作（在系统设置中开启）为前提，App 只能引导与检测，不能代替用户授权。
- 验证需要真实辅助功能授权与 GUI 操作的部分（首次授权、撤销、升级路径）由人手工执行，其余可用脚本与日志断言。
