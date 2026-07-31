# MacsyZones 项目维护指南

## 项目概述

这是 MacsyZones 的自定义版本，移除了所有 Pro 许可证验证和捐赠提醒功能。

**上游仓库**: https://github.com/rohanrhu/MacsyZones（仅用于同步更新，永远不会向上游推送代码或提交 PR）
**本项目仓库**: https://github.com/jiezhengj/MacsyZones（所有推送操作的目标）

## ⚠️ 重要规则

1. **永远不会向上游项目推送代码或提交 PR**
2. **当用户说"推送 GitHub"时，一定仅指推送到本项目自己的仓库 `jiezhengj/MacsyZones`**
3. 上游仓库仅用于拉取更新，是单向同步关系
4. **代码复用优先**：添加或修改功能时，必须先检查上游项目是否已有实现

---

## 代码复用原则

### 核心理念

本项目是上游项目的改造版本，**必须优先复用上游代码**，而非自行重写。

### 为什么必须复用

1. **保持功能一致性**：避免丢失上游的错误处理、边界检查、用户体验细节
2. **便于同步更新**：复用上游代码可以减少 rebase 时的冲突
3. **减少维护成本**：上游的实现经过测试和验证
4. **避免功能退化**：自行重写可能丢失上游的重要细节（如重名检查、参数验证等）

### 复用优先级

1. **上游已有实现** → 复用上游代码，仅做必要的汉化和适配
2. **上游无实现** → 自行编写新功能
3. **上游实现不适用** → 必须说明原因，再自行编写

### 检查流程

在添加或修改功能前，**必须执行以下检查**：

```bash
# 1. 查看上游项目中的相关文件
git show upstream/main:MacsyZones/<文件名>.swift

# 2. 搜索相关功能关键词
git show upstream/main:MacsyZones/<文件名>.swift | grep -A <行数> "<关键词>"

# 3. 如果找到上游实现，复制并汉化
# 4. 如果未找到，再自行编写
```

### 示例：正确做法 vs 错误做法

**❌ 错误做法**：直接自己写
```
发现按钮无反应 → 自己写一个新视图 → 丢失上游的重名检查、参数验证等功能
```

**✅ 正确做法**：先查上游
```
发现按钮无反应 → 检查上游 Popover.swift → 找到 RenameView/DuplicateView/NewView → 复用并汉化
```

### 特殊情况处理

以下情况可以自行编写：
- 上游确实没有该功能
- 上游实现有明确的 bug 或缺陷
- 上游实现与本项目架构不兼容（需说明原因）

---

## 测试原则

### 核心理念

在请求用户测试前，**必须先进行我能做的测试**，尽可能减少用户的测试负担。

### Build 前测试

1. **语法检查**：
   ```bash
   xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones -configuration Debug build 2>&1 | tail -20
   ```

2. **代码逻辑验证**：
   - 检查视图绑定是否正确（`@Binding`、`@State`、`@ObservedObject`）
   - 验证函数调用链是否完整
   - 确认条件判断逻辑正确（如按钮禁用条件）
   - 检查数据流是否正确（输入 → 处理 → 输出）

3. **文件完整性检查**：
   - 验证所有修改的文件语法正确
   - 确认没有遗漏的导入或类型引用
   - 检查新增/删除的文件是否与项目结构一致

### Build 后测试

1. **运行应用并检查日志**：
   ```bash
   # 运行应用并查看输出
   /path/to/MacsyZones.app/Contents/MacOS/MacsyZones 2>&1
   ```

2. **检查控制台输出**：
   - 是否有运行时错误
   - 是否有警告信息
   - 是否有预期的调试日志

3. **自动化验证**：
   - 检查文件是否正确写入（如配置文件）
   - 验证状态变更是否生效
   - 确认资源是否正确加载

### 我无法测试的内容

- UI 交互测试（点击按钮、查看对话框）
- 视觉效果检查（布局、字体、颜色、动画）
- 用户体验验证（响应速度、操作流畅度）
- 多显示器场景测试
- 不同 macOS 版本兼容性

### 测试报告格式

