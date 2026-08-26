<p align="center">
  <img src="Design/AppIconMaster.png" width="112" alt="Codex Token Ledger 图标">
</p>

<h1 align="center">Codex Token Ledger</h1>

<p align="center">
  macOS 菜单栏里的 Codex 上下文与用量查看器
</p>

<p align="center">
  macOS 14+ &nbsp;·&nbsp; SwiftUI + AppKit &nbsp;·&nbsp; 7 种语言
</p>

---

Codex Token Ledger 只驻留在菜单栏。应用内显示名为 **Token Pulse**，没有主窗口，也不会出现在 Dock 中。

## 界面

| 实时上下文 | Token 明细 |
| :---: | :---: |
| <img src="docs/images/overview-light.png" width="340" alt="Token Pulse 实时上下文"> | <img src="docs/images/token-details-light.png" width="340" alt="Token Pulse Token 明细"> |

## 功能

- **当前请求** — 输入、缓存输入、输出与上下文占用
- **当前轮次** — 同一轮内多次模型调用的有效增量
- **任务累计** — 当前任务最新的累计 Token
- **多任务** — 自动发现运行中的任务并读取真实标题
- **本地历史** — 汇总 `sessions` 与可选的 `archived_sessions`
- **账号用量** — 读取 Codex `app-server` 返回的累计用量与额度窗口
- **费用** — 按单次请求和内置 API 费率折算参考成本
- **Tibo 信号** — 单独显示公共重置信号，不与账号周期混合

## 数字从哪里来

| 显示内容 | 数据来源 | 类型 |
| --- | --- | --- |
| 当前上下文 | `last_token_usage` | Codex 原始事件 |
| 当前轮次 | 本轮累计事件的有效差值 | 确定性计算 |
| 任务累计 | `total_token_usage` | Codex 原始事件 |
| 本地历史 | 已索引会话的最终累计值 | 确定性汇总 |
| 账号用量与额度 | Codex `app-server` | 官方账号数据 |
| 参考成本 | 完整 Token 明细 × 内置费率 | 估算 |
| 剩余时间 | 同一额度窗口的历史样本 | 估算 |

缺少必要字段时显示“不可用”。应用不会根据字符数猜 Token，也不会用本地会话推断账号额度。计算细节见 [Token 计算](docs/calculation-spec.md)。

## 账号

支持 Codex OAuth、已有 Codex Home、原始 Token、API Key、`auth.json`、JSON / JSONL、Sub2、CPA / CLIProxyAPI 和 Cockpit。

切换账号时有两个独立动作：

| 操作 | 结果 |
| --- | --- |
| 仅监控 | 读取该账号的数据，不改变 Codex 当前登录 |
| 登录到 Codex | 备份当前凭据后，替换默认 Codex Home 的登录 |

## 构建

需要 macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。账号功能还需要本机 Codex CLI。

```bash
git clone https://github.com/Lincb522/CodexTokenLedger.git
cd CodexTokenLedger
xcodegen generate
./scripts/build_app.sh
```

应用输出到：

```text
build/DerivedData/Build/Products/Release/CodexTokenLedger.app
```

生成本地 ad-hoc 签名的应用与 ZIP：

```bash
./scripts/package_release.sh
```

公开分发仍需 Developer ID 签名和 Apple 公证。

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

| 文档 | 内容 |
| --- | --- |
| [文档索引](docs/README.md) | 全部项目文档 |
| [产品约束](PRODUCT.md) | 数据、账号与界面边界 |
| [界面规范](DESIGN.md) | 尺寸、层级、颜色和动画 |
| [系统结构](docs/architecture.md) | 组件、数据流与本地文件 |
| [Token 计算](docs/calculation-spec.md) | 去重、聚合、费用和预测公式 |
| [开发与发布](docs/development.md) | 工程、测试、打包与审计 |
| [验证记录](VERIFICATION.md) | 当前版本的测试与产物 |
| [安全说明](SECURITY.md) | 凭据边界与漏洞报告 |

## 开发者

**Zijiu522**

## 许可

本项目暂未声明开源许可证。第三方内容见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
