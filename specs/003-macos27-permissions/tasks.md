# Tasks: macOS 27 权限模型适配

**Input**: Design documents from `/specs/003-macos27-permissions/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: 工程无 XCTest target（见 plan.md「Complexity Tracking」），因此不生成单元测试任务；改用桩断言脚本 + 运行期日志断言 + quickstart 手动矩阵，这些存在于「验证」类任务中。

**Organization**: 按用户故事分阶段，每个故事可独立实现与独立验收。

## Format: `[ID] [P?] [Story] Description`

- **[P]**：可并行（不同文件、无未完成依赖）
- **[Story]**：所属用户故事（US1–US5）；Setup / Foundational / Polish 阶段不带
- 每条任务都带确切文件路径

## Path Conventions

单 target macOS App：源码在 `MacsyZones/`，脚本在 `scripts/`，验证桩在 `scripts/tests/`，设计与验证文档在 `specs/003-macos27-permissions/`。

## Phase 1: Setup（共享准备）

**Purpose**：建立基线与取证素材，避免后面拿「改完之后」当基线。

- [ ] T001 运行 `bash scripts/build-debug.sh`，确认 `** BUILD SUCCEEDED **` 且 `verify-signing.sh` PASS；把 `warning:` 计数与原文写入 `/tmp/m003-warnings-baseline.txt`
- [ ] T002 [P] 抓取现有权限行为基线：启动当前安装副本，`log show --last 5m --predicate 'process == "tccd" AND eventMessage CONTAINS "MeowingCat.MacsyZones"'` 与 app 崩溃报告一并保存到 `/tmp/m003-permission-baseline.log`，并记下当前是否弹模态框（供回归对比）

---

## Phase 2: Foundational（阻塞性前置）

**Purpose**：权限模型与引导基础设施。**所有用户故事都依赖这里**，必须在 US1 之前完成。

- [ ] T003 在 `MacsyZones/PermissionCenter.swift` 定义类型：`PermissionCapability`（`windowControl` / `inputMonitoring` / `eventPosting`）、`PermissionStatus`（`granted` / `denied` / `unknown` / `notRequired`）、`PermissionProbe`、`CapabilityState`、`PermissionSnapshot`，字段与取值遵循 `data-model.md` 的 `PermissionCapability`、`PermissionStatus`、`PermissionProbe`、`CapabilityState`、`PermissionSnapshot` 定义
- [ ] T004 在 `MacsyZones/PermissionCenter.swift` 实现窗口控制探针：前台 app（`NSWorkspace.shared.frontmostApplication`）与 `com.apple.finder` 各一次 `AXUIElementCopyAttributeValue(kAXWindowsAttribute)`，另取 `AXIsProcessTrusted()` 作参考值；1 秒超时，在 `.utility` 队列执行，结果按 `data-model.md` 的 `PermissionProbe.id`（`frontmost` / `finder` / `api`）记录
- [ ] T005 在 `MacsyZones/PermissionCenter.swift` 实现输入监听探针（`CGPreflightListenEventAccess()`，`PermissionProbe.id = preflight`）与 `eventPosting` 固定 `notRequired` 约定；实现 `PermissionSnapshot.overall` 与窗口控制的汇总规则（`data-model.md`「窗口控制汇总规则」表，含「部分目标可控」）
- [ ] T006 在 `MacsyZones/PermissionCenter.swift` 实现复核调度：`start()` / `stop()` / `recheck(trigger:)`，同 trigger 1 秒去重；触发源 `launch` / `activate` / `wake` / `ax-failure` / `manual` / `poll`（`data-model.md` 的 `CapabilityState.trigger` 取值）；`granted` 后 30s 轮询、非 `granted` 时 5s × 最多 24 次；所有计时器与工作项可取消
- [ ] T007 在 `MacsyZones/PermissionCenter.swift` 实现宽限状态机：`CapabilityState.suspectUntil` 与 60 秒规则，仅在「上一次 `granted`、本次 `denied`、距进程启动 < 60s」时进入可疑态，其余 `granted→denied` 立即生效（`data-model.md` 状态机与不变式 1–4）
- [ ] T008 [P] 在 `MacsyZones/Utils.swift` 增加权限日志设施：`os.Logger(subsystem: "MeowingCat.MacsyZones", category: "permissions")` 与固定字段输出（`capability` / `status` / `probe` / `target` / `error` / `latencyMs` / `trigger`），路径类字段用 `.private`
- [ ] T009 [P] 在 `MacsyZones/PermissionGuidance.swift` 实现 `GuidanceTarget` 与版本判定（`ProcessInfo.processInfo.operatingSystemVersion.minor >= 3` 选 pane，禁止 `#available`），深链与文案按 `contracts/guidance-targets.md` 的「深链契约」与「文案契约」；`NSWorkspace.open` 失败时按「行为契约」兜底
- [ ] T010 [P] 编写 `scripts/tests/permission-stubs.swift`（复刻三态判定与宽限计算，不引入 AppKit）与 `scripts/tests/permission-assertions.swift`（断言：`.success`→granted、`-25211`→denied、`-25204`/超时/目标缺失→unknown、双目标都 `-25211`→denied、部分成功→granted+部分可控、宽限 60s 边界）
- [ ] T011 编写 `scripts/check_permission_model.sh`：调用 T010 的桩与断言，并 grep 不变量（`MacsyZones/PermissionCenter.swift` 中不出现 `#available`、不出现 `AXUIElementSetAttributeValue`、权限路径不出现 `exit(`）；输出 `PASS: 权限模型断言通过（<N> assertions）`