在请求用户测试前，应提供：
```
✅ 已完成的测试：
- [x] 构建成功，无编译错误
- [x] 代码逻辑验证通过
- [x] 运行时无崩溃
- [x] 日志输出正常

⚠️ 需要用户验证：
- [ ] 点击按钮是否弹出对话框
- [ ] 对话框功能是否正常
- [ ] 视觉效果是否符合预期
```

---

## 版本号规则

### 独立版本号体系

**重要**：本项目作为 fork，**不继承上游项目的版本号**，而是从 **v1.0.0** 开始独立演进。

### 语义化版本（Semantic Versioning）

版本号格式：**x.y.z**（例如 1.2.3）

| 版本号 | 含义 | 何时递增 | 示例 |
|--------|------|----------|------|
| **x** (Major) | 主版本号 | 重大更新、不兼容的 API 变更、架构重构 | 1.0.0 → 2.0.0 |
| **y** (Minor) | 次版本号 | 新功能添加（向后兼容） | 1.0.0 → 1.1.0 |
| **z** (Patch) | 补丁号 | Bug 修复、小改进（向后兼容） | 1.0.0 → 1.0.1 |

### 递增规则

1. **主版本号 (x)**
   - 重大架构变更
   - 不兼容的 API 变更
   - 大规模功能重写
   - 重大的 UI 设计变更

2. **次版本号 (y)**
   - 新增功能
   - 新增 UI 组件
   - 性能优化
   - 新的配置选项

3. **补丁号 (z)**
   - Bug 修复
   - 文档更新
   - 小的 UI 调整
   - 代码重构（不影响功能）

### 本项目的版本号示例

```
1.0.0 → 1.0.1：修复了一个 bug
1.0.1 → 1.1.0：添加了新功能（如快捷键自定义）
1.1.0 → 2.0.0：重大架构变更（如从 SwiftUI 迁移到 AppKit）
```

### 上游版本号映射

本项目需要记录与上游版本号的对应关系，便于同步更新时参考：

| 本项目版本 | 上游版本 | 说明 |
|------------|----------|------|
| v1.0.0 | v3.0.4 | 初始版本，基于上游 v3.0.4 改造 |

**映射记录原则**：
- 每次从上游同步更新后，在上表中记录新的映射关系
- 便于追踪上游版本变化和改造基础

---

## Release 规范

### Release 标题格式

**固定格式**：`MacsyZones 中文定制版 vx.y.z`

- ❌ 禁止在标题后添加 ` - 修复XXX` 等描述性后缀
- ✅ 示例：`MacsyZones 中文定制版 v1.2.3`

### Release 正文模板

**必须使用以下精确格式**，不可随意增删分隔线或修改结构：

```markdown
## vx.y.z 更新内容

### <分类标题>
- <具体内容>
- <具体内容>

---

**上游版本映射**：本版本基于上游 vX.Y.Z 改造

---

🙏 感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！
```

### 正文规则

1. **一级标题**：`## vx.y.z 更新内容`（如 `## v1.2.3 更新内容`）
2. **分类标题**：使用 `###` 开头，常见分类：
   - `### Bug 修复`
   - `### 新功能`
   - `### UI 优化`
   - `### 代码清理`
   - `### 改造内容`
3. **分项列表**：使用 `- ` 开头，每项一行
4. **分隔线**：使用 `---` 分隔三个区块（更新内容 / 上游映射 / 致谢）
5. **上游映射**：`**上游版本映射**：本版本基于上游 vX.Y.Z 改造`
6. **致谢**：`🙏 感谢原作者 [Oğuzhan Eroğlu](https://meowingcat.io/) 的杰出工作！`

### 措辞规范

- ✅ 推荐：感谢原作者的杰出工作
- ❌ 避免：购买正版、支持开发者（显得像在做盗版）

### 创建 Release 的完整流程

**每次发布 Release 必须执行以下全部步骤**，不可跳过：

**步骤 1：更新版本号**
```bash
sed -i '' 's/MARKETING_VERSION = .*/MARKETING_VERSION = x.y.z;/g' MacsyZones.xcodeproj/project.pbxproj
```

**步骤 2：构建 Release 版本**
```bash
xcodebuild -project MacsyZones.xcodeproj -scheme MacsyZones -configuration Release -derivedDataPath build clean build
```

