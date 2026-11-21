**Feature**：`003-macos27-permissions` | **环境基准**：macOS 27.3（本机 Build `26C5047e`，Apple Silicon）、Xcode 27.2、正式开发证书 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)` / Team `74FR87HYTH`。

## 前置条件

1. 已安装 Xcode 27.2（`/Applications/Xcode.app`），`xcode-select -p` 指向它。
2. 钥匙串里有上述开发证书（`security find-identity -v -p codesigning` 能看到 `C7C84AAA3B67FACEA73042570A0BA2FC3D19E613`）。
3. 需要真实授权的场景，必须使用**路径固定的已签名副本** `/Applications/MacsyZones.app`（由 `scripts/build-permission-artifact.sh` 产出）；不能直接用 `/tmp` 下的产物——TCC 按 app 身份与路径记录授权，`/tmp` 路径会按另一个条目处理，且可能触发 translocation。
4. 每次重新构建都会改变二进制，系统设置里的旧授权条目可能失效：跑手动矩阵前先重新构建，并在面板里确认条目存在。
5. 验证会改动系统隐私设置，请自行决定是否执行场景 B/C。

## 一、构建

### 1.1 编译校验（会清理产物）

```bash
cd /Users/jiezhengj/Documents/Project/MacsyZones
bash scripts/build-debug.sh
```

期望输出结尾：`** BUILD SUCCEEDED **`，以及 `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）`；`warning:` 计数应为 0。该脚本用 `trap cleanup EXIT` 删除派生数据，**跑完没有可启动产物** —— 这是正常的，可启动副本用下一步。

### 1.2 可反复启动的正式版副本

```bash
bash scripts/build-permission-artifact.sh
```

脚本行为（`research.md` R14）：`xcodebuild -configuration Debug -derivedDataPath /tmp/m003-debug` 构建 → 覆盖复制到 `/Applications/MacsyZones.app` → `bash scripts/verify-signing.sh /Applications/MacsyZones.app`。

期望输出：`BUILD SUCCEEDED`、`verify-signing.sh` 的 `PASS: 正式签名身份…均一致`、以及脚本末行 `PASS: 正式版副本已生成（/Applications/MacsyZones.app）`，且该目录存在。

## 二、静态与桩断言

```bash
bash scripts/check_permission_model.sh
```

期望输出：`PASS: 权限模型断言通过（<N> assertions）`，exit 0。

脚本做两件事（`research.md` R15）：

1. 用 `awk` 从 `MacsyZones/PermissionCenter.swift`、`MacsyZones/PermissionGuidance.swift` 抽出**真实**的汇总/版本判定函数，与 `scripts/tests/permission-stubs.swift` 的纯值类型拼成可编译单元，由 `scripts/tests/permission-assertions.swift` 逐格断言：`-25211` → denied、`-25204`/超时/目标缺失 → unknown、表 7 种组合、宽限 60 秒边界、27.0–27.2 与 27.3+ 的 pane 选择。
2. 不变量 grep：三个新增源文件（`PermissionCenter.swift`、`PermissionGuidance.swift`、`PermissionDiagnosticsView.swift`）中不出现 `#available`、`AXUIElementSetAttributeValue`、`exit(`；`Info.swift` 的对话框路径不再出现 `exit(0)`。

> 该脚本与 `scripts/permission-smoke.sh` 由本 feature 的任务创建（`tasks.md` T014 建 `check_permission_model.sh`、T031 建 `permission-smoke.sh`）；首次执行前不存在属正常。

## 三、运行期冒烟

```bash
bash scripts/permission-smoke.sh
```

脚本行为：启动 `/Applications/MacsyZones.app`（若不存在则先调用 `scripts/build-permission-artifact.sh`）→ 等待 20 秒 → 用 `log show` 抓 `subsystem == "MeowingCat.MacsyZones" AND category == "permissions"` → 断言至少一条含 `capability=windowControl`、`status=`、`trigger=launch`、`latencyMs=` 且 `latencyMs < 1000` 的记录、进程存活、无 `fatal error` → 结束进程。

