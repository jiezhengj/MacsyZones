# Bug Verification: 区块尺寸按百分比往返后少 1 点

- **Slug**: layout-size-1px-truncation
- **Tested**: 2026-11-22
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

算术与静态证据显示缺陷机制已被掐断：`830/1440` 回乘的 `829.9999999999999` 现在在 `getRect`/`getAXRect` 落回 `830`，取整对所有消费者（编辑器窗口、`reArrange`、AX 写入）生效。整点尺寸在实机上的可见结果（窗口高度显示 830）需要一次拖拽+保存的人工确认——本机已无可用 GUI 自动化通道，见「Residual Risks」。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | 从用户实机 `UserLayouts.json` 取出 `大屏` zone1 百分比，跑 `scripts/check_layout_geometry.sh` 的 legacy/rounded 两套公式 | pass | legacy 得到 `829.9999999999999`（复现），rounded 得到 `830`（修复） |
| New / updated tests | `bash scripts/check_layout_geometry.sh` | pass | `PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）` |
| Regression suite | `bash scripts/build-debug.sh` | pass | `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）` |
| Regression suite | `bash scripts/check_lazy_lifecycle.sh`（002 的物化回归） | pass | 未触及惰性物化路径，保持 PASS |
| Install & launch | `bash scripts/build-permission-artifact.sh` + `open -a` | pass | 正式版已替换；进程稳定，权限探针 `granted`，无崩溃报告 |
| Manual end-to-end | 编辑模式下把区块拖到 830 高，保存，重进编辑看高度 | not-run | 需要点击菜单栏铅笔并拖拽，本机 GUI 自动化被 TCC 阻断 |

## Output Excerpts

```
reported zone legacy height=829.9999999999999 fixed height=830.0
PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）
```

```
zone1 old w=1470.0 h=829.9999999999999 | new w=1470.0 h=830.0 x=0.0 y=580.0
zone2 old w=1100.0 h=690.0 | new w=1100.0 h=690.0 x=1460.0 y=79.0
```

## Residual Risks

- 未在实机做「拖拽 → 保存 → 重进」的目视确认；改变的是换算层，窗口实际落点由 WindowServer 决定，理论上已消除亚像素输入。
- 取整会让非整点布局产生 ≤1 点位移；相邻共享边的取整策略已用算术断言锁定。
- 多屏 + 缩放组合只做了算术推演（`NSScreen.frame` 是点坐标），未在所有显示器配置上实机复核。

## Recommendation

- 保持修复。请人工做一次两分钟验收：编辑 `大屏`，把某个区块拉到 830 高 → 保存 → 重进编辑，确认高度显示/窗口实际高度是 830 而不是 829；若有异常，按新证据重跑 `/speckit-bug-assess`。
