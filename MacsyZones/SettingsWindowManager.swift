//
// MacsyZones, macOS system utility for managing windows on your Mac.
//
// https://github.com/jiezhengj/MacsyZones
//
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
//
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

import Cocoa
import SwiftUI

class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?
    private var state: SettingsState?

    private init() {}

    // MARK: - Window Visibility
    var isVisible: Bool {
        return window?.isVisible ?? false
    }

    // MARK: - Show Window
    func showWindow() {
        if window == nil {
            createWindow()
        }

        // Refresh state
        state?.refresh()

        // Center on mouse screen
        if let screen = getFocusedScreen() {
            centerWindowOnScreen(screen)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Hide Window
    func hideWindow() {
        window?.orderOut(nil)
    }

    // MARK: - Toggle Window
    func toggleWindow() {
        if isVisible {
            // Just focus, don't close
            window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showWindow()
        }
    }

    // MARK: - Create Window
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
        window.delegate = WindowDelegate.shared
        window.center()

        self.window = window
    }

    // MARK: - Center Window on Screen
    private func centerWindowOnScreen(_ screen: NSScreen) {
        guard let window = window else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Window Delegate
class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        // Just hide, don't destroy
        // Window will be reused next time
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Window gained focus
    }

    func windowDidResignKey(_ notification: Notification) {
        // Window lost focus - don't close
    }
}
