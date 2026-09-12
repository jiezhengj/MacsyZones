# 架构方案概述

本实施方案将 MacsyZones 全面推进至 **macOS 27 专有最新技术基准**，彻底剥离历史系统兼顾包袱，深度集成上游开源社区成熟的 6 个关键 PR（PR #79、PR #86、PR #102、PR #104、PR #106、PR #107），系统性解决开机冷启动首拖失灵、AX 观察器注册竞态、布局窗口全量实例化造成的内存膨胀，以及约束重入崩溃等核心缺陷。

改动涉及底层平台基线升级、AX 窗口观察引擎与拖拽状态机重写、窗口图形树按需懒加载、数据解包防御以及高级吸附交互增强。根据项目量化规则，本次发布定级为 **`v2.0.0 / Major`**。

# 技术上下文与环境基准

- **开发与部署环境**：macOS 27.0+（Tahoe），使用 Xcode 27 原生 SDK。
- **开发语言与并发模型**：Swift 6.0，严格并发检查（Strict Concurrency Checking），UI 线程全量 `@MainActor` 隔离。
- **底层依赖框架**：AppKit、SwiftUI、ApplicationServices (AXUIElement / HIServices / SkyLight)。
- **构建与签名策略**：固定使用 Team ID `74FR87HYTH`，Bundle ID `MeowingCat.MacsyZones`，发布前通过 `scripts/check-version.sh 2.0.0 major` 门禁。
- **性能与内存目标**：冷启动与常驻物理内存稳定处于 20MB~30MB 区间，冷启动首拖 Finder 唤起吸附网格成功率 100%。

# 上游 PR 深度技术映射与复用策略

## 1. PR #102：辅助功能时序平滑与跨 Space 健壮性（作者：daniellavallee）

