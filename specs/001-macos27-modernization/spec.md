# 用户场景与独立验收测试

### 用户旅程 1：系统冷启动后 Finder 窗口首拖吸附（优先级：P1，溯源 PR #102）

用户刚开机登录系统，MacsyZones 随登录项自动在后台运行。用户桌面加载完毕后，首次打开或点击 Finder 窗口，拖拽其标题栏并按住 Shift（或先按住 Shift 再拖拽）。系统必须百分之百立即呈现当前桌面关联的分区吸附网格，并在松开鼠标后将窗口精准吸附到位。

**设定该优先级的理由**：解决困扰用户的冷启动核心功能失灵，此为应用最核心、最高频的场景。

**独立验收测试**：系统冷启动后，在未进行任何应用切换或呼出启动台的前提下，首次拖拽 Finder 窗口并按住 Shift，网格正常出现并吸附成功。

**验收场景**：
1. **Given** 系统完成冷启动登录，MacsyZones 在后台运行且此前未发生任何屏幕切换，**When** 用户首次按住 Finder 窗口标题栏拖动并按下 Shift，**Then** 分区网格无延迟平滑淡入，并在鼠标释放时将窗口调整至目标分区尺寸与坐标。
2. **Given** 用户在点击拖动 Finder 窗口之前已经按下了 Shift 键，**When** 用户开始按住鼠标左键移动窗口，**Then** 拖拽状态机立即响应并显示分区网格，行为与“先拖后按 Shift”完全一致。

### 用户旅程 2：跨虚拟桌面（Space）与多显示器无缝吸附（优先级：P1，溯源 PR #102）

用户在多显示器环境下工作，并在各个屏幕间配置了不同的 Space 独立分区偏好。用户在不同 Space 和不同显示器间切换、移动窗口时，吸附热区与网格准确跟随当前屏幕和桌面，不再产生快捷键失效或误用上一个桌面布局的问题。

**设定该优先级的理由**：多屏幕、多虚拟桌面是 macOS 高级用户的基准工作流，失灵将严重破坏日常操作连续性。

**独立验收测试**：在拥有至少 2 个虚拟桌面或外接显示器的环境下，在各桌面之间连续切换并吸附窗口，验证布局与热区完全正确。

**验收场景**：
1. **Given** 用户拥有主副双显示器并各自配置了不同分区布局，**When** 用户将窗口从主屏幕拖动跨越至副屏幕，**Then** 遮罩网格自动由主屏布局无缝切换为副屏专属布局。
2. **Given** 用户全屏运行某应用辅助空间（Full-Screen Auxiliary Space），**When** 用户在全屏空间内触发吸附，**Then** 遮罩网格以全屏辅助层级正常显示，不发生遮挡。

### 用户旅程 3：超轻量常驻与按需窗口物化（优先级：P1，溯源 PR #104、PR #106、PR #107）

MacsyZones 在后台长期常驻运行，仅当用户实际呼出吸附网格、切换布局或进入布局编辑器时才物化创建 AppKit 物理窗口图形树；未激活的布局仅在内存中保存纯数据结构，应用启动与常驻内存严格维持在 20MB~30MB 区间。

**设定该优先级的理由**：作为常驻工具类 App，占用数百兆物理内存无法接受。

**独立验收测试**：通过活动监视器或 `vmmap` 监测冷启动与长期运行内存，验证启动不重复加载且常驻物理占用低于 30MB。

**验收场景**：
1. **Given** 用户配置了 8 个以上复杂布局（包含数十个分区），**When** 应用冷启动后进入常驻状态，**Then** 仅活跃布局在按需使用时创建物理窗口，冷启动物理内存低于 30MB。
2. **Given** 用户打开 QuickSnapper 选区面板后关闭，**When** 关闭动画完成，**Then** 窗口列表缓存被清空，HostingView 被完全释放解构。

### 用户旅程 4：分区编辑器对齐预设与高级吸附交互（优先级：P2，溯源 PR #86）

用户在布局编辑器中可以通过 6 个对齐预设按钮在不改变当前分区自定义宽高的情况下，快速将分区对齐至屏幕边缘或居中；在桌面拖拽窗口时，支持拖拽自动吸附、多区联合吸附以及粘性右键取消。

**设定该优先级的理由**：极大提升高级用户定制分区和排版的灵活性。

