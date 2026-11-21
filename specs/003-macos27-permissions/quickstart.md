# 快速验证指南：macOS 27 权限模型适配

**Feature**: `003-macos27-permissions` | **环境基准**：macOS 27.3（本机 Build `26C5047e`，Apple Silicon）、Xcode 27.2、正式开发证书 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)` / Team `74FR87HYTH`。

## 前置条件

1. 已安装 Xcode 27.2（`/Applications/Xcode.app`），`xcode-select -p` 指向它。
2. 钥匙串里有上述开发证书（`security find-identity -v -p codesigning` 能看到）。
3. 需要真实授权的场景，必须使用**已签名并安装**的构建产物（`~/Applications/MacsyZones-dbg.app` 或 `/Applications/MacsyZones.app`），不能直接从 `/tmp` 运行——`/tmp` 路径会让 TCC 按不同身份记录，且可能触发 translocation。
4. 验证会改动系统隐私设置，请自行决定是否执行场景 C/E/F。

## 一、构建

```bash
cd /Users/jiezhengj/Documents/Project/MacsyZones
bash scripts/build-debug.sh
```

期望输出结尾：`** BUILD SUCCEEDED **`，以及 `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）`；`warning:` 计数应为 0。

## 二、静态与桩断言

```bash
bash scripts/check_permission_model.sh
```

期望输出：`PASS: 权限模型断言通过（<N> assertions）`，exit 0。脚本覆盖：状态映射表（`granted/denied/unknown` 与 `-25211`/`-25204`/超时/目标缺失）、宽限窗口计算、以及不变量 grep（源码中不出现 `#available`、探针代码中不出现 `AXUIElementSetAttributeValue`、权限路径中不出现 `exit(`）。

## 三、运行期冒烟

```bash
bash scripts/permission-smoke.sh
```

脚本行为：启动构建产物 → 等待 20 秒 → 用 `log show` 抓 `subsystem == "MeowingCat.MacsyZones" AND category == "permissions"` → 断言至少一条 `capability=windowControl`、字段齐全、无崩溃 → 关闭进程。

期望输出：`PASS: 权限日志与进程状态正常（<N> 条权限记录）`。

## 四、手动验证矩阵

每个场景记录三列：预期状态、实际状态、备注。前三个场景必须在已授权安装副本上跑。

### 场景 A：首次未授权启动（关键）

1. 先移除授权：系统设置 → 隐私与安全性 → System & App Protection Override（或无障碍）→ 若列表中有 MacsyZones，关闭开关。
2. 启动 `~/Applications/MacsyZones-dbg.app`。

预期：

- 不出现**阻塞式**模态框；主界面可用，菜单栏图标在。
- 引导面板/横幅出现，文案包含「System & App Protection Override」（27.3+），并有「打开系统设置」「重新检测」按钮。
- 点「打开系统设置」→ 系统设置停在对应面板（不是首页）。
- 日志可见 `capability=windowControl status=denied`（或 `unknown`）`trigger=launch`。
- 应用不退出、不崩溃。

### 场景 B：授权后自动恢复（关键）

1. 承接场景 A，在系统设置里把 MacsyZones 加入/打开授权。
2. 不重启 app，切回 MacsyZones（触发 `didActivateApplication`）。

预期：

- 10 秒内（或点「重新检测」后 2 秒内）状态变 `granted`：引导消失、横幅消失。
- 日志出现 `status=granted trigger=activate`（或 `manual`）。
- 拖动窗口吸附功能立即可用（拖一个窗口到屏幕边缘，出现分区高亮）。

### 场景 C：运行中撤销权限

1. 场景 B 之后，回到系统设置关闭 MacsyZones 的授权。
2. 回到 MacsyZones 操作一次（拖动窗口）。

预期：

- 60 秒宽限内不弹任何提示（只写日志）；宽限结束后显示非模态提示。
- 应用不崩溃；再次授权后自动恢复（回到场景 B 的预期）。

### 场景 D：27.2 → 27.3 升级保持授权

需在另一台（或降级后的）机器：27.2 上授权 → 升级到 27.3 → 启动。

预期：无需重新授权即可用（苹果声明「已授予的权限保持不变」）；若实际要求重新授权，把实测结果写进 `research.md` R12 与 `spec.md` 的假设段落，并在引导里补一句说明。

### 场景 E：per-target 部分可用

1. 授权后分别尝试吸附 Finder 窗口与 Safari 窗口（27.3 beta 2 已知问题：Override app 可能无法与 WebKit app 交互）。

预期：诊断面板如实显示「部分目标受控」；不可控的目标吸附失败时不崩溃、不刷错误日志；`notes` 里出现对应说明。

### 场景 F：输入监听关闭

1. 系统设置 → 隐私与安全性 → 输入监控（Input Monitoring）中关闭 MacsyZones。
2. 重启 app。

预期：拖动吸附不可用但 Carbon 全局快捷键仍工作；横幅说明「缺少输入监听权限」；诊断面板 `inputMonitoring=denied`、`windowControl=granted`。

## 五、诊断报告

设置 → 权限 → 「复制报告」，粘贴到 issue 或存档。用 `contracts/permission-report.schema.json` 校验：

```bash
pbpaste > /tmp/permission-report.json
python3 - <<'PY'
import json
schema = json.load(open('/Users/jiezhengj/Documents/Project/MacsyZones/specs/003-macos27-permissions/contracts/permission-report.schema.json'))
report = json.load(open('/tmp/permission-report.json'))
assert report["schemaVersion"] == 1
assert report["app"]["bundleID"] == "MeowingCat.MacsyZones"
ids = {c["id"] for c in report["capabilities"]}
assert {"windowControl", "inputMonitoring"} <= ids
print("PASS: 报告结构符合契约", {c["id"]: c["status"] for c in report["capabilities"]})
PY
```

## 六、日志取证

```bash
# 最近 5 分钟的权限日志
log show --last 5m --predicate 'subsystem == "MeowingCat.MacsyZones" AND category == "permissions"' --info

# 系统的 TCC 侧证据（是否弹过提示、是否 preflight_unknown）
log show --last 10m --predicate 'process == "tccd" AND eventMessage CONTAINS "MeowingCat.MacsyZones"' --info

# 是否出现登录期 fd 耗尽误判（社区已知问题）
log show --last 3d --predicate 'process == "tccd" AND eventMessage CONTAINS "Too many open files"'
```

## 七、排错

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 构建失败提示签名 | 证书不在钥匙串 / Xcode 版本不符 | `security find-identity -v -p codesigning` 核对 `C7C84AAA...` |
| 烟雾脚本抓不到日志 | 用 `/tmp` 下的产物、或未签名 | 用 `~/Applications/MacsyZones-dbg.app`；`codesign -dv --verbose=4 <app>` 核对 Team ID |
| 状态永远 `unknown` | 探针目标 app 未运行（Finder 被替换） | 打开 Finder 后点「重新检测」；诊断面板会显示 `lastError` |
| 授权后仍 `denied` | 系统设置里改的不是同一个副本（`/tmp` vs `~/Applications`）；或 tccd 登录期抖动 | 删掉旧条目重新添加；等 60 秒宽限后重试 |
| 面板跳转落到首页 | 锚点在新系统被改名 | 按 `contracts/guidance-targets.md` 兜底文案手动导航，并记录实际锚点回填契约 |
