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

import Foundation
import SwiftUI
import Combine

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

class MacsyReady: ObservableObject {
    @Published var isReady: Bool = false
}

let macsyReady = MacsyReady()
let appUpdater = AppUpdater()

let quickSnapper = QuickSnapper()

let cycleForwardHotkey = GlobalHotkey() {
    cycleWindowsInZone(forward: true)
    return noErr
}

let cycleBackwardHotkey = GlobalHotkey() {
    cycleWindowsInZone(forward: false)
    return noErr
}

// 权限引导接线（T018）：首轮权限探测完成后，窗口控制未授权才展示一次非模态引导；
// Combine 订阅的存储与一次性展示标志（AnyCancellable 非 Sendable，故存全局区而非 AppDelegate 属性）。
var permissionGuidanceCancellable: AnyCancellable?
var hasShownPermissionGuidance = false
var hasShownPermissionOnboarding = false
// T023：菜单栏状态标记的快照订阅（每次快照更新时刷新标记）。
var permissionTrayCancellable: AnyCancellable?

var statusItem: NSStatusItem!
var accessibilityDialog: AccessibilityDialog?
var updateFailedDialog: UpdateFailedDialog?

var mouseUpMonitor: Any?
var mouseDownMonitor: Any?
var mouseDragMonitor: Any?
var rightMouseMonitor: Any?
var shortcutMonitor: Any?

var isPreview: Bool {
    return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

/// Carries an AX element across the main-actor hop. AXUIElement is a Core
/// Foundation reference type; only the sending side touches it before the
/// handoff, and the receiving side only registers notifications.
private struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement
}

@MainActor
final class WindowObserverManager {
    static let shared = WindowObserverManager()

    private struct WindowEntry {
        let element: AXUIElement
        let notifications: [CFString]
    }

    private struct AppEntry {
        let observer: AXObserver
        let appElement: AXUIElement
        var observesWindowCreation: Bool
        var shouldRetryWindowCreation: Bool
        var windows: [UInt32: WindowEntry] = [:]
    }

    private var entries: [pid_t: AppEntry] = [:]

    /// Guards the delayed re-scans so quitting the app does not leave work
    /// items that touch AX after teardown.
    private var pendingScanWorkItems: [DispatchWorkItem] = []

    private let observerRunLoop: CFRunLoop

    private final class RunLoopBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CFRunLoop?

        func set(_ runLoop: CFRunLoop) {
            lock.lock(); value = runLoop; lock.unlock()
        }

