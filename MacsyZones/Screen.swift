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

private var lastFocusedScreen: NSScreen?

func getFocusedScreen() -> NSScreen? {
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
        lastFocusedScreen = screen
        return screen
    }

    // A display can be disconnected while it is the last focused screen.
    // Never return a stale NSScreen object that is no longer available.
    if let previousScreen = lastFocusedScreen,
       NSScreen.screens.contains(where: { $0 == previousScreen }) {
        return previousScreen
    }

    let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
    lastFocusedScreen = fallbackScreen
    return fallbackScreen
}

func getScreenNumber(screen: NSScreen) -> Int? {
    guard let displayId = screen.cgDirectDisplayID else { return nil }
    return Int(displayId)
}

func resolveScreen(screenNumber: Int) -> NSScreen? {
    if let screen = NSScreen.screens.first(where: { getScreenNumber(screen: $0) == screenNumber }) {
        return screen
    }

    return nil
}

func centerWindowOnFocusedScreen(_ window: NSWindow) {
    guard let screen = getFocusedScreen() else {
        window.center()
        return
    }
    
    let screenFrame = screen.visibleFrame
    let windowFrame = window.frame
    
    let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
    let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
    
    window.setFrameOrigin(NSPoint(x: x, y: y))
}
