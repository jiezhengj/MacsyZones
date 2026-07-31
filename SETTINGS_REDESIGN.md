# MacsyZones 独立窗口改造方案

## 一、技术方案

### 1.1 当前架构分析

**现有实现**：
- `App.swift` - AppDelegate 管理 NSPopover 和 NSStatusItem
- `Popover.swift` - TrayPopupView 作为 Popover 内容，包含 Main、NewView、RenameView 等子视图
- `Settings.swift` - AppSettings 类管理全局设置（实时保存）
- `Preferences.swift` - SpaceLayoutPreferences 管理每屏幕/工作区的布局偏好
- `Screen.swift` - 屏幕相关辅助函数

**核心问题**：
1. 当前配置是实时保存的，新需求需要"确定才保存"
2. 多屏幕配置需要统一管理，而非只显示当前屏幕
3. 需要从 Popover 改为独立窗口

### 1.2 新架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                      AppDelegate                            │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │ StatusItem  │───▶│      SettingsWindowManager          │ │
│  └─────────────┘    │  (单例，管理窗口生命周期)            │ │
│                     └─────────────────────────────────────┘ │
│                                    │                        │
│                                    ▼                        │
│                     ┌─────────────────────────────────────┐ │
│                     │       SettingsWindow (NSWindow)     │ │
│                     │  ┌───────────────────────────────┐  │ │
│                     │  │   SettingsView (SwiftUI)      │  │ │
│                     │  │   - ScreenTabView (顶部Tab)   │  │ │
│                     │  │   - SettingsContentView       │  │ │
│                     │  │   - ActionButtonsView         │  │ │
│                     │  └───────────────────────────────┘  │ │
│                     └─────────────────────────────────────┘ │
│                                    │                        │
│                                    ▼                        │
│                     ┌─────────────────────────────────────┐ │
│                     │   SettingsState (临时状态管理)       │ │
│                     │   - 临时 AppSettings 副本           │ │
│                     │   - 临时 SpaceLayoutPreferences 副本│ │
│                     │   - 是否有修改 (isDirty)            │ │
│                     └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 核心组件设计

#### 1.3.1 SettingsWindowManager（窗口管理器）

```swift
class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    private var settingsState: SettingsState?
    
    // 显示窗口（如果已存在则聚焦）
    func showWindow()
    
    // 隐藏窗口（不销毁）
    func hideWindow()
    
    // 切换窗口显示状态
    func toggleWindow()
    
    // 窗口是否可见
    var isVisible: Bool
}
```

#### 1.3.2 SettingsState（临时状态管理）

```swift
class SettingsState: ObservableObject {
    // 临时设置副本
    @Published var tempAppSettings: AppSettingsData
    @Published var tempSpacePreferences: [ScreenSpacePair: String]
    
    // 屏幕管理
    @Published var selectedScreenIndex: Int
    @Published var availableScreens: [ScreenInfo]
    
    // 脏状态标记
    @Published var isDirty: Bool = false
    
    // 初始化：从当前配置加载
    init()
    
    // 保存所有修改
    func saveAll()
    
    // 放弃所有修改
    func discardAll()
    
    // 检查是否有修改
    func checkForChanges()
}
```

#### 1.3.3 SettingsView（主视图）

```swift
struct SettingsView: View {
    @ObservedObject var state: SettingsState
    
    var body: some View {
        VStack {
            // 顶部屏幕选择 Tab
            ScreenTabBar(selectedIndex: $state.selectedScreenIndex, 
                        screens: state.availableScreens)
            
            // 中间配置内容
            ScrollView {
                SettingsContentView(state: state)
            }
            
            // 底部按钮
            HStack {
                Button("取消") { state.discardAll() }
                Button("确定") { state.saveAll() }
            }
        }
    }
}
```

---

## 二、实施方案

### 2.1 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `SettingsWindowManager.swift` | 窗口管理器 |
| 新建 | `SettingsState.swift` | 临时状态管理 |
| 新建 | `SettingsView.swift` | 新的设置主视图 |
| 修改 | `App.swift` | 移除 Popover 相关代码，集成新窗口管理器 |
| 修改 | `Popover.swift` | 保留子视图组件，移除 TrayPopupView |
| 删除 | - | 无文件删除 |

