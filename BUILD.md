# MacsyZones 打包规范

## 签名问题说明

### 问题描述
使用 ad-hoc 签名 (`CODE_SIGN_IDENTITY = "-"`) 没有稳定的 Apple Developer 签名身份，且不同构建的 CDHash 可能变化。macOS 的辅助功能授权与应用的 Bundle ID、签名身份和代码要求有关；当这些身份变化，系统可能把应用视为新的客户端并要求重新授权。

### 解决方案
使用固定的 Apple Development 证书、固定的证书 SHA-1、固定的 Team ID 和固定的 Bundle ID。验收时应比较 `Authority`、证书 SHA-1、`Identifier`、`TeamIdentifier` 和 designated requirement；CDHash 是代码内容的哈希，不承诺在不同源码构建之间保持不变。

### 关于开发者账号
**本项目使用免费 Apple 开发者账号**（通过 Xcode 登录 Apple ID 获得），无需付费开发者计划。

免费开发者证书的特点：
- ✅ 可用于本地开发和测试
- ✅ 签名的 app 可以在本机运行
- ✅ Apple Developer 签名身份和 designated requirement 可保持稳定
- ❌ 不能分发给其他设备
- ❌ 不能上传到 App Store

对于本项目的个人使用场景，免费开发者证书完全足够。

---

## 签名配置

### 当前签名证书
```
Apple Development: jie.zhengj@qq.com (8SDSF987N2)
证书 ID: C7C84AAA3B67FACEA73042570A0BA2FC3D19E613
Team ID: 74FR87HYTH
```

### Xcode 项目配置

在 `MacsyZones.xcodeproj/project.pbxproj` 中，所有 Build Configuration（Debug、Release、App Store）需要设置：

```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = "Apple Development: jie.zhengj@qq.com (8SDSF987N2)"
CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development: jie.zhengj@qq.com (8SDSF987N2)"
DEVELOPMENT_TEAM = 74FR87HYTH
```

**重要**：不要使用 ad-hoc 签名 (`"-"`)，也不要改变正式 App 的 Bundle ID。正式验收和日常使用必须使用 `MeowingCat.MacsyZones` 与当前 Apple Development 证书；临时 UI 测试不得通过 `PRODUCT_BUNDLE_IDENTIFIER` 创建另一个客户端，否则会触发新的无障碍授权。

如果 `security find-identity -v -p codesigning` 返回 `0 valid identities found`，不要继续构建或运行 App。打开 Xcode 的 `Settings → Accounts`，选择 `jie.zhengj@qq.com` 对应账户，进入 `Manage Certificates…`，点击 `+ → Apple Development` 创建或恢复证书；然后确认 SHA-1 为 `C7C84AAA3B67FACEA73042570A0BA2FC3D19E613`。不要选择美国区账户，也不要用 ad-hoc 作为替代方案。

### 为什么之前的 Agent 选择 ad-hoc 签名？
之前的 Agent 可能认为：
1. 用户没有付费开发者账号
2. 只是个人使用，不需要分发

但实际上，**免费开发者证书**（通过 Xcode 登录 Apple ID 获得）完全可以满足个人使用需求，并保持稳定的签名身份。ad-hoc 签名无法提供同等的身份保证；更换证书邮箱、Team ID、Bundle ID 或 designated requirement 都可能让 macOS 重新请求无障碍授权。

---

## 构建流程

### 方法 1：Xcode GUI
1. 打开 `MacsyZones.xcodeproj`
2. 选择 `Product → Archive`
3. 在 Organizer 中选择 Archive → `Distribute App`
4. 选择 `Copy App`（免费 Apple Development 证书不能作为 Developer ID 分发证书）
5. 导出 App 文件

### 方法 2：命令行构建
```bash
# 清理并构建 Release 版本
xcodebuild -project MacsyZones.xcodeproj \
  -scheme MacsyZones \
  -configuration Release \
  -derivedDataPath build \
  clean build

# 构建产物位置
# build/Build/Products/Release/MacsyZones.app
```

### 可重复构建并生成 DMG

脚本会检查版本递增级别、`MARKETING_VERSION`、本项目版本台账、钥匙串证书、Bundle ID、签名身份和 DMG 内容。所有中间文件都在 `/tmp`，DMG 也不会进入 Git：

```bash
targetVersion=1.2.6
bumpLevel=patch
bash scripts/build-release-dmg.sh "$targetVersion" "$bumpLevel"
# 输出：/tmp/MacsyZones-v1.2.6.dmg
```

执行 Release 构建前，必须先在 [`RELEASES.md`](RELEASES.md) 登记下一发布目标和级别，并更新 `MARKETING_VERSION`。版本规则和 Major/Minor/Patch 判定见 [`VERSIONING.md`](VERSIONING.md)。

验证已安装 App 或构建产物时，使用同一套正式身份检查：

```bash
bash scripts/verify-signing.sh /Applications/MacsyZones.app
```

脚本固定检查 `MeowingCat.MacsyZones`、`Apple Development: jie.zhengj@qq.com (8SDSF987N2)`、证书 SHA-1 `C7C84AAA3B67FACEA73042570A0BA2FC3D19E613`、`74FR87HYTH` 和 designated requirement，并拒绝 ad-hoc 或无嵌入证书签名；发布脚本也会拒绝通过环境变量覆盖为其他签名身份或 Team ID。

