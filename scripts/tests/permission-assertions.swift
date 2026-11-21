// 权限模型断言（T013）：对 awk 抽取出的真实 PermissionRules / PermissionGuidance
// 纯函数逐条断言（R2 七行汇总、R1 三态映射、R4 宽限边界、R3 面板映射与深链契约）。
// 断言失败即 fatalError("FAIL: …")，成功末尾打印 PASS: 权限模型断言通过（N assertions）。

var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    checks += 1
}

// MARK: - 窗口控制汇总（R2 七行表）

// 任一 granted → granted
expect(PermissionRules.summarizeWindowControl(frontmost: .granted, finder: .granted) == .granted, "g+g 应为 granted")
expect(PermissionRules.summarizeWindowControl(frontmost: .granted, finder: .denied) == .granted, "g+d 应为 granted（部分受控不报未授权）")
expect(PermissionRules.summarizeWindowControl(frontmost: .denied, finder: .granted) == .granted, "d+g 应为 granted（部分受控不报未授权）")
expect(PermissionRules.summarizeWindowControl(frontmost: .granted, finder: .unknown) == .granted, "g+u 应为 granted")
expect(PermissionRules.summarizeWindowControl(frontmost: .unknown, finder: .granted) == .granted, "u+g 应为 granted")
// 双 denied → denied
expect(PermissionRules.summarizeWindowControl(frontmost: .denied, finder: .denied) == .denied, "d+d 应为 denied")
// 含 unknown 的其余组合 → unknown
expect(PermissionRules.summarizeWindowControl(frontmost: .denied, finder: .unknown) == .unknown, "d+u 应为 unknown")
expect(PermissionRules.summarizeWindowControl(frontmost: .unknown, finder: .denied) == .unknown, "u+d 应为 unknown")
expect(PermissionRules.summarizeWindowControl(frontmost: .unknown, finder: .unknown) == .unknown, "u+u 应为 unknown")

// 部分目标标注（FR-014：只进诊断 notes，不把部分受控报成未授权）
expect(PermissionRules.partialTargets(frontmost: .granted, finder: .denied) == ["finder"], "g+d 应标注 finder 部分受控")
expect(PermissionRules.partialTargets(frontmost: .denied, finder: .granted) == ["frontmost"], "d+g 应标注 frontmost 部分受控")
expect(PermissionRules.partialTargets(frontmost: .granted, finder: .granted).isEmpty, "g+g 无部分受控标注")
expect(PermissionRules.partialTargets(frontmost: .unknown, finder: .unknown).isEmpty, "u+u 无部分受控标注")

// MARK: - AXError 三态映射（R1/R2）

expect(PermissionRules.probeStatus(fromAXError: 0, timedOut: false, targetMissing: false) == .granted, "AXError 0 应为 granted")
expect(PermissionRules.probeStatus(fromAXError: -25211, timedOut: false, targetMissing: false) == .denied, "AXError -25211（kAXErrorAPIDisabled）应为 denied")
expect(PermissionRules.probeStatus(fromAXError: -25204, timedOut: false, targetMissing: false) == .unknown, "AXError -25204 应为 unknown")
expect(PermissionRules.probeStatus(fromAXError: 0, timedOut: true, targetMissing: false) == .unknown, "探针超时应为 unknown")
expect(PermissionRules.probeStatus(fromAXError: 0, timedOut: false, targetMissing: true) == .unknown, "探针目标缺失应为 unknown")
expect(PermissionRules.probeStatus(fromAXError: -25299, timedOut: false, targetMissing: false) == .unknown, "其他错误码应为 unknown")

// MARK: - 宽限边界（R4：仅登录期 60 秒内 granted→denied 可疑）

expect(PermissionRules.shouldEnterGrace(previous: .granted, probe: .denied, secondsSinceLaunch: 59) == true, "距启动 59 秒的 granted→denied 应进宽限")
expect(PermissionRules.shouldEnterGrace(previous: .granted, probe: .denied, secondsSinceLaunch: 60) == false, "距启动 60 秒整不进宽限（<60 才可疑）")
expect(PermissionRules.shouldEnterGrace(previous: .granted, probe: .denied, secondsSinceLaunch: 61) == false, "距启动 61 秒的 granted→denied 应立即生效")
expect(PermissionRules.shouldEnterGrace(previous: .denied, probe: .denied, secondsSinceLaunch: 10) == false, "前态 denied 不进宽限")
expect(PermissionRules.shouldEnterGrace(previous: .granted, probe: .granted, secondsSinceLaunch: 10) == false, "前态 granted 且本次 granted 不进宽限")
expect(PermissionRules.shouldEnterGrace(previous: .granted, probe: .unknown, secondsSinceLaunch: 10) == false, "前态 granted 且本次 unknown 不进宽限")

// MARK: - 面板映射（R3：minorVersion >= 3 分界，禁 #available）