**独立验收测试**：在编辑器中点击对齐按钮验证尺寸保持不变仅原点平移；在桌面按住 Command 划过多区验证多区合并吸附；右键点击验证粘性取消。

**验收场景**：
1. **Given** 用户自定义了一个宽 400 高 300 的分区，**When** 用户点击“左对齐”与“垂直居中”按钮，**Then** 分区保持 400x300 尺寸，仅坐标紧贴屏幕左侧并垂直居中。
2. **Given** 用户拖拽窗口时按住 Command 修饰键滑过连续两个相邻分区，**When** 松开鼠标左键，**Then** 窗口被调整至涵盖这两个分区并集的外接矩形大小。
3. **Given** 用户正在拖拽窗口并显示吸附网格，**When** 用户右键点击取消吸附，**Then** 吸附网格隐藏，且在本次拖拽鼠标未松开前，后续鼠标移动均不会重新激活动画。

### 用户旅程 5：macOS 27 约束重入零闪退体验（优先级：P1，溯源 PR #79）

在 macOS 27 环境下，用户高频快速调整窗口尺寸、移动窗口或悬停分区时，UI 渲染流畅自然，绝不发生 `SIGTRAP / EXC_BREAKPOINT` 崩溃。

**设定该优先级的理由**：保证应用在 macOS 27 最新系统上的基本可用性与绝对稳定性。

**独立验收测试**：在 macOS 27 下连续快速拖拽缩放窗口 100 次，验证无任何异常退出或 AppKit 崩溃日志。

**验收场景**：
1. **Given** 用户正在频繁调整分区窗口尺寸，**When** AppKit 触发 `windowDidResize` 与约束更新，**Then** `@Published` 属性变更在下一 RunLoop 异步生效，窗口平滑重绘且无重入异常。

### 用户旅程 6：文档同步、Git 推送与 GitHub Release 发布（优先级：P1）

用户或开发者在完成全部代码实现与验证后，需要获得更新完毕的项目说明文档，将经过测试的代码与规范资产提交推送到 GitHub 远端仓库（`origin custom`），并通过自动化构建工具打出正式签名的 Release DMG 安装包，利用 `gh` CLI 发布正式 GitHub Release（Tag: `v2.0.0`），最后将版本台账更新归档。

**设定该优先级的理由**：交付闭环是软件工程完整生命周期不可或缺的核心部分，未经打包发布、文档同步与远端推送的工程不能算作交付完成。

**独立验收测试**：执行文档更新、`git push` 推送至 `jiezhengj/MacsyZones`，通过 `scripts/build-release-dmg.sh` 在 `/tmp` 产生通过签名审计的 DMG，通过 `gh release create` 与 `gh release upload` 创建 Release 并上传，最后在 `RELEASES.md` 中将状态由“计划中”更新为“已发布”并推送。

**验收场景**：
1. **Given** 全部代码与验证完成，**When** 执行文档同步更新与提交推送，**Then** `README.md` 准确说明 macOS 27 特性与新能力，远端 `custom` 分支与本地完全同步。
2. **Given** 触发 Release 构建脚本，**When** 执行 `scripts/build-release-dmg.sh 2.0.0 major`，**Then** `/tmp` 下成功生成 `MacsyZones-v2.0.0.dmg` 且通过 `hdiutil verify` 与签名审计。
3. **Given** 准备发布，**When** 调用 `gh release create` 与 `gh release upload`，**Then** GitHub 远端生成标题为 `MacsyZones 中文定制版 v2.0.0` 的 Release，DMG 资产可供下载，本地临时 DMG 被及时清理。
4. **Given** GitHub Release 创建成功，**When** 更新 `RELEASES.md`，**Then** “当前已发布版本”变为 `v2.0.0`，状态变为“已发布”，并推送至远端。

### 边界与异常情况 (Edge Cases)

- **慢启动进程**：某个刚启动的应用其主窗口创建耗时超过 1 秒，系统的辅助功能服务在进程启动初期的注册可能失败（返回 `kAXErrorCannotComplete`），系统通过指数退避重试（+0.2s, +0.5s, +1.0s）持续追踪，确保首个窗口出现时立即被观察（PR #102）。
- **辅助功能通知完全丢失**：若某第三方非标应用（如特殊自绘引擎）在拖拽时不发出任何 `kAXWindowMovedNotification`，物理鼠标位移兜底逻辑在检测到鼠标拖拽位移大于 5pt 时自动介入，确保吸附不失效（PR #102）。
- **脏数据与异常保存**：当分区配置文件与实际活跃视图列表出现数量不一致或分区序号缺失时，`reArrange()` 必须安全容错，严禁执行强制解包导致应用崩溃（PR #86）。
- **频繁连击快捷键**：快速连续按下/松开 QuickSnapper 或吸附快捷键时，通过世代代号（`lifecycleGeneration`）确保过期的淡出动画不会覆盖新打开的面板（PR #107）。

