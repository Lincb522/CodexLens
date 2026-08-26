# Codex Token Ledger

Codex Token Ledger 是一款 macOS 菜单栏应用，界面名称为 **Token Pulse**。它读取 Codex 已记录的计量事件和本机 `app-server` 数据，分别展示实时对话上下文、任务累计 Token、账号用量、额度窗口与 API 等价成本。

<p align="center">
  <img src="docs/images/overview-light.png" width="340" alt="Token Pulse 概览">
  <img src="docs/images/token-details-light.png" width="340" alt="Token 明细">
</p>

## 主要功能

- **实时上下文**：显示当前任务最新一次模型请求的上下文输入，不把任务累计值当成上下文大小。
- **多任务监控**：发现全部未完成任务，并可在菜单内切换当前任务。
- **三种统计口径**：当前请求、当前轮次、任务累计分别显示输入、缓存输入和输出。
- **本地账本**：扫描当前 Codex Home 的 `sessions` 与可选 `archived_sessions`，按任务分页查看真实累计计数。
- **账号用量与额度**：通过本机 Codex `app-server` 读取账号累计 Token、额度窗口、重置时间和积分字段。
- **多账号**：支持 OAuth、Codex Home、原始 Token、`auth.json`、通用 JSON/JSONL、Sub2、CPA/CLIProxyAPI 与 Cockpit；切换时可选择仅监控或同步登录 Codex。
- **剩余时间预测**：只根据同一账号、同一额度窗口的真实历史样本推算，不使用 Token 猜测订阅额度。
- **费用估算**：使用完整 Token 拆分和内置 API 费率快照计算 API 等价成本；缺字段或缺费率时显示不可用。
- **Tibo 重置信号**：独立显示公开的全局重置信号，不与账号的 5 小时或每周额度重置混合。
- **本地化与主题**：支持简体中文、繁体中文、英语、日语、韩语、西班牙语和法语，以及浅色、深色和跟随系统。

## 数据口径

| 界面数据 | 来源 | 口径 |
| --- | --- | --- |
| 当前对话上下文 | rollout `last_token_usage` | Codex 事件原始计数 |
| 当前轮次 | 本轮严格增长的累计事件差值 | 确定性派生 |
| 任务累计 | 最新有效 `total_token_usage` | Codex 事件原始计数 |
| 本地对话总量 | 已索引会话的最终累计事件 | Codex 事件原始计数 |
| 账号累计与额度 | `account/usage/read`、`account/rateLimits/read` | Codex 本机服务返回值 |
| API 等价成本 | 完整计数 × 费率快照 | 估算 |
| 预计还能用多久 | 额度百分比历史斜率 | 估算 |

应用不根据消息字符数重新估算 Token，也不会为缺失的输入/输出字段补零。详细规则见 [Token、账号用量与费用计算规范](docs/calculation-spec.md)。

## 系统要求

- macOS 14 或更高版本
- Xcode 16 或更高版本
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 已安装并可运行的 Codex CLI（账号同步功能需要）

## 构建

```bash
git clone https://github.com/Lincb522/CodexTokenLedger.git
cd CodexTokenLedger
xcodegen generate
./scripts/build_app.sh
```

Release 应用位于：

```text
build/DerivedData/Build/Products/Release/CodexTokenLedger.app
```

生成本地 ad-hoc 签名的应用和 ZIP：

```bash
./scripts/package_release.sh
```

```text
dist/CodexTokenLedger.app
dist/CodexTokenLedger-menu-bar-macOS.zip
```

## 测试

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

测试覆盖 Token 事件解析、累计去重、并发任务、标题识别、账号 RPC、凭据导入、额度预测、请求级超长上下文费率、Tibo 状态机、i18n 和菜单界面约束。

## 使用

1. 启动应用；它只出现在 macOS 菜单栏，不创建 Dock 图标或主窗口。
2. 点击菜单栏读数查看当前任务的上下文输入。
3. 在顶部任务选择区切换正在运行的 Codex 任务。
4. 展开 Token 明细，查看当前请求、当前轮次和任务累计的完整计数及单位。
5. 进入控制中心配置刷新频率、任务发现、账号、数据目录、语言和主题。
6. 添加账号时明确选择“仅监控”或“登录到 Codex”。

## 隐私与凭据

- rollout 扫描只处理会话元数据和 `token_count` 事件，不保存聊天正文、reasoning 文本或工具输出。
- 账号同步以 `read-only` 沙盒和 `never` approval 启动本机 Codex `app-server`。
- 原始 Token 只进入隔离账号目录中的原生 `auth.json`；目录权限为 `0700`，文件权限为 `0600`。
- 切换 Codex 登录前保存本地备份，并通过同目录临时文件原子替换 `auth.json`。
- 日志、缓存、导出和测试夹具不得包含 access token、refresh token、API key 或完整 `auth.json`。
- Tibo 监控是可关闭的唯一独立公开网络数据源；缓存只保留验证后的证据元数据与正文哈希。

安全边界和问题报告方式见 [SECURITY.md](SECURITY.md)。

## 文档

- [产品约束](PRODUCT.md)
- [界面设计规范](DESIGN.md)
- [系统架构](docs/architecture.md)
- [Token 与费用计算规范](docs/calculation-spec.md)
- [开发与发布](docs/development.md)
- [贡献指南](CONTRIBUTING.md)
- [版本记录](CHANGELOG.md)
- [验证记录](VERIFICATION.md)
- [第三方许可](THIRD_PARTY_NOTICES.md)

## 开发者

Zijiu522

## 许可

本仓库当前未声明项目级开源许可证。第三方代码和规则的许可信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
