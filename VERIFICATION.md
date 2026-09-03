# 验证记录

[← README](README.md) · [文档](docs/README.md)

---

版本：**2.4.1 (41)**

日期：**2026-09-03**

工具：**Xcode 26.4 / Swift 6.3**

## 测试

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

结果：125 项测试，124 项通过，1 项网络测试跳过，0 项失败。

覆盖范围：

- rollout Token 解析、去重和累计回退
- 当前请求、当前轮次与任务累计
- 多任务发现和标题来源
- 账号 RPC、额度窗口与剩余时间预测
- Token、JSON、JSONL、Sub2、CPA 和 Cockpit 导入
- GPT-5.6 单次请求超长上下文费率
- Tibo 来源过滤和周期状态
- 七种语言
- 菜单尺寸、主题、详情展开和长数字布局

## 界面

已检查以下仓库内截图：

```text
docs/images/overview-light.png
docs/images/token-details-light.png
```

固定条件：

- `NSStatusItem` + 原生 `NSMenu`
- 菜单宽 340pt，所有页面高 740pt
- 主页面无 `ScrollView`
- 详情展开前后菜单尺寸不变
- 可见字号不小于 12pt
- SwiftUI 根背景透明
- 浅色、深色和跟随系统可即时切换
- 应用内图标不使用 SVG

## Release

[GitHub Release v2.4.1](https://github.com/Lincb522/CodexLens/releases/tag/v2.4.1)

```bash
xcodebuild \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

./scripts/package_release.sh
codesign --verify --deep --strict --verbose=2 "dist/Codex Lens.app"
lipo -archs "dist/Codex Lens.app/Contents/MacOS/Codex Lens"
unzip -t dist/Codex-Lens-macOS.zip
```

本地 Release 构建验证：

| 项目 | 结果 |
| --- | --- |
| 架构 | `x86_64 arm64` |
| 应用名称 | `Codex Lens` |
| 可执行文件 | `Codex Lens` |
| Bundle ID | `com.tokenledger.CodexTokenLedger`（保持不变，兼容既有安装） |
| 版本 | `2.4.1 (41)` |

`v*` tag 工作流生成 Developer ID 签名、未经 Apple 公证的 DMG 与 ZIP；手动触发工作流可选择提交公证。
