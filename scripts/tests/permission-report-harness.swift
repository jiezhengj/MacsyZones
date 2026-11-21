// T032 自动化桩：构造 PermissionDiagnosticReport 并按生产端同一编码器（pretty + sortedKeys）
// 写 /tmp/m003-report.json，供 quickstart.md「五、诊断报告」的逐字段校验脚本消费。
// 说明：本桩在命令行运行，Bundle.main 不指向 App bundle，makeAppInfo() 的
// bundleID/teamID/version 会取到缺省值。为了与真实报告同源又不伪造数据，
// App 段从验证副本（~/Applications/MacsyZones-dbg.app）的 Info.plist 实读
// 版本/Build/路径，bundleID 取该 Info.plist 的 CFBundleIdentifier，teamID 用
// AGENTS.md 固定的签名 Team 常量（运行中的 App 由 SecCode 从签名读取同一值）。
// System 段仍直接调用 PermissionCenter.makeSystemInfo()（与真实报告同源）。

import Foundation

@MainActor
func m003MakeHarnessReport() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let now = formatter.string(from: Date())

    let artifactPath = NSString(string: "~/Applications/MacsyZones-dbg.app").expandingTildeInPath
    let bundle = Bundle(url: URL(fileURLWithPath: artifactPath))
    let info = bundle?.infoDictionary ?? [:]
    let app = AppInfo(
        marketingVersion: (info["CFBundleShortVersionString"] as? String) ?? "0",
        build: (info["CFBundleVersion"] as? String) ?? "0",
        bundleID: bundle?.bundleIdentifier ?? "MeowingCat.MacsyZones",
        teamID: "74FR87HYTH",
        path: artifactPath,
        isTranslocated: artifactPath.contains("/AppTranslocation/"),
        isLoginItem: false
    )

    let probes: [PermissionProbe] = [
        PermissionProbe(id: "frontmost", target: "com.apple.finder", axError: -25211, status: .denied, latencyMs: 42),
        PermissionProbe(id: "finder", target: "com.apple.finder", axError: -25211, status: .denied, latencyMs: 38),
        PermissionProbe(id: "api", target: "system", axError: nil, status: .denied, latencyMs: 0),
    ]
    let capabilities: [PermissionDiagnosticCapability] = [
        PermissionDiagnosticCapability(id: "windowControl", status: "denied", lastCheckedAt: now,
                                       probes: probes, lastError: nil, trigger: "launch"),
        PermissionDiagnosticCapability(id: "inputMonitoring", status: "denied", lastCheckedAt: now,
                                       probes: [PermissionProbe(id: "preflight", target: "system", axError: nil, status: .denied, latencyMs: 1)],
                                       lastError: nil, trigger: "launch"),
        PermissionDiagnosticCapability(id: "eventPosting", status: "notRequired", lastCheckedAt: now,
                                       probes: [], lastError: nil, trigger: "launch"),
    ]
    let report = PermissionDiagnosticReport(
        schemaVersion: 1,
        generatedAt: now,
        app: app,
        system: PermissionCenter.makeSystemInfo(),
        capabilities: capabilities,
        notes: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! encoder.encode(report)
    try! data.write(to: URL(fileURLWithPath: "/tmp/m003-report.json"))
    print("harness: 报告已生成 /tmp/m003-report.json")
}

// 顶层执行体：挂到主 actor 后调用（makeSystemInfo 为 @MainActor static）。
Task { @MainActor in
    m003MakeHarnessReport()
    exit(0)
}
dispatchMain()