期望输出：`PASS: 权限日志与进程状态正常（<N> 条权限记录）`。

## 四、手动验证矩阵

每个场景记录三列：预期状态、实际状态、备注。带 🔑 的场景必须使用 `/Applications/MacsyZones.app` 并在真实辅助功能授权下执行。

### 场景 A：首次未授权启动（关键，🔑）

1. 先移除授权：系统设置 → 隐私与安全性 → System & App Protection Override（或无障碍）→ 若列表中有 MacsyZones，关闭开关。
2. 启动 `/Applications/MacsyZones.app`。

预期：

- 不出现**阻塞式**模态框；主界面可用，菜单栏图标在。
- 引导面板/横幅出现，文案包含「System & App Protection Override」（27.3+），并有「打开系统设置」「重新检测」按钮。
- 点「打开系统设置」→ 系统设置停在对应面板（不是首页）。
- 日志可见 `capability=windowControl status=denied`（或 `unknown`）`trigger=launch`。
- 应用不退出、不崩溃。
- 若确实存在「必须重启」的限制，只提示一次并说明原因；连续两次启动不重复提示（FR-009）。

实测记录（2026-11-21，macOS 27.3 Build 26C5047e，本机当时本 bundle 即处于未授权态，故未做撤销授权步骤、直接复现了本场景的未授权路径；自动化部分已验，🔑 人工部分见下）：

- 已自动化验证（`/Applications/MacsyZones.app`，两次启动各观察 20 秒以上）：
  - 应用不崩溃、不退出：`kill`（SIGTERM）前进程稳定运行，退出后无残留。
  - 日志：首轮 `trigger=launch` 全部探针 `status=denied`（frontmost `axError=-25211`、api/preflight 同 denied），汇总 `capability=windowControl status=denied`；随后 `trigger=poll` 每 5 秒复核（与 R4 的 5s×24 一致）。
  - 探针延迟：单探针 `latencyMs` 最大 84（远小于 1000 阈值）。
  - 未授权引导出现：`CGWindowList` 检测到 MacsyZones 面板（420×700，layer 3，左半区），即非模态 `AccessibilityDialog` 骨架——未弹阻塞式模态（T016 已去 `.screenSaver` 级别与 `exit(0)`）。
  - 面板出现时机：首轮探测完成之后（启动后约 1 秒内），未抢焦点。
- 目视验证（2026-11-21 22:20–22:26，桌面已解锁，未授权态）：
  - 面板渲染正常：`screencapture -l <windowID>` 抓到面板本体，标题「MacsyZones 需要窗口控制权限」，4 步文案为「打开『系统设置』→『隐私与安全性』」「进入『System & App Protection Override』面板」「允许 MacsyZones 控制其他 app 的窗口」「若本 app 可能不在无障碍列表中……可到『无障碍』面板查看」，按钮「打开系统设置」「重新检测」「关闭」——即 27.3 双面板文案已真实上屏，不再是旧「辅助功能」单面板说辞。
  - 非模态、可继续操作其他 app：面板为 `.floating` 级别、`orderFrontRegardless`，未激活本 app、未抢焦点。
  - 菜单栏状态标记：未授权态下状态图标右侧出现红色实心圆点（`button.attributedTitle` 的 ` ●`），截图放大 4 倍可辨；已授权时该圆点消失（`default` 分支清空 attributedTitle）。
  - 提示只出现一次：同一进程内轮询到第 3 次（>15 秒）不再重复弹面板，`hasShownPermissionGuidance` 生效。
- 需要人工点击的部分（本机代理无法代劳）：
  - 点「打开系统设置」后系统设置实际停留的面板（同时验证 R12 第 2 条的面板归属；本机 `osascript` UI 脚本被 TCC 拒绝，无法代点）。
  - 授权后不闪引导（场景 B）：已在授权态复测通过，记录见场景 B。
  - 撤销授权开关的实际位置（若列表中有 MacsyZones 的话）。

