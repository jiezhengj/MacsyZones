# 任务清单与执行规范

本文档为 `001-macos27-modernization` 特性的自包含任务包。每个任务均具备完整的上下文、严格的文件边界、明确的代码实现指导与可执行的验证检查，可供无会话上下文的执行器独立执行。

# 阶段 1：工程基线与平台 SDK 现代化

### 任务 T001：升级工程部署目标至 macOS 27.0 并注册新文件引用

- [ ] T001 升级工程部署目标至 macOS 27.0 并注册新文件引用

- **单项可观察目标**：在 Xcode 工程文件 `MacsyZones.xcodeproj/project.pbxproj` 中将所有编译配置的 `MACOSX_DEPLOYMENT_TARGET` 统一设置为 `27.0`，并在工程中正确注册新增源码文件 `MacsyZones/DragSessionState.swift`。
- **溯源关联**：FR-001、SC-007、Upstream macOS 27 Baseline。
- **上下文概要**：MacsyZones 推进至 macOS 27 专有标准，需要提升底层 Deployment Target，同时为即将引入的状态机文件预留 PBX 引用。
- **前置条件**：工作目录位于 Git 仓库根目录，分支为 `custom`。
- **允许修改的文件**：
  - `MacsyZones.xcodeproj/project.pbxproj`
- **只读参考文件**：
  - `specs/001-macos27-modernization/plan.md`
- **禁止的变更**：
  - 禁止更改 `PRODUCT_BUNDLE_IDENTIFIER = MeowingCat.MacsyZones`。
  - 禁止更改 `DEVELOPMENT_TEAM = 74FR87HYTH`。
  - 禁止更改 `CODE_SIGN_IDENTITY = "Apple Development"`。
- **输入与输出**：
  - 输入：现有的 Xcode 工程文件。
  - 输出：`MACOSX_DEPLOYMENT_TARGET = 27.0` 的工程配置，包含 `DragSessionState.swift` 的 PBXBuildFile 与 PBXFileReference。
- **不变量与边界条件**：
  - 必须确保 Debug 和 Release 两种配置的 Deployment Target 保持一致。
- **有序实现要求**：
  1. 使用正则将 `project.pbxproj` 中所有 `MACOSX_DEPLOYMENT_TARGET = 11.0;`、`MACOSX_DEPLOYMENT_TARGET = 12.0;` 等行替换为 `MACOSX_DEPLOYMENT_TARGET = 27.0;`。
  2. 生成唯一的 24 位十六进制 ID，分别在 `PBXBuildFile`、`PBXFileReference`、`PBXGroup (MacsyZones)` 与 `PBXSourcesBuildPhase` 中加入 `DragSessionState.swift`。
- **可执行验证检查**：
  - 执行命令：`grep "MACOSX_DEPLOYMENT_TARGET" MacsyZones.xcodeproj/project.pbxproj | sort -u`
  - 预期结果：仅输出 `MACOSX_DEPLOYMENT_TARGET = 27.0;`。
- **完成证据**：`project.pbxproj` 包含 `MACOSX_DEPLOYMENT_TARGET = 27.0;` 且包含 `DragSessionState.swift` 引用。
- **停止条件**：若修改后 `xcodebuild -list` 报错或解析失败，立即停止并恢复。
- **交接说明**：T001 完成后，工程已准备好接受 Swift 6 / macOS 27 专有代码。

### 任务 T002：消除历史系统可用性宏分支与屏幕索引降级

- [ ] T002 消除历史系统可用性宏分支与屏幕索引降级

- **单项可观察目标**：彻底删除 `Screen.swift`、`Preferences.swift` 与 `Settings.swift` 中所有的历史可用性宏（如 `#available(macOS 12.0, *)`、`#available(macOS 13.0, *)`、`#available(macOS 26.0, *)`），并将 `Screen.swift` 中的屏幕识别完全固化为 `screen.cgDirectDisplayID`。
- **溯源关联**：FR-001、SC-007、Upstream macOS 27 Modernization。
- **上下文概要**：项目不再向下兼容 macOS 26 及更低版本，必须移除所有历史运行期宏分支，净化代码路径。
- **前置条件**：T001 已完成。
- **允许修改的文件**：
  - `MacsyZones/Screen.swift`
  - `MacsyZones/Preferences.swift`
  - `MacsyZones/Settings.swift`
- **只读参考文件**：
  - `specs/001-macos27-modernization/spec.md`
- **禁止的变更**：
  - 禁止更改快捷键注册与偏好持久化键名。
- **输入与输出**：
  - 输入：带有旧系统判断的代码文件。
  - 输出：无任何可用性判断宏且纯净依赖 `cgDirectDisplayID` 的源码。
- **不变量与边界条件**：
  - `screen.cgDirectDisplayID` 在 macOS 27 环境下为标准非空标量，不得保留基于屏幕数组下标的回退逻辑。
- **有序实现要求**：
  1. 检查 `Screen.swift`：移除所有 `#available` 分支，直接返回 `screen.cgDirectDisplayID`。
  2. 检查 `Settings.swift` 与 `Preferences.swift`：解构外部包裹的 `if #available(macOS 12.0, *)` 条件块，直接执行热键注册与偏好读取。
- **可执行验证检查**：
  - 执行命令：`git grep "#available" MacsyZones/Screen.swift MacsyZones/Settings.swift MacsyZones/Preferences.swift || true`
  - 预期结果：无任何输出（无 `#available` 残留）。
- **完成证据**：上述 3 个文件中不存在任何 `#available` 关键字。
- **停止条件**：若语法解析出现未闭合大括号，立即停止。
- **交接说明**：代码已纯净化，可进入核心逻辑优化。

# 阶段 2：内存优化与启动冗余清理

### 任务 T003：消除启动阶段双重布局加载

- [ ] T003 消除启动阶段双重布局加载（溯源 PR #104）

