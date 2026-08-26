# 开发与发布

## 环境

- macOS 14+
- Xcode 16+
- XcodeGen
- Python 3（审计脚本）
- Pillow（仅重新生成图标时需要）

确认工具：

```bash
xcodebuild -version
swift --version
xcodegen --version
/usr/bin/python3 --version
```

## 生成工程

`project.yml` 是工程定义的唯一来源。不要直接修改生成后的 `CodexTokenLedger.xcodeproj`。

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

主要测试分区：

- Token 结构校验、累计值和费用；
- rollout 读取、并发任务与标题来源；
- 本地会话扫描和缓存；
- 账号 RPC 与额度解析；
- Token/JSON/JSONL/Sub2/CPA/Cockpit 导入；
- 凭据原子写入与回滚；
- 额度剩余时间预测；
- Tibo 规则和周期状态机；
- 七种语言与菜单视觉约束。

`MenuBarVisualSmokeTests.testRenderOverviewForVisualInspection` 会把界面夹具输出到 `build/`。检查浅色、深色、展开详情、长数字和固定 340pt 宽度后再提交界面变更。

## 构建

```bash
./scripts/build_app.sh
```

脚本生成 arm64+x86_64 Release 应用，路径为：

```text
build/DerivedData/Build/Products/Release/CodexTokenLedger.app
```

## 打包

```bash
./scripts/package_release.sh
```

输出：

```text
dist/CodexTokenLedger.app
dist/CodexTokenLedger-menu-bar-macOS.zip
```

该脚本只执行本地 ad-hoc 签名。公开分发前仍需使用 Developer ID 签名并完成 Apple 公证。

## 本地化

所有用户可见字符串必须进入：

```text
Sources/CodexTokenLedger/Resources/Localizable.xcstrings
```

每个 key 必须显式覆盖：

```text
en, zh-Hans, zh-Hant, ja, ko, es, fr
```

新增文案后运行完整测试，确认没有返回 key 本身，也没有在 340pt 布局中被截断、换行或缩小。

## 图标

源文件：

```text
Design/AppIconMaster.png
Design/BrandMarkMaster.png
```

重新生成 Asset Catalog 尺寸：

```bash
/usr/bin/python3 -m pip install Pillow
./scripts/generate_icon.py
```

应用内图标是透明 PNG Image Assets，不在运行时使用 SVG。

## 审计脚本

### Token 结构

```bash
./scripts/audit_token_evidence.py \
  --codex-home "$CODEX_HOME" \
  --output build/token-evidence-audit.json
```

脚本只检查 `token_count` 结构，不读取或输出聊天正文。

### 账号 RPC

```bash
./scripts/audit_account_rpc.py \
  --codex-home "$CODEX_HOME" \
  --output build/account-rpc-schema-audit.json
```

输出只保留字段结构，不保留字段值。该脚本会让本机 Codex 使用正常凭据源；不要在不受信任的构建环境中运行。

### Tibo 公开数据源

```bash
./scripts/audit_tibo_signal.sh build/tibo-signal-audit.json
```

该命令访问公开网络源，只应在需要验证实时来源时运行。

## 发布检查

1. 更新 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 和 `CHANGELOG.md`。
2. 运行完整测试并检查视觉夹具。
3. 执行 Release 通用构建。
4. 检查 `lipo -archs`、`codesign --verify` 和 ZIP 完整性。
5. 确认 String Catalog 七种语言没有缺失项。
6. 确认提交中没有 `auth.json`、Token、API key、`.env`、构建目录或真实账号导出。
7. 更新 `VERIFICATION.md` 中的最终命令、哈希和已验证范围。