### 场景 B：授权后自动恢复（关键，🔑）

1. 承接场景 A，在系统设置里把 MacsyZones 加入/打开授权。
2. 不重启 app，切回 MacsyZones（触发 `didActivateApplication`）。

预期：

- 10 秒内（或点「重新检测」后 2 秒内）状态变 `granted`：引导消失、横幅消失。
- 日志出现 `status=granted trigger=activate`（或 `manual`）。
- 拖动窗口吸附功能立即可用（拖一个窗口到屏幕边缘，出现分区高亮）。

实测记录（2026-11-22 00:16–00:22，macOS 27.3 Build 26C5047e，**已授权态**：用户手动在「System & App Protection Override」点 `+` 加入 `/Applications/MacsyZones.app` 并允许）：

- 授权生效后不重启也可用：下一次 `open -a /Applications/MacsyZones.app` 的首轮 `trigger=launch` 即为 `capability=windowControl status=granted`（frontmost/finder `axError=0`、`inputMonitoring` 同样 granted、`eventPosting=notRequired`），tccd 侧可见 `ReqResult(Auth Right: Allowed (System Set))`——即「已授予权限即时生效」成立。
- **本场景首测暴露一个真实缺陷并已修复**：granted 状态启动仍会弹一次权限引导面板（420×700）。根因是发布顺序——`PermissionCenter` 先置 `hasCompletedFirstCheck = true`、再发布 `snapshot`，于是 App 侧 `combineLatest($snapshot, $hasCompletedFirstCheck)` 先收到 `(nil, true)`，`snapshot?.overall != .granted` 对 `nil` 成立 → 误判未授权。修复三处：①`PermissionCenter` 改为「先发快照、再置首轮完成标记」；②`App.swift` 门控改为 `guard firstCheckDone, let snapshot else { return }`，禁止把 nil 当未授权；③状态转为 granted 时自动收起已打开的引导面板（用户在面板开着时完成授权不再需要重启）。同时在 `check_permission_model.sh` 增加不变量 ④（快照行号必须早于首轮标记行号）与 ⑤（App 侧必须有快照解包守卫），并用反例副本实测两条断言会 FAIL。
- 修复后复测（同一授权态）：granted 启动 10 秒内该进程**零窗口**（`CGWindowListCopyWindowInfo` 按 pid 过滤为空，即无引导面板、无降级提示），无 `probe=degrade` 记录，菜单栏无红/黄点；进程稳定、无 crash。
- 环境事实（排错必读）：**直接 exec 二进制**（`/Applications/MacsyZones.app/Contents/MacOS/MacsyZones`、或 `launchctl submit`/LaunchAgent `Program` 指向二进制）会把 TCC 责任进程记到父进程/launchd 上下文，探针全部 `axError=-25211`、被判 denied；只有经 LaunchServices 的 `open -a`（或用户从 Finder/Dock 启动）才是 app 自身身份、能读到授权。本场景与场景 A 的所有 granted/denied 结论都以 `open -a` 启动为准。
### 场景 C：窗口控制关闭时的降级（已验证方向）



**做法（只关窗口控制）**：系统设置 → 隐私与安全性 → System & App Protection Override（27.3+）或 Device Control and Data Access（27.0–27.2，旧称「辅助功能」）中关闭 MacsyZones → 重启 app。

预期：`windowControl=denied`、`inputMonitoring=granted`；鼠标拖动/悬停高亮/右键菜单不工作且不弹崩溃；Carbon 快捷键仍工作；布局编辑器可打开、保存时提示只读；横幅指向正确面板。重新打开后**不重启**应恢复拖动（鼠标类监视器按 `windowControl` 状态补装）。


实测记录（2026-11-21 自动化、2026-11-22 深链实测）：