### 2.2 实施步骤

#### 步骤 1：创建 SettingsState（临时状态管理）

**职责**：
- 打开窗口时，深拷贝当前 AppSettings 和 SpaceLayoutPreferences
- 提供临时修改的绑定
- 追踪是否有修改（isDirty）
- 提供保存和放弃方法

**关键实现**：
```swift
class SettingsState: ObservableObject {
    @Published var tempSettings: AppSettingsData
    @Published var tempSpacePrefs: [ScreenSpacePair: String]
    @Published var selectedScreenIndex: Int = 0
    @Published var isDirty: Bool = false
    
    private var originalSettings: AppSettingsData
    private var originalSpacePrefs: [ScreenSpacePair: String]
    
    init() {
        // 深拷贝当前配置
        let current = AppSettingsData(...)
        self.tempSettings = current
        self.originalSettings = current
        // ... 类似处理 spacePreferences
    }
    
    func saveAll() {
        // 将 temp 写入 appSettings 和 spaceLayoutPreferences
        appSettings.apply(tempSettings)
        spaceLayoutPreferences.apply(tempSpacePrefs)
        appSettings.save()
        spaceLayoutPreferences.save()
    }
    
    func discardAll() {
        // 恢复 original
        tempSettings = originalSettings
        tempSpacePrefs = originalSpacePrefs
        isDirty = false
    }
}
```

#### 步骤 2：创建 SettingsView（新主视图）

**职责**：
- 顶部显示屏幕 Tab（显示器 1、显示器 2...）
- 中间显示配置内容（复用现有 Main 视图的布局）
- 底部显示取消/确定按钮

**UI 结构**：
```swift
struct SettingsView: View {
    @ObservedObject var state: SettingsState
    
    var body: some View {
        VStack(spacing: 0) {
            // 屏幕选择 Tab
            Picker("屏幕", selection: $state.selectedScreenIndex) {
                ForEach(0..<state.availableScreens.count, id: \.self) { index in
                    Text("显示器 \(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // 配置内容（复用现有布局）
            ScrollView {
                VStack {
                    LayoutSettingsSection(state: state)
                    SnapKeySettingsSection(state: state)
                    ModifierKeySettingsSection(state: state)
                    // ... 其他设置区域
                }
                .padding()
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Spacer()
                Button("取消") {
                    state.discardAll()
                    SettingsWindowManager.shared.hideWindow()
                }
                Button("确定") {
                    state.saveAll()
                    SettingsWindowManager.shared.hideWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 550, height: 600)
    }
}
```

#### 步骤 3：创建 SettingsWindowManager（窗口管理器）

**职责**：
- 管理窗口的创建、显示、隐藏
- 单例模式，窗口只创建一次
- 点击图标时显示/聚焦窗口
- 窗口居中于鼠标所在屏幕

**关键实现**：
```swift
class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    private var state: SettingsState?
    
    var isVisible: Bool {
        window?.isVisible ?? false
    }
    
    func showWindow() {
        if window == nil {
            createWindow()
        }
        
        // 刷新临时状态
        state?.refresh()
        
        // 居中于鼠标所在屏幕
        if let screen = getFocusedScreen() {
            window?.center(on: screen)
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideWindow() {
        window?.orderOut(nil)
    }
    
    func toggleWindow() {
        if isVisible {
            // 不关闭，只聚焦
            window?.makeKey()
        } else {
            showWindow()
        }
    }
    
    private func createWindow() {
        state = SettingsState()
        let contentView = SettingsView(state: state!)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "MacsyZones 设置"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.center()
        
        self.window = window
    }
}
```

#### 步骤 4：修改 App.swift

**变更内容**：
1. 移除 `popover` 相关代码
2. 移除 `setupPopover()`、`showPopover()`、`closePopover()` 方法
3. 修改 `togglePopover()` 为调用 `SettingsWindowManager.shared.toggleWindow()`
4. 添加右键菜单支持

