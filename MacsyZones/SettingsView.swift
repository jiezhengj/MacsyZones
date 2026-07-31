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

                if #available(macOS 12.0, *) {
                    Button(action: { showOnboarding() }) {
                        Image(systemName: "info.circle")
                        Text("关于")
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if updater.isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if updater.isDownloading {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("下载中...")
                            .font(.caption)
                    } else if updater.isUpdatable == true {
                        Button("更新到 \(updater.latestVersion ?? "")") {
                            updater.downloadAndInstall()
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(state.selectedScreenIndex == index ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(state.selectedScreenIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
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
                .help("编辑布局")

                Button(action: { stopEditing(); showRenameView = true }) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .frame(height: buttonHeight)
                }
                .help("重命名布局")

                Button(action: { stopEditing(); showDuplicateView = true }) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .frame(height: buttonHeight)
                }
                .help("复制布局")

                Button(action: { stopEditing(); showNewView = true }) {
                    Image(systemName: "plus")
                        .frame(height: buttonHeight)
                }
                .help("新建布局")

                Button(action: { layouts.removeCurrentLayout() }) {
                    Image(systemName: "trash")
                        .frame(height: buttonHeight)
                }
                .disabled(layouts.layouts.count < 2)
                .help("删除布局")
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
                title: Text("添加和设计布局"),
                message: Text("创建适合您需求的自定义布局。\n\n1. 点击菜单栏中的铅笔图标进入编辑模式\n2. 点击 + 按钮添加区域\n3. 通过拖动边缘调整区域大小和位置\n4. 为不同的工作流程创建新布局\n\n注意：MacsyZones 会记住您为每个屏幕和工作区组合选择的首选布局。您可以在屏幕上选择首选布局。"),
                dismissButton: .default(Text("确定"))
            )
        }
        .sheet(isPresented: $showRenameView) {
            RenameView(isPresented: $showRenameView, layouts: layouts)
        }
        .sheet(isPresented: $showDuplicateView) {
            DuplicateView(isPresented: $showDuplicateView, layouts: layouts)
        }
        .sheet(isPresented: $showNewView) {
            NewView(isPresented: $showNewView, layouts: layouts)
        }
    }
}

// MARK: - Rename View (from upstream)
struct RenameView: View {
    @Binding var isPresented: Bool
    @ObservedObject var layouts: UserLayouts
    @State private var layoutName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("重命名布局")
                .font(.headline)

            TextField("输入布局名称", text: $layoutName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 250)

            HStack(spacing: 12) {
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("取消")
                }

                Button(action: {
                    if layoutName.trimmingCharacters(in: .whitespaces).isEmpty { return }
                    layouts.renameCurrentLayout(to: layoutName)
                    isPresented = false
                }) {
                    Image(systemName: "checkmark").foregroundColor(.green)
                    Text("重命名")
                }
                .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            layoutName = layouts.currentLayoutName
        }
    }
}

// MARK: - Duplicate View (from upstream)
struct DuplicateView: View {
    @Binding var isPresented: Bool
    @ObservedObject var layouts: UserLayouts
    @State private var layoutName: String
    @State private var showAlreadyExistsAlert: Bool = false

    init(isPresented: Binding<Bool>, layouts: UserLayouts) {
        self._isPresented = isPresented
        self.layouts = layouts
        self._layoutName = State(initialValue: layouts.currentLayoutName + " 副本")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("复制布局")
                .font(.headline)

            TextField("输入布局名称", text: $layoutName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 250)

            HStack(spacing: 12) {
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("取消")
                }

                Button(action: {
                    if layoutName.trimmingCharacters(in: .whitespaces).isEmpty { return }
                    if layouts.layouts.keys.contains(layoutName) {
                        showAlreadyExistsAlert = true
                        return
                    }
                    layouts.duplicateCurrentLayout(newName: layoutName)
                    isPresented = false
                }) {
                    Image(systemName: "checkmark").foregroundColor(.green)
                    Text("复制")
                }
                .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .alert(isPresented: $showAlreadyExistsAlert) {
            Alert(
                title: Text("提示"),
                message: Text("已存在同名布局，请选择其他名称。"),
                dismissButton: .default(Text("好的"))
            )
        }
    }
}

// MARK: - New View (from upstream)
struct NewView: View {
    @Binding var isPresented: Bool
    @ObservedObject var layouts: UserLayouts
    @State private var layoutName: String = "我的布局"
    @State private var layoutType: LayoutType = .zone
    @State private var gridRows: Int = 3
    @State private var gridColumns: Int = 3
    @State private var showAlreadyExistsAlert: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Text("新建布局")
                .font(.headline)

            TextField("输入布局名称", text: $layoutName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 250)

            Picker("布局类型", selection: $layoutType) {
                Text("区域").tag(LayoutType.zone)
                Text("网格").tag(LayoutType.grid)
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 250)