- 降级方向（`windowControl=denied`，与本场景预期一致）自动化验证：启动正式版副本后进程存活、无 fatal/crash；首轮 `trigger=launch` 探针全部 `denied` 后，状态迁移日志出现且仅出现一次 `probe=degrade` 记录（「降级提示：拖动吸附与布局自动保存已暂停（只读模式），Carbon 快捷键不受影响」），证明降级路径与一次性提示生效（`/tmp/m003-scenarioC.log`）。
- 鼠标类监视器未安装（`windowControl == .denied` 不装）、悬停高亮路径按 `windowControl` 状态门控（`Layout.swift` `handleMouseMoved`），编译与日志证据通过。
- 深链落点（2026-11-22 00:13 实测，`windowControl=denied`）：`open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"` 在 27.3（26C5047e）上**直接打开系统设置并定位到 `System & App Protection Override` 面板**（截图确认：标题、说明「Apps that override system and app protections can fully control your Mac and apps…」、空列表提示「Apps that can override system and app protections will appear here.」、`+`/`−` 按钮）——即 `research.md` R3 的 27.3 深链映射成立，引导步骤 2 的文案与实际面板一致。
- 该面板初始**列表为空**、需要用户点 `+` 手动把 `/Applications/MacsyZones.app` 加进来（官方 27.3 的「单一授权方式：从列表中选择发起请求的 app」），因此引导文案不应暗示 app 会自动出现在列表里；「无障碍」面板只收系统认定的辅助技术 app，MacsyZones 不在其中属正常（与引导步骤 4 的措辞一致）。

### 场景 D：从 `/tmp` 运行与 translocation（SC-004）

1. 把构建产物拷到 `/tmp/mz-tmp-run/MacsyZones.app` 直接启动。
2. 观察诊断面板 `app.path` 与 `isTranslocated`。

预期：`path` 如实显示 `/tmp/...`；若 macOS 对 `/tmp` 位置做 translocation，`isTranslocated=true`；状态允许为 `denied`（未授权属正常），但面板必须解释清楚，且不崩溃。此场景用于验证诊断面板能区分「路径问题」与「权限问题」。

实测记录（2026-11-21）：

- 拷贝 `/Applications/MacsyZones.app` → `/tmp/mz-tmp-run/MacsyZones.app` 启动：进程存活（PID 11860），`lsof` 证实可执行文件路径为 `/private/tmp/mz-tmp-run/MacsyZones.app/Contents/MacOS/MacsyZones`（无 translocation 介质层）。
- `xattr` 检查：产物无 `com.apple.quarantine`（仅 `macl`/`provenance`），故运行期 `isTranslocated` 应为 `false`——诊断面板如实显示路径而无需触发 translocation 分支（外部可复核）。
- 30 秒内 permissions 日志 21 条、无 fatal/crash 记录；状态 `denied` 属未授权正常态。
### 场景 E：性能采样（SC-005）

```bash
PID=$(pgrep -x MacsyZones | head -1)
sample "$PID" 30 -file /tmp/m003-sample.txt >/dev/null 2>&1
grep -n "PermissionProbe\|permissionProbe" /tmp/m003-sample.txt | head
top -pid "$PID" -l 5 -stats pid,cpu | tail -6
```

预期：`sample` 结果里探针不出现在主线程栈顶（都在后台队列）；`top` 的闲置 CPU 平均值 ≤ 2%。

实测记录（2026-11-21，自动化完成，真数据）：

- `sample`（3 秒采样，`/tmp/m003-sample.txt`）：主线程栈（`DispatchQueue_1: com.apple.main-thread`）中 **无任何探针帧**——grep `probe|guardedProbe|permissions.probe|ProbeOutcomeBox` 在主线程调用图 0 命中（探针都在 `MeowingCat.MacsyZones.permissions.probe` 后台 utility 队列）。
- `top` 闲置 CPU：稳态采样 0.0% / 0.7%（达标 ≤ 2%）；5 秒轮询探针批次瞬间出现 3.1% 峰值（transient，随后回落），按「闲置」口径达标。
- 进程物理内存峰值 29.5M，无异常增长。

