<p align="center">
  <img src="Design/AppIconMaster.png" width="112" alt="Codex Token Ledger">
</p>

<h1 align="center">Codex Token Ledger</h1>

| 概览 | Token 明细 |
| :---: | :---: |
| <img src="docs/images/overview-light.png" width="340" alt="概览"> | <img src="docs/images/token-details-light.png" width="340" alt="Token 明细"> |

## 功能

- 当前请求：输入、缓存输入、输出、上下文占用
- 当前轮次：本轮所有模型调用
- 任务累计：当前任务的累计 Token
- 多任务：发现正在运行的任务并切换
- 本地历史：统计 `sessions` 和 `archived_sessions`
- 账号：用量、额度窗口、重置时间、剩余时间
- 费用：按请求和模型费率折算
- Tibo：预测与确认的公共重置信号

## 数据口径

| 项目 | 取值 |
| --- | --- |
| 当前请求 | 最新 `last_token_usage` |
| 当前轮次 | 本轮 `total_token_usage` 的有效增量 |
| 任务累计 | 最新 `total_token_usage` |
| 本地历史 | 每个已索引会话的最终累计值 |
| 账号用量 | Codex `app-server` |
| 费用 | 完整 Token 明细 × 模型费率 |
| 剩余时间 | 同一账号、同一额度窗口的历史样本 |

无法确认的字段显示“不可用”。不按字符数估算 Token，不用本地会话推算账号额度。详细规则见 [Token 计算](docs/calculation-spec.md)。

## 账号

导入格式：

- Codex OAuth
- Codex Home
- Token / API Key
- `auth.json`
- JSON / JSONL
- Sub2
- CPA / CLIProxyAPI
- Cockpit

切换方式：

- **仅监控**：不修改 Codex 当前登录
- **登录到 Codex**：备份后替换默认 Codex Home 的登录

## 构建

依赖：macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。账号功能需要 Codex CLI。

```bash
git clone https://github.com/Lincb522/CodexTokenLedger.git
cd CodexTokenLedger
xcodegen generate
./scripts/build_app.sh
```

```text
build/DerivedData/Build/Products/Release/CodexTokenLedger.app
```

打包：

```bash
./scripts/package_release.sh
```

`package_release.sh` 使用 ad-hoc 签名。公开分发需要 Developer ID 签名和 Apple 公证。

## 测试

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

## 文档

- [文档索引](docs/README.md)
- [产品约束](PRODUCT.md)
- [界面规范](DESIGN.md)
- [系统结构](docs/architecture.md)
- [Token 计算](docs/calculation-spec.md)
- [开发与发布](docs/development.md)
- [验证记录](VERIFICATION.md)
- [安全说明](SECURITY.md)

## 开发者

Zijiu522

## 许可

本项目暂未声明开源许可证。第三方内容见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
