# MacsyZones 中文定制版

[![GitHub release](https://img.shields.io/github/release/jiezhengj/MacsyZones.svg?style=flat-square&color=informational)](https://github.com/jiezhengj/MacsyZones/releases)

基于 [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) 二次开发的 macOS 窗口管理工具中文定制版。

> ⚠️ **声明**：本项目仅为个人自用，不对外分发。

> 🙏 感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！

## 版本映射

| 本项目版本 | 上游版本 | 说明 |
|-----------|---------|------|
| v1.0.0 | v3.0.4 | 首个中文定制版，基于上游最新版本 |
| v1.1.0 | v3.0.4 | 汉化、功能整合与 UI 优化 |
| v1.2.0 | v3.0.4 | 帮助界面改造，功能说明分散到各设置区域 |

## 改造内容

- ✅ 界面完全中文化
- ✅ 更新检查指向本项目仓库
- ✅ 独立设置窗口（替代 Popover）
- ✅ 布局管理优化
- ✅ 帮助界面改造，功能说明分散到各设置区域

## 安装

从 [Releases](https://github.com/jiezhengj/MacsyZones/releases) 下载最新版本。

### 首次运行

应用使用 ad-hoc 签名，首次运行时可能会提示"无法验证开发者"。请在 **系统设置 → 隐私与安全性** 中点击"仍要打开"。

## 从源码构建

```bash
git clone https://github.com/jiezhengj/MacsyZones.git
cd MacsyZones
open MacsyZones.xcodeproj
# Cmd + R 运行，或 Product → Archive 打包
```

## 许可证

[GNU General Public License v3.0](LICENSE)

原始项目 Copyright (C) 2024, Oğuzhan Eroğlu

## 致谢

- [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) - 原始项目