expect(PermissionGuidance.primaryPane(forMinor: 2) == .legacyAccessibility, "minor 2 首选 legacyAccessibility")
expect(PermissionGuidance.primaryPane(forMinor: 0) == .legacyAccessibility, "minor 0 首选 legacyAccessibility")
expect(PermissionGuidance.primaryPane(forMinor: 3) == .systemProtectionOverride, "minor 3 首选 systemProtectionOverride")
expect(PermissionGuidance.primaryPane(forMinor: 4) == .systemProtectionOverride, "minor 4 首选 systemProtectionOverride")
expect(PermissionGuidance.fallbackPane(forMinor: 2) == .privacyRoot, "minor 2 备选 privacyRoot")
expect(PermissionGuidance.fallbackPane(forMinor: 3) == .accessibilityApps, "minor 3 备选 accessibilityApps")

// T038：两套 pane 形态的边界值（minor 0 / 2 / 3 / 4 已覆盖，再补 minor 1 与负值容错）
expect(PermissionGuidance.primaryPane(forMinor: 1) == .legacyAccessibility, "minor 1 首选 legacyAccessibility")
expect(PermissionGuidance.fallbackPane(forMinor: 4) == .accessibilityApps, "minor 4 备选 accessibilityApps")

// T038：打开失败链路（真实函数 openOutcome 抽取执行）
// 契约：深链成功 → opened；深链失败但首页成功 → openedFallback；两次都失败 → 仅文字路径（failed）。
expect(PermissionGuidance.openOutcome(pane: .systemProtectionOverride, deepLinkOpened: true, rootOpened: false) == .opened(.systemProtectionOverride), "深链成功 → opened(pane)")
expect(PermissionGuidance.openOutcome(pane: .legacyAccessibility, deepLinkOpened: true, rootOpened: true) == .opened(.legacyAccessibility), "深链成功时不再打开首页 → opened(pane)")
expect(PermissionGuidance.openOutcome(pane: .accessibilityApps, deepLinkOpened: false, rootOpened: true) == .openedFallback, "深链失败首页成功 → openedFallback")
expect(PermissionGuidance.openOutcome(pane: .systemProtectionOverride, deepLinkOpened: false, rootOpened: false) == .failed, "27.3+ 两次失败 → failed（仅文字路径）")
expect(PermissionGuidance.openOutcome(pane: .legacyAccessibility, deepLinkOpened: false, rootOpened: false) == .failed, "27.0–27.2 两次失败 → failed（仅文字路径）")

// 深链契约（guidance-targets.md 表格逐行）
expect(PermissionGuidance.deepLinkString(for: .systemProtectionOverride) == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", "systemProtectionOverride 深链应与契约一致")
expect(PermissionGuidance.deepLinkString(for: .legacyAccessibility) == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", "legacyAccessibility 深链应与契约一致")
expect(PermissionGuidance.deepLinkString(for: .accessibilityApps) == "x-apple.systempreferences:com.apple.preference.security?Privacy_AccessibilityApps", "accessibilityApps 深链应与契约一致")
expect(PermissionGuidance.deepLinkString(for: .privacyRoot) == "x-apple.systempreferences:com.apple.preference.security", "privacyRoot 深链应与契约一致")

// 面板文案契约：27.3+ 必含「System & App Protection Override」，旧版必含「Device Control and Data Access」，备选面板必含「无障碍」
expect(PermissionGuidance.panelTitle(for: .systemProtectionOverride).contains("System & App Protection Override"), "systemProtectionOverride 面板标题应含 System & App Protection Override")
expect(PermissionGuidance.panelTitle(for: .legacyAccessibility).contains("Device Control and Data Access"), "legacyAccessibility 面板标题应含 Device Control and Data Access")
expect(PermissionGuidance.panelTitle(for: .accessibilityApps).contains("无障碍"), "accessibilityApps 面板标题应含「无障碍」")
expect(PermissionGuidance.steps(for: .systemProtectionOverride).contains { $0.contains("System & App Protection Override") }, "主面板步骤应含 System & App Protection Override")
expect(PermissionGuidance.steps(for: .systemProtectionOverride).contains { $0.contains("无障碍") }, "27.3+ 步骤应以「无障碍」为备选")
expect(PermissionGuidance.steps(for: .legacyAccessibility).contains { $0.contains("Device Control and Data Access") }, "27.0–27.2 步骤应含 Device Control and Data Access")
expect(!PermissionGuidance.steps(for: .accessibilityApps).contains { $0.contains("辅助功能") }, "文案禁用旧称「辅助功能」")
expect(!PermissionGuidance.steps(for: .systemProtectionOverride).contains { $0.contains("重启") }, "文案禁用「重启后继续」")

print("PASS: 权限模型断言通过（\(checks) assertions）")