```swift
// 移除
var popover: NSPopover!

// 修改 togglePopover
@objc func togglePopover(sender: AnyObject?) {
    SettingsWindowManager.shared.toggleWindow()
}

// 修改 createTrayIcon
func createTrayIcon() {
    // ... 现有代码 ...
    
    // 添加右键菜单
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "打开主界面", action: #selector(showSettings), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
    statusItem?.menu = menu
}

@objc func showSettings() {
    SettingsWindowManager.shared.showWindow()
}
```

#### 步骤 5：调整 Popover.swift

**变更内容**：
1. 保留 NewView、RenameView、DuplicateView、GridEditorView 等子视图
2. 移除 TrayPopupView（不再需要）
3. 将 Main 视图重构为可复用的组件

---

## 三、测试用例

### 3.0 构建测试（优先级：最高）

**每次代码变更后必须执行**：

```bash
# 构建项目并捕获错误
xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones build 2>&1 | tee build.log

# 检查构建结果
if [ $? -eq 0 ]; then
    echo "✅ 构建成功"
else
    echo "❌ 构建失败"
    # 提取错误信息
    grep "error:" build.log
fi
```

**构建测试检查清单**：

| ID | 检查项 | 预期结果 |
|----|--------|----------|
| B01 | 编译错误 | 无错误 |
| B02 | 警告 | 无新增警告（或记录并评估） |
| B03 | 链接错误 | 无错误 |
| B04 | 资源缺失 | 所有资源文件存在 |

**错误自动分析**：
- 构建失败时，自动提取 `error:` 和 `warning:` 行
- 分析错误类型：语法错误、类型不匹配、缺失符号等
- 提供修复建议

---

### 3.1 基本功能测试

| ID | 测试项 | 操作步骤 | 预期结果 |
|----|--------|----------|----------|
| T01 | 窗口显示 | 点击菜单栏图标 | 窗口出现在鼠标所在屏幕中央 |
| T02 | 窗口聚焦 | 窗口已显示时再次点击图标 | 窗口获得焦点 |
| T03 | 窗口关闭 | 点击左上角关闭按钮 | 窗口隐藏，配置不保存 |
| T04 | 确定保存 | 修改配置后点击确定 | 配置保存，窗口关闭 |
| T05 | 取消修改 | 修改配置后点击取消 | 配置恢复原状，窗口关闭 |

### 3.2 多屏幕测试

| ID | 测试项 | 操作步骤 | 预期结果 |
|----|--------|----------|----------|
| T06 | 屏幕切换 | 点击不同的屏幕 Tab | 显示对应屏幕的配置 |
| T07 | 独立配置 | 为屏幕1和屏幕2设置不同布局 | 各屏幕配置独立保存 |
| T08 | 跨屏保存 | 切换多个屏幕修改后点确定 | 所有屏幕的修改都保存 |

### 3.3 脏状态测试

| ID | 测试项 | 操作步骤 | 预期结果 |
|----|--------|----------|----------|
| T09 | 无修改关闭 | 不修改任何配置直接关闭 | 无任何副作用 |
| T10 | 修改后关闭 | 修改配置后关闭窗口 | 配置不保存 |
| T11 | 修改后确定 | 修改配置后点确定 | 配置保存 |
| T12 | 切换Tab保留 | 修改屏幕1后切到屏幕2 | 屏幕1的修改保留在内存 |

### 3.4 边界情况测试

| ID | 测试项 | 操作步骤 | 预期结果 |
|----|--------|----------|----------|
| T13 | 单屏幕 | 只有一个显示器时 | 隐藏屏幕选择Tab |
| T14 | 热插拔 | 使用中拔掉外接显示器 | 界面正确更新 |
| T15 | 重复打开 | 快速多次点击图标 | 窗口行为正常 |

### 3.5 右键菜单测试

| ID | 测试项 | 操作步骤 | 预期结果 |
|----|--------|----------|----------|
| T16 | 打开主界面 | 右键图标选择"打开主界面" | 窗口显示 |
| T17 | 退出 | 右键图标选择"退出" | 应用退出 |

### 3.6 布局编辑器测试

