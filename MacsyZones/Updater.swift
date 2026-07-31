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

class AppUpdater: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdatable: Bool?
    @Published var isDownloading = false
    
    @Published var latestVersion: String?
    
    let updater = GitHubUpdater()
    
    func checkForUpdates(download: Bool = false) {
        Task { @MainActor in
            self.isChecking = true
        }
        
        updater.checkForUpdates { version in
            guard let version = version else {
                Task { @MainActor in
                    self.isChecking = false
                    self.isDownloading = false
                    self.isUpdatable = false
                }
                
                return
            }
            
            Task { @MainActor in
                self.latestVersion = version
                self.isChecking = false
                self.isUpdatable = true
                self.isDownloading = true
            }
        } onDownloaded: { success in
            Task { @MainActor in
                self.isChecking = false
                self.isDownloading = false
            }
        }
    }
}

func isVersionGreater(_ version: String, than otherVersion: String) -> Bool {
    let cleanVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
    let cleanOtherVersion = otherVersion.hasPrefix("v") ? String(otherVersion.dropFirst()) : otherVersion
    
    let versionComponents = cleanVersion.split(separator: ".")
    let otherVersionComponents = cleanOtherVersion.split(separator: ".")
    
    let minComponents = min(versionComponents.count, otherVersionComponents.count)
    
    for i in 0..<minComponents {
        guard let vNum = Int(versionComponents[i]), let otherNum = Int(otherVersionComponents[i]) else {
            if versionComponents[i] > otherVersionComponents[i] {
                return true
            } else if versionComponents[i] < otherVersionComponents[i] {
                return false
            }
            continue
        }
        
        if vNum > otherNum {
            return true
        } else if vNum < otherNum {
            return false
        }
    }
    
    return versionComponents.count > otherVersionComponents.count
}

func getApplicationsPath() -> URL {
    return Bundle.main.bundleURL.deletingLastPathComponent()
}

class GitHubAPI {
    let session = URLSession.shared

    func checkLatestRelease(onChecked: @escaping ((version: String, url: URL)?) -> Void) {
        let urlString = "https://api.github.com/repos/jiezhengj/MacsyZones/releases/latest"
        guard let url = URL(string: urlString) else {
            onChecked(nil)
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                onChecked(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let assets = json["assets"] as? [[String: Any]],
                   let downloadUrl = assets.first?["browser_download_url"] as? String
                {
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
                    let isGreater = isVersionGreater(version, than: appVersion)
                    
                    onChecked(isGreater ? (version: version, url: URL(string: downloadUrl)!): nil)
                } else {
                    onChecked(nil)
                }
            } catch {
                debugLog("Error parsing JSON:")
                dump(error)
                onChecked(nil)
            }
        }
        
        task.resume()
    }
}

