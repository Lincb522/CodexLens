# 验证记录

[← README](README.md) · [文档](docs/README.md)

---

版本：**2.1.0 (22)**

日期：**2026-08-27**

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

结果：73 项测试，72 项通过，1 项网络测试跳过，0 项失败。

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
- 菜单宽 340pt，主页面高 705pt
- 主页面无 `ScrollView`
- 详情展开前后菜单尺寸不变
- 可见字号不小于 12pt
- SwiftUI 根背景透明
- 浅色、深色和跟随系统可即时切换
- 应用内图标不使用 SVG

## Release

[GitHub Release v2.1.0](https://github.com/Lincb522/CodexTokenLedger/releases/tag/v2.1.0)

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
codesign --verify --deep --strict --verbose=2 dist/CodexTokenLedger.app
lipo -archs dist/CodexTokenLedger.app/Contents/MacOS/CodexTokenLedger
unzip -t dist/CodexTokenLedger-menu-bar-macOS.zip
```

验证结果：

| 项目 | 结果 |
| --- | --- |
| 架构 | `x86_64 arm64` |
| 签名 | 本地 ad-hoc，有效 |
| ZIP | 完整性通过 |
| MIT 许可 | 已写入应用资源，内容与仓库 `LICENSE` 一致 |
| Tibo Watch 许可 | 已随应用打包 |

产物：

| 文件 | SHA-256 |
| --- | --- |
| `CodexTokenLedger` | `1cbed7c15477c2dd0b8783aebf9d91c305dd1d6564b891f4b4997c6688a30f0c` |
| `CodexTokenLedger-menu-bar-macOS.zip` | `f2ecfd06973cfce38576b109ad3acd5bb8b4634069d482c1e8cda56c42daaf31` |

ZIP 大小：4,448,293 bytes。当前包未经过 Apple 公证。
