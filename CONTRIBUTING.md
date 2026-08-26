# 贡献指南

## 开始

```bash
git clone <repository-url>
cd CodexTokenLedger
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

## 修改原则

- 保持 Codex 原始计数、服务端返回值、确定性派生和估算之间的边界。
- 缺少必要字段时返回不可用，不猜测 Token 拆分、账号额度或部分费用。
- 不读取、保存或输出与当前统计无关的聊天正文和凭据值。
- `project.yml` 是 Xcode 工程来源；不要提交生成的 `.xcodeproj`。
- 所有用户可见字符串必须进入 String Catalog，并覆盖七种受支持语言。
- 菜单主页面保持 340×705pt、无滚动条、最小 12pt 字号、单行不缩放。
- 界面变更必须检查浅色、深色、展开详情、长数字和多任务状态。
- 内部图标使用项目 PNG Image Assets；不要引入运行时 SVG。

## 提交前

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

同时确认：

- `git status --ignored` 中的 `build/`、`dist/` 和 `.xcodeproj/` 未被加入；
- 没有 `auth.json`、Token、API key、Cookie 或 `.env`；
- 变更涉及的规范文档和测试已同步更新；
- 不依赖真实账号或网络的测试可以离线运行。
