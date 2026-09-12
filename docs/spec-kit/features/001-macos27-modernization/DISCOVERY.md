# 业务目标与不作为代价

## 业务目标

将 MacsyZones 定制版全面演进至 macOS 27 专有最新技术基准，彻底消除历史遗留的低版本兼顾包袱，系统性引入上游开源社区经过实证检验的最新修复与增强能力（重点涵盖 PR #79、PR #86、PR #102、PR #104、PR #106、PR #107），解决开机冷启动失灵、辅助功能（AX）观察器时序竞态、布局窗口重复加载与内存过度膨胀、约束重入崩溃等顽疾，使应用在纯净现代 macOS 27 环境下提供稳定、顺畅、轻量（内存 < 30MB）的窗口分区吸附与高级排版体验。

## 不作为代价

- 若不推进适配：在 macOS 27 强化 AppKit 渲染约束周期机制下，应用在窗口拖拽、调整大小或状态变更时将频繁遭遇 `SIGTRAP / EXC_BREAKPOINT` 约束重入崩溃（上游 PR #79 针对性解决的问题）。
- 若不重构 AX 机制：冷启动后 Finder 首拖失灵、跨 Space/显示器吸附失灵等问题将持续困扰用户，必须依赖重复重启或切屏规避（上游 PR #102 针对性解决的问题）。
- 若不清理内存：每次启动创建双倍甚至全量布局 AppKit 窗口树，持续占用 200MB~400MB 物理显存，极大违背桌面工具轻量化原则（上游 PR #104、PR #106、PR #107 针对性解决的问题）。
- 若不加固配置保存：用户在自定义布局中调整或删除分区时，因强制解包可能导致确定性闪退与配置损坏（上游 PR #86 针对性解决的问题）。

# 上游关键 PR 查证与溯源映射

## PR #102：辅助功能时序与跨 Space 恢复机制

- **PR 标识**：Pull Request #102 (`rohanrhu/MacsyZones/pull/102`)
- **分支作者**：Daniel Lavallee (`daniellavallee`)
- **关键 Commit**：`ec28f8f8ee4b570d8af442b32c26d8bd485b7b19`（核心架构与状态机）、`d7ed26ec9d3508f3be9bb785c9feaa7831909b86`（测试环境兜底）
- **核心成因剖析**：
  1. 系统冷启动后，Finder 尚未完全渲染标准应用窗口，MacsyZones 早期对 Finder 的 `AXObserverAddNotification` 调用返回 `kAXErrorCannotComplete`。
  2. 原逻辑由于未对返回值做校验，直接将窗口标记为“已观察”，且永远不再重试。
  3. 当用户首次拖拽 Finder 窗口时，系统无法收到 `kAXWindowMovedNotification`，`isMovingAWindow` 恒为 `false`，导致按住 Shift 毫无反应。
  4. 用户随后“随手打开一次 App 列表（启动台）”之所以能恢复，是因为触发了 `NSWorkspace.didActivateApplicationNotification`，间接刷新了部分前台窗口列表。
  5. 此外，原逻辑中“先按 Shift 后拖拽”与“先拖拽后按 Shift”走完全独立的按键与事件监听分支，时序极其脆弱。
