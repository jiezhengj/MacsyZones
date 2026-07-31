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

import Foundation
import SwiftUI
import Combine

// MARK: - Screen Info
struct ScreenInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let screen: NSScreen?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScreenInfo, rhs: ScreenInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Settings State
class SettingsState: ObservableObject {
    // MARK: - Published Properties
    @Published var tempAppSettings: AppSettingsData
    @Published var tempSpacePreferences: [ScreenSpacePair: String]
    @Published var selectedScreenIndex: Int = 0
    @Published var availableScreens: [ScreenInfo] = []
    @Published var isDirty: Bool = false

    // MARK: - Original Values (for comparison and restore)
    private var originalAppSettings: AppSettingsData
    private var originalSpacePreferences: [ScreenSpacePair: String]

    // MARK: - Layout selection per screen
    @Published var screenLayoutSelections: [Int: String] = [:]

    // MARK: - Initialization
    init() {
        // Deep copy current AppSettings
        let currentSettings = AppSettingsData(
            modifierKey: appSettings.modifierKey,
            snapKey: appSettings.snapKey,
            modifierKeyDelay: appSettings.modifierKeyDelay,
            fallbackToPreviousSize: appSettings.fallbackToPreviousSize,
            onlyFallbackToPreviousSizeWithUserEvent: appSettings.onlyFallbackToPreviousSizeWithUserEvent,
            selectPerDesktopLayout: appSettings.selectPerDesktopLayout,
            prioritizeCenterToSnap: appSettings.prioritizeCenterToSnap,
            shakeToSnap: appSettings.shakeToSnap,
            shakeAccelerationThreshold: appSettings.shakeAccelerationThreshold,
            snapResize: appSettings.snapResize,
            snapResizeThreshold: appSettings.snapResizeThreshold,
            quickSnapShortcut: appSettings.quickSnapShortcut,
            snapWithRightClick: appSettings.snapWithRightClick,
            showSnapResizersOnHover: appSettings.showSnapResizersOnHover,
            cycleWindowsForwardShortcut: appSettings.cycleWindowsForwardShortcut,
            cycleWindowsBackwardShortcut: appSettings.cycleWindowsBackwardShortcut,
            snapHighlightStrategy: appSettings.snapHighlightStrategy
        )

        self.tempAppSettings = currentSettings
        self.originalAppSettings = currentSettings

        // Deep copy SpaceLayoutPreferences
        let currentSpacePrefs = spaceLayoutPreferences.spaces
        self.tempSpacePreferences = currentSpacePrefs
        self.originalSpacePreferences = currentSpacePrefs

        // Load available screens
        refreshScreens()
    }

    // MARK: - Screen Management
    func refreshScreens() {
        availableScreens = NSScreen.screens.enumerated().map { index, screen in
            let name = screen.localizedName.isEmpty ? "显示器 \(index + 1)" : screen.localizedName
            return ScreenInfo(id: index, name: name, screen: screen)
        }

        // Ensure selectedScreenIndex is valid
        if selectedScreenIndex >= availableScreens.count {
            selectedScreenIndex = 0
        }
    }

    // MARK: - Layout Selection for Current Screen
    func getLayoutForCurrentScreen() -> String? {
        guard selectedScreenIndex < availableScreens.count else { return nil }
        let screen = availableScreens[selectedScreenIndex]

        // Get current space number
        guard let spaceNumber = SpaceLayoutPreferences.getCurrentSpaceNumber() else {
            return userLayouts.currentLayoutName
        }

        let pair = ScreenSpacePair(screen: screen.id, space: spaceNumber)
        return tempSpacePreferences[pair] ?? userLayouts.currentLayoutName
    }

    func setLayoutForCurrentScreen(_ layoutName: String) {
        guard selectedScreenIndex < availableScreens.count else { return }
        let screen = availableScreens[selectedScreenIndex]

        guard let spaceNumber = SpaceLayoutPreferences.getCurrentSpaceNumber() else { return }

        let pair = ScreenSpacePair(screen: screen.id, space: spaceNumber)
        tempSpacePreferences[pair] = layoutName
        checkForChanges()
    }

    // MARK: - Change Detection
    func checkForChanges() {
        let settingsChanged = !areSettingsEqual(tempAppSettings, originalAppSettings)
        let prefsChanged = tempSpacePreferences != originalSpacePreferences

        isDirty = settingsChanged || prefsChanged
    }

    private func areSettingsEqual(_ lhs: AppSettingsData, _ rhs: AppSettingsData) -> Bool {
        return lhs.modifierKey == rhs.modifierKey &&
               lhs.snapKey == rhs.snapKey &&
               lhs.modifierKeyDelay == rhs.modifierKeyDelay &&
               lhs.fallbackToPreviousSize == rhs.fallbackToPreviousSize &&
               lhs.onlyFallbackToPreviousSizeWithUserEvent == rhs.onlyFallbackToPreviousSizeWithUserEvent &&
               lhs.selectPerDesktopLayout == rhs.selectPerDesktopLayout &&
               lhs.prioritizeCenterToSnap == rhs.prioritizeCenterToSnap &&
               lhs.shakeToSnap == rhs.shakeToSnap &&
               lhs.shakeAccelerationThreshold == rhs.shakeAccelerationThreshold &&
               lhs.snapResize == rhs.snapResize &&
               lhs.snapResizeThreshold == rhs.snapResizeThreshold &&
               lhs.quickSnapShortcut == rhs.quickSnapShortcut &&
               lhs.snapWithRightClick == rhs.snapWithRightClick &&
               lhs.showSnapResizersOnHover == rhs.showSnapResizersOnHover &&
               lhs.cycleWindowsForwardShortcut == rhs.cycleWindowsForwardShortcut &&
               lhs.cycleWindowsBackwardShortcut == rhs.cycleWindowsBackwardShortcut &&
               lhs.snapHighlightStrategy == rhs.snapHighlightStrategy
    }

