# MacsyZones 中文定制版

[![GitHub release](https://img.shields.io/github/release/jiezhengj/MacsyZones.svg?style=flat-square&color=informational)](https://github.com/jiezhengj/MacsyZones/releases)

基于 [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) 二次开发的 macOS 窗口管理工具中文定制版。

> ⚠️ **声明**：本项目仅为个人自用，不对外分发。

> 🙏 感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！

## 版本与发布

当前已发布版本：`v1.2.5`

下一发布目标：`v1.2.6`（Patch）

完整版本台账见 [`RELEASES.md`](RELEASES.md)，版本判定规则见 [`VERSIONING.md`](VERSIONING.md)。本项目版本与上游版本独立演进；仓库中继承的上游 tags 不代表本项目版本。

| 本项目版本 | 上游版本 | 说明 |
|-----------|---------|------|
| v1.0.0 | v3.0.4 | 首个中文定制版 |
| v1.1.0 | v3.0.4 | 汉化、功能整合与 UI 优化 |
| v1.2.0 | v3.0.4 | 帮助界面改造，功能说明分散到各设置区域 |
| v1.2.1 | v3.0.4 | 修复版本号问题，更新功能正常工作 |
| v1.2.2 | v3.0.4 | 关于界面优化，新增版本号显示 |
| v1.2.3 | v3.0.4 | 修复设置界面所有帮助按钮无反应问题 |
| v1.2.4 | v3.0.4 | 改进更新体验：下载状态可视化管理 |
`v1.2.6` 是回滚新架构后，保留版本门禁、正式签名和可重复 DMG 构建改进的下一发布目标。

## 改造内容

- ✅ 界面完全中文化
- ✅ 移除 Pro 许可证验证和捐赠提醒
- ✅ 更新检查指向本项目仓库
- ✅ 独立设置窗口（替代 Popover）
- ✅ 布局管理优化
- ✅ 帮助界面改造，功能说明分散到各设置区域
- ✅ 帮助按钮改用原生 NSAlert，修复无反应问题
- ✅ 更新下载状态可视化（检查中/下载中/下载失败）
- ✅ 启动时自动检查并静默下载更新

## 安装

从 [Releases](https://github.com/jiezhengj/MacsyZones/releases) 下载最新版本 DMG 文件。

### 首次运行

应用使用 Apple Development 证书签名，首次运行时可能会提示"无法验证开发者"。请在 **系统设置 → 隐私与安全性** 中点击"仍要打开"。

## 从源码构建

```bash
git clone https://github.com/jiezhengj/MacsyZones.git
cd MacsyZones
open MacsyZones.xcodeproj
# Cmd + R 运行，或 Product → Archive 打包
```

正式签名、版本检查、DMG 构建和 GitHub Release 流程见 [`BUILD.md`](BUILD.md)。

## 许可证

[GNU General Public License v3.0](LICENSE)

原始项目 Copyright (C) 2024, Oğuzhan Eroğlu

## 致谢

- [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) - 原始项目