- **单项可观察目标**：在 `MacsyZones/App.swift` 中删除 `applicationDidFinishLaunching` 内部第二处无条件调用 `userLayouts.load()`，避免开机重复构建两套 AppKit 窗口图形树。
- **溯源关联**：FR-006、SC-003、Upstream PR #104（Commit `4af86df75102cacc258dbb1eaa878a6c74ccf533`，作者：eafire15）。
- **上下文概要**：`UserData.init()` 已经触发了 `load()`。第 199 行重复调用导致每个布局的窗口被实例化两次，浪费 170MB+ 内存。
- **前置条件**：T001 已完成。
- **允许修改的文件**：
  - `MacsyZones/App.swift`
- **只读参考文件**：
  - Upstream commit `4af86df75102cacc258dbb1eaa878a6c74ccf533`
- **禁止的变更**：
  - 禁止删除 `UserData.init()` 中的加载逻辑。
  - 禁止更改 `userLayouts` 全局实例生命周期。
- **输入与输出**：
  - 输入：`App.swift` 包含启动期 `userLayouts.load()`。
  - 输出：删除该行冗余调用的 `App.swift`。
- **不变量与边界条件**：
  - 应用启动时仍能正确读取用户既有布局。
- **有序实现要求**：
  1. 定位 `App.swift` 中 `applicationDidFinishLaunching` 方法。
  2. 找到 `userLayouts.load()` 语句（原第 199 行附近），将其删除。
- **可执行验证检查**：
  - 执行命令：`git grep -n "userLayouts.load()" MacsyZones/App.swift || true`
  - 预期结果：无匹配项（`App.swift` 中不再显式调用 `userLayouts.load()`）。
- **完成证据**：`App.swift` 中不包含 `userLayouts.load()`。
- **停止条件**：若定位到多个调用点，仅删除启动方法内部的重复点。
- **交接说明**：消除双重实例化后，进入按需物化重构。

### 任务 T004：实现 UserLayout 布局窗口惰性物化（Lazy Materialization）

- [ ] T004 实现 UserLayout 布局窗口惰性物化（溯源 PR #106）

- **单项可观察目标**：重构 `UserData.swift` 中的 `UserLayout` 类，将 `layoutWindow` 改造为按需延迟实例化的计算属性，并在 `Macsy.swift` 隐藏与重置时加入守卫，使冷启动物理内存降至 30MB 以内。
- **溯源关联**：FR-007、SC-003、Upstream PR #106（Commit `0fd5d926a8e661251f55867cf40bac717743ed55` 等，作者：eafire15）。
- **上下文概要**：此前所有已保存布局均在启动时被一次性创建，造成物理内存长期高达数百兆。按需物化仅在实际使用或编辑时创建窗口。
- **前置条件**：T003 已完成。
- **允许修改的文件**：
  - `MacsyZones/UserData.swift`
  - `MacsyZones/Macsy.swift`
- **只读参考文件**：
  - Upstream PR #106 commits `0fd5d926a8e661251f55867cf40bac717743ed55`、`c57c6cb7d764df06f7a5a9d744d205297b15d751`
- **禁止的变更**：
  - 禁止更改 `UserLayouts.json` 持久化格式与结构。
- **输入与输出**：
  - 输入：强引用全量初始化的 `layoutWindow`。
  - 输出：支持 `storedLayoutWindow`、`materializedLayoutWindow` 与 `hasMaterializedLayoutWindow` 的惰性类。
- **不变量与边界条件**：
  - 当布局尚未物化时，调用 `hide()` 或 `resetCurrentLayout()` 不得触发其实例化。
- **有序实现要求**：
  1. 在 `UserData.swift` 的 `UserLayout` 类中：
     - 将 `var layoutWindow: LayoutWindow!` 替换为 `private var storedLayoutWindow: LayoutWindow?`。
     - 添加 `var materializedLayoutWindow: LayoutWindow? { storedLayoutWindow }`。
     - 添加 `var hasMaterializedLayoutWindow: Bool { storedLayoutWindow != nil }`。
     - 声明 `var layoutWindow: LayoutWindow`：若 `storedLayoutWindow` 存在则返回；否则构建 `LayoutWindow(userLayout: self)` 并缓存。
     - 实现 `func discardMaterializedLayoutWindow()` 与 `func stopEditing(discardWindow: Bool = true)`。
  2. 在 `Macsy.swift` 中：
     - 在 `hide()`、`resetCurrentLayout()`、`stopEditing()` 中，增加 `if userLayouts.currentLayout.hasMaterializedLayoutWindow` 守卫，避免不必要实例化。
- **可执行验证检查**：
  - 执行命令：`git grep "storedLayoutWindow" MacsyZones/UserData.swift`
  - 预期结果：找到 `storedLayoutWindow` 字段定义与使用。
- **完成证据**：`UserLayout` 具备惰性物化与守卫接口。
- **停止条件**：若修改导致类型循环引用，立即排查解除。
- **交接说明**：完成布局惰性化，继续清理弹窗生命周期。

### 任务 T005：实现 QuickSnapper 关闭资源彻底解构与世代代号保护

- [ ] T005 实现 QuickSnapper 关闭资源彻底解构与世代代号保护（溯源 PR #107）

- **单项可观察目标**：在 `MacsyZones/QuickSnapper.swift` 中实现关闭淡出完成后释放窗口列表与 HostingView，引入 `lifecycleGeneration` 防范异步动画竞态，并将状态与热键调度约束至 `@MainActor`。
- **溯源关联**：FR-008、SC-003、Upstream PR #107（Commit `501c92f3cba4b0c561558d051c1faef85d2bcb29`、`69f1019032cf5e30ae16f4e934ee49393e8903f0`，作者：eafire15）。
- **上下文概要**：QuickSnapper 关闭后残留 AppKit 物理视图且缺乏世代保护，连续快速触发时易引发越界与时序混乱。
- **前置条件**：T001 已完成。
- **允许修改的文件**：
  - `MacsyZones/QuickSnapper.swift`
