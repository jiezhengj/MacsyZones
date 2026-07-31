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

import SwiftUI
import ServiceManagement
import Combine

class PopoverState: ObservableObject {
    static let shared = PopoverState()
    @Published var shouldStopListening = false
}

struct ShortcutInputView: View {
    @Binding var shortcut: String
    var isFocused: Binding<Bool> = .constant(false)
    
    @State private var isListening = false
    @State private var flagsMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    @ObservedObject private var popoverState = PopoverState.shared

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                toggleListening()
            }) {
                VStack {
                    Text(isListening ? "Listening for shortcut..." : shortcut.isEmpty ? "Click to set shortcut" : presentingShortcut(shortcut))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(7)
                }
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isListening ? Color(NSColor.selectedTextBackgroundColor).opacity(0.2) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isListening ? Color(NSColor.selectedTextBackgroundColor) : Color.gray, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            if !shortcut.isEmpty {
                Button(action: {
                    stopListening()
                    shortcut = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .onDisappear {
            stopListening()
            isFocused.wrappedValue = false
        }
        .onChange(of: isListening) { newValue in
            isFocused.wrappedValue = newValue
        }
        .onChange(of: popoverState.shouldStopListening) { shouldStop in
            if shouldStop && isListening {
                stopListening()
            }
        }
    }
    
    private func toggleListening() {
        isListening.toggle()
        if isListening {
            startListening()
        } else {
            stopListening()
        }
    }

    private func startListening() {
        isListening = true
        
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            self.currentModifiers = event.modifierFlags
            return event
        }
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyString: String
            switch event.keyCode {
            case 48: keyString = "Tab"
            case 36: keyString = "Return"
            case 51: keyString = "Delete"
            case 53: keyString = "Escape"
            case 123: keyString = "Left"
            case 124: keyString = "Right"
            case 125: keyString = "Down"
            case 126: keyString = "Up"
            case 49: keyString = "Space"
            default:
                keyString = event.charactersIgnoringModifiers?.uppercased() ?? ""
            }
            
            var components = [String]()
            
            if self.currentModifiers.contains(.command) {
                components.append("Command")
            }
            if self.currentModifiers.contains(.option) {
                components.append("Option")
            }
            if self.currentModifiers.contains(.control) {
                components.append("Control")
            }
            if self.currentModifiers.contains(.shift) {
                components.append("Shift")
            }
            
            if !keyString.isEmpty {
                components.append(keyString)
            }
            
            self.shortcut = components.joined(separator: "+")
            self.stopListening()
            return nil
        }
    }

    private func stopListening() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        flagsMonitor = nil
        keyMonitor = nil
        currentModifiers = []
        isListening = false
    }

    private func createShortcutString(from event: NSEvent) -> String {
        var components = [String]()

        if event.modifierFlags.contains(.command) {
            components.append("Command")
        }
        if event.modifierFlags.contains(.option) {
            components.append("Option")
        }
        if event.modifierFlags.contains(.control) {
            components.append("Control")
        }
        if event.modifierFlags.contains(.shift) {
            components.append("Shift")
        }

        if let characters = event.charactersIgnoringModifiers {
            components.append(characters.uppercased())
        }

        return components.joined(separator: "+")
    }
}

struct Main: View {
    @Binding var page: String

    @ObservedObject var settings = appSettings

    @ObservedObject var layouts = userLayouts

    @State var showAboutDialog = false
    @State var showResetToDefaultsDialog = false
    
    @State var showDialog = false
    @State var showLayoutHelpDialog = false
    @State var showModifierKeyHelpDialog = false
    @State var showSnapKeyHelpDialog = false
    @State var showQuickSnapperHelpDialog = false
    @State var showSnapResizeHelpDialog = false
    @State var showWindowCyclingHelpDialog = false
    @State var showSnapHighlightStrategyHelpDialog = false
    @State var showPerDesktopLayoutsHelpDialog = false
    
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
        let levels = ["Very High", "High", "Medium", "Low"]
        