    // MARK: - Save All Changes
    @MainActor
    func saveAll() {
        // Apply AppSettings
        appSettings.modifierKey = tempAppSettings.modifierKey ?? appSettings.modifierKey
        appSettings.snapKey = tempAppSettings.snapKey ?? appSettings.snapKey
        appSettings.modifierKeyDelay = tempAppSettings.modifierKeyDelay ?? appSettings.modifierKeyDelay
        appSettings.fallbackToPreviousSize = tempAppSettings.fallbackToPreviousSize ?? appSettings.fallbackToPreviousSize
        appSettings.onlyFallbackToPreviousSizeWithUserEvent = tempAppSettings.onlyFallbackToPreviousSizeWithUserEvent ?? appSettings.onlyFallbackToPreviousSizeWithUserEvent
        appSettings.selectPerDesktopLayout = tempAppSettings.selectPerDesktopLayout ?? appSettings.selectPerDesktopLayout
        appSettings.prioritizeCenterToSnap = tempAppSettings.prioritizeCenterToSnap ?? appSettings.prioritizeCenterToSnap
        appSettings.shakeToSnap = tempAppSettings.shakeToSnap ?? appSettings.shakeToSnap
        appSettings.shakeAccelerationThreshold = tempAppSettings.shakeAccelerationThreshold ?? appSettings.shakeAccelerationThreshold
        appSettings.snapResize = tempAppSettings.snapResize ?? appSettings.snapResize
        appSettings.snapResizeThreshold = tempAppSettings.snapResizeThreshold ?? appSettings.snapResizeThreshold
        appSettings.quickSnapShortcut = tempAppSettings.quickSnapShortcut ?? appSettings.quickSnapShortcut
        appSettings.snapWithRightClick = tempAppSettings.snapWithRightClick ?? appSettings.snapWithRightClick
        appSettings.showSnapResizersOnHover = tempAppSettings.showSnapResizersOnHover ?? appSettings.showSnapResizersOnHover
        appSettings.cycleWindowsForwardShortcut = tempAppSettings.cycleWindowsForwardShortcut ?? appSettings.cycleWindowsForwardShortcut
        appSettings.cycleWindowsBackwardShortcut = tempAppSettings.cycleWindowsBackwardShortcut ?? appSettings.cycleWindowsBackwardShortcut
        appSettings.snapHighlightStrategy = tempAppSettings.snapHighlightStrategy ?? appSettings.snapHighlightStrategy
        appSettings.save()

        // Apply SpaceLayoutPreferences
        spaceLayoutPreferences.spaces = tempSpacePreferences
        spaceLayoutPreferences.save()

        // Update hotkeys
        if #available(macOS 12.0, *) {
            quickSnapper.toggleHotkey?.register(for: appSettings.quickSnapShortcut)
            cycleForwardHotkey.register(for: appSettings.cycleWindowsForwardShortcut)
            cycleBackwardHotkey.register(for: appSettings.cycleWindowsBackwardShortcut)
        }

        // Update original values
        originalAppSettings = tempAppSettings
        originalSpacePreferences = tempSpacePreferences
        isDirty = false
    }

    // MARK: - Discard All Changes
    func discardAll() {
        tempAppSettings = originalAppSettings
        tempSpacePreferences = originalSpacePreferences
        isDirty = false
    }

    // MARK: - Refresh (when window opens)
    func refresh() {
        // Reload current settings
        let currentSettings = AppSettingsData(
            modifierKey: appSettings.modifierKey,
            snapKey: appSettings.snapKey,
            modifierKeyDelay: appSettings.modifierKeyDelay,
            fallbackToPreviousSize: appSettings.fallbackToPreviousSize,
            onlyFallbackToPreviousSizeWithUserEvent: appSettings.onlyFallbackToPreviousSizeWithUserEvent,
            selectPerDesktopLayout: appSettings.selectPerDesktopLayout,
            prioritizeCenterToSnap: appSettings.prioritizeCenterToSnap,
            shakeToSnap: appSettings.shakeToSnap,
            shakeAccelerationThreshold: appSettings.shakeAccelerationThreshold,
            snapResize: appSettings.snapResize,
            snapResizeThreshold: appSettings.snapResizeThreshold,
            quickSnapShortcut: appSettings.quickSnapShortcut,
            snapWithRightClick: appSettings.snapWithRightClick,
            showSnapResizersOnHover: appSettings.showSnapResizersOnHover,
            cycleWindowsForwardShortcut: appSettings.cycleWindowsForwardShortcut,
            cycleWindowsBackwardShortcut: appSettings.cycleWindowsBackwardShortcut,
            snapHighlightStrategy: appSettings.snapHighlightStrategy
        )

        self.tempAppSettings = currentSettings
        self.originalAppSettings = currentSettings
        self.tempSpacePreferences = spaceLayoutPreferences.spaces
        self.originalSpacePreferences = spaceLayoutPreferences.spaces
        self.isDirty = false

        refreshScreens()
    }
}
