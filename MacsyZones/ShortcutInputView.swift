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
                    Text(isListening ? "正在监听快捷键..." : shortcut.isEmpty ? "点击设置快捷键" : presentingShortcut(shortcut))
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
