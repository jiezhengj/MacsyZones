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
import AppKit

class AppUpdater: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdatable: Bool?
    @Published var isDownloading = false
    @Published var isDownloaded = false
    @Published var downloadFailed = false

    @Published var latestVersion: String?

    let updater = GitHubUpdater()
    var downloadedDmgPath: URL?

    func autoCheckAndDownload() {
        guard !isDownloading, !isDownloaded else { return }
        checkAndDownload()
    }

    func userTriggerUpdate() {
        if isDownloaded {
            installUpdate()
        } else if !isDownloading {
            checkAndDownload()
        }
    }

    private func checkAndDownload() {
        Task { @MainActor in
            self.isChecking = true
            self.downloadFailed = false
        }

        updater.checkForUpdates { version in
            Task { @MainActor in
                guard let version = version else {
                    self.isChecking = false
                    self.isUpdatable = false
                    return
                }
                self.latestVersion = version
                self.isUpdatable = true
                self.isChecking = false
                self.isDownloading = true
            }
        } onDownloaded: { success, dmgPath in
            Task { @MainActor in
                self.isDownloading = false
                if success, let dmgPath = dmgPath {
                    self.isDownloaded = true
                    self.downloadedDmgPath = dmgPath
                    self.showUpdateReadyAlert()
                } else {
                    self.downloadFailed = true
                }
            }
        }
    }

    func showUpdateReadyAlert() {
        let alert = NSAlert()
        alert.window.level = .floating
        alert.alertStyle = .informational
        alert.messageText = "MacsyZones"
        alert.informativeText = "更新已下载完成。点击确定重启并安装更新。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        alert.window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            installUpdate()
        }
    }

    func installUpdate() {
        guard let dmgPath = downloadedDmgPath else { return }

        updater.installDmg(from: dmgPath) { success in
            DispatchQueue.main.async {
                if success {
                    restartApp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApp.terminate(nil)
                    }
                }
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
        debugLog("[Updater] 检查更新: \(urlString)")

        guard let url = URL(string: urlString) else {
            debugLog("[Updater] 无效的 URL")
            onChecked(nil)
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                debugLog("[Updater] API 请求失败: \(error.localizedDescription)")
                onChecked(nil)
                return
            }

            guard let data = data else {
                debugLog("[Updater] 没有收到数据")
                onChecked(nil)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                debugLog("[Updater] API 响应状态码: \(httpResponse.statusCode)")
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let assets = json["assets"] as? [[String: Any]],
                   let downloadUrl = assets.first?["browser_download_url"] as? String
                {
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                    let isGreater = isVersionGreater(version, than: appVersion)

                    debugLog("[Updater] 最新版本: \(version), 当前版本: \(appVersion), 需要更新: \(isGreater)")
                    debugLog("[Updater] 下载地址: \(downloadUrl)")

                    onChecked(isGreater ? (version: version, url: URL(string: downloadUrl)!): nil)
                } else {
                    debugLog("[Updater] 解析 JSON 失败")
                    onChecked(nil)
                }
            } catch {
                debugLog("[Updater] JSON 解析错误: \(error.localizedDescription)")
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

    func checkForUpdates(onChecked: ((String?) -> Void)? = nil, onDownloaded: ((Bool, URL?) -> Void)? = nil) {
        githubAPI.checkLatestRelease { [self] latestRelease in
            guard let latestRelease else {
                onChecked?(nil)
                return
            }

            onChecked?(latestRelease.version)

            self.downloadDmg(from: latestRelease.url, version: latestRelease.version) { success, dmgPath in
                onDownloaded?(success, dmgPath)
            }
        }
    }

    func downloadDmg(from url: URL, version: String, onCompleted: ((Bool, URL?) -> Void)? = nil) {
        debugLog("[Updater] 开始下载: \(url)")

        downloadFile(from: url) { tmpPath in
            if let tmpPath = tmpPath {
                debugLog("[Updater] 下载完成: \(tmpPath)")
            } else {
                debugLog("[Updater] 下载失败")
            }

            guard let tmpPath = tmpPath else {
                onCompleted?(false, nil)
                return
            }

            onCompleted?(true, tmpPath)
        }
    }

    func installDmg(from dmgURL: URL, onInstalled: @escaping (Bool) -> Void) {
        debugLog("[Updater] 开始安装 DMG: \(dmgURL)")

        let fileManager = FileManager.default
        let destinationFolder = getApplicationsPath()
        let destinationApp = destinationFolder.appendingPathComponent("MacsyZones.app")
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mountPoint = tempDirectory.appendingPathComponent("mount")

        debugLog("[Updater] 目标路径: \(destinationApp)")
        debugLog("[Updater] 临时目录: \(tempDirectory)")
        debugLog("[Updater] 挂载点: \(mountPoint)")

        do {
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            debugLog("[Updater] 创建临时目录成功")

            // 挂载 dmg
            debugLog("[Updater] 挂载 DMG...")
            let hdiutilAttach = Process()
            hdiutilAttach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            hdiutilAttach.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
            try hdiutilAttach.run()
            hdiutilAttach.waitUntilExit()

            debugLog("[Updater] hdiutil attach 退出状态: \(hdiutilAttach.terminationStatus)")

            guard hdiutilAttach.terminationStatus == 0 else {
                debugLog("[Updater] 挂载 DMG 失败")
                try? fileManager.removeItem(at: tempDirectory)
                onInstalled(false)
                return
            }

            // 查找 app
            let extractedAppURL = mountPoint.appendingPathComponent("MacsyZones.app")
            debugLog("[Updater] 查找 app: \(extractedAppURL)")

            guard fileManager.fileExists(atPath: extractedAppURL.path) else {
                debugLog("[Updater] DMG 中没有找到 app")
                // 列出挂载点内容
                if let contents = try? fileManager.contentsOfDirectory(atPath: mountPoint.path) {
                    debugLog("[Updater] 挂载点内容: \(contents)")
                }
                // 卸载 dmg
                let hdiutilDetach = Process()
                hdiutilDetach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                hdiutilDetach.arguments = ["detach", mountPoint.path, "-force"]
                try? hdiutilDetach.run()
                hdiutilDetach.waitUntilExit()
                try? fileManager.removeItem(at: tempDirectory)
                onInstalled(false)
                return
            }

            debugLog("[Updater] 找到 app")

            // 读取版本号
            let extractedInfoPlist = extractedAppURL.appendingPathComponent("Contents/Info.plist")
            guard let extractedPlistData = try? Data(contentsOf: extractedInfoPlist),
                  let extractedPlist = try? PropertyListSerialization.propertyList(from: extractedPlistData, options: [], format: nil) as? [String: Any],
                  let targetVersion = extractedPlist["CFBundleShortVersionString"] as? String else {
                debugLog("[Updater] 无法读取目标版本号")
                let hdiutilDetach = Process()
                hdiutilDetach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                hdiutilDetach.arguments = ["detach", mountPoint.path, "-force"]
                try? hdiutilDetach.run()
                hdiutilDetach.waitUntilExit()
                try? fileManager.removeItem(at: tempDirectory)
                onInstalled(false)
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            debugLog("[Updater] 当前版本: \(currentVersion), 目标版本: \(targetVersion)")

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

            onInstalled(true)
        } catch {
            debugLog("Update error: \(error.localizedDescription)")
            // 卸载 dmg
            let hdiutilDetach = Process()
            hdiutilDetach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            hdiutilDetach.arguments = ["detach", mountPoint.path, "-force"]
            try? hdiutilDetach.run()
            hdiutilDetach.waitUntilExit()
            try? fileManager.removeItem(at: tempDirectory)
            onInstalled(false)
        }
    }
}

func downloadFile(from url: URL, onComplete: @escaping (URL?) -> Void) {
    debugLog("[Updater] 开始下载文件: \(url)")

    let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
        if let error = error {
            debugLog("[Updater] 下载错误: \(error.localizedDescription)")
            onComplete(nil)
            return
        }

        if let httpResponse = response as? HTTPURLResponse {
            debugLog("[Updater] 下载响应状态码: \(httpResponse.statusCode)")
        }

        guard let tempURL = tempURL else {
            debugLog("[Updater] 下载失败: 没有临时文件")
            onComplete(nil)
            return
        }

        debugLog("[Updater] 下载成功，临时文件: \(tempURL)")
        onComplete(tempURL)
    }
    task.resume()
}
