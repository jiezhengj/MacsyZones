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

struct OnboardingStateData: Codable {
    var hasCompletedOnboarding: Bool?
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
    let icon: NSImage?
}

@available(macOS 12.0, *)
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state = onboardingState
    let window: NSWindow?

    init(window: NSWindow? = nil) {
        self.window = window
    }

    private let aboutPage = OnboardingPage(
        title: "关于",
        description: "**MacsyZones** 是您在 macOS 上的终极窗口管理伴侣。\n\n通过**强大的吸附区域**高效组织工作空间，使用**键盘快捷键**提升生产力，并自定义布局以匹配您的工作流程。\n\n📌 **关于本版本**\n这是 [MacsyZones](https://github.com/rohanrhu/MacsyZones) 的中文定制 fork 版本，**仅供个人学习使用，不对外分发**。\n\n感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！🥳",
        icon: NSImage(named: "MenuBarIcon")
    )

    var body: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        VStack(spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MacsyZones")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("版本 \(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .onAppear {
                window?.center()
            }

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                Text(.init(aboutPage.description))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 20)

            Divider()

            // Bottom button
            HStack {
                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Text("确定")
                        .fontWeight(.semibold)
                        .frame(width: 100)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

@available(macOS 12.0, *)
struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
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
                        Image(nsImage: page.icon ?? NSImage())
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(height: 60)
                            .foregroundStyle(Color.accentColor.opacity(0.6))
                            .symbolRenderingMode(.hierarchical)
                            .padding(.bottom, 16)
                        Text(page.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor.opacity(0.6))
                    }
                )
                .frame(height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 20)

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

