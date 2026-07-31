# MacsyZones 项目维护指南

## 项目概述

这是 MacsyZones 的自定义版本，移除了所有 Pro 许可证验证和捐赠提醒功能。

**上游仓库**: https://github.com/rohanrhu/MacsyZones
**自定义版本**: 移除商业限制，仅供个人使用

---

## 问题1：如何同步上游更新而不重复改造

### 分支策略

```
main     ← 跟踪上游仓库，保持原始代码
custom   ← 你的改造版本，基于 main
```

### 首次设置（只需做一次）

```bash
# 1. 添加上游仓库
git remote add upstream https://github.com/rohanrhu/MacsyZones.git
git fetch upstream

# 2. 创建 custom 分支保存改造
git checkout -b custom
git add .
git commit -m "Remove Pro/Donation restrictions"

# 3. 确保 main 分支跟踪上游
git checkout main
git branch -u upstream/main
```

### 同步上游更新（每次需要更新时执行）

```bash
# 方法1：使用同步脚本
./sync-upstream.sh

# 方法2：手动执行
git checkout main
git pull upstream main        # 拉取上游最新代码
git checkout custom
git rebase main               # 将改造应用到最新代码上

# 如果有冲突，解决冲突后：
git add <resolved-files>
git rebase --continue
```

### 冲突解决指南

改造涉及的文件：
- `App.swift` - 移除 `macsyProLock` 和 `donationReminder` 实例
- `States.swift` - 移除 `donationReminder.count()` 调用
- `Popover.swift` - 移除 Pro UI 组件

**冲突解决原则**：
1. 保留上游的新功能和bug修复
2. 重新应用移除 Pro/捐赠的改造
3. 如果上游新增了 Pro 相关功能，一并移除

---

## 问题2：如何保留用户配置

### 配置存储位置

```
~/Library/Application Support/MeowingCat.MacsyZones/
```

### 配置文件清单

| 文件 | 内容 | 重要性 |
|------|------|--------|
| `UserLayouts.json` | 自定义窗口布局 | ⭐⭐⭐ 核心配置 |
| `AppSettings.json` | 应用设置（快捷键、行为等） | ⭐⭐⭐ 核心配置 |
| `SpaceLayoutPreferences.json` | 桌面布局偏好 | ⭐⭐ 重要 |
| `UpdateState.json` | 更新状态 | ⭐ 可重建 |

### 替换 App 时的配置保留

**关键原则**：只要 `bundleIdentifier` 保持不变，配置就会自动保留。

当前 `bundleIdentifier`: `MeowingCat.MacsyZones`

**安全替换步骤**：
1. 构建你的改造版本（Xcode → Product → Archive）
2. 导出 App 文件
3. 退出当前运行的 MacsyZones
4. 直接替换 `/Applications/MacsyZones.app`
5. 重新启动 app

**验证配置保留**：
```bash
# 检查配置文件是否存在
ls -la ~/Library/Application\ Support/MeowingCat.MacsyZones/
```

### 备份建议

在替换前备份配置：
```bash
cp -r ~/Library/Application\ Support/MeowingCat.MacsyZones ~/Desktop/MacsyZones-backup
```

---

## 已移除的组件

### 删除的文件
- `ProLock.swift` - Pro 许可证验证系统
- `PubKey.swift` - 许可证签名公钥
- `DonationReminder.swift` - 捐赠提醒弹窗

### 修改的文件
- `App.swift` - 移除全局实例
- `States.swift` - 移除触发点
- `Popover.swift` - 移除 UI 组件

---

## 快速参考

### 日常工作流程

```bash
# 检查上游更新
git fetch upstream
git log main..upstream/main --oneline

# 同步更新
./sync-upstream.sh

# 构建并替换
# Xcode → Product → Archive → 导出 → 替换 /Applications/
```

### 紧急回滚

如果新版本有问题：
```bash
# 回滚到上一个 custom 版本
git checkout custom
git log --oneline  # 找到上一个好的提交
git reset --hard <commit-hash>
# 重新构建
```

---

## 相关文档

- [README.md](README.md) - 原始项目说明
- [CONTRIBUTING.md](CONTRIBUTING.md) - 贡献指南
- [LICENSE](LICENSE) - GPL-3.0 许可证
