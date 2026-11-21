# 契约：权限引导目标（面板与深链）

**Feature**: `003-macos27-permissions` | **适用**：`PermissionGuidance.swift` 的取值表，以及引导文案必须满足的行为。

## 深链契约

| 键 | URL | 说明 |
|---|---|---|
| `systemProtectionOverride` | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` | macOS 27.3+「System & App Protection Override」面板 |
| `accessibilityApps` | `x-apple.systempreferences:com.apple.preference.security?Privacy_AccessibilityApps` | macOS 27.3+「无障碍（Accessibility）」面板 |
| `legacyAccessibility` | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` | macOS 27.0–27.2「Device Control and Data Access」面板 |
| `privacyRoot` | `x-apple.systempreferences:com.apple.preference.security` | 兜底：隐私与安全性首页 |

约束：

1. 锚点名 `Privacy_Accessibility` / `Privacy_AccessibilityApps` 来自本机 `SecurityPrivacyExtension.appex` 的 `revealElementKeyName` 资源；若未来版本改名，`NSWorkspace.open` 不会报错但会落到面板首页——因此**打开后必须允许用户点「重新检测」**，不假设跳转成功就代表授权完成。
2. `NSWorkspace.shared.open(url)` 返回 `false`（URL 不被识别）时，退化为 `privacyRoot` 并同时展示文字路径；两次都失败则只展示文字路径，不阻塞引导。
3. 深链只能打开面板，不能替用户勾选；不得尝试写入 TCC 数据库（macOS 27 已禁止直接访问本地 TCC db）。

## 文案契约（面向用户的中文）

| 场景 | 必须出现 | 禁止出现 |
|---|---|---|
| 27.3+ 引导 | 「System & App Protection Override」（可附英文原名）、「无障碍」作为备选、「打开系统设置」按钮、「重新检测」按钮 | 「辅助功能」（旧称，27.3 面板不存在该名）、「重启 MacsyZones 后继续」、任何指向旧截图的步骤 |
| 27.0–27.2 引导 | 「Device Control and Data Access」、「打开系统设置」 | 27.3 专有面板名 |
| 未在列表中找到本 app | 说明「本 app 可能不在无障碍列表中，属正常」+ 首选面板路径 | 让用户反复在不同面板里找 |
| 已授权但探针仍失败 | 说明可能是「按目标应用分别授权」或「系统短时误判」，给出「重新检测」 | 「权限已开启，功能应可用」这类与事实矛盾的断言 |

## 行为契约

| 状态 | 打开面板按钮 | 重新检测按钮 | 自动行为 |
|---|---|---|---|
| `denied` | 可用（首选 pane） | 可用 | 每 5s 复核，最多 24 次 |
| `unknown` | 可用 | 可用 | 同上，并在诊断面板显示 `lastError` |
| `granted` | 可用（供用户复核） | 可用 | 每 30s 复核 |
| `granted` + 可疑（宽限中） | 可用 | 可用 | 仅在「距进程启动 < 60s」时出现；60s 后自动复检，期间不弹任何提示 |
| `granted` + 部分目标受控 | 可用（供用户补授权） | 可用 | 正常运行；诊断 `notes` 标注「部分目标受控」，不提示未授权 |

## 演示/冒烟契约

`scripts/permission-smoke.sh` 依赖 `/Applications/MacsyZones.app`（由 `scripts/build-permission-artifact.sh` 产出，见 `research.md` R14）与以下可观察输出（`log show --predicate 'subsystem == "MeowingCat.MacsyZones" AND category == "permissions"'`）：

- 进程启动 10 秒内至少一条 `capability=windowControl` 的记录，包含 `status=` 与 `trigger=launch`。
- 每条记录包含 `latencyMs=`，且窗口控制探针 `latencyMs < 1000`。
- 记录字段与 `contracts/permission-report.schema.json` 的 `capabilities[].probes[]` 命名一致：`id`、`target`、`status`、`latencyMs`（`axError` 可空）。
- 崩溃或 `fatal error` 出现即判失败。