- **引入方案**：
  1. 引入全新纯 Swift 状态机 `DragSessionState.swift`，抹平按键与拖拽先后顺序差异，具备窗口归属锁与物理修饰键独立保留能力。
  2. 重构 `WindowObserverManager`：仅在 `AXObserverAddNotification` 确认返回 `kAXErrorSuccess` 时才入库；针对 `kAXErrorCannotComplete` 实施指数退避重试（+0.2s、+0.5s、+1.0s），最多 3 次。
  3. 在 `didActivateApplicationNotification` 中执行增量对账补查，并同时监听 `kAXWindowMovedNotification` 与 `kAXMovedNotification`。
  4. 在 `Macsy.swift` 的 `onMouseDragged` 中实现全局物理位移兜底：当位移差超过 5pt 且光标下为有效窗口时，主动触发拖拽吸附会话。
  5. 改造遮罩层属性：将所有分区和网格窗口的 `collectionBehavior` 配置为 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`，解决跨 Space 和全屏桌面遮挡问题。
  6. 实现基于显示器 UUID 的独立 Space 解析（`Preferences.swift`），避免跨显示器获取错误 Space 布局。

## PR #79：macOS 27 约束重入崩溃防御

- **PR 标识**：Pull Request #79 (`rohanrhu/MacsyZones/pull/79`)
- **分支作者**：Wylan Swets (`wylanswets`)
- **关键 Commit**：`c66f06ac789ccc72d8c55a7d3eaeff50b54ce586`
- **核心成因剖析**：
  在 macOS 27（Tahoe）强化后的 AppKit 渲染周期中，当窗口正在执行约束更新阶段时，如果在 `NSWindowDelegate`（如 `windowDidResize`、`windowDidMove`）或鼠标悬停监听中直接修改 `@Published` 属性，会导致 SwiftUI 视图树同步刷新并触发 `setNeedsUpdateConstraints:`，进而重入 `-[NSWindow _postWindowNeedsUpdateConstraints]`，系统抛出致命的 `SIGTRAP / EXC_BREAKPOINT` 崩溃。
- **引入方案**：
  1. 为所有固定尺寸或程序化管理的 `NSHostingView`（包括 `ScreenChangeWarningDialog`、`SectionWindow`、`EditorSectionView`、`LayoutWindow.editorBarWindow`、`SnapResizer`、`GridLayoutWindow`）显式设置 `sizingOptions = []`。在 macOS 27 原生环境下直接赋值，移除所有历史宏判断。
  2. 将 `EditorSectionWindowDelegate` 中的 `windowDidResize` 与 `windowDidMove` 内对 `@Published` 的更新统一派发至 `DispatchQueue.main.async`，切入下一个 RunLoop。
  3. 在 `LiquidGlassView.updateNSView()` 中增加当前值比对守卫：`if let currentRadius = nsView.value(forKey: "cornerRadius") as? CGFloat, currentRadius != cornerRadius`，避免无谓的 KVC 属性写入引发重绘。
  4. 在 `Macsy.swift` 的 `getHoveredSectionWindow()` 中，将 `sectionWindow.isHovered` 的修改推迟至 `DispatchQueue.main.async` 且仅在值变化时赋值。

## PR #86：布局安全保存、对齐预设与拖拽吸附增强

- **PR 标识**：Pull Request #86 (`rohanrhu/MacsyZones/pull/86`)
- **分支作者**：Cansın Şenalioğlu (`haylax`)
- **关键 Commit**：
  - `795e46978602dab707b9207176bf8f222943e9c9`（分区安全排序与解包加固）
  - `bb77f61d002c25ec6342ce12b880935b689b97c9`（编辑器尺寸保持对齐工具栏）
  - `fbe6e28aa699b397ba9eb3b4c0afaf83e8c22d5f`（拖拽自动吸附、多区联合吸附与右键粘性取消）
- **引入方案**：
  1. **解包安全加固**：重写 `UserData.swift` 中的 `reArrange()`，将 `$0.number!` 替换为 `($0.number ?? Int.max)` 排序；使用 `guard let sectionWindow = layoutWindow.sectionWindows.first(where: { $0.number == sectionConfig.number }) else { continue }` 替代强制解包，防止保存时崩溃。
  2. **对齐预设工具栏**：在 `Layout.swift` 中引入 `AlignmentPreset` 枚举（`left`、`horizontalCenter`、`right`、`top`、`verticalCenter`、`bottom`），通过 6 个 SF Symbols 按钮（`align.horizontal.*` / `align.vertical.*`）快速对齐分区，严格保持当前分区的自定义宽高不变，仅调整其相对屏幕的原点坐标。
  3. **拖拽体验升级**：
     - 新增配置项：`snapWhileDragging`（拖拽时自动激活吸附网格，无需长按修饰键；此时长按 Shift 反转为临时关闭吸附）、`enableZoneSpanning`（启用多区联合吸附，默认开启）、`spanKey`（联合修饰键，默认 Command）。
     - 在 `Macsy.swift` 中实现 `spannedSectionWindows` 跨区收集与联合外接矩形（Union Bounding Box）吸附计算。
     - 增加 `snapSuppressedForDrag` 标志位，实现粘性右键取消：在一次拖拽中右键取消吸附后，该次拖拽的后续移动中吸附网格保持静默，直到松开鼠标左键重置。
     - 将配置选项汉化并集成至本项目的 `SettingsView.swift`。

## PR #104：消除启动阶段双重布局窗口加载

- **PR 标识**：Pull Request #104 (`rohanrhu/MacsyZones/pull/104`)
- **分支作者**：Chriscoveries (`eafire15`)
- **关键 Commit**：`4af86df75102cacc258dbb1eaa878a6c74ccf533`
- **核心成因剖析**：
  `UserData.init()` 内部已经对全局 `UserLayouts` 实例执行了 `load()`。但在 `App.swift` 的 `applicationDidFinishLaunching` 中，代码再次无条件显式调用了 `userLayouts.load()`。这导致每个已保存布局的 AppKit 窗口图树被重复构造了整整两遍，开机即浪费超过 170MB 物理显存。
- **引入方案**：
  彻底删除 `App.swift` 中启动时的第二处 `userLayouts.load()` 调用。

## PR #106：布局窗口延迟物化（Lazy Materialization）

- **PR 标识**：Pull Request #106 (`rohanrhu/MacsyZones/pull/106`)
- **分支作者**：Chriscoveries (`eafire15`)
- **关键 Commit**：`0fd5d926a8e661251f55867cf40bac717743ed55`、`507e37cd9814526d311164d1638cba2dbbf86c51`、`2570967a66f4591deac55e8e2fc17b75dbeb35d4`、`aac8ad5838af52d3cb844ad48e4bcabe5990a17f`、`c57c6cb7d764df06f7a5a9d744d205297b15d751`、`03f67f19f13b78b85a8c534ba5eab6602bb4b34a`
- **核心成因剖析**：
  以往每个保存的布局在启动或数据加载时，都会预先构建完整的 `LayoutWindow` 及下属数十个 `SectionWindow`。即使用户平时只使用其中一个布局，其余所有布局也永久驻留在 AppKit 窗口层，造成物理内存长期高达 200MB~400MB。
- **引入方案**：
  1. 重构 `UserData.swift` 中的 `UserLayout`：将 `layoutWindow` 改造为惰性物化（Lazy Materialization）属性，区分 `storedLayoutWindow` 与对外暴露的访问器。未使用的布局在内存中仅为极小的数据模型。
  2. 提供 `hasMaterializedLayoutWindow` 与 `materializedLayoutWindow` 安全检查器；在 `Macsy.swift` 执行重置、隐藏（`hide()`）或退出编辑时，先检查是否存在已物化窗口，严禁因为清理操作而反向实例化未激活的布局。
  3. 延迟创建 `ScreenChangeWarningDialog`，仅当真正发生屏幕尺寸不匹配时才实例化。
  4. 冷启动常驻物理内存大幅降低至 20MB~30MB 级别。

## PR #107：QuickSnapper 弹窗生命周期彻底释放

- **PR 标识**：Pull Request #107 (`rohanrhu/MacsyZones/pull/107`)
- **分支作者**：Chriscoveries (`eafire15`)
- **关键 Commit**：`501c92f3cba4b0c561558d051c1faef85d2bcb29`、`69f1019032cf5e30ae16f4e934ee49393e8903f0`
- **核心成因剖析**：
  QuickSnapper 面板在呼出并关闭后，其包含的窗口列表、缩略图视图及 HostingView 未被释放；快速连续呼出和关闭时，旧淡出动画的完成回调会异步篡改新打开面板的状态，甚至引发越界闪退。
- **引入方案**：
  1. 在 `QuickSnapper.swift` 中引入 `lifecycleGeneration` 世代代号（`UInt64`）。
  2. 当面板关闭动画完成后，核对世代代号；若为当前生命周期结束，彻底清空窗口缓存列表并设置 `panel.contentView = nil`，完整解构 HostingView 树。
  3. 快捷键与键盘导航调用全量收拢至 `@MainActor`，并在关闭状态下阻断任何快捷键操作。

## macOS 27 专有基线与环境纯净化

- **升级规范**：在 `MacsyZones.xcodeproj/project.pbxproj` 中将 `MACOSX_DEPLOYMENT_TARGET` 固化为 `27.0`。
- **分支清理**：全面移除代码中所有历史系统可用性检查（如 `#available(macOS 12.0, *)`、`#available(macOS 13.0, *)`、`#available(macOS 26.0, *)`）。
- **接口单一化**：在 `Screen.swift` 中移除旧系统对 `NSScreen.screens.firstIndex(of: screen)` 的降级兜底，原生统一采用 `screen.cgDirectDisplayID` 对应显示器 UUID。

