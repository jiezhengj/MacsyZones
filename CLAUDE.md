# MacsyZones 项目指令

## 项目概述

MacsyZones 是 macOS 窗口管理应用，此版本移除了所有商业限制（Pro 许可证、捐赠提醒）。

**当前状态**: 自定义版本，仅供个人使用
**上游仓库**: https://github.com/rohanrhu/MacsyZones（仅用于同步更新）
**本项目仓库**: https://github.com/jiezhengj/MacsyZones

## ⚠️ 核心规则

1. **永远不会向上游项目推送代码或提交 PR**
2. **当用户说"推送 GitHub"时，一定仅指推送到本项目自己的仓库 `jiezhengj/MacsyZones`**
3. 上游仓库仅用于拉取更新，是单向同步关系

---

## 开发语言

**默认使用中文**进行交流和文档编写。

---

## 核心改造

### 已移除的功能
- Pro 许可证验证系统
- 捐赠提醒弹窗
- 所有购买相关 UI

### 涉及的文件
- `App.swift` - 全局实例移除
- `States.swift` - 触发点移除
- `Popover.swift` - UI 组件移除

---

## 配置管理

### 配置存储位置
```
~/Library/Application Support/MeowingCat.MacsyZones/
```

### 关键配置文件
- `UserLayouts.json` - 用户自定义布局
- `AppSettings.json` - 应用设置

### 配置保留原则
- `bundleIdentifier` 必须保持为 `MeowingCat.MacsyZones`
- 替换 app 时配置自动保留
- 无需手动迁移配置

---

## 更新同步策略

### 分支结构
```
custom   ← 默认分支，自定义改造版本
upstream ← 上游仓库（rohanrhu/MacsyZones），仅用于拉取更新
```

### 同步流程
1. `git fetch upstream` - 获取上游更新
2. `git checkout main && git pull upstream main` - 更新 main 分支
3. `git checkout custom && git rebase main` - 应用改造到新版本
4. 解决冲突（如有）
5. 构建并替换 app

### 冲突解决原则
- 保留上游新功能和 bug 修复
- 重新应用移除 Pro/捐赠的改造
- 检查上游是否新增 Pro 相关功能，一并移除

---

## 构建与部署

### 构建步骤
1. 用 Xcode 打开 `MacsyZones.xcodeproj`
2. `Product → Archive`
3. 导出 App 文件

### 部署步骤
1. 退出当前 MacsyZones
2. 替换 `/Applications/MacsyZones.app`
3. 重新启动

---

## 注意事项

### 不要修改的内容
- 保持 `bundleIdentifier` 为 `MeowingCat.MacsyZones`
- 不要删除用户配置文件
- 不要修改配置存储路径

### 可以修改的内容
- 移除新增的商业限制功能
- 自定义 UI 和快捷键
- 添加个人需要的功能

---

## 相关文档

- [AGENTS.md](AGENTS.md) - 详细维护指南
- [README.md](README.md) - 原始项目说明
