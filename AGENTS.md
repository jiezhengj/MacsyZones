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

### 长期有效文档的权威层级

- `VERSIONING.md`：版本级别判定、版本递增算法和发布/资产修复边界。
- `RELEASES.md`：本项目自己的已发布版本和上游基线（不登记尚未发布的版本）。
- `BUILD.md`：签名、构建、DMG 和 GitHub Release 的操作细节。
- `README.md`：面向用户的功能和版本说明。

阶段性设计和实施过程文档已删除；它们不是版本号、Goal 状态或 Release 规则的依据。

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
   scripts/build-debug.sh
   ```

   该脚本固定使用 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`、Team ID `74FR87HYTH` 和 Bundle ID `MeowingCat.MacsyZones`，并在构建后执行签名审计。权限测试不得使用临时 Bundle ID 或 UI Harness。

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
   # 仅运行已通过正式签名审计的安装版本
   scripts/verify-signing.sh /Applications/MacsyZones.app
   /Applications/MacsyZones.app/Contents/MacOS/MacsyZones 2>&1
   ```

   不要直接运行临时目录中的 UI Harness 或自定义 Bundle ID 构建；macOS 会把它们当作新的辅助功能 TCC 客户端，导致重复授权提示。

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

版本号规则、Major/Minor/Patch 的量化判定和本项目当前版本台账统一见 [`VERSIONING.md`](VERSIONING.md) 与 [`RELEASES.md`](RELEASES.md)。

必须遵守以下硬规则：

1. 版本级别按完整 Goal/发布范围判定，不按最后一个 commit 判定。
2. 多种变更同时存在时采用最高级别：`Major > Minor > Patch`。
3. 跨越两个以上核心域并重构职责边界、持久化迁移、核心 UI、更新器或签名发布边界时，至少是 Major。
4. 不预设下一个版本：版本号与级别只在创建 Release 之前，按本次发布范围内的实际变更判定，不在 `RELEASES.md` 或任何文档中提前登记下一版本的性质或版本号。
5. 修改 `MARKETING_VERSION` 后，必须先执行：

   ```bash
   scripts/check-version.sh <target-version> <major|minor|patch>
   ```

6. 版本检查未通过时，不得构建 Release、创建 tag 或上传 GitHub Release。

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

**步骤 1：判定版本决策并更新版本号**

按本次发布范围内的实际变更判定级别与版本号（规则见 [`VERSIONING.md`](VERSIONING.md)），再更新 Xcode 项目版本号；`RELEASES.md` 只在 Release 创建成功后记录，不提前登记下一版本。

```bash
targetVersion=<X.Y.Z>
bumpLevel=<major|minor|patch>
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = ${targetVersion};/g" MacsyZones.xcodeproj/project.pbxproj
scripts/check-version.sh "$targetVersion" "$bumpLevel"
```

**步骤 2：构建 Release 版本**
```bash
scripts/build-release-dmg.sh "$targetVersion" "$bumpLevel"
```

**步骤 3：验证签名**
```bash
# build-release-dmg.sh 已在创建 DMG 前自动完成正式签名审计。
# 如需复核已安装版本：
bash scripts/verify-signing.sh /Applications/MacsyZones.app
```
必须确认：
- `Authority=Apple Development: jie.zhengj@qq.com (8SDSF987N2)`
- 证书 SHA-1=`C7C84AAA3B67FACEA73042570A0BA2FC3D19E613`
- `Identifier=MeowingCat.MacsyZones`
- `TeamIdentifier=74FR87HYTH`

注：Xcode 27 的 `codesign -dv --verbose=4` 可能不再输出单独的 `Signature=Apple Development` 行，以完整的 `Authority`、`Identifier` 和 `TeamIdentifier` 为准。

**步骤 4：验证 DMG（在临时目录）**
```bash
hdiutil verify /tmp/MacsyZones-vx.y.z.dmg
```

`scripts/build-release-dmg.sh` 已在 `/tmp` 中完成 App 签名审计、DMG 创建和镜像信息校验。
- DMG 文件名格式：`MacsyZones-vx.y.z.dmg`（如 `MacsyZones-v1.2.3.dmg`）
- ⚠️ **DMG 必须创建在 `/tmp/` 目录，绝对不能放在项目文件夹里**

**步骤 5：提交代码并推送 `custom`**
```bash
git add <source-files> MacsyZones.xcodeproj/project.pbxproj RELEASES.md
git commit -m "<提交信息>"
git push origin custom
```
- ⚠️ **绝对不要 `git add` DMG 文件**，DMG 不属于 Git 版本管理

**步骤 6：创建 tag 并推送**
```bash
git tag -a vx.y.z -m "vx.y.z: <简要描述>"
git push origin vx.y.z
```

**步骤 7：创建 GitHub Release 并上传 DMG**
```bash
# 创建 release
gh release create "v${targetVersion}" \
  --repo jiezhengj/MacsyZones \
  --title "MacsyZones 中文定制版 v${targetVersion}" \
  --notes "## v${targetVersion} 更新内容
