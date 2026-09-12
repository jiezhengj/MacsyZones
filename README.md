[![GitHub release](https://img.shields.io/github/release/jiezhengj/MacsyZones.svg?style=flat-square&color=informational)](https://github.com/jiezhengj/MacsyZones/releases)

基于 [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) 深度二次开发的 macOS 窗口管理工具中文定制版。本项目已全面升级至 **macOS 27 专版基线**，移除了所有 Pro 许可证与捐赠限制，重构了核心拖拽状态机与辅助功能观察器，并引入多项上游前沿交互特性。

> [!WARNING]
> 本项目仅为个人自用定制版本，不对外商业分发。

> [!NOTE]
> 感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！

# 系统要求

* macOS 27.0 或更高版本
* Apple Silicon 或 Intel 架构 Mac
* 需要授予系统辅助功能（Accessibility）与屏幕录制/显示捕获权限

# 版本说明

* 当前版本：`v2.0.0`（Major 重构发布）
* 上游基线：基于上游 `v3.0.4` 改造并整合多项核心 PR 增强
* 完整版本台账与演化历史请参阅 [`RELEASES.md`](RELEASES.md)，版本判定规则见 [`VERSIONING.md`](VERSIONING.md)。

| 本项目版本 | 上游基线 | 版本类型 | 核心更新说明 |
|-----------|---------|---------|-------------|
| v2.0.0 | v3.0.4 | Major | macOS 27 专版升级、冷启动首拖自愈状态机、惰性物化与世代代号、6 态分区对齐、拖拽自动吸附与多区跨越 |
| v1.2.5 | v3.0.4 | Patch | 稳定基线版本，提供版本门禁、正式签名与 DMG 可重复构建 |
| v1.2.4 | v3.0.4 | Patch | 改进更新体验：下载状态可视化管理 |
| v1.2.3 | v3.0.4 | Patch | 修复设置界面所有帮助按钮无反应问题 |
| v1.2.2 | v3.0.4 | Patch | 关于界面优化，新增版本号显示 |
| v1.2.1 | v3.0.4 | Patch | 修复版本号识别问题，自动更新流程正常工作 |
| v1.2.0 | v3.0.4 | Minor | 帮助界面重构，功能说明就近分散到各设置卡片 |
| v1.1.0 | v3.0.4 | Minor | 界面完全中文化、移除许可证限制、独立设置窗口与布局管理优化 |
| v1.0.0 | v3.0.4 | Major | 首个中文定制版 |

# 核心特性与改进

## 1. 平台 SDK 与架构专版化
* **macOS 27 纯净基线**：统一部署目标至 macOS 27.0，彻底移除所有历史 `#available(macOS 12.0/13.0/26.0, *)` 宏分支与屏幕数组索引回退逻辑，原生基于 Display UUID 绑定 Space。
* **AppKit 约束重入加固**：针对 macOS 27 全面加固 `NSHostingView` 尺寸声明（`sizingOptions = []`），隔离主线程约束触发布局重入隐患。

## 2. 核心引擎重构与开机首拖自愈
* **纯 Swift 拖拽状态机**：引入 `DragSessionState` 解耦状态跟踪，精准捕获拖拽初始化、移动、吸附就绪与取消全生命周期。
* **辅助功能观察器重构**：`WindowObserverManager` 引入退避重试（Backoff Retry）与焦点同步，在系统刚开机启动、Finder 尚未注册通知时实现自动重试与重新订阅。
* **物理位移双重兜底**：结合鼠标位移阈值（>5pt）兜底辅助功能通知丢失场景，彻底解决冷启动后 Finder 首次拖拽无吸附区域的问题。

## 3. 内存与生命周期管理优化
* **UserLayout 惰性窗口物化**：移除启动阶段无意义的全量双重布局加载，仅在实际触发展示或吸附计算时按需物化，极大缩短开机启动耗时。
* **QuickSnapper 世代代号与彻底释放**：引入 `lifecycleGeneration` 世代代号机制，在关闭和重置吸附器时完全清空闭包、Window 实例与观察者，阻断内存泄漏与跨世代重入。

## 4. 分区编辑与拖拽吸附交互增强
* **分区对齐工具栏**：分区编辑窗口新增 6 态对齐工具栏（左/居中/右、上/居中/下），在保持分区尺寸不变的前提下实现一键吸附对齐。
* **拖拽自动吸附与粘性右键取消**：支持在无辅助键下直接拖拽至边缘或分区内自动吸附，长按 Command 键实现多分区联合吸附跨越；拖拽中单击右键可平滑取消吸附。
* **崩溃隐患修复**：全面防御 `reArrange()` 等关键数据处理中的隐式解包崩溃，增强运行时容错。

## 5. 定制化与本地化特性
* **纯净无干扰体验**：彻底移除上游的 Pro 许可证验证、公钥验签以及捐赠弹窗逻辑。
* **完全中文化界面**：主界面、菜单栏、设置中心及帮助弹窗全面汉化。
* **独立设置中心**：替代原轻量 Popover，提供完整的布局创建、复制、重命名、快捷键配置与系统权限状态监控。
* **安全自动更新**：内置静默更新检查，指向本项目 GitHub Releases 仓库。

# 安装指南

1. 从 [Releases 页面](https://github.com/jiezhengj/MacsyZones/releases) 下载最新版本的 `MacsyZones-v2.0.0.dmg`。
2. 打开 DMG 文件，将 `MacsyZones.app` 拖入 `Applications` 应用程序文件夹。
3. 首次启动时，应用需要以下系统权限：
   * **辅助功能（Accessibility）**：用于监听窗口拖拽与调整窗口大小位置。
   * **屏幕录制/显示捕获（Screen Recording）**：用于检测多显示器状态与计算吸附覆盖层。
4. 如遇 macOS 系统的安全提示（未识别的开发者），请前往 **系统设置 → 隐私与安全性**，找到 MacsyZones 并点击 **仍要打开**。

# 从源码构建

本项目采用正式 Apple Development 证书签名，提供全自动构建与发布脚本：

```bash
# 克隆本项目仓库
git clone https://github.com/jiezhengj/MacsyZones.git
cd MacsyZones

# 语法与签名审计测试（Debug 构建）
scripts/build-debug.sh

# 检查版本一致性与递增级别（Major / Minor / Patch）
scripts/check-version.sh 2.0.0 major

# 构建正式签名的 Release DMG（自动在 /tmp 目录生成并通过 hdiutil 校验）
scripts/build-release-dmg.sh 2.0.0 major
```

关于证书配置、签名审计、DMG 制作与 GitHub Release 发布流程的完整指南，请参阅 [`BUILD.md`](BUILD.md)。

# 许可证

本项目遵循 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 许可证。

原始项目 Copyright (C) 2024, Oğuzhan Eroğlu.

# 致谢

感谢上游开源项目 [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) 及原作者 Oğuzhan Eroğlu 的杰出工作！