# 详细系统能力与需求规范

### 功能需求 (Functional Requirements)

- **FR-001**：系统必须将最低部署版本（Deployment Target）明确指定为 `macOS 27.0`，彻底剥离项目内全部历史系统条件分支（如 `#available(macOS 12.0, *)`、`#available(macOS 13.0, *)`、`#available(macOS 26.0, *)`），并移除 `Screen.swift` 中对 `NSScreen.screens.firstIndex(of: screen)` 的历史降级。
- **FR-002**：系统必须引入统一的拖拽会话状态机 `DragSessionState`（溯源 PR #102），抹平按键发生先后顺序（先 Shift 后拖 vs 先拖后 Shift）的时序差异，并具备独立保留键盘物理修饰键状态的能力。
- **FR-003**：系统必须在 `WindowObserverManager` 中实现 AX 注册验证与重试机制（溯源 PR #102），仅在 `AXObserverAddNotification` 返回 `kAXErrorSuccess` 时才记录为已观察；返回 `kAXErrorCannotComplete` 时执行 3 次指数退避重试（+0.2s、+0.5s、+1.0s）。
- **FR-004**：系统必须在前台应用激活通知（`didActivateApplicationNotification`）中对获得焦点的应用窗口进行增量对账补查（溯源 PR #102），并同时监听 `kAXWindowMovedNotification` 与 `kAXMovedNotification`。
- **FR-005**：系统必须在 `onMouseDragged` 中实现全局鼠标物理位移兜底（溯源 PR #102），当辅助功能移动通知延迟或丢失时，位移超过 5pt 且光标下为标准窗口时主动驱动 `DragSessionState` 触发吸附。
- **FR-006**：系统必须移除 `App.swift:applicationDidFinishLaunching` 中多余的第二处 `userLayouts.load()` 调用（溯源 PR #104），消除启动时的双重窗口对象创建。
- **FR-007**：系统必须将 `UserLayout.layoutWindow` 重构为惰性物化（Lazy Materialization，溯源 PR #106），仅在需要显示或编辑该布局时才创建 AppKit 物理窗口图，且在 `Macsy.swift` 重置或隐藏时检查 `hasMaterializedLayoutWindow`，严禁逆向实例化未激活布局。
- **FR-008**：系统必须在 QuickSnapper 关闭时清空窗口列表并置空其 HostingView，同时引入 `lifecycleGeneration` 世代代号防止时序竞态，快捷键操作收拢至 `@MainActor`（溯源 PR #107）。
- **FR-009**：系统必须消除 `UserData.reArrange()` 中所有的强制解包操作（溯源 PR #86），使用 `($0.number ?? Int.max)` 排序与 `guard let` 遍历，确保在任何配置不一致情况下保存不崩溃。
- **FR-010**：系统必须为所有固定或程序化尺寸的 `NSHostingView` 显式声明 `sizingOptions = []`，并将窗口代理中的 `@Published` 属性变更派发至 `DispatchQueue.main.async`（溯源 PR #79），彻底防止 AppKit 约束重入崩溃。
- **FR-011**：系统必须在 `LiquidGlassView.updateNSView()` 中增加当前属性值比对守卫（溯源 PR #79），避免无谓的 KVC 属性写入引发视图重绘。
- **FR-012**：系统必须在分区编辑器中提供 6 项对齐预设（`AlignmentPreset`，溯源 PR #86），在不改变自定义尺寸的前提下重新定位坐标，并以 SF Symbols 按钮展示。
- **FR-013**：系统必须支持拖拽自动吸附（`snapWhileDragging`）、按住扩展键多分区联合吸附（`enableZoneSpanning` / `spanKey`，默认 Command）以及粘性右键取消（`snapSuppressedForDrag`）（溯源 PR #86），并在 `SettingsView.swift` 中提供中文配置界面。
- **FR-014**：系统在退出时必须完整清理并移除所有全局鼠标、键盘监听器（NSEvent Global Monitors）及 AX RunLoop Sources（溯源 PR #102）。
- **FR-015**：系统必须同步更新项目面向用户的说明文档 `README.md`，清晰陈述最低支持系统为 macOS 27、冷启动拖拽修复机制、分区对齐工具栏、拖拽自动吸附以及多区联合吸附等核心功能。
- **FR-016**：系统所有版本提交与 Git 分支推送必须且仅能推送到本项目自己的远端仓库 `jiezhengj/MacsyZones` 的 `custom` 分支，严格禁止向上游仓库推送任何代码或创建 Pull Request。
- **FR-017**：系统在发布时必须调用 `scripts/build-release-dmg.sh 2.0.0 major`，在 `/tmp` 目录下生成正式签名审计通过的 DMG 安装包（`MacsyZones-v2.0.0.dmg`），并通过 `hdiutil verify` 校验，严禁将 DMG 纳入 Git 或存放在工程目录内。
- **FR-018**：系统在创建 GitHub Release 时必须统一使用 `gh` CLI 工具及其子命令（严格禁止通过浏览器或第三方 HTTP 客户端操作），标题格式为 `MacsyZones 中文定制版 v2.0.0`，严格遵循项目规定的 Release Notes 模板，上传 DMG 资产并校验，上传后立即删除本地临时 DMG，最后将 `RELEASES.md` 中的版本状态更新为“已发布”并推送。

