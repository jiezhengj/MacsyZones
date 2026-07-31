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
import AVKit
import AVFoundation
import MediaPlayer

struct OnboardingStateData: Codable {
    var hasCompletedOnboarding: Bool?
}

struct CustomVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = false
        playerView.videoGravity = .resizeAspect
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

class OnboardingState: UserData, ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    
    init() {
        super.init(name: "OnboardingState", data: "{}", fileName: "OnboardingState.json")
    }
    
    override func load() {
        super.load()
        
        guard let jsonData = data.data(using: .utf8) else {
            debugLog("Error: Unable to convert onboarding state data to UTF-8")
            return
        }
        
        do {
            let state = try JSONDecoder().decode(OnboardingStateData.self, from: jsonData)
            self.hasCompletedOnboarding = state.hasCompletedOnboarding ?? false
        } catch {
            debugLog("Error parsing onboarding state JSON: \(error)")
        }
    }
    
    override func save() {
        do {
            let state = OnboardingStateData(hasCompletedOnboarding: hasCompletedOnboarding)
            
            let jsonData = try JSONEncoder().encode(state)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                data = jsonString
                super.save()
            }
        } catch {
            debugLog("Error encoding onboarding state JSON: \(error)")
        }
    }
}

let onboardingState = OnboardingState()

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let video: String
    let icon: NSImage?
}

