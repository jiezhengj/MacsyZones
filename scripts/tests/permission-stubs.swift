import Foundation

// 权限模型断言桩（T012）：只提供被抽取纯函数所需的类型定义，不 import AppKit。
// PermissionRules 的真实函数体由 scripts/check_permission_model.sh 用 awk 从
// MacsyZones/PermissionCenter.swift 抽取拼接（R15），此处不含任何业务逻辑副本。

// 三态权限状态（与 PermissionCenter.swift 定义同形）。
enum PermissionStatus: String, Equatable, Sendable {
    case granted, denied, unknown, notRequired
}

// 引导面板（与 PermissionGuidance.swift 定义同形）。
enum PermissionGuidancePane: String, Equatable, Sendable {
    case systemProtectionOverride, accessibilityApps, legacyAccessibility, privacyRoot
}

// 引导目标（与 PermissionGuidance.swift 定义同形）。
struct GuidanceTarget: Equatable, Sendable {
    let pane: PermissionGuidancePane
    let url: URL
    let panelTitle: String
    let steps: [String]
}

// 单条探针记录（与 PermissionCenter.swift 定义同形；断言只用到字段存在性）。
struct PermissionProbe: Equatable, Sendable {
    let id: String
    let target: String
    let axError: Int?
    let status: PermissionStatus
    let latencyMs: Int
}

// 单能力状态（与 PermissionCenter.swift 定义同形；断言只用到字段存在性）。
struct CapabilityState: Sendable {
    let capability: String
    var status: PermissionStatus
    var lastCheckedAt: Date
    var lastChangedAt: Date
    var trigger: String
    var probes: [PermissionProbe]
    var lastError: String?
    var suspectUntil: Date?
}
