# Bug Verification: 编辑布局时编辑框按设置选中的显示器摆放

- **Slug**: editor-window-wrong-screen
- **Tested**: 2026-11-22
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

修复后重跑原复现路径：设置里选内置显示器 + `小屏` 再点编辑，编辑层 `Macsy Layout` 出现在内置屏 `(0,33) 1470×923`、编辑条在 `(735,495)`，不再是外置屏；切到外置显示器后编辑层随之变为 `(1470,-454) 2560×1361`。五个脚本检查与正式签名 Debug 构建全部通过，未发现回归。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | AXUIElement 驱动 `/Applications/MacsyZones.app`（pid 21442）：状态栏菜单 → 打开主界面 → 选 `Built-in Retina Display` → 选 `小屏` → 点 `Edit`，再用 `CGWindowListCopyWindowInfo` 读窗口几何 | pass | 编辑层 `(0,33) 1470×923`、编辑条 `(735,495)`，均在内置屏；切 `U27N3G6R4B` 再编辑则为 `(1470,-454) 2560×1361`，落外置屏 |
| 新建区块落点 | 编辑态点「新建区域」后读窗口几何 | pass | 新蓝框 `735×478 at (368,239)`，完整在内置屏内（修复前会落在鼠标所在的外置屏） |
| 保存基准 | 保存后读 `~/Library/Application Support/MeowingCat.MacsyZones/UserLayouts.json` | pass | `w=0.5 h=0.5 x=0.250340 y=0.25` → 按内置屏 1470×956 换算即 `735×478 at (368,239)`，与蓝框一致；测试区块已删除、`小屏` 恢复 0 区块 |
| New / updated tests | `bash scripts/check_editor_screen.sh` | pass | `PASS: 目标屏幕解析正确（同一百分比按各屏尺寸换算，不会跨屏串味）` + `PASS: 编辑目标屏幕回归通过（设置选中的显示器决定编辑框与保存基准）` |
| Regression suite | `bash scripts/check_layout_geometry.sh` | pass | `PASS: 布局几何回归通过（百分比往返不丢点，相邻区块不错缝）` |
| Regression suite | `bash scripts/check_layout_selection.sh` | pass | `PASS: 布局选择一致性回归通过（下拉选中项与四个按钮共用同一名字）` |
| Regression suite | `bash scripts/check_lazy_lifecycle.sh` | pass | `PASS: 139 assertions against actual UserLayout/startEditing/stopEditing/toggleEditing source` |
| Build / signing | `bash scripts/build-debug.sh` | pass | `** BUILD SUCCEEDED **` + `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）` |
| 发布版安装 | `build-release-dmg.sh 2.1.2 patch` → 挂载 DMG 覆盖 `/Applications/MacsyZones.app` | pass | `CFBundleShortVersionString = 2.1.2`，`verify-signing.sh` PASS，启动 pid 22447 |
| 发布版真机复测 | 在 v2.1.2 上重跑复现步骤：选 `Built-in Retina Display` + `小屏` → `Edit`；再切 `U27N3G6R4B` → `Edit` | pass | 内置屏编辑层 `(0,33) 1470×923` + 编辑条 `(735,495)`；外置屏编辑层 `(1470,-454) 2561×1361`；测试区块已取消，`小屏` 仍为 0 区块 |

## Output Excerpts

```text
--- 设置选内置屏 + 小屏 + 编辑 ---
layer=26 281x50 at (735,495) name=Macsy Seciton Editor Bar
layer=25 1470x923 at (0,33) name=Macsy Layout
layer=0 550x632 at (2475,-89) name=MacsyZones 设置

--- 切到外置屏 + 编辑 ---
layer=26 281x50 at (2750,227) name=Macsy Seciton Editor Bar
layer=25 2560x1361 at (1470,-454) name=Macsy Layout
```

```text
zone1: pct w=0.500000 h=0.500000 x=0.250340 y=0.250000
     -> 内置屏像素 735.0x478.0 at (368.0,239.0)
```

## Residual Risks

- **跨屏拖拽与提示文案未做真机点击验证**：合成 `CGEvent` 拖拽（`/tmp/drag.swift`、`/tmp/drag2.swift`）无法驱动窗口移动，因此「拖到另一块屏被弹回 + 新文案『一个布局只属于一个屏幕』」只有源码级断言（`scripts/check_editor_screen.sh` 检查文案与 `originalScreen` 来源），需人工拖一次确认。
- 空布局（0 区块）下拖编辑层同样会被弹回并提示，可能让用户困惑；已在 `fix.md` 的 Follow-ups 记录，未在本次修复范围内。
- 单屏设备未实测，逻辑上 `editingScreen` 回退 `getFocusedScreen()`，行为与修复前一致。

## Recommendation

关闭该 bug：原症状（编辑框固定出现在外置屏、无法在内置屏编辑）已按复现步骤验证消失，相关回归脚本与正式签名构建均通过。若要更严格，可在人工确认一次跨屏拖拽提示后把 `test.md` 的 Result 保持为 `verified` 并在备注里补一次记录。
