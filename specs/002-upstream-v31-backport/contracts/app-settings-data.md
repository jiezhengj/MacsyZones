# 契约：`AppSettings.json` 持久化格式

MacsyZones 没有对外 API 或插件边界，本 feature 唯一会被「外部」消费的接口是磁盘上的用户配置文件：升级前写入的 `AppSettings.json` 必须能被新版本正确读取，新版本写入的文件也必须能被旧语义理解（多出的键被忽略）。这是本 feature 唯一需要固化的契约。

## 位置与编码

- 路径：`~/Library/Application Support/MeowingCat.MacsyZones/AppSettings.json`
- 编码：UTF-8 JSON，单行字符串整体落盘（`MacsyZones/UserData.swift` 的 `data` 字段）
- 写入者：`AppSettings.save()`（`MacsyZones/Settings.swift:121-152`），只在用户保存设置或重置默认值时触发
- 读取者：`AppSettings.load()`（`:88-118`），App 启动时一次

## 字段契约（本 feature 相关部分）

| 键 | 类型 | 允许缺省 | 缺省语义 | 版本引入 |
|---|---|---|---|---|
| `quickSnapperZoneLayoutsOnly` | boolean | 是 | `true` | 本 feature 引入 |
| 其余 20 个既有键 | boolean / string / number | 是（均为 optional） | 见 `AppSettings` 的 `default*` 常量 | 早于本 feature |

示例（节选，保留未知键是允许的）：

```json
{
  "modifierKey": "Control",
  "snapKey": "Shift",
  "snapResize": true,
  "showSnapResizersOnHover": true,
  "enableZoneSpanning": true,
  "quickSnapperZoneLayoutsOnly": true
}
```

## 兼容性保证

1. **向后兼容（旧文件 → 新版本）**：缺少 `quickSnapperZoneLayoutsOnly` 时按 `true` 处理，其余字段沿用既有 `??` 回退；任何字段缺失都不得导致整份设置解码失败。
2. **向前兼容（新文件 → 旧版本）**：旧版本 `JSONDecoder` 忽略未知键，因此新版本写出的 `quickSnapperZoneLayoutsOnly` 不会让回滚后的旧版本崩溃（回滚时该行为退化为「全部布局参与循环」）。
3. **不写空值语义**：`save()` 写出的是当前内存值（非 nil），因此文件里该键始终存在；`nil` 只出现在内存默认态。
4. **失败处理**：编码失败 → `debugLog("Error encoding settings JSON: …")` 且不覆盖磁盘；解码失败 → `debugLog("Error parsing settings JSON: …")` 且保留内存默认值。两条路径都不得抛出、不得崩溃（章程原则五）。
5. **重置**：`resetToDefaults()` 后重新落盘，该键必须为 `true`。

## 验证方式

- 静态：`scripts/check_lazy_lifecycle.sh` 不覆盖此契约；由 `quickstart.md` 的「旧配置升级」场景手工验证。
- 手工：删除 `AppSettings.json` 中该键 → 启动 → 设置里开关显示为开启 → 关闭并保存 → 重新启动 → 仍为关闭。

## 明确不在契约内

- `UserLayouts.json` 的布局结构不由本 feature 修改。
- 不引入设置版本号字段，也不做显式迁移函数：字段级 optional 回退就是迁移机制。