# 参与者与系统权限

## 参与者 (Actors)

- **桌面工作流用户**：使用键盘修饰键（Shift / Option / Command）配合鼠标拖拽进行窗口快速吸附与分屏排版。
- **系统辅助功能（Accessibility）服务**：负责监听窗口创建、位移与销毁事件，并分发至应用。
- **macOS WindowServer / SkyLight**：负责管理物理显示器 UUID、虚拟桌面（Spaces）状态与窗口层级合成。

## 权限与特权边界

- **辅助功能权限（TCC Accessibility）**：应用启动时审计权限状态；使用固定 Apple Development 签名证书与 Bundle ID `MeowingCat.MacsyZones`，避免升级或重启时重复弹窗索权。
- **沙盒边界**：根据 macOS 窗口管理器通用规范，保持无沙盒运行（已在 Xcode 配置），以支持全局跨进程 AXUIElement 操纵。

# 核心用户旅程与 Given/When/Then 骨架

## 核心旅程 1：系统冷启动后 Finder 窗口首拖吸附（Given/When/Then）

- **Given（前提）**：系统刚刚完成冷启动登录，MacsyZones 作为登录项在后台启动，用户桌面刚加载完毕且此前未执行任何切屏或呼出启动台操作。
- **When（操作）**：用户首次打开或点击 Finder 窗口，按住左键拖拽其标题栏并同时按住 Shift 键（或先按住 Shift 再拖拽窗口）。
- **Then（结果）**：
  1. `DragSessionState` 状态机在拖拽或按键发生瞬间完成对齐，不依赖操作顺序。
  2. 若 AX 移动通知正常到达，触发 `onWindowMoved`；若 AX 通知在冷启动期间丢失，鼠标物理位移兜底（`onMouseDragged`）在位移超过 5pt 后立即激活。
  3. 屏幕上平滑淡入当前 Space 关联的分区吸附网格，释放鼠标时光标所在分区高亮并准确贴合吸附。

