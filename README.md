# MacsyZones

[![GitHub release](https://img.shields.io/github/release/jiezhengj/MacsyZones.svg?style=flat-square&color=informational)](https://github.com/jiezhengj/MacsyZones/releases)
[![GitHub stars](https://img.shields.io/github/stars/jiezhengj/MacsyZones?style=flat-square)](https://github.com/jiezhengj/MacsyZones/stargazers)

**MacsyZones** 是一款 macOS 窗口管理工具，让您的工作流程更加高效，轻松组织和管理窗口布局。

> 🙏 **致谢**：本项目基于 [rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones) 进行二次开发，感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！

| ![MacsyZones](media/MacsyZonesAppIcon.png) | MacsyZones 是 macOS 上的 FancyZones 替代品。您可以自由创建布局和区域，并轻松将窗口适配到各个区域中。 |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

<img width="1728" height="1760" alt="MacsyZones 设置界面" src="https://github.com/user-attachments/assets/54385d2e-7d97-4d85-8aab-a9681cea8b70" />

## 功能演示

https://github.com/user-attachments/assets/f197dfa9-ef54-4a7d-b6af-630a0f0d2cac

https://github.com/user-attachments/assets/101d3296-889f-4cfb-93cf-87bad548a108

## ✨ 主要功能

- 🪟 **窗口布局管理** - 创建自定义窗口布局，自由定义区域
- ⌨️ **快捷键支持** - 使用快捷键快速吸附窗口到指定区域
- 🖱️ **鼠标操作** - 拖拽窗口时自动显示可吸附区域
- 🔄 **窗口循环** - 在同一区域内快速切换多个窗口
- 📐 **吸附调整** - 精确调整窗口大小以匹配区域
- 🖥️ **多显示器支持** - 为每个屏幕和工作区设置不同布局
- 🎨 **网格布局** - 支持网格类型的快速布局

## 📦 安装方式

### 从 GitHub Releases 下载

前往 [Releases](https://github.com/jiezhengj/MacsyZones/releases) 页面下载最新版本。

### 使用 Homebrew（需自行添加 tap）

```sh
# 如果你将项目发布为 Homebrew tap
brew install --cask jiezhengj/tap/macsyzones
```

## 🛠️ 从源码构建

### 环境要求

- macOS 11.5 或更高版本
- Xcode 13 或更高版本

### 构建步骤

1. 克隆仓库
   ```bash
   git clone https://github.com/jiezhengj/MacsyZones.git
   cd MacsyZones
   ```

2. 用 Xcode 打开项目
   ```bash
   open MacsyZones.xcodeproj
   ```

3. 构建运行
   - 按 `Cmd + R` 运行
   - 或 `Product → Archive` 打包

## ⚙️ 使用说明

### 基本操作

1. **启动应用** - 运行后会在菜单栏显示图标
2. **创建布局** - 点击菜单栏图标，选择"新建布局"
3. **设计区域** - 在布局编辑器中拖拽创建窗口区域
4. **吸附窗口** - 按住修饰键（默认 Control）拖拽窗口到区域

### 快捷键

| 功能 | 默认快捷键 |
|------|-----------|
| 显示布局 | 按住 Control 键 |
| 吸附键 | 按住 Shift 键 |
| 快速吸附 | Control + Shift + S |
| 向前循环窗口 | Command + ] |
| 向后循环窗口 | Command + [ |

## 📋 与原版的区别

本版本在原版基础上进行了以下修改：

- ✅ 移除了 Pro 许可证验证系统
- ✅ 移除了捐赠提醒弹窗
- ✅ 移除了购买相关界面
- ✅ 移除了 Layout Switcher 功能
- ✅ 界面完全中文化
- ✅ 更新检查指向本项目仓库

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目基于 [GNU General Public License v3.0](LICENSE) 许可证发布。

### 原始项目许可

原始项目 MacsyZones 由 [Oğuzhan Eroğlu](https://meowingcat.io/) 开发，同样采用 GPL-3.0 许可证。

Copyright (C) 2024, Oğuzhan Eroğlu <rohanrhu2@gmail.com>

## 🙏 致谢

- **[rohanrhu/MacsyZones](https://github.com/rohanrhu/MacsyZones)** - 原始项目，感谢原作者的无私分享
- **[Oğuzhan Eroğlu](https://meowingcat.io/)** - MacsyZones 的创造者
- 所有为原项目做出贡献的开发者们

## 🔗 相关链接

- 原项目：https://github.com/rohanrhu/MacsyZones
- 原项目官网：https://macsyzones.com
- 本项目：https://github.com/jiezhengj/MacsyZones