- **对应 Commit**：`ec28f8f8ee4b570d8af442b32c26d8bd485b7b19`、`d7ed26ec9d3508f3be9bb785c9feaa7831909b86`
- **复用目标 1（拖拽状态机）**：新增 `MacsyZones/DragSessionState.swift`，使用纯 Swift 实现确定的状态迁移，管理 `idle`、`candidate(windowID, mousePos)`、`active(windowID, target)` 状态，消除“先按 Shift 后拖拽”与“先拖拽后按 Shift”的时序偶合。
- **复用目标 2（AX 注册重试机制）**：重构 `App.swift` 中的 `WindowObserverManager`。仅在 `AXObserverAddNotification` 返回 `kAXErrorSuccess` 时才向内部字典添加窗口；对 `kAXErrorCannotComplete` 执行指数退避重试（+0.2s、+0.5s、+1.0s）；同时监听 `kAXWindowMovedNotification` 与 `kAXMovedNotification`。
- **复用目标 3（前台应用激活补账）**：在 `App.swift` 中监听 `NSWorkspace.didActivateApplicationNotification`，当前台应用切换（如用户点击 Finder）时，主动对该应用的窗口进行增量对账补查。
- **复用目标 4（物理位移兜底）**：在 `Macsy.swift` 中完善 `onMouseDragged` 回调，当 AX 事件丢失时，通过检测鼠标移动差（> 5pt）且光标下为有效标准窗口，保底激活 `DragSessionState`。
- **复用目标 5（遮罩层跨 Space 属性）**：在 `Macsy.swift` 与 `Layout.swift` 中，将所有分区和网格窗口的 `collectionBehavior` 配置为 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`。
- **复用目标 6（多显示器 Space 解析）**：在 `Preferences.swift` 中根据当前获得焦点显示器的 UUID 读取对应 Space，取代单一全局 Space 解析。

## 2. PR #79：macOS 27 AppKit 约束重入崩溃防御（作者：wylanswets）

- **对应 Commit**：`c66f06ac789ccc72d8c55a7d3eaeff50b54ce586`
- **复用目标 1（NSHostingView 尺寸声明）**：在 `Layout.swift` 中，为 `ScreenChangeWarningDialog`、`SectionWindow`、`EditorSectionView`、`LayoutWindow.editorBarWindow`、`SnapResizer`、`GridLayoutWindow` 等所有固定或程序化尺寸的窗口 contentViews 设置 `sizingOptions = []`。
- **复用目标 2（代理状态异步派发）**：在 `Layout.swift` 的 `EditorSectionWindowDelegate` 中，将 `windowDidResize` 与 `windowDidMove` 对 `sectionWindow?.windowSize` 与 `layoutWindow?.refreshEditorBarState()` 的 `@Published` 修改包装在 `DispatchQueue.main.async` 中。
- **复用目标 3（LiquidGlassView 守卫）**：在 `LiquidGlass.swift` 的 `updateNSView()` 中，先读取 `nsView.value(forKey: "cornerRadius") as? CGFloat`，仅在值不相等时才执行 `setValue(cornerRadius, forKey: "cornerRadius")`。
- **复用目标 4（悬停状态异步派发）**：在 `Macsy.swift` 的 `getHoveredSectionWindow()` 中，将 `sectionWindow.isHovered` 的修改推迟至 `DispatchQueue.main.async` 并加入新旧值判断。

## 3. PR #86：布局安全保存、对齐工具栏与拖拽吸附增强（作者：haylax）

- **对应 Commit**：`795e46978602dab707b9207176bf8f222943e9c9`、`bb77f61d002c25ec6342ce12b880935b689b97c9`、`fbe6e28aa699b397ba9eb3b4c0afaf83e8c22d5f`
- **复用目标 1（解包安全防崩溃）**：在 `UserData.swift` 的 `reArrange()` 中，将强制解包彻底替换为 `($0.number ?? Int.max)` 排序，并用 `guard let sectionWindow = layoutWindow.sectionWindows.first(...) else { continue }` 忽略无效分区。
- **复用目标 2（对齐预设按钮）**：在 `Layout.swift` 中引入 `AlignmentPreset` 枚举与 `AlignmentButton` 视图（使用 6 个 SF Symbols：`align.horizontal.left`、`align.horizontal.center`、`align.horizontal.right`、`align.vertical.top`、`align.vertical.center`、`align.vertical.bottom`），在 `EditorSectionView` 插入对齐工具栏，保持当前分区宽高不变仅调整原点。
- **复用目标 3（拖拽增强与多区联合）**：在 `Settings.swift` 与 `SettingsView.swift` 中添加 `snapWhileDragging`（拖拽自动吸附）、`enableZoneSpanning`（多区联合吸附）、`spanKey`（联合键）的配置与中文 UI；在 `Macsy.swift` 中维护 `spannedSectionWindows` 并计算联合矩形吸附；增加 `snapSuppressedForDrag` 实现右键粘性取消。

## 4. PR #104：消除启动双重布局加载（作者：eafire15）

- **对应 Commit**：`4af86df75102cacc258dbb1eaa878a6c74ccf533`
- **复用目标**：删除 `App.swift` 中 `applicationDidFinishLaunching` 内多余的 `userLayouts.load()`（位于第 199 行附近），避免已在 `UserData.init()` 中加载的布局窗口再次被全量实例化。

## 5. PR #106：布局窗口惰性物化（作者：eafire15）

- **对应 Commit**：`0fd5d926a8e661251f55867cf40bac717743ed55`、`507e37cd9814526d311164d1638cba2dbbf86c51`、`2570967a66f4591deac55e8e2fc17b75dbeb35d4`、`aac8ad5838af52d3cb844ad48e4bcabe5990a17f`、`c57c6cb7d764df06f7a5a9d744d205297b15d751`
- **复用目标 1（按需物化数据模型）**：重构 `UserData.swift` 中的 `UserLayout`，内部采用 `private var storedLayoutWindow: LayoutWindow?`，对外提供 `var layoutWindow: LayoutWindow`（按需创建并缓存）、`var hasMaterializedLayoutWindow: Bool` 以及 `var materializedLayoutWindow: LayoutWindow?`。
- **复用目标 2（安全隐藏与重置）**：在 `Macsy.swift` 中的重置、隐藏（`hide()`）与退出编辑操作中，使用 `hasMaterializedLayoutWindow` 守卫，避免因调用隐藏而反向触发创建未激活布局的物理窗口。
- **复用目标 3（按需创建警告窗口）**：在 `Layout.swift` 中将 `ScreenChangeWarningDialog` 的构造延迟至真正发生屏幕尺寸变化时。

## 6. PR #107：QuickSnapper 面板资源彻底解构（作者：eafire15）

- **对应 Commit**：`501c92f3cba4b0c561558d051c1faef85d2bcb29`、`69f1019032cf5e30ae16f4e934ee49393e8903f0`
- **复用目标 1（资源清空与置空）**：在 `QuickSnapper.swift` 的关闭淡出回调完成后，清空 `windows = []` 并执行 `panel.contentView = nil`，彻底销毁 AppKit 物理视图层级。
- **复用目标 2（世代代号防竞态）**：引入 `lifecycleGeneration: UInt64`，每次呼出和关闭时自增，确保延迟动画或异步快捷键回调不会作用于新开启的面板。
- **复用目标 3（主线程调度）**：所有面板状态、热键及选择操作统一声明在 `@MainActor` 下。

## 7. macOS 27 专有基线升级

- 在 `MacsyZones.xcodeproj/project.pbxproj` 中统一设置 `MACOSX_DEPLOYMENT_TARGET = 27.0`。
- 全量清理所有 `#available(macOS 12.0, *)`、`#available(macOS 13.0, *)`、`#available(macOS 26.0, *)` 等可用性条件宏。
- 在 `Screen.swift` 中移除旧系统对 `NSScreen.screens.firstIndex(of: screen)` 的回退代码，统一使用 `screen.cgDirectDisplayID` 与屏幕 UUID。

