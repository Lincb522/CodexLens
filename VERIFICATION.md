# 验证记录

[← README](README.md) · [文档](docs/README.md)

---

版本：**2.5.1 (43)**

日期：**2026-09-06**

## 测试

Xcode 26.4，运行环境为 Intel macOS 26.3。145 项测试中，144 项通过，1 项按需开启的 Tibo 在线审计跳过，0 项失败。

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

本次覆盖：

- Token 完整数值与 K / M / B / T 简写、七种语言、整数边界
- 显示偏好保存与恢复、菜单栏即时切换，原始统计保持不变
- 热力格日期与当天用量、UTC 跨日、跨月、闰年及自选日期范围
- 完整使用记录不受首页筛选影响，单日跳转定位正确
- 原有 Token 去重、累计、账号 RPC、额度和 Tibo 回归

## 界面

本次检查的是 `NSHostingView` 测试渲染：

- 主窗口仍为 340 × 680pt，固定底部导航
- 340/420pt 画布下的完整和简写模式、浅色和深色页面
- 热力图及范围编辑器的 280/300/380pt 布局
- 首页小格尺寸不变，长区间可横向滚动
- 完整数值汇总按行显示，数字、单位与底部导航不重叠
- 长数字、七种语言、加载、空状态和错误状态

窗口使用透明 `NSPanel` 与原生菜单材质。测试渲染不能验证真实桌面的毛玻璃合成；鼠标悬停、键盘、VoiceOver 和 macOS 14 运行尚未实测。

## 分发

[GitHub Release v2.5.1](https://github.com/Lincb522/CodexLens/releases/tag/v2.5.1) · [发布工作流](https://github.com/Lincb522/CodexLens/actions/workflows/release.yml)

`v*` tag 工作流测试后生成通用架构 DMG、ZIP、SHA-256 清单和 Sparkle 更新源。安装包使用 Developer ID 签名，tag 发布不提交 Apple 公证；具体状态见对应发布页。

下载后可验证：

```bash
shasum -a 256 -c SHA256SUMS.txt
unzip -t Codex-Lens-macOS.zip
hdiutil verify Codex-Lens-macOS.dmg
codesign --verify --deep --strict --verbose=2 "Codex Lens.app"
lipo -archs "Codex Lens.app/Contents/MacOS/Codex Lens"
```
