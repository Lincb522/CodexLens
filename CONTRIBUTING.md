# 参与开发

## 准备

```bash
git clone https://github.com/Lincb522/CodexTokenLedger.git
cd CodexTokenLedger
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

## 提交要求

- 保留原始计数、服务端数据、确定性计算和估算之间的区别。
- 字段不足时返回不可用，不猜测 Token 明细、账号额度或费用。
- 不读取或输出统计之外的聊天正文和凭据值。
- 修改 `project.yml`，不要提交生成的 `.xcodeproj`。
- 界面文字进入 String Catalog，并覆盖七种语言。
- 主页面保持 340×705pt、无滚动条、字号不小于 12pt。
- 界面改动检查浅色、深色、详情展开、长数字和多任务状态。
- 应用内图标使用 PNG Image Assets。

提交前重新运行完整测试，并确认 Git 中没有：

- `build/`、`dist/` 或生成的 `.xcodeproj`
- `auth.json`、Token、API Key、Cookie 或 `.env`
- 真实账号导出