**Checkpoint**：`bash scripts/check_permission_model.sh` 通过后，US1–US5 可并行开工（各自改不同文件）。

---

## Phase 3: US1（P1）首次授权引导指向真正需要的开关

**Goal**：未授权用户在 macOS 27.3 上看到正确面板路径并能一键打开，且不被模态框挡住。

**Independent Test**：quickstart 场景 A —— 撤销授权后启动，引导出现、文案含正确面板名、按钮能跳到对应面板、app 不退出、主界面可用。

- [ ] T012 [US1] 改造 `MacsyZones/Info.swift` 的 `AccessibilityPermissionView`：按 T009 的 `GuidanceTarget` 输出步骤（27.3+ 先 System & App Protection Override、再看无障碍），按钮改为「打开系统设置」「重新检测」，删除旧截图引用（`Accessibility-Permission-Tutorial-1/2`）与「重启后继续」文案（FR-006/FR-007/FR-008/FR-009）
- [ ] T013 [US1] 在 `MacsyZones/Info.swift` 把 `AccessibilityDialog` 改为非模态面板：去掉 `.screenSaver` 级别、去掉 `onCancel` 的 `exit(0)`、允许随时关闭（FR-004/FR-010）
- [ ] T014 [US1] 改造 `MacsyZones/App.swift`：删除 `hasAccessibilityPermission`、`checkAccessibilityPermission()`、`requestAccessibilityPermissions()`，改为 `PermissionCenter.shared.start()`；`showAccessibilityPermissionPopover()` 改为非模态引导入口
- [ ] T015 [US1] 在 `MacsyZones/App.swift` 的 `applicationDidFinishLaunching` 中接线：`windowControl != .granted` 时展示引导（不阻塞、不抢焦点），已在启动流程内的窗口观察与菜单栏图标照常初始化
- [ ] T016 [US1] 构建并执行 quickstart 场景 A，把实测结果（本 app 实际出现在哪个面板、深链是否落点正确）回填到 `specs/003-macos27-permissions/quickstart.md` 与 `research.md` R12

---

## Phase 4: US2（P1）权限状态持续复核

**Goal**：授权/撤销/唤醒/切换应用后，状态自动收敛，不再需要重启；瞬时误判不打扰用户。

**Independent Test**：quickstart 场景 B 与 C —— 授权后 10 秒内变 `granted`；撤销后 60 秒宽限内无提示、之后出现非模态提示。