- **只读参考文件**：
  - Upstream commit `69f1019032cf5e30ae16f4e934ee49393e8903f0`
- **禁止的变更**：
  - 禁止更改 QuickSnapper 默认激活快捷键与缩略图网格渲染。
- **输入与输出**：
  - 输入：关闭后保留 contentView 的 QuickSnapper 类。
  - 输出：关闭后置空 `panel.contentView = nil` 并具备世代代号校验的 QuickSnapper。
- **不变量与边界条件**：
  - 在面板处于关闭状态时，任何键盘回车或方向键输入均不得对非空窗口进行操作。
- **有序实现要求**：
  1. 在 `QuickSnapper` 类中添加 `private var lifecycleGeneration: UInt64 = 0`。
  2. 在 `hide()` 中递增 `lifecycleGeneration`；在淡出动画完成闭包中检查世代代号，若匹配则执行 `self.panel.contentView = nil`、`self.windows = []`。
  3. 将涉及 UI 操作的闭包与热键动作包装在 `@MainActor` 或 `DispatchQueue.main.async` 中。
- **可执行验证检查**：
  - 执行命令：`git grep "lifecycleGeneration" MacsyZones/QuickSnapper.swift`
  - 预期结果：找到世代代号的定义与递增逻辑。
- **完成证据**：QuickSnapper 在关闭后释放视图树并受世代保护。
- **停止条件**：若修改导致关闭后重新打开白屏，检查 `show()` 是否正确重新赋值 `contentView`。
- **交接说明**：内存与生命周期清理完成，进入辅助功能引擎重构。

# 阶段 3：拖拽会话状态机与辅助功能引擎重构

### 任务 T006：创建纯 Swift 拖拽会话状态机 DragSessionState

- [ ] T006 创建纯 Swift 拖拽会话状态机 DragSessionState（溯源 PR #102）

- **单项可观察目标**：在 `MacsyZones/DragSessionState.swift` 中实现完全解耦、确定的拖拽状态机模型，统一处理修饰键与拖拽先后时序，管理窗口归属锁与物理修饰键独立保留。
- **溯源关联**：FR-002、SC-001、SC-002、Upstream PR #102（Commit `ec28f8f8ee4b570d8af442b32c26d8bd485b7b19`，作者：daniellavallee）。
- **上下文概要**：此前修饰键与鼠标拖拽各自定义状态，导致“先按 Shift 后拖”与“先拖后按 Shift”行为不一致。状态机集中管理状态迁移。
- **前置条件**：T001 已完成并在工程中注册该文件。
- **允许新建的文件**：
  - `MacsyZones/DragSessionState.swift`
- **只读参考文件**：
  - `git show pr-102:MacsyZones/DragSessionState.swift`
- **禁止的变更**：
  - 该文件不得依赖 AppKit 或真实窗口对象，必须保持为可单测的纯 Swift 逻辑。
- **输入与输出**：
  - 输入：无（新建文件）。
  - 输出：包含 `DragSessionPhase`、`DragSessionState` 结构体的源码文件。
- **不变量与边界条件**：
  - 当处于 `active` 拖拽状态时，来自其他窗口的拖拽通知必须被拒绝。
  - 鼠标释放时重置拖拽，但保留物理修饰键按下标志。
- **有序实现要求**：
  1. 复用上游 PR #102 中的 `MacsyZones/DragSessionState.swift` 实现。
  2. 包含 `DragSessionPhase` 枚举（`idle`、`candidate(windowID: CGWindowID, startPosition: CGPoint)`、`active(windowID: CGWindowID, currentTarget: SectionWindow?)`）。
  3. 提供 `onModifierDown()`、`onModifierUp()`、`onWindowDragStarted()`、`onWindowMoved()`、`onMouseUp()` 等纯函数状态转移方法。
- **可执行验证检查**：
  - 执行命令：`test -f MacsyZones/DragSessionState.swift && echo "File exists"`
  - 预期结果：输出 `File exists`。
- **完成证据**：`DragSessionState.swift` 存在且语法无误。
- **停止条件**：若包含编译错误，立即修正。
- **交接说明**：状态机就绪，下一步在 `App.swift` 与 `Macsy.swift` 中进行接入。

### 任务 T007：重构 WindowObserverManager 辅助功能观察器引擎

- [ ] T007 重构 WindowObserverManager 辅助功能观察器引擎（溯源 PR #102）

- **单项可观察目标**：重构 `App.swift` 中的 `WindowObserverManager`，仅在 AX 注册成功后记录窗口，引入指数退避重试（+0.2s, +0.5s, +1.0s），接入 `didActivateApplicationNotification` 增量对账，并清理退出事件。
- **溯源关联**：FR-003、FR-004、FR-014、SC-001、Upstream PR #102（Commit `ec28f8f8ee4b570d8af442b32c26d8bd485b7b19`，作者：daniellavallee）。
- **上下文概要**：解决冷启动 Finder 首拖失灵的核心任务。冷启动时 Finder 未就绪导致 AX 注册失败，原代码直接标记已观察且不再重试；重构后实现退避重试与激活补查。
- **前置条件**：T006 已完成。
- **允许修改的文件**：
  - `MacsyZones/App.swift`
- **只读参考文件**：
  - `git show pr-102:MacsyZones/App.swift`
- **禁止的变更**：
  - 禁止删除已有的权限检查（`AXIsProcessTrusted()`）弹窗。
- **输入与输出**：
  - 输入：未做注册校验且无退避重试的 `WindowObserverManager`。
  - 输出：支持返回值校验、退避重试、双移动通知监听、激活对账与退出资源清理的引擎。
- **不变量与边界条件**：
  - 每个应用在注册完成前最多重试 3 次，避免无限轮询消耗 CPU。