...
"

# 上传 DMG
gh release upload "v${targetVersion}" "/tmp/MacsyZones-v${targetVersion}.dmg" --repo jiezhengj/MacsyZones --clobber

# 上传完成后删除 DMG
rm -f "/tmp/MacsyZones-v${targetVersion}.dmg"
```

**步骤 8：发布后更新台账**

确认 GitHub Release 页面和 DMG 下载成功后，将 `RELEASES.md` 中的版本状态改为“已发布”，更新“当前已发布版本”，再提交并推送该文档变更。未创建 GitHub Release 的版本不得写入“已发布”。

如果 GitHub CLI 未登录、token 失效或 Release 资产无法验证，必须停止发布并报告阻塞，不能把本地 DMG 或 tag 当成已完成 Release。

### DMG 文件规则

- ⚠️ DMG 文件**绝对禁止**放在项目文件夹内
- ⚠️ DMG 文件**绝对禁止**纳入 Git 版本管理
- DMG 全程在 `/tmp/` 目录创建和使用
- Release 上传完成后**必须立即删除**本地 DMG 文件

---

## 版本号管理

`MARKETING_VERSION` 是 App 版本唯一构建来源；关于界面从 `Info.plist` 自动读取，不需要单独修改。

不要把“当前项目版本”“最近已发布版本”和“上游版本”混为一谈：

- 当前项目构建版本：以 `project.pbxproj` 为准。
- 最近已发布版本：以 `RELEASES.md` 为准；下一个版本不预先登记。
- 上游基线：只记录用于同步的上游版本，不参与本项目递增计算。
- 任何新代码 Release 都必须通过 `scripts/check-version.sh`；资产修复例外仅适用于同一代码、同一 tag 的 DMG 替换。

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

<!-- PROJECT-SPEC-KIT-GOVERNANCE:START -->
# Spec Kit 项目规则

## 项目规则和文件的权威来源

本项目使用官方 Spec Kit CLI、当前 Agent 的官方原生集成及其技能。此规则块与项目提交的 `.specify/**`、`specs/**` 和官方集成文件共同构成本项目的 Spec Kit 工作基线。目标项目 Agent 不需要也不得依赖个人全局规则或中央 Reference。

- `.specify/**` 和 Agent 集成文件由官方 CLI 管理；`specs/**` 中的流程产物由官方技能生成。不要重新初始化已有 `.specify/` 的项目，也不要手工覆盖 CLI 托管文件。
- 细节以本项目当前 CLI 的实际帮助和已安装官方技能为准。若它们与本规则存在差异，先说明受影响的步骤，再按当前工具实际支持的操作处理；不得臆造替代命令或以本地仿制品替代官方能力。

## Spec Kit 文档语言

- 本项目 Spec Kit 流程文档语言：中文。
- Constitution、Feature SDD、Bug Fix 和 Assessment 流程产生的新文档或实质性改写内容均使用中文；命令、路径、代码标识符、产品名和官方术语保留原文。
- 用户在单项任务中明确指定其他语言时，按该次要求处理；用户明确更改项目默认语言时，更新本规则。

## 每个新会话的入口

项目存在 `.specify/` 时，Agent 在首次实质性操作前只读取 `.agent-state/spec_kit_component_update_cache.json` 中的 `last_full_check`：

- 若 `status` 为 `success`，且 `checked_at_utc` 距当前不足 7×24 小时，Agent 不运行更新助手，直接开始用户任务。
- 若记录缺失、已过期、状态不是 `success`、时间在未来或无法解析，Agent 才运行更新助手：

~~~text
Windows：python .agent-support\spec_kit_component_updater.py
macOS/Linux：python3 .agent-support/spec_kit_component_updater.py
~~~

- 用户明确要求立即检查时，Agent 运行更新助手并加 `--recheck`。这会重新检查远端版本，不会强制覆盖文件。
- 更新助手只在整轮检查没有失败或未知状态时写入成功时间。发现 CLI 更新但需用户批准仍视为检查完成；Agent 本次会话说明候选版本。用户批准并完成 CLI 升级后，Agent 立即再运行一次助手以检查新 CLI 对应的组件。助手无法启动或退出非零时，Agent 说明原因。
- 若本机找不到 `specify`，Agent 询问用户是否从官方来源安装；用户拒绝时返回 `HANDOFF_TO_AGENT`。若 Python 低于 3.10 或更新助手缺失，Agent 说明检查未完成，不假称已检查。
- 更新助手的组件范围、官方来源校验、失败处理和 CLI 交互由脚本执行；Agent 按脚本报告处理需要用户决定的事项。
- 当前任务需要的官方集成或扩展缺失时，Agent 先询问用户是否安装；只使用当前 Agent 可用的官方原生集成，不改用 `generic`。Bug Fix 需要 `bug` 时，或用户选择 Assessment 且缺少 `assess` 时，Agent 询问是否运行对应的 `specify extension add` 命令。

## 选择工作流程

先按用户要达成的结果选择入口，不因任务发生在代码仓库中就自动启动 Feature SDD：

| 工作目标 | 采用的流程 |
| --- | --- |
| 问答、只读调查、代码审查、常规维护，或不改变预期技术行为的修改 | 不启动 Spec Kit 流程，按用户要求和项目规则处理。 |
| 用户尚未决定一个想法是否值得投入 | 可询问是否使用独立的 Assessment；它不实现代码，也不自动启动 Feature SDD。 |
| 已有行为违反既定预期 | 使用独立的 Bug Fix 流程；不要求先运行 Feature SDD 或 Constitution。 |
| 需要新增或明显改变预期技术能力、用户可观察行为 | 使用 Feature SDD；按下面的影响和风险标准选择短路径或完整路径。 |

若缺陷修复与新增行为可以拆开，分别处理。若不能拆开，先澄清交付目标和行为预期；不得把新增行为当作缺陷修复。

## Feature SDD：两种路径

每个项目在首次开始 Feature SDD 前建立一次 Constitution；它是两种路径共用的项目级前置步骤，不必为每个 Feature 重做。之后每个 Feature 选择以下一条路径：

| 路径 | 适用情况 | 每个 Feature 的步骤 |
| --- | --- | --- |
| 短路径 | 范围较小、需求清楚、风险低，且不改变外部接口、持久化数据格式、安全边界或核心架构。 | `specify → plan → tasks → implement → converge` |
| 完整路径 | 生产级功能，或影响 API、数据格式、架构、安全、隐私，涉及多个组件，或难以回退。 | `specify → clarify → plan → checklist → tasks → analyze → implement → converge` |

风险无法判断时先澄清；仍不确定时采用完整路径。每次只调用一个当前集成提供的官方技能，审阅该阶段结果后再继续。具体技能调用方式以当前 Agent 的原生集成为准。

## Bug Fix：诊断、修复、验证

当已有行为不符合明确的预期时，按 `assess → fix → test` 顺序使用官方 Bug Fix 技能，并在进入下一阶段前审阅当前产物。

- `assess` 记录症状、复现证据、预期行为、诊断和建议修复范围；此阶段不修改源代码。诊断没有证据支持或问题并非缺陷时，不进入 `fix`。
- `fix` 按已审阅的诊断实施修复并记录变更；这是此流程中实施源码修复的阶段。若新证据要求扩大范围，先说明并审阅偏差。
- `test` 重做原始复现并记录验证结果；此阶段不通过修改源代码来掩盖失败。仅测试套件通过、但没有重做原始复现，不足以证明缺陷已修复。

## Assessment：决定是否投入

当用户尚未决定一个想法是否值得投入、且选择了评估流程时，按 `intake → research → define → shape → decide` 顺序使用官方 Assessment 技能，并逐阶段审阅证据和产物。

Assessment 可以用于软件或非软件想法，不要求已有源代码，不修改源代码。`go`、`needs-clarification` 和 `kill` 都是有效结果；`go` 只表示可继续考虑，是否实施仍由用户决定。用户决定实现软件想法后，再把评估结论交给 Feature SDD；如项目尚未建立 Constitution，应在首次 Feature SDD 前建立。

## 共同执行边界

- Feature SDD、Bug Fix、Assessment 是三类不同工作入口；短路径和完整路径是 Feature SDD 内的两种模式。不得把三类入口串成一条强制流程。
- 按官方 CLI 安装需要的官方集成或扩展；每个阶段使用当前集成提供的官方技能。官方能力不可用时，说明缺失内容和受影响步骤，不安装本地替代品。
- 官方目录列出某个工作流不代表维护者审计了其 shell 内容。首次运行或更新后的首次运行前，Agent 必须检查 `.specify/workflows/<id>/workflow.yml` 中 shell 步骤的 `run` 字段；不得仅凭目录来源认定工作流安全。
- 不增加本地自建生命周期、工作流、预设、Bundle、额外 Discovery 阶段、审批台账或任务状态机。
- 不把未运行的 CLI 检查、技能或扩展报告为已完成；操作结果、阶段产物和验证证据须如实汇报。
<!-- PROJECT-SPEC-KIT-GOVERNANCE:END -->
