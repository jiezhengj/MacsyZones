# 数据模型：macOS 27 权限模型适配

**Feature**: `003-macos27-permissions` | **Date**: 2026-11-21

本 feature 不新增持久化实体。以下类型全部是运行时内存模型（`PermissionCenter.swift` / `PermissionGuidance.swift` 内定义），诊断报告是唯一需要序列化的结构。

## PermissionCapability

| 值 | 含义 | 判定来源 |
|---|---|---|
| `windowControl` | 控制其他 app 的窗口（读写 `kAXPositionAttribute` / `kAXSizeAttribute`） | AX 探针（R2） |
| `inputMonitoring` | 全局键盘监听（`keyDown`/`flagsChanged` 的 `NSEvent` 全局监视器） | `CGPreflightListenEventAccess()` |
| `eventPosting` | 合成并投递输入事件（`CGEvent.post` / event tap 回注） | 当前不用；固定 `notRequired` |

## PermissionStatus

| 值 | 含义 | 触发条件 |
|---|---|---|
| `granted` | 已授权且探针证实可用 | 探针返回 `.success` |
| `denied` | 系统明确拒绝 | 探针返回 `kAXErrorAPIDisabled (-25211)`；`CGPreflightListenEventAccess()` 为 false |
| `unknown` | 无法判定（系统未答复 / 探针目标缺失 / 超时） | 探针返回 `-25204`、其他 AXError、目标 app 不存在、超过 1s |
| `notRequired` | 本项目当前不需要该能力 | `eventPosting` |

## PermissionProbe

```swift
struct PermissionProbe {
    let id: String            // "frontmost" | "finder" | "api" | "preflight"
    let target: String        // bundle id 或 "system"
    let axError: Int?         // AXError rawValue；preflight 为 nil
    let status: PermissionStatus
    let latencyMs: Int
}
```

规则：一次窗口控制判定产生 2 条探针（`frontmost`、`finder`），另加 1 条 `api`（`AXIsProcessTrusted()`）作为参考；汇总规则见下。

## CapabilityState

```swift
struct CapabilityState {
    let capability: PermissionCapability
    var status: PermissionStatus
    var lastCheckedAt: Date
    var lastChangedAt: Date
    var trigger: String            // "launch" | "activate" | "wake" | "ax-failure" | "manual" | "poll"
    var probes: [PermissionProbe]
    var lastError: String?
    var suspectUntil: Date?        // 宽限窗口截止时间（R4）
}
```

不变式：

1. `status == .granted` 时 `probes` 中至少有一条 `windowControl` 探针为 `.success`，或 `inputMonitoring` 为 `preflight == true`。
2. `suspectUntil != nil` 期间对外仍报上一次的 `granted`，但 `isSuspect == true`（UI 只显示「检测中」，不报警）。
3. `status == .unknown` 时 `lastError` 必须非空（便于诊断报告解释原因）。
4. `lastChangedAt` 只在 `status` 真正变化时更新（用于避免 UI 闪烁）。

### 窗口控制汇总规则（由探针推导）

| frontmost | finder | api（仅参考） | 汇总结果 |
|---|---|---|---|
| success | success | 任意 | `granted` |
| success | apiDisabled | 任意 | `granted`（`partialTargets` 标注 finder 不可控） |
| apiDisabled | success | 任意 | `granted`（`partialTargets` 标注 frontmost 不可控） |
| success | unknown | 任意 | `granted`（另一目标无法判定，不据此降级） |
| apiDisabled | unknown | 任意 | `unknown` + `lastError`（无法区分全局拒绝与目标侧问题） |
| unknown | unknown | 任意 | `unknown` + `lastError` |
| apiDisabled | apiDisabled | 任意 | `denied` |