# 项目文件结构与修改范围

### 新增文件

- `MacsyZones/DragSessionState.swift`：管理拖拽与按键顺序的纯 Swift 状态机（溯源 PR #102）。
- `tests/DragSessionStateTests.swift`：针对状态机的独立纯 Swift 单元测试（溯源 PR #102）。

### 修改文件

- `MacsyZones.xcodeproj/project.pbxproj`：升级至 `27.0`，注册 `DragSessionState.swift` 源码引用。
- `MacsyZones/App.swift`：删除第 199 行冗余 `userLayouts.load()`（PR #104）；重构 `WindowObserverManager` 支持注册成功校验与指数退避重试（PR #102）；接入 `didActivateApplicationNotification`（PR #102）；清理退出事件监听器（PR #102）；接入拖拽设置（PR #86）。
- `MacsyZones/Macsy.swift`：实现 `onMouseDragged` 物理位移兜底（PR #102）；接入 `DragSessionState`；窗口遮罩属性添加 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`（PR #102）；接入多区联合吸附与粘性右键取消（PR #86）；防约束重入异步更新悬停状态（PR #79）；惰性物化判断守卫（PR #106）。
- `MacsyZones/UserData.swift`：实现 `UserLayout` 惰性物化 `storedLayoutWindow`（PR #106）；重构 `reArrange()` 消除强制解包（PR #86）。
- `MacsyZones/Layout.swift`：为所有 `NSHostingView` 声明 `sizingOptions = []`（PR #79）；代理事件异步调度（PR #79）；添加 `AlignmentPreset` 与 6 个对齐按钮（PR #86）；按需实例化警告框（PR #106）。
- `MacsyZones/LiquidGlass.swift`：防无谓 KVC 属性写入守卫（PR #79）。
- `MacsyZones/QuickSnapper.swift`：关闭时清空列表并置空 `contentView`，引入 `lifecycleGeneration` 保护与 `@MainActor` 约束（PR #107）。
- `MacsyZones/Settings.swift`：添加 `snapWhileDragging`、`enableZoneSpanning`、`spanKey` 字段与持久化（PR #86）。
- `MacsyZones/SettingsView.swift`：新增拖拽自动吸附、多区联合吸附及修饰键设置项的中文 UI（PR #86）。
- `MacsyZones/Screen.swift`：移除旧系统条件判断与屏幕索引查找，使用 `cgDirectDisplayID`（macOS 27 专有）。
- `MacsyZones/Preferences.swift`：实现基于显示器 UUID 的独立 Space 偏好解析（PR #102）。
- `README.md`：更新版本说明、macOS 27 最低要求、新功能（冷启动修复、对齐工具栏、自动/联合吸附）。
- `RELEASES.md`：登记并发布 `v2.0.0 / Major`，维护版本台账与已发布历史。

# 实施步骤与依赖顺序

### 第 1 阶段：工程配置与 macOS 27 专有基线

1. 更新 `project.pbxproj` 中的 `MACOSX_DEPLOYMENT_TARGET` 为 `27.0`。
2. 全局排查并删除所有 `#available(macOS 12.0, *)`、`#available(macOS 13.0, *)`、`#available(macOS 26.0, *)` 等可用性宏分支。
3. 清理 `Screen.swift` 中的降级索引逻辑，固化使用 `cgDirectDisplayID`。

### 第 2 阶段：拖拽状态机与冷启动 AX 观察引擎重构（PR #102）

1. 编写 `MacsyZones/DragSessionState.swift` 并添加单元逻辑覆盖。
2. 重构 `WindowObserverManager`：严格返回值校验、指数退避重试机制、前台应用激活补账机制。
3. 激活 `Macsy.swift` 中的 `onMouseDragged` 物理位移兜底。
4. 全面联调消除“先 Shift 后拖”与“先拖后 Shift”时序差异。
5. 配置遮罩层 `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` 与多显示器 Space 解析。