@available(macOS 12.0, *)
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state = onboardingState
    @State private var currentPage = 0
    @State private var isAnimating = false
    let window: NSWindow?
    
    init(window: NSWindow? = nil) {
        self.window = window
    }
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "欢迎使用 MacsyZones",
            description: "**MacsyZones** 是您在 macOS 上的终极窗口管理伴侣。\n\n通过**强大的吸附区域**高效组织工作空间，使用**键盘快捷键**提升生产力，并自定义布局以匹配您的工作流程。\n\nMacsyZones 拥有独特的功能，让生活更美好。我一直在努力让它变得更好。您可以**购买 MacsyZones** 来支持我，也可以**捐赠**任意金额。\n\n访问 [macsyzones.com](https://macsyzones.com) 购买并了解如何支持我。🥳\n\n让我们开始吧！🚀",
            video: "MacsyZones Onboarding Welcome",
            icon: NSImage(named: "MenuBarIcon")
        ),
        OnboardingPage(
            title: "吸附窗口",
            description: "将窗口吸附到区域是**快速且直观**的。\n\n**1.** 拖动窗口时按住**吸附键**（默认：**Shift**）\n**2.** 您的区域将出现在屏幕上\n**3.** 将窗口移动到目标区域上方\n**4.** 释放即可将窗口吸附到位\n\n💡 **提示：**您也可以使用**右键点击吸附**（默认启用）来吸附窗口，无需按住吸附键。",
            video: "MacsyZones Onboarding Snap",
            icon: NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "添加和设计布局",
            description: "创建适合您需求的**自定义布局**。\n\n**1.** 点击菜单栏中的**铅笔图标**进入编辑模式\n**2.** 点击 **+ 按钮**添加区域\n**3.** 通过**拖动边缘**调整区域大小和位置\n**4.** 为不同的工作流程创建新布局\n\n📝 **注意：**MacsyZones 会记住您为每个屏幕和工作区组合选择的**首选布局**。您可以在屏幕上选择首选布局。",
            video: "MacsyZones Onboarding Layout Editor",
            icon: NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "摇晃吸附",
            description: "一种**神奇的方式**通过运动来吸附窗口。\n\n**1.** 点击并按住窗口的**标题栏**\n**2.** **快速**摇晃鼠标或触控板\n**3.** 区域将自动出现\n**4.** 移动并释放即可吸附\n\n⚡ **提示：**在设置中调整**摇晃灵敏度**以匹配您的偏好。此功能非常适合**触控板用户**！",
            video: "MacsyZones Onboarding Shake to Snap",
            icon: NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "吸附调整大小",
            description: "使用区域边缘**精确**调整窗口大小。\n\n**1.** 将鼠标指针移动到两个区域边缘交汇处，或按住**修饰键**（默认：**Control**）片刻\n**2.** 吸附调整器将出现在区域之间\n**3.** 将窗口边缘拖动到吸附调整器附近\n**4.** 边缘将吸附到调整器以实现**完美对齐**\n\n✨ **功能：**在设置中启用**'悬停时显示吸附调整器'**，无需按住修饰键即可立即查看。",
            video: "MacsyZones Onboarding Snap Resize",
            icon: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        ),
        OnboardingPage(
            title: "快速吸附",
            description: "快速吸附是一个**轻量级窗口管理**工具，让您使用键盘快捷键将窗口吸附到预定义区域。\n\n**1.** 使用**快速吸附快捷键**（默认：**Control+Shift+S**）切换快速吸附模式\n**2.** 使用方向键 ↑ / ↓ 在区域间导航，← / → 在布局间导航\n**3.** 按区域编号（1-9）将选定窗口吸附到该区域\n4. 按 Delete **取消吸附**选定窗口\n5. 按 Enter 完成操作\n\n🚀 **效率：**快速吸附专为偏好**键盘中心工作流程**的用户设计，无需离开键盘即可快速管理窗口。您可以用它作为吸附器、布局切换器和快速窗口切换器。",
            video: "MacsyZones Onboarding Quick Snapper",
            icon: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacsyZones 入门指南")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("第 \(currentPage + 1) 步，共 \(pages.count) 步")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    completeOnboarding()
                }) {
                    HStack(spacing: 6) {
                        Text("跳过")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .help("Skip onboarding")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .onAppear {
                window?.center()
            }
            
            HStack(spacing: 8) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button(action: {
                        guard !isAnimating else { return }
                        isAnimating = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage = index
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isAnimating = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(nsImage: page.icon ?? NSImage())
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 20, height: 20)
                                .font(.system(size: 20, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    currentPage == index
                                    ? LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : LinearGradient(
                                        colors: [Color.secondary.opacity(0.6), Color.secondary.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            Text(page.title)
                                .font(.system(size: 10, weight: currentPage == index ? .semibold : .regular))
                                .foregroundColor(currentPage == index ? .accentColor : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(currentPage == index ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    currentPage == index ? Color.accentColor.opacity(0.3) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .scaleEffect(currentPage == index ? 1.0 : 0.9)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            OnboardingPageView(page: pages[currentPage])
                .id(currentPage)
                .padding(.vertical, 10)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            
            HStack(spacing: 12) {
                if currentPage > 0 {
                    Button(action: {
                        guard !isAnimating, currentPage > 0 else { return }
                        isAnimating = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isAnimating = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text("上一步")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(currentPage == index ? 1.0 : 0.8)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                if currentPage < pages.count - 1 {
                    Button(action: {
                        guard !isAnimating, currentPage < pages.count - 1 else { return }
                        isAnimating = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isAnimating = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text("下一步")
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: {
                        completeOnboarding()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text("开始使用")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .padding(.vertical, 20)
        .frame(minWidth: 600, minHeight: 920)
    }
    
    private func completeOnboarding() {
        state.hasCompletedOnboarding = true
        state.save()
        dismiss()
    }
}

@available(macOS 12.0, *)
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?
    @State private var isPlayerReady: Bool = false
    
    private func getVideoURL() -> URL? {
        guard !page.video.isEmpty else { return nil }
        
        if let asset = NSDataAsset(name: page.video) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(page.video)
                .appendingPathExtension("mp4")
            
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                try? asset.data.write(to: tempURL)
            }
            
            return tempURL
        }
        
        return nil
    }
    
    private func setupPlayer(url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        player.isMuted = true
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        MPRemoteCommandCenter.shared().playCommand.isEnabled = false
        MPRemoteCommandCenter.shared().pauseCommand.isEnabled = false
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.isEnabled = false
        MPRemoteCommandCenter.shared().stopCommand.isEnabled = false
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
        
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        DispatchQueue.main.async {
            loopObserver = observer
        }
        
        return player
    }
    
    var body: some View {
        VStack(spacing: 24) {
            if let videoURL = getVideoURL() {
                if isPlayerReady, let player = player {
                    CustomVideoPlayer(player: player)
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 420)
                        .overlay(
                            ProgressView()
                        )
                        .padding(.horizontal, 20)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if player == nil {
                                    player = setupPlayer(url: videoURL)
                                    isPlayerReady = true

                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        player?.play()
                                    }
                                }
                            }
                        }
                }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        VStack {
                            Image(nsImage: NSImage(named: "MenuBarIcon") ?? NSImage())
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(height: 40)
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                                .symbolRenderingMode(.hierarchical)
                                .padding(.bottom, 20)
                            Text("让我们学习如何使用 MacsyZones")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                        }
                    )
                    .frame(height: 280)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text(.init(page.description))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .lineSpacing(4)
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlayerReady = false
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
                loopObserver = nil
            }
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPRemoteCommandCenter.shared().playCommand.isEnabled = false
            MPRemoteCommandCenter.shared().pauseCommand.isEnabled = false
            MPRemoteCommandCenter.shared().togglePlayPauseCommand.isEnabled = false
        }
    }
}

@available(macOS 12.0, *)
struct OnboardingWindowView: View {
    @ObservedObject var state = onboardingState
    @State private var showOnboarding = false
    
    var body: some View {
        EmptyView()
            .onAppear {
                if !state.hasCompletedOnboarding {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showOnboarding = true
                    }
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
    }
}

private var onboardingWindow: NSWindow?

@available(macOS 12.0, *)
func showOnboarding() {
    let window = NSWindow()
    window.title = "欢迎使用 MacsyZones"
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    
    let onboardingView = OnboardingView(window: window)
    let hostingController = NSHostingController(rootView: onboardingView)
    window.contentViewController = hostingController
    
    onboardingWindow = window
    
    NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
    ) { _ in
        onboardingWindow = nil
    }
    
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
}

#Preview {
    if #available(macOS 12.0, *) {
        OnboardingView(window: nil)
    }
}

