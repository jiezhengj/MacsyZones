<!--
Sync Impact Report:
- Version change: Initial Template -> 1.0.0
- Modified principles: Replaced all placeholders with MacsyZones project-specific core principles
  - 原则一：上游代码复用优先 (Upstream Reuse First)
  - 原则二：单向同步与主权仓库隔离 (One-Way Sync & Sovereign Upstream Boundary)
  - 原则三：严谨的本地自测与正式签名审计 (Strict Pre-Verification & Formal Code Signing)
  - 原则四：量化版本决策与门禁约束 (Quantitative Versioning & Release Gate)
  - 原则五：配置持久化与平滑迁移 (Configuration Persistence & Stability)
- Added sections: 额外约束与架构标准, 治理与修订程序
- Removed sections: 无
- Follow-up TODOs: 无
- Version change: 1.0.0 -> 1.0.1（PATCH）
- 2026-11-21：移除「规则文档双向同步（`AGENTS.md` ≡ `CLAUDE.md`）」条款。`CLAUDE.md` 已于 2026-09-29 的 `9d51733` 主动删除并合并进 `AGENTS.md`，原条款成为无法履行的悬空要求；项目规则改由 `AGENTS.md` 作为唯一权威来源，不再维护重复副本。
-->

# MacsyZones 项目章程

## 核心原则

### 原则一：上游代码复用优先 (Upstream Reuse First)
在添加或修改功能时，必须先检查上游项目（rohanrhu/MacsyZones）是否已有成熟实现。若上游已有实现，必须优先复用并仅做必要的汉化与无 Pro / macOS 27 适配，严禁自行重新编写相同功能的逻辑。这有助于保持功能一致性、避免边界条件处理缺失并大幅降低代码同步时的冲突。

### 原则二：单向同步与主权仓库隔离 (One-Way Sync & Sovereign Upstream Boundary)
上游仓库仅作为拉取更新与代码复用的只读基线，严禁向上游项目推送代码、创建分支或提交 PR。当提及推送 GitHub 时，目标一定且仅为本项目自有仓库 `jiezhengj/MacsyZones`。

### 原则三：严谨的本地自测与正式签名审计 (Strict Pre-Verification & Formal Code Signing)
在请求用户测试前，开发者与 Agent 必须完成所有可本地验证的检查（编译构建、代码逻辑验证、静态分析、运行时无崩溃及日志输出）。严禁使用临时 Bundle ID 或未签名的二进制包。构建产物必须严格满足正式签名审计要求：
- Bundle Identifier: `MeowingCat.MacsyZones`
- Team Identifier: `74FR87HYTH`
- Authority: `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`

### 原则四：量化版本决策与门禁约束 (Quantitative Versioning & Release Gate)
版本级别（Major/Minor/Patch）必须依据完整需求范围严格遵循 `VERSIONING.md` 与 `RELEASES.md` 进行量化判定，不得仅按最后一个 Commit 推断。修改版本后必须执行 `scripts/check-version.sh <version> <level>` 门禁检查。DMG 安装包全程在 `/tmp` 目录生成并在发布后删除，严禁纳入 Git 仓库管理。

### 原则五：配置持久化与平滑迁移 (Configuration Persistence & Stability)
应用必须确保 `~/Library/Application Support/MeowingCat.MacsyZones/` 目录下的用户布局（UserLayouts.json）与设置（AppSettings.json）在版本迭代中稳定保留与兼容。代码中禁止对配置解析与重排执行可能导致崩溃的强制解包（Force Unwrapping），所有数据持久化操作必须具备安全的异常容错逻辑。

## 额外约束与架构标准

- **系统基线要求**：最低部署系统明确为 macOS 27.0，彻底移除历史 macOS 版本的条件编译分支。
- **窗口惰性物化**：常驻运行内存需维持在轻量区间，窗口采用按需惰性物化（Lazy Materialization），未激活布局不得常驻物理图形树。
- **并发与主线程调度**：所有 AppKit 窗口代理与 UI 状态属性的变更派发必须置于主线程或下一 RunLoop，杜绝约束重入崩溃。
- **规则文档单一来源**：项目规则以根目录 `AGENTS.md` 为唯一权威来源，不维护重复副本；规则更新只改 `AGENTS.md` 及其指向的专门文档（`VERSIONING.md`、`RELEASES.md`、`BUILD.md`）。

## 治理与修订程序

- **效力层级**：本章程为 MacsyZones 项目的根本工程规范，规范化开发中的所有 Specification、Plan、Tasks 及实施代码均必须符合本章程规定。
- **版本演进**：章程版本遵循语义化版本规则：
  - MAJOR：核心原则的删除、重新定义或重大治理方向逆转。
  - MINOR：新增原则、新增架构标准或重大指导扩充。
  - PATCH：文字澄清、格式优化、非语义性修正。
- **审查机制**：任何对本章程的修改必须记录变更原因，并在文件顶部保留同步影响报告（Sync Impact Report）。

**Version**: 1.0.1 | **Ratified**: 2026-09-26 | **Last Amended**: 2026-11-21