### 第 3 阶段：内存压缩与按需物化重构（PR #104、PR #106、PR #107）

1. 删除 `App.swift:applicationDidFinishLaunching` 中冗余的 `userLayouts.load()`。
2. 重构 `UserData.swift` 中的 `UserLayout`，实现 `materializeLayoutWindow` 按需懒加载，并暴露 `hasMaterializedLayoutWindow`。
3. 在 `Macsy.swift` 中守卫隐藏与重置逻辑，防止意外触发物化。
4. 重构 `QuickSnapper.swift`：关闭时清空列表、置空 HostingView、接入 `lifecycleGeneration` 并全量收拢至 `@MainActor`。

### 第 4 阶段：系统健壮性与防崩溃加固（PR #79、PR #86）

1. 重构 `UserData.swift:reArrange()`，使用安全解包防崩溃。
2. 为所有非自适应 `NSHostingView` 配置 `sizingOptions = []`。
3. 将窗口代理中的 `@Published` 属性写入派发至 `DispatchQueue.main.async`。
4. 在 `LiquidGlassView.updateNSView()` 中增加当前值相等性守卫。
5. 在 `applicationWillTerminate` 中清理所有全局鼠标/键盘监听器。

### 第 5 阶段：高级交互与排版扩展（PR #86）

1. 在 `Layout.swift` 中实现 `AlignmentPreset` 枚举并在分区编辑栏注入 6 个 SF Symbols 对齐按钮。
2. 在 `Settings.swift` 与 `SettingsView.swift` 中增加吸附设置选项。
3. 在 `Macsy.swift` 中实现按住 Command 跨区多选合并吸附逻辑与粘性右键取消。

### 第 6 阶段：版本审计与自动化构建验证

1. 在 `RELEASES.md` 中登记 `v2.0.0 / Major` 发布目标。
2. 执行 `scripts/check-version.sh 2.0.0 major` 校验版本号与级别。
3. 执行 `scripts/build-debug.sh` 进行编译与正式签名审计。

### 第 7 阶段：文档更新、Git 推送与 GitHub Release 发布

1. 同步更新面向用户的说明文档 `README.md`，反映 macOS 27 特性与新能力。
2. 将全部代码与文档变更提交并推送到 GitHub 远端仓库（`origin custom`）。
3. 运行 `scripts/build-release-dmg.sh 2.0.0 major` 构建正式签名的 Release DMG，并在 `/tmp` 中验证 DMG 完整性与挂载状态。
4. 创建 Git Tag `v2.0.0` 并推送到 `origin v2.0.0`。
5. 使用 `gh release create` 创建标题为 `MacsyZones 中文定制版 v2.0.0` 的 Release，使用 `gh release upload` 上传 DMG 资产。
6. 上传完成后立即删除 `/tmp` 中的 DMG 文件。
7. 更新 `RELEASES.md` 中的版本状态为“已发布”，并将“当前已发布版本”更新为 `v2.0.0`，提交并推送 `RELEASES.md`。

# 验收验证计划

### 自动化验证命令

```bash
# 1. 版本一致性与级别门禁审计
scripts/check-version.sh 2.0.0 major

# 2. Debug 构建与本地签名审计
scripts/build-debug.sh

# 3. Release DMG 打包构建与挂载校验
scripts/build-release-dmg.sh 2.0.0 major

# 4. GitHub Release 资产与状态校验
gh release view v2.0.0 --repo jiezhengj/MacsyZones
```

### 核心交互人工复核清单

1. **冷启动首拖验证**：系统重启开机后，在未呼出 Launchpad 的前提下，直接拖动 Finder 窗口按住 Shift，验证网格是否无延迟平滑弹出（验证 PR #102）。
2. **时序等价性验证**：分别测试“先按住 Shift 再拖动窗口”与“先拖动窗口再按住 Shift”，验证吸附触发行为完全一致（验证 PR #102）。
3. **内存占用基准测试**：使用活动监视器确认应用启动常驻物理内存低于 30MB（验证 PR #104、PR #106、PR #107）。
4. **macOS 27 约束重入审计**：快速拖动调整各窗口尺寸，控制台确认无 `SIGTRAP / EXC_BREAKPOINT` 崩溃（验证 PR #79）。
5. **分区对齐与跨区吸附验证**：在分区编辑器中使用对齐按钮确认尺寸不变仅原点平移；拖拽时按 Command 测试跨区合并吸附（验证 PR #86）。
