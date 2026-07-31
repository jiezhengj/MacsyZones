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

import SwiftUI
import ServiceManagement

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var state: SettingsState

    @State private var showAboutDialog = false
    @State private var showResetToDefaultsDialog = false
    @State private var showDialog = false
    @State private var showLayoutHelpDialog = false
    @State private var showModifierKeyHelpDialog = false
    @State private var showSnapKeyHelpDialog = false
    @State private var showQuickSnapperHelpDialog = false
    @State private var showSnapResizeHelpDialog = false
    @State private var showWindowCyclingHelpDialog = false
    @State private var showSnapHighlightStrategyHelpDialog = false
    @State private var showPerDesktopLayoutsHelpDialog = false

    @State private var startAtLogin = false
    @ObservedObject var updater = appUpdater

    func resetDialogs() {
        showDialog = false
        showLayoutHelpDialog = false
        showModifierKeyHelpDialog = false
        showSnapKeyHelpDialog = false
        showQuickSnapperHelpDialog = false
        showSnapResizeHelpDialog = false
        showWindowCyclingHelpDialog = false
        showSnapHighlightStrategyHelpDialog = false
        showPerDesktopLayoutsHelpDialog = false
    }

    func sensitivityLabel(for threshold: CGFloat) -> String {
        let minSensitivity: CGFloat = 10000
        let maxSensitivty: CGFloat = 100000
        let levels = ["极高", "高", "中", "低"]

        let relative = threshold - minSensitivity
        let level = Int((relative / CGFloat(maxSensitivty - minSensitivity)) * CGFloat(levels.count))
        let index = max(0, min(level, levels.count - 1))

        return levels[index]
    }

    func updateStartAtLoginState() {
        if #available(macOS 13.0, *) {
            let actualState = SMAppService.mainApp.status == .enabled
            if startAtLogin != actualState {
                startAtLogin = actualState
            }
        }
    }

    func toggleRunAtStartup() {
        if #available(macOS 13.0, *) {
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateStartAtLoginState()
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateStartAtLoginState()
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Screen selection tab (only show if multiple screens)
            if state.availableScreens.count > 1 {
                ScreenTabBar(state: state)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))

                Divider()
            }

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Layout settings (per screen)
                    LayoutSettingsSection(state: state)

                    Divider().padding(.vertical, 2)

                    // Global settings
                    SnapKeySettingsSection(state: state)

                    Divider().padding(.vertical, 2)

                    ModifierKeySettingsSection(state: state)

                    Divider().padding(.vertical, 2)

                    WindowCyclingSettingsSection(state: state)

                    Divider().padding(.vertical, 2)

                    QuickSnapperSettingsSection(state: state)

                    Divider().padding(.vertical, 2)

                    AdvancedSettingsSection(state: state)
                }
                .padding()
            }

            Divider()

            // Bottom buttons
            HStack {
                Button("重置为默认值") {
                    showResetToDefaultsDialog = true
                    showDialog = true
                }
                .foregroundColor(.red)

                Spacer()

                HStack(spacing: 12) {
                    if updater.isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if updater.isUpdatable == true {
                        Button("更新到 \(updater.latestVersion ?? "")") {
                            updater.checkForUpdates()
                        }
                    }

                    Button("取消") {
                        state.discardAll()
                        SettingsWindowManager.shared.hideWindow()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("确定") {
                        state.saveAll()
                        SettingsWindowManager.shared.hideWindow()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 550, height: 600)
        .alert(isPresented: $showDialog) {
            if showResetToDefaultsDialog {
                return Alert(
                    title: Text("重置为默认值"),
                    message: Text("确定要将所有设置重置为默认值吗？此操作无法撤销。"),
                    primaryButton: .destructive(Text("重置")) {
                        // Reset temp settings to defaults
                        state.tempAppSettings = AppSettingsData()
                        state.checkForChanges()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            } else {
                return Alert(
                    title: Text("提示"),
                    dismissButton: .default(Text("好的"))
                )
            }
        }
        .onAppear {
            updateStartAtLoginState()
        }
    }
}

// MARK: - Screen Tab Bar
struct ScreenTabBar: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(state.availableScreens.enumerated()), id: \.element.id) { index, screen in
                Button(action: {
                    state.selectedScreenIndex = index
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "display")
                            .font(.system(size: 20))
                        Text(screen.name)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(state.selectedScreenIndex == index ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(state.selectedScreenIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Layout Settings Section (per screen)
struct LayoutSettingsSection: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var layouts = userLayouts

    @State private var showLayoutHelpDialog = false
    @State private var showNewView = false
    @State private var showRenameView = false
    @State private var showDuplicateView = false

    var currentLayoutName: String {
        state.getLayoutForCurrentScreen() ?? layouts.currentLayoutName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("布局").font(.subheadline)
                Button(action: { showLayoutHelpDialog = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Picker("选择布局", selection: Binding(
                get: { currentLayoutName },
                set: { state.setLayoutForCurrentScreen($0) }
            )) {
                ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                    Text(name)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())

            HStack(alignment: .center, spacing: 2) {
                let buttonHeight: CGFloat = 25

                Button(action: {
                    if layouts.currentLayout.layoutType == .grid {
                        stopEditing()
                        // Handle grid editor
                    } else {
                        toggleEditing()
                    }
                }) {
                    Image(systemName: "pencil")
                        .frame(height: buttonHeight)
                }

                Button(action: { stopEditing(); showRenameView = true }) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .frame(height: buttonHeight)
                }

                Button(action: { stopEditing(); showDuplicateView = true }) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .frame(height: buttonHeight)
                }

                Button(action: { stopEditing(); showNewView = true }) {
                    Image(systemName: "plus")
                        .frame(height: buttonHeight)
                }

                Button(action: { layouts.removeCurrentLayout() }) {
                    Image(systemName: "trash")
                        .frame(height: buttonHeight)
                }
                .disabled(layouts.layouts.count < 2)
            }
            .frame(maxWidth: .infinity)

            if layouts.currentLayout.layoutType == .grid,
               let gridConfig = layouts.currentLayout.gridConfig {
                HStack(spacing: 4) {
                    Image(systemName: "grid")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("网格: \(gridConfig.rows) x \(gridConfig.columns)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .alert(isPresented: $showLayoutHelpDialog) {
            Alert(
                title: Text("布局"),
                message: Text("您可以为每个屏幕和工作区选择不同的布局。\n\nMacsyZones 会记住您为每个屏幕/工作区选择的布局。"),
                dismissButton: .default(Text("好的"))
            )
        }
    }
}

// MARK: - Snap Key Settings Section
struct SnapKeySettingsSection: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("吸附键").font(.subheadline)

            Picker("吸附键", selection: Binding(
                get: { state.tempAppSettings.snapKey ?? "Shift" },
                set: {
                    state.tempAppSettings.snapKey = $0
                    state.checkForChanges()
                }
            )) {
                Text("无").tag("None")
                Text("Shift").tag("Shift")
                Text("Command").tag("Command")
                Text("Option").tag("Option")
                Text("Control").tag("Control")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())

            Toggle("右键点击吸附", isOn: Binding(
                get: { state.tempAppSettings.snapWithRightClick ?? true },
                set: {
                    state.tempAppSettings.snapWithRightClick = $0
                    state.checkForChanges()
                }
            ))
            .toggleStyle(.checkbox)
            .padding(.top, 4)
        }
    }
}

// MARK: - Modifier Key Settings Section
struct ModifierKeySettingsSection: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("修饰键").font(.subheadline)

            Picker("修饰键", selection: Binding(
                get: { state.tempAppSettings.modifierKey ?? "Control" },
                set: {
                    state.tempAppSettings.modifierKey = $0
                    state.checkForChanges()
                }
            )) {
                Text("无").tag("None")
                Text("Command").tag("Command")
                Text("Option").tag("Option")
                Text("Control").tag("Control")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())

            Text("延迟: \(String(format: "%.2f", Double(state.tempAppSettings.modifierKeyDelay ?? 1000) / 1000.0))秒")
                .font(.caption2)

            Slider(value: Binding(
                get: { Double(state.tempAppSettings.modifierKeyDelay ?? 1000) },
                set: {
                    state.tempAppSettings.modifierKeyDelay = Int($0)
                    state.checkForChanges()
                }
            ), in: 0...2000, step: 100)
        }
    }
}

// MARK: - Window Cycling Settings Section
struct WindowCyclingSettingsSection: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("窗口循环").font(.subheadline)

            VStack(alignment: .leading, spacing: 10) {
                Group {
                    Text("向前循环").font(.caption2)
                    ShortcutInputView(shortcut: Binding(
                        get: { state.tempAppSettings.cycleWindowsForwardShortcut ?? "Command+]" },
                        set: {
                            state.tempAppSettings.cycleWindowsForwardShortcut = $0
                            state.checkForChanges()
                        }
                    ))
                }

                Group {
                    Text("向后循环").font(.caption2)
                    ShortcutInputView(shortcut: Binding(
                        get: { state.tempAppSettings.cycleWindowsBackwardShortcut ?? "Command+[" },
                        set: {
                            state.tempAppSettings.cycleWindowsBackwardShortcut = $0
                            state.checkForChanges()
                        }
                    ))
                }
            }
        }
    }
}

