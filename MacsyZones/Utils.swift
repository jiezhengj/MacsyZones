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
import SwiftUI
import AppKit
import os

// 权限子系统专用日志（R6）：Release 构建也可见（Logger 不受 #if DEBUG 限制），
// 固定字段 capability / status / probe / target / error / latencyMs / trigger，
// 供 permission-smoke 冒烟脚本与诊断复核按子系统过滤。
private let permissionLog = Logger(subsystem: "MeowingCat.MacsyZones", category: "permissions")

/// 记录一条权限探针/汇总日志。target 含 bundle id 与 app 路径，按 R6 用 .private；
/// 其余字段为非敏感枚举值与数字，用 .public 便于 log stream / log show 直接阅读。
func permissionLogRecord(
    capability: String,
    id: String,
    target: String,
    status: String,
    axError: Int?,
    latencyMs: Int,
    trigger: String,
    error: String? = nil
) {
    var axErrorText = "nil"
    if let axError { axErrorText = String(axError) }
    var errorText = "nil"
    if let error, !error.isEmpty { errorText = error }
    permissionLog.log(
        "capability=\(capability, privacy: .public) probe=\(id, privacy: .public) target=\(target, privacy: .private) status=\(status, privacy: .public) axError=\(axErrorText, privacy: .public) latencyMs=\(latencyMs, privacy: .public) trigger=\(trigger, privacy: .public) error=\(errorText, privacy: .public)"
    )
}

func debugLog(_ message: String, file: String = #file, line: Int = #line) {
    #if DEBUG
        print("[\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(message)")
    #endif
}

// Returns a human-readable screen ratio string (e.g. "1/2", "1/3") for a given percentage value.
// Uses a 0.5% tolerance to account for floating-point rounding.
func screenRatioString(for percentage: CGFloat) -> String? {
    // Common screen ratios to check against
    let ratios: [(numerator: Int, denominator: Int)] = [
        (1, 2), (1, 3), (2, 3), (1, 4), (3, 4),
        (1, 5), (2, 5), (3, 5), (4, 5),
        (1, 6), (5, 6),
        (1, 8), (3, 8), (5, 8), (7, 8)
    ]

    let tolerance: CGFloat = 0.005

    for ratio in ratios {
        let expected = CGFloat(ratio.numerator) / CGFloat(ratio.denominator)
        if abs(percentage - expected) < tolerance {
            return "\(ratio.numerator)/\(ratio.denominator)"
        }
    }

    return nil
}

public extension View {
    func modifier<ModifiedContent: View>(@ViewBuilder content: (_ content: Self) -> ModifiedContent) -> ModifiedContent {
        content(self)
    }
}
