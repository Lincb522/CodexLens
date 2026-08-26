# Token、账号用量与费用计算规范

## 1. 证据等级

应用只展示以下四种口径：

1. **Codex Event · Exact**：Codex rollout 中的原始 `token_count`。
2. **Codex Server · Official**：本机 Codex `app-server` 返回的账号统计与额度。
3. **Derived from Exact**：对实测计数做去重、相减或相加的确定性结果。
4. **Official Rate · Estimate**：实测 Token 乘官方 API 费率所得的可复算等价成本。

字段不存在、结构不合法、模型未定价或聚合不完整时返回 unavailable，而不是用经验比例、字符数或零值填补。

## 2. 实时上下文

每 2 秒刷新已发现 rollout，每 10 秒重新发现任务。读取器比较最后一个 `task_started` 与 `task_complete` 的文件位置，只把未完成任务放入活动集合。

选中任务的最新模型调用来自：

```text
info.last_token_usage.input_tokens
info.last_token_usage.cached_input_tokens
info.last_token_usage.cache_write_input_tokens
info.last_token_usage.output_tokens
info.last_token_usage.reasoning_output_tokens
info.last_token_usage.total_tokens
info.model_context_window
```

```text
context_input = last_token_usage.input_tokens
published_window(GPT-5.6 Sol/Terra/Luna) = 1,050,000
context_used_percent = context_input / published_window × 100
context_remaining = max(0, published_window - context_input)
```

`input_tokens` 是 Codex 对实际模型输入的计数，覆盖系统指令、保留上下文、工具结果和文件/图片等输入。它不是对可见聊天文字重新 tokenizer，也不包含该次请求随后生成的输出。

`model_context_window` 是当前 turn 的 Codex runtime 证据，可能与公开模型容量不同。界面分别显示两者，不用其中一个覆盖另一个。

## 3. 当前整轮聚合与去重

一轮任务可能因工具调用产生多个模型请求。应用从最新 `task_started` 开始维护上一条有效累计计数：

```text
if current_total == previous_total:
    ignore_duplicate
elif current_total structurally >= previous_total:
    call_usage = current_total - previous_total
    current_turn += call_usage
    previous_total = current_total
else:
    ignore_stale_or_regressed_event
```

累计回退不会移动基准，避免后续事件被重复计算。每个被接受的差值保留模型、时间和用量，因此实时费用可以按单次模型调用应用请求级费率规则。

三个显示口径互不替代：

- `last_token_usage`：最新模型调用；
- `current_turn_usage`：本轮全部已接受调用；
- 最新 `total_token_usage`：整个任务累计。

## 4. Token 结构校验

每条计数在进入引擎前必须满足：

```text
all counters >= 0
cached_input + cache_write_input <= input
reasoning_output <= output
reported_total >= input + output
```

```text
uncached_input = input - cached_input - cache_write_input
component_total = input + output
```

`reasoning_output_tokens` 是 `output_tokens` 的解释性子集，不再加入总 Token 或费用。

部分旧事件只有可信 `total_tokens`，而输入/输出字段为零。此时：

- Token 总量采用 `reported_total`；
- `hasCompleteBreakdown = false`；
- 不猜测输入/输出比例；
- 不计算 API 等价成本。

## 5. 本地对话总 Token

扫描范围为当前 Codex Home 的 `sessions` 和可选 `archived_sessions`。

现代会话使用最后一个有效 `total_token_usage` 作为会话总量，每个会话只生成一个累计记录。旧格式没有累计计数时，回退到去重后的 `last_token_usage` 增量。

归档迁移可能复制同一事件，旧格式使用以下指纹去重：

```text
session_id + timestamp + model + input + cached_input + output + total
```

“本地对话总 Token”是所有已索引会话的精确总和，不套用隐藏日期筛选。快速索引只物化计量元数据，不读取或保存消息正文。

## 6. 账号官方 Token 与额度

每个账号通过其独立 Codex Home 启动只读 `app-server`：

- `account/read`：账号邮箱、套餐；
- `account/usage/read`：`summary.lifetimeTokens`、`dailyUsageBuckets[].startDate/tokens`；
- `account/rateLimits/read`：额度窗口 `usedPercent`、`windowDurationMins`、`resetsAt` 与服务端积分余额。

账号累计 Token 直接显示 `lifetimeTokens`。每日桶连同真实 `startDate` 显示，不假设最后一个桶必然等于用户本地时区的今天。

旧本地 rollout 不能可靠归属于后来切换的账号，因此本地对话总 Token 与账号官方累计 Token 分开展示。

## 7. “还能用多久”预测

预测数据只来自本机持续保存的真实额度百分比样本：

```text
sample = account_id
       + window_id
       + observed_at
       + used_percent
       + resets_at
       + window_minutes
```

只保留同账号、同窗口、同一重置时间（误差不超过 300 秒）且没有超过窗口时长的样本。1 秒内的重复样本覆盖，单窗口最多使用最近 64 个样本。

进入预测至少需要：

```text
sample_count >= 2
observation_span >= 120 seconds
observed_delta >= 0.10 percentage points
```