- **有序实现要求**：
  1. 复用 PR #102 中 `WindowObserverManager` 的设计：
     - 以 PID 和 WindowID 复合索引观察器字典。
     - 同时注册 `kAXMovedNotification` 与 `kAXWindowMovedNotification`。
     - 仅当 `AXObserverAddNotification` 返回 `kAXErrorSuccess` 时记录；返回 `kAXErrorCannotComplete` 时调度延迟重试（0.2s、0.5s、1.0s）。
  2. 在 `NSWorkspace.shared.notificationCenter` 注册 `NSWorkspace.didActivateApplicationNotification` 观察者，应用激活时触发补查。
  3. 在 `applicationWillTerminate` 中移除所有 AX 观察器与 RunLoop Sources。
- **可执行验证检查**：
  - 执行命令：`git grep "kAXErrorCannotComplete" MacsyZones/App.swift`
  - 预期结果：找到针对 `kAXErrorCannotComplete` 的退避重试处理。
- **完成证据**：`App.swift` 包含严格 AX 注册校验与退避重试逻辑。
- **停止条件**：若重试逻辑未设置终止条件，必须设置最大重试次数为 3。
- **交接说明**：完成观察器引擎加固，下一步完善位移兜底与遮罩属性。

### 任务 T008：激活物理鼠标位移兜底与遮罩层 Space 跨越增强

- [ ] T008 激活物理鼠标位移兜底与遮罩层 Space 跨越增强（溯源 PR #102）

- **单项可观察目标**：在 `MacsyZones/Macsy.swift` 的 `onMouseDragged` 中实现光标位移 > 5pt 的主动吸附兜底；将所有遮罩窗口的 `collectionBehavior` 设置为 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`；在 `Preferences.swift` 中实现基于显示器 UUID 的独立 Space 偏好解析。
- **溯源关联**：FR-005、SC-001、SC-002、Upstream PR #102（Commit `ec28f8f8ee4b570d8af442b32c26d8bd485b7b19`，作者：daniellavallee）。
- **上下文概要**：当 AX 事件被应用阻塞时，物理鼠标位移兜底保证吸附正常触发；全屏辅助属性使遮罩层在所有桌面均可正常展示。
- **前置条件**：T006、T007 已完成。
- **允许修改的文件**：
  - `MacsyZones/Macsy.swift`
  - `MacsyZones/Preferences.swift`
- **只读参考文件**：
  - `git show pr-102:MacsyZones/Macsy.swift`
  - `git show pr-102:MacsyZones/Preferences.swift`
- **禁止的变更**：
  - 禁止在鼠标微小晃动（< 5pt）时误触吸附，防止干扰文本选取。
- **输入与输出**：
  - 输入：空实现的 `onMouseDragged`，单全局 Space 解析。
  - 输出：具有 > 5pt 阈值判断的位移兜底逻辑，具有跨 Space 属性的窗口集合，具有显示器 UUID Space 解析能力的偏好管理类。
- **不变量与边界条件**：
  - 鼠标释放时必须彻底清除位移累加与候选窗口锁定。
- **有序实现要求**：
  1. 复用 PR #102 中 `Macsy.swift` 的 `onMouseDragged` 实现：读取光标全局位移差，若大于 5pt 且光标下为有效 AX 窗口，调用 `dragSession.onWindowDragStarted`。
  2. 检查各窗口初始化点（`Layout.swift` 与 `Macsy.swift`），统一设置 `window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`。
  3. 在 `Preferences.swift` 中复用 PR #102 的 Space 解析：基于显示器 UUID 从 `com.apple.spaces.plist` 读取对应 `Current Space`。
- **可执行验证检查**：
  - 执行命令：`git grep "canJoinAllSpaces" MacsyZones/Macsy.swift MacsyZones/Layout.swift`
  - 预期结果：找到各窗口集合行为中包含 `canJoinAllSpaces`。
- **完成证据**：鼠标位移兜底逻辑完整，遮罩窗口具备跨桌面展示能力。
- **停止条件**：若多显示器 Space 查找抛出空指针，确保包含全局 Space 回退。
- **交接说明**：冷启动与 Space 健壮性重构完成，进入防崩溃与约束加固阶段。

# 阶段 4：防崩溃与 AppKit 约束重入加固

### 任务 T009：修复 UserData.reArrange() 强制解包崩溃

- [ ] T009 修复 UserData.reArrange() 强制解包崩溃（溯源 PR #86）

- **单项可观察目标**：在 `MacsyZones/UserData.swift` 的 `reArrange()` 中，彻底消除 `$0.number!` 与 `.first(where:)!` 的强制解包，使用安全排序与 `guard let` 忽略脏数据，杜绝保存布局时的闪退。
- **溯源关联**：FR-009、SC-005、Upstream PR #86（Commit `795e46978602dab707b9207176bf8f222943e9c9`，作者：haylax）。
- **上下文概要**：在增删分区或分区配置与活跃窗口不同步时，强制解包直接触发 SIGTRAP。
- **前置条件**：T001 已完成。
- **允许修改的文件**：
  - `MacsyZones/UserData.swift`
- **只读参考文件**：
  - `git show pr-86:MacsyZones/UserData.swift`
- **禁止的变更**：
  - 禁止更改分区序号从 1 开始重排的业务规则。
- **输入与输出**：
  - 输入：含有 2 处强制解包的 `reArrange()`。
  - 输出：100% 安全解包且容错的 `reArrange()`。
- **不变量与边界条件**：
  - 遇到丢失 `sectionWindow` 的配置项跳过重排并继续，不得抛出未捕获异常。
- **有序实现要求**：
  1. 将 `let sectionConfigs = self.sectionConfigs.values.sorted { $0.number! < $1.number! }` 改为：
     ```swift
     let sectionConfigs = self.sectionConfigs.values.sorted {
         ($0.number ?? Int.max) < ($1.number ?? Int.max)
     }
     ```
  2. 将循环内部的强制解包：
     `let sectionWindow = layoutWindow.sectionWindows.first(where: { $0.number == sectionConfig.number })!`
     改为：
     `guard let sectionWindow = layoutWindow.sectionWindows.first(where: { $0.number == sectionConfig.number }) else { continue }`
- **可执行验证检查**：
  - 执行命令：`git grep "number\!" MacsyZones/UserData.swift || true`
  - 预期结果：无任何输出（无强制解包）。
- **完成证据**：`reArrange()` 不包含任何 `!` 强制解包。
- **停止条件**：若修改改变了分区排序结果，核对是否使用了相同的比较逻辑。
- **交接说明**：布局保存加固完成，进入约束重入防御。

### 任务 T010：加固 AppKit 约束重入防护与 NSHostingView 尺寸声明

- [ ] T010 加固 AppKit 约束重入防护与 NSHostingView 尺寸声明（溯源 PR #79）

- **单项可观察目标**：在 `MacsyZones/Layout.swift`、`MacsyZones/LiquidGlass.swift` 与 `MacsyZones/Macsy.swift` 中，为所有固定尺寸 `NSHostingView` 设置 `sizingOptions = []`；在窗口代理中通过 `DispatchQueue.main.async` 派发 `@Published` 变更；在 `LiquidGlassView` 中守卫 KVC 写入，杜绝 macOS 27 下的 `SIGTRAP / EXC_BREAKPOINT` 崩溃。
- **溯源关联**：FR-010、FR-011、SC-004、Upstream PR #79（Commit `c66f06ac789ccc72d8c55a7d3eaeff50b54ce586`，作者：wylanswets）。
- **上下文概要**：macOS 27 强化了 AppKit 约束更新周期，在窗口代理或悬停检测中直接修改 `@Published` 会重入 `_postWindowNeedsUpdateConstraints` 造成崩溃。
- **前置条件**：T001 已完成。
- **允许修改的文件**：
  - `MacsyZones/Layout.swift`
  - `MacsyZones/LiquidGlass.swift`
  - `MacsyZones/Macsy.swift`
- **只读参考文件**：
  - `git show pr-79:MacsyZones/Layout.swift`
  - `git show pr-79:MacsyZones/LiquidGlass.swift`
  - `git show pr-79:MacsyZones/Macsy.swift`
- **禁止的变更**：
  - 禁止添加 `#available(macOS 13.0, *)` 等多余宏，macOS 27 原生支持 `sizingOptions`。
