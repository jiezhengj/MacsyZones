//
// MacsyZones, macOS system utility for managing windows on your Mac.
//
// https://macsyzones.com
//
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
//
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

// 权限中心：macOS 27 的三能力（窗口控制 / 输入监听 / 事件发布）判定与状态机。
// 决策依据：specs/003-macos27-permissions/research.md（R1 三态、R2 真实探针汇总、
// R4 复核时机与 60 秒登录期宽限、R6 日志字段）与 specs/003-macos27-permissions/data-model.md。
// 约定：探针只读（不做任何 AX 写操作）；所有计时器/工作项记录在册并可取消；
// 状态只存内存，不写 AppSettings.json / UserDefaults（R11）。

import Foundation
import AppKit
import CoreGraphics
import Security
import ServiceManagement

// MARK: - 模型定义（data-model.md，字段名与 contracts/permission-report.schema.json 一致）

/// 权限能力（data-model.md「PermissionCapability」）。
enum PermissionCapability: String, CaseIterable, Sendable {
    /// 控制其他 app 的窗口（读写 kAXPositionAttribute / kAXSizeAttribute）。
    case windowControl
    /// 全局键盘监听（keyDown / flagsChanged 的 NSEvent 全局监视器）。
    case inputMonitoring
    /// 合成并投递输入事件；当前不用，固定 notRequired。
    case eventPosting
}

/// 三态权限状态（R1）：granted / denied / unknown，另有 notRequired。
enum PermissionStatus: String, Sendable {
    /// 已授权且探针证实可用（探针返回 .success）。
    case granted
    /// 系统明确拒绝（kAXErrorAPIDisabled / preflight 为 false）。
    case denied
    /// 无法判定（-25204、其他错误、目标缺失、超过 1 秒）。
    case unknown
    /// 本项目当前不需要该能力（eventPosting）。
    case notRequired
}

/// 单条探针记录（data-model.md「PermissionProbe」）。
struct PermissionProbe: Sendable {
    /// 探针标识："frontmost" | "finder" | "api" | "preflight"。
    let id: String
    /// 探针目标：bundle id 或 "system"。
    let target: String
    /// AXError rawValue；preflight 为 nil。
    let axError: Int?
    let status: PermissionStatus
    /// 探针耗时（毫秒）；冒烟契约要求窗口控制探针 < 1000。
    let latencyMs: Int
}

/// 单能力状态（data-model.md「CapabilityState」）。
struct CapabilityState: Sendable {
    let capability: PermissionCapability
    var status: PermissionStatus
    var lastCheckedAt: Date
    var lastChangedAt: Date
    /// "launch" | "activate" | "wake" | "ax-failure" | "manual" | "poll"
    var trigger: String
    var probes: [PermissionProbe]
    /// unknown 时必须非空（不变式 3）。
    var lastError: String?
    /// 60 秒登录期宽限窗口截止时间（R4；nil 表示不在可疑态）。
    var suspectUntil: Date?
}

/// 系统信息（schema 的 system.* 段一一对应）。
struct SystemInfo: Sendable {
    /// ProcessInfo.operatingSystemVersion 转 "27.3"。
    let productVersion: String
    /// 系统 Build（如 26C5047e），解析失败为 "unknown"。
    let build: String
    /// "arm64" | "x86_64"（uname 运行时判定）。
    let arch: String
}

/// App 信息（schema 的 app.* 段一一对应）。
struct AppInfo: Sendable {
    /// CFBundleShortVersionString，缺省 "0"。
    let marketingVersion: String
    /// CFBundleVersion，缺省 "0"。
    let build: String
    /// Bundle.main.bundleIdentifier，缺省 "unknown"。
    let bundleID: String
    /// 签名 Team ID，读取失败为 "unknown"。
    let teamID: String
    /// Bundle.main.bundlePath（报告中完整输出；日志中用 .private）。
    let path: String
    /// path 含 "/AppTranslocation/" 即 true。
    let isTranslocated: Bool
    /// 是否作为登录项启动（SMAppService 判定失败时 false）。
    let isLoginItem: Bool
}

