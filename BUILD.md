# MacsyZones 打包规范

## 签名问题说明

### 问题描述
使用 ad-hoc 签名 (`CODE_SIGN_IDENTITY = "-"`) 会导致每次构建生成不同的签名哈希（CDHash）。macOS 根据签名哈希识别应用身份，哈希变化意味着系统认为这是一个"新"应用，需要重新授权辅助功能权限。

### 解决方案
使用固定的 Apple Developer 证书签名，确保每次构建生成相同的签名哈希。

### 关于开发者账号
**本项目使用免费 Apple 开发者账号**（通过 Xcode 登录 Apple ID 获得），无需付费开发者计划。

免费开发者证书的特点：
- ✅ 可用于本地开发和测试
- ✅ 签名的 app 可以在本机运行
- ✅ 签名哈希保持稳定（不会每次变化）
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

**重要**：不要使用 ad-hoc 签名 (`"-"`)，它会导致签名哈希每次变化。

### 为什么之前的 Agent 选择 ad-hoc 签名？
之前的 Agent 可能认为：
1. 用户没有付费开发者账号
2. 只是个人使用，不需要分发

但实际上，**免费开发者证书**（通过 Xcode 登录 Apple ID 获得）完全可以满足个人使用需求，且签名哈希稳定。ad-hoc 签名的问题是每次构建都会生成不同的哈希，导致 macOS 认为是新应用，需要重新授权。

---

## 构建流程

### 方法 1：Xcode GUI
1. 打开 `MacsyZones.xcodeproj`
2. 选择 `Product → Archive`
3. 在 Organizer 中选择 Archive → `Distribute App`
4. 选择 `Developer ID` 或 `Copy App`（用于本地分发）
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
  MacsyZones-1.0.dmg
```

### 清理临时文件
```bash
rm -rf /tmp/MacsyZones-dmg
```

---

## 验证签名

### 检查签名哈希
```bash
codesign -dv --verbose=4 MacsyZones.app 2>&1 | grep CDHash
```

每次构建后，CDHash 应该保持一致（使用相同证书签名时）。

### 检查签名身份
```bash
codesign -dv --verbose=4 MacsyZones.app 2>&1 | grep "Signature\|Identifier"
```

应显示：
- `Signature=Apple Development`
- `Identifier=MeowingCat.MacsyZones`

---

## 更新 GitHub Release

### 上传新 DMG
```bash
# 删除旧的 DMG 资源
gh release delete-asset v1.0 MacsyZones-1.0.dmg --repo jiezhengj/MacsyZones --yes

# 上传新的 DMG
gh release upload v1.0 MacsyZones-1.0.dmg --repo jiezhengj/MacsyZones --clobber
```

---

## 版本管理

- **版本号不变**：仅更新 DMG 文件，不创建新的 Git tag
- **代码推送**：推送到 `jiezhengj/MacsyZones` 的 `custom` 分支
- **Release 更新**：使用 `gh release` 命令更新现有 release 的资源文件

---

## 常见问题

### Q: 为什么辅助功能权限需要重新授权？
A: macOS 根据应用的签名哈希（CDHash）识别应用。如果哈希变化，系统认为是新应用，需要重新授权。

### Q: 如何确保签名哈希一致？
A: 使用固定的开发者证书签名（不要使用 ad-hoc 签名），并且确保每次构建使用相同的证书和 Team ID。

### Q: 可以使用自签名证书吗？
A: 可以，但需要在 Keychain Access 中创建自签名证书，并确保证书名称与 Xcode 配置中的 `CODE_SIGN_IDENTITY` 一致。推荐使用 Apple Developer 证书。

---

## 相关文件

- `MacsyZones.xcodeproj/project.pbxproj` - Xcode 项目配置
- `MacsyZones/MacsyZones.entitlements` - 应用权限配置
- `MacsyZones-1.0.dmg` - 分发包文件