- **输入与输出**：
  - 输入：直接在窗口代理中同步修改 `@Published` 的代码。
  - 输出：带有 `sizingOptions = []` 且异步派发的健壮实现。
- **不变量与边界条件**：
  - `sizingOptions = []` 仅适用于程序化指定宽高的窗口 contentView。
- **有序实现要求**：
  1. 在 `Layout.swift` 中，为 `ScreenChangeWarningDialog`、`SectionWindow`、`EditorSectionView`、`LayoutWindow.editorBarWindow`、`SnapResizer`、`GridLayoutWindow` 的 `NSHostingView` 显式设置 `sizingOptions = []`。
  2. 在 `EditorSectionWindowDelegate` 的 `windowDidResize` 与 `windowDidMove` 中，使用 `DispatchQueue.main.async { [weak self] in ... }` 包装属性修改。
  3. 在 `LiquidGlass.swift` 的 `updateNSView()` 中，添加：
     ```swift
     if let currentRadius = nsView.value(forKey: "cornerRadius") as? CGFloat, currentRadius != cornerRadius {
         nsView.setValue(cornerRadius, forKey: "cornerRadius")
     }
     ```
  4. 在 `Macsy.swift` 的 `getHoveredSectionWindow()` 中，将 `sectionWindow.isHovered` 的更新推迟至 `DispatchQueue.main.async`，且仅在值变化时赋值。
- **可执行验证检查**：
  - 执行命令：`git grep "sizingOptions = \[\]" MacsyZones/Layout.swift`
  - 预期结果：找到多处 `sizingOptions = []` 设置。
- **完成证据**：各窗口内容视图已声明 `sizingOptions = []`，代理与悬停更新已异步化。
- **停止条件**：若出现线程安全警告，核对 `[weak self]` 是否完备。
- **交接说明**：约束重入防御完成，进入高级交互扩展。

# 阶段 5：分区编辑与高级吸附交互增强

### 任务 T011：分区编辑器对齐工具栏 AlignmentPreset

- [ ] T011 分区编辑器对齐工具栏 AlignmentPreset（溯源 PR #86）

- **单项可观察目标**：在 `MacsyZones/Layout.swift` 中定义 `AlignmentPreset` 枚举与 6 个基于 SF Symbols 的对齐按钮，集成至 `EditorSectionView`，实现保持当前分区宽高不变的前提下快速将分区对齐至屏幕边缘或居中。
- **溯源关联**：FR-012、SC-005、Upstream PR #86（Commit `bb77f61d002c25ec6342ce12b880935b689b97c9`，作者：haylax）。
- **上下文概要**：现有的定位预设会重置分区尺寸，新增的对齐预设仅改变原点坐标（左/水平居中/右/顶/垂直居中/底），极大提升排版效率。
- **前置条件**：T001 已完成。
- **允许修改的文件**：
  - `MacsyZones/Layout.swift`
- **只读参考文件**：
  - `git show pr-86:MacsyZones/Layout.swift`
- **禁止的变更**：
  - 禁止破坏原有的 `PositioningPreset` 按钮功能。
- **输入与输出**：
  - 输入：仅有缩放定位工具栏的 `EditorSectionView`。
  - 输出：包含 `AlignmentPreset` 独立对齐行的 `EditorSectionView`。
- **不变量与边界条件**：
  - 分区计算新原点时必须保证处于当前屏幕的可见安全区域内。
