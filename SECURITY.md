# 安全说明

[仓库首页](README.md) · [文档索引](docs/README.md)

## 报告漏洞

请使用仓库的私密安全报告功能，不要把以下内容放进公开 Issue、截图、日志或复现文件：

- access token、refresh token、ID token
- OpenAI API Key
- 完整 `auth.json`
- Cookie 或 Authorization Header
- 真实账号导出或包含凭据的 Codex Home

报告中请写明受影响版本、复现步骤、预期结果和实际结果。日志只保留复现所需字段，并先移除敏感值。维护者：Zijiu522。

## 凭据处理

- 账号读取由本机 Codex CLI 使用原有凭据源完成。
- 缓存、导出和日志不保存原始凭据。
- 导入凭据写入隔离 Codex Home 的 `auth.json`。
- 隔离目录权限为 `0700`，凭据文件权限为 `0600`。
- 只有“登录到 Codex”会替换默认登录，替换前先创建本地备份。
- 真实凭据不得进入测试夹具、示例文件或 Git 历史。

账号 RPC 审计会让本机 Codex 使用正常凭据源。只在已经检查过的代码状态下手动运行。