        func get() -> CFRunLoop? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    private init() {
        let readySemaphore = DispatchSemaphore(value: 0)
        let box = RunLoopBox()

        let thread = Thread {
            let runLoop: CFRunLoop = CFRunLoopGetCurrent()
            box.set(runLoop)

            var ctx = CFRunLoopSourceContext()
            if let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx) {
                CFRunLoopAddSource(runLoop, source, .commonModes)
            }

            readySemaphore.signal()

            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, true)
            }
        }
        thread.name = "com.macsyzones.ax-observer"
        thread.qualityOfService = QualityOfService.userInteractive
        thread.start()

        readySemaphore.wait()
        observerRunLoop = box.get()!
    }

    @discardableResult
    func observeApp(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }

        if var entry = entries[pid] {
            if entry.shouldRetryWindowCreation {
                let result = AXObserverAddNotification(entry.observer,
                                                       entry.appElement,
                                                       kAXWindowCreatedNotification as CFString,
                                                       nil)
                entry.observesWindowCreation = notificationWasRegistered(result)
                entry.shouldRetryWindowCreation = !entry.observesWindowCreation && result != .notificationUnsupported
                entries[pid] = entry
            }
            return true
        }

        let appElement = AXUIElementCreateApplication(pid)

        let observerPtr = UnsafeMutablePointer<AXObserver?>.allocate(capacity: 1)
        defer { observerPtr.deallocate() }

        guard AXObserverCreate(pid, onObserverNotification, observerPtr) == .success,
              let observer = observerPtr.pointee
        else {
            debugLog("Failed to create observer for pid \(pid)")
            return false
        }

        AXUIElementSetMessagingTimeout(appElement, 0.75)

        let createdResult = AXObserverAddNotification(observer,
                                                      appElement,
                                                      kAXWindowCreatedNotification as CFString,
                                                      nil)
        let observesWindowCreation = notificationWasRegistered(createdResult)
        if !observesWindowCreation {
            debugLog("Failed to observe window creation for pid \(pid): \(createdResult.rawValue)")
        }

        addRunLoopSource(for: observer)

        entries[pid] = AppEntry(
            observer: observer,
            appElement: appElement,
            observesWindowCreation: observesWindowCreation,
            shouldRetryWindowCreation: !observesWindowCreation && createdResult != .notificationUnsupported
        )
        debugLog("AX app observer ready: pid=\(pid), observesWindowCreation=\(observesWindowCreation)")

        return true
    }

    @discardableResult
    func observeWindow(pid: pid_t, element: AXUIElement, attempt: Int = 0) -> Bool {
        guard pid > 0 else { return false }

        // AX attributes may be temporarily unavailable (window still being
        // constructed, app busy). That is "indeterminate", not "not a window":
        // retry with backoff instead of dropping the window for good.
        switch checkStandardWindow(element) {
        case .notStandard:
            return false
        case .indeterminate:
            scheduleObserveRetry(pid: pid, element: element, attempt: attempt)
            return false
        case .standard:
            break
        }

        guard observeApp(pid: pid), var entry = entries[pid] else {
            scheduleObserveRetry(pid: pid, element: element, attempt: attempt)
            return false
        }
        guard let windowID = getWindowID(from: element), windowID != 0 else {
            debugLog("Refusing to tag an AX window without a valid window ID: pid=\(pid)")
            return false
        }

        if let existing = entry.windows[windowID] {
            if CFEqual(existing.element, element) {
                return true
            }
            removeNotifications(existing.notifications,
                                observer: entry.observer,
                                element: existing.element)
            entry.windows.removeValue(forKey: windowID)
        }

        AXUIElementSetMessagingTimeout(element, 0.75)

        var registeredNotifications: [CFString] = []
        let movedNotifications: [CFString] = [
            kAXMovedNotification as CFString,
            kAXWindowMovedNotification as CFString
        ]

        for notification in movedNotifications {
            let result = AXObserverAddNotification(entry.observer, element, notification, nil)
            if notificationWasRegistered(result) {
                registeredNotifications.append(notification)
            } else {
                debugLog("AX movement registration failed: pid=\(pid), windowID=\(windowID), notification=\(notification), error=\(result.rawValue)")
            }
        }

        guard !registeredNotifications.isEmpty else {
            debugLog("Window remains retryable because no AX movement notification registered: pid=\(pid), windowID=\(windowID)")
            return false
        }

        let destroyedNotification = kAXUIElementDestroyedNotification as CFString
        let destroyedResult = AXObserverAddNotification(entry.observer,
                                                        element,
                                                        destroyedNotification,
                                                        nil)
        if notificationWasRegistered(destroyedResult) {
            registeredNotifications.append(destroyedNotification)
        } else {
            // Movement observation is still useful. A stale record is replaced
            // when the same window ID is discovered again, or removed when the
            // owning application terminates.
            debugLog("AX destruction registration unavailable: pid=\(pid), windowID=\(windowID), error=\(destroyedResult.rawValue)")
        }

        entry.windows[windowID] = WindowEntry(element: element,
                                              notifications: registeredNotifications)
        entries[pid] = entry
        debugLog("AX window observer ready: pid=\(pid), windowID=\(windowID), notifications=\(registeredNotifications.count)")
        return true
    }

    private func scheduleObserveRetry(pid: pid_t, element: AXUIElement, attempt: Int) {
        guard attempt < 3 else {
            debugLog("Giving up on pid \(pid) window after repeated AX errors; it won't be observed.")
            return
        }

        let delayNanoseconds = UInt64(150_000_000 * (attempt + 1))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            self.observeWindow(pid: pid, element: element, attempt: attempt + 1)
        }
    }

    /// Cross-checks the AX window list against the on-screen CG window list and
    /// re-registers windows that AX did not report. A window can appear in CG
    /// while still missing from `kAXWindowsAttribute`; those windows never emit
    /// AX movement notifications and silently lose snapping until this heals.
    ///
    /// The diff itself is cheap, but hunting the missing elements walks AX
    /// window lists, and an unresponsive app can stall those calls for seconds.
    /// So the hunt runs off the main actor; only `observeWindow` touches the
    /// observer registry.
    func reconcile(pid: pid_t, axWindows: [AXUIElement]) {
        guard pid > 0 else { return }

        var axIDs = Set<UInt32>()
        for window in axWindows {
            if let id = getWindowID(from: window) {
                axIDs.insert(id)
            }
        }
        let observedIDs: Set<UInt32> = entries[pid].map { Set($0.windows.keys) } ?? []

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                          kCGNullWindowID) as? [[String: Any]]
            else { return }

            var cgTitles: [UInt32: String] = [:]
            let pidValue = Int(pid)
            for info in cgList {
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == pidValue,
                      let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let windowID = info[kCGWindowNumber as String] as? UInt32
                else { continue }
                cgTitles[windowID] = (info[kCGWindowName as String] as? String) ?? ""
            }

            let missingIDs = Set(cgTitles.keys).subtracting(axIDs).subtracting(observedIDs)
            guard !missingIDs.isEmpty else { return }

            debugLog("Reconcile: pid \(pid) is missing \(missingIDs.count) window(s) from AX; hunting for them.")

            var hunted: [AXElementBox] = []
            for windowID in missingIDs {
                var element = retrieveFreshWindowElement(for: windowID, pid: pid)

                if element == nil {
                    let title = cgTitles[windowID] ?? ""
                    if !title.isEmpty, let found = retrieveFreshWindowElementByTitle(title: title) {
                        element = found.element
                    }
                }

                if let element {
                    hunted.append(AXElementBox(element: element))
                }
            }

            guard !hunted.isEmpty, let self else { return }

            Task { @MainActor in
                for box in hunted {
                    self.observeWindow(pid: pid, element: box.element)
                }
            }
        }
    }

    /// Reads the app's AX window list off the main thread, then registers every
    /// window and reconciles against the CG window list on the main actor.
    func scanWindows(forPid pid: pid_t) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.75)

            var windowListRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement,
                                                       kAXWindowsAttribute as CFString,
                                                       &windowListRef)
            let windowList = (windowListRef as? [AXUIElement]) ?? []

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeApp(pid: pid)
                guard result == .success else { return }
                self.reconcile(pid: pid, axWindows: windowList)
                for window in windowList {
                    self.observeWindow(pid: pid, element: window)
                }
            }
        }
    }

    func scanAllRunningApplications() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier > 0 &&
              app.processIdentifier != ownPID &&
              app.activationPolicy == .regular {
            scanWindows(forPid: app.processIdentifier)
        }
    }

    func scheduleWindowScans(forPid pid: pid_t? = nil, delays: [TimeInterval]) {
        for delay in delays {
            var scheduledItem: DispatchWorkItem?
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if let scheduledItem {
                        self.pendingScanWorkItems.removeAll { $0 === scheduledItem }
                    }
                    if let pid {
                        self.scanWindows(forPid: pid)
                    } else {
                        self.scanAllRunningApplications()
                    }
                }
            }
            scheduledItem = workItem
            pendingScanWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func cancelPendingScans() {
        for workItem in pendingScanWorkItems {
            workItem.cancel()
        }
        pendingScanWorkItems.removeAll()
    }

    func forgetWindow(pid: pid_t, windowID: UInt32) {
        guard var entry = entries[pid] else { return }
        guard let window = entry.windows.removeValue(forKey: windowID) else { return }
        removeNotifications(window.notifications,
                            observer: entry.observer,
                            element: window.element)
        entries[pid] = entry
    }

    func forgetWindow(element: AXUIElement) {
        for (pid, var entry) in entries {
            guard let match = entry.windows.first(where: { CFEqual($0.value.element, element) }) else {
                continue
            }
            removeNotifications(match.value.notifications,
                                observer: entry.observer,
                                element: match.value.element)
            entry.windows.removeValue(forKey: match.key)
            entries[pid] = entry
            debugLog("Removed destroyed AX window: pid=\(pid), windowID=\(match.key)")
            return
        }
    }

    func removeApp(pid: pid_t) {
        guard let entry = entries.removeValue(forKey: pid) else { return }
        removeRunLoopSource(for: entry.observer)
        debugLog("Removed AX app observer: pid=\(pid)")
    }

    func refreshApplication(pid: pid_t, retry: Int = 0) {
        guard pid > 0, observeApp(pid: pid) else { return }

        // AX calls can block while a Space transition is settling. Query each
        // process away from the main thread, then update the registry on the
        // main actor so switching Spaces never freezes the overlay UI.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.75)

            var windowListRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement,
                                                       kAXWindowsAttribute as CFString,
                                                       &windowListRef)
            let windows = windowListRef as? [AXUIElement]

            Task { @MainActor [weak self] in
                guard let self else { return }

                // Handles kAXErrorCannotComplete or unexpected errors with backoff retry (+0.2s, +0.5s, +1.0s)
                guard result == .success, let windows else {
                    debugLog("AX window refresh failed: pid=\(pid), retry=\(retry), error=\(result.rawValue) (kAXErrorCannotComplete check)")
                    guard retry < 3 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(retry + 1)) { [weak self] in
                        self?.refreshApplication(pid: pid, retry: retry + 1)
                    }
                    return
                }

                for window in windows {
                    self.observeWindow(pid: pid, element: window)
                }
            }
        }
    }

    func refreshAllRunningApplications() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier > 0 &&
              app.processIdentifier != ownPID &&
              app.activationPolicy == .regular {
            refreshApplication(pid: app.processIdentifier)
        }
    }

    private enum StandardWindowCheck {
        case standard
        case notStandard
        case indeterminate
    }

    private func checkStandardWindow(_ element: AXUIElement) -> StandardWindowCheck {
        var roleRef: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard roleStatus == .success else {
            // T022：读取失败携带原始 AXError 上报权限中心（仅 kAXErrorAPIDisabled 会触发即时复核）。
            PermissionCenter.shared.reportAXFailure(roleStatus)
            return .indeterminate
        }
        guard (roleRef as? String) == kAXWindowRole else { return .notStandard }

        var subroleRef: CFTypeRef?
        let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        guard subroleStatus == .success else {
            PermissionCenter.shared.reportAXFailure(subroleStatus)
            return .indeterminate
        }
        guard (subroleRef as? String) == kAXStandardWindowSubrole else { return .notStandard }

        return .standard
    }

    private func notificationWasRegistered(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
    }

    private func removeNotifications(_ notifications: [CFString],
                                     observer: AXObserver,
                                     element: AXUIElement) {
        for notification in notifications {
            let result = AXObserverRemoveNotification(observer, element, notification)
            if result != .success && result != .notificationNotRegistered && result != .invalidUIElement {
                debugLog("Failed to remove AX notification \(notification): \(result.rawValue)")
            }
        }
    }

    private func addRunLoopSource(for observer: AXObserver) {
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopPerformBlock(observerRunLoop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopAddSource(self.observerRunLoop, source, .defaultMode)
        }
        CFRunLoopWakeUp(observerRunLoop)
    }

    private func removeRunLoopSource(for observer: AXObserver) {
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopPerformBlock(observerRunLoop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopRemoveSource(self.observerRunLoop, source, .defaultMode)
        }
        CFRunLoopWakeUp(observerRunLoop)
    }
}

