# Bug Verification: 区块尺寸按百分比往返后少 1 点

- **Slug**: layout-size-1px-truncation
- **Tested**: 2026-11-22
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

算术层面的复现与修复都已跑通：同一组用户实机百分比，旧公式得到 `829.9999999999999`，新公式得到 `830`，且 1100×690 区块与相邻共享边保持不变。点击级「拖到 830 → 保存 → 重进编辑」没有执行（本机 GUI 自动化被 TCC 阻断），所以不算端到端 verified。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `bash scripts/check_layout_geometry.sh`（内嵌 legacy/rounded 双公式） | pass | legacy 复现 `829.9999999999999`；rounded 得 `830.0` |
| New / updated tests | `bash scripts/check_layout_geometry.sh` | pass | 取整实现断言 + 算术断言全部通过 |
| Regression suite | `bash scripts/check_lazy_lifecycle.sh` | pass | `139 assertions`，惰性物化路径未受影响 |
| Regression suite | `bash scripts/build-debug.sh` | pass | `BUILD SUCCEEDED` + 签名校验 PASS，警告仅基线一条 |
| Lint / type-check | `xcodebuild`（同上构建） | pass | Swift 编译无新增警告 |
| Manual end-to-end | 拖到 830 → 保存 → 重进编辑 | not-run | 需要点击与拖拽，自动化通道被 TCC 拒绝 |

## Output Excerpts

```
reported zone legacy height=829.9999999999999 fixed height=830.0
PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）
```

```
PASS: 139 assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source; no AppKit or application launch
```

## Residual Risks

- 只在算术层证明修复，窗口最终高度由 WindowServer 落点决定；未实机目视确认。
- 亚像素输入被取整后，非整点布局会移动 ≤1 点；相邻共享边已用断言覆盖，但多屏 + 缩放组合未逐一实机复核。
- 网格布局不走 `SectionConfig` 路径，本次未触及；`check_lazy_lifecycle.sh` 通过作为旁证。

## Recommendation

保持修复，但把状态记为 partial 并在人工验收后关闭：请在 `大屏` 把一个区块拖到 830 高 → 保存 → 重进编辑，确认高度是 830；若仍为 829，按新证据重跑 `/speckit-bug-assess`。
