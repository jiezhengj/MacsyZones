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

// T028：权限诊断面板。展示三能力状态、最近检测时间、探针明细（id/target/axError/latencyMs）、
// AppInfo（path/isTranslocated/isLoginItem）与 SystemInfo；底部提供「重新检测」「复制报告」。
// 数据全部来自 PermissionCenter.shared.snapshot，不采集窗口标题等个人数据（FR-017/FR-018）。

import SwiftUI

struct PermissionDiagnosticsView: View {
    @ObservedObject var center: PermissionCenter = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !center.hasCompletedFirstCheck {
                Text("正在进行首轮权限探测…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if let snapshot = center.snapshot {
                // 三能力状态与最近检测时间。
                ForEach(snapshot.capabilities, id: \.capability) { state in
                    capabilityRow(state)
                }

                Divider()

                // 系统信息（SystemInfo）。
                labeledRow("系统版本", snapshot.system.productVersion)
                labeledRow("系统 Build", snapshot.system.build)
                labeledRow("架构", snapshot.system.arch)

                Divider()

                // App 信息（AppInfo；path 完整显示，属用户主动查看的诊断信息）。
                labeledRow("App 版本", snapshot.app.marketingVersion)
                labeledRow("App Build", snapshot.app.build)
                labeledRow("Bundle ID", snapshot.app.bundleID)
                labeledRow("Team ID", snapshot.app.teamID)
                labeledRow("路径", snapshot.app.path)
                labeledRow("是否从临时位置迁移运行", snapshot.app.isTranslocated ? "是（AppTranslocation）" : "否")
                labeledRow("是否登录项", snapshot.app.isLoginItem ? "是" : "否")

                Divider()

                buttonsRow
            }
        }
    }

    /// 单能力状态行：名称、状态徽章、最近检测时间、触发源、探针明细、错误说明。
    @ViewBuilder
    private func capabilityRow(_ state: CapabilityState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(capabilityName(state.capability))
                    .font(.callout.weight(.semibold))
                statusBadge(state.status)
                Spacer()
                Text("最近检测 \(state.lastCheckedAt.formatted(date: .omitted, time: .standard))（\(triggerName(state.trigger))）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 探针明细：id / target / axError / latencyMs。
            ForEach(Array(state.probes.enumerated()), id: \.offset) { _, probe in
                Text("探针 \(probe.id)：目标 \(probe.target)，状态 \(statusName(probe.status))，AXError \(probe.axError.map(String.init) ?? "—")，耗时 \(probe.latencyMs) ms")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let lastError = state.lastError {
                Text("错误说明：\(lastError)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // T036（FR-014）：per-target 部分可控 → 标注「部分目标受控」，不整体报未授权。
            if state.capability == .windowControl, state.status == .granted {
                let frontmost = state.probes.first { $0.id == "frontmost" }?.status
                let finder = state.probes.first { $0.id == "finder" }?.status
                let partial = PermissionRules.partialTargets(frontmost: frontmost ?? .unknown, finder: finder ?? .unknown)
                if !partial.isEmpty {
                    Text("部分目标受控：\(partial.joined(separator: "、"))（该系统授权按应用区分）")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var buttonsRow: some View {
        HStack(spacing: 10) {
            Button("重新检测") {
                PermissionCenter.shared.recheck(trigger: "manual")
            }
            Button("复制报告") {
                center.copyDiagnosticReport()
            }
        }
        .controlSize(.small)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func capabilityName(_ capability: PermissionCapability) -> String {
        switch capability {
        case .windowControl: return "窗口控制"
        case .inputMonitoring: return "输入监听"
        case .eventPosting: return "事件发布"
        }
    }

    private func statusName(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: return "已授权"
        case .denied: return "未授权"
        case .unknown: return "未知"
        case .notRequired: return "不需要"
        }
    }

    private func triggerName(_ trigger: String) -> String {
        switch trigger {
        case "launch": return "启动"
        case "activate": return "激活"
        case "wake": return "唤醒"
        case "ax-failure": return "AX 失败"
        case "manual": return "手动"
        case "poll": return "轮询"
        default: return trigger
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        Text(statusName(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.18))
            .foregroundColor(badgeColor(status))
            .cornerRadius(4)
    }

    private func badgeColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .unknown: return .yellow
        case .notRequired: return .gray
        }
    }
}

// T029：设置窗口的诊断 section（插在 AdvancedSettingsSection 之后）。
struct PermissionDiagnosticsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("权限诊断").font(.headline)
            PermissionDiagnosticsView()
        }
    }
}