判定式的等价表述：**任一探针 `success` → `granted`；没有 `success` 且所有已完成的探针均为 `apiDisabled` → `denied`；其余组合 → `unknown`。** `api` 探针（`AXIsProcessTrusted()`）只进诊断报告，不改变汇总结果——espanso 的案例说明它可能与真实可用性相反。`partialTargets` 只写进诊断 `notes`，不改变 `granted` 判定（FR-014：不把部分受控报成未授权）。

## PermissionSnapshot

```swift
struct PermissionSnapshot {
    let generatedAt: Date
    let capabilities: [CapabilityState]
    let overall: PermissionStatus   // 取最严格的窗口控制状态；inputMonitoring 单独展示
    let system: SystemInfo
    let app: AppInfo
}

struct SystemInfo {                 // 与 contracts/permission-report.schema.json 的 system 段一一对应
    let productVersion: String      // ProcessInfo.operatingSystemVersion 转 "27.3"
    let build: String               // 系统 Build（如 26C5047e）
    let arch: String                // "arm64" | "x86_64"（uname -m 或 #if arch 之外的运行时判定）
}

struct AppInfo {                    // 与 schema 的 app 段一一对应
    let marketingVersion: String    // CFBundleShortVersionString，缺省 "0"
    let build: String               // CFBundleVersion，缺省 "0"
    let bundleID: String            // Bundle.main.bundleIdentifier ?? "unknown"
    let teamID: String              // 从签名信息读取失败时填 "unknown"（用 SecCode 或省略为 "unknown"）
    let path: String                // Bundle.main.bundlePath
    let isTranslocated: Bool        // path 含 "/AppTranslocation/"
    let isLoginItem: Bool           // 是否作为登录项启动（SMAppService/已注册登录项判定失败时 false）
}
```

`SystemInfo` 与 `AppInfo` 都必须显式定义：`PermissionSnapshot` 与诊断报告共用这两个类型，字段名与 `contracts/permission-report.schema.json` 的 `system.*` / `app.*` 完全一致，禁止在报告生成处另造同义字段名。

## PermissionCenter（`@MainActor final class PermissionCenter: ObservableObject`）

职责与约定：

- `static let shared`；`func start()` / `func stop()`；`@Published private(set) var snapshot: PermissionSnapshot`。
- `@Published private(set) var hasCompletedFirstCheck: Bool`：首轮探测（含全部能力）完成前为 false。所有「未授权才展示引导」的 UI 判定必须先等它为 true，否则已授权用户每次启动都会闪一次未授权引导。
- `var onStatusChange: ((PermissionCapability, PermissionStatus, PermissionStatus) -> Void)?`：状态迁移回调（主线程调用），供全局监视器按能力类型装/卸：`windowControl` 驱动鼠标类、`inputMonitoring` 驱动键盘类（见 R13）。
- `func recheck(trigger: String)`：合并并发请求（同一 trigger 1 秒内去重）；探针在 `DispatchQueue(label: "...permissions.probe", qos: .utility)` 执行，结果 `Task { @MainActor in }` 回写。
- `func reportAXFailure(_ error: AXError)`：仅当 `error == .apiDisabled` 时触发 `recheck(trigger: "ax-failure")`。
- 调度：启动 `+0s` 一次；`granted` 后 30s 轮询；非 `granted` 时 5s × 最多 24 次；由 `NSWorkspace.didActivateApplication`、`NSWorkspace.didWake`（均注册在 `NSWorkspace.shared.notificationCenter`）、设置窗口 `NSWindow.didBecomeKey`（注册在 `NotificationCenter.default`）、菜单栏点击、`reportAXFailure` 触发额外复核。`NSApplication.didBecomeActive` 在 `.prohibited` 激活策略下可能永不触发，只作可选补充（`MacsyZones/App.swift` 中 `NSApp.setActivationPolicy(.prohibited)`）。
- 生命周期：所有 `Timer`/`DispatchWorkItem` 在 `stop()` 与 `applicationWillTerminate` 中取消（与 002 的 `cancelPendingScans` 同款纪律）。

状态机（单个能力）：