对所有间隔不少于 120 秒、额度百分比正向增长的样本对计算：

```text
slope_i = Δused_percent / Δseconds × 3600
rate = median(all positive slope_i)
time_to_exhaustion = remaining_percent / rate × 3600
```

再把 `time_to_exhaustion` 与服务端 `resetsAt - now` 比较，输出“重置前够用”或“预计提前耗尽”。没有持续增长时输出“未观察到持续消耗”，样本不足时输出“正在收集”。

置信度规则：

- 高：至少 8 个样本、2 小时跨度、5 个百分点变化；
- 中：至少 4 个样本、30 分钟跨度、1 个百分点变化；
- 其他：低。

该预测不使用 Token 数推断订阅额度，因为没有公开固定的 Token→ChatGPT/Codex 额度映射。

## 8. Tibo 公共重置信号

Tibo 信号是面向所有 Codex 用户的临时全局人工重置公告。它不是任何单一账号的 5 小时额度、每周额度或其他服务端周期重置，也不属于 Token、账号用量、额度预测或费用计算输入。应用最多每 5 分钟读取一次公开动态源，并只接受：

```text
author.screen_name == "thsottiaux"
type == "status"
source host in {x.com, twitter.com}
posted_at within [now - 14 days, now + 5 minutes]
text matches a versioned deterministic rule
```

状态分为候选、结构化预测和已确认，但规则模式不会仅凭 `tomorrow`、`soon` 等关键词生成精确预测时间：没有可审计的 `expectedStart/expectedEnd` 时仍保持候选。缓存不保存正文，只保存动态 ID、来源 URL、发布时间、状态、可选结构化时间窗口、重置类型、命中规则、规则版本与正文 SHA-256。滚动接口结果会与现有元数据按动态 ID 合并并最多保留 128 条，使旧确认事实继续充当周期锚点；来源失败时保留最近的有效证据并将来源状态改为 degraded/offline。

周期派生规则与 Tibo Watch 一致：

```text
lastConfirmedAt = latest non-banked confirmed post timestamp
lastObservedResetAt = max(lastConfirmedAt, reached structured prediction start)
baselineNextResetAt = lastObservedResetAt + 7 days
activePrediction = latest expected event posted after lastConfirmedAt
displayedNextResetAt = activePrediction.start ?? baselineNextResetAt
```

结构化预测到时但没有确认帖时，基线必须标记为“推定”；确认帖出现后使用其真实发布时间重新锚定，并清除发布于该确认之前的已兑现预测。banked reset 不参与公共强制重置基线。

动态的 `postedAt` 与结构化窗口作为绝对时刻保存；展示时使用 macOS 当前自动更新时区重新格式化，不会把源站 UTC 字符串直接当成本地时间。紧凑周期页使用本地日期时间；详细证据格式化器仍可附带明确 UTC 偏移（包括夏令时与半小时时区）。

该信号不会更改 `usedPercent`、`resetsAt`、消耗斜率、耗尽时间或任何费用结果；官方服务端与本机实测数据仍是数值计算的唯一输入。

## 9. API 等价成本

文本费率单位均为 USD / 1,000,000 Token：

```text
cost = uncached_input / 1M × input_rate
     + cached_input / 1M × cached_input_rate
     + cache_write_input / 1M × cache_write_rate
     + output / 1M × output_rate
```

GPT-5.6 Sol / Terra / Luna 当前内置官方费率：

| 模型 | 输入 | 缓存输入 | 输出 |
| --- | ---: | ---: | ---: |
| Sol | $4.00 | $0.40 | $20.00 |
| Terra | $2.00 | $0.20 | $12.00 |
| Luna | $0.20 | $0.02 | $1.20 |

缓存写入按未缓存输入的 1.25×。单次请求输入超过 272,000 Token 时，整次请求输入侧乘 2、输出侧乘 1.5。阈值判断是严格的 `input_tokens > 272_000`，并且只能按单次请求应用。

实时本轮保留请求边界，因此逐调用计算再求和。历史累计会话没有请求边界，只按标准费率给出 API 等价估算，不臆测超长倍率。

任何调用缺少完整拆分或官方模型费率时，该调用与包含它的聚合成本都返回 unavailable；引擎不会静默忽略未知记录后给出“部分总价”。应用不再提供 Token→ChatGPT 积分估算。

## 10. 标题来源

标题优先级：

```text
Desktop local_thread_catalog.display_title
→ threads.name
→ threads.title
→ first_user_message
→ preview
→ working-directory basename
```

标题来源徽标通过 String Catalog 本地化，工作目录继续作为项目副标题。

## 11. 明确边界

- 图片、Web 搜索、Computer Use 等按调用计费项目不在文本 Token 公式内。
- 历史累计会话无法恢复已经丢失的逐请求边界或会话内模型切换细节。
- 最终 API 发票、订阅包含额度、企业折扣和服务端风控以 OpenAI 账号系统为准。
- 费率是带日期的本地快照；未知或未来模型显示 unavailable，直到更新官方费率。