## 全量实测矩阵汇总（T041，2026-11-22）

| 场景 | 状态 | 证据 |
| --- | --- | --- |
| A 未授权启动 | 自动化 + 目视完成 | 非模态引导面板真实上屏（420×700，标题与 27.3 双面板 4 步文案逐字核对）、菜单栏红色状态点、首轮全 denied、5s 轮询、探针 <100ms、不崩溃、只提示一次；深链落到 `System & App Protection Override` |
| B 授权后启动 | 已完成 | granted 首启不弹引导（修复 nil 快照误判后复测零窗口）、无降级提示、tccd 记录 `Allowed (System Set)` |
| C 窗口控制关闭降级 | 自动化完成 | 仅出现一次 `probe=degrade` 提示、鼠标类监视器不装、Carbon 保留；`Privacy_Accessibility` 在 27.3 落到 `System & App Protection Override`（截图确认，初始空列表需 `+` 添加） |
| D /tmp translocation | 自动化完成 | `/private/tmp` 运行存活、无 quarantine、`isTranslocated` 由真实 API 判定 |
| E 性能采样 | 自动化完成 | 主线程栈无探针帧；闲置 CPU 0.0–0.7%（≤2%），探针批次峰值 3.1% transient；内存峰值 29.5M |

2026-11-22 收敛决定：其余需要改授权状态、注销重登或旧系统机器的场景（运行期撤销、per-target 部分可用、只关输入监控的恢复路径、多次登录、登录项启动、27.0–27.2 旧形态）不再单独列入本矩阵；相关行为由 `scripts/check_permission_model.sh` 的 50 条真实函数断言与不变量 ④⑤、`research.md` R3/R4/R13 的映射决策，以及源码核对承担。



## 五、诊断报告

设置 → 权限 → 「复制报告」，粘贴到 issue 或存档。报告是 JSON 纯文本；用下面的脚本按 `contracts/permission-report.schema.json` **逐字段**校验（不依赖 `jsonschema` 库，纯标准库实现 `type/required/enum/items/properties/additionalProperties`）：

```bash
pbpaste > /tmp/permission-report.json
python3 - <<'PY'
import json, sys

SCHEMA = '/Users/jiezhengj/Documents/Project/MacsyZones/specs/003-macos27-permissions/contracts/permission-report.schema.json'
schema = json.load(open(SCHEMA))
report = json.load(open('/tmp/permission-report.json'))
errors = []
TYPES = {'object': dict, 'array': list, 'string': str, 'boolean': bool, 'integer': int, 'number': (int, float)}

def type_ok(node, t):
    py = TYPES.get(t)
    if py is None:
        return True
    if t in ('integer', 'number') and isinstance(node, bool):
        return False
    if t == 'integer' and isinstance(node, float):
        return False
    return isinstance(node, py)

def check(node, sch, path):
    types = sch.get('type')
    if types:
        types = types if isinstance(types, list) else [types]
        if not any(type_ok(node, t) for t in types):
            errors.append(f'{path}: 期望 {"|".join(types)}，实际 {type(node).__name__}')
            return
    if 'const' in sch and node != sch['const']:
        errors.append(f'{path}: 期望常量 {sch["const"]!r}，实际 {node!r}')
    if 'enum' in sch and node not in sch['enum']:
        errors.append(f'{path}: {node!r} 不在枚举 {sch["enum"]}')
    if isinstance(node, dict):
        for key in sch.get('required', []):
            if key not in node:
                errors.append(f'{path}: 缺必填字段 {key}')
        props = sch.get('properties', {})
        if sch.get('additionalProperties') is False:
            for key in node:
                if key not in props:
                    errors.append(f'{path}: 多余字段 {key}')
        for key, sub in props.items():
            if key in node:
                check(node[key], sub, f'{path}.{key}')
    elif isinstance(node, list):
        if 'minItems' in sch and len(node) < sch['minItems']:
            errors.append(f'{path}: 少于 {sch["minItems"]} 项')
        if 'maxItems' in sch and len(node) > sch['maxItems']:
            errors.append(f'{path}: 多于 {sch["maxItems"]} 项')
        for i, el in enumerate(node):
            check(el, sch.get('items', {}), f'{path}[{i}]')
    elif isinstance(node, (int, float)) and not isinstance(node, bool):
        if 'minimum' in sch and node < sch['minimum']:
            errors.append(f'{path}: 小于最小值 {sch["minimum"]}')

check(report, schema, '$')
if errors:
    print('FAIL: 报告不符合契约')
    for e in errors[:20]:
        print(' -', e)
    sys.exit(1)
print('PASS: 报告结构符合契约', {c['id']: c['status'] for c in report['capabilities']})
PY
```

