# Token 计算

[← README](../README.md) · [文档](README.md)

---

[数据类型](#数据类型) · [当前上下文](#当前上下文) · [当前轮次](#当前轮次) · [结构校验](#结构校验) · [本地历史](#本地历史) · [账号与额度](#账号用量与额度) · [剩余时间](#剩余时间) · [费用](#api-参考成本) · [Tibo](#tibo-公共信号) · [任务标题](#任务标题)

## 数据类型

| 类型 | 含义 |
| --- | --- |
| 精确事件 | rollout 中的 `token_count` |
| 官方账号数据 | Codex `app-server` 返回的账号用量与额度 |
| 确定性计算 | 对精确事件去重、求差或汇总 |
| 费用估算 | 精确 Token 明细按内置 API 费率折算 |

字段缺失、结构不合法、模型没有费率或聚合不完整时，结果为 `unavailable`。应用不根据字符数估算 Token，也不会用零补齐缺失字段。

## 当前上下文

活动任务来自 `$CODEX_HOME/sessions`。读取器比较最后一个 `task_started` 与 `task_complete` 的位置，只保留尚未完成的任务。

最近一次请求读取：

```text
info.last_token_usage.input_tokens
info.last_token_usage.cached_input_tokens
info.last_token_usage.cache_write_input_tokens
info.last_token_usage.output_tokens
info.last_token_usage.reasoning_output_tokens
info.last_token_usage.total_tokens
info.model_context_window
```

首页主数为：

```text
context_input = last_token_usage.input_tokens
used_percent = context_input / published_window × 100
remaining = max(0, published_window - context_input)
```

GPT-5.6 Sol、Terra 和 Luna 的内置公开容量为 1,050,000 Token。`model_context_window` 是 Codex 为当前 turn 记录的运行窗口，两者在界面中分开显示。

`input_tokens` 是模型实际收到的输入，可能包含系统指令、保留上下文、工具结果、文件和图片。它不等于可见聊天文字，也不包含随后生成的输出。

## 当前轮次

工具调用可能让一个 turn 内出现多次模型请求。每次收到累计事件时按以下规则处理：

```text
current == previous       → 不增加 Token；完整明细可修正同一累计点的输入/缓存/输出拆分
current >= previous       → 接受差值并更新 previous
current < previous        → 回退或旧事件，忽略
```

累计回退不会移动基准。每个有效差值保留模型、时间和 Token 明细，费用可以按单次请求计算。

界面中的三个范围分别是：

- 当前请求：最新 `last_token_usage`
- 当前轮次：本轮所有有效请求之和
- 任务累计：最新 `total_token_usage`

## 结构校验

一条完整计数需要满足：

```text
所有字段 >= 0
cached_input + cache_write_input <= input
reasoning_output <= output
reported_total >= input + output
```

派生值：

```text
uncached_input = input - cached_input - cache_write_input
component_total = input + output
```

`reasoning_output_tokens` 已包含在 `output_tokens` 中，不重复相加。

部分旧事件只有可信的 `total_tokens`。这类记录可计入 Token 总量，但不能拆分输入输出，也不计算费用。

## 本地历史

扫描范围为当前 Codex Home 的 `sessions`，以及用户开启后扫描的 `archived_sessions`。

现代会话使用最后一个有效 `total_token_usage`。旧格式没有累计计数时，使用去重后的 `last_token_usage` 增量。旧事件的去重指纹为：

```text
session_id + timestamp + model + input + cached_input + output + total
```

同一会话同时出现在 `archived_sessions` 和 `sessions` 时，优先采用累计 Token 更大的记录；累计值相同则采用时间更新的记录。存在现代累计计数时，只叠加确实晚于该累计点的旧格式事件。

本地历史是已索引会话的总和，不归属到后来切换的账号。索引只保存计量元数据，不保存消息正文。

## 账号用量与额度

每个账号通过独立 Codex Home 启动只读 `app-server`：

| RPC | 使用字段 |
| --- | --- |
| `account/read` | 邮箱、套餐 |
| `account/usage/read` | `summary.lifetimeTokens`、每日用量桶 |
| `account/rateLimits/read` | `usedPercent`、窗口长度、`resetsAt`、积分 |

账号累计直接使用 `lifetimeTokens`。每日桶按服务端给出的日期显示，不假设最后一项就是用户本地的今天。

### 账号额度的 API 等价值

账号当前剩余百分比和重置时间来自 `account/rateLimits/read`。满额价值不从本地任务、项目或账号历史反推，而使用 2026 年 8 月公开的独立实测基线：

| 套餐 | 每周 API 等价值 | 实测区间 |
| --- | ---: | ---: |
| Plus | US$105 | US$94–113 |
| Pro 5× | US$537.50 | US$525–550 |
| Pro 20× | US$2,144 | US$2,080–2,240 |

Pro 20× 基线来自单一账号、GPT-5.6 Sol Standard、两个独立额度周期的交叉测量。中央值为每周 53,600 credits；按当时 25 credits = US$1 的费率换算为 US$2,144。来源：<https://www.reddit.com/r/codex/comments/1v6ubah/realworld_codex_pro_20x_plan_test_with_gpt56_sol/>。

```text
current_api_equivalent = weekly_api_equivalent × official_remaining_percent / 100
monthly_api_equivalent = weekly_api_equivalent × 365.2425 / 12 / 7
```

月度值按平均公历月折算。Token 数取决于模型以及输入、缓存输入和输出的组成，应用不再把额度显示成一个缺少确定含义的固定 Token 总数。实测值是第三方参考，不是 OpenAI 的额度承诺。

## 剩余时间

样本由以下字段组成：

```text
account_id
window_id
observed_at
used_percent
resets_at
window_minutes
```

只比较同一账号、同一窗口、同一重置时间的样本。重置时间允许 300 秒误差；单窗口最多保留最近 64 个样本。

开始计算至少需要：

```text
2 个样本
观察跨度 120 秒
额度变化 0.10 个百分点
```

对间隔不少于 120 秒且额度持续增长的样本对计算每小时变化率，取中位数：

```text
rate = median(Δused_percent / Δseconds × 3600)
time_to_exhaustion = remaining_percent / rate × 3600
```

再与 `resetsAt - now` 比较，判断重置前是否会耗尽。样本不足显示“正在收集”，没有持续增长显示“未观察到持续消耗”。

置信度：

| 等级 | 条件 |
| --- | --- |
| 高 | 8 个样本、2 小时跨度、5 个百分点变化 |
| 中 | 4 个样本、30 分钟跨度、1 个百分点变化 |
| 低 | 已满足最低计算条件，但未达到以上条件 |

剩余时间只使用官方额度百分比的变化率；总额度 Token 估算单独显示，不参与耗尽时间判断。

## API 参考成本

费率单位为 USD / 1,000,000 Token：

```text
cost = uncached_input / 1M × input_rate
     + cached_input / 1M × cached_input_rate
     + cache_write_input / 1M × cache_write_rate
     + output / 1M × output_rate
```

内置费率：

| 模型 | 输入 | 缓存输入 | 输出 |
| --- | ---: | ---: | ---: |
| GPT-5.6 Sol | $4.00 | $0.40 | $20.00 |
| GPT-5.6 Terra | $2.00 | $0.20 | $12.00 |
| GPT-5.6 Luna | $0.20 | $0.02 | $1.20 |
| GPT-5.5 | $5.00 | $0.50 | $30.00 |
| Daybreak Blue | $4.00 | $0.40 | $20.00 |
| Daybreak Red | $12.50 | $1.25 | $75.00 |
| GPT-5.4 | $2.50 | $0.25 | $15.00 |
| GPT-5.4 Mini | $0.75 | $0.075 | $4.50 |
| GPT-5.3 Codex | $1.75 | $0.175 | $14.00 |
| GPT-5.2 | $1.75 | $0.175 | $14.00 |

缓存写入按未缓存输入费率的 1.25 倍计算。单次请求输入严格大于 272,000 Token 时，该请求输入侧乘 2，输出侧乘 1.5。

当前请求和当前轮次保留请求边界，所以逐请求选择费率后相加。详情中的“对话累计”直接使用当前会话的累计 Token 拆分；累计事件没有完整请求边界，因此按标准费率估算。历史项目同样只按标准费率计算。任一记录缺少完整拆分或模型费率时，包含它的聚合费用为 `unavailable`。

图片、Web Search、Computer Use 等非文本计费项不包含在公式内。最终账单、订阅包含额度、企业折扣和服务端规则以账号系统为准。

## Tibo 公共信号

Tibo 信号不参与 Token、账号额度、剩余时间或费用计算。它只接受满足以下条件的公开动态：

```text
author.screen_name == "thsottiaux"
type == "status"
source host in {x.com, twitter.com}
发布时间位于 now - 14 days 到 now + 5 minutes
正文命中已版本化规则
```

数据同时取自 Tibo 的公开动态时间线和独立公共预测接口。两路都可用时合并；一路失败或数据过期时标记为降级，不把旧结果伪装成新信号。

状态分为：

| 状态 | 含义 |
| --- | --- |
| 候选 | 提到了重置，但没有可验证时间 |
| 预测 | 暗示性文字推导出的有界时间窗口 |
| 已公布 | 动态明确给出了计划时间 |
| 已确认 | 动态明确表示重置已经传播或完成 |

相对时间按 Tibo 所在的 `America/Los_Angeles` 日历解释。例如 “Soon, but not today” 只生成当地下一自然日的预测窗口，不生成具体时刻。较高证据等级不能被后来的低等级解析覆盖。

周期计算：

```text
lastConfirmedAt = 最近一次非 banked 的确认时间
lastObservedResetAt = lastConfirmedAt
displayedNextResetAt = 有效“预测”或“已公布”窗口的开始时间
```

预测窗口到达不会自动变成“已确认”。只有确认动态才更新最近重置事实，并清除该确认之前的预测。Tibo 重置与账号 5 小时/周额度重置分别显示；确认后不会凭空生成下一周时间。缓存只保存动态 ID、URL、时间、状态、规则和正文 SHA-256，不保存正文。

## 任务标题

标题按以下顺序选择：

```text
Desktop local_thread_catalog.display_title
→ threads.name
→ threads.title
→ first_user_message
→ preview
→ working-directory basename
```
