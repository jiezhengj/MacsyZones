**Feature**：`003-macos27-permissions` | **环境基准**：macOS 27.3（本机 Build `26C5047e`，Apple Silicon）、Xcode 27.2、正式开发证书 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)` / Team `74FR87HYTH`。

## 前置条件

1. 已安装 Xcode 27.2（`/Applications/Xcode.app`），`xcode-select -p` 指向它。
2. 钥匙串里有上述开发证书（`security find-identity -v -p codesigning` 能看到 `C7C84AAA3B67FACEA73042570A0BA2FC3D19E613`）。
3. 需要真实授权的场景，必须使用**路径固定的已签名副本** `~/Applications/MacsyZones-dbg.app`（由 `scripts/build-permission-artifact.sh` 产出）；不能直接用 `/tmp` 下的产物——TCC 按 app 身份与路径记录授权，`/tmp` 路径会按另一个条目处理，且可能触发 translocation。
4. 每次重新构建都会改变二进制，系统设置里的旧授权条目可能失效：跑手动矩阵前先重新构建，并在面板里确认条目存在。
5. 验证会改动系统隐私设置，请自行决定是否执行场景 C/E/F。

## 一、构建

### 1.1 编译校验（会清理产物）

```bash
cd /Users/jiezhengj/Documents/Project/MacsyZones
bash scripts/build-debug.sh
```

期望输出结尾：`** BUILD SUCCEEDED **`，以及 `PASS: 正式签名 Debug 构建完成（Bundle ID: MeowingCat.MacsyZones）`；`warning:` 计数应为 0。该脚本用 `trap cleanup EXIT` 删除派生数据，**跑完没有可启动产物** —— 这是正常的，可启动副本用下一步。

### 1.2 可反复启动的验证副本

```bash
bash scripts/build-permission-artifact.sh
```

脚本行为（`research.md` R14）：`xcodebuild -configuration Debug -derivedDataPath /tmp/m003-debug` 构建 → 覆盖复制到 `~/Applications/MacsyZones-dbg.app` → `bash scripts/verify-signing.sh ~/Applications/MacsyZones-dbg.app`。

期望输出：`BUILD SUCCEEDED`、`verify-signing.sh` 的 `PASS: 正式签名身份…均一致`、以及脚本末行 `PASS: 验证副本已生成（~/Applications/MacsyZones-dbg.app）`，且该目录存在。

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

脚本行为：启动 `~/Applications/MacsyZones-dbg.app`（若不存在则先调用 `scripts/build-permission-artifact.sh`）→ 等待 20 秒 → 用 `log show` 抓 `subsystem == "MeowingCat.MacsyZones" AND category == "permissions"` → 断言至少一条含 `capability=windowControl`、`status=`、`trigger=launch`、`latencyMs=` 且 `latencyMs < 1000` 的记录、进程存活、无 `fatal error` → 结束进程。

期望输出：`PASS: 权限日志与进程状态正常（<N> 条权限记录）`。

## 四、手动验证矩阵

每个场景记录三列：预期状态、实际状态、备注。带 🔑 的场景必须使用 `~/Applications/MacsyZones-dbg.app` 并在真实辅助功能授权下执行。

### 场景 A：首次未授权启动（关键，🔑）

1. 先移除授权：系统设置 → 隐私与安全性 → System & App Protection Override（或无障碍）→ 若列表中有 MacsyZones，关闭开关。
2. 启动 `~/Applications/MacsyZones-dbg.app`。

预期：

- 不出现**阻塞式**模态框；主界面可用，菜单栏图标在。
- 引导面板/横幅出现，文案包含「System & App Protection Override」（27.3+），并有「打开系统设置」「重新检测」按钮。
- 点「打开系统设置」→ 系统设置停在对应面板（不是首页）。
- 日志可见 `capability=windowControl status=denied`（或 `unknown`）`trigger=launch`。
- 应用不退出、不崩溃。
- 若确实存在「必须重启」的限制，只提示一次并说明原因；连续两次启动不重复提示（FR-009）。

实测记录（2026-11-21，macOS 27.3 Build 26C5047e，本机当时本 bundle 即处于未授权态，故未做撤销授权步骤、直接复现了本场景的未授权路径；自动化部分已验，🔑 人工部分见下）：

- 已自动化验证（`~/Applications/MacsyZones-dbg.app`，两次启动各观察 20 秒以上）：
  - 应用不崩溃、不退出：`kill`（SIGTERM）前进程稳定运行，退出后无残留。
  - 日志：首轮 `trigger=launch` 全部探针 `status=denied`（frontmost `axError=-25211`、api/preflight 同 denied），汇总 `capability=windowControl status=denied`；随后 `trigger=poll` 每 5 秒复核（与 R4 的 5s×24 一致）。
  - 探针延迟：单探针 `latencyMs` 最大 84（远小于 1000 阈值）。
  - 未授权引导出现：`CGWindowList` 检测到 MacsyZones 面板（420×700，layer 3，左半区），即非模态 `AccessibilityDialog` 骨架——未弹阻塞式模态（T016 已去 `.screenSaver` 级别与 `exit(0)`）。
  - 面板出现时机：首轮探测完成之后（启动后约 1 秒内），未抢焦点。
- 留待人工（需解锁桌面/真实交互）：
  - 面板文案与「打开系统设置」「重新检测」按钮的人工确认（验证期间屏幕处于锁屏，截图只见锁屏界面）。
  - 点「打开系统设置」后系统设置实际停留的面板（同时验证 R12 第 2 条的面板归属）。
  - 授权后不闪引导（场景 B）：本机当前未授权，无法复现 granted 首启。
  - 撤销授权开关的实际位置（若列表中有 MacsyZones 的话）。

### 场景 B：授权后自动恢复（关键，🔑）

1. 承接场景 A，在系统设置里把 MacsyZones 加入/打开授权。
2. 不重启 app，切回 MacsyZones（触发 `didActivateApplication`）。

预期：

- 10 秒内（或点「重新检测」后 2 秒内）状态变 `granted`：引导消失、横幅消失。
- 日志出现 `status=granted trigger=activate`（或 `manual`）。
- 拖动窗口吸附功能立即可用（拖一个窗口到屏幕边缘，出现分区高亮）。

### 场景 C：运行中撤销权限（🔑）

1. 场景 B 之后（进程已运行超过 60 秒），回到系统设置关闭 MacsyZones 的授权。
2. 回到 MacsyZones 操作一次（拖动窗口，或点菜单栏图标）。

预期：

- **没有 60 秒静默期**：运行期撤销属确定性操作，10 秒内识别并降级为「暂停吸附」，横幅/诊断显示未授权。机制是「交互触发即时复核（拖动触发 AX 失败 → `reportAXFailure`，或点菜单/诊断面板）；无交互时，首次识别只能靠 `granted` 期间那条 30 秒轮询（最坏 30 秒），识别失败后转 5 秒轮询 ×24 次兜底」（`research.md` R4、`data-model.md` 状态机）。
- 应用不崩溃；再次授权后自动恢复（回到场景 B 的预期）。
- 反向验证宽限只用于登录期：杀掉进程后立刻在授权仍有效的情况下重启，前 60 秒内即使探针短暂 `denied` 也不得出现未授权提示（结合场景 G 一起看）。

实测记录（2026-11-21，**未实机验证**：本机该 bundle 当前处于未授权态，无法执行「先授权再撤销」的完整流程；真实授权/撤销操作留待人工）：

- 机制口径（实现已落地，供人工验证时对照）：场景 B 的识别路径是「未授权期间 5 秒轮询（5s×最多 24 次）+ didActivateApplication/didWake/didBecomeKey/菜单栏点击即时复核」，授权后应在 ≤10 秒内（点「重新检测」≤2 秒）变 granted；场景 C（进程已运行超过 60 秒）运行期撤销后，无交互时靠 granted 期间的 30 秒轮询识别（最坏 30 秒，符合 R4 口径），有交互（拖动触发 AX 失败 → `reportAXFailure`，或点菜单栏/「重新检测」）时即时复核（≤10 秒，目标 2 秒）。
- 已自动化的替代证据：`App.swift` 接线处已挂 `didActivateApplication`/`didWake`/`didBecomeKey`/菜单栏点击/`reportAXFailure` → `recheck(trigger:)`（编译通过 + 源码核对）；未授权态下 `trigger=poll` 每 5 秒复核节奏已实机日志验证（见场景 A 实测记录）。
- 留待人工：① 授权后 granted 的实际到达耗时（≤10 秒）；② 运行期撤销后的降级耗时（无交互 ≤30 秒 / 拖动交互 ≤10 秒）；③ granted→denied 切换后菜单栏红点与横幅是否同步出现；④ 再次授权后不重启即恢复（场景 B 恢复路径）。

### 场景 D：27.2 → 27.3 升级保持授权

需在另一台（或降级后的）机器：27.2 上授权 → 升级到 27.3 → 启动。

预期：无需重新授权即可用（苹果声明「已授予的权限保持不变」）；若实际要求重新授权，把实测结果写进 `research.md` R12 与 `spec.md` 的假设段落，并在引导里补一句说明。**本机已升级到 27.3，此场景只能标注「未实机验证」或由用户提供第二台机器。**

### 场景 E：per-target 部分可用（🔑）

1. 授权后分别尝试吸附 Finder 窗口与 Safari 窗口（27.3 beta 2 已知问题：Override app 可能无法与 WebKit app 交互）。

预期：诊断面板如实显示「部分目标受控」；不可控的目标吸附失败时不崩溃、不刷错误日志；`notes` 里出现对应说明。

### 场景 F：输入监听关闭 与 窗口控制关闭（🔑，两个方向都验）

**F1 只关输入监控**：系统设置 → 隐私与安全性 → 输入监控（Input Monitoring）中关闭 MacsyZones → 重启 app。

预期：`inputMonitoring=denied`、`windowControl=granted`；**鼠标拖动吸附照常可用**；仅修饰键/吸附键驱动的布局切换与吸附键组合暂停，横幅说明「缺少输入监控」；Carbon 全局快捷键仍工作。重新打开输入监控后**不重启**也应恢复键盘功能（`research.md` R13 的补装路径）。

**F2 只关窗口控制**：系统设置 → 隐私与安全性 → System & App Protection Override（27.3+）或 Device Control and Data Access（27.0–27.2，旧称「辅助功能」）中关闭 MacsyZones → 重启 app。

预期：`windowControl=denied`、`inputMonitoring=granted`；鼠标拖动/悬停高亮/右键菜单不工作且不弹崩溃；Carbon 快捷键仍工作；布局编辑器可打开、保存时提示只读；横幅指向正确面板。重新打开后**不重启**应恢复拖动（鼠标类监视器按 `windowControl` 状态补装）。

> 反向回归：F1 不得出现「拖动失效」，F2 不得出现「键盘切换仍报缺输入监控」——两条都是评审发现的绑定错位，必须各验一次。

### 场景 G：已授权用户多次登录不误报（SC-003）

1. 在已授权状态下注销并重新登录 5 次（或用 `killall MacsyZones` + 重新启动模拟启动路径，但登录项路径必须真登录）。
2. 每次登录后 30 秒内观察：是否出现权限引导/横幅。

预期：5 次均不出现「未授权」提示；权限日志中 `trigger=launch` 且 `status=denied` 的记录为 0。若某次出现误判，记录当时 `tccd` 是否伴随 `Too many open files`（登录期文件描述符耗尽），并作为宽限窗口是否足够的依据。

### 场景 H：从 `/tmp` 运行与 translocation（SC-004）

1. 把构建产物拷到 `/tmp/mz-tmp-run/MacsyZones.app` 直接启动。
2. 观察诊断面板 `app.path` 与 `isTranslocated`。

预期：`path` 如实显示 `/tmp/...`；若 macOS 对 `/tmp` 位置做 translocation，`isTranslocated=true`；状态允许为 `denied`（未授权属正常），但面板必须解释清楚，且不崩溃。此场景用于验证诊断面板能区分「路径问题」与「权限问题」。

### 场景 I：登录项启动（SC-004）

1. 在设置中把 MacsyZones 设为登录项（若产品已有该开关）或手工加入系统设置的登录项。
2. 注销重登，观察诊断面板 `app.isLoginItem` 与首次检测时机。

预期：`isLoginItem=true`；登录后首轮检测不早于窗口观察就绪，且无「未知」造成的引导闪现。

### 场景 J：性能采样（SC-005）

```bash
PID=$(pgrep -x MacsyZones | head -1)
sample "$PID" 30 -file /tmp/m003-sample.txt >/dev/null 2>&1
grep -n "PermissionProbe\|permissionProbe" /tmp/m003-sample.txt | head
top -pid "$PID" -l 5 -stats pid,cpu | tail -6
```

预期：`sample` 结果里探针不出现在主线程栈顶（都在后台队列）；`top` 的闲置 CPU 平均值 ≤ 2%。

### 场景 K：27.0–27.2 旧形态手工验证（SC-006）

**前置**：需要一台仍在 27.0–27.2 的机器（本机已是 27.3，无法降级）。若没有可用机器，本场景**必须标注「未实机验证」**，不得写成已验证（标注方式同场景 D，见 `tasks.md` T042；T039 只负责场景 D 的升级路径标注）。

1. 在同一份构建产物上确认引导文案指向 **Device Control and Data Access**（不是 27.3 的 `System & App Protection Override`）。
2. 点击引导按钮，确认打开的是 `Privacy_Accessibility` 面板（`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`），且授权后 `windowControl` 变为 `granted`。
3. 确认深链失败时回退到 `privacyRoot`（隐私与安全性根面板）。

预期：三处行为与 27.3+ 分支表格一致（`research.md` R3 的两套映射）；诊断报告 `system.productVersion` 落在 `27.0`–`27.2` 时走 `legacyAccessibility` 分支。

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
| 冒烟脚本抓不到日志 | 启动的是 `/tmp` 下的产物、或产物未签名、或 `~/Applications/MacsyZones-dbg.app` 还是旧构建 | 重新跑 `scripts/build-permission-artifact.sh`；`codesign -dv --verbose=4 <app>` 核对 Team ID |
| 状态永远 `unknown` | 探针目标 app 未运行（Finder 被替换） | 打开 Finder 后点「重新检测」；诊断面板会显示 `lastError` |
| 授权后仍 `denied` | 系统设置里改的不是同一个副本（`/tmp` vs `~/Applications`）；或 tccd 登录期抖动 | 删掉旧条目重新添加；登录后 60 秒内属宽限期，等待或「重新检测」 |
| 面板跳转落到首页 | 锚点在新系统被改名 | 按 `contracts/guidance-targets.md` 兜底文案手动导航，并记录实际锚点回填契约 |