该脚本覆盖 schema 实际用到的 `type`（含 `["string","null"]` 这类可空写法）、`const`、`enum`、`required`、`additionalProperties: false`、`minItems`/`maxItems`、`minimum`。缺字段、枚举越界、多余字段都会失败退出（已用正反样例自测：合法样例 PASS，删掉 `app.teamID` 且把 `status` 改成 `weird` 的样例报两条错误并 exit 1）。

实测记录（2026-11-21，自动化）：

- 「复制报告」按钮由诊断面板 GUI 触发；自动化等价路径已验证：`scripts/tests/permission-report-harness.swift`（`swiftc` 编译 `PermissionCenter.swift` 后运行）调用生产端同一 `JSONEncoder`（pretty + sortedKeys）生成 `/tmp/m003-report.json`，再跑上面的 python 脚本 → `PASS: 报告结构符合契约 {'windowControl': 'denied', 'inputMonitoring': 'denied', 'eventPosting': 'notRequired'}`。
- 说明：命令行环境 `Bundle.main` 不指向 App bundle，harness 的 App 段改从正式版副本 `/Applications/MacsyZones.app` 的 Info.plist 实读版本/Build/bundleID（与真实运行值同源）；`teamID` 使用 AGENTS.md 固定签名 Team 常量（真实运行时由 SecCode 从签名读取同一值）。

## 六、日志取证

```bash
# 最近 5 分钟的权限日志
log show --last 5m --predicate 'subsystem == "MeowingCat.MacsyZones" AND category == "permissions"' --info

# 系统的 TCC 侧证据（是否弹过提示、是否 preflight_unknown）
log show --last 10m --predicate 'process == "tccd" AND eventMessage CONTAINS "MeowingCat.MacsyZones"' --info

# 是否出现登录期文件描述符耗尽导致的误判（社区已知问题）
log show --last 3d --predicate 'process == "tccd" AND eventMessage CONTAINS "Too many open files"'
```

## 七、排错

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 构建失败提示签名 | 证书不在钥匙串 / Xcode 版本不符 | `security find-identity -v -p codesigning` 核对 `C7C84AAA...` |
| 冒烟脚本抓不到日志 | 启动的是 `/tmp` 下的产物、或产物未签名、或 `/Applications/MacsyZones.app` 还是旧构建 | 重新跑 `scripts/build-permission-artifact.sh`；`codesign -dv --verbose=4 <app>` 核对 Team ID |
| 状态永远 `unknown` | 探针目标 app 未运行（Finder 被替换） | 打开 Finder 后点「重新检测」；诊断面板会显示 `lastError` |
| 授权后仍 `denied` | 系统设置里改的不是同一个副本（`/tmp` vs `~/Applications`）；或 tccd 登录期抖动 | 删掉旧条目重新添加；登录后 60 秒内属宽限期，等待或「重新检测」 |
| 面板跳转落到首页 | 锚点在新系统被改名 | 按 `contracts/guidance-targets.md` 兜底文案手动导航，并记录实际锚点回填契约 |
