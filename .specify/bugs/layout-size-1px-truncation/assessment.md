# Bug Assessment: 区块尺寸按百分比往返后少 1 点

- **Slug**: layout-size-1px-truncation
- **Created**: 2026-11-22
- **Source**: pasted text（用户 m02025 报告第一条）
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim)

> 第一，比如现在的“大屏”方案，我把其中一个区块设置为 1100×830，保存后，永远会被保存为 1100×829。

## Symptom

把区块拖成整数高度（例如 830 点）并保存后，重新排列/退出重进时该区块变成 829 点，且每次保存都无法纠正；宽度同理（1100 在 2560 宽的屏上恰好整除，所以用户只看到高度少 1）。

## Reproduction

1. 在外接 2560×1440 屏上，进入编辑模式，把某个区块拖到高 830 点。
2. 点击保存（`onSave`），区块窗口立即变成 829 点。
3. 反复保存，高度始终是 829；退出编辑再进入仍是 829。

证据（用户实机数据 `~/Library/Application Support/MeowingCat.MacsyZones/UserLayouts.json`）：
`大屏` zone1 `heightPercentage = 0.5763888888888888`，在 1440 高的屏上 `1440 × 0.5763888888888888 = 829.9999999999999`。

## Suspected Code Paths

- `MacsyZones/Layout.swift:1571` `onSave()` — 用 `editorWindow.frame.size` 除以屏幕尺寸写入百分比（830/1440 = 0.5763888888888888，该 double 不可精确表示）。
- `MacsyZones/UserData.swift:694` `SectionConfig.getRect(on:)` — `screen.frame.height * heightPercentage`，无取整，得到 829.9999999999999。
- `MacsyZones/UserData.swift:716` `SectionConfig.getAXRect(on:)` — 同上，且这是写其他 app 窗口 AX geometry 的来源（`MacsyZones/Macsy.swift:1015`）。
- `MacsyZones/Layout.swift:858` `reset(sectionConfig:)` — 用 `getRect()` 直接 `setFrame`，亚像素尺寸进入编辑器窗口。

## Root Cause Hypothesis

置信度：high。

百分比是唯一的持久化表示（`SectionConfig` 只有 `width/height/x/yPercentage`），保存时用整数点除以屏幕点数，比值在 double 里无法精确表示；读回时再乘一次屏幕尺寸，误差落在 829.9999999999999 这类值上。整条链路（编辑器窗口 `setFrame`、`reArrange`、AX 写 `kAXSizeAttribute`）都没有做整点取整，WindowServer/AX 侧把 829.999… 落成 829，于是每次往返丢 1 点。

已用 Python 复核该算术：`(830/1440) * 1440 == 829.9999999999999`，且 JSON 中存的正是 `830/1440` 的最近 double。

## Proposed Remediation

**Preferred**：在几何计算处按「边缘取整」把百分比换算回整点——`getRect` 与 `getAXRect` 分别计算 `minX/minY = round(origin + size * percentage)` 与 `maxX/maxY = round(origin + size * (percentage + extentPercentage))`，宽高由取整后的两条边相减得到。这样 829.9999 与 830.0001 都回归到 830，且相邻区块共享的边仍落在同一条整点线上，不会因为「原点取整 + 宽高取整」各自独立而出现 1 点缝或重叠。

不改变持久化格式（仍存百分比），不改 `onSave` 的换算方式——修复点放在「百分比 → 点」的唯一出口，所有消费者（编辑器窗口、`reArrange`、AX 写入）自动受益。

**Alternatives**：
- 保存时把像素宽高先取整再除（`(830).rounded() / 1440`）——无效，损失发生在回乘而不是存储。
- 持久化改为存整点像素——改变配置格式，需要迁移，超出本次缺陷范围。

**Files likely to change**：
- `MacsyZones/UserData.swift`
- `scripts/check_layout_geometry.sh`（新增静态+算术断言）

**Tests to add or update**：
- 断言 `getRect`/`getAXRect` 使用取整边缘计算，且不存在裸 `screen.frame.height * heightPercentage` 直接作为返回值。
- 算术回归：对 1440 高、`heightPercentage = 830/1440` 输入，取整后高度必须是 830；对 2560 宽、`1100/2560` 必须是 1100。

## Risks & Considerations

- 取整会让非整点布局产生 ≤1 点的位移；这对窗口管理工具可接受，且比每次丢 1 点稳定。
- 多屏缩放（backing scale ≠ 1）下 `NSScreen.frame` 仍是点坐标，取整到点不会破坏 Retina 渲染。
- 网格布局（`layoutType == .grid`）不走 `SectionConfig` 路径，需确认无回归。

## Open Questions

- 无（用户数据已足够定位；宽度 1100 恰好整除，不需要额外澄清）。
