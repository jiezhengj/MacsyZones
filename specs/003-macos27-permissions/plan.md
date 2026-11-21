# Implementation Plan: macOS 27 权限模型适配

**Branch**: `003-macos27-permissions` | **Date**: 2026-11-21 | **Spec**: [spec.md](</Users/jiezhengj/Documents/Project/MacsyZones/specs/003-macos27-permissions/spec.md>)

**Input**: Feature specification from `/specs/003-macos27-permissions/spec.md`

## Summary

macOS 27.3 把「设备控制与数据访问」拆成 **System & App Protection Override** 与 **无障碍** 两个面板，禁用程序主动弹授权框（`AXIsProcessTrustedWithOptions` 底层返回 `preflight_unknown`），并按目标 app 记录 per-target 授权。本项目当前是「启动时检测一次 + 模态框挡住主界面 + 指向旧面板」，在这套模型下会让用户永久卡在「没有权限」。

本 feature 用一套独立的权限中心替换单一布尔：分能力（窗口控制 / 输入监听 / 事件投递）检测三态（已授权 / 未授权 / 未知），按真实 AX 探针而不是单一 API 判定，多时机复核并带失败宽限，引导指向 macOS 27 正确面板并支持一键打开，Release 输出结构化日志，设置里提供诊断面板与可粘贴报告，输入监听缺失时按能力降级。

## Technical Context

**Language/Version**: Swift 5（`SWIFT_VERSION = 5.0`，与现有工程一致）；AppKit + SwiftUI；无第三方依赖。

**Primary Dependencies**: ApplicationServices（`AXUIElement`、`AXIsProcessTrusted`）、CoreGraphics（`CGPreflightListenEventAccess`）、AppKit（`NSEvent` 全局监听、`NSWorkspace` 通知）、os（`Logger` 统一日志）。iOS/macOS SDK：`MacOSX27.2.sdk`（本机无 27.3 SDK，不得依赖 27.3 新增符号）。

**Storage**: 不新增持久化。权限状态为运行时内存状态；诊断报告只写剪贴板，不落盘。不读写 TCC 数据库，不写 `AppSettings.json` 新字段（如需「不再提示」类偏好，按 `AGENTS.md`/章程五用 optional 字段 + `??` 回退，本 feature 不引入）。

**Testing**: 无 XCTest target（沿用 002 的三层验证）：① `bash scripts/build-debug.sh`（正式签名 Debug 构建，BUILD SUCCEEDED + `verify-signing.sh` PASS）；② 纯值逻辑用 `scripts/check_permission_model.sh` + `scripts/tests/*.swift` 桩断言（不引入 AppKit）；③ 运行期用 `scripts/permission-smoke.sh` 启动 App、按 `log show` 断言权限日志与无崩溃。需要真实 TCC 授权与 GUI 的行为（首次授权、撤销、升级路径）走 `quickstart.md` 的手动矩阵。

**Target Platform**: macOS 27.0+（部署目标 `MACOSX27.0`），本机 27.3（Build `26C5047e`，Apple Silicon）；需同时兼容 27.0–27.2 的旧面板形态。

**Project Type**: 单 target 的 macOS 桌面 App（`MacsyZones.xcodeproj`，`PBXFileSystemSynchronizedRootGroup` 自动收录 `MacsyZones/` 下的新 Swift 文件，无需改 pbxproj）。

**Performance Goals**: 权限探针不得造成主线程 > 50ms 阻塞（探针在后台队列执行，结果回主线程）；空闲时 CPU ≤ 2%；空闲检测频率上限 1 次/30 秒。

**Constraints**: 不得申请需要苹果审批的 entitlement；不得改变 Bundle ID / Team ID / 签名方式 / 部署目标；禁止 `#available` 降级分支（用 `ProcessInfo.operatingSystemVersion` 判定 27.0–27.2 与 27.3+ 的文案差异）；新增 UI 文案中文、风格与现有设置一致；权限引导不得使用阻塞式模态框。

**Scale/Scope**: 新增 3 个源文件（`PermissionCenter.swift`、`PermissionGuidance.swift`、`PermissionDiagnosticsView.swift`），改造 `App.swift`（约 6 处接线）、`Info.swift`（引导视图）、`SettingsView.swift`（诊断 section）；新增 2 个校验脚本 + 1 个 schema。共约 700–900 行新增代码。

## Constitution Check

*GATE: 通过后方可进入 Phase 0；Phase 1 设计后复检。*