- **有序实现要求**：
  1. 复用 PR #86 中的 `AlignmentPreset` 枚举（定义 `left`、`horizontalCenter`、`right`、`top`、`verticalCenter`、`bottom`）。
  2. 实现 `struct AlignmentButton: View`，使用 SF Symbols（`align.horizontal.left`、`align.horizontal.center`、`align.horizontal.right`、`align.vertical.top`、`align.vertical.center`、`align.vertical.bottom`）。
  3. 在 `EditorSectionView` 的操作栏中加入对齐预设按钮行，点击时仅更新 `sectionWindow.window.setFrameOrigin(...)`，保留当前 `frame.size`。
- **可执行验证检查**：
  - 执行命令：`git grep "enum AlignmentPreset" MacsyZones/Layout.swift`
  - 预期结果：找到 `AlignmentPreset` 枚举定义。
- **完成证据**：`Layout.swift` 中定义了 `AlignmentPreset` 并在编辑器视图中渲染。
- **停止条件**：若 SF Symbols 名称拼写错误导致图标丢失，核对苹果官方符号名称。
- **交接说明**：编辑器对齐工具栏就绪，继续实现高级吸附交互。

### 任务 T012：拖拽自动吸附、多区联合吸附与粘性右键取消

- [ ] T012 拖拽自动吸附、多区联合吸附与粘性右键取消（溯源 PR #86）

- **单项可观察目标**：在 `Settings.swift` 与 `SettingsView.swift` 中增加 `snapWhileDragging`、`enableZoneSpanning`、`spanKey` 配置项及中文 UI；在 `Macsy.swift` 中实现多分区联合矩形吸附与粘性右键取消标志位。
- **溯源关联**：FR-013、SC-006、Upstream PR #86（Commit `fbe6e28aa699b397ba9eb3b4c0afaf83e8c22d5f`，作者：haylax）。
- **上下文概要**：提供无按键自动吸附、按住 Command 划过多区合并吸附，以及右键单击取消当前拖拽吸附的平滑体验。
- **前置条件**：T006、T008 已完成。
- **允许修改的文件**：
  - `MacsyZones/Settings.swift`
  - `MacsyZones/SettingsView.swift`
  - `MacsyZones/Macsy.swift`
  - `MacsyZones/App.swift`
- **只读参考文件**：
  - `git show pr-86:MacsyZones/Settings.swift`
  - `git show pr-86:MacsyZones/Macsy.swift`
  - `git show pr-86:MacsyZones/Popover.swift`
- **禁止的变更**：
  - 本项目移除了 `Popover.swift`，设置 UI 必须添加在 `SettingsView.swift`，使用纯正简洁的中文标签。
- **输入与输出**：
  - 输入：缺乏联合吸附的拖拽逻辑。
  - 输出：支持联合吸附并带配置项与界面的完整系统。
- **不变量与边界条件**：
  - 右键取消后，在当前拖拽松开前，后续鼠标移动均不得重新唤醒吸附网格。
- **有序实现要求**：
  1. 在 `Settings.swift` 中添加 `@Published var snapWhileDragging: Bool = true`、`@Published var enableZoneSpanning: Bool = true`、`@Published var spanKey: String = "Command"`，并同步至 `AppSettingsData` 的编码/解码。
  2. 在 `SettingsView.swift` 的吸附行为分组中添加中文切换项：
     - "拖拽时自动吸附（无需长按按键）"
     - "多分区联合吸附（按住扩展按键）"
     - 扩展按键选择器（Command / Shift / Option / Control）。
  3. 在 `Macsy.swift` 中维护 `spannedSectionWindows` 数组；当按住 `spanKey` 且光标划过多分区时，计算联合外接矩形并在鼠标释放时将窗口调整至联合区域。
  4. 增加 `snapSuppressedForDrag` 布尔值，当右键按下时置为 `true`，拖拽结束时重置为 `false`。
- **可执行验证检查**：
  - 执行命令：`git grep "enableZoneSpanning" MacsyZones/Settings.swift MacsyZones/Macsy.swift`
  - 预期结果：找到该配置字段在设置和拖拽逻辑中的引用。
- **完成证据**：设置项已持久化，UI 已汉化呈现，吸附逻辑支持多区合并。
- **停止条件**：若多选矩形计算出现坐标翻转，核对 AppKit 笛卡尔坐标系统换算。
- **交接说明**：全部业务逻辑完成，进入发布版本门禁与构建验证。

# 阶段 6：版本审计与自动化构建验证

### 任务 T013：登记发布目标并执行全量版本门禁与构建验证

- [ ] T013 登记发布目标并执行全量版本门禁与构建验证

- **单项可观察目标**：在 `RELEASES.md` 中登记发布目标为 `v2.0.0 / Major`，执行 `scripts/check-version.sh 2.0.0 major` 校验版本一致性，执行 `scripts/build-debug.sh` 验证编译与本地正式签名审计通过。
- **溯源关联**：SC-007、项目版本与发布规范。
- **上下文概要**：按照项目量化规则，本次升级覆盖平台最低系统提升、状态机与观察器重构、内存按需物化，判定为 Major。发布前必须通过自动化审计门禁。
- **前置条件**：T001 至 T012 全部完成。
- **允许修改的文件**：
  - `RELEASES.md`
- **只读参考文件**：
  - `VERSIONING.md`
  - `BUILD.md`
- **禁止的变更**：
  - 禁止跳过 `scripts/check-version.sh` 脚本校验。
  - 禁止在项目目录下生成或暂存 DMG 文件。
- **输入与输出**：
  - 输入：全部代码已更新。
  - 输出：`RELEASES.md` 登记完备，Debug 构建与签名审计通过。