## 核心旅程 2：跨虚拟桌面（Space）与全屏窗口吸附

- **Given（前提）**：用户在多显示器环境下配置了独立的虚拟桌面偏好（Per-Display Space Layout Preferences）。
- **When（操作）**：用户使用三指滑移或快捷键切换至 Space 2（或全屏应用辅助空间），拖拽某应用程序窗口。
- **Then（结果）**：
  1. `didActivateApplicationNotification` 与 Space 监听器增量刷新当前 Space 下的窗口与显示器 UUID。
  2. 遮罩层以 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` 姿态稳定呈现，永不出现层级丢失或跨屏错位。

## 核心旅程 3：高级分区编辑与跨区联合吸附

- **Given（前提）**：用户在布局编辑器中配置分区，或在桌面拖拽窗口。
- **When（操作）**：
  1. 编辑器场景：用户点击新增的 6 项“对齐预设”按钮（左/中/右/顶/中/底）。
  2. 拖拽场景：用户按住 Command 键并滑动光标经过连续 2 个相邻分区并松开。
- **Then（结果）**：
  1. 编辑器对齐：分区保持自定义宽高不变，原点精准吸附至屏幕边界或中心。
  2. 跨区吸附：系统动态计算 2 个分区的联合外接矩形（Union Bounding Box），窗口平滑嵌入合并后的大区域。

# 输入、输出、归属与生命周期

## 核心数据流与生命周期

- **配置持久化**：用户布局 `UserLayouts.json`、偏好 `SpaceLayoutPreferences.json` 与全局应用设置 `AppSettings.json` 保持格式兼容，存储于 `~/Library/Application Support/MeowingCat.MacsyZones/`。
- **延迟物化生命周期（Lazy Materialization）**：
  - 应用启动时仅加载数据模型，不为所有保存的布局预先创建 NSWindow 物理树。
  - 仅在当前 Space 激活该布局、或进入编辑器时，按需物化（`materializeLayoutWindow`）。
  - 切换离开或关闭弹窗后，注销与置空视图树（`QuickSnapper.panel.contentView = nil`），物理内存占用持续处于 < 30MB 水准。

# 异常、重试、部分失败与恢复机制

## 容错与恢复设计

1. **AX 注册失败重试（Exponential Backoff）**：
   在应用刚启动或目标进程未完全加载时，若 `AXObserverAddNotification` 返回 `kAXErrorCannotComplete`，不标记已观察，分别在 +0.2s、+0.5s、+1.0s 执行指数退避重试，最多 3 次。
2. **物理鼠标位移兜底（Mouse Drag Fallback）**：
   若辅助功能通知彻底被第三方进程阻塞，鼠标拖拽监听器检测到全局坐标连续变化且光标下存在标准窗口时，主动触发拖拽吸附会话。
3. **数据解包防御（No Force Unwrap）**：
   彻底移除 `UserData.reArrange()` 中的强制解包；若分区序号或关联窗口缺失，跳过脏数据并安全继续，永不引发 `SIGTRAP` 致命错误。
4. **约束重入防御（Sizing Options）**：
   为所有程序化尺寸的 `NSHostingView` 设置 `sizingOptions = []`，并在主线程下一 RunLoop（`DispatchQueue.main.async`）派发窗口代理中的 `@Published` 变更，阻断重入异常。

# 安全、隐私、无障碍与平台兼容

## 平台与 SDK 边界（macOS 27 专有）

- **最低部署目标**：`MACOSX_DEPLOYMENT_TARGET = 27.0`。
- **旧系统兼容清理**：彻底删除所有 `#available(macOS 12.0, *)`、`#available(macOS 13.0, *)`、`#available(macOS 26.0, *)` 条件分支，消除分支碎片。
- **原生接口现代对齐**：使用 `NSScreen.cgDirectDisplayID` 与现代 Display UUID 映射；全量迁移至 Swift 6 严格并发与 `@MainActor` 标注。