| 原则 | 结论 | 依据 |
|------|------|------|
| 一、上游代码复用优先 | 通过（无上游实现可复用） | `upstream/main` 的权限代码与 fork 完全同构（`App.swift:518-533`、`Info.swift:15-95` 仍是单次检测 + 模态框 + 旧面板文案），上游尚未适配 macOS 27；本 feature 无上游可回移，属章程允许的自研场景，需在 `research.md` R0 记录核查过程。 |
| 二、单向同步与主权仓库隔离 | 通过 | 只推 `jiezhengj/MacsyZones` 的 `custom`；不向 `upstream` 推送；不改上游远程。 |
| 三、严谨本地自测与正式签名审计 | 通过 | 构建一律走 `scripts/build-debug.sh`（正式签名 + `verify-signing.sh`）；不产生临时 Bundle ID；冒烟测试用构建产物，不 ad-hoc 签名。 |
| 四、量化版本决策与门禁约束 | 通过（实施期不触发） | 版本号/级别在 Release 前按实际变更判定；实施期不跑 `check-version.sh`、不预填版本（与 002 一致）。 |
| 五、配置持久化与平滑迁移 | 通过 | 不新增配置字段、不迁移 `AppSettings.json`/`UserLayouts.json`；新增状态不落盘。 |
| 额外：macOS 27 基线、禁 `#available` 降级分支 | 通过 | 用 `ProcessInfo.operatingSystemVersion` 判定 27.0–27.2 与 27.3+；所有 API 在 27.0 可达（`CGPreflightListenEventAccess` 自 10.15、`os.Logger` 自 11.0）。 |
| 额外：窗口惰性物化 | 通过 | 诊断视图只在设置窗口打开时构建；不新增常驻面板。 |
| 额外：主线程调度 | 通过 | 探针与 AX 读操作在 `.utility` 队列执行，结果 `Task { @MainActor }` 回写；状态变更只从主线程发出。 |
| 额外：规则文档单一来源 | 通过 | 规则改动只涉及 `AGENTS.md`（若需要新增权限排障说明），不创建 `CLAUDE.md`。 |

无章程违规项，Complexity Tracking 只记录现有工程约束（无 XCTest target）。

## Project Structure

### Documentation (this feature)

```text
specs/003-macos27-permissions/
├── plan.md               # 本文件
├── research.md           # Phase 0：R0–R12 决策
├── data-model.md         # Phase 1：权限状态模型与状态机
├── contracts/
│   ├── permission-report.schema.json   # 诊断报告 JSON 结构（复制/粘贴契约）
│   └── guidance-targets.md             # 各 27.x 形态的面板路径与深链
├── quickstart.md         # Phase 1：构建、脚本、手动验证矩阵
├── checklists/
│   └── requirements.md   # 规格质量检查表
└── tasks.md              # Phase 2（/speckit-tasks 生成，非本命令）
```

### Source Code (repository root)

```text
MacsyZones/
├── PermissionCenter.swift          # 新增：能力/状态模型、探针、复核调度、宽限重试、os.Logger 输出
├── PermissionGuidance.swift        # 新增：按 27.x 形态选择面板标题/深链/文案，打开系统设置
├── PermissionDiagnosticsView.swift # 新增：设置内诊断 section + 报告生成与复制
├── App.swift                       # 改造：接入 PermissionCenter；替换启动时单次检测；onboarding 条件；-25211 上报；唤醒/激活复核
├── Info.swift                      # 改造：权限引导视图（非模态、正确面板、一键打开、旧截图移除）
├── SettingsView.swift              # 改造：插入「权限」诊断 section
└── Utils.swift                     # 改造：debugLog 与 os.Logger 并存（Release 也能出诊断日志）

scripts/
├── check_permission_model.sh       # 新增：值类型/状态机静态断言（grep + swift 桩）
└── permission-smoke.sh             # 新增：启动构建产物、断言权限日志、确认无崩溃

scripts/tests/
├── permission-stubs.swift          # 新增：PermissionStatus/PermissionProbe 纯值逻辑桩
└── permission-assertions.swift     # 新增：断言脚本（被 check_permission_model.sh 调用）
```

**Structure Decision**: 沿用现有单 target 布局（`MacsyZones/` 为同步根组，新增文件自动入编译）；权限逻辑集中到 `PermissionCenter.swift`，避免继续散落在 `App.swift`；引导文案与深链单独成文件，便于 27.0–27.2 与 27.3+ 两套形态维护与测试；诊断 UI 与设置页复用现有 SwiftUI 组件风格。

## Complexity Tracking

| 项目 | 说明 | 取舍 |
|------|------|------|
| 无 XCTest target | 工程没有测试 target，新增会改 pbxproj 与签名流程 | 沿用 002 的三层验证（构建 + 桩脚本 + 运行期日志断言），不新增 target |
| 无 27.3 SDK | 本机 Xcode 27.2 只有 `MacOSX27.2.sdk`，无法编译 27.3 新符号 | 只用 27.0 可达 API + 运行时版本判定；面板差异靠 `ProcessInfo` 与深链，不依赖新常量 |
| 双形态面板文案 | 27.0–27.2 旧面板 vs 27.3+ 拆分面板 | 用 `operatingSystemVersion` 分支文案（非 `#available`），两套文案集中在 `PermissionGuidance.swift` |
