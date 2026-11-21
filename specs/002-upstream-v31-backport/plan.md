**Branch**: `002-upstream-v31-backport` | **Date**: 2026-11-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-upstream-v31-backport/spec.md`

# 实施概要

把上游 `rohanrhu/MacsyZones` 在 `v3.0.4..v3.1.1` 之间仍然有效、且 fork 尚未具备的改进，按「上游代码复用优先」原则手工回移进 `custom` 分支。全部改动分成五个可独立验收的切片：

1. **P1 快速吸附只切区域布局**（上游 `b83b923` + `08a028a`）——两个循环闭包加区域过滤/空集守卫/索引回退，并新增 `quickSnapperZoneLayoutsOnly` 设置项，落到 fork 自研的 `SettingsView.swift` + `SettingsState` 暂存式架构。
2. **P1 吸附调整器光标方向**（上游 `b77e366` 第二部分）——`SnapResizerMode` 已存在于 fork，只需把方向透传到 SwiftUI 视图并按方向选择光标。
3. **P2 惰性物化收口**（上游 `ada5b51` 残余）——鼠标移动路径改用 `materializedLayoutWindow`、警告面板懒建、关闭回调弱引用。
4. **P2 窗口观察对账**（上游 `7719891`）——CG ↔ AX 差集对账 + 标题狩猎、启动后定时重扫、标准窗口三态判定；与 fork 已有的双移动通知/CFEqual 替换/节流/鼠标兜底并存。
5. **P3 构建清单与代码健康**——`LastUpgradeCheck`/`LastUpgradeVersion` 2700、五处 `onChange` 双参数、移植上游惰性物化回归脚本。

不采用上游已回滚或与 fork 结构无关的内容（见 FR-021）：`e41e327`/`43d28e2`、`f660129`、PR #105、`d93890a` 中的工程设置项、`9b0f2dd` 的纯风格去重。

# 技术上下文

**语言/版本**：Swift（`SWIFT_VERSION = 5.0` 语言模式），AppKit + SwiftUI 混合；最低部署目标 macOS 27.0

**主要依赖**：AppKit、SwiftUI、ApplicationServices（`AXUIElement` / `AXObserver`）、CoreGraphics（`CGWindowListCopyWindowInfo`）、ServiceManagement（登录项）。不新增任何第三方依赖

**存储**：`~/Library/Application Support/MeowingCat.MacsyZones/` 下的 `AppSettings.json` 与 `UserLayouts.json`（`Codable` JSON，`MacsyZones/UserData.swift` 统一落盘）

**测试**：工程没有 XCTest target，也不新增（新增测试 target 会改动 pbxproj 与签名配置，且上游没有）。验证分三层：

1. 构建：`scripts/build-debug.sh`、`scripts/build-release-dmg.sh`
2. 脚本断言：`scripts/tests/*.swift` 用 `/usr/bin/swift` 直接跑，从真实源码抽片段做编译级断言（上游 `ada5b51` 已有方案，已实测可在 fork 源码上通过）
3. 手工 QA：`quickstart.md` 的场景清单（光标、循环、对账、内存、构建日志）

**目标平台**：macOS 27（Apple Silicon 优先）

**项目类型**：macOS 菜单栏常驻桌面应用，单 Xcode 工程

**性能目标**：闲置 CPU ≤ 2%；激活路径主线程无 > 50ms 阻塞；冷布局物化次数 0（见 SC-004 / SC-007）

**约束**：

- 推送目标只有 `jiezhengj/MacsyZones` 的 `custom`；`upstream` 只允许 `fetch`
- 签名固定 `Manual` + `Apple Development: jie.zhengj@qq.com (8SDSF987N2)` + Team `74FR87HYTH`
- 不得改动 `MACOSX_DEPLOYMENT_TARGET = 27.0`、`SWIFT_VERSION`、`scripts/verify-signing.sh` 校验口径
- 本 feature 不预判也不登记下一发布版本（FR-023）

# 章程检查

*GATE：Phase 0 之前必须通过；Phase 1 设计完成后复核。*

| 章程条款 | 判定 | 说明 |
|---|---|---|
| 原则一 上游代码复用优先 | 通过 | 五个切片全部以上游提交为蓝本，逐处标注提交哈希；唯一偏离是设置界面落到 fork 自研 `SettingsView.swift`（上游用 `Popover.swift`，fork 已删除），属必要适配 |
| 原则二 单向同步与主权仓库隔离 | 通过 | 只 `git fetch upstream`，不推送、不开 PR；实现阶段所有提交只进 `custom` |
| 原则三 严谨的本地自测与正式签名审计 | 通过 | 实现阶段必须先跑 Debug/Release 构建 + `scripts/check-version.sh` + `scripts/verify-signing.sh`，再交用户手工验收；不改 bundle id / 签名 / Team |
| 原则四 量化版本决策与门禁约束 | 通过（口径已更新） | 用户裁定（m00293）版本号与级别只在创建 Release 前按实际变更判定，`RELEASES.md`/`VERSIONING.md`/`AGENTS.md`/`BUILD.md` 已同步改写；本 feature 因此不承担版本登记，发布时才跑门禁 |
| 原则五 配置持久化与平滑迁移 | 通过 | 新设置字段用 `Bool?` + `?? 默认值` 解码（与现有 20 个字段同构），旧 `AppSettings.json` 缺字段不会导致解码失败；不引入强解包 |
| 额外约束·macOS 27 基线 | 通过 | 不新增版本条件编译分支 |
| 额外约束·窗口惰性物化 | 通过（强化） | P2 切片 3 正是对惰性物化的收口，并补自动化回归闸门 |
| 额外约束·主线程调度 | 通过 | 对账的 CG 列表读取在后台队列，注册表写入统一 `Task { @MainActor }`，与 fork 现有 `refreshApplication` 一致 |
| 额外约束·规则文档双向同步（`AGENTS.md` ≡ `CLAUDE.md`） | 存在预存偏差 | 仓库当前没有 `CLAUDE.md`，本 feature 不修改任何规则文档，未扩大偏差；处置见复杂度跟踪 |

设计完成后复核：无新增违反项。

# 项目结构

### 本文档目录（本 feature）

```text
specs/002-upstream-v31-backport/
├── plan.md              # 本文件
├── research.md          # Phase 0：回移方式的决策与依据
├── data-model.md        # Phase 1：设置字段、观察登记表、对账输入输出、对话框生命周期
├── quickstart.md        # Phase 1：构建、脚本断言与手工验收清单
├── contracts/
│   └── app-settings-data.md   # 持久化契约：AppSettings.json 字段与向后兼容规则
├── checklists/
└── tasks.md             # Phase 2（/speckit-tasks 产出）
```

### 源码布局（仓库根，单 Xcode 工程）

```text
MacsyZones/                     # 应用源码（target 唯一）
├── App.swift                   # 切片 4：WindowObserverManager（对账/重扫/三态判定）、AppDelegate
├── Macsy.swift                 # 切片 4 复用的元素获取 helper、节流、DragSessionState 退出清理
├── Layout.swift                # 切片 2（SnapResizer 光标）、切片 3（物化比较、警告对话框）
├── QuickSnapper.swift          # 切片 1（布局循环）
├── Settings.swift              # 切片 1（AppSettingsData 字段与持久化）
├── SettingsState.swift         # 切片 1（脏检测/保存/刷新快照）
├── SettingsView.swift          # 切片 1（快速吸附分区中文开关）
├── ShortcutInputView.swift     # 切片 5（onChange 双参数）
├── UserData.swift              # 惰性物化实现（切片 3 的回归断言对象）
└── ...（其余文件本 feature 不改）

MacsyZones.xcodeproj/           # 切片 5：project.pbxproj、xcshareddata/xcschemes/MacsyZones.xcscheme
scripts/
├── build-debug.sh              # 既有
├── build-release-dmg.sh        # 既有
├── check-version.sh            # 既有
├── verify-signing.sh           # 既有
├── check_lazy_lifecycle.sh     # 新增（切片 5，上游原文移植）
└── tests/
    ├── README.md               # 新增（上游原文移植）
    ├── lazy-stubs.swift        # 新增（上游原文移植）
    └── lazy-assertions.swift   # 新增（上游原文移植）
```

**结构决策**：沿用既有单工程布局，不新增 module、target 或目录层级；新增文件只有 `scripts/check_lazy_lifecycle.sh` 与 `scripts/tests/` 三个文件，全部来自上游原样移植（已对 fork 源码试跑通过，139 条断言 PASS）。

# 复杂度跟踪

| 偏差/复杂度 | 为什么必须这样 | 更简单的替代方案为什么不行 |
|---|---|---|
| 不新增 XCTest target，改用 `/usr/bin/swift` 跑独立断言脚本 | 工程只有一个 app target、签名与 bundle id 固定；新增测试 target 会改动 pbxproj、scheme 与签名配置，且上游从未提供 | 直接新增 XCTest target：改动面远大于被验证的代码，且与「上游代码复用优先」冲突；纯手工验收：无法在 CI/命令行复现，SC-004 无客观闸门 |
| 章程要求 `AGENTS.md` 与 `CLAUDE.md` 内容完全一致，但仓库没有 `CLAUDE.md`（预存偏差） | 该文件缺失早于本 feature 存在，本 feature 只是修改了 `AGENTS.md` 的版本登记条款（已单独提交 `9711960`） | 本 feature 顺手创建 22KB 的 `CLAUDE.md` 副本：属于治理决策、与回移范围无关，且会掩盖「两份文档如何长期保持同步」的真问题；建议由用户单独决定（复制 / 软链 / 改为单一来源 + 生成脚本） |