# 范围与非目标声明

## 包含在范围内的目标（In Scope）

1. 升级工程至 macOS 27 专属部署目标与清理废弃 API。
2. 引入 `DragSessionState` 并重构 `WindowObserverManager`，解决冷启动与按键时序失灵（溯源 PR #102）。
3. 激活 `onMouseDragged` 物理位移兜底（溯源 PR #102）。
4. 修复启动重复加载布局并实现布局窗口按需物化（溯源 PR #104、PR #106）。
5. 修复 QuickSnapper 生命周期内存泄漏与动画世代代号保护（溯源 PR #107）。
6. 修复 `reArrange()` 强制解包崩溃与约束重入防护（溯源 PR #79、PR #86）。
7. 增加分区编辑器尺寸保持对齐按钮 `AlignmentPreset`（溯源 PR #86）。
8. 增加修饰键跨区联合吸附（Zone Spanning）与粘性右键取消（溯源 PR #86）。
9. 遵循版本量化规范判定为 `v2.0.0 / Major`，并验证全自动化打包与签名流程。

## 明确非目标（Out of Scope）

1. 不恢复或重新引入 upstream `Switcher.swift`（Snap w/ Ease 悬浮切换条维持彻底删除）。
2. 不引入任何 `ProLock`、捐赠或商业化弹窗逻辑。
3. 不兼容 macOS 26 及更早版本 macOS。
4. 不修改网络更新器架构（维持当前安全的自建 Release DMG 与 SHA-256 审计体系）。

# 发现项分类总表 (Classified Discovery Inventory)

- `[CONFIRMED_FACT]` 本项目已发布最新版为 v1.2.5，基线来源于上游 v3.0.4（Commit `7940806`）。
- `[CONFIRMED_FACT]` 启动时存在两处 `userLayouts.load()`（第 1 处在 `UserData.init()`，第 2 处在 `App.swift` 第 199 行），导致 AppKit 窗口双倍实例化并浪费 170MB+ 物理内存（PR #104）。
- `[CONFIRMED_FACT]` 冷启动时由于 Finder 窗口尚未就绪，AX 观察器注册静默失败且无重试，导致 `isMovingAWindow` 无法置为 `true`，首次拖拽必定失灵；呼出启动台激活了 `didActivateApplicationNotification` 从而重新对账刷新（PR #102）。
- `[CONFIRMED_FACT]` `UserData.reArrange()` 存在 `$0.number!` 与 `.first(where:)!` 强制解包，增删分区保存时可被确定性触发崩溃（PR #86）。
- `[CONFIRMED_FACT]` macOS 27 在窗口代理修改 `@Published` 属性会引发 `_postWindowNeedsUpdateConstraints` 约束重入崩溃，需通过 `sizingOptions = []` 与异步主线程分发化解（PR #79）。
- `[CONFIRMED_FACT]` 全量预构布局窗口是内存膨胀至数百兆的主因，惰性物化（Lazy Materialization）可将冷启动内存降至 23MB（PR #106）。
- `[CONFIRMED_FACT]` QuickSnapper 关闭后残留 HostingView 与窗口列表，且动画回调缺乏世代代号保护，易产生时序竞态（PR #107）。
- `[USER_DECISION]` 项目规范治理全面采用 GitHub Spec Kit，法定文档语言确定为 zh-CN。
- `[USER_DECISION]` 项目目标直接推进至 macOS 27 专有最新标准，不需要考虑对 macOS 26 及更低版本的向下兼容。
- `[USER_DECISION]` 方案不分阶段，一次性交付完备的稳定、性能、交互升级，版本定级为 v2.0.0 / Major。
- `[OUT_OF_SCOPE]` 上游 v3.0 悬浮切换条（`Switcher.swift`）因严重性能问题与高 CPU 占用继续保持剔除。
- `[OUT_OF_SCOPE]` 商业化授权、捐赠弹窗及多余的多语言翻译拓展。