- [ ] T017 [US2] 在 `MacsyZones/App.swift` 注册复核触发：`NSWorkspace.didActivateApplicationNotification`、`NSWorkspace.didWakeNotification`、`NSApplication.didBecomeActiveNotification` 分别调用 `permissionCenter.recheck(trigger:)`，并在 `applicationWillTerminate` 中 `stop()`（FR-003）
- [ ] T018 [US2] 在 `MacsyZones/App.swift`（`observeWindow` 失败分支）与 `MacsyZones/Macsy.swift`（AX 写窗口属性失败处）把 `kAXErrorAPIDisabled` 上报 `PermissionCenter.shared.reportAXFailure(_:)`，触发 `trigger=ax-failure` 复核（FR-003）
- [ ] T019 [US2] 在 `MacsyZones/App.swift` 把状态映射到常驻 UI：菜单栏图标附加未授权标记；状态变化时刷新设置窗口顶部非模态横幅文案（`CapabilityState.status` 变化才刷新，避免闪烁，见 `data-model.md` 不变式 4）
- [ ] T020 [US2] 在 `MacsyZones/App.swift` 把 onboarding 条件由 `hasAccessibilityPermission` 改为 `PermissionCenter.shared.snapshot.overall == .granted`，并保证未授权时引导优先于 onboarding（FR-004/FR-009）
- [ ] T021 [US2] 构建并执行 quickstart 场景 B、C，记录实际收敛时间与宽限行为到 `specs/003-macos27-permissions/quickstart.md` 的实测记录段

---

## Phase 5: US3（P2）诊断面板与 Release 可观测性

**Goal**：用户能自己看到「卡在哪一类权限」，维护者能收到可判定的结构化报告。

**Independent Test**：设置里能看到三能力状态与探针明细；「复制报告」产出可通过 `contracts/permission-report.schema.json` 校验的 JSON；`log show` 能过滤到权限日志。

- [ ] T022 [P] [US3] 创建 `MacsyZones/PermissionDiagnosticsView.swift`：展示 `PermissionSnapshot` 各能力状态、最近检测时间、探针明细（含原始 `axError`）、`app` 与 `system` 信息，底部「重新检测」「复制报告」按钮（FR-016）
- [ ] T023 [US3] 在 `MacsyZones/SettingsView.swift` 的 `AdvancedSettingsSection` 之后插入 `PermissionDiagnosticsSection`（只在设置窗口打开时构建，遵守惰性物化约束）
- [ ] T024 [US3] 在 `MacsyZones/PermissionCenter.swift` 实现 `PermissionDiagnosticReport`（`Codable`，`schemaVersion = 1`）与「复制到剪贴板」：字段与必填项严格遵循 `data-model.md` 的 `DiagnosticReport` 与 `contracts/permission-report.schema.json`，不采集窗口标题与个人数据（FR-017/FR-018）
- [ ] T025 [US3] 编写 `scripts/permission-smoke.sh`：启动构建产物 20 秒 → `log show` 抓 `subsystem == "MeowingCat.MacsyZones" AND category == "permissions"` → 断言至少一条 `capability=windowControl` 且字段齐全、`latencyMs < 1000`、无 `fatal error` → 退出码反映结果（contracts/guidance-targets.md「演示/冒烟契约」）
- [ ] T026 [US3] 用 quickstart「五、诊断报告」的校验片段验证报告 JSON 符合 schema，并把实际报告样例存到 `/tmp/m003-report-sample.json` 供人工核对

---

## Phase 6: US4（P2）全局输入监听单独检测与降级

**Goal**：缺输入监听时功能按能力降级且用户知道原因，而不是静默失灵。

**Independent Test**：quickstart 场景 F —— 关闭 Input Monitoring 后，拖动吸附暂停且横幅说明原因，Carbon 全局快捷键仍可用，app 不崩溃。

- [ ] T027 [US4] 在 `MacsyZones/App.swift` 的 `applicationDidFinishLaunching` 中按 `snapshot.inputMonitoring` 决定是否安装全局监视器（`leftMouseDown`/`leftMouseDragged`/`leftMouseUp`/`keyDown`+`flagsChanged`/`rightMouseDown`），并在 `MacsyZones/Layout.swift` 的 `mouseMoved` 监视器安装处做同样判断（FR-011/FR-013）
- [ ] T028 [US4] 实现降级矩阵（FR-012/FR-014）：缺输入监听 → 拖动与悬停高亮暂停、横幅标注「缺少输入监听权限」、Carbon 快捷键保留；缺窗口控制 → 布局编辑器可打开但保存/吸附提示只读；per-target 部分可控 → 诊断面板 `notes` 标注「部分目标受控」，不在日志里刷错误
- [ ] T029 [US4] 构建并执行 quickstart 场景 F，记录降级行为与日志到 `specs/003-macos27-permissions/quickstart.md` 实测记录段

---

## Phase 7: US5（P3）跨 27.x 子版本与升级路径稳定

**Goal**：同一构建在 27.0–27.2 与 27.3+ 都给出正确引导；升级用户不被重新挡住。