```text
       ┌──────────┐  探针 granted   ┌─────────┐
       │ unknown  │ ───────────────▶│ granted │
       └────┬─────┘                 └────┬────┘
            │ 探针 denied                 │ 探针 denied（首次变化）
            ▼                             ▼
       ┌──────────┐                 ┌──────────────┐
       │  denied  │◀────────────────│ granted+可疑 │ 60s 宽限（R4）
       └────┬─────┘   宽限结束仍 denied └──────────────┘
            │ 探针 granted
            └──────────────▶ granted（立即，无宽限）
```

宽限规则：**仅登录期生效**——「上一次为 `granted`、本次探针为 `denied`、且距进程启动 < 60 秒」时进入可疑态（对外仍报 `granted`，`isSuspect == true`）；60 秒内恢复则当作抖动，超时仍 `denied` 才切换并提示。**距进程启动 ≥ 60 秒的 `granted → denied` 立即生效**，因为运行中撤销是用户的确定性操作（`quickstart.md` 场景 C 按此验收）。

## GuidanceTarget（`PermissionGuidance.swift`）

```swift
struct GuidanceTarget {
    enum Pane { case systemProtectionOverride, accessibilityApps, legacyAccessibility, privacyRoot }
    let pane: Pane
    let url: URL                // x-apple.systempreferences 深链
    let panelTitle: String      // 面向用户的中文标题
    let steps: [String]         // 分步说明（3 步以内）
}
```

选择规则（版本判定用 `ProcessInfo.processInfo.operatingSystemVersion.minor`，禁止 `#available`）：

| 系统 | 首选 pane | 兜底 pane |
|---|---|---|
| 27.3+ | `systemProtectionOverride`（`?Privacy_Accessibility`） | `accessibilityApps`（`?Privacy_AccessibilityApps`） |
| 27.0–27.2 | `legacyAccessibility`（`?Privacy_Accessibility`） | `privacyRoot`（`com.apple.preference.security`） |

## DiagnosticReport（诊断报告，序列化契约见 `contracts/permission-report.schema.json`）

```swift
struct PermissionDiagnosticReport: Codable {
    let schemaVersion: Int          // 固定 1
    let generatedAt: String         // ISO 8601，带时区
    let app: AppSection
    let system: SystemSection
    let capabilities: [CapabilitySection]
    let notes: [String]
}
```

字段要求：

- `app.marketingVersion` / `app.build` 来自 `Bundle.main`（`CFBundleShortVersionString` / `CFBundleVersion`）。
- `app.isTranslocated`：路径含 `/AppTranslocation/` 即 true（用户从下载目录直接运行时的重要线索）。
- `app.path` 在报告中以完整路径输出（用户主动复制，属可接受暴露）；但日志中必须 `.private`。
- `capabilities[].probes[].axError` 保留原始错误码（如 `-25211`），不翻译成人类可读文本，便于检索。
- 不包含：用户名、主机名、其他 app 的窗口标题、TCC 数据库内容、任何路径之外的隐私信息。

## 与现有模型的边界

- 不修改 `AppSettingsData`（无新字段）；不写 `AppSettings.json`/`UserLayouts.json`。
- 不复用 `macsyReady`（`MacsyZones/App.swift:23`）作为权限状态载体：`macsyReady.isReady` 表示「窗口观察就绪」，与权限是正交概念。
- `hasAccessibilityPermission`（`MacsyZones/App.swift:38`）在实现后删除。它的引用点是：写入 `MacsyZones/App.swift:742`（`AXIsProcessTrustedWithOptions` 结果）、读取 `MacsyZones/App.swift:627`（onboarding 条件）与 `:746`（是否展示引导）、调用 `:554`/`:555`（`:555` 是对 `requestAccessibilityPermissions()` 的间接调用，函数体在 `:745`）、定义 `:740`/`:745`。删除后这些位置全部改为读 `PermissionCenter.shared.snapshot`，`:554`/`:555` 两处改为 `PermissionCenter.shared.start()`。