| ID | 测试项 | 操作步骤 | 预期结果 |
|----|--------|----------|----------|
| T18 | 编辑布局 | 在设置窗口中点击编辑布局 | 布局编辑器正常打开 |
| T19 | 共存 | 设置窗口和编辑器同时打开 | 两个窗口互不影响 |

---

## 四、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 配置丢失 | 高 | 保存前备份原配置 |
| 多屏幕检测失败 | 中 | 降级到单屏幕模式 |
| 窗口内存泄漏 | 低 | 使用单例模式，复用窗口 |

---

## 五、工作量估算

| 步骤 | 工作量 | 说明 |
|------|--------|------|
| SettingsState | 2小时 | 临时状态管理 |
| SettingsView | 3小时 | UI 重构 |
| SettingsWindowManager | 1小时 | 窗口管理 |
| App.swift 修改 | 1小时 | 集成测试 |
| 测试 | 2小时 | 功能测试 |
| **总计** | **9小时** | - |

---

## 六、测试执行流程

### 6.1 开发阶段测试流程

```
┌─────────────────────────────────────────────────────────────┐
│                     开发迭代流程                            │
├─────────────────────────────────────────────────────────────┤
│  1. 编写/修改代码                                           │
│           │                                                 │
│           ▼                                                 │
│  2. 执行构建测试 (xcodebuild build)                         │
│           │                                                 │
│     ┌─────┴─────┐                                           │
│     ▼           ▼                                           │
│  成功         失败                                          │
│     │           │                                           │
│     │           ▼                                           │
│     │      3. 分析错误日志                                   │
│     │           │                                           │
│     │           ▼                                           │
│     │      4. 修复错误                                       │
│     │           │                                           │
│     │           └───────► 返回步骤 2                        │
│     ▼                                                       │
│  5. 执行功能测试                                            │
│           │                                                 │
│     ┌─────┴─────┐                                           │
│     ▼           ▼                                           │
│  通过        失败                                           │
│     │           │                                           │
│     │           ▼                                           │
│     │      6. 修复问题                                      │
│     │           │                                           │
│     │           └───────► 返回步骤 2                        │
│     ▼                                                       │
│  7. 提交代码                                               │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 构建测试命令

```bash
# 基本构建
xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones build

# 清理后构建（确保无缓存影响）
xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones clean build

# 详细输出（用于调试）
xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones build -verbose
```

### 6.3 错误日志分析

**常见错误类型及处理**：

| 错误类型 | 特征 | 处理方式 |
|----------|------|----------|
| 语法错误 | `expected ';'` 等 | 检查代码语法 |
| 类型不匹配 | `cannot convert type` | 检查变量类型 |
| 缺失符号 | `use of unresolved identifier` | 检查变量/函数名 |
| 未使用变量 | `unused variable` | 删除或使用变量 |
| 强制解包 | `unexpectedly found nil` | 添加可选绑定 |

**日志提取脚本**：

```bash
#!/bin/bash
# build-and-analyze.sh

LOG_FILE="build.log"
xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones build 2>&1 | tee $LOG_FILE

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ 构建失败，错误信息："
    echo "=============================="
    grep -E "error:|warning:" $LOG_FILE | head -20
    echo "=============================="
    
    # 统计错误数量
    ERROR_COUNT=$(grep -c "error:" $LOG_FILE)
    WARNING_COUNT=$(grep -c "warning:" $LOG_FILE)
    
    echo "错误数: $ERROR_COUNT"
    echo "警告数: $WARNING_COUNT"
    exit 1
else
    echo "✅ 构建成功"
    WARNING_COUNT=$(grep -c "warning:" $LOG_FILE)
    if [ $WARNING_COUNT -gt 0 ]; then
        echo "⚠️  有 $WARNING_COUNT 个警告"
    fi
    exit 0
fi
```

### 6.4 测试验证清单

**构建测试**（每次变更后）：
- [ ] 编译无错误
- [ ] 无新增警告
- [ ] 链接成功

**功能测试**（完成一个功能模块后）：
- [ ] 基本功能正常
- [ ] 边界情况处理正确
- [ ] 无崩溃

**集成测试**（所有功能完成后）：
- [ ] 所有测试用例通过
- [ ] 性能可接受
- [ ] 内存无泄漏
