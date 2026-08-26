# 开发与发布

[仓库首页](../README.md) · [文档索引](README.md)

## 环境

- macOS 14+
- Xcode 16+
- XcodeGen
- Python 3（审计脚本）
- Pillow（重新生成图标时需要）

```bash
xcodebuild -version
swift --version
xcodegen --version
```

## 工程

`project.yml` 是工程定义，不要直接修改生成的 `CodexTokenLedger.xcodeproj`。

```bash
xcodegen generate
open CodexTokenLedger.xcodeproj
```

## 测试

```bash
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

界面改动还要运行 `MenuBarVisualSmokeTests.testRenderOverviewForVisualInspection`，并检查 `build/` 中的浅色、深色、详情展开、长数字和多任务截图。

## 构建与打包

```bash
./scripts/build_app.sh
./scripts/package_release.sh
```

输出：

```text
build/DerivedData/Build/Products/Release/CodexTokenLedger.app
dist/CodexTokenLedger.app
dist/CodexTokenLedger-menu-bar-macOS.zip
```

打包脚本使用本地 ad-hoc 签名。公开分发需要 Developer ID 签名和 Apple 公证。

## 本地化

界面文字位于：

```text
Sources/CodexTokenLedger/Resources/Localizable.xcstrings
```

每个 key 需要覆盖：

```text
en, zh-Hans, zh-Hant, ja, ko, es, fr
```

新增文字后检查七种语言在 340pt 宽度下没有截断、换行或缩小。

## 图标

源图：

```text
Design/AppIconMaster.png
Design/BrandMarkMaster.png
```

生成 Asset Catalog：

```bash
/usr/bin/python3 -m pip install Pillow
./scripts/generate_icon.py
```

应用内图标使用透明 PNG Image Assets。

## 审计

Token 事件结构：

```bash
./scripts/audit_token_evidence.py \
  --codex-home "$CODEX_HOME" \
  --output build/token-evidence-audit.json
```

账号 RPC 字段：

```bash
./scripts/audit_account_rpc.py \
  --codex-home "$CODEX_HOME" \
  --output build/account-rpc-schema-audit.json
```

Tibo 公共源：

```bash
./scripts/audit_tibo_signal.sh build/tibo-signal-audit.json
```

前两个脚本不输出聊天正文或凭据值。账号 RPC 审计会使用本机 Codex 的正常凭据源，只能在可信代码状态下手动运行。

## 发布前

1. 更新 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 和 `CHANGELOG.md`。
2. 运行完整测试并检查界面截图。
3. 构建 arm64 与 x86_64 Release。
4. 检查 `lipo -archs`、`codesign --verify` 和 ZIP 完整性。
5. 检查 String Catalog 的七种语言。
6. 确认提交中没有凭据、`.env`、构建目录或真实账号导出。
7. 更新 `VERIFICATION.md`。