**步骤 3：验证签名**
```bash
codesign -dv --verbose=4 build/Build/Products/Release/MacsyZones.app 2>&1 | grep -E "CDHash|Signature|Identifier|Authority"
```
必须确认：
- `Signature=Apple Development`
- `Identifier=MeowingCat.MacsyZones`
- `Authority=Apple Development: jie.zhengj@gmail.com (8SDSF987N2)`

**步骤 4：创建 DMG**
```bash
mkdir -p /tmp/MacsyZones-dmg
cp -R build/Build/Products/Release/MacsyZones.app /tmp/MacsyZones-dmg/
ln -sf /Applications /tmp/MacsyZones-dmg/Applications
hdiutil create -volname "MacsyZones" -srcfolder /tmp/MacsyZones-dmg -ov -format UDZO MacsyZones-vx.y.z.dmg
rm -rf /tmp/MacsyZones-dmg
```
- DMG 文件名格式：`MacsyZones-vx.y.z.dmg`（如 `MacsyZones-v1.2.3.dmg`）

**步骤 5：提交代码并推送**
```bash
git add MacsyZones/SettingsView.swift MacsyZones.xcodeproj/project.pbxproj MacsyZones-vx.y.z.dmg
git commit -m "<提交信息>"
git push origin custom
```

**步骤 6：创建 tag 并推送**
```bash
git tag -a vx.y.z -m "vx.y.z: <简要描述>"
git push origin vx.y.z
```

**步骤 7：创建 GitHub Release 并上传 DMG**
```bash
# 创建 release
gh release create vx.y.z \
  --repo jiezhengj/MacsyZones \
  --title "MacsyZones 中文定制版 vx.y.z" \
  --notes "## vx.y.z 更新内容
...
"

# 上传 DMG
gh release upload vx.y.z MacsyZones-vx.y.z.dmg --repo jiezhengj/MacsyZones --clobber
```

### DMG 文件必须纳入 Git 版本管理

- DMG 文件**必须** `git add` 并提交到仓库
- 旧版本 DMG **必须** `git rm` 删除
- 每次发布后，仓库中包含且仅包含当前版本的 DMG 文件

---

## 版本号管理

### 重要：构建前必须更新版本号

**问题**：Xcode 项目中的 `MARKETING_VERSION` 默认是 `1.0`，如果不手动更新，每次构建出来的 app 版本号都是 `1.0`，导致更新功能陷入无限循环。

**解决**：每次发布新版本前，必须更新以下位置的版本号：

1. **Xcode 项目**：`MacsyZones.xcodeproj/project.pbxproj` 中的 `MARKETING_VERSION`

```bash
# 查看当前版本
grep "MARKETING_VERSION" MacsyZones.xcodeproj/project.pbxproj

# 更新版本号（替换 x.y.z 为新版本）
sed -i '' 's/MARKETING_VERSION = .*/MARKETING_VERSION = x.y.z;/g' MacsyZones.xcodeproj/project.pbxproj
```

2. **关于界面**：版本号会自动从 Info.plist 读取，无需手动更新

---

## 问题1：如何同步上游更新而不重复改造

### 分支策略

```
custom   ← 默认分支，你的改造版本
upstream ← 上游仓库（rohanrhu/MacsyZones），仅用于拉取更新
```

### 当前状态

- **默认分支**: `custom`
- **上游仓库**: `rohanrhu/MacsyZones`（只读，永不推送）
- **本项目仓库**: `jiezhengj/MacsyZones`（所有推送的目标）

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
- `SettingsView.swift` - 集成布局管理 UI（原 Popover.swift 功能）

**注意**：上游的 `Popover.swift` 已被删除，其功能已迁移至 `SettingsView.swift`。同步时需检查上游 `Popover.swift` 的新增功能是否需要迁移到 `SettingsView.swift`。

**冲突解决原则**：
1. 保留上游的新功能和bug修复
2. 重新应用移除 Pro/捐赠的改造
3. 如果上游新增了 Pro 相关功能，一并移除
4. 上游 `Popover.swift` 的功能变更需同步到 `SettingsView.swift`

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
- `SettingsView.swift` - 集成布局管理 UI（替代原 Popover.swift）

### 删除的文件（改造过程中）
- `Popover.swift` - 原 UI 组件，功能已迁移至 SettingsView.swift

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