**Independent Test**：桩断言覆盖两套 pane 映射；代码里无 `#available`；升级场景结论有书面记录。

- [ ] T030 [US5] 在 `scripts/tests/permission-assertions.swift` 与 `scripts/check_permission_model.sh` 增加两套形态断言：`minor < 3` → `legacyAccessibility`、`minor >= 3` → `systemProtectionOverride` 且兜底为 `accessibilityApps`（FR-019）
- [ ] T031 [US5] 验证并记录升级路径（FR-020）：按 quickstart 场景 D 在可用机器上执行「27.2 授权 → 升级 27.3 → 启动」，结论回填 `quickstart.md` 场景 D 与 `research.md` R12；若本机无法执行，明确标注「未实机验证」及原因
- [ ] T032 [US5] 执行边界断言：`git diff` 中不含 `#available`、`com.apple.private.*` entitlement、`sqlite3`/TCC 数据库访问、`MACOSX_DEPLOYMENT_TARGET`/`PRODUCT_BUNDLE_IDENTIFIER`/`DEVELOPMENT_TEAM`/`CODE_SIGN_*` 变更（FR-021/FR-022）

---

## Phase 8: Polish 与交付

**Purpose**：跨故事验证、文档回填与切片提交。

- [ ] T033 构建矩阵：`bash scripts/build-debug.sh`（Debug + 签名校验）与 Release 配置 `xcodebuild ... -configuration Release` + `bash scripts/verify-signing.sh <app>` 双 PASS，`warning:` 计数为 0
- [ ] T034 执行 quickstart 场景 A–F 全量手动矩阵，逐项回填 `specs/003-macos27-permissions/quickstart.md` 的实测记录表（无法自动化的项注明原因）
- [ ] T035 章程与文档复核：确认无新增配置字段（章程五）、无 `#available`（额外约束）、主线程纪律（探针在后台队列）、`AGENTS.md` 是否需要补「权限排障」段落
- [ ] T036 分切片提交（setup / foundational / US1 / US2 / US3 / US4 / US5 / 文档）并在本文件末尾写「实现记录」：提交哈希、验证结果、偏差与未完成项

---

## Dependencies

```text
Phase 1 (T001–T002) → Phase 2 (T003–T011) → 以下可并行
  ├─ Phase 3 US1 (T012–T016)   ← T009 提供引导表
  ├─ Phase 4 US2 (T017–T021)   ← T006/T007 提供调度与宽限
  ├─ Phase 5 US3 (T022–T026)   ← T003–T007 提供快照；T022 与 T023 可并行
  ├─ Phase 6 US4 (T027–T029)   ← T005 提供 inputMonitoring 状态
  └─ Phase 7 US5 (T030–T032)   ← T009/T030 依赖 T009 完成
Phase 8 (T033–T036) 依赖全部用户故事完成
```

- US1 与 US2 都改 `MacsyZones/App.swift`，但改动区域不同（启动接线 vs 通知注册）；若并行执行，需在同一文件上顺序写入或由一人合并。
- US3 的 `PermissionDiagnosticsView.swift`（T022）与 `SettingsView.swift`（T023）可并行，T024 依赖两者字段确认。

## Parallel Execution Examples

**US1 内部**：T012（`Info.swift` 视图）与 T014（`App.swift` 接线）不同文件，可并行；T013 与 T012 同文件，需顺序。

**US3 内部**：T022（新文件）与 T025（`scripts/permission-smoke.sh`）可并行。

**跨故事**：T008（`Utils.swift`）、T009（`PermissionGuidance.swift`）、T010（`scripts/tests/`）在 Phase 2 内标 [P]，三者文件互不重叠。

## Implementation Strategy

**MVP = US1 + 前置 Phase 2**：完成 T003–T011 与 T012–T016 后，未授权用户已不再被模态框挡住、能跳到正确面板——这是本 feature 的核心价值（当前用户被卡死的正是这一步）。

**增量顺序**：MVP → US2（自动收敛，去掉「重启 app」依赖）→ US3（诊断与日志，让后续排障不再靠猜）→ US4（输入监听的诚实降级）→ US5（跨版本与升级）。每个故事完成即构建 + 对应 quickstart 场景验收，不留到最后一起验。

## 实现记录

（实现完成后填写：提交哈希、验证结果、与计划的偏差、未完成项。）