/// 一次完整判定的快照。
struct PermissionSnapshot: Sendable {
    let generatedAt: Date
    /// 三个能力的当前状态，顺序与 PermissionCapability.allCases 一致。
    let capabilities: [CapabilityState]
    /// 取最严格的窗口控制状态；inputMonitoring 单独展示。
    let overall: PermissionStatus
    let system: SystemInfo
    let app: AppInfo
}

// MARK: - 纯判定函数（R15 抽取目标）

/// 窗口控制汇总与宽限判定的纯函数集合。
/// 注意：这些函数会被 scripts/check_permission_model.sh 用 awk 逐个抽取后
/// 在纯 Foundation 环境执行（R15），因此内部大括号必须保持单行风格，
/// 且只依赖 PermissionStatus / 基础类型，不引用 AppKit。
enum PermissionRules {
    /// 60 秒登录期宽限窗口（R4）。与 shouldEnterGrace 内的 60.0 必须一致。
    static let graceWindowSeconds: TimeInterval = 60.0

    /// 窗口控制汇总规则（data-model.md「窗口控制汇总规则」7 行）：
    /// 任一探针 success（此处建模为 .granted）→ granted；
    /// 没有 success 且所有已完成的探针均为 apiDisabled（.denied）→ denied；
    /// 其余（.unknown 组合）→ unknown。
    static func summarizeWindowControl(frontmost: PermissionStatus, finder: PermissionStatus) -> PermissionStatus {
        if frontmost == .granted { return .granted }
        if finder == .granted { return .granted }
        if frontmost == .denied && finder == .denied { return .denied }
        return .unknown
    }

    /// 「部分目标受控」标注（FR-014：不把部分失败报成未授权，只进诊断 notes）。
    static func partialTargets(frontmost: PermissionStatus, finder: PermissionStatus) -> [String] {
        if frontmost == .granted && finder == .denied { return ["finder"] }
        if frontmost == .denied && finder == .granted { return ["frontmost"] }
        return []
    }

    /// AXError → 三态映射（R2）：0 → granted；-25211（kAXErrorAPIDisabled）→ denied；
    /// -25204（kAXErrorCannotComplete）、其他错误、探针超时、目标缺失 → unknown。
    static func probeStatus(fromAXError axError: Int, timedOut: Bool, targetMissing: Bool) -> PermissionStatus {
        if timedOut || targetMissing { return .unknown }
        if axError == 0 { return .granted }
        if axError == -25211 { return .denied }
        return .unknown
    }

    /// 宽限进入条件（R4）：仅登录期生效——上一次 granted、本次探针 denied、
    /// 且距本进程启动 < 60 秒。60 秒边界之外（含等于 60 秒）不进宽限，
    /// granted → denied 立即生效（运行中撤销是用户的确定性操作）。
    static func shouldEnterGrace(previous: PermissionStatus, probe: PermissionStatus, secondsSinceLaunch: TimeInterval) -> Bool {
        previous == .granted && probe == .denied && secondsSinceLaunch < 60.0
    }
}

// MARK: - 探针结果传递（跨线程一次性投递）

/// 单条探针的跨线程结果盒：先完成者胜出，保证每条探针恰好投递一次。
private final class ProbeOutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var value: (axError: Int?, status: PermissionStatus)?

    /// 记录结果；返回是否由本次调用首次写入（只投递一次）。
    func set(axError: Int?, status: PermissionStatus) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        value = (axError, status)
        return true
    }

    var read: (axError: Int?, status: PermissionStatus)? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

// MARK: - PermissionCenter

