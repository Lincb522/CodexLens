# 项目文档

[返回仓库首页](../README.md)

| 文档 | 适合查看的内容 |
| --- | --- |
| [产品约束](../PRODUCT.md) | 首页显示什么、哪些数据不能混用、账号切换如何处理 |
| [界面规范](../DESIGN.md) | 固定尺寸、信息层级、颜色、文字、图标和动画 |
| [系统结构](architecture.md) | AppKit / SwiftUI 边界、服务组件、数据流和本地文件 |
| [Token 计算](calculation-spec.md) | 当前请求、当前轮次、任务累计、费用与额度预测 |
| [开发与发布](development.md) | 生成工程、测试、打包、本地化、图标和审计脚本 |
| [验证记录](../VERIFICATION.md) | 当前版本的测试结果、Release 检查和文件哈希 |
| [参与开发](../CONTRIBUTING.md) | 本地准备和提交要求 |
| [安全说明](../SECURITY.md) | 凭据处理与漏洞报告 |
| [版本记录](../CHANGELOG.md) | 各版本的功能和计算变化 |
| [第三方内容](../THIRD_PARTY_NOTICES.md) | Tibo Watch 来源与许可 |

## 代码入口

| 位置 | 内容 |
| --- | --- |
| `Sources/CodexTokenLedger/Views` | 菜单界面 |
| `Sources/CodexTokenLedger/ViewModels` | 界面状态与服务调度 |
| `Sources/CodexTokenLedger/Services` | rollout、账号、费用、额度与 Tibo |
| `Sources/CodexTokenLedger/Models` | 数据模型与偏好设置 |
| `Tests/CodexTokenLedgerTests` | 单元测试与界面夹具 |
| `scripts` | 构建、打包、图标和审计脚本 |
