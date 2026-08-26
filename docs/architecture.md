# 系统结构

## 进程与界面

应用以 `LSUIElement` 运行。`CodexTokenLedgerApp` 启动后，由 `NativeMenuBarController` 创建菜单：

```text
NSStatusItem
└── NSMenu
    └── NSMenuItem.view
        └── NSHostingView<MenuBarDashboardView>
```

AppKit 负责菜单窗口、材质和尺寸，SwiftUI 负责内容。应用没有主窗口或 Dock 图标。

## 组件

```text
NativeMenuBarController
├── 菜单生命周期、状态栏、主题、尺寸
└── DashboardViewModel
    ├── CodexLiveContextMonitor / CodexLiveContextReader
    ├── CodexSessionScanner / CodexThreadMetadataReader
    ├── CodexAccountService
    ├── CodexCredentialImportAdapter / CodexCredentialStore
    ├── BillingCalculator / PricingCatalog
    ├── QuotaForecastEngine / QuotaUsageHistoryStore
    ├── TiboResetSignalService / TiboResetSignalStore
    └── UsageCacheStore / CodexAccountUsageStore / UsageExporter
```

`DashboardViewModel` 持有界面状态并调用服务。文件发现由 `CodexLiveContextMonitor` actor 串行处理；视图不直接访问文件、网络或凭据。

## 数据流

### 当前任务

1. 在 `$CODEX_HOME/sessions` 中发现未完成的 JSONL。
2. 读取 `task_started`、`task_complete`、`turn_context` 和 `token_count`。
3. 用最新 `last_token_usage` 更新当前请求。
4. 对严格增长的 `total_token_usage` 求差，得到本轮调用。
5. 将活动任务交给 `DashboardViewModel` 排序和选择。

### 本地历史

1. 扫描 `sessions`，按设置决定是否扫描 `archived_sessions`。
2. 每个现代会话只采用最后一个有效累计事件。
3. 旧格式事件按会话和计数指纹去重。
4. 文件索引写入 `UsageCacheStore`，未变化的文件不重复完整分析。

### 账号

1. 每个账号使用独立 Codex Home。
2. `CodexAccountService` 启动 `codex -s read-only -a never app-server`。
3. 调用 `account/read`、`account/rateLimits/read`，以及可用时的 `account/usage/read`。
4. 返回值转成 `CodexAccountUsageSnapshot`；缓存不保存原始凭据。

### 导入与切换

1. `CodexCredentialImportAdapter` 识别 Token、API Key 和受支持的 JSON 结构。
2. 转为 Codex 原生 `auth.json`。
3. `CodexCredentialStore` 校验后写入隔离账号目录。
4. “仅监控”不改动默认 Codex Home。
5. “登录到 Codex”先备份原凭据，再通过同目录临时文件原子替换。

## 数据等级

| 枚举 | 数据 |
| --- | --- |
| `codexEventExact` | rollout 原始计数 |
| `codexServerOfficial` | Codex 本机服务返回值 |
| `derivedFromExactCounters` | 对原始计数去重、求差或聚合 |
| `officialRateEstimate` | Token 明细按费率折算 |
| `unavailable` | 证据不足 |

显示层不能把 `unavailable` 改成零。

## 本地文件

根目录：

```text
~/Library/Application Support/CodexTokenLedger/
```

| 内容 | 位置 |
| --- | --- |
| 界面设置 | `UserDefaults` |
| 会话索引 | `usage-index-v1.json` |
| 账号快照 | `account-usage-v1.json` |
| 额度样本 | `quota-observations-v1.json` |
| Tibo 元数据 | `tibo-reset-signal.json` |
| 隔离账号 | `Accounts/**/.codex/auth.json` |
| 登录备份 | `CredentialBackups/**/.codex/auth.json` |

默认 Codex Home 为 `$CODEX_HOME`；未设置时使用 `~/.codex`。

## 外部边界

运行时不包含第三方 Swift 包。应用只连接：

- 本机 Codex CLI 与 Codex Home
- 可选的 Tibo 公共数据源
- macOS 系统框架

Xcode 工程由 `project.yml` 通过 XcodeGen 生成。
