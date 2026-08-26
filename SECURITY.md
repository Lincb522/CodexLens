# Security

## 支持范围

安全修复以当前 `main` 分支和最新发布版本为准。

## 报告问题

如果仓库托管平台支持私密安全报告，请使用 Private Vulnerability Reporting。不要在公开 Issue、截图、日志或复现文件中提交：

- access token、refresh token、id token；
- OpenAI API key；
- 完整 `auth.json`；
- Cookie、Authorization Header；
- 真实账号导出或包含凭据的 Codex Home。

报告应包含受影响版本、可复现步骤、预期与实际行为，以及已经移除敏感值的最小日志。当前维护者：Zijiu522。

## 凭据边界

- 正常账号读取由本机 Codex CLI 使用其原有凭据源完成。
- 应用缓存、导出和日志不保存原始凭据。
- 导入的凭据只写入隔离 Codex Home 的 `auth.json`。
- 隔离目录权限为 `0700`，凭据文件权限为 `0600`。
- 默认 Codex 登录仅在用户明确选择“登录到 Codex”时改变；改变前会创建本地备份。
- 禁止把真实凭据加入测试夹具、快照、示例文件或 Git 历史。

## 开发环境

不要在会接触真实凭据的环境中运行未经审查的构建阶段、脚本或依赖。账号 RPC 审计会让本机 Codex 使用正常凭据源，因此只应在可信代码状态下手动运行。
