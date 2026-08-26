# 系统架构

## 运行形态

Codex Token Ledger 是 `LSUIElement` 菜单栏应用。入口 `CodexTokenLedgerApp` 将应用设为 accessory，`NativeMenuBarController` 创建：

```text
NSStatusItem
└── NSMenu
    └── NSMenuItem.view
        └── NSHostingView<MenuBarDashboardView>
```

AppKit 管理菜单窗口和系统毛玻璃；SwiftUI 根视图保持透明。应用没有主窗口或 Dock 图标。

## 组件边界

```text
NativeMenuBarController
├── 菜单栏状态、菜单生命周期、主题和尺寸
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

`DashboardViewModel` 是界面状态和服务调用的统一所有者。实时文件发现由 `CodexLiveContextMonitor` actor 串行化；SwiftUI 视图不直接执行文件、网络或凭据操作。

## 数据流

### 实时上下文

1. `CodexLiveContextMonitor` 在 `$CODEX_HOME/sessions` 中发现进行中的 JSONL。
2. `CodexLiveContextReader` 读取 `task_started`、`task_complete`、`turn_context` 和 `token_count`。
3. 最新 `last_token_usage` 形成当前请求上下文。
4. 严格增长的 `total_token_usage` 快照相减，形成当前轮次调用记录。
5. `DashboardViewModel` 选择当前任务并更新菜单栏与详情。

### 本地账本

1. `CodexSessionScanner` 扫描 `sessions`，可选扫描 `archived_sessions`。
2. 每个现代会话只采用最后一个有效累计事件。
3. 旧事件按会话和计数指纹去重。
4. `UsageCacheStore` 保存文件索引，未变化的 JSONL 不重复完整分析。

### 账号与额度

1. `CodexAccountService` 使用指定账号目录作为 `CODEX_HOME`。
2. 它以 `codex -s read-only -a never app-server` 启动本机进程。
3. JSON Line RPC 依次调用 `account/read`、`account/rateLimits/read` 和可用时的 `account/usage/read`。
4. 返回值规范化为 `CodexAccountUsageSnapshot`，缓存中不保存原始凭据。

### 凭据导入与切换

1. `CodexCredentialImportAdapter` 识别原始 Token、API key 和受支持 JSON 结构。
2. 结果规范化为 Codex 原生 `auth.json`。
3. `CodexCredentialStore` 校验大小和结构后写入隔离账号目录。
4. 用户选择“登录到 Codex”时，应用先备份当前凭据，再原子替换默认 Codex Home 的 `auth.json`。
5. 用户选择“仅监控”时，默认 Codex 登录保持不变。

## 证据等级

`UsageEvidence` 将数值分为：

| 等级 | 含义 |
| --- | --- |
| `codexEventExact` | Codex rollout 原始计数 |
| `codexServerOfficial` | 本机 Codex 服务返回值 |
| `derivedFromExactCounters` | 对原始计数去重、相减或聚合 |
| `officialRateEstimate` | 计数乘费率快照的等价成本 |
| `unavailable` | 缺少形成完整结果所需的证据 |

未知值保持不可用；不能由显示层把未知值改成零。

## 持久化

默认数据目录为：

```text
~/Library/Application Support/CodexTokenLedger/
```

| 内容 | 路径或存储 |
| --- | --- |
| 界面偏好、目录选择、刷新频率 | `UserDefaults` |
| 会话索引 | `usage-index-v1.json` |
| 账号统计快照 | `account-usage-v1.json` |
| 额度历史样本 | `quota-observations-v1.json` |
| Tibo 证据元数据 | `tibo-reset-signal.json` |
| 隔离账号 | `Accounts/**/.codex/auth.json` |
| 登录切换备份 | `CredentialBackups/**/.codex/auth.json` |

默认 Codex Home 为 `$CODEX_HOME`，未设置时使用 `~/.codex`。

## UI 约束

- 概览、本地账本和控制中心固定为 340×705pt。
- 不使用 `ScrollView`；长列表使用显式分页。
- 可见字号不小于 12pt；标签不换行、不缩放。
- 展开 Token 详情是现有窗口内的浮层，不改变 `NSMenu` 固有尺寸。
- 大型精确计数使用“标签在左、数值在右”的独立行，避免三列数据碰撞。
- 主题和语言由同一 `DashboardViewModel` 状态驱动。

## 外部依赖

运行时不包含第三方 Swift 包。外部边界只有：

- 本机 Codex CLI 与其 Codex Home；
- 可选的 Tibo 公开动态数据源；
- macOS 系统框架。

Xcode 工程由 `project.yml` 通过 XcodeGen 生成。
