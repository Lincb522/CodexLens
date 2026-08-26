# Codex Token Ledger

macOS 菜单栏里的 Codex 用量查看器。应用内名称为 **Token Pulse**，没有主窗口，也不会出现在 Dock 中。

<p align="center">
  <img src="docs/images/overview-light.png" width="340" alt="Token Pulse 概览">
</p>

## 能看到什么

- 当前任务最近一次模型请求的上下文输入、缓存输入和输出
- 当前轮次与整个任务的累计 Token
- 多个运行中任务及其真实标题
- 本机历史会话的 Token 总量
- 当前账号的用量、额度窗口和重置时间
- 按 API 费率折算的参考成本
- Tibo 公共重置信号

Token 详情会把“本次请求”“当前轮次”和“任务累计”分开显示：

<p align="center">
  <img src="docs/images/token-details-light.png" width="340" alt="Token 明细">
</p>

## 数据来源

| 项目 | 来源 |
| --- | --- |
| 当前上下文 | rollout 中最新的 `last_token_usage` |
| 当前轮次 | 本轮累计事件的有效增量 |
| 任务累计 | 最新的 `total_token_usage` |
| 本地历史 | `sessions` 与可选的 `archived_sessions` |
| 账号用量与额度 | Codex `app-server` |
| 参考成本 | 完整 Token 明细 × 内置费率 |
| 剩余时间 | 同一额度窗口的本地历史样本 |

缺少必要字段时，界面显示“不可用”。应用不会根据字符数猜 Token，也不会用本地会话推断账号额度。完整口径见 [Token 计算](docs/calculation-spec.md)。

## 账号

支持以下添加方式：

- Codex OAuth
- 已有 Codex Home
- 原始 Token 或 API Key
- `auth.json`
- JSON / JSONL
- Sub2
- CPA / CLIProxyAPI
- Cockpit

切换账号时可选择“仅监控”或“登录到 Codex”。只有后者会改动默认 Codex Home 的登录状态，写入前会创建本地备份。

## 环境

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Codex CLI（账号用量与登录切换需要）

## 构建

```bash
git clone https://github.com/Lincb522/CodexTokenLedger.git
cd CodexTokenLedger
xcodegen generate
./scripts/build_app.sh
```

应用位于：

```text
build/DerivedData/Build/Products/Release/CodexTokenLedger.app
```

打包本地 ad-hoc 签名版本：

```bash
./scripts/package_release.sh
```

输出到 `dist/`。公开分发仍需 Developer ID 签名和 Apple 公证。

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