/// 三能力权限中心（@MainActor，生命周期与 app 一致）。
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    /// 最近一次完整判定的快照；start() 前为 nil。
    @Published private(set) var snapshot: PermissionSnapshot?

    /// 首轮探测（含全部能力）完成前为 false。所有「未授权才展示引导」的
    /// UI 判定必须先等它为 true，否则已授权用户每次启动都会闪一次引导。
    @Published private(set) var hasCompletedFirstCheck = false

    /// 状态迁移回调（主线程调用），供全局监视器按能力类型装/卸（R13）：
    /// windowControl 驱动鼠标类、inputMonitoring 驱动键盘类。
    var onStatusChange: ((PermissionCapability, PermissionStatus, PermissionStatus) -> Void)?

    /// 探针专用队列（utility，1 秒超时不阻塞主线程）。
    private let probeQueue = DispatchQueue(label: "MeowingCat.MacsyZones.permissions.probe", qos: .utility)

    /// 进程启动时刻（宽限窗口以它为基准）。
    private let launchedAt = Date()

    /// 内存中的能力状态（R11：不持久化）。
    private var capabilities: [PermissionCapability: CapabilityState] = [:]

    // 复核调度（T008）：所有计时器/工作项记录在册并可取消。
    private var pollWorkItem: DispatchWorkItem?
    private var graceWorkItem: DispatchWorkItem?
    /// 非 granted 状态下已执行的 5 秒轮询次数（最多 24 次）。
    private var pollCount = 0
    /// 同一 trigger 1 秒内的去重记录。
    private var lastTriggerAt: [String: Date] = [:]
    /// 当前是否有探针批次在执行（进行中则合并新请求）。
    private var batchInFlight = false
    /// 系统通知观察者（stop() 时统一移除）。
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultCenterObservers: [NSObjectProtocol] = []

    private init() {}

    // MARK: 生命周期

    /// 启动：注册系统触发源并立即做首轮判定（R4：启动完成后 +0s）。
    func start() {
        registerSystemTriggers()
        recheck(trigger: "launch")
    }

    /// 停止：取消全部计时器/工作项并移除观察者（applicationWillTerminate 调用）。
    func stop() {
        cancelTimers()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        for token in defaultCenterObservers { NotificationCenter.default.removeObserver(token) }
        defaultCenterObservers.removeAll()
    }

    /// 取消轮询与宽限计时（不取消通知观察者）。
    func cancelTimers() {
        pollWorkItem?.cancel()
        pollWorkItem = nil
        graceWorkItem?.cancel()
        graceWorkItem = nil
    }

    /// 注册复核触发源（R4）：工作区激活/唤醒、任意 key 窗口成为关键窗。
    /// NSApplication.didBecomeActive 在 .prohibited 激活策略下可能永不触发，
    /// 故不依赖它。菜单栏点击与诊断面板的「重新检测」由调用方触发 manual。
    private func registerSystemTriggers() {
        guard workspaceObservers.isEmpty && defaultCenterObservers.isEmpty else { return }

        let activateToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck(trigger: "activate") }
        }
        workspaceObservers.append(activateToken)

        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck(trigger: "wake") }
        }
        workspaceObservers.append(wakeToken)

        let keyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck(trigger: "activate") }
        }
        defaultCenterObservers.append(keyToken)
    }

    // MARK: 复核入口

    /// 复核入口：同一 trigger 1 秒内去重；探针批次进行中则合并请求（T008）。
    /// trigger 取值：launch / activate / wake / ax-failure / manual / poll。
    func recheck(trigger: String) {
        let now = Date()
        if let last = lastTriggerAt[trigger], now.timeIntervalSince(last) < 1.0 { return }
        lastTriggerAt[trigger] = now
        guard !batchInFlight else { return }

        // 硬触发（非 poll）重置 5 秒轮询计数，让未授权状态重新获得完整重试窗口。
        if trigger != "poll" { pollCount = 0 }

        batchInFlight = true
        runProbeBatch(trigger: trigger)
    }

    /// WindowObserverManager 的 AX 失败路径上报入口：仅 apiDisabled 触发即时复核（R4）。
    func reportAXFailure(_ error: AXError) {
        guard error == .apiDisabled else { return }
        recheck(trigger: "ax-failure")
    }

    // MARK: 探针执行（T006 / T007）

    /// 在探针队列执行一批探针：窗口控制三条（frontmost / finder / api）+
    /// 输入监听一条（preflight）。每条独立 1 秒超时；事件发布不探针（固定 notRequired）。
    private func runProbeBatch(trigger: String) {
        probeQueue.async { [weak self] in
            let frontmostProbe = Self.frontmostProbe()
            let finderProbe = Self.finderProbe()
            let apiProbe = Self.apiProbe()
            let preflightProbe = Self.preflightProbe()

            Task { @MainActor in
                self?.finishBatch(
                    trigger: trigger,
                    probes: [frontmostProbe, finderProbe, apiProbe, preflightProbe]
                )
            }
        }
    }

    /// 单探针包装：把可能阻塞的 AX 读取放到全局队列，主等待线程最多等 timeout 秒，
    /// 超时即产出 unknown（latencyMs 记录实际等待时长），不阻塞批次的其余探针。
    private nonisolated static func guardedProbe(
        id: String, target: String, timeout: TimeInterval,
        work: @escaping () -> (axError: Int?, status: PermissionStatus)
    ) -> PermissionProbe {
        let startedAt = DispatchTime.now()
        let box = ProbeOutcomeBox()
        DispatchQueue.global(qos: .utility).async {
            let outcome = work()
            _ = box.set(axError: outcome.axError, status: outcome.status)
        }
        let semaphore = DispatchSemaphore(value: 0)
        // 唤醒辅助：工作完成后发信号；等待线程最多等 timeout。
        DispatchQueue.global(qos: .utility).async {
            // 轮询等待一次性结果，最多 timeout（由 box 保证只取首值）。
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if box.read != nil { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout + 0.2)
        let latencyMs = Int(
            Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000.0
        )
        if let outcome = box.read {
            return PermissionProbe(id: id, target: target, axError: outcome.axError, status: outcome.status, latencyMs: latencyMs)
        }
        // 超时：中断并记 unknown（R2 风险兜底）。
        return PermissionProbe(id: id, target: target, axError: nil, status: .unknown, latencyMs: latencyMs)
    }

    /// frontmost 探针：当前前台 app 读一次 kAXWindowsAttribute（只读，无副作用）。
    private nonisolated static func frontmostProbe() -> PermissionProbe {
        let app = NSWorkspace.shared.frontmostApplication
        let target = app?.bundleIdentifier ?? "system"
        guard let pid = app?.processIdentifier, pid > 0 else {
            // 目标缺失：记 unknown（不降级为纯 API 判定）。
            return PermissionProbe(id: "frontmost", target: target, axError: nil,
                                   status: PermissionRules.probeStatus(fromAXError: 0, timedOut: false, targetMissing: true),
                                   latencyMs: 0)
        }
        let element = AXUIElementCreateApplication(pid)
        return guardedProbe(id: "frontmost", target: target, timeout: 1.0) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
            return (axError: Int(error.rawValue), status: PermissionRules.probeStatus(fromAXError: Int(error.rawValue), timedOut: false, targetMissing: false))
        }
    }

    /// finder 探针：com.apple.finder 读一次 kAXWindowsAttribute（Finder 几乎总在运行，
    /// 且不受 WebKit 已知问题影响）。
    private nonisolated static func finderProbe() -> PermissionProbe {
        let finder = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }
        let target = "com.apple.finder"
        guard let pid = finder?.processIdentifier, pid > 0 else {
            return PermissionProbe(id: "finder", target: target, axError: nil,
                                   status: PermissionRules.probeStatus(fromAXError: 0, timedOut: false, targetMissing: true),
                                   latencyMs: 0)
        }
        let element = AXUIElementCreateApplication(pid)
        return guardedProbe(id: "finder", target: target, timeout: 1.0) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
            return (axError: Int(error.rawValue), status: PermissionRules.probeStatus(fromAXError: Int(error.rawValue), timedOut: false, targetMissing: false))
        }
    }

    /// api 探针：AXIsProcessTrusted() 仅作诊断参考，不参与汇总（espanso 案例证明
    /// API 结论可能与真实可用性相反）。
    private nonisolated static func apiProbe() -> PermissionProbe {
        let startedAt = DispatchTime.now()
        let trusted = AXIsProcessTrusted()
        let latencyMs = Int(
            Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000.0
        )
        return PermissionProbe(id: "api", target: "system", axError: nil,
                               status: trusted ? .granted : .denied, latencyMs: latencyMs)
    }

    /// preflight 探针：CGPreflightListenEventAccess() 直接判定输入监听（R2）。
    private nonisolated static func preflightProbe() -> PermissionProbe {
        let startedAt = DispatchTime.now()
        let allowed = CGPreflightListenEventAccess()
        let latencyMs = Int(
            Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000.0
        )
        return PermissionProbe(id: "preflight", target: "system", axError: nil,
                               status: allowed ? .granted : .denied, latencyMs: latencyMs)
    }

    // MARK: 结果回写与状态机（T007 / T009）

    /// 批次回写（主线程）：逐条记探针日志 → 汇总 → 宽限状态机 → 发布快照 → 调度下一轮。
    private func finishBatch(trigger: String, probes: [PermissionProbe]) {
        batchInFlight = false
        let now = Date()
        let frontmost = probes.first { $0.id == "frontmost" }
        let finder = probes.first { $0.id == "finder" }
        let preflight = probes.first { $0.id == "preflight" }

        // 逐条探针日志（R6 / 冒烟契约：每条记录都带 latencyMs=）。
        for probe in probes {
            permissionLogRecord(
                capability: PermissionCapability.windowControl.rawValue,
                id: probe.id,
                target: probe.target,
                status: probe.status.rawValue,
                axError: probe.axError,
                latencyMs: probe.latencyMs,
                trigger: trigger
            )
        }

        // 窗口控制：汇总 + 宽限状态机。
        let windowControlMaxLatency = probes
            .filter { $0.id != "preflight" }
            .map { $0.latencyMs }
            .max() ?? 0
        let summarized = PermissionRules.summarizeWindowControl(
            frontmost: frontmost?.status ?? .unknown,
            finder: finder?.status ?? .unknown
        )
        let partialTargets = PermissionRules.partialTargets(
            frontmost: frontmost?.status ?? .unknown,
            finder: finder?.status ?? .unknown
        )
        let windowState = applyStateMachine(
            capability: .windowControl,
            summarized: summarized,
            probes: probes.filter { $0.id != "preflight" },
            partialTargets: partialTargets,
            trigger: trigger,
            now: now,
            logLatencyMs: windowControlMaxLatency
        )
        capabilities[.windowControl] = windowState

        // 输入监听：preflight 直接判定，不进宽限状态机（preflight 是同步布尔，无抖动源）。
        let inputStatus = preflight?.status ?? .unknown
        let inputLastError: String? = inputStatus == .unknown ? "preflight 探针超时或缺失" : nil
        let inputState = commitState(
            capability: .inputMonitoring,
            newStatus: inputStatus,
            probes: [preflight].compactMap { $0 },
            lastError: inputLastError,
            suspectUntil: nil,
            trigger: trigger,
            now: now,
            logLatencyMs: preflight?.latencyMs ?? 0,
            notes: nil
        )
        capabilities[.inputMonitoring] = inputState

        // 事件发布：固定 notRequired，不探针（data-model.md）。
        let eventState = commitState(
            capability: .eventPosting,
            newStatus: .notRequired,
            probes: [],
            lastError: nil,
            suspectUntil: nil,
            trigger: trigger,
            now: now,
            logLatencyMs: 0,
            notes: "当前不需要该能力"
        )
        capabilities[.eventPosting] = eventState

        // 首轮完成标记（T008）：全部能力均有状态后置 true。
        if !hasCompletedFirstCheck, PermissionCapability.allCases.allSatisfy({ capabilities[$0] != nil }) {
            hasCompletedFirstCheck = true
        }

        // 发布快照（overall 取窗口控制的对外状态）。
        snapshot = PermissionSnapshot(
            generatedAt: now,
            capabilities: PermissionCapability.allCases.compactMap { capabilities[$0] },
            overall: windowState.status,
            system: Self.makeSystemInfo(),
            app: Self.makeAppInfo()
        )

        scheduleNextPoll(externalStatus: windowState.status)
    }

    /// 窗口控制专用状态机（T009，data-model.md「状态机」+ 四条不变式）：
    /// 仅当「上一次 granted、本次探针 denied、距进程启动 < 60 秒」进入可疑态
    /// （对外仍报 granted、只记日志）；60 秒内恢复视为抖动；宽限结束仍 denied
    /// 才切换。距启动 ≥ 60 秒的 granted → denied 立即生效。
    private func applyStateMachine(
        capability: PermissionCapability,
        summarized: PermissionStatus,
        probes: [PermissionProbe],
        partialTargets: [String],
        trigger: String,
        now: Date,
        logLatencyMs: Int
    ) -> CapabilityState {
        let secondsSinceLaunch = now.timeIntervalSince(launchedAt)
        let previous = capabilities[capability]
        var status = summarized
        var suspectUntil: Date? = nil
        var notes: [String] = []
        if !partialTargets.isEmpty {
            notes.append("部分目标受控：\(partialTargets.joined(separator: "、"))")
        }

        var lastError: String? = nil
        if summarized == .unknown {
            lastError = explainUnknown(probes: probes, frontmost: nil, finder: nil)
        }

        if let previousState = previous, previousState.suspectUntil != nil, summarized == .denied {
            if now < previousState.suspectUntil! {
                // 宽限中再次探到 denied：维持 granted 与原截止时间，不延长。
                status = .granted
                suspectUntil = previousState.suspectUntil
            } else {
                // 宽限结束仍 denied：切换并提示。
                status = .denied
                notes.append("宽限期结束后仍被拒绝，判定为未授权")
            }
        } else if let previousStatus = previous?.status, previousStatus == .granted, summarized == .denied,
                  PermissionRules.shouldEnterGrace(previous: previousStatus, probe: summarized, secondsSinceLaunch: secondsSinceLaunch) {
            // 进入可疑态：对外仍报 granted，只记日志、不弹提示。
            status = .granted
            suspectUntil = now.addingTimeInterval(max(0, PermissionRules.graceWindowSeconds - secondsSinceLaunch))
            scheduleGraceRecheck(at: suspectUntil!)
            permissionLogRecord(
                capability: capability.rawValue,
                id: "summary",
                target: "system",
                status: status.rawValue,
                axError: nil,
                latencyMs: logLatencyMs,
                trigger: trigger,
                error: "登录期宽限：探针 denied，距启动 \(Int(secondsSinceLaunch)) 秒，进入可疑态至 \(suspectUntil!)（notes: \(notes.joined(separator: "；"))）"
            )
        } else if previousStatusKnownSuspect(previous: previous), summarized == .granted {
            // 宽限窗口内恢复 granted：视为抖动。
            notes.append("宽限期内恢复，判定为系统抖动")
        }

        return commitState(
            capability: capability,
            newStatus: status,
            probes: probes,
            lastError: lastError,
            suspectUntil: suspectUntil,
            trigger: trigger,
            now: now,
            logLatencyMs: logLatencyMs,
            notes: notes.isEmpty ? nil : notes.joined(separator: "；")
        )
    }

    /// 上一次状态是否处于可疑态（用于识别「宽限期内恢复 granted」的抖动）。
    private func previousStatusKnownSuspect(previous: CapabilityState?) -> Bool {
        previous?.suspectUntil != nil
    }

    /// 为 unknown 汇总生成可解释的 lastError（不变式 3）。
    private func explainUnknown(probes: [PermissionProbe], frontmost: PermissionProbe?, finder: PermissionProbe?) -> String {
        var reasons: [String] = []
        for probe in probes where probe.status == .unknown {
            var reason = "探针 \(probe.id)（\(probe.target)）"
            if probe.axError != nil { reason += " AXError=\(probe.axError!)" }
            reasons.append(reason)
        }
        if reasons.isEmpty { reasons.append("探针结果无法区分全局拒绝与目标侧问题") }
        return "无法确认是全局拒绝还是目标侧问题：" + reasons.joined(separator: "；")
    }

    /// 提交一个能力的最终状态：记日志、维护 lastChangedAt、触发 onStatusChange。
    private func commitState(
        capability: PermissionCapability,
        newStatus: PermissionStatus,
        probes: [PermissionProbe],
        lastError: String?,
        suspectUntil: Date?,
        trigger: String,
        now: Date,
        logLatencyMs: Int,
        notes: String?
    ) -> CapabilityState {
        let previous = capabilities[capability]
        let previousStatus = previous?.status
        let changed = previousStatus != newStatus

        // 不变式 3：unknown 时 lastError 必须非空。
        var finalError = lastError
        if newStatus == .unknown && (finalError ?? "").isEmpty {
            finalError = "探针结果无法判定"
        }

        let state = CapabilityState(
            capability: capability,
            status: newStatus,
            lastCheckedAt: now,
            lastChangedAt: changed ? now : (previous?.lastChangedAt ?? now),  // 不变式 4
            trigger: trigger,
            probes: probes,
            lastError: finalError,
            suspectUntil: suspectUntil
        )

        // 汇总日志（对外状态）。
        permissionLogRecord(
            capability: capability.rawValue,
            id: "summary",
            target: "system",
            status: newStatus.rawValue,
            axError: nil,
            latencyMs: logLatencyMs,
            trigger: trigger,
            error: {
                var parts: [String] = []
                if let previousStatus { parts.append("previous=\(previousStatus.rawValue)") }
                if changed { parts.append("changed=true") }
                if let suspectUntil { parts.append("suspectUntil=\(suspectUntil)") }
                if let notes { parts.append("notes=\(notes)") }
                if let finalError { parts.append("error=\(finalError)") }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()
        )

        if changed {
            onStatusChange?(capability, previousStatus ?? newStatus, newStatus)
        }
        return state
    }

    // MARK: 调度（T008）

    /// granted 后 30 秒轮询；非 granted 时 5 秒 × 最多 24 次（达到上限后停止，
    /// 等待 activate / wake / manual / ax-failure 等硬触发重置）。
    private func scheduleNextPoll(externalStatus: PermissionStatus) {
        pollWorkItem?.cancel()
        pollWorkItem = nil
        if externalStatus == .granted {
            schedulePoll(after: 30.0)
            return
        }
        guard pollCount < 24 else { return }
        pollCount += 1
        schedulePoll(after: 5.0)
    }

    private func schedulePoll(after interval: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            self?.recheck(trigger: "poll")
        }
        pollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    /// 宽限到期复检（R4）：60 秒后自动复核一次；若仍 denied，状态机按
    /// 「宽限结束仍 denied」切换。注意批次进行中该复核会被合并去重，
    /// 由随后的 30 秒轮询兜底。
    private func scheduleGraceRecheck(at deadline: Date) {
        graceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recheck(trigger: "poll")
        }
        graceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow, execute: work)
    }

    // MARK: SystemInfo / AppInfo

    /// 系统 Build 从 operatingSystemVersionString 的括号里解析
    /// （形如 "Version 27.2 (Build 26C5047e)"），失败为 "unknown"。
    static func makeSystemInfo() -> SystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var productVersion = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { productVersion += ".\(version.patchVersion)" }

        var build = "unknown"
        let versionString = ProcessInfo.processInfo.operatingSystemVersionString
        if let buildStart = versionString.range(of: "Build "),
           let closeParen = versionString.range(of: ")", range: buildStart.upperBound..<versionString.endIndex) {
            build = String(versionString[buildStart.upperBound..<closeParen.lowerBound])
        }

        var arch = "unknown"
        var machineInfo = utsname()
        uname(&machineInfo)
        let machine = withUnsafeBytes(of: &machineInfo.machine) { rawBuffer -> String in
            String(cString: rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        if !machine.isEmpty { arch = machine }

        return SystemInfo(productVersion: productVersion, build: build, arch: arch)
    }

    static func makeAppInfo() -> AppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketingVersion = (info["CFBundleShortVersionString"] as? String) ?? "0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let path = Bundle.main.bundlePath
        let isTranslocated = path.contains("/AppTranslocation/")

        var teamID = "unknown"
        var code: SecCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code {
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode {
                var information: CFDictionary?
                if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
                   let information,
                   let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String {
                    teamID = team
                }
            }
        }

        var isLoginItem = false
        if SMAppService.mainApp.status == .enabled { isLoginItem = true }

        return AppInfo(
            marketingVersion: marketingVersion,
            build: build,
            bundleID: bundleID,
            teamID: teamID,
            path: path,
            isTranslocated: isTranslocated,
            isLoginItem: isLoginItem
        )
    }
}