如果 Xcode beta 不在默认路径，可显式指定：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  bash scripts/build-release-dmg.sh "$targetVersion" "$bumpLevel"
```

脚本不会自动修改版本号、创建 tag、提交代码或上传 GitHub Release；但它会拒绝版本号未递增或级别不匹配的 Release 构建。上传前应先人工确认 DMG，再按 [`AGENTS.md`](AGENTS.md) 的完整流程执行发布步骤。

---

## 创建 DMG

### 准备工作目录
```bash
mkdir -p /tmp/MacsyZones-dmg
cp -R build/Build/Products/Release/MacsyZones.app /tmp/MacsyZones-dmg/
ln -sf /Applications /tmp/MacsyZones-dmg/Applications
```

### 创建 DMG 文件
```bash
hdiutil create \
  -volname "MacsyZones" \
  -srcfolder /tmp/MacsyZones-dmg \
  -ov \
  -format UDZO \
  /tmp/MacsyZones-v<target-version>.dmg
```

### 清理临时文件
```bash
rm -rf /tmp/MacsyZones-dmg
```

---

## 验证签名

### 检查签名元数据
```bash
codesign -dv --verbose=4 MacsyZones.app 2>&1 | \
  grep -E "CDHash|Identifier|Authority|TeamIdentifier"

codesign -d -r- MacsyZones.app 2>&1
```

CDHash 仅用于记录具体构建，不要求不同源码构建之间相同。应确认每次正式构建的 `Authority`、证书 SHA-1 `C7C84AAA3B67FACEA73042570A0BA2FC3D19E613`、`Identifier`、`TeamIdentifier` 和 designated requirement 一致。

### 检查签名身份
```bash
codesign -dv --verbose=4 MacsyZones.app 2>&1 | grep "Signature\|Identifier"
```

应显示：
- `Authority=Apple Development: jie.zhengj@qq.com (8SDSF987N2)`
- `Identifier=MeowingCat.MacsyZones`
- `TeamIdentifier=74FR87HYTH`

Xcode 27 的 `codesign -dv` 输出可能不再包含单独的 `Signature=Apple Development` 行；以完整的 `Authority`、`Identifier` 和 `TeamIdentifier` 为准。

---

## 更新 GitHub Release

### 创建新的 Release

代码、资源、配置迁移、构建脚本或签名流程发生变化时，必须创建新的版本和新的 Release：

```bash
targetVersion=1.2.6
gh release create "v${targetVersion}" \
  --repo jiezhengj/MacsyZones \
  --title "MacsyZones 中文定制版 v${targetVersion}" \
  --notes-file /tmp/MacsyZones-release-notes.md

gh release upload "v${targetVersion}" \
  "/tmp/MacsyZones-v${targetVersion}.dmg" \
  --repo jiezhengj/MacsyZones \
  --clobber
```

上传成功并确认资产可下载后，立即删除 `/tmp/MacsyZones-v<target-version>.dmg`。

### 仅修复已有 Release 资产

只有代码 commit、`MARKETING_VERSION`、Git tag 和 Release 正文完全不变，仅 DMG 上传失败或文件损坏时，才允许替换已有资产：

```bash
existingVersion=1.2.5
gh release upload "v${existingVersion}" \
  "/tmp/MacsyZones-v${existingVersion}.dmg" \
  --repo jiezhengj/MacsyZones \
  --clobber
```

资产修复不创建新 tag，不改变版本号，也不能包含代码变更。

---

## 版本管理

- **新代码发布**：必须递增版本号、创建新 tag 和新 GitHub Release。
- **资产修复**：仅在同一代码和同一 tag 下替换 DMG，不递增版本号。
- **代码推送**：推送到 `jiezhengj/MacsyZones` 的 `custom` 分支，绝不推送 `upstream`。
- **版本台账**：维护 [`RELEASES.md`](RELEASES.md)，未成功创建 Release 的版本不能标记为已发布。
- **规则来源**：版本判定使用 [`VERSIONING.md`](VERSIONING.md)，不依赖过程文档。

---

## 常见问题

### Q: 为什么辅助功能权限需要重新授权？
A: 正式 App 的构建必须始终使用相同的 Bundle ID、Team ID、证书和 designated requirement。常见原因是这些身份发生改变；使用临时 Bundle ID 构建 UI 也会产生新的 TCC 客户端。不同源码构建的 CDHash 可以不同，这本身只说明代码内容不同，不能单独作为签名身份是否正确的判断依据。不要为了 UI 自动化临时设置 `PRODUCT_BUNDLE_IDENTIFIER=MeowingCat.MacsyZones.UIHarness` 或其他 Bundle ID；UI 验收必须使用正式的 `MeowingCat.MacsyZones` App。

### Q: 如何避免反复授权？
A: 使用固定的开发者证书、Team ID 和 `MeowingCat.MacsyZones` Bundle ID；将同一个已签名构建安装到 `/Applications/MacsyZones.app` 后再测试；不要同时运行其他 Bundle ID 相同的副本，也不要使用临时 Bundle ID 作为 UI 验收构建。通过 `codesign -d -r-` 检查 designated requirement，而不是要求 CDHash 跨版本不变。

### Q: 可以使用自签名证书吗？
A: 可以，但需要在 Keychain Access 中创建自签名证书，并确保证书名称与 Xcode 配置中的 `CODE_SIGN_IDENTITY` 一致。推荐使用 Apple Developer 证书。

---

## 相关文件

- `MacsyZones.xcodeproj/project.pbxproj` - Xcode 项目配置
- `MacsyZones/MacsyZones.entitlements` - 应用权限配置
- `VERSIONING.md` - 版本级别与递增规则
- `RELEASES.md` - 本项目版本台账