// MARK: - Quick Snapper Settings Section
struct QuickSnapperSettingsSection: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速吸附").font(.subheadline)

            ShortcutInputView(shortcut: Binding(
                get: { state.tempAppSettings.quickSnapShortcut ?? "Control+Shift+S" },
                set: {
                    state.tempAppSettings.quickSnapShortcut = $0
                    state.checkForChanges()
                }
            ))

            Divider().padding(.vertical, 2)

            Toggle("吸附调整大小", isOn: Binding(
                get: { state.tempAppSettings.snapResize ?? true },
                set: {
                    state.tempAppSettings.snapResize = $0
                    state.checkForChanges()
                }
            ))
            .toggleStyle(.checkbox)

            if state.tempAppSettings.snapResize ?? true {
                Text("阈值: \(Int(state.tempAppSettings.snapResizeThreshold ?? 33))像素")
                    .font(.caption2)
                    .padding(.top, 4)

                Slider(value: Binding(
                    get: { Double(state.tempAppSettings.snapResizeThreshold ?? 33) },
                    set: {
                        state.tempAppSettings.snapResizeThreshold = CGFloat($0)
                        state.checkForChanges()
                    }
                ), in: 5...67, step: 2)

                Toggle("悬停时显示吸附调整器", isOn: Binding(
                    get: { state.tempAppSettings.showSnapResizersOnHover ?? true },
                    set: {
                        state.tempAppSettings.showSnapResizersOnHover = $0
                        state.checkForChanges()
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Advanced Settings Section
struct AdvancedSettingsSection: View {
    @ObservedObject var state: SettingsState
    @State private var startAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                Toggle("优先区域中心", isOn: Binding(
                    get: { state.tempAppSettings.prioritizeCenterToSnap ?? true },
                    set: {
                        state.tempAppSettings.prioritizeCenterToSnap = $0
                        state.checkForChanges()
                    }
                ))
                .toggleStyle(.checkbox)

                HStack(spacing: 5) {
                    Text("区域高亮策略").font(.subheadline)
                        .padding(.top, 4)
                }

                Picker("区域高亮策略", selection: Binding(
                    get: { state.tempAppSettings.snapHighlightStrategy ?? .centerProximity },
                    set: {
                        state.tempAppSettings.snapHighlightStrategy = $0
                        state.checkForChanges()
                    }
                )) {
                    Text("中心接近").tag(SnapHighlightStrategy.centerProximity)
                    Text("平面").tag(SnapHighlightStrategy.flat)
                }
                .labelsHidden()
                .pickerStyle(MenuPickerStyle())
            }

            Divider().padding(.vertical, 2)

            Toggle("取消吸附时恢复之前大小", isOn: Binding(
                get: { state.tempAppSettings.fallbackToPreviousSize ?? true },
                set: {
                    state.tempAppSettings.fallbackToPreviousSize = $0
                    state.checkForChanges()
                }
            ))
            .toggleStyle(.checkbox)

            if state.tempAppSettings.fallbackToPreviousSize ?? true {
                Toggle("仅用户操作时", isOn: Binding(
                    get: { state.tempAppSettings.onlyFallbackToPreviousSizeWithUserEvent ?? true },
                    set: {
                        state.tempAppSettings.onlyFallbackToPreviousSizeWithUserEvent = $0
                        state.checkForChanges()
                    }
                ))
                .toggleStyle(.checkbox)
            }

            Divider().padding(.vertical, 2)

            Toggle("按桌面布局", isOn: Binding(
                get: { state.tempAppSettings.selectPerDesktopLayout ?? true },
                set: {
                    state.tempAppSettings.selectPerDesktopLayout = $0
                    state.checkForChanges()
                }
            ))
            .toggleStyle(.checkbox)

            Divider().padding(.vertical, 2)

            Toggle("摇晃吸附", isOn: Binding(
                get: { state.tempAppSettings.shakeToSnap ?? true },
                set: {
                    state.tempAppSettings.shakeToSnap = $0
                    state.checkForChanges()
                }
            ))
            .toggleStyle(.checkbox)

            if state.tempAppSettings.shakeToSnap ?? true {
                HStack {
                    Text("摇晃力度").font(.caption2)
                        .padding(.top, 4)
                    Spacer()
                    Text(sensitivityLabel(for: state.tempAppSettings.shakeAccelerationThreshold ?? 50000))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Slider(value: Binding(
                    get: { Double(100000 - (state.tempAppSettings.shakeAccelerationThreshold ?? 50000)) },
                    set: {
                        state.tempAppSettings.shakeAccelerationThreshold = CGFloat(100000 - $0)
                        state.checkForChanges()
                    }
                ), in: 10000...100000, step: 5000)
            }

            Divider().padding(.vertical, 2)

            if #available(macOS 13.0, *) {
                Toggle("登录时启动", isOn: $startAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: startAtLogin) { _ in
                        toggleRunAtStartup()
                    }
                    .onAppear {
                        updateStartAtLoginState()
                    }
            }
        }
    }

    func sensitivityLabel(for threshold: CGFloat) -> String {
        let minSensitivity: CGFloat = 10000
        let maxSensitivty: CGFloat = 100000
        let levels = ["极高", "高", "中", "低"]

        let relative = threshold - minSensitivity
        let level = Int((relative / CGFloat(maxSensitivty - minSensitivity)) * CGFloat(levels.count))
        let index = max(0, min(level, levels.count - 1))

        return levels[index]
    }

    func updateStartAtLoginState() {
        if #available(macOS 13.0, *) {
            let actualState = SMAppService.mainApp.status == .enabled
            if startAtLogin != actualState {
                startAtLogin = actualState
            }
        }
    }

    func toggleRunAtStartup() {
        if #available(macOS 13.0, *) {
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateStartAtLoginState()
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateStartAtLoginState()
                }
            }
        }
    }
}