            if layoutType == .grid {
                VStack(spacing: 6) {
                    Stepper("行数: \(gridRows)", value: $gridRows, in: 1...24)
                    Stepper("列数: \(gridColumns)", value: $gridColumns, in: 1...24)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            HStack(spacing: 12) {
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("取消")
                }

                Button(action: {
                    if layoutName.trimmingCharacters(in: .whitespaces).isEmpty { return }
                    if layouts.layouts.keys.contains(layoutName) {
                        showAlreadyExistsAlert = true
                        return
                    }
                    switch layoutType {
                    case .zone:
                        layouts.createLayout(name: layoutName)
                    case .grid:
                        layouts.createGridLayout(name: layoutName, rows: gridRows, columns: gridColumns)
                    }
                    isPresented = false
                }) {
                    Image(systemName: "checkmark").foregroundColor(.green)
                    Text("创建")
                }
                .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .alert(isPresented: $showAlreadyExistsAlert) {
            Alert(
                title: Text("提示"),
                message: Text("已存在同名布局，请选择其他名称。"),
                dismissButton: .default(Text("好的"))
            )
        }
    }
}

// MARK: - Snap Key Settings Section
struct SnapKeySettingsSection: View {
    @ObservedObject var state: SettingsState
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("吸附键").font(.subheadline)
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .alert(isPresented: $showHelp) {
                Alert(
                    title: Text("吸附窗口"),
                    message: Text("将窗口吸附到区域是快速且直观的。\n\n1. 拖动窗口时按住吸附键（默认：Shift）\n2. 您的区域将出现在屏幕上\n3. 将窗口移动到目标区域上方\n4. 释放即可将窗口吸附到位\n\n提示：您也可以使用右键点击吸附（默认启用）来吸附窗口，无需按住吸附键。"),
                    dismissButton: .default(Text("确定"))
                )
            }

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
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("修饰键").font(.subheadline)
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .alert(isPresented: $showHelp) {
                Alert(
                    title: Text("摇晃吸附"),
                    message: Text("一种神奇的方式通过运动来吸附窗口。\n\n1. 点击并按住窗口的标题栏\n2. 快速摇晃鼠标或触控板\n3. 区域将自动出现\n4. 移动并释放即可吸附\n\n提示：在设置中调整摇晃灵敏度以匹配您的偏好。此功能非常适合触控板用户！"),
                    dismissButton: .default(Text("确定"))
                )
            }

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
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("窗口循环").font(.subheadline)
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .alert(isPresented: $showHelp) {
                Alert(
                    title: Text("窗口循环"),
                    message: Text("使用键盘快捷键在窗口之间快速切换。\n\n向前循环：Command+]\n向后循环：Command+[\n\n您可以在设置中自定义快捷键。"),
                    dismissButton: .default(Text("确定"))
                )
            }

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
    @State private var showQuickSnapperHelp = false
    @State private var showSnapResizeHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("快速吸附").font(.subheadline)
                Button(action: { showQuickSnapperHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .alert(isPresented: $showQuickSnapperHelp) {
                Alert(
                    title: Text("快速吸附"),
                    message: Text("快速吸附是一个轻量级窗口管理工具，让您使用键盘快捷键将窗口吸附到预定义区域。\n\n1. 使用快速吸附快捷键（默认：Control+Shift+S）切换快速吸附模式\n2. 使用方向键 ↑ / ↓ 在区域间导航，← / → 在布局间导航\n3. 按区域编号（1-9）将选定窗口吸附到该区域\n4. 按 Delete 取消吸附选定窗口\n5. 按 Enter 完成操作\n\n效率：快速吸附专为偏好键盘中心工作流程的用户设计，无需离开键盘即可快速管理窗口。您可以用它作为吸附器、布局切换器和快速窗口切换器。"),
                    dismissButton: .default(Text("确定"))
                )
            }

            ShortcutInputView(shortcut: Binding(
                get: { state.tempAppSettings.quickSnapShortcut ?? "Control+Shift+S" },
                set: {
                    state.tempAppSettings.quickSnapShortcut = $0
                    state.checkForChanges()
                }
            ))

            Divider().padding(.vertical, 2)

            HStack(spacing: 5) {
                Toggle("吸附调整大小", isOn: Binding(
                    get: { state.tempAppSettings.snapResize ?? true },
                    set: {
                        state.tempAppSettings.snapResize = $0
                        state.checkForChanges()
                    }
                ))
                .toggleStyle(.checkbox)

                Button(action: { showSnapResizeHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .alert(isPresented: $showSnapResizeHelp) {
                Alert(
                    title: Text("吸附调整大小"),
                    message: Text("使用区域边缘精确调整窗口大小。\n\n1. 将鼠标指针移动到两个区域边缘交汇处，或按住修饰键（默认：Control）片刻\n2. 吸附调整器将出现在区域之间\n3. 将窗口边缘拖动到吸附调整器附近\n4. 边缘将吸附到调整器以实现完美对齐\n\n功能：在设置中启用'悬停时显示吸附调整器'，无需按住修饰键即可立即查看。"),
                    dismissButton: .default(Text("确定"))
                )
            }

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
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("高级设置").font(.subheadline)
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .imageScale(.small)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .alert(isPresented: $showHelp) {
                Alert(
                    title: Text("高级设置"),
                    message: Text("高级窗口管理设置。\n\n优先区域中心：吸附时优先考虑区域中心位置\n区域高亮策略：选择区域高亮的显示方式\n取消吸附时恢复之前大小：窗口取消吸附时恢复原始尺寸\n按桌面布局：为不同桌面空间选择不同布局"),
                    dismissButton: .default(Text("确定"))
                )
            }

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