### 核心实体模型 (Key Entities)

- **DragSessionState**：管理全局拖拽与修饰键按下状态的纯 Swift 状态机模型，包含 `idle`、`candidate(windowID, mousePos)`、`active(windowID, target)` 等互斥状态，不依赖外部 AppKit 环境。
- **UserLayout**：分区或网格布局的核心模型，持有一套配置数据与可选物化的 `storedLayoutWindow`，提供 `hasMaterializedLayoutWindow` 检查器。
- **AlignmentPreset**：定义左、水平居中、右、顶、垂直居中、底 6 种对齐策略的枚举类型。

# 可度量验收准则 (Success Criteria)

### 可度量指标 (Measurable Outcomes)

- **SC-001（冷启动可靠性）**：系统冷启动登录后，首次拖拽 Finder 窗口触发 Shift 吸附的成功率达到 100%，无需预先切换 Space 或呼出 Launchpad。
- **SC-002（时序一致性）**：“先按 Shift 再拖拽”与“先拖拽再按 Shift”两种操作路径的吸附触发成功率达到 100%。
- **SC-003（轻量内存常驻）**：在保存 5 个以上布局的环境下，应用冷启动后的常驻物理内存（Resident Memory）严格控制在 30MB 以内。
- **SC-004（零重入闪退）**：在 macOS 27 环境下进行高频连续窗口调整、拖拽与多屏移动测试，不发生 `SIGTRAP / EXC_BREAKPOINT` 崩溃。
- **SC-005（配置保存健壮性）**：在布局编辑器中连续增删分区 50 次并保存，无任何未捕获异常或闪退。
- **SC-006（跨区联合吸附）**：拖拽窗口并按住 Command 键划过多个分区时，联合外接矩形吸附准确率达到 100%。
- **SC-007（纯净构建与签名）**：通过 `scripts/check-version.sh 2.0.0 major` 门禁，Debug 与 Release 构建及签名审计全部一次性通过。
- **SC-008（全流程交付与发布闭环）**：GitHub 远端仓库 `jiezhengj/MacsyZones` 的 `custom` 分支与 `v2.0.0` tag 成功推送，GitHub Release 页面资产正常可下载，`RELEASES.md` 版本台账更新为“已发布”并完成推送。

# 实施假设与环境基准 (Assumptions)

- 运行环境为配备 Apple Silicon 芯片的 macOS 27（Tahoe）及以上系统。
- 编译工具链采用 Xcode 27 原生 SDK，支持 Swift 6.0 强并发模式。
- 代码签名固定使用本项目的 Apple Development 证书（Team ID: `74FR87HYTH`，Bundle ID: `MeowingCat.MacsyZones`）。
- 维持不向上游推送、仅推送到本项目 GitHub 仓库（`jiezhengj/MacsyZones`）的代码治理边界。
- 上游代码复用优先：严格采用来自 PR #79、PR #86、PR #102、PR #104、PR #106、PR #107 的成熟逻辑与数据模型。
