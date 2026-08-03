# MacsyZones 项目指令

本文件只作为 Claude Code 的入口，不复制一份独立的项目规则。

开始任何任务前，必须阅读并遵守 [`AGENTS.md`](AGENTS.md)。长期有效的规则来源如下：

- [`AGENTS.md`](AGENTS.md)：工作范围、上游代码复用、测试、分支和发布执行约束。
- [`VERSIONING.md`](VERSIONING.md)：版本级别判定、版本递增算法和新 Release/资产修复边界。
- [`RELEASES.md`](RELEASES.md)：本项目自己的版本台账、当前已发布版本和下一发布目标。
- [`BUILD.md`](BUILD.md)：Apple Development 签名、构建、DMG 和 GitHub Release 操作。
- [`README.md`](README.md)：面向用户的功能和版本说明。

关键约束：

1. 永远不向 `rohanrhu/MacsyZones` 推送代码或提交 PR；所有 GitHub 推送只针对 `jiezhengj/MacsyZones`。
2. 修改功能前先检查 `upstream/main` 是否已有实现，优先复用上游代码。
3. 请求用户测试前先完成本地可执行的测试、构建和签名检查。
4. 新代码 Release 必须先完成版本级别判定，并通过 `scripts/check-version.sh <version> <major|minor|patch>`；不能沿用旧版本号。
5. 阶段性设计和实施过程文档已删除，不能作为版本、Release 或 Goal 状态的依据。

默认使用中文交流和编写文档。
