# 快速验证指南

本文件是「改完怎么证明它真的好了」的运行手册：命令可直接复制执行，手工场景按用户故事编号对应 `spec.md`。实现细节见 `plan.md` 与 `research.md`，数据结构见 `data-model.md`。

## 前置条件

- macOS 27 + Xcode 27（命令行工具链完整，`xcodebuild -version` 可用）
- 已授予 MacsyZones 辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能）
- 仓库在 `custom` 分支、工作区干净：`git status --short` 无输出
- 本机无第三方依赖要求（脚本只用 `grep`/`awk`/`/usr/bin/swift`）

## 一、构建

```bash
bash scripts/build-debug.sh
bash scripts/build-release-dmg.sh
```

**期望**：两条命令均 exit 0；DMG 落在 `/tmp`（构建脚本自带此约定，不得进仓库）。构建日志里不得出现新增的 `onChange` 弃用警告（对照改动前日志）。

## 二、脚本断言（惰性物化回归闸门）

```bash
bash scripts/check_lazy_lifecycle.sh
```

**期望**：

```text
Testing lazy layout lifecycle from /Users/jiezhengj/Documents/Project/MacsyZones
PASS: 139 assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source; no AppKit or application launch
```

该脚本从真实源码抽取 `UserLayout` 与 `startEditing/stopEditing/toggleEditing`，锚点漂移会以 `FAIL: could not extract …` 退出 1（fail closed）。故意改动 `UserData.swift:152` 的 `class UserLayout {` 行可验证闸门确实会拦。

## 三、手工场景

### 场景 A（用户故事 1）：快速吸附只切区域布局

准备：库里有 1 个区域布局（≥2 个分区）与 1 个网格布局。

1. 按快速吸附快捷键唤出面板，连按 ← 10 次、→ 10 次。
   **期望**：只在区域布局上循环；每次停留时 1–9 都能吸附到对应分区。
2. 打开设置 → 快速吸附 → 关闭「仅切换区域布局」→ 保存。
   **期望**：无需重启，下一次唤出即可切到网格布局；当前是网格布局时按 ← / → 能正常离开。
3. 关闭开关后再打开、然后点「取消」。
   **期望**：行为保持上一次保存的取值（暂存式设置生效，开关回到原值）。
4. 把库删到只剩网格布局（区域布局全删），开启「仅切换区域布局」后唤出面板按 ← / →。
   **期望**：无反应、不崩溃、面板不消失。

### 场景 B（用户故事 2）：调整条光标方向

1. 两个窗口左右吸附铺满，鼠标移到两窗之间的**竖向**调整条上。
   **期望**：光标为左右箭头（↔），可拖动改变左右宽度。
2. 两窗上下吸附，移到**横向**调整条上。
   **期望**：光标为上下箭头（↕）。
3. 进入布局编辑器，重复 1、2，观察编辑器里出现的同类调整条。
   **期望**：方向与光标关系一致，不出现「编辑器里对、桌面上错」。

### 场景 C（用户故事 3）：惰性物化不被打穿

1. 退出 MacsyZones 再启动（冷启动），什么都不做，只移动鼠标 60 秒。
   **期望**：不出现任何布局窗口；`debugLog` 里没有因鼠标移动触发 `LayoutWindow` 初始化的记录。
2. 打开一个只有 1 个分区的布局编辑器，不跨屏。
   **期望**：没有 380×340 的警告面板被创建（可通过日志里 `ScreenChangeWarningDialog` 的创建记录确认；未改日志时用「内存占用不随分区数线性增长」观察）。
3. 把编辑器窗口拖到另一块屏幕。
   **期望**：警告面板出现且只出现一次；点「知道了」后关闭编辑器，内存回到编辑器打开前的量级（无残留 panel）。

### 场景 D（用户故事 4）：窗口观察对账

1. 正常启动后，打开一个「在后台建窗」的 App（如 Safari 新建窗口后切走再切回）。
   **期望**：12 秒内该窗口的 AX 移动事件生效——拖动它跨屏时布局能跟随（不再只有鼠标兜底）。
2. 反复用 ⌘Tab 切换应用 20 次，观察日志。
   **期望**：每次激活有一次对账记录；不出现已观察窗口被重复注册；无 `Failed to register AX notifications` 刷屏。
3. 闲置 5 分钟，`top -pid $(pgrep MacsyZones) -l 60 -s 5 | grep MacsyZones` 观察。
   **期望**：CPU 平均 ≤ 2%（SC-007）。
4. 系统设置里撤销辅助功能权限，再操作窗口。
   **期望**：日志按退避降频，不刷屏；恢复权限后自动恢复观察。

### 场景 E（构建清单与代码健康）

1. Xcode 27 打开 `MacsyZones.xcodeproj`。
   **期望**：不再提示「推荐设置」更新。
2. `grep -n "LastUpgradeCheck" MacsyZones.xcodeproj/project.pbxproj`、`grep -n LastUpgradeVersion MacsyZones.xcodeproj/xcshareddata/xcschemes/MacsyZones.xcscheme`
   **期望**：均为 2700。

### 场景 F（旧配置升级 / 契约）

1. 备份并编辑 `~/Library/Application Support/MeowingCat.MacsyZones/AppSettings.json`，删掉 `quickSnapperZoneLayoutsOnly` 键。
2. 启动 → 打开设置 → 快速吸附。
   **期望**：开关显示为「开启」；其余设置项全部保留（没有因为解码失败被重置）。
3. 关闭开关并保存 → 退出 → 重新启动。
   **期望**：开关仍为关闭，`AppSettings.json` 中出现 `"quickSnapperZoneLayoutsOnly":false`。

### 场景 G（零回归）

按 v2.0.0 的基本盘走一遍：冷启动首次拖拽吸附、多屏 / Space 切换后布局跟随、多分区联合吸附、右键取消吸附、按住修饰键拖拽。全部与改动前一致（SC-009）。

## 四、交付前门禁（发布动作，不在本 feature 内）

本 feature 不登记、不预判版本号。仅在真正准备发版时执行：

```bash
bash scripts/check-version.sh <目标版本> <major|minor|patch>
bash scripts/verify-signing.sh
```

`check-version.sh` 会要求目标版本高于已发布版本，因此实现过程中不跑它，避免产生「必须改 MARKETING_VERSION」的假冲突。

## 五、排错

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `check_lazy_lifecycle.sh` 报 `could not extract exactly one complete UserLayout` | 有人改了 `UserData.swift` 的 `class UserLayout {` 起始行或 `struct UpdateStateData:` 行 | 修正锚点或恢复命名；这是脚本的保护机制，不是脚本坏了 |
| `check_lazy_lifecycle.sh` 报 `swift: command not found` | 未安装 Xcode 命令行工具 | `xcode-select --install` |
| 构建通过但开关不持久化 | `SettingsState.refresh()` 的 `AppSettingsData(...)` 漏了新字段 | 按 `data-model.md` 的三处清单逐项对照 |
| 光标仍是上下箭头 | `NSHostingView(rootView:)` 没把 `mode` 传进 `SnapResizerView` | 检查 `MacsyZones/Layout.swift:1921-1922` 与视图默认值 |
| 对账后窗口被注册两次 | 对账没跳过 `observedIDs` 里已有的窗口 | 按 `data-model.md` 的 ReconcileView 规则加 `observedIDs` 过滤 |