- **不变量与边界条件**：
  - 代码签名必须匹配 Team ID `74FR87HYTH` 与证书 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`。
- **有序实现要求**：
  1. 在 `RELEASES.md` 的“下一发布目标”中登记 `v2.0.0 / Major`，列出全部更新要点与上游 PR 映射。
  2. 运行 `scripts/check-version.sh 2.0.0 major` 进行版本门禁校验。
  3. 运行 `scripts/build-debug.sh` 进行全量编译并验证代码签名。
- **可执行验证检查**：
  - 执行命令：`scripts/check-version.sh 2.0.0 major && scripts/build-debug.sh`
  - 预期结果：版本检查通过，Debug 构建成功并输出签名审计 `PASSED`。
- **完成证据**：版本门禁通过且构建日志显示签名成功。
- **停止条件**：若签名审计失败或编译报错，必须在当前任务解决，不得跳过。
- **交接说明**：版本与签名验证就绪，进入文档更新与发布交付。

# 阶段 7：文档更新、Git 推送与 GitHub Release 闭环交付

### 任务 T014：更新项目面向用户的说明文档 README.md

- [ ] T014 更新项目面向用户的说明文档 README.md

- **单项可观察目标**：在 `README.md` 中全面更新系统支持要求（macOS 27.0+），并撰写关于 Finder 冷启动修复、分区对齐工具栏、拖拽自动吸附和多区联合吸附的功能说明与最新发布指引。
- **溯源关联**：FR-015、SC-008、项目文档规范。
- **上下文概要**：面向用户的 `README.md` 需要真实反映 `v2.0.0` 带来的架构跃迁与新交互能力，告知用户环境基准提升至 macOS 27。
- **前置条件**：T013 完成。
- **允许修改的文件**：
  - `README.md`
- **只读参考文件**：
  - `specs/001-macos27-modernization/spec.md`
  - `RELEASES.md`
- **禁止的变更**：
  - 禁止在 Markdown 正文中使用全局大标题或水平分割线（`---`）。
- **输入与输出**：
  - 输入：旧版 README.md。
  - 输出：与 macOS 27 专版对齐的全新 README.md。
- **不变量与边界条件**：
  - 必须保留致谢原作者与 GPL-3.0 许可证说明。
- **有序实现要求**：
  1. 更新项目概述与系统需求为 macOS 27.0+。
  2. 详细列出 v2.0.0 的核心特性：冷启动拖拽修复、纯 Swift 拖拽状态机、惰性窗口物化、分区对齐工具栏、拖拽自动吸附与多区联合吸附。
  3. 更新版本说明与构建运行指南。
- **可执行验证检查**：
  - 执行命令：`git grep "macOS 27" README.md`
  - 预期结果：找到 macOS 27 系统要求说明。
- **完成证据**：`README.md` 内容全面更新并通过排版规则审查。
- **停止条件**：排版违反 Markdown 空行或标题规则时必须调整。
- **交接说明**：文档同步就绪，进入版本提交与推送。

### 任务 T015：提交全部代码与规范变更并推送到 GitHub custom 分支

- [ ] T015 提交全部代码与规范变更并推送到 GitHub custom 分支

- **单项可观察目标**：将全部源代码、Spec 资产与文档变更进行规范 Git 提交，并推送到本项目 GitHub 远端仓库 `jiezhengj/MacsyZones` 的 `custom` 分支。
- **溯源关联**：FR-016、SC-008、项目 GitHub 纪律。
- **上下文概要**：所有工作必须安全同步至项目的唯一远端仓库，严格禁止向上游推送。
- **前置条件**：T014 已完成。
- **允许执行的命令**：
  - `git add <files>`
  - `git commit -m "..."`
  - `git push origin custom`
- **只读参考文件**：
  - `AGENTS.md`（重要规则：只推送到 `jiezhengj/MacsyZones`）
- **禁止的变更**：
  - 严禁将任何 `.dmg` 文件加入暂存区或提交。
  - 严禁执行指向 `upstream` 的 `git push` 或 PR 创建。
- **输入与输出**：
  - 输入：工作区待提交变更。
  - 输出：`origin/custom` 与本地 `custom` 分支同步且工作区干净。
- **不变量与边界条件**：
  - 提交信息清晰明了，概括 macOS 27 专版化重构与 PR 溯源。
- **有序实现要求**：
  1. 执行 `git status` 复核所有待暂存文件，确认无临时文件或 DMG。
  2. 执行 `git add` 暂存所有代码与文档文件。
  3. 执行 `git commit` 生成提交。
  4. 执行 `git push origin custom` 推送。
- **可执行验证检查**：
  - 执行命令：`git log -n 1 --oneline && git status --short`
  - 预期结果：最新提交记录在 custom 分支头部，工作区干净。
- **完成证据**：远端 `custom` 分支接收到最新 commit。
- **停止条件**：若推送出现拒绝，核对网络与分支状态。
- **交接说明**：代码已推送，进入 Release DMG 构建。

### 任务 T016：构建正式签名的 Release DMG 安装包

- [ ] T016 构建正式签名的 Release DMG 安装包

- **单项可观察目标**：使用项目专用构建脚本 `scripts/build-release-dmg.sh 2.0.0 major` 在 `/tmp` 目录下构建正式签名的 Release DMG 文件，并完成 `hdiutil verify` 校验。
- **溯源关联**：FR-017、SC-007、SC-008、BUILD.md。
- **上下文概要**：Release DMG 是面向最终用户的分发载体，必须由专用脚本在 `/tmp` 中全程构建并通过正式 Apple Development 签名审计。
- **前置条件**：T015 已完成。
- **允许修改的文件**：
  - `scripts/build-release-dmg.sh`
- **允许执行的命令**：
  - `scripts/build-release-dmg.sh 2.0.0 major`
  - `hdiutil verify /tmp/MacsyZones-v2.0.0.dmg`
- **只读参考文件**：
  - `BUILD.md`
  - `scripts/build-release-dmg.sh`
- **禁止的变更**：
  - 绝对禁止在项目仓库目录下生成或保存 DMG 文件。
- **输入与输出**：
  - 输入：通过版本门禁的代码库。
  - 输出：位于 `/tmp/MacsyZones-v2.0.0.dmg` 的经过签名校验的镜像文件。
- **不变量与边界条件**：
  - 签名 Authority 必须为 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`，Team ID 必须为 `74FR87HYTH`。
