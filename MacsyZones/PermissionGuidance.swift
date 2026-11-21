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

// 权限引导（R3 / contracts/guidance-targets.md）：
// - 面板与深链取值表；版本判定用 ProcessInfo 的 minorVersion（constitution 禁可用性分支）。
// - macOS 27.3+ 主面板为「System & App Protection Override」，备选「无障碍」；
//   27.0–27.2 面板名为「Device Control and Data Access」。
// - 深链只能打开面板，不能替用户勾选；绝不做任何 TCC 写操作。
// 约定：纯判定函数（primaryPane / fallbackPane / deepLinkString / panelTitle）
// 会被 scripts/check_permission_model.sh 用 awk 抽取后执行（R15），
// 内部大括号保持单行/紧凑风格，函数体只依赖本文件类型与 Foundation。

import Foundation
import AppKit

/// 引导目标面板（guidance-targets.md 深链契约的四个键）。
enum PermissionGuidancePane: String, Sendable {
    /// macOS 27.3+ 主面板「System & App Protection Override」。
    case systemProtectionOverride
    /// macOS 27.3+ 备选面板「无障碍（Accessibility）」。
    case accessibilityApps
    /// macOS 27.0–27.2 面板「Device Control and Data Access」。
    case legacyAccessibility
    /// 兜底：隐私与安全性首页。
    case privacyRoot
}

/// 一次引导的目标描述（data-model.md「GuidanceTarget」）。
struct GuidanceTarget: Sendable {
    let pane: PermissionGuidancePane
    /// x-apple.systempreferences:… 深链 URL。
    let url: URL
    /// 面板完整路径（用于文字提示与复制报告）。
    let panelTitle: String
    /// 文字步骤（面向用户的中文）。
    let steps: [String]
}

/// 引导面板映射与打开逻辑（R3）。版本判定用 ProcessInfo 的 minorVersion（constitution 禁可用性分支）。
enum PermissionGuidance {
    /// macOS 27.3 起使用新面板体系；minorVersion >= 3 判定（constitution 禁可用性分支）。
    static func isOverrideEra(minor: Int) -> Bool {
        minor >= 3
    }

    /// 首选面板：27.3+ → systemProtectionOverride；27.0–27.2 → legacyAccessibility。
    static func primaryPane(forMinor minor: Int) -> PermissionGuidancePane {
        minor >= 3 ? .systemProtectionOverride : .legacyAccessibility
    }

    /// 备选面板：27.3+ → accessibilityApps；27.0–27.2 → privacyRoot（首页兜底）。
    static func fallbackPane(forMinor minor: Int) -> PermissionGuidancePane {
        minor >= 3 ? .accessibilityApps : .privacyRoot
    }

    /// 深链契约（guidance-targets.md）：锚点名来自本机 SecurityPrivacyExtension.appex
    /// 的 revealElementKeyName 资源；若未来改名，open 会落到面板首页而不报错。
    static func deepLinkString(for pane: PermissionGuidancePane) -> String {
        switch pane {
        case .systemProtectionOverride, .legacyAccessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .accessibilityApps:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AccessibilityApps"
        case .privacyRoot:
            return "x-apple.systempreferences:com.apple.preference.security"
        }
    }

    /// 面板显示路径（用于文字提示，不含按钮）。
    static func panelTitle(for pane: PermissionGuidancePane) -> String {
        switch pane {
        case .systemProtectionOverride:
            return "系统设置 → 隐私与安全性 → System & App Protection Override"
        case .accessibilityApps:
            return "系统设置 → 隐私与安全性 → 无障碍"
        case .legacyAccessibility:
            return "系统设置 → 隐私与安全性 → Device Control and Data Access"
        case .privacyRoot:
            return "系统设置 → 隐私与安全性"
        }
    }

    /// 组装一次引导的目标（含文字步骤）。
    static func makeTarget(forMinor minor: Int, pane: PermissionGuidancePane) -> GuidanceTarget {
        let url = URL(string: deepLinkString(for: pane))!
        return GuidanceTarget(
            pane: pane,
            url: url,
            panelTitle: panelTitle(for: pane),
            steps: steps(for: pane)
        )
    }

    /// 引导步骤（文案契约：27.3+ 先主面板再看「无障碍」；未在列表属正常）。
    static func steps(for pane: PermissionGuidancePane) -> [String] {
        switch pane {
        case .systemProtectionOverride:
            return [
                "打开「系统设置」→「隐私与安全性」。",
                "进入「System & App Protection Override」面板。",
                "允许 MacsyZones 控制其他 app 的窗口。",
                "若本 app 可能不在无障碍列表中，属正常；如仍受限，可到「无障碍」面板查看。"
            ]
        case .accessibilityApps:
            return [
                "打开「系统设置」→「隐私与安全性」→「无障碍」。",
                "本 app 可能不在无障碍列表中，属正常。",
                "若列表中出现 MacsyZones，请允许它控制你的电脑。"
            ]
        case .legacyAccessibility:
            return [
                "打开「系统设置」→「隐私与安全性」。",
                "进入「Device Control and Data Access」面板。",
                "允许 MacsyZones 控制其他 app 的窗口。"
            ]
        case .privacyRoot:
            return [
                "打开「系统设置」→「隐私与安全性」。",
                "在首页找到相关权限条目后按提示允许 MacsyZones。"
            ]
        }
    }

    /// 「未在列表中找到本 app」的提示语（文案契约）。
    static let notInListNotice = "本 app 可能不在无障碍列表中，属正常。"

    /// 「已授权但探针仍失败」的提示语（文案契约：不与事实矛盾的断言）。
    static let probeStillFailingNotice = "该系统可能按目标应用分别授权，或系统短时误判；请点「重新检测」复核。"

    // MARK: 打开面板（含兜底）

    /// 打开结果。
    enum OpenOutcome: Equatable, Sendable {
        /// 深链直达目标面板。
        case opened(PermissionGuidancePane)
        /// 深链未被识别，已退化为隐私与安全性首页。
        case openedFallback
        /// 两次打开都失败：调用方只展示文字路径，不阻塞引导。
        case failed
    }

    /// 打开链路的纯判定（R15 可抽取执行）：深链成功 → opened(pane)；深链失败但
    /// 首页成功 → openedFallback；两次都失败 → failed（调用方只展示文字路径）。
    static func openOutcome(pane: PermissionGuidancePane, deepLinkOpened: Bool, rootOpened: Bool) -> OpenOutcome {
        if deepLinkOpened { return .opened(pane) }
        if rootOpened { return .openedFallback }
        return .failed
    }

    /// 打开引导面板：先试深链；返回 false 时退化为 privacyRoot（契约第 2 条）；
    /// 两次都失败返回 .failed，由调用方展示文字路径。
    @discardableResult
    static func open(_ pane: PermissionGuidancePane) -> OpenOutcome {
        let deepLink = URL(string: deepLinkString(for: pane))!
        let deepLinkOpened = NSWorkspace.shared.open(deepLink)
        let rootOpened = deepLinkOpened ? false : NSWorkspace.shared.open(URL(string: deepLinkString(for: .privacyRoot))!)
        return openOutcome(pane: pane, deepLinkOpened: deepLinkOpened, rootOpened: rootOpened)
    }
}