class GitHubUpdater {
    let githubAPI = GitHubAPI()
    let fileManager = FileManager.default
    let applicationsDirectory = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true).first!
    let appName = "MacsyZones"
    
    func checkForUpdates(onChecked: ((String?) -> Void)? = nil, onDownloaded: ((Bool) -> Void)? = nil) {
        githubAPI.checkLatestRelease { [self] latestRelease in
            guard let latestRelease else {
                onChecked?(nil)
                return
            }

            onChecked?(latestRelease.version)

            self.downloadDmg(from: latestRelease.url, version: latestRelease.version) { success in
                onDownloaded?(success)
            }
        }
    }

    private func downloadDmg(from url: URL, version: String, onCompleted: ((Bool) -> Void)? = nil) {
        let destination = URL(fileURLWithPath: "\(NSTemporaryDirectory())\(appName).dmg")

        downloadFile(from: url, to: destination) { [self] tmpPath in
            guard let tmpPath = tmpPath else {
                debugLog("Error downloading update!")
                onCompleted?(false)
                return
            }

            onCompleted?(true)

            self.installDmg(from: tmpPath)
        }
    }

    private func installDmg(from dmgURL: URL) {
        let fileManager = FileManager.default
        let destinationFolder = getApplicationsPath()
        let destinationApp = destinationFolder.appendingPathComponent("MacsyZones.app")
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mountPoint = tempDirectory.appendingPathComponent("mount")

        do {
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            // 挂载 dmg
            let hdiutilAttach = Process()
            hdiutilAttach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            hdiutilAttach.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
            try hdiutilAttach.run()
            hdiutilAttach.waitUntilExit()

            guard hdiutilAttach.terminationStatus == 0 else {
                debugLog("Error: Failed to mount DMG.")
                try? fileManager.removeItem(at: tempDirectory)
                return
            }

            // 查找 app
            let extractedAppURL = mountPoint.appendingPathComponent("MacsyZones.app")
            guard fileManager.fileExists(atPath: extractedAppURL.path) else {
                debugLog("Error: App not found in DMG.")
                // 卸载 dmg
                let hdiutilDetach = Process()
                hdiutilDetach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                hdiutilDetach.arguments = ["detach", mountPoint.path, "-force"]
                try? hdiutilDetach.run()
                hdiutilDetach.waitUntilExit()
                try? fileManager.removeItem(at: tempDirectory)
                return
            }

            // 读取版本号
            let extractedInfoPlist = extractedAppURL.appendingPathComponent("Contents/Info.plist")
            guard let extractedPlistData = try? Data(contentsOf: extractedInfoPlist),
                  let extractedPlist = try? PropertyListSerialization.propertyList(from: extractedPlistData, options: [], format: nil) as? [String: Any],
                  let targetVersion = extractedPlist["CFBundleShortVersionString"] as? String else {
                debugLog("Error: Could not read target version from extracted app.")
                let hdiutilDetach = Process()
                hdiutilDetach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                hdiutilDetach.arguments = ["detach", mountPoint.path, "-force"]
                try? hdiutilDetach.run()
                hdiutilDetach.waitUntilExit()
                try? fileManager.removeItem(at: tempDirectory)
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            updateState.setUpdateAttempt(currentVersion: currentVersion, targetVersion: targetVersion)

            let scriptURL = tempDirectory.appendingPathComponent("update.sh")
            let script = """
            #!/bin/bash
            sleep 2

            # 移除隔离属性
            xattr -r -d com.apple.quarantine "\(extractedAppURL.path)" 2>/dev/null || true

            # 删除旧 app
            rm -rf "\(destinationApp.path)"

            # 复制新 app
            ditto "\(extractedAppURL.path)" "\(destinationApp.path)"

            # 再次移除隔离属性
            xattr -r -d com.apple.quarantine "\(destinationApp.path)" 2>/dev/null || true

            # 卸载 dmg
            hdiutil detach "\(mountPoint.path)" -force 2>/dev/null || true

            # 清理临时文件
            rm -rf "\(tempDirectory.path)"
            rm -f "\(dmgURL.path)"

            # 等待文件系统稳定
            sleep 1

            open "\(destinationApp.path)"
            exit 0
            """

            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let updateProcess = Process()
            updateProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            updateProcess.arguments = ["-c", "nohup \"\(scriptURL.path)\" > /dev/null 2>&1 &"]
            try updateProcess.run()

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.window.level = .floating
                alert.alertStyle = .informational
                alert.messageText = "MacsyZones"
                alert.informativeText = "更新即将开始。应用将自动重启。"
                alert.addButton(withTitle: "好的")

                alert.window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)

                alert.runModal()

                restartApp()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            debugLog("Update error: \(error.localizedDescription)")
            // 卸载 dmg
            let hdiutilDetach = Process()
            hdiutilDetach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            hdiutilDetach.arguments = ["detach", mountPoint.path, "-force"]
            try? hdiutilDetach.run()
            hdiutilDetach.waitUntilExit()
            try? fileManager.removeItem(at: tempDirectory)
        }
    }
}

func downloadFile(from url: URL, to destination: URL, onComplete: @escaping (URL?) -> Void) {
    let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
        guard let tempURL = tempURL, error == nil else {
            onComplete(nil)
            return
        }
        
        onComplete(tempURL)
    }
    task.resume()
}