@main
struct MacsyZonesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isPreview {
            debugLog("Running in preview mode, skipping setup.")

            macsyReady.isReady = true

            return
        }

        NSApp.setActivationPolicy(.prohibited)

        checkIfRunning()
        createTrayIcon()
        // T017/T018：权限探测由 PermissionCenter 负责（@MainActor 隔离）；
        // 首轮探测完成前不展示任何未授权引导，完成后再按 snapshot.overall 判定。
        Task { @MainActor in
            PermissionCenter.shared.start()

            // T035：按能力类型接线监视器装/卸（windowControl→鼠标类、inputMonitoring→键盘类）。
            wirePermissionMonitorLifecycle()

            // 首轮探测完成后接线：未授权 → 展示一次非模态引导；已授权 → 补齐 onboarding
            // （原逻辑在探测同步完成后立即判定，此处等首轮完成，行为等价且单点触发防双弹）。
            permissionGuidanceCancellable = PermissionCenter.shared.$snapshot
                .combineLatest(PermissionCenter.shared.$hasCompletedFirstCheck)
                .receive(on: DispatchQueue.main)
                .sink { pair in
                    let (snapshot, firstCheckDone) = pair
                    // 快照未就绪时不得判定：nil 曾被当成「未授权」而误弹一次引导。
                    guard firstCheckDone, let snapshot else { return }

                    if snapshot.overall != .granted, !hasShownPermissionGuidance {
                        hasShownPermissionGuidance = true
                        self.showAccessibilityPermissionPopover()
                    } else if snapshot.overall == .granted, accessibilityDialog != nil {
                        // 用户在引导面板还开着的时候完成授权：立即收起面板，不要求重启。
                        accessibilityDialog?.dismiss()
                        accessibilityDialog = nil
                    }
                    if snapshot.overall == .granted,
                       !onboardingState.hasCompletedOnboarding,
                       !hasShownPermissionOnboarding {
                        hasShownPermissionOnboarding = true
                        showOnboarding()
                    }
                }

            // T023：首轮探测早于 createTrayIcon 的完成时机不确定，这里订阅快照，
            // 每次快照更新都刷新菜单栏标记（首轮完成前快照为 nil，标记保持空白）。
            permissionTrayCancellable = PermissionCenter.shared.$snapshot
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    Task { @MainActor in
                        refreshTrayPermissionMark()
                    }
                }
        }
        monitorActivations()
        GlobalHotkey.setup()
        quickSnapper.setup()

        // Schedule the re-scans before the initial scan starts so their delays
        // count from real launch time instead of from the end of that scan.
        WindowObserverManager.shared.scheduleWindowScans(delays: [2.0, 6.0, 12.0])
        
        Thread { [self] in
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.processIdentifier != ownPID && $0.activationPolicy == .regular
            }
            
            for app in apps {
                let pid = app.processIdentifier
                let element = AXUIElementCreateApplication(pid)

                // Observe the application even when AXWindows is temporarily
                // unavailable or empty. Otherwise its future windows can never
                // emit AXWindowCreated to MacsyZones.
                Task { @MainActor in
                    startObserving(pid: pid)
                }
                
                var windowListRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowListRef)
                if result != .success { continue }

                if let windowList = windowListRef as? [AXUIElement]
                {
                    for window in windowList {
                        var titleValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(window,
                                                      kAXTitleAttribute as CFString,
                                                      &titleValue)
                        
                        if let title = titleValue as? String, !title.isEmpty {
                            debugLog("Window is being observed: \(title)")
                        }
                        
                        Task { @MainActor in
                            startObserving(pid: pid, element: window)
                        }
                    }
                }
            }
            
            debugLog("All apps are being observed for window movement.")
            
            Task { @MainActor in
                // T034：全局监视器按能力类型分别安装（R13）——
                // 鼠标类（leftMouseDown/leftMouseDragged/leftMouseUp/rightMouseDown）绑 windowControl，
                // 键盘类（keyDown+flagsChanged）绑 inputMonitoring；
                // 对应能力 != .denied 时安装（unknown 也安装，FR-013）。
                installMouseMonitors()
                installKeyboardMonitor()

                spaceLayoutPreferences.startObserving()

                spaceLayoutPreferences.switchToCurrent()
                
                macsyReady.isReady = true

                // onboarding 的判定已移至权限中心首轮探测完成后的接线处（T018）。

                cycleForwardHotkey.register(for: appSettings.cycleWindowsForwardShortcut)
                cycleBackwardHotkey.register(for: appSettings.cycleWindowsBackwardShortcut)
            }
        }
        .start()
        
        checkUpdateState()
    }
    
    
    func checkIfRunning() {
        let notificationName = "MeowingCat.MacsyZones.CheckIfRunning"
        let uniqueNotification = Notification.Name(notificationName)
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        if isRunning {
            DistributedNotificationCenter.default().postNotificationName(
                uniqueNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            
            let alert = NSAlert()
            alert.window.level = .screenSaver
            alert.window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            alert.alertStyle = .critical
            alert.messageText = "MacsyZones is already running"
            alert.informativeText = "Another instance of MacsyZones is already running. This instance will exit."
            alert.addButton(withTitle: "OK")
            
            alert.window.center()
            
            alert.window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            alert.runModal()
            
            NSApp.terminate(nil)
            return
        }
    }
    
    func checkUpdateState() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        if updateState.hasFailedUpdate(currentVersion: currentVersion) {
            showUpdateFailedDialog()
        } else {
            if let targetVersion = updateState.targetVersion {
                if currentVersion == targetVersion || isVersionGreater(currentVersion, than: targetVersion) {
                    updateState.clearUpdateAttempt()
                }
            }
            
            appUpdater.autoCheckAndDownload()
        }
    }
    
    func showUpdateFailedDialog() {
        if updateFailedDialog == nil {
            updateFailedDialog = UpdateFailedDialog()
        }
        
        updateFailedDialog?.show()
    }
    
    func createTrayIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                image.isTemplate = true
            } else {
                button.image = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: "MacsyZones")
                button.image?.isTemplate = true
            }

            // Left click action
            button.action = #selector(toggleSettings)
            button.target = self

            // Right click menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "打开主界面", action: #selector(showSettings), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem?.menu = menu
        }
    }

    @objc func showSettings() {
        SettingsWindowManager.shared.showWindow()
    }

    @objc func toggleSettings(sender: AnyObject?) {
        // T021：菜单栏图标点击是复核触发源之一（R4）；didActivate/didWake/didBecomeKey
        // 已由 PermissionCenter 内部注册，didBecomeActive 在 .prohibited 下可能永不触发，
        // 故按任务要求只作可选补充、不依赖。
        Task { @MainActor in
            PermissionCenter.shared.recheck(trigger: "manual")
        }
        SettingsWindowManager.shared.toggleWindow()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // T017：旧的 checkAccessibilityPermission() / requestAccessibilityPermissions()
    // 已删除；未授权引导统一走 showAccessibilityPermissionPopover()（非模态）。

    func showAccessibilityPermissionPopover() {
        if accessibilityDialog == nil {
            accessibilityDialog = AccessibilityDialog()
        }
        accessibilityDialog?.show()
    }

    func monitorActivations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTermination(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        guard app.processIdentifier > 0,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular
        else { return }

        debugLog("Newly launched app is being observed: \(app)")
        Task { @MainActor in
            WindowObserverManager.shared.refreshApplication(pid: app.processIdentifier)
            WindowObserverManager.shared.scheduleWindowScans(forPid: app.processIdentifier,
                                                            delays: [1.0, 3.0, 7.0])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            WindowObserverManager.shared.refreshApplication(pid: app.processIdentifier)
        }
    }

    @objc func handleAppTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }

        let pid = app.processIdentifier
        Task { @MainActor in
            WindowObserverManager.shared.removeApp(pid: pid)
        }
    }

    @objc func handleAppActivation(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            Task { @MainActor in
                WindowObserverManager.shared.refreshApplication(pid: app.processIdentifier)
                // Windows that AX did not list at launch surface on the CG side
                // first; reconcile as soon as the app is brought forward.
                WindowObserverManager.shared.scheduleWindowScans(forPid: app.processIdentifier,
                                                                delays: [0.0])
            }
        }

        guard appSettings.selectPerDesktopLayout,
              !isQuickSnapping,
              !isEditing,
              !isFitting,
              !isSnapResizing
        else { return }

        spaceLayoutPreferences.switchToCurrent()
    }

    @objc func handleWindowDidBecomeKey(_ notification: Notification) {
        guard appSettings.selectPerDesktopLayout,
              !isQuickSnapping,
              !isEditing,
              !isFitting,
              !isSnapResizing
        else { return }
        
        spaceLayoutPreferences.switchToCurrent()
    }
    
    @MainActor
    func startObserving(pid: pid_t, element: AXUIElement? = nil) {
        if let element = element {
            WindowObserverManager.shared.observeWindow(pid: pid, element: element)
        } else {
            WindowObserverManager.shared.observeApp(pid: pid)
        }
    }
    
    @MainActor
    func monitorShortcuts() {
        // T034：防重复安装。
        guard shortcutMonitor == nil else { return }
        var modifierKeyTask: DispatchWorkItem?
        var snapKeyUsed = false
        var prevFlags = NSEvent.ModifierFlags()
        
        shortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if !macsyReady.isReady { return }
            var modifierKey: NSEvent.ModifierFlags = .control
            
            if appSettings.modifierKey == "Command" {
                modifierKey = .command
            } else if appSettings.modifierKey == "Option" {
                modifierKey = .option
            }
            
            modifierKeyTask?.cancel()
            modifierKeyTask = nil
            
            let modifierKeyUsed = !prevFlags.contains(modifierKey) && event.modifierFlags.contains(modifierKey)
            prevFlags = event.modifierFlags
            
            if isEditing || isQuickSnapping {
                return
            }
            
            if appSettings.snapKey != "None" {
                var snapKey: NSEvent.ModifierFlags = .shift
                
                if appSettings.snapKey == "Control" {
                    snapKey = .control
                } else if appSettings.snapKey == "Command" {
                    snapKey = .command
                } else if appSettings.snapKey == "Option" {
                    snapKey = .option
                }
                
                if appSettings.selectPerDesktopLayout {
                    if let layoutName = spaceLayoutPreferences.getCurrent() {
                        userLayouts.setCurrentLayout(name: layoutName)
                    }
                }
                
                if appSettings.snapWhileDragging {
                    // Auto-snap mode: holding the snap key temporarily SUPPRESSES snapping
                    // while dragging; releasing it re-activates the layout.
                    if isMovingAWindow {
                        if event.modifierFlags.contains(snapKey) {
                            if isFitting {
                                setIsFitting(false)
                                if !isQuickSnapping {
                                    userLayouts.currentLayout.hide()
                                }
                            }
                        } else if !isFitting && !snapSuppressedForDrag {
                            setIsFitting(true)
                            userLayouts.currentLayout.show()
                            if userLayouts.currentLayout.layoutType == .grid {
                                userLayouts.currentLayout.gridLayoutWindow?.setAnchorAtMousePosition()
                            }
                        }
                    }
                } else {
                    if event.modifierFlags.contains(snapKey) && !isFitting && isMovingAWindow {
                        snapKeyUsed = true
                        setIsFitting(true)
                        userLayouts.currentLayout.show()
                        if userLayouts.currentLayout.layoutType == .grid {
                            userLayouts.currentLayout.gridLayoutWindow?.setAnchorAtMousePosition()
                        }
                    } else if isFitting && snapKeyUsed {
                        snapKeyUsed = false
                        setIsFitting(false)
                        if !isQuickSnapping {
                            userLayouts.currentLayout.hide()
                        }
                    }
                    
                    if !event.modifierFlags.contains(snapKey) {
                        snapKeyUsed = false
                    }
                }
            }
            
            if !snapKeyUsed && !appSettings.snapWhileDragging && appSettings.modifierKey != "None" && event.type == .flagsChanged {
                if appSettings.selectPerDesktopLayout {
                    if let layoutName = spaceLayoutPreferences.getCurrent() {
                        userLayouts.setCurrentLayout(name: layoutName)
                    }
                }
                
                let delay = Double(appSettings.modifierKeyDelay) / 1000.0
                
                if modifierKeyUsed {
                    if !isFitting {
                        modifierKeyTask = DispatchWorkItem {
                            if isFitting {
                                if userLayouts.currentLayout.layoutType == .zone {
                                    userLayouts.currentLayout.layoutWindow.show(showSnapResizers: true)
                                } else {
                                    userLayouts.currentLayout.show()
                                }
                            }
                        }
                        
                        setIsFitting(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: modifierKeyTask!)
                    }
                } else {
                    modifierKeyTask?.cancel()
                    modifierKeyTask = nil
                    
                    if isFitting {
                        setIsFitting(false)
                        if !isQuickSnapping {
                            userLayouts.currentLayout.hide()
                        }
                    }
                }
            }
        }
    }
    
    private func monitorRightClick() {
        // T034：防重复安装。
        guard rightMouseMonitor == nil else { return }
        rightMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { event in
            if !macsyReady.isReady { return }
            if event.buttonNumber != 1 { return }
            if !appSettings.snapWithRightClick { return }
            if isEditing { return }
            if isQuickSnapping { return }
            if isSnapResizing { return }
            if !isMovingAWindow { return }
            
            if !isFitting {
                if appSettings.selectPerDesktopLayout,
                   let layoutName = spaceLayoutPreferences.getCurrent()
                {
                    userLayouts.currentLayoutName = layoutName
                }

                userLayouts.currentLayout.show()
                if userLayouts.currentLayout.layoutType == .grid {
                    userLayouts.currentLayout.gridLayoutWindow?.setAnchorAtMousePosition()
                }
                setIsFitting(true)
                snapSuppressedForDrag = false
            } else {
                userLayouts.currentLayout.hide()
                setIsFitting(false)
                // Keep snapping off for the rest of this drag so it doesn't
                // re-activate on the next mouse movement.
                snapSuppressedForDrag = true
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            WindowObserverManager.shared.cancelPendingScans()
        }

        // T035：与 PermissionCenter.stop() 同口径——统一走按能力类型的卸载函数（幂等）。
        MainActor.assumeIsolated {
            uninstallMouseMonitors()
            uninstallKeyboardMonitor()
            PermissionCenter.shared.stop()
        }
    }

    /// 安装鼠标类全局监视器（绑 windowControl）。
    @MainActor
    func installMouseMonitors() {
        guard PermissionCenter.shared.status(of: .windowControl) != .denied else { return }
        if mouseDownMonitor == nil {
            mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
                onMouseDown(event: event)
            }
        }
        if mouseDragMonitor == nil {
            mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
                onMouseDragged(event: event)
            }
        }
        if mouseUpMonitor == nil {
            mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
                onMouseUp(event: event)
            }
        }
        monitorRightClick()
    }

    /// 安装键盘类全局监视器（绑 inputMonitoring）。
    @MainActor
    func installKeyboardMonitor() {
        guard PermissionCenter.shared.status(of: .inputMonitoring) != .denied else { return }
        monitorShortcuts()
    }

    /// 卸载鼠标类全局监视器（幂等，windowControl → .denied 时调用）。
    @MainActor
    func uninstallMouseMonitors() {
        for monitor in [mouseDownMonitor, mouseDragMonitor, mouseUpMonitor, rightMouseMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        mouseDownMonitor = nil
        mouseDragMonitor = nil
        mouseUpMonitor = nil
        rightMouseMonitor = nil
    }

    /// 卸载键盘类全局监视器（幂等，inputMonitoring → .denied 时调用）。
    @MainActor
    func uninstallKeyboardMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        shortcutMonitor = nil
    }

    /// T035：按能力类型驱动监视器装/卸的状态迁移接线（research.md R13、data-model.md 状态机）。
    /// PermissionCenter 在主线程回调；这里用 Task { @MainActor } 落回主线程执行装/卸。
    @MainActor
    func wirePermissionMonitorLifecycle() {
        PermissionCenter.shared.onStatusChange = { capability, _, new in
            Task { @MainActor in
                switch capability {
                case .windowControl:
                    if new == .denied {
                        self.uninstallMouseMonitors()
                        showLayoutReadOnlyHintIfNeeded()
                    } else if new == .granted {
                        self.installMouseMonitors()
                    }
                case .inputMonitoring:
                    if new == .denied {
                        self.uninstallKeyboardMonitor()
                    } else if new == .granted {
                        self.installKeyboardMonitor()
                    }
                case .eventPosting:
                    break
                }
            }
        }
    }
}

