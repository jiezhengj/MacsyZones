# Bug Verification: 设置里的布局操作永远作用于当前活动布局

- **Slug**: layout-settings-actions-wrong-layout
- **Tested**: 2026-11-22
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

静态回归锁定了「下拉与四个按钮共用同一个布局名」：设置区不再出现 `renameCurrentLayout`/`removeCurrentLayout`/`duplicateCurrentLayout`，重命名/复制弹窗接收 `sourceLayoutName`，删除走 `removeLayout(named:)`，偏好同步覆盖持久化与设置窗口暂存两份状态。构建与安装通过；点击级端到端复现需要人工，见「Residual Risks」。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | grep 设置区是否仍调用 current 版 API | pass | 三个 API 在 `SettingsView.swift` 中零命中 |
| New / updated tests | `bash scripts/check_layout_selection.sh` | pass | `PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）` |
| Regression suite | `bash scripts/build-debug.sh` | pass | `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）` |
| Regression suite | `bash scripts/check_lazy_lifecycle.sh` | pass | 139 断言 PASS（布局增删改走同一套 stopEditing/物化路径） |
| Install & launch | `bash scripts/build-permission-artifact.sh` + `open -a` | pass | 正式版已替换为新构建，进程稳定，无崩溃报告 |
| Manual end-to-end | 设置 → 布局下拉选 `小屏` → 重命名/复制/删除 | not-run | 需要点击设置窗口，本机 GUI 自动化被 TCC 阻断 |

## Output Excerpts

```
PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）
```

```
PASS: 139 assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source; no AppKit or application launch
```

## Residual Risks

- 未做点击级目视确认；语义变化（重命名不再静默覆盖、删除时偏好改指兜底布局）需人工走一遍。
- 布局增删改会立即写盘（与既有的 `createLayout`/`removeCurrentLayout` 一致），不进入设置窗口的「保存」暂存模型；如果用户重命名后又点「取消」，布局改名仍会保留。
- 多屏幕/多空间偏好在同一布局被多个键引用时，重命名会全部改指新名字；实机多屏组合未逐一复核。

## Recommendation

- 保持修复。人工验收建议：设置 → 布局下拉选 `小屏`，分别点重命名、复制、删除，确认每次作用于 `小屏`，且下拉跟着更新为新名字/兜底布局；再确认「保存」「取消」不会把旧名字写回。