- **有序实现要求**：
  1. 调用 `scripts/build-release-dmg.sh 2.0.0 major` 执行 Release 构建。
  2. 脚本自动在 `/tmp` 执行 Release 编译、签名审计、DMG 制作与 `hdiutil verify`。
  3. 复核 `/tmp/MacsyZones-v2.0.0.dmg` 的存在性与大小。
- **可执行验证检查**：
  - 执行命令：`hdiutil verify /tmp/MacsyZones-v2.0.0.dmg`
  - 预期结果：输出包含 `校验成功` 或 `Checksum: OK`。
- **完成证据**：`/tmp/MacsyZones-v2.0.0.dmg` 校验通过。
- **停止条件**：若签名或打包失败，必须排查证书与编译日志。
- **交接说明**：DMG 已就绪，进入 GitHub Release 发布与资产上传。

### 任务 T017：创建 Git Tag 并通过 gh CLI 发布 GitHub Release 与资产上传

- [ ] T017 创建 Git Tag 并通过 gh CLI 发布 GitHub Release 与资产上传

- **单项可观察目标**：打上 Git Tag `v2.0.0` 并推送到 GitHub，使用 `gh release create` 创建标题为 `MacsyZones 中文定制版 v2.0.0` 的 Release，使用 `gh release upload` 上传 DMG 资产，随后删除本地临时 DMG。
- **溯源关联**：FR-018、SC-008、AGENTS.md Release 规范、GitHub 操作纪律。
- **上下文概要**：严格使用 `gh` CLI 完成 GitHub 服务操作，遵循既定的 Release Notes 模板，严禁使用浏览器或直接 API。
- **前置条件**：T016 已完成。
- **允许修改的文件**：
  - `RELEASES.md`
- **允许执行的命令**：
  - `git tag -a v2.0.0 -m "..."`
  - `git push origin v2.0.0`
  - `gh release create ...`
  - `gh release upload ...`
  - `rm -f /tmp/MacsyZones-v2.0.0.dmg`
- **只读参考文件**：
  - `AGENTS.md`（Release 规范与正文模板）
- **禁止的变更**：
  - 禁止在 Release 标题后添加额外描述。
  - 禁止上传非 `/tmp` 下的构建文件。
- **输入与输出**：
  - 输入：`/tmp/MacsyZones-v2.0.0.dmg` 与 Release Notes 内容。
  - 输出：GitHub 上线的 Release `v2.0.0` 及其 DMG 资产。
- **不变量与边界条件**：
  - 发布完成后必须立即删除 `/tmp` 中的 DMG 文件。
- **有序实现要求**：
  1. 执行 `git tag -a v2.0.0 -m "v2.0.0: macOS 27 专版化重构与上游核心增强"`。
  2. 执行 `git push origin v2.0.0` 推送标签。
  3. 执行 `gh release create "v2.0.0" --repo jiezhengj/MacsyZones --title "MacsyZones 中文定制版 v2.0.0" --notes "..."`。
  4. 执行 `gh release upload "v2.0.0" "/tmp/MacsyZones-v2.0.0.dmg" --repo jiezhengj/MacsyZones --clobber`。
  5. 执行 `rm -f "/tmp/MacsyZones-v2.0.0.dmg"`。
- **可执行验证检查**：
  - 执行命令：`gh release view v2.0.0 --repo jiezhengj/MacsyZones`
  - 预期结果：显示 Release 详情及 `MacsyZones-v2.0.0.dmg` 资产列表。
- **完成证据**：GitHub Release 正式创建且 DMG 资产挂载在 Release 页面上。
- **停止条件**：若 gh 未登录或权限不足，停止并报告阻断。
- **交接说明**：Release 发布完成，进行最终台账同步。

### 任务 T018：更新 RELEASES.md 版本台账为“已发布”并推送

- [ ] T018 更新 RELEASES.md 版本台账为“已发布”并推送

- **单项可观察目标**：将 `RELEASES.md` 中的“当前已发布版本”更新为 `v2.0.0`，在发布历史表格中将 `v2.0.0` 的状态更新为“已发布”，并提交、推送到 `origin custom`。
- **溯源关联**：FR-015、SC-008、RELEASES.md 维护规则。
- **上下文概要**：台账是版本唯一权威记录，只有 GitHub Release 创建并资产可下载后才能标记为已发布。
- **前置条件**：T017 已完成。
- **允许修改的文件**：
  - `RELEASES.md`
- **只读参考文件**：
  - `RELEASES.md`
  - `AGENTS.md`
- **禁止的变更**：
  - 禁止在未成功上传 GitHub Release 的情况下提前标记为“已发布”。
- **输入与输出**：
  - 输入：处于“计划中”的 RELEASES.md。
  - 输出：处于“已发布”且已推送到远端的 RELEASES.md。
- **不变量与边界条件**：
  - 该文档中的已发布版本号必须与 git tag、Xcode MARKETING_VERSION 和 GitHub Release 保持绝对一致。
- **有序实现要求**：
  1. 修改 `RELEASES.md`：“当前已发布版本：`v2.0.0`”。
  2. 将历史表中 `v2.0.0` 的状态由“计划中”更新为“已发布”。
  3. 规划下一发布目标为 `v2.0.1 / Patch`。
  4. 提交并推送 `RELEASES.md` 至 `origin custom`。
- **可执行验证检查**：
  - 执行命令：`git grep "当前已发布版本：\`v2.0.0\`" RELEASES.md`
  - 预期结果：台账已明确记录 v2.0.0 为当前已发布版本。
- **完成证据**：`RELEASES.md` 变更已推送到 GitHub `custom` 分支。
- **停止条件**：无。
- **交接说明**：全链路工作完成。
