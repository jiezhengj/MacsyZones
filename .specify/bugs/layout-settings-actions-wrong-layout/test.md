# Bug Verification: 设置里的布局操作永远作用于当前活动布局

- **Slug**: layout-settings-actions-wrong-layout
- **Tested**: 2026-11-22
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

设置区与 `UserLayouts` 的一致性由静态回归锁定：下拉与四个按钮共用 `selectedLayoutName`，旧的 current 版调用零命中，按名字的增删改与偏好修正都存在。点击级复现（下拉选 `小屏` 后点重命名/复制/删除）没有执行——本机 GUI 自动化被 TCC 阻断，所以记为 partial。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `bash scripts/check_layout_selection.sh` | pass | 设置区零命中 `renameCurrentLayout(`/`removeCurrentLayout(`/`duplicateCurrentLayout(` |
| New / updated tests | `bash scripts/check_layout_selection.sh` | pass | 共用 `selectedLayoutName`、按名字实现、偏好修正断言全部通过 |
| Regression suite | `bash scripts/check_lazy_lifecycle.sh` | pass | `139 assertions`，布局增删改仍走 `stopEditing`/物化路径 |
| Regression suite | `bash scripts/build-debug.sh` | pass | `BUILD SUCCEEDED` + 签名校验 PASS |
| Lint / type-check | `xcodebuild`（同上构建） | pass | 无新增警告 |
| Manual end-to-end | 下拉选 `小屏` → 重命名/复制/删除 | not-run | 需要点击设置窗口，自动化被 TCC 拒绝 |

## Output Excerpts

```
PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）
```

```
PASS: 139 assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source; no AppKit or application launch
```

## Residual Risks

- 未做点击级目视确认；行为变化（重命名不再静默覆盖同名布局、删除非活动布局时偏好改指兜底）需人工走一遍。
- 布局增删改立即写盘，不进入「保存/取消」暂存模型，这是既有语义，非本次引入。
- 多屏/多空间偏好被同一布局名多次引用时，改名会全部改指新名字；只做静态与构建验证。

## Recommendation

保持修复，记为 partial 待人工验收：设置 → 布局下拉选 `小屏`，依次点重命名、复制、删除，确认每次作用于 `小屏`，下拉随之更新为新名字或兜底布局，再确认「保存/取消」不会把旧名字写回。
