# Bug Fix: 区块尺寸按百分比往返后少 1 点

- **Slug**: layout-size-1px-truncation
- **Fixed**: 2026-11-22
- **Assessment**: ./assessment.md

## 变更摘要

在「百分比 → 点」的唯一出口做边缘取整，不改持久化格式。

- `MacsyZones/UserData.swift` `SectionConfig.getRect(on:)`：先算 `minX/minY/maxX/maxY` 四条边并 `.rounded()`，宽高由取整后的边相减。`830 / 1440` 回乘得到的 `829.9999999999999` 现在落回 `830`。
- `MacsyZones/UserData.swift` `SectionConfig.getAXRect(on:)`：屏幕坐标（下边 `minY`、上边 `maxY`）取整后再翻成 AX 坐标，宽高与 `getRect` 完全一致；写其他 app 窗口 `kAXPositionAttribute`/`kAXSizeAttribute` 时不再带亚像素。
- 新增 `scripts/check_layout_geometry.sh`：静态断言（两处必须使用边缘取整、不得残留裸乘）+ 算术断言（830 用例、1100×690 不变、相邻区块共享边不错缝）。

## 为什么放在这里

- 保存端（`onSave`）本来就只能拿到整数点窗口尺寸，损失发生在回乘；改存储端无效。
- `getRect`/`getAXRect` 是编辑器窗口、`reArrange`、AX 写入的公共入口，一处修复覆盖全部消费者。
- 边缘取整（而不是「原点取整 + 宽高各自取整」）保证相邻区块共享的边落在同一条整点线上，不会产生 1 点缝。

## 验证

```
bash scripts/check_layout_geometry.sh
# reported zone legacy height=829.9999999999999 fixed height=830.0
# PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）

bash scripts/build-debug.sh
# PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）
```

## 未改动

- `UserLayouts.json` 格式（仍存百分比）；`onSave`、`getUpdated`、`reArrange` 的换算方式。
- 网格布局（`layoutType == .grid`）不经过 `SectionConfig`，无影响。
