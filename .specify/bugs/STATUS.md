# Bug 状态台账

本文件记录 `.specify/bugs/<slug>/` 下各缺陷的当前状态。缺陷的诊断、修复与验证分别见各自目录的 `assessment.md`、`fix.md`、`test.md`。

| Slug | 状态 | 关闭日期 | 关闭版本 | 说明 |
| --- | --- | --- | --- | --- |
| layout-size-1px-truncation | 已关闭 | 2026-11-22 | v2.1.1 | 取整修复已发布；算术复现与回归脚本通过，点击级目视验收由人确认，若复现则重开 |
| layout-settings-actions-wrong-layout | 已关闭 | 2026-11-22 | v2.1.1 | 统一选中布局修复已发布；静态回归与构建通过，点击级目视验收由人确认，若复现则重开 |
| editor-window-wrong-screen | 已修复待发布 | — | — | 编辑层按设置选中的显示器摆放；原症状已按复现步骤验证消失，跨屏拖拽提示待人工确认；等待下个版本发布后关闭 |

## 关闭规则

- 修复已随某个 GitHub Release 交付，且 `test.md` 记录的检查已完成（允许 `partial`：仅点击级人工验收未执行时，需在关闭说明里写明）。
- 关闭不删除目录，保留 `assessment.md` / `fix.md` / `test.md` 作为证据。
- 人工验收发现仍可复现时，把状态改回「重开」，并按 `/speckit-bug-assess` 补充新证据，不要直接改代码。