        let relative = threshold - minSensitivity
        let level = Int((relative / CGFloat(maxSensitivty - minSensitivity)) * CGFloat(levels.count))
        let index = max(0, min(level, levels.count - 1))
        
        return levels[index]
    }
    
    @State private var startAtLogin = false
    
    @ObservedObject var updater = appUpdater
    
    func updateStartAtLoginState() {
        if #available(macOS 13.0, *) {
            let actualState = SMAppService.mainApp.status == .enabled
            
            if startAtLogin != actualState {
                startAtLogin = actualState
                debugLog("Updated start at login state to: \(actualState)")
            }
        }
    }
    
    func toggleRunAtStartup() {
        if #available(macOS 13.0, *) {
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                    debugLog("Successfully registered app to start at login")
                } else {
                    try SMAppService.mainApp.unregister()
                    debugLog("Successfully unregistered app from start at login")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateStartAtLoginState()
                }
                
            } catch {
                debugLog("Failed to toggle run at startup: \(error)")
                DispatchQueue.main.async {
                    self.updateStartAtLoginState()
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 5) {
                Text("MacsyZones").font(.headline)
                Button(action: {
                    resetDialogs()
                    showDialog = true
                    showAboutDialog = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .imageScale(.small)
                        .contentShape(Circle())
                }
                .contentShape(Circle())
                .buttonStyle(BorderlessButtonStyle())
                .modifier {
                    if #available(macOS 14.0, *) {
                        $0.focusEffectDisabled(true)
                    } else { $0 }
                }
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        HStack(spacing: 5) {
                            Text("布局").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showLayoutHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Picker("Select Layout", selection: $layouts.currentLayoutName) {
                            ForEach(Array(layouts.layouts.keys), id: \.self) { name in
                                Text(name)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onAppear {
                            if let preferedLayout = spaceLayoutPreferences.getCurrent() {
                                layouts.currentLayoutName = preferedLayout
                            }
                        }
                        .onChange(of: layouts.currentLayoutName) { _ in
                            guard !isFitting else { return }

                            let wasEditing = isEditing
                            stopEditing()
                            userLayouts.selectLayout(layouts.currentLayoutName)
                            if wasEditing { startEditing() }
                            spaceLayoutPreferences.setCurrent(layoutName: layouts.currentLayoutName)
                            spaceLayoutPreferences.save()
                        }
                        
                        HStack(alignment: .center, spacing: 2) {
                            let buttonHeight: CGFloat = 25

                            Button(action: {
                                if layouts.currentLayout.layoutType == .grid {
                                    stopEditing()
                                    page = "editGrid"
                                } else {
                                    toggleEditing()
                                }
                            }) {
                                Image(systemName: "pencil")
                                    .frame(height: buttonHeight)
                            }

                            Button(action: { stopEditing(); page = "rename" }) {
                                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                                    .frame(height: buttonHeight)
                            }

                            Button(action: { stopEditing(); page = "duplicate" }) {
                                Image(systemName: "plus.rectangle.on.rectangle")
                                    .frame(height: buttonHeight)
                            }

                            Button(action: { stopEditing(); page = "new" }) {
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

                    Divider().padding(.vertical, 2)
                    
                    Group {
                        HStack(spacing: 5) {
                            Text("吸附键").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showSnapKeyHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Picker("吸附键", selection: $settings.snapKey) {
                            Text("无").tag("None")
                            Text("Shift").tag("Shift")
                            Text("Command").tag("Command")
                            Text("Option").tag("Option")
                            Text("Control").tag("Control")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: settings.snapKey) { _ in appSettings.save() }
                        
                        Toggle("右键点击吸附", isOn: $settings.snapWithRightClick)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.snapWithRightClick) { _ in appSettings.save() }
                            .padding(.top, 4)
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    Group {
                        HStack(spacing: 5) {
                            Text("修饰键").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showModifierKeyHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Picker("修饰键", selection: $settings.modifierKey) {
                            Text("无").tag("None")
                            Text("Command").tag("Command")
                            Text("Option").tag("Option")
                            Text("Control").tag("Control")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: settings.modifierKey) { _ in appSettings.save() }
                        
                        Text("延迟: \(String(format: "%.2f", Double(settings.modifierKeyDelay) / 1000.0))秒")
                            .font(.caption2)
                        Slider(value: Binding(
                            get: { Double(settings.modifierKeyDelay) },
                            set: { settings.modifierKeyDelay = Int($0) }
                        ), in: 0...2000, step: 100)
                        .onChange(of: settings.modifierKeyDelay) { _ in appSettings.save() }
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 5) {
                            Text("窗口循环").font(.subheadline)
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showWindowCyclingHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Group {
                                Text("向前循环").font(.caption2)
                                ShortcutInputView(shortcut: $settings.cycleWindowsForwardShortcut)
                                    .onChange(of: settings.cycleWindowsForwardShortcut) { newShortcut in
                                        if #available(macOS 12.0, *) {
                                            cycleForwardHotkey.register(for: newShortcut)
                                        }
                                        
                                        appSettings.save()
                                    }
                            }
                            
                            Group {
                                Text("向后循环").font(.caption2)
                                ShortcutInputView(shortcut: $settings.cycleWindowsBackwardShortcut)
                                    .onChange(of: settings.cycleWindowsBackwardShortcut) { newShortcut in
                                        if #available(macOS 12.0, *) {
                                            cycleBackwardHotkey.register(for: newShortcut)
                                        }
                                        
                                        appSettings.save()
                                    }
                            }
                        }
                    }
                }
                .frame(minWidth: 220)
                .fixedSize()
                
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading) {
                        VStack {
                            HStack(spacing: 5) {
                                Text("快速吸附").font(.subheadline)
                                Button(action: {
                                    resetDialogs()
                                    showDialog = true
                                    showQuickSnapperHelpDialog = true
                                }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 13))
                                        .imageScale(.small)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            ShortcutInputView(shortcut: $settings.quickSnapShortcut)
                                .onChange(of: settings.quickSnapShortcut) { _ in
                                    if #available(OSX 12.0, *) {
                                        quickSnapper.toggleHotkey?.register(for: settings.quickSnapShortcut)
                                    }
                                    
                                    appSettings.save()
                                }
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Toggle("吸附调整大小", isOn: $settings.snapResize)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.snapResize) { _ in appSettings.save() }
                        
                        if settings.snapResize {
                            Text("阈值: \(Int(settings.snapResizeThreshold))像素")
                                .font(.caption2)
                                .padding(.top, 4)
                            
                            Slider(value: Binding(
                                get: { Double(settings.snapResizeThreshold) },
                                set: { settings.snapResizeThreshold = CGFloat($0) }
                            ), in: 5...67, step: 2)
                            .onChange(of: settings.snapResizeThreshold) { _ in appSettings.save() }
                            
                            Toggle("悬停时显示吸附调整器", isOn: $settings.showSnapResizersOnHover)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.showSnapResizersOnHover) { _ in appSettings.save() }
                            
                            Divider().padding(.vertical, 2)
                        }
                        
                        Group {
                            Toggle("优先区域中心", isOn: $settings.prioritizeCenterToSnap)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.prioritizeCenterToSnap) { _ in appSettings.save() }
                            
                            HStack(spacing: 5) {
                                Text("区域高亮策略").font(.subheadline)
                                    .padding(.top, 4)
                                
                                Button(action: {
                                    resetDialogs()
                                    showDialog = true
                                    showSnapHighlightStrategyHelpDialog = true
                                }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 13))
                                        .imageScale(.small)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            Picker("区域高亮策略", selection: $settings.snapHighlightStrategy) {
                                Text("中心接近").tag(SnapHighlightStrategy.centerProximity)
                                Text("平面").tag(SnapHighlightStrategy.flat)
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: settings.snapKey) { _ in appSettings.save() }
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Toggle("取消吸附时恢复之前大小", isOn: $settings.fallbackToPreviousSize)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.fallbackToPreviousSize) { _ in appSettings.save() }
                        
                        if settings.fallbackToPreviousSize {
                            Toggle("仅用户操作时", isOn: $settings.onlyFallbackToPreviousSizeWithUserEvent)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.onlyFallbackToPreviousSizeWithUserEvent) { _ in appSettings.save() }
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            Toggle("按桌面布局", isOn: $settings.selectPerDesktopLayout)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.selectPerDesktopLayout) { _ in appSettings.save() }
                            
                            Button(action: {
                                resetDialogs()
                                showDialog = true
                                showPerDesktopLayoutsHelpDialog = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .imageScale(.small)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Toggle("摇晃吸附", isOn: $settings.shakeToSnap)
                            .toggleStyle(.checkbox)
                            .onChange(of: settings.shakeToSnap) { _ in appSettings.save() }
                        
                        if settings.shakeToSnap {
                            HStack {
                                Text("摇晃力度").font(.caption2)
                                    .padding(.top, 4)
                                Spacer()
                                Text(sensitivityLabel(for: settings.shakeAccelerationThreshold)).font(.caption2).foregroundColor(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(100000 - settings.shakeAccelerationThreshold) },
                                set: { settings.shakeAccelerationThreshold = CGFloat(100000 - $0) }
                            ), in: 10000...100000, step: 5000)
                            .onChange(of: settings.shakeAccelerationThreshold) { _ in appSettings.save() }
                        }
                    }
                    
                    if #available(macOS 13.0, *) {
                        Divider().padding(.vertical, 2)
                        
                        Toggle("登录时启动", isOn: $startAtLogin)
                            .toggleStyle(.checkbox)
                            .onChange(of: startAtLogin) { _ in 
                                toggleRunAtStartup()
                            }
                            .onAppear { 
                                updateStartAtLoginState()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                                updateStartAtLoginState()
                            }
                    }
                }
                .fixedSize()
            }

            HStack {
                Button(action: { updater.checkForUpdates() }) {
                    HStack {
                        if updater.isChecking {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("检查中...")
                        } else if updater.isDownloading {
                            ProgressView().font(.system(size: 12))
                            Text("下载中...")
                        } else if let isUpdatable = updater.isUpdatable, let latestVersion = updater.latestVersion, isUpdatable {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("更新到 \(latestVersion)")
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("检查更新")
                        }
                    }
                }
                .disabled(updater.isChecking || updater.isDownloading)
                
                Button(action: {
                    showResetToDefaultsDialog = true
                    showDialog = true
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise.circle")
                        Text("重置")
                    }
                }
                
                if #available(macOS 12.0, *) {
                    Button(action: { showOnboarding() }) {
                        Image(systemName: "questionmark.circle")
                        Text("帮助")
                    }
                }
                
                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text("退出")
                    }
                }
            }
            .fixedSize()
            .padding(.top, 5)
        }
        .frame(minWidth: 400)
        .fixedSize()
        .alert(isPresented: $showDialog) {
            if showResetToDefaultsDialog {
                return Alert(
                    title: Text("重置为默认值"),
                    message: Text("确定要将所有设置重置为默认值吗？此操作无法撤销。"),
                    primaryButton: .destructive(Text("重置")) {
                        Task { @MainActor in
                            appSettings.resetToDefaults()
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            } else if showLayoutHelpDialog {
                return Alert(
                   title: Text("布局"),
                   message: Text("""
                   您可以添加、删除、重命名布局，并为当前（屏幕，工作区）对选择布局。

                   MacsyZones 会记住您为每个（屏幕，工作区）对选择的布局。

                   重要提示：编辑布局时请不要将区域放置在多个屏幕上。这对 MacsyZones 来说是未定义行为。

                   相反，您可以为每个屏幕（或工作区）创建多个布局并轻松切换；MacsyZones 会记住您为每个（屏幕，工作区）对选择的布局。

                   祝您使用愉快！ 🥳
               """),
                   dismissButton: .default(Text("好的"))
                )
            } else if showModifierKeyHelpDialog {
                return Alert(
                   title: Text("修饰键"),
                   message: Text("""
                       修饰键主要用于执行吸附调整大小，但您也可以使用它将窗口吸附到区域。

                       修饰键有一个可调整的延迟；当您按住修饰键时，MacsyZones 将开始显示区域和它们之间的吸附调整器。

                       您可以按住修饰键并使用鼠标或触控板执行吸附调整大小。

                       祝您使用愉快！ 🥳
                   """),
                   dismissButton: .default(Text("好的"))
                )
            } else if showSnapKeyHelpDialog {
                return Alert(
                   title: Text("吸附键"),
                   message: Text("""
                       吸附键用于将窗口吸附到区域。

                       您可以按住吸附键并将窗口拖动到区域。

                       吸附键仅在移动窗口时有效。

                       祝您使用愉快！ 🥳
                   """),
                   dismissButton: .default(Text("好的"))
                )
           } else if showQuickSnapperHelpDialog {
               return Alert(
                   title: Text("快速吸附快捷键"),
                   message: Text("""
                       快速吸附快捷键用于激活快速吸附器。

                       快速吸附器是一个允许您使用键盘轻松快速地将窗口吸附到区域的功能。

                       它也可用作窗口切换器。（类似 Windows 的 Alt+Tab 窗口切换器。）

                       祝您使用愉快！ 🥳
                   """),
                   dismissButton: .default(Text("好的"))
                )
           } else if showSnapResizeHelpDialog {
               return Alert(
                  title: Text("吸附调整大小"),
                  message: Text("""
                      吸附调整大小是一个允许您将窗口大小调整为区域的功能。

                      您可以启用或禁用吸附调整大小并调整吸附阈值。

                      修饰键有一个可调整的延迟；当您按住修饰键时，MacsyZones 将开始显示区域和它们之间的吸附调整器。

                      您可以按住修饰键并使用鼠标或触控板执行吸附调整大小。

                      祝您使用愉快！ 🥳
                  """),
                  dismissButton: .default(Text("好的"))
               )
           } else if showWindowCyclingHelpDialog {
               return Alert(
                  title: Text("窗口循环"),
                  message: Text("""
                      窗口循环允许您在同一区域内快速切换多个窗口。

                      当您将多个窗口放置在同一区域时，可以使用配置的快捷键在它们之间循环。

                      • 向前循环：将区域中的下一个窗口带到前台
                      • 向后循环：将区域中的上一个窗口带到前台

                      循环仅影响当前放置在区域中的窗口，并将在与当前聚焦窗口相同区域的窗口之间循环。

                      祝您使用愉快！ 🥳
                  """),
                  dismissButton: .default(Text("好的"))
               )
            } else if showSnapHighlightStrategyHelpDialog {
                return Alert(
                    title: Text("区域高亮策略"),
                    message: Text("""
                        当您移动窗口并按住吸附键时，您会看到您的区域；此选项让您可以选择如何高亮区域。

                        我们有两个选项：中心接近和平面：

                        • 中心接近：距离鼠标指针最近的中心圆的区域将被高亮。
                        • 平面：在鼠标指针下最前面可见的区域将被高亮。

                        注意：另一个选项"优先区域中心"具有更高的优先级。

                        祝您使用愉快！ 🥳
                    """),
                    dismissButton: .default(Text("好的"))
                )
            } else if showPerDesktopLayoutsHelpDialog {
                return Alert(
                    title: Text("按桌面布局"),
                    message: Text("""
                        如果启用此选项，MacsyZones 将记住您为每个 macOS 工作区（虚拟桌面）/ 屏幕对选择的布局。

                        祝您使用愉快！ 🥳
                    """),
                    dismissButton: .default(Text("好的"))
                )
            } else {
                return Alert(
                    title: Text("关于 MacsyZones"),
                    message: Text("""
                        Copyright ©️ 2024, Oğuzhan Eroğlu (https://meowingcat.io).

                        MacsyZones 帮助您高效地组织窗口。

                        版本: \(appVersion) (构建: \(appBuild))
                    """),
                    dismissButton: .cancel(Text("好的"))
                )
            }
        }
    }
}

struct NewView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @State var layoutName: String = "我的布局"
    @State var layoutType: LayoutType = .zone
    @State var gridRows: Int = 3
    @State var gridColumns: Int = 3

    @State var showAlreadyExistsAlert: Bool = false

    var body: some View {
        VStack {
            Text("MacsyZones").font(.headline).padding(.bottom, 10)

            Text("布局名称:").font(.subheadline)

            VStack {
                TextField("输入布局名称", text: $layoutName).cornerRadius(5)

                Picker("布局类型", selection: $layoutType) {
                    Text("区域").tag(LayoutType.zone)
                    Text("网格").tag(LayoutType.grid)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.vertical, 4)

                if layoutType == .grid {
                    VStack(spacing: 6) {
                        Stepper("行数: \(gridRows)", value: $gridRows, in: 1...24)
                        Stepper("列数: \(gridColumns)", value: $gridColumns, in: 1...24)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                HStack(alignment: .center) {
                    Button(action: {
                        page = "main"
                    }) {
                        Image(systemName: "xmark").foregroundColor(.red)
                        Text("取消")
                    }

                    Button(action: {
                        if layoutName.trimmingCharacters(in: .whitespaces).isEmpty {
                            return
                        }

                        if layouts.layouts.keys.contains(layoutName) {
                            showAlreadyExistsAlert = true
                            return
                        }

                        switch layoutType {
                        case .zone:
                            layouts.createLayout(name: layoutName)
                            startEditing()
                        case .grid:
                            layouts.createGridLayout(name: layoutName, rows: gridRows, columns: gridColumns)
                        }

                        page = "main"
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("创建")
                    }
                    .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .alert(isPresented: $showAlreadyExistsAlert) {
            Alert(
                title: Text("提示"),
                message: Text("已存在同名布局，请选择其他名称。"),
                dismissButton: .default(Text("好的"))
            )
        }
    }
}

struct RenameView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @State var layoutName: String = ""

    var body: some View {
        VStack {
            Text("MacsyZones").font(.headline).padding(.bottom, 10)

            Text("布局名称:").font(.subheadline)

            VStack {
                TextField("输入布局名称", text: $layoutName).cornerRadius(5)

                HStack(alignment: .center) {
                    Button(action: {
                        page = "main"
                    }) {
                        Image(systemName: "xmark").foregroundColor(.red)
                        Text("取消")
                    }

                    Button(action: {
                        if layoutName.trimmingCharacters(in: .whitespaces).isEmpty {
                            return
                        }

                        userLayouts.renameCurrentLayout(to: layoutName)
                        page = "main"
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("重命名")
                    }
                    .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct DuplicateView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @State var layoutName: String

    @State var showAlreadyExistsAlert: Bool = false

    var body: some View {
        VStack {
            Text("MacsyZones").font(.headline).padding(.bottom, 10)

            Text("布局名称:").font(.subheadline)

            VStack {
                TextField("输入布局名称", text: $layoutName).cornerRadius(5)

                HStack(alignment: .center) {
                    Button(action: {
                        page = "main"
                    }) {
                        Image(systemName: "xmark").foregroundColor(.red)
                        Text("取消")
                    }

                    Button(action: {
                        if layoutName.trimmingCharacters(in: .whitespaces).isEmpty {
                            return
                        }

                        if layouts.layouts.keys.contains(layoutName) {
                            showAlreadyExistsAlert = true
                            return
                        }

                        layouts.duplicateCurrentLayout(newName: layoutName)
                        startEditing()

                        page = "main"
                    }) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                        Text("复制")
                    }
                    .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .alert(isPresented: $showAlreadyExistsAlert) {
            Alert(
                title: Text("提示"),
                message: Text("已存在同名布局，请选择其他名称。"),
                dismissButton: .default(Text("好的"))
            )
        }
    }
}

struct GridPreview: View {
    let rows: Int
    let columns: Int

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<columns, id: \.self) { col in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                        .frame(width: cellWidth - 3, height: cellHeight - 3)
                        .position(
                            x: CGFloat(col) * cellWidth + cellWidth / 2,
                            y: CGFloat(row) * cellHeight + cellHeight / 2
                        )
                }
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct GridEditorView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @State var gridRows: Int
    @State var gridColumns: Int

    init(page: Binding<String>) {
        _page = page
        let config = userLayouts.currentLayout.gridConfig ?? GridConfig.defaultGrid
        _gridRows = State(initialValue: config.rows)
        _gridColumns = State(initialValue: config.columns)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("MacsyZones").font(.headline).padding(.bottom, 4)

            Text("Edit Grid: \(layouts.currentLayoutName)").font(.subheadline)

            GridPreview(rows: gridRows, columns: gridColumns)
                .frame(width: 200, height: 130)
                .padding(.vertical, 4)

            VStack(spacing: 6) {
                Stepper("Rows: \(gridRows)", value: $gridRows, in: 1...24)
                Stepper("Columns: \(gridColumns)", value: $gridColumns, in: 1...24)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 12) {
                Button(action: {
                    page = "main"
                }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("取消")
                }

                Button(action: {
                    let newConfig = GridConfig(rows: gridRows, columns: gridColumns)
                    layouts.currentLayout.gridConfig = newConfig
                    layouts.currentLayout.gridLayoutWindow?.gridConfig = newConfig
                    layouts.currentLayout.gridLayoutWindow?.updateView()
                    layouts.save()
                    page = "main"
                }) {
                    Image(systemName: "checkmark").foregroundColor(.green)
                    Text("保存")
                }
            }
        }
    }
}

struct TrayPopupView: View {
    @ObservedObject var ready = macsyReady

    @State private var page = "main"
    @ObservedObject var layouts = userLayouts

    func generateUniqueDuplicateName() -> String {
        let baseName = layouts.currentLayoutName
        var copyName = baseName + " Copy"
        var counter = 2

        while layouts.layouts.keys.contains(copyName) {
            copyName = baseName + " Copy \(counter)"
            counter += 1
        }

        return copyName
    }

    var body: some View {
        if !ready.isReady {
            VStack {
                VStack(alignment: .center) {
                    Text("MacsyZones is loading...").padding(.bottom, 10).padding(.top, 25)
                    ProgressView().padding(.bottom, 25)
                }.frame(width: 240)
            }
        } else {
            VStack {
                switch page {
                case "new":
                    NewView(page: $page)
                case "rename":
                    RenameView(page: $page, layoutName: layouts.currentLayoutName)
                case "duplicate":
                    DuplicateView(page: $page, layoutName: generateUniqueDuplicateName())
                case "editGrid":
                    GridEditorView(page: $page)
                default:
                    Main(page: $page)
                }
            }
            .padding()
        }
    }
}

extension NSColor {
    func saturate(by factor: CGFloat) -> NSColor {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * factor, 1.0), brightness: b, alpha: a)
    }

    func enlighten(by factor: CGFloat) -> NSColor {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: min(b * factor, 1.0), alpha: a)
    }
}

#Preview {
    TrayPopupView(layouts: UserLayouts())
}