func restartApp() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
    task.launch()
    
    NSApp.terminate(nil)
}

// T023：菜单栏状态标记。在模板图标（image.isTemplate 保持不动、深浅色着色不受影响）
// 之后以 attributedTitle 叠加彩色小圆点：denied → 红点，unknown → 黄点，granted → 无标记。
// 快照为 nil（首轮探测未完成）时同样保持空白，不提前报警。
@MainActor
func refreshTrayPermissionMark() {
    guard let button = statusItem?.button else { return }
    switch PermissionCenter.shared.snapshot?.overall {
    case .denied:
        let mark = NSMutableAttributedString(string: " ●")
        mark.addAttribute(.foregroundColor,
                          value: NSColor.systemRed,
                          range: NSRange(location: 0, length: mark.length))
        button.attributedTitle = mark
    case .unknown:
        let mark = NSMutableAttributedString(string: " ●")
        mark.addAttribute(.foregroundColor,
                          value: NSColor.systemYellow,
                          range: NSRange(location: 0, length: mark.length))
        button.attributedTitle = mark
    default:
        button.attributedTitle = NSAttributedString()
    }
}

// MARK: - 降级提示（T036，FR-012）

/// 只读提示一次性标志：denied 后仅提示一次，避免每次操作刷提示。
var didShowLayoutReadOnlyHint = false

/// 缺窗口控制权限时的一次性只读提示：拖动吸附与布局自动保存已暂停；
/// Carbon 快捷键不受影响。写日志与 debugLog，不弹模态（R5）。
@MainActor
func showLayoutReadOnlyHintIfNeeded() {
    guard PermissionCenter.shared.status(of: .windowControl) == .denied,
          !didShowLayoutReadOnlyHint
    else { return }
    didShowLayoutReadOnlyHint = true
    permissionLogRecord(
        capability: "windowControl",
        id: "degrade",
        target: "system",
        status: "denied",
        axError: nil,
        latencyMs: 0,
        trigger: "manual",
        error: "降级提示：拖动吸附与布局自动保存已暂停（只读模式），Carbon 快捷键不受影响"
    )
    debugLog("窗口控制权限缺失：拖动吸附与布局自动保存已暂停（只读模式），Carbon 快捷键不受影响。")
}

